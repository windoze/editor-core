import AppKit
import EditorCoreUIFFI
import Foundation
import Metal
import MetalKit

extension EditorCoreSkiaView {
    func didMutateDocumentText() {
        docContentEpoch &+= 1
        docTextCacheEpoch = 0
        docTextCache = nil
        docTextCacheScalarCount = 0
        cachedSelectedRange = nil
        cachedMarkedRange = nil
        lastHoverScalarIndex = nil
        clearCommandHoverFeedback()
        updateGutterWidthIfNeeded()
        startProcessingPoll()
        onDidMutateDocumentText?()
    }

    func notifySelectionDidChange(causedByTextMutation: Bool) {
        cachedSelectedRange = nil
        invalidateIMECharacterCoordinates()
        onDidChangeSelection?(causedByTextMutation)
    }

    @discardableResult
    func updateGutterWidthIfNeeded() -> Bool {
        do {
            let lineCount = try editor.logicalLineCount()
            let required = max(minimumGutterWidthCells, Self.requiredGutterWidthCells(lineCount: lineCount))
            if required == gutterWidthCells { return false }

            gutterWidthCells = required
            try editor.setGutterWidthCells(required)
            return true
        } catch {
            // Gutter resizing is best-effort; never break input/rendering because of it.
            return false
        }
    }

    /// 根据逻辑行数计算需要的 gutter 宽度（cell）。
    ///
    /// 说明：
    /// - renderer 会在 gutter 的前 2 个 cell 预留给 fold marker（更接近 VSCode 的 glyph margin 宽度），
    ///   因此行号至少需要 `2 + digits`。
    /// - `EditorCoreSkiaView` 当前的 `cellWidthPx` 是“固定网格”近似值（并非严格基于 font metrics），
    ///   当行号位数变大时，Skia 的字形 advance 误差会累积，导致行号靠近分隔线时出现轻微裁切/重叠。
    ///   因此从 5 位数（>= 10K 行）开始，我们额外预留 1 个 padding cell。
    internal static func requiredGutterWidthCells(lineCount: UInt32) -> UInt32 {
        let maxLineNo = max(1, lineCount)
        let digits = UInt32(String(maxLineNo).count)
        let extraPadding: UInt32 = digits >= 5 ? 1 : 0
        let foldMarkerCells: UInt32 = 2
        return max(4, foldMarkerCells + digits + extraPadding)
    }

    func documentTextForInputQueries() -> String? {
        if docTextCacheEpoch == docContentEpoch, let cached = docTextCache {
            return cached
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let text = try editor.text()
            docTextCache = text
            docTextCacheEpoch = docContentEpoch
            docTextCacheScalarCount = text.unicodeScalars.count

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

    func invalidateIMECharacterCoordinates() {
        // 用于 IME 候选窗定位：当 caret/marked range 或 viewport 变化时，需要通知系统重新查询 firstRect。
        textInputContext.invalidateCharacterCoordinates()
    }

    func startProcessingPoll() {
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

    /// Best-effort: start a short-lived async processing poll window.
    ///
    /// This is useful when a host enables Tree-sitter (or other async processors) on a fresh
    /// document without any edits yet, so the initial highlight/folding pass can be applied.
    public func kickProcessingPoll() {
        startProcessingPoll()
    }

    func stopProcessingPoll() {
        processingPollTimer?.cancel()
        processingPollTimer = nil
    }

    func pollProcessingTick() {
        if alwaysPollProcessing == false, ProcessInfo.processInfo.systemUptime > processingPollDeadlineUptime {
            stopProcessingPoll()
            return
        }

        do {
            let r = try editor.pollProcessing()
            if r.applied {
                requestRedraw()
                invalidateIMECharacterCoordinates()
                notifyViewportStateDidChange()
            }
            if r.applied || (r.pending == false && alwaysPollProcessing == false) {
                onDidApplyAsyncProcessing?()
            }
            if r.pending == false, alwaysPollProcessing == false {
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

    public override func resetCursorRects() {
        super.resetCursorRects()
        // VSCode-like: show text cursor when hovering over the editor content.
        addCursorRect(bounds, cursor: .iBeam)
    }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            updateCaretBlinkTimer()
            onDidBecomeFirstResponder?()
        }
        return ok
    }

    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            updateCaretBlinkTimer()
        }
        return ok
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Hover requires mouse moved events.
        window?.acceptsMouseMovedEvents = true
        updateLayerContentsScaleIfNeeded()
        updateViewportIfNeeded()
        updateCaretBlinkTimer()

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
        gutterDiagnosticOverlayView.frame = bounds
        updateViewportIfNeeded()
    }

    public override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        // 对 `MTKView`（on-demand 模式）来说，仅标记 needsDisplay 在某些系统版本上不会触发 GPU draw。
        // 我们在这里统一把它转成一次 `draw()`，这样外部（demo/scroll container/test）只要
        // 继续用 `needsDisplay = true` 就能可靠刷新画面。
        scheduleDrawIfPossible()
    }

    func updateLayerContentsScaleIfNeeded() {
        guard let window else { return }
        // 在某些 layer-backed 组合/缩放配置下，如果 contentsScale 不跟随 window 的 backingScaleFactor，
        // 会导致“画面贴屏”和“事件坐标 hit-test”不在同一套像素坐标系里（表现为点击/光标不对齐）。
        if layer?.contentsScale != window.backingScaleFactor {
            layer?.contentsScale = window.backingScaleFactor
        }
    }

    static let defaultFontSizePoints: CGFloat = 13.0
    static let defaultLineHeightMultiple: CGFloat = 18.0 / 13.0
    static let defaultCellWidthMultiple: CGFloat = 8.0 / 13.0
    static let defaultPaddingMultiple: CGFloat = 8.0 / 13.0

    static func normalizeFontSizePoints(_ v: CGFloat) -> CGFloat {
        guard v.isFinite else { return defaultFontSizePoints }
        return min(max(v, 6.0), 72.0)
    }

    func applyRenderMetricsIfNeeded(force: Bool) -> Bool {
        let fontPt = Self.normalizeFontSizePoints(fontSizePoints)
        let scale = max(1.0, scaleFactor)

        let fontSizePx: Float = Float(fontPt * scale)
        let lineHeightPx: Float = Float(fontPt * Self.defaultLineHeightMultiple * scale)
        let cellWidthPx: Float = Float(fontPt * Self.defaultCellWidthMultiple * scale)
        let paddingPx: Float = Float(fontPt * Self.defaultPaddingMultiple * scale)

        let snapshot = RenderMetricsSnapshot(
            fontSizePx: fontSizePx,
            lineHeightPx: lineHeightPx,
            cellWidthPx: cellWidthPx,
            paddingPx: paddingPx
        )

        if force == false, lastAppliedRenderMetrics == snapshot {
            return false
        }

        do {
            try editor.setRenderMetrics(
                fontSize: fontSizePx,
                lineHeightPx: lineHeightPx,
                cellWidthPx: cellWidthPx,
                paddingXPx: paddingPx,
                paddingYPx: paddingPx
            )
            self.lineHeightPx = lineHeightPx
            self.cellWidthPx = cellWidthPx
            self.paddingPx = paddingPx
            lastAppliedRenderMetrics = snapshot
            applyTextVerticalAlignIfNeeded(force: false)
            return true
        } catch {
            NSLog("EditorCoreSkiaView setRenderMetrics failed: %@", String(describing: error))
            return false
        }
    }

    func updateViewportIfNeeded() {
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

        let viewportChanged = (widthPx != viewportWidthPx) || (heightPx != viewportHeightPx) || (newScale != scaleFactor)
        if viewportChanged {
            viewportWidthPx = widthPx
            viewportHeightPx = heightPx
            scaleFactor = newScale

            // MTKView 的 drawableSize 以“像素”为单位；这里保持与 Rust viewport 一致。
            let newDrawableSize = CGSize(width: CGFloat(widthPx), height: CGFloat(heightPx))
            if drawableSize != newDrawableSize {
                drawableSize = newDrawableSize
            }
        }

        let metricsChanged = applyRenderMetricsIfNeeded(force: false)

        if viewportChanged {
            do {
                try editor.setViewportPx(widthPx: widthPx, heightPx: heightPx, scale: Float(newScale))
            } catch {
                NSLog("EditorCoreSkiaView setViewportPx failed: %@", String(describing: error))
            }
        }

        if viewportChanged, ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_SCALE"] == "1" {
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

        if viewportChanged {
            applyCaretAppearanceIfNeeded(force: false)
        }

        if viewportChanged || metricsChanged {
            requestRedraw()
            invalidateIMECharacterCoordinates()
            notifyViewportStateDidChange()
        }
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
}
