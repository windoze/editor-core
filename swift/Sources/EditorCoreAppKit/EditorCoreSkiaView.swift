import AppKit
import EditorCoreUIFFI
import Foundation
import Metal
import MetalKit

enum EditorCoreSkiaViewError: Error {
    case metalUnavailable
    case metalCommandQueueUnavailable
}

/// Hover information produced by `EditorCoreSkiaView` hit-testing.
///
/// Notes:
/// - `charOffset` is in Unicode scalar indices (Rust `char` offsets).
/// - `logicalLine/logicalColumn` are 0-based and also counted in Unicode scalars.
public struct EditorCoreSkiaHoverInfo {
    public let charOffset: UInt32
    public let logicalLine: UInt32
    public let logicalColumn: UInt32
    public let windowPoint: CGPoint
    public let viewPoint: CGPoint
    public let viewBackingXPx: Float
    public let viewBackingYPx: Float
    public let documentLinkJSON: String?

    public init(
        charOffset: UInt32,
        logicalLine: UInt32,
        logicalColumn: UInt32,
        windowPoint: CGPoint,
        viewPoint: CGPoint,
        viewBackingXPx: Float,
        viewBackingYPx: Float,
        documentLinkJSON: String?
    ) {
        self.charOffset = charOffset
        self.logicalLine = logicalLine
        self.logicalColumn = logicalColumn
        self.windowPoint = windowPoint
        self.viewPoint = viewPoint
        self.viewBackingXPx = viewBackingXPx
        self.viewBackingYPx = viewBackingYPx
        self.documentLinkJSON = documentLinkJSON
    }
}

/// Context information for building a context menu at a given mouse event.
public struct EditorCoreSkiaContextMenuContext {
    public let charOffset: UInt32
    public let logicalLine: UInt32
    public let logicalColumn: UInt32
    public let windowPoint: CGPoint
    public let viewPoint: CGPoint
    public let viewBackingXPx: Float
    public let viewBackingYPx: Float

    public init(
        charOffset: UInt32,
        logicalLine: UInt32,
        logicalColumn: UInt32,
        windowPoint: CGPoint,
        viewPoint: CGPoint,
        viewBackingXPx: Float,
        viewBackingYPx: Float
    ) {
        self.charOffset = charOffset
        self.logicalLine = logicalLine
        self.logicalColumn = logicalColumn
        self.windowPoint = windowPoint
        self.viewPoint = viewPoint
        self.viewBackingXPx = viewBackingXPx
        self.viewBackingYPx = viewBackingYPx
    }
}

/// 自绘版 AppKit 组件（Option 2）：
/// - Rust: editor-core + editor-core-ui + Skia（Metal/GPU 直接绘制到 `MTLTexture`）
/// - Swift/AppKit: `MTKView` 负责承接事件并把 `CAMetalDrawable` 呈现到屏幕
///
/// 这是一个“先把正确性与 IME 桥打通”的 MVP：
/// - caret / selection / mouse drag selection
/// - insertText / markedText（IME 组合输入）
/// - undo/redo
@MainActor
public final class EditorCoreSkiaView: MTKView {
    public let editor: EditorUI

    /// Pasteboard used for copy/cut/paste. Defaults to `NSPasteboard.general`.
    ///
    /// Tests can override this to avoid touching the real system clipboard.
    public var pasteboard: NSPasteboard = .general

    /// Hook for opening URLs (e.g. LSP `DocumentLink.target`). Defaults to `NSWorkspace.shared.open`.
    public var onOpenURL: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Called when the editor's viewport state (scroll position / total lines / viewport size) may have changed.
    ///
    /// Hosts can use this to keep native scrollbars in sync.
    public var onViewportStateDidChange: (() -> Void)?

    /// Called when the mouse hovers over a new character offset in the document.
    ///
    /// Hosts can use this to present hover UI (tooltip/popover/inspector).
    public var onHover: ((EditorCoreSkiaHoverInfo) -> Void)?

    /// Called when the mouse leaves the view, allowing hosts to dismiss hover UI.
    public var onHoverExit: (() -> Void)?

    /// Context menu hook.
    ///
    /// - If the closure returns a menu, it will be shown.
    /// - If it returns `nil`, the view falls back to a simple default menu (cut/copy/paste/select all).
    public var contextMenuProvider: ((EditorCoreSkiaContextMenuContext) -> NSMenu?)?

    /// Called when async derived-state processing (e.g. Tree-sitter) applied new edits.
    ///
    /// This is primarily useful for tests and for hosts that want explicit "derived state updated" signals.
    public var onDidApplyAsyncProcessing: (() -> Void)?

    private let metalCommandQueue: MTLCommandQueue
    private var viewportWidthPx: UInt32 = 0
    private var viewportHeightPx: UInt32 = 0
    private var scaleFactor: CGFloat = 1
    private var didLogScaleDebugOnce: Bool = false
    private var lastInputDebugLogUptime: TimeInterval = 0
    private var drawScheduled: Bool = false
    private var didPresentFirstFrame: Bool = false
    private var didLogDrawSetupOnce: Bool = false
    private let textCacheDebugEnabled: Bool = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_TEXT_CACHE"] == "1"
    private let perfDebugEnabled: Bool = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_PERF"] == "1"

    // MARK: - Perf counters (debug only)

    private var perfLastReportUptime: TimeInterval = 0
    private var perfInsertTextCount: Int = 0
    private var perfInsertTextTotalMs: Double = 0
    private var perfSetMarkedCount: Int = 0
    private var perfSetMarkedTotalMs: Double = 0
    private var perfDoCommandCount: Int = 0
    private var perfDoCommandTotalMs: Double = 0
    private var perfRenderMetalCount: Int = 0
    private var perfRenderMetalTotalMs: Double = 0

    private func perfReportIfNeeded(force: Bool = false) {
        guard perfDebugEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if force == false, perfLastReportUptime > 0, now - perfLastReportUptime < 1.0 {
            return
        }
        perfLastReportUptime = now

        let insertAvg = perfInsertTextCount > 0 ? (perfInsertTextTotalMs / Double(perfInsertTextCount)) : 0
        let markedAvg = perfSetMarkedCount > 0 ? (perfSetMarkedTotalMs / Double(perfSetMarkedCount)) : 0
        let cmdAvg = perfDoCommandCount > 0 ? (perfDoCommandTotalMs / Double(perfDoCommandCount)) : 0
        let renderAvg = perfRenderMetalCount > 0 ? (perfRenderMetalTotalMs / Double(perfRenderMetalCount)) : 0

        NSLog(
            "EditorCoreSkiaView perf(1s): insertText=%d avg=%.2fms setMarked=%d avg=%.2fms doCommand=%d avg=%.2fms renderMetal=%d avg=%.2fms",
            perfInsertTextCount,
            insertAvg,
            perfSetMarkedCount,
            markedAvg,
            perfDoCommandCount,
            cmdAvg,
            perfRenderMetalCount,
            renderAvg
        )

        perfInsertTextCount = 0
        perfInsertTextTotalMs = 0
        perfSetMarkedCount = 0
        perfSetMarkedTotalMs = 0
        perfDoCommandCount = 0
        perfDoCommandTotalMs = 0
        perfRenderMetalCount = 0
        perfRenderMetalTotalMs = 0
    }

    // MARK: - Text cache (performance)

    /// AppKit/NSTextInputClient 在输入过程中会频繁查询 `selectedRange/markedRange/firstRect/...`。
    /// 如果每次都跨 FFI 拉整份文档字符串，会造成明显卡顿（尤其是长文档 + 频繁回调）。
    private var docContentEpoch: UInt64 = 1
    private var docTextCacheEpoch: UInt64 = 0
    private var docTextCache: String?
    private var cachedSelectedRange: (epoch: UInt64, start: UInt32, end: UInt32, value: NSRange)?
    private var cachedMarkedRange: (epoch: UInt64, start: UInt32, len: UInt32, value: NSRange)?

    private var lineHeightPx: Float = 18
    private var gutterWidthCells: UInt32 = 4

    private var rectSelectionAnchorOffset: UInt32?
    private var lineSelectionAnchorOffset: UInt32?
    private var wordSelectionAnchorOffset: UInt32?
    private var wordSelectionOrigin: (start: UInt32, end: UInt32)?

    private var hoverTrackingArea: NSTrackingArea?
    private var lastHoverCharOffset: UInt32?

    private lazy var textInputContext = NSTextInputContext(client: self)

    private var processingPollTimer: DispatchSourceTimer?
    private var processingPollDeadlineUptime: TimeInterval = 0

    private func didMutateDocumentText() {
        docContentEpoch &+= 1
        docTextCacheEpoch = 0
        docTextCache = nil
        cachedSelectedRange = nil
        cachedMarkedRange = nil
        updateGutterWidthIfNeeded()
        startProcessingPoll()
    }

    @discardableResult
    private func updateGutterWidthIfNeeded() -> Bool {
        do {
            let lineCount = try editor.logicalLineCount()
            let maxLineNo = max(1, lineCount)
            let digits = UInt32(String(maxLineNo).count)
            // Renderer reserves the first gutter cell for fold markers.
            let required = max(4, 1 + digits)
            if required == gutterWidthCells { return false }

            gutterWidthCells = required
            try editor.setGutterWidthCells(required)
            return true
        } catch {
            // Gutter resizing is best-effort; never break input/rendering because of it.
            return false
        }
    }

    private func documentTextForInputQueries() -> String? {
        if docTextCacheEpoch == docContentEpoch, let cached = docTextCache {
            return cached
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let text = try editor.text()
            docTextCache = text
            docTextCacheEpoch = docContentEpoch

            if textCacheDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                NSLog("EditorCoreSkiaView text cache miss: fetched %d chars in %.2fms", text.count, dtMs)
            }

            return text
        } catch {
            if textCacheDebugEnabled {
                NSLog("EditorCoreSkiaView text cache miss: fetch failed: %@", String(describing: error))
            }
            return nil
        }
    }

    private func invalidateIMECharacterCoordinates() {
        // 用于 IME 候选窗定位：当 caret/marked range 或 viewport 变化时，需要通知系统重新查询 firstRect。
        textInputContext.invalidateCharacterCoordinates()
    }

    private func startProcessingPoll() {
        // Extend the deadline on each edit burst.
        processingPollDeadlineUptime = ProcessInfo.processInfo.systemUptime + 2.0

        if processingPollTimer != nil {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.pollProcessingTick()
        }
        processingPollTimer = timer
        timer.resume()
    }

    private func stopProcessingPoll() {
        processingPollTimer?.cancel()
        processingPollTimer = nil
    }

    private func pollProcessingTick() {
        if ProcessInfo.processInfo.systemUptime > processingPollDeadlineUptime {
            stopProcessingPoll()
            return
        }

        do {
            let r = try editor.pollProcessing()
            if r.applied {
                requestRedraw()
                invalidateIMECharacterCoordinates()
                onViewportStateDidChange?()
                onDidApplyAsyncProcessing?()
            }
            if r.pending == false {
                stopProcessingPoll()
            }
        } catch {
            stopProcessingPoll()
            NSLog("EditorCoreSkiaView pollProcessing failed: %@", String(describing: error))
        }
    }

    public override var acceptsFirstResponder: Bool { true }
    public override var isFlipped: Bool { true }
    public override var inputContext: NSTextInputContext? { textInputContext }

    public init(
        library: EditorCoreUIFFILibrary,
        initialText: String = "",
        viewportWidthCells: UInt32 = 120,
        fontFamiliesCSV: String? = nil
    ) throws {
        self.editor = try EditorUI(library: library, initialText: initialText, viewportWidthCells: viewportWidthCells)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EditorCoreSkiaViewError.metalUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw EditorCoreSkiaViewError.metalCommandQueueUnavailable
        }
        self.metalCommandQueue = queue
        super.init(frame: .zero, device: device)

        if textCacheDebugEnabled {
            NSLog("EditorCoreSkiaView text cache debug enabled (EDITOR_CORE_APPKIT_DEBUG_TEXT_CACHE=1)")
        }
        if perfDebugEnabled {
            NSLog("EditorCoreSkiaView perf debug enabled (EDITOR_CORE_APPKIT_DEBUG_PERF=1)")
        }

        // 说明：
        // - 理想情况下我们希望使用“事件驱动”的 on-demand draw（`enableSetNeedsDisplay = true` + `isPaused = true`）。
        // - 但在 macOS 26.3 的部分组合下，首次显示阶段 on-demand draw 可能不会拿到 drawable，
        //   导致用户看到“编辑区空白”直到发生额外事件。
        //
        // 解决策略：启动时先连续渲染，保证首帧一定 present；首帧成功后自动切回 on-demand。
        enableSetNeedsDisplay = false
        isPaused = false
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        delegate = self

        // 让 Rust/Skia 走 Metal 后端渲染到 `CAMetalDrawable.texture`。
        try editor.enableMetal(device: device, commandQueue: queue)

        // 默认主题（可后续开放给 host 自定义）
        try editor.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 0xFF, g: 0xFF, b: 0xFF, a: 0xFF),
                foreground: EcuRgba8(r: 0x11, g: 0x11, b: 0x11, a: 0xFF),
                selectionBackground: EcuRgba8(r: 0xC7, g: 0xDD, b: 0xFF, a: 0xFF),
                caret: EcuRgba8(r: 0x11, g: 0x11, b: 0x11, a: 0xFF)
            )
        )

        // 让 gutter 可见（行号 + 折叠标记）。
        try editor.setGutterWidthCells(gutterWidthCells)
        _ = updateGutterWidthIfNeeded()

        // Reserved overlay StyleId（见 `crates/editor-core-render-skia/src/lib.rs`）。
        // 这里先用一套默认配色，后续可由 host 主题系统统一下发。
        let gutterBg: UInt32 = 0x0600_0001
        let gutterFg: UInt32 = 0x0600_0002
        let gutterSep: UInt32 = 0x0600_0003
        let foldCollapsed: UInt32 = 0x0600_0004
        let foldExpanded: UInt32 = 0x0600_0005
        try editor.setStyleColors([
            EcuStyleColors(styleId: gutterBg, background: EcuRgba8(r: 0xF5, g: 0xF5, b: 0xF5, a: 0xFF)),
            EcuStyleColors(styleId: gutterFg, foreground: EcuRgba8(r: 0x88, g: 0x88, b: 0x88, a: 0xFF)),
            EcuStyleColors(styleId: gutterSep, foreground: EcuRgba8(r: 0xDD, g: 0xDD, b: 0xDD, a: 0xFF)),
            EcuStyleColors(styleId: foldExpanded, background: EcuRgba8(r: 0xAA, g: 0xAA, b: 0xAA, a: 0xFF)),
            EcuStyleColors(styleId: foldCollapsed, background: EcuRgba8(r: 0x77, g: 0x77, b: 0x77, a: 0xFF)),
        ])

        if let fontFamiliesCSV, fontFamiliesCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try editor.setFontFamiliesCSV(fontFamiliesCSV)
        }
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidthCells:) 构造。")
    public override init(frame frameRect: NSRect, device: MTLDevice?) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidthCells:) 构造。")
    public required init(coder: NSCoder) {
        fatalError("unavailable")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Hover requires mouse moved events.
        window?.acceptsMouseMovedEvents = true
        updateLayerContentsScaleIfNeeded()
        updateViewportIfNeeded()

        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1", didLogDrawSetupOnce == false {
            didLogDrawSetupOnce = true
            let layerDesc = layer.map { String(describing: type(of: $0)) } ?? "nil"
            let delegateDesc = delegate.map { String(describing: type(of: $0)) } ?? "nil"
            NSLog(
                "EditorCoreSkiaView setup: window=%@ wantsLayer=%d layer=%@ device=%@ delegate=%@ paused=%d setNeeds=%d fps=%d bounds(points)=%@ drawableSize(px)=%@",
                String(describing: window),
                wantsLayer ? 1 : 0,
                layerDesc,
                device.map { String(describing: $0) } ?? "nil",
                delegateDesc,
                isPaused ? 1 : 0,
                enableSetNeedsDisplay ? 1 : 0,
                preferredFramesPerSecond,
                NSStringFromSize(bounds.size),
                NSStringFromSize(drawableSize)
            )
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .inVisibleRect,
            .mouseMoved,
            .mouseEnteredAndExited,
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerContentsScaleIfNeeded()
        updateViewportIfNeeded()
        requestRedraw()
    }

    public override func layout() {
        super.layout()
        updateViewportIfNeeded()
    }

    public override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        // 对 `MTKView`（on-demand 模式）来说，仅标记 needsDisplay 在某些系统版本上不会触发 GPU draw。
        // 我们在这里统一把它转成一次 `draw()`，这样外部（demo/scroll container/test）只要
        // 继续用 `needsDisplay = true` 就能可靠刷新画面。
        scheduleDrawIfPossible()
    }

    private func updateLayerContentsScaleIfNeeded() {
        guard let window else { return }
        // 在某些 layer-backed 组合/缩放配置下，如果 contentsScale 不跟随 window 的 backingScaleFactor，
        // 会导致“画面贴屏”和“事件坐标 hit-test”不在同一套像素坐标系里（表现为点击/光标不对齐）。
        if layer?.contentsScale != window.backingScaleFactor {
            layer?.contentsScale = window.backingScaleFactor
        }
    }

    private func updateViewportIfNeeded() {
        let pointsSize = bounds.size
        let fallbackScale = window?.backingScaleFactor ?? (NSScreen.main?.backingScaleFactor ?? 1)
        let safeScale = max(1, fallbackScale)

        let backingSize: NSSize
        if window != nil,
           pointsSize.width.isFinite,
           pointsSize.height.isFinite,
           pointsSize.width > 0,
           pointsSize.height > 0
        {
            let converted = convertToBacking(pointsSize)
            if converted.width.isFinite, converted.height.isFinite {
                backingSize = converted
            } else {
                // 在某些布局阶段（比如 view 还未有有效 bounds 时），MTKView 的内部缩放因子可能导致
                // convertToBacking 返回 NaN/Inf。这里回退到 window 的 backingScaleFactor。
                backingSize = NSSize(width: pointsSize.width * safeScale, height: pointsSize.height * safeScale)
            }
        } else {
            // 当 bounds 为 0 或未就绪时，不要调用 convertToBacking（可能产生 NaN/Inf 并触发 Swift runtime trap）。
            let w = pointsSize.width.isFinite ? pointsSize.width : 0
            let h = pointsSize.height.isFinite ? pointsSize.height : 0
            backingSize = NSSize(width: w * safeScale, height: h * safeScale)
        }

        let backingWidth = backingSize.width.isFinite ? backingSize.width : 0
        let backingHeight = backingSize.height.isFinite ? backingSize.height : 0
        let widthPx = UInt32(max(1, Int(max(0, backingWidth).rounded())))
        let heightPx = UInt32(max(1, Int(max(0, backingHeight).rounded())))

        let newScale: CGFloat
        if pointsSize.width > 0, pointsSize.height > 0, backingWidth > 0, backingHeight > 0 {
            let sx = backingWidth / pointsSize.width
            let sy = backingHeight / pointsSize.height
            if sx.isFinite, sy.isFinite, sx > 0, sy > 0 {
                newScale = (sx + sy) * 0.5
            } else {
                newScale = safeScale
            }
        } else {
            newScale = safeScale
        }

        guard widthPx != viewportWidthPx || heightPx != viewportHeightPx || newScale != scaleFactor else {
            return
        }

        viewportWidthPx = widthPx
        viewportHeightPx = heightPx
        scaleFactor = newScale

        // MTKView 的 drawableSize 以“像素”为单位；这里保持与 Rust viewport 一致。
        let newDrawableSize = CGSize(width: CGFloat(widthPx), height: CGFloat(heightPx))
        if drawableSize != newDrawableSize {
            drawableSize = newDrawableSize
        }

        // 先用固定等宽网格参数（后续可做更精确 font metrics）
        let fontSizePx: Float = Float(13.0 * newScale)
        let lineHeightPx: Float = Float(18.0 * newScale)
        let cellWidthPx: Float = Float(8.0 * newScale)
        let paddingPx: Float = Float(8.0 * newScale)
        self.lineHeightPx = lineHeightPx

        do {
            try editor.setRenderMetrics(
                fontSize: fontSizePx,
                lineHeightPx: lineHeightPx,
                cellWidthPx: cellWidthPx,
                paddingXPx: paddingPx,
                paddingYPx: paddingPx
            )
            try editor.setViewportPx(widthPx: widthPx, heightPx: heightPx, scale: Float(newScale))
        } catch {
            NSLog("EditorCoreSkiaView updateViewport failed: %@", String(describing: error))
        }

        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_SCALE"] == "1" {
            if didLogScaleDebugOnce == false {
                didLogScaleDebugOnce = true
                NSLog(
                    "EditorCoreSkiaView scale debug: bounds(points)=%@ backingSize(px)=%@ newScale=%.3f window.backingScaleFactor=%.3f layer.contentsScale=%.3f",
                    NSStringFromSize(pointsSize),
                    NSStringFromSize(backingSize),
                    Double(newScale),
                    Double(window?.backingScaleFactor ?? 0),
                    Double(layer?.contentsScale ?? 0)
                )
            }
        }

        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    deinit {
        processingPollTimer?.cancel()
        processingPollTimer = nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        // 在 macOS 26.3 上观察到：`MTKViewDelegate.draw(in:)` 有时不会被调用（导致“编辑区空白”），
        // 但 AppKit 的 view-based draw pipeline 仍然会触发 `draw(_:)`。
        //
        // 因此这里把 Metal 渲染放到 `draw(_:)` 里作为兜底（并保持 `MTKViewDelegate` 的实现）。
        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
            NSLog("EditorCoreSkiaView drawRect: dirty=%@ bounds(points)=%@ drawableSize(px)=%@",
                  NSStringFromRect(dirtyRect),
                  NSStringFromSize(bounds.size),
                  NSStringFromSize(drawableSize))
        }
        updateViewportIfNeeded()
        renderToCurrentDrawable(debugSource: "drawRect")
    }

    // MARK: - Mouse

    private func debugLogInput(_ event: NSEvent, xPx: Float, yPx: Float, phase: String, force: Bool) {
        guard ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_INPUT"] == "1" else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if force == false, now - lastInputDebugLogUptime < 0.1 {
            return
        }
        lastInputDebugLogUptime = now

        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        let boundsSize = bounds.size
        let backingSize = convertToBacking(boundsSize)
        let sx = boundsSize.width > 0 ? (backingSize.width / boundsSize.width) : 0
        let sy = boundsSize.height > 0 ? (backingSize.height / boundsSize.height) : 0

        var extra = ""
        if let scalar = try? editor.viewPointToCharOffset(xPx: xPx, yPx: yPx) {
            if let snapped = try? editor.charOffsetToViewPoint(offset: scalar) {
                let dx = snapped.xPx - xPx
                let dy = snapped.yPx - yPx
                extra = String(format: " off=%u snapped=(%.1f,%.1f) d=(%.1f,%.1f)", scalar, snapped.xPx, snapped.yPx, dx, dy)
            } else {
                extra = " off=\(scalar)"
            }
        }

        NSLog(
            "EditorCoreSkiaView input %@: window=%@ view=%@ sx=%.3f sy=%.3f -> px=(%.1f,%.1f) viewport=%ux%u%@",
            phase,
            NSStringFromPoint(windowPoint),
            NSStringFromPoint(viewPoint),
            Double(sx),
            Double(sy),
            Double(xPx),
            Double(yPx),
            viewportWidthPx,
            viewportHeightPx,
            extra
        )
    }

    public override func mouseMoved(with event: NSEvent) {
        guard onHover != nil else { return }
        updateViewportIfNeeded()

        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: windowPoint,
            view: self
        )

        do {
            let offset = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
            if offset == lastHoverCharOffset { return }
            lastHoverCharOffset = offset

            let pos = try editor.charOffsetToLogicalPosition(offset: offset)
            let linkJSON = try? editor.documentLinkJSONAtViewPoint(xPx: xPx, yPx: yPx)

            onHover?(
                EditorCoreSkiaHoverInfo(
                    charOffset: offset,
                    logicalLine: pos.line,
                    logicalColumn: pos.column,
                    windowPoint: windowPoint,
                    viewPoint: viewPoint,
                    viewBackingXPx: xPx,
                    viewBackingYPx: yPx,
                    documentLinkJSON: linkJSON ?? nil
                )
            )
        } catch {
            // Hover is best-effort: never beep or disrupt input.
        }
    }

    public override func mouseExited(with event: NSEvent) {
        if lastHoverCharOffset != nil {
            lastHoverCharOffset = nil
            onHoverExit?()
        }
        super.mouseExited(with: event)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let context = buildContextMenuContext(for: event)
        if let menu = contextMenuProvider?(context) {
            return menu
        }
        return defaultContextMenu(for: context)
    }

    public override func rightMouseDown(with event: NSEvent) {
        // Ensure we become first responder so standard actions (copy/cut/paste) go through our overrides.
        window?.makeFirstResponder(self)

        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    private func buildContextMenuContext(for event: NSEvent) -> EditorCoreSkiaContextMenuContext {
        updateViewportIfNeeded()

        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: windowPoint,
            view: self
        )

        let offset = (try? editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)) ?? 0
        let pos = (try? editor.charOffsetToLogicalPosition(offset: offset)) ?? (line: 0, column: 0)

        return EditorCoreSkiaContextMenuContext(
            charOffset: offset,
            logicalLine: pos.line,
            logicalColumn: pos.column,
            windowPoint: windowPoint,
            viewPoint: viewPoint,
            viewBackingXPx: xPx,
            viewBackingYPx: yPx
        )
    }

    private func defaultContextMenu(for context: EditorCoreSkiaContextMenuContext) -> NSMenu {
        let menu = NSMenu(title: "Editor")
        menu.autoenablesItems = false

        let hasSelection: Bool
        do {
            let s = try editor.selectionOffsets()
            hasSelection = s.start != s.end
        } catch {
            hasSelection = false
        }

        let canPaste = pasteboard.string(forType: .string) != nil

        let cut = NSMenuItem(title: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        cut.target = self
        cut.isEnabled = hasSelection

        let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = hasSelection

        let paste = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        paste.target = self
        paste.isEnabled = canPaste

        let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAll.target = self
        selectAll.isEnabled = true

        menu.addItem(cut)
        menu.addItem(copy)
        menu.addItem(paste)
        menu.addItem(.separator())
        menu.addItem(selectAll)

        // Keep `context` referenced (future-proof: allow providers to attach representedObject via userInfo).
        _ = context
        return menu
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: event.locationInWindow,
            view: self
        )
        debugLogInput(event, xPx: xPx, yPx: yPx, phase: "down", force: true)

        rectSelectionAnchorOffset = nil
        lineSelectionAnchorOffset = nil
        wordSelectionAnchorOffset = nil
        wordSelectionOrigin = nil

        do {
            if event.modifierFlags.contains(.command) {
                // Cmd+Click: prefer opening document links (VSCode-style) when a link is present.
                if event.clickCount == 1, openDocumentLinkIfPresent(xPx: xPx, yPx: yPx) {
                    return
                }
                // Cmd+Click: add a new caret at point (multi-cursor).
                let offset = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                try editor.addCaret(atCharOffset: offset, makePrimary: true)
            } else if event.modifierFlags.contains(.option) {
                // Option+Drag: rectangular (box) selection.
                let anchor = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                rectSelectionAnchorOffset = anchor
                try editor.setRectSelection(anchorOffset: anchor, activeOffset: anchor)
            } else {
                // Double/triple click selection.
                if event.clickCount == 2 {
                    let anchor = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                    wordSelectionAnchorOffset = anchor
                    try editor.mouseDown(xPx: xPx, yPx: yPx)
                    try editor.selectWord()
                    wordSelectionOrigin = try editor.selectionOffsets()
                } else if event.clickCount >= 3 {
                    // Triple-click: select line (code editor behavior).
                    //
                    // If user keeps dragging after triple-click, we extend the selection by full lines.
                    let anchor = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                    lineSelectionAnchorOffset = anchor
                    try editor.mouseDown(xPx: xPx, yPx: yPx)
                    try editor.selectLine()
                } else {
                    try editor.mouseDown(xPx: xPx, yPx: yPx)
                }
            }
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
    }

    /// Try to open an LSP document link at the given view point (in backing pixels).
    ///
    /// Returns `true` when a link was found and opened.
    @discardableResult
    public func openDocumentLinkIfPresent(xPx: Float, yPx: Float) -> Bool {
        do {
            guard let json = try editor.documentLinkJSONAtViewPoint(xPx: xPx, yPx: yPx) else {
                return false
            }
            guard let url = Self.documentLinkTargetURL(from: json) else {
                return false
            }
            onOpenURL(url)
            return true
        } catch {
            return false
        }
    }

    private static func documentLinkTargetURL(from json: String) -> URL? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let target = obj["target"] as? String, target.isEmpty == false else { return nil }

        // LSP `DocumentLink.target` is typically a URI string (file://, https://, ...).
        if let url = URL(string: target), url.scheme != nil {
            return url
        }
        // Fallback: treat it as a filesystem path.
        return URL(fileURLWithPath: target)
    }

    public override func mouseDragged(with event: NSEvent) {
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(
            windowPoint: event.locationInWindow,
            view: self
        )
        debugLogInput(event, xPx: xPx, yPx: yPx, phase: "drag", force: false)
        do {
            if let anchor = rectSelectionAnchorOffset {
                let active = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                try editor.setRectSelection(anchorOffset: anchor, activeOffset: active)
            } else if let anchor = lineSelectionAnchorOffset {
                let active = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                try editor.setLineSelection(anchorOffset: anchor, activeOffset: active)
            } else if wordSelectionAnchorOffset != nil, let origin = wordSelectionOrigin {
                let active = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                try expandWordSelectionToward(activeOffset: active, origin: origin)
            } else {
                try editor.mouseDragged(xPx: xPx, yPx: yPx)
            }
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
    }

    public override func mouseUp(with event: NSEvent) {
        rectSelectionAnchorOffset = nil
        lineSelectionAnchorOffset = nil
        wordSelectionAnchorOffset = nil
        wordSelectionOrigin = nil
        editor.mouseUp()
        requestRedraw()
        invalidateIMECharacterCoordinates()
    }

    private func expandWordSelectionToward(activeOffset: UInt32, origin: (start: UInt32, end: UInt32)) throws {
        // Normal "double-click then drag" behavior:
        // - anchor to the original word selection
        // - extend by word towards the active point
        // - allow shrinking when the drag direction changes by resetting to the origin first
        //
        // The core `ExpandSelectionBy` command is expand-only by design, so the view resets the
        // selection to the original word range on every drag event.
        try editor.setSelections([EcuSelectionRange(start: origin.start, end: origin.end)], primaryIndex: 0)

        // Now expand by one word at a time until the active point is inside the selection.
        var remaining = 2048
        while remaining > 0 {
            let s = try editor.selectionOffsets()
            if activeOffset < s.start {
                try editor.expandSelectionBy(unit: .word, count: 1, direction: .backward)
                let next = try editor.selectionOffsets()
                if next.start == s.start { break }
            } else if activeOffset > s.end {
                try editor.expandSelectionBy(unit: .word, count: 1, direction: .forward)
                let next = try editor.selectionOffsets()
                if next.end == s.end { break }
            } else {
                break
            }
            remaining -= 1
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        handleScroll(deltaYPoints: event.scrollingDeltaY, hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas)
    }

    // MARK: - Smooth scroll helper (testable)

    /// Smooth-scroll handler shared by `scrollWheel(with:)` and unit tests.
    ///
    /// - Parameters:
    ///   - deltaYPoints: For precise scrolling events, this is the point delta. For coarse scrolling
    ///     (mouse wheel), AppKit's delta is closer to “line units”.
    ///   - hasPreciseScrollingDeltas: Mirrors `NSEvent.hasPreciseScrollingDeltas`.
    func handleScroll(
        deltaYPoints: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) {
        // 平滑滚动：
        // - trackpad（hasPreciseScrollingDeltas == true）给出的是 point 级连续 delta
        // - 传统鼠标滚轮（hasPreciseScrollingDeltas == false）更接近“行数”delta
        //
        // UI 侧统一换算成“backing pixels”的 delta，再交给 Rust UI 层维护
        // `(scroll_top, sub_row_offset)`，并在渲染/hit-test 中使用子行偏移。
        var scale = window?.backingScaleFactor ?? (NSScreen.main?.backingScaleFactor ?? 1)
        scale = max(1, scale)

        var deltaPt = deltaYPoints
        if hasPreciseScrollingDeltas == false {
            // 注意：这里不能直接用 `convertToBacking/convertFromBacking` 来换算 delta，
            // 因为 `NSSize` 在语义上是“尺寸”，某些情况下系统可能会丢掉符号位（导致滚动方向错）。
            //
            // 我们使用明确的 `backingScaleFactor` 做乘除，确保 delta 的正负号稳定。
            let lineHeightPt = CGFloat(max(1, lineHeightPx)) / scale
            if lineHeightPt > 0 {
                deltaPt *= lineHeightPt
            }
        }

        let deltaPx = deltaPt * scale
        if deltaPx != 0 {
            // 约定：Rust `scrollByPixels` 的正值表示“向下滚动”（内容向上，显示更靠后的行）。
            // AppKit: scrollingDeltaY > 0 通常表示“向上滚动”（内容向下）。
            // 我们约定 Rust `scrollByPixels` 的正值表示“向下滚动”（内容向上），因此取负号。
            editor.scrollByPixels(Float(-deltaPx))
            requestRedraw()
            invalidateIMECharacterCoordinates()
            onViewportStateDidChange?()
        }
    }

    // MARK: - Keyboard / Text input

    public override func keyDown(with event: NSEvent) {
        // 说明：
        // - `interpretKeyEvents` 主要处理“文本系统 key binding”（比如方向键、delete、Option+Left 等），
        //   最终回调到 `insertText` / `setMarkedText` / `doCommand(by:)`。
        // - 但像 Cmd+C / Cmd+V / Cmd+X 这类“菜单快捷键”在没有 NSMenu 的 demo 环境里不会被触发，
        //   导致看起来“剪贴板命令不存在”。
        //
        // 为了让组件在“无菜单”场景也能工作，我们在这里直接拦截常用 Cmd 快捷键。
        if handleCommandShortcutsIfNeeded(event: event) {
            return
        }

        // 让系统把按键解释成 insertText / setMarkedText / doCommand(by:)
        interpretKeyEvents([event])
    }

    /// Handle common “menu-like” Cmd shortcuts for menu-less hosts (e.g. our SwiftPM demo).
    ///
    /// Returns `true` when the event is handled.
    private func handleCommandShortcutsIfNeeded(event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }

        // We only handle simple single-character shortcuts here.
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else { return false }
        let key = chars.lowercased()

        switch key {
        case "c":
            copy(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "a":
            selectAll(nil)
            return true
        case "z":
            // macOS convention: Cmd+Z undo, Shift+Cmd+Z redo.
            if flags.contains(.shift) {
                redo(nil)
            } else {
                undo(nil)
            }
            return true
        case "y":
            // Some editors support Cmd+Y for redo.
            redo(nil)
            return true
        default:
            return false
        }
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        updateViewportIfNeeded()
        let text: String
        if let s = string as? String {
            text = s
        } else if let a = string as? NSAttributedString {
            text = a.string
        } else {
            text = String(describing: string)
        }

        let t0 = perfDebugEnabled ? CFAbsoluteTimeGetCurrent() : 0
        do {
            try editor.commitText(text)
            didMutateDocumentText()
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfInsertTextCount += 1
                perfInsertTextTotalMs += dtMs
                perfReportIfNeeded()
            }
        } catch {
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfInsertTextCount += 1
                perfInsertTextTotalMs += dtMs
                perfReportIfNeeded()
            }
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        updateViewportIfNeeded()
        let text: String
        if let s = string as? String {
            text = s
        } else if let a = string as? NSAttributedString {
            text = a.string
        } else {
            text = String(describing: string)
        }

        let t0 = perfDebugEnabled ? CFAbsoluteTimeGetCurrent() : 0
        do {
            // `selectedRange` 是 marked string 内部的 UTF-16 range（caret/selection in preedit）。
            // 我们转换成 Unicode scalar offsets 并交给 Rust，以支持 inline/preedit 模式下
            // caret 在组合串内部移动（例如拼音候选、选词时）。
            let selStartScalar = Self.scalarOffset(fromUTF16Offset: selectedRange.location, in: text)
            let selEndScalar = Self.scalarOffset(fromUTF16Offset: selectedRange.location + selectedRange.length, in: text)
            let selLenScalar = max(0, selEndScalar - selStartScalar)

            // `replacementRange` 是 document 内的 UTF-16 range；大多数情况下为 NSNotFound，
            // 此时 Rust 会优先替换“已有 marked range”，否则替换当前 selection/caret。
            var replaceStart: UInt32 = UInt32.max
            var replaceLen: UInt32 = 0
            if replacementRange.location != NSNotFound {
                let doc: String
                if let cached = documentTextForInputQueries() {
                    doc = cached
                } else {
                    doc = try editor.text()
                }
                let a = Self.scalarOffset(fromUTF16Offset: replacementRange.location, in: doc)
                let b = Self.scalarOffset(fromUTF16Offset: replacementRange.location + replacementRange.length, in: doc)
                replaceStart = UInt32(max(0, a))
                replaceLen = UInt32(max(0, b - a))
            }

            try editor.setMarkedText(
                text,
                selectedStart: UInt32(max(0, selStartScalar)),
                selectedLen: UInt32(selLenScalar),
                replaceStart: replaceStart,
                replaceLen: replaceLen
            )
            didMutateDocumentText()
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfSetMarkedCount += 1
                perfSetMarkedTotalMs += dtMs
                perfReportIfNeeded()
            }
        } catch {
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfSetMarkedCount += 1
                perfSetMarkedTotalMs += dtMs
                perfReportIfNeeded()
            }
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    public func unmarkText() {
        editor.unmarkText()
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    public override func doCommand(by selector: Selector) {
        updateViewportIfNeeded()
        let t0 = perfDebugEnabled ? CFAbsoluteTimeGetCurrent() : 0
        var didEditText = false
        do {
            switch selector {
            case #selector(copy(_:)):
                copy(nil)
            case #selector(cut(_:)):
                cut(nil)
            case #selector(paste(_:)):
                paste(nil)
            case #selector(moveLeft(_:)):
                // 非 shift：如果有选区，先折叠选区到起点（符合多数编辑器习惯）。
                let sel = try editor.selectionOffsets()
                if sel.start != sel.end {
                    try editor.setSelections([EcuSelectionRange(start: sel.start, end: sel.start)], primaryIndex: 0)
                } else {
                    try editor.moveGraphemeLeft()
                }
            case #selector(moveRight(_:)):
                let sel = try editor.selectionOffsets()
                if sel.start != sel.end {
                    try editor.setSelections([EcuSelectionRange(start: sel.end, end: sel.end)], primaryIndex: 0)
                } else {
                    try editor.moveGraphemeRight()
                }
            case #selector(moveWordLeft(_:)):
                let sel = try editor.selectionOffsets()
                if sel.start != sel.end {
                    try editor.setSelections([EcuSelectionRange(start: sel.start, end: sel.start)], primaryIndex: 0)
                }
                try editor.moveWordLeft()
            case #selector(moveWordRight(_:)):
                let sel = try editor.selectionOffsets()
                if sel.start != sel.end {
                    try editor.setSelections([EcuSelectionRange(start: sel.end, end: sel.end)], primaryIndex: 0)
                }
                try editor.moveWordRight()
            case #selector(moveToBeginningOfLine(_:)):
                try editor.moveToVisualLineStart()
            case #selector(moveToEndOfLine(_:)):
                try editor.moveToVisualLineEnd()
            case #selector(moveToLeftEndOfLine(_:)):
                // Some keybindings (Home / Cmd+Left in certain layouts) map to the bidi-aware variants.
                try editor.moveToVisualLineStart()
            case #selector(moveToRightEndOfLine(_:)):
                try editor.moveToVisualLineEnd()
            case #selector(moveToBeginningOfDocument(_:)):
                try editor.moveToDocumentStart()
            case #selector(moveToEndOfDocument(_:)):
                try editor.moveToDocumentEnd()
            case #selector(scrollToBeginningOfDocument(_:)):
                // Home key in some contexts is dispatched as a "scroll" action.
                // We treat it as a caret move for editor behavior consistency.
                try editor.moveToDocumentStart()
            case #selector(scrollToEndOfDocument(_:)):
                try editor.moveToDocumentEnd()
            case #selector(pageUp(_:)):
                try editor.moveVisualByPages(-1)
            case #selector(pageDown(_:)):
                try editor.moveVisualByPages(1)
            case #selector(scrollPageUp(_:)):
                try editor.moveVisualByPages(-1)
            case #selector(scrollPageDown(_:)):
                try editor.moveVisualByPages(1)
            case #selector(moveUp(_:)):
                try editor.moveVisualByRows(-1)
            case #selector(moveDown(_:)):
                try editor.moveVisualByRows(1)
            case #selector(moveLeftAndModifySelection(_:)):
                try editor.moveGraphemeLeftAndModifySelection()
            case #selector(moveRightAndModifySelection(_:)):
                try editor.moveGraphemeRightAndModifySelection()
            case #selector(moveWordLeftAndModifySelection(_:)):
                try editor.moveWordLeftAndModifySelection()
            case #selector(moveWordRightAndModifySelection(_:)):
                try editor.moveWordRightAndModifySelection()
            case #selector(moveToBeginningOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineStartAndModifySelection()
            case #selector(moveToEndOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineEndAndModifySelection()
            case #selector(moveToLeftEndOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineStartAndModifySelection()
            case #selector(moveToRightEndOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineEndAndModifySelection()
            case #selector(moveToBeginningOfDocumentAndModifySelection(_:)):
                try editor.moveToDocumentStartAndModifySelection()
            case #selector(moveToEndOfDocumentAndModifySelection(_:)):
                try editor.moveToDocumentEndAndModifySelection()
            case Selector(("scrollToBeginningOfDocumentAndModifySelection:")):
                try editor.moveToDocumentStartAndModifySelection()
            case Selector(("scrollToEndOfDocumentAndModifySelection:")):
                try editor.moveToDocumentEndAndModifySelection()
            case #selector(pageUpAndModifySelection(_:)):
                try editor.moveVisualByPagesAndModifySelection(-1)
            case #selector(pageDownAndModifySelection(_:)):
                try editor.moveVisualByPagesAndModifySelection(1)
            case Selector(("scrollPageUpAndModifySelection:")):
                try editor.moveVisualByPagesAndModifySelection(-1)
            case Selector(("scrollPageDownAndModifySelection:")):
                try editor.moveVisualByPagesAndModifySelection(1)
            case #selector(moveUpAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(-1)
            case #selector(moveDownAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(1)
            case #selector(deleteBackward(_:)):
                try editor.backspace()
                didEditText = true
            case #selector(deleteForward(_:)):
                try editor.deleteForward()
                didEditText = true
            case #selector(deleteWordBackward(_:)):
                try editor.deleteWordBack()
                didEditText = true
            case #selector(deleteWordForward(_:)):
                try editor.deleteWordForward()
                didEditText = true
            case #selector(insertNewline(_:)):
                try editor.commitText("\n")
                didEditText = true
            case #selector(insertTab(_:)):
                try editor.commitText("\t")
                didEditText = true
            case #selector(cancelOperation(_:)):
                // Escape: cancel marked text / composition (restore original replaced range).
                let marked = try editor.markedRange()
                if marked.hasMarked {
                    try editor.setMarkedText("", selectedStart: 0, selectedLen: 0)
                    didEditText = true
                }
            case #selector(undo(_:)):
                try editor.undo()
                didEditText = true
            case #selector(redo(_:)):
                try editor.redo()
                didEditText = true
            default:
                break
            }
        } catch {
            NSSound.beep()
        }
        if didEditText {
            didMutateDocumentText()
        }
        if perfDebugEnabled {
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            perfDoCommandCount += 1
            perfDoCommandTotalMs += dtMs
            perfReportIfNeeded()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    // MARK: - Clipboard

    public override func selectAll(_ sender: Any?) {
        do {
            // EditorCoreUI 使用 Unicode scalar offset（与 Rust `char` 索引一致），这里用 unicodeScalars 计数。
            let text: String
            if let cached = documentTextForInputQueries() {
                text = cached
            } else {
                text = try editor.text()
            }
            let end = UInt32(text.unicodeScalars.count)
            try editor.setSelections([EcuSelectionRange(start: 0, end: end)], primaryIndex: 0)
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    @objc(undo:)
    public func undo(_ sender: Any?) {
        do {
            try editor.undo()
            didMutateDocumentText()
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    @objc(redo:)
    public func redo(_ sender: Any?) {
        do {
            try editor.redo()
            didMutateDocumentText()
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    @objc(copy:)
    public func copy(_ sender: Any?) {
        do {
            let text = try editor.selectedText()
            guard text.isEmpty == false else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } catch {
            NSSound.beep()
        }
    }

    @objc(cut:)
    public func cut(_ sender: Any?) {
        do {
            let text = try editor.selectedText()
            guard text.isEmpty == false else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            try editor.deleteSelectionsOnly()
            didMutateDocumentText()
            requestRedraw()
            invalidateIMECharacterCoordinates()
            onViewportStateDidChange?()
        } catch {
            NSSound.beep()
        }
    }

    @objc(paste:)
    public func paste(_ sender: Any?) {
        updateViewportIfNeeded()
        guard let text = pasteboard.string(forType: .string), text.isEmpty == false else { return }
        do {
            try editor.commitText(text)
            didMutateDocumentText()
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    // MARK: - NSTextInputClient state queries

    public func selectedRange() -> NSRange {
        guard let sel = try? editor.selectionOffsets() else { return NSRange(location: 0, length: 0) }
        if let cached = cachedSelectedRange,
           cached.epoch == docContentEpoch,
           cached.start == sel.start,
           cached.end == sel.end
        {
            return cached.value
        }
        guard let text = documentTextForInputQueries() else { return NSRange(location: 0, length: 0) }
        let startUtf16 = Self.utf16Offset(fromScalarOffset: Int(sel.start), in: text)
        let endUtf16 = Self.utf16Offset(fromScalarOffset: Int(sel.end), in: text)
        let range = NSRange(location: startUtf16, length: max(0, endUtf16 - startUtf16))
        cachedSelectedRange = (epoch: docContentEpoch, start: sel.start, end: sel.end, value: range)
        return range
    }

    public func markedRange() -> NSRange {
        guard let marked = try? editor.markedRange(), marked.hasMarked else { return NSRange(location: NSNotFound, length: 0) }
        if let cached = cachedMarkedRange,
           cached.epoch == docContentEpoch,
           cached.start == marked.start,
           cached.len == marked.len
        {
            return cached.value
        }
        guard let text = documentTextForInputQueries() else { return NSRange(location: NSNotFound, length: 0) }
        let startUtf16 = Self.utf16Offset(fromScalarOffset: Int(marked.start), in: text)
        let endUtf16 = Self.utf16Offset(fromScalarOffset: Int(marked.start + marked.len), in: text)
        let range = NSRange(location: startUtf16, length: max(0, endUtf16 - startUtf16))
        cachedMarkedRange = (epoch: docContentEpoch, start: marked.start, len: marked.len, value: range)
        return range
    }

    public func hasMarkedText() -> Bool {
        guard let marked = try? editor.markedRange() else { return false }
        return marked.hasMarked
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let text = documentTextForInputQueries() else { return nil }
        let ns = text as NSString
        let clamped = NSRange(
            location: min(max(0, range.location), ns.length),
            length: min(max(0, range.length), max(0, ns.length - range.location))
        )
        actualRange?.pointee = clamped
        return NSAttributedString(string: ns.substring(with: clamped))
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .foregroundColor, .backgroundColor]
    }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // 这个 rect 用于 IME 候选窗定位。
        //
        // 关键点：
        // - AppKit 在组合输入期间可能会用不同的 range 来查询（markedRange / selectedRange 等），
        //   如果我们直接使用传入的 `range.location`，候选窗会在“组合串起点”和“光标位置”之间跳动，
        //   甚至看起来像是“随机”。
        // - 正确行为：候选窗应跟随“当前 insertion point”（也就是 selection 的 active 端/光标），
        //   尤其是在 marked text（preedit）存在时。
        updateViewportIfNeeded()
        guard let window else {
            actualRange?.pointee = range
            return .zero
        }
        guard let text = documentTextForInputQueries() else {
            actualRange?.pointee = range
            return .zero
        }

        // Prefer the current caret position during IME composition.
        let effectiveRange: NSRange
        if hasMarkedText() {
            effectiveRange = selectedRange()
        } else {
            effectiveRange = range
        }
        actualRange?.pointee = effectiveRange

        // Use the end of the range as the insertion point.
        // Handle NSNotFound defensively.
        let utf16Index: Int
        if effectiveRange.location == NSNotFound {
            let sel = selectedRange()
            utf16Index = max(0, sel.location + sel.length)
        } else {
            utf16Index = max(0, effectiveRange.location + effectiveRange.length)
        }

        let scalarOffset = Self.scalarOffset(fromUTF16Offset: utf16Index, in: text)

        guard let pt = try? editor.charOffsetToViewPoint(offset: UInt32(scalarOffset)) else { return .zero }

        // 不使用 `convertFromBacking(point)`：
        // - 我们之前已经遇到过在“缩放显示 / Retina”等组合下，point<->backing 的点转换不稳定（X/Y 比例不一致）。
        // - 这里改用 `convertToBacking(bounds.size)` 推导像素/点比例，并手动做除法，
        //   保证和 viewport 计算、事件 hit-test 一致（参见 `EditorCoreCoordinateMapping`）。
        let boundsSize = bounds.size
        let backingSize = convertToBacking(boundsSize)
        let sx = boundsSize.width > 0 ? (backingSize.width / boundsSize.width) : 1
        let sy = boundsSize.height > 0 ? (backingSize.height / boundsSize.height) : 1

        let xPt = CGFloat(pt.xPx) / max(1e-6, sx)
        let yPt = CGFloat(pt.yPx) / max(1e-6, sy)
        let hPt = CGFloat(pt.lineHeightPx) / max(1e-6, sy)

        let rectInView = NSRect(x: xPt, y: yPt, width: 1, height: hPt)
        let rectInWindow = convert(rectInView, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)

        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_IME_RECT"] == "1" {
            NSLog(
                "EditorCoreSkiaView IME rect debug: hasMarked=%d query=%@ effective=%@ utf16Index=%d scalarOffset=%d viewPt=(%.1f,%.1f) lineH=%.1f screenRect=%@",
                hasMarkedText() ? 1 : 0,
                NSStringFromRange(range),
                NSStringFromRange(effectiveRange),
                utf16Index,
                scalarOffset,
                Double(xPt),
                Double(yPt),
                Double(hPt),
                NSStringFromRect(rectInScreen)
            )
        }

        return rectInScreen
    }

    public func characterIndex(for point: NSPoint) -> Int {
        // point 是 view 坐标（points），我们做 hit-test 并返回 UTF-16 index
        guard let text = documentTextForInputQueries() else { return 0 }
        let (xPx, yPx) = EditorCoreCoordinateMapping.viewPointToViewBackingPx(
            viewPoint: point,
            view: self
        )
        guard let scalar = try? editor.viewPointToCharOffset(xPx: xPx, yPx: yPx) else { return 0 }
        return Self.utf16Offset(fromScalarOffset: Int(scalar), in: text)
    }

    // MARK: - UTF16 <-> UnicodeScalar offset mapping (simple, O(n))

    private static func scalarOffset(fromUTF16Offset targetUtf16Offset: Int, in text: String) -> Int {
        let target = max(0, min(targetUtf16Offset, text.utf16.count))

        var utf16Cursor = 0
        var scalars = 0
        for scalar in text.unicodeScalars {
            let unitCount = scalar.value <= 0xFFFF ? 1 : 2
            if utf16Cursor + unitCount > target {
                break
            }
            utf16Cursor += unitCount
            scalars += 1
        }
        return scalars
    }

    private static func utf16Offset(fromScalarOffset targetScalarOffset: Int, in text: String) -> Int {
        let target = max(0, min(targetScalarOffset, text.unicodeScalars.count))

        var utf16Cursor = 0
        var scalars = 0
        for scalar in text.unicodeScalars {
            if scalars >= target {
                break
            }
            utf16Cursor += scalar.value <= 0xFFFF ? 1 : 2
            scalars += 1
        }
        return utf16Cursor
    }

    // MARK: - Draw scheduling

    /// Request a redraw for an on-demand `MTKView` (`isPaused = true`, `enableSetNeedsDisplay = true`).
    ///
    /// Why we do this:
    /// - 在某些 macOS/MTKView 组合下，仅设置 `needsDisplay = true` 有时不会触发 `MTKViewDelegate.draw(in:)`，
    ///   导致首次显示为空白。
    /// - `draw()` 可以强制触发一次 Metal draw pass；这里用 main queue coalesce，避免高频事件导致连环 draw。
    private func requestRedraw() {
        // 标记脏区：必须调用 super，避免走我们自己的 `setNeedsDisplay` override 形成递归。
        super.setNeedsDisplay(bounds)
        scheduleDrawIfPossible()
    }

    private func scheduleDrawIfPossible() {
        // 视图未挂到 window 时，强制 draw() 没意义；等 viewDidMoveToWindow / 下一次事件再 draw。
        guard window != nil else { return }

        guard drawScheduled == false else { return }
        drawScheduled = true
        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
            let delegateDesc = delegate.map { String(describing: type(of: $0)) } ?? "nil"
            NSLog(
                "EditorCoreSkiaView scheduleDraw: delegate=%@ paused=%d setNeeds=%d bounds(points)=%@ drawableSize(px)=%@",
                delegateDesc,
                isPaused ? 1 : 0,
                enableSetNeedsDisplay ? 1 : 0,
                NSStringFromSize(bounds.size),
                NSStringFromSize(drawableSize)
            )
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drawScheduled = false
            if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
                NSLog("EditorCoreSkiaView scheduleDraw: calling draw()")
            }
            // `MTKView.draw()` 在部分系统组合下不会触发 delegate（未知原因）。
            // 这里用 AppKit `displayIfNeeded()` 强制走 `draw(_:)`，而我们的 `draw(_:)` 会做 Metal render。
            self.displayIfNeeded()
        }
    }

    private func renderToCurrentDrawable(debugSource: String) {
        guard let drawable = currentDrawable else {
            if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
                NSLog("EditorCoreSkiaView render(%@): drawable=nil", debugSource)
            }
            return
        }

        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
            let t = drawable.texture
            NSLog(
                "EditorCoreSkiaView render(%@): drawable=ok tex=%dx%d pf=%d usage=0x%X storage=%d",
                debugSource,
                t.width,
                t.height,
                t.pixelFormat.rawValue,
                t.usage.rawValue,
                t.storageMode.rawValue
            )
        }

        let t0 = perfDebugEnabled ? CFAbsoluteTimeGetCurrent() : 0
        do {
            try editor.renderMetal(into: drawable.texture)
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfRenderMetalCount += 1
                perfRenderMetalTotalMs += dtMs
                perfReportIfNeeded()
            }
        } catch {
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfRenderMetalCount += 1
                perfRenderMetalTotalMs += dtMs
                perfReportIfNeeded()
            }
            NSLog("EditorCoreSkiaView Metal render failed(%@): %@", debugSource, String(describing: error))
            return
        }

        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

        // 关键：在某些系统/驱动组合下，如果用“完全空的 command buffer”去 present，
        // 会出现“present 成功但屏幕仍是空白”的现象（即使 Skia 已经在更早的 command buffer 里写入了 drawable 的 texture）。
        //
        // 这里做一个极轻量的 no-op render pass：
        // - loadAction = .load：不清屏，保留 Skia 画进去的内容
        // - storeAction = .store：保证结果可用于后续 present
        //
        // 这样可以确保 present 所在的 command buffer 明确“使用了”这个 drawable 的 texture。
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if didPresentFirstFrame == false {
            didPresentFirstFrame = true
            enableSetNeedsDisplay = true
            isPaused = true
        }
    }
}

extension EditorCoreSkiaView: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // MTKView 在窗口缩放 / backing scale 变化时会回调这里；同步 Rust viewport。
        updateViewportIfNeeded()
    }

    public func draw(in view: MTKView) {
        updateViewportIfNeeded()
        renderToCurrentDrawable(debugSource: "delegate")
    }
}

extension EditorCoreSkiaView: @preconcurrency NSTextInputClient {}
