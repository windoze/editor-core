import AppKit
import EditorCoreUIFFI
import Foundation

@MainActor
public final class EditorCoreSkiaMinimapView: NSView {
    public let editorView: EditorCoreSkiaView
    public var editor: EditorUI { editorView.editor }

    /// Hard cap for detailed (per-line) minimap rendering.
    ///
    /// Above this threshold the minimap still shows the viewport indicator, but skips per-line
    /// content bars to avoid expensive JSON + decoding work.
    public var maxDetailedVisualLines: UInt32 = 5_000

    /// Maximum visual height (in view units) allotted to a single visual row in the minimap.
    ///
    /// When the document has only a few lines, scaling `totalRows -> bounds.height` makes the
    /// minimap look vertically stretched. This cap limits the per-row height and leaves the
    /// remaining space as background.
    ///
    /// Set to `<= 0` to disable capping (legacy behavior).
    public var maxLineHeightPx: CGFloat = 2

    /// Background color for the minimap area (including unused space when the content is shorter
    /// than the minimap height).
    public var backgroundColor: NSColor = .windowBackgroundColor

    private var viewportObserverToken: EditorCoreSkiaView.ViewportStateObserverToken?
    private var refreshPending: Bool = false
    private var minimapDirty: Bool = true

    private var cachedGrid: MinimapGridDTO?
    private var cachedViewportState: EcuViewportState?

    private struct ViewportDragState {
        var grabOffsetY: CGFloat
    }

    private var viewportDragState: ViewportDragState?

    public override var isFlipped: Bool { true }

    public init(editorView: EditorCoreSkiaView) {
        self.editorView = editorView
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        viewportObserverToken = editorView.addViewportStateObserver { [weak self] in
            guard let self else { return }
            self.minimapDirty = true
            self.needsDisplay = true
            self.scheduleRefresh()
        }
        scheduleRefresh()
    }

    @available(*, unavailable, message: "请使用 init(editorView:) 构造。")
    public override init(frame frameRect: NSRect) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(editorView:) 构造。")
    public required init?(coder: NSCoder) {
        fatalError("unavailable")
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background.
        backgroundColor.setFill()
        ctx.fill(bounds)

        // Ensure we have a recent viewport state; drawing can happen before the async refresh tick.
        if cachedViewportState == nil {
            cachedViewportState = try? editor.viewportState()
        }

        guard let vp = cachedViewportState else { return }

        let totalRows = CGFloat(max(1, vp.totalVisualLines))
        let heightPx = max(1, bounds.height)
        let widthPx = max(1, bounds.width)
        let (lineHeightPx, contentHeightPx) = minimapContentMetrics(totalRows: totalRows, heightPx: heightPx)

        if let grid = cachedGrid, vp.totalVisualLines <= maxDetailedVisualLines {
            // Render per-line density bars. We deliberately draw in pixel rows (1px height)
            // so large documents collapse naturally without needing extra downsampling logic.
            ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.25).cgColor)
            for (idx, line) in grid.lines.enumerated() {
                let visualRow = CGFloat(grid.startVisualRow) + CGFloat(idx)
                let y = floor(visualRow * lineHeightPx)
                if y < 0 || y >= contentHeightPx { continue }

                let totalCells = max(1, CGFloat(line.totalCells))
                let density = min(1, CGFloat(line.nonWhitespaceCells) / totalCells)
                let w = max(1, floor(widthPx * density))
                ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
            }
        } else {
            // Large-doc fallback: show a subtle placeholder so the minimap still feels "alive".
            ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.05).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        }

        // Viewport indicator (including smooth-scroll sub-row offset).
        let rect = viewportIndicatorRect(
            vp: vp,
            totalRows: totalRows,
            heightPx: heightPx,
            lineHeightPx: lineHeightPx,
            contentHeightPx: contentHeightPx
        )

        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.18).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.65).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    }

    public override func mouseDown(with event: NSEvent) {
        // Click/drag-to-scroll:
        // - 点击 viewport 指示框：进入拖拽模式（类似拖动滚动条 thumb）
        // - 点击其他区域：先跳转，再继续拖拽（grab 取指示框中心）
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.height > 0 else { return }

        do {
            let vp = try editor.viewportState()
            let totalRows = CGFloat(max(1, vp.totalVisualLines))
            let heightPx = max(1, bounds.height)
            let rect = viewportIndicatorRect(vp: vp, totalRows: totalRows, heightPx: heightPx)

            if rect.contains(p) {
                viewportDragState = ViewportDragState(grabOffsetY: p.y - rect.minY)
            } else {
                viewportDragState = ViewportDragState(grabOffsetY: rect.height * 0.5)
            }

            applyViewportDrag(at: p, vp: vp)
        } catch {
            viewportDragState = nil
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard viewportDragState != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        do {
            let vp = try editor.viewportState()
            applyViewportDrag(at: p, vp: vp)
        } catch {
            // best-effort
        }
    }

    public override func mouseUp(with event: NSEvent) {
        viewportDragState = nil
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        minimapDirty = true
        scheduleRefresh()
        needsDisplay = true
    }

    public override func viewDidHide() {
        super.viewDidHide()
        // 隐藏时释放详细缓存，避免后台无意义占用内存/CPU。
        cachedGrid = nil
        cachedViewportState = nil
    }

    private func scheduleRefresh() {
        guard refreshPending == false else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refreshNow()
        }
    }

    private func refreshNow() {
        // 如果 minimap 没有显示（或尚未布局出有效尺寸），跳过昂贵的 JSON 获取/解码。
        guard isHidden == false, bounds.width > 1, bounds.height > 1 else { return }
        guard minimapDirty else { return }
        minimapDirty = false

        do {
            let vp = try editor.viewportState()
            cachedViewportState = vp

            guard vp.totalVisualLines <= maxDetailedVisualLines else {
                cachedGrid = nil
                needsDisplay = true
                return
            }

            let json = try editor.minimapJSON(startVisualRow: 0, rowCount: max(1, vp.totalVisualLines))
            let grid = try MinimapGridDTO.decode(from: json)
            cachedGrid = grid
        } catch {
            cachedGrid = nil
        }
        needsDisplay = true
    }

    // MARK: - Testing hooks

    var _cachedGridForTesting: MinimapGridDTO? { cachedGrid }

    func _refreshNowForTesting() {
        minimapDirty = true
        refreshNow()
    }

    private func viewportIndicatorRect(vp: EcuViewportState, totalRows: CGFloat, heightPx: CGFloat) -> CGRect {
        let (lineHeightPx, contentHeightPx) = minimapContentMetrics(totalRows: totalRows, heightPx: heightPx)
        return viewportIndicatorRect(
            vp: vp,
            totalRows: totalRows,
            heightPx: heightPx,
            lineHeightPx: lineHeightPx,
            contentHeightPx: contentHeightPx
        )
    }

    private func viewportIndicatorRect(
        vp: EcuViewportState,
        totalRows: CGFloat,
        heightPx: CGFloat,
        lineHeightPx: CGFloat,
        contentHeightPx: CGFloat
    ) -> CGRect {
        _ = (totalRows, heightPx)

        guard contentHeightPx.isFinite, contentHeightPx > 0 else {
            return .zero
        }
        guard lineHeightPx.isFinite, lineHeightPx > 0 else {
            return CGRect(x: 0, y: 0, width: bounds.width, height: max(2, contentHeightPx))
        }

        let visibleRows = CGFloat(max(1, vp.heightRows ?? vp.totalVisualLines))
        let posRows = CGFloat(vp.scrollTop) + CGFloat(vp.subRowOffset) / 65536.0

        let rawTop = posRows * lineHeightPx
        let rawBottom = (posRows + visibleRows) * lineHeightPx
        let yTop = rawTop.clamped(to: 0...contentHeightPx)
        let yBottom = rawBottom.clamped(to: 0...contentHeightPx)

        let minH: CGFloat = 2
        let rawH = max(0, yBottom - yTop)
        let h = max(minH, min(rawH, contentHeightPx))
        let y = min(max(0, yTop), max(0, contentHeightPx - h))

        return CGRect(x: 0, y: y, width: bounds.width, height: h)
    }

    private func applyViewportDrag(at point: NSPoint, vp: EcuViewportState) {
        guard let drag = viewportDragState else { return }
        guard bounds.height > 0 else { return }

        let total = max(1.0, Double(vp.totalVisualLines))
        let visible = Double(max(1, vp.heightRows ?? vp.totalVisualLines))
        let maxScroll = max(0.0, total - visible)
        guard maxScroll > 0 else { return }

        let totalRows = CGFloat(max(1, vp.totalVisualLines))
        let heightPx = max(1, bounds.height)
        let (lineHeightPx, contentHeightPx) = minimapContentMetrics(totalRows: totalRows, heightPx: heightPx)
        let indicator = viewportIndicatorRect(
            vp: vp,
            totalRows: totalRows,
            heightPx: heightPx,
            lineHeightPx: lineHeightPx,
            contentHeightPx: contentHeightPx
        )

        guard lineHeightPx.isFinite, lineHeightPx > 0 else { return }
        let maxYTop = max(0, contentHeightPx - indicator.height)
        let yTop = (point.y - drag.grabOffsetY).clamped(to: 0...maxYTop)
        let posRows = Double(yTop / lineHeightPx)
        setSmoothScrollPosRows(posRows.clamped(to: 0.0...maxScroll))
    }

    private func setSmoothScrollPosRows(_ posRows: Double) {
        let top = floor(posRows).clamped(to: 0.0...Double(UInt32.max))
        let frac = (posRows - top).clamped(to: 0.0...0.999_999)
        let sub = UInt32((frac * 65536.0).rounded(.down)).clamped(to: 0...65535)

        editor.setSmoothScrollState(topVisualRow: UInt32(top), subRowOffset: sub)
        cachedViewportState = try? editor.viewportState()
        needsDisplay = true

        editorView.needsDisplay = true
        editorView.notifyViewportStateDidChange()
    }

    private func minimapContentMetrics(totalRows: CGFloat, heightPx: CGFloat) -> (lineHeightPx: CGFloat, contentHeightPx: CGFloat) {
        let total = max(1, totalRows)
        let h = max(1, heightPx)

        let ideal = h / total
        let capped = (maxLineHeightPx > 0) ? min(ideal, maxLineHeightPx) : ideal
        let lineHeightPx = max(1e-6, capped)
        let contentHeightPx = min(h, total * lineHeightPx)
        return (lineHeightPx, contentHeightPx)
    }
}

struct MinimapGridDTO: Decodable {
    let startVisualRow: UInt32
    let count: UInt32
    let actualLineCount: UInt32
    let lines: [MinimapLineDTO]
}

struct MinimapLineDTO: Decodable {
    let logicalLineIndex: UInt32
    let visualInLogical: UInt32
    let charOffsetStart: UInt32
    let charOffsetEnd: UInt32
    let totalCells: UInt32
    let nonWhitespaceCells: UInt32
    let dominantStyle: UInt32?
    let isFoldPlaceholderAppended: Bool
}

private extension MinimapGridDTO {
    static func decode(from json: String) throws -> MinimapGridDTO {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MinimapGridDTO.self, from: data)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
