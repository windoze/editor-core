import AppKit
import EditorCoreUIFFI
import Foundation

/// 自绘版 AppKit 组件（Option 2）：
/// - Rust: editor-core + editor-core-ui + Skia（CPU raster 输出 RGBA buffer）
/// - Swift/AppKit: NSView 负责承接事件与把 RGBA buffer 贴到屏幕
///
/// 这是一个“先把正确性与 IME 桥打通”的 MVP：
/// - caret / selection / mouse drag selection
/// - insertText / markedText（IME 组合输入）
/// - undo/redo
@MainActor
public final class EditorCoreSkiaView: NSView {
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

    private var pixelBuffer: [UInt8] = []
    private var viewportWidthPx: UInt32 = 0
    private var viewportHeightPx: UInt32 = 0
    private var scaleFactor: CGFloat = 1
    private var didLogScaleDebugOnce: Bool = false
    private var lastInputDebugLogUptime: TimeInterval = 0

    private var lineHeightPx: Float = 18
    private var gutterWidthCells: UInt32 = 4

    private var rectSelectionAnchorOffset: UInt32?
    private var lineSelectionAnchorOffset: UInt32?
    private var wordSelectionAnchorOffset: UInt32?
    private var wordSelectionOrigin: (start: UInt32, end: UInt32)?

    private lazy var textInputContext = NSTextInputContext(client: self)

    private func invalidateIMECharacterCoordinates() {
        // 用于 IME 候选窗定位：当 caret/marked range 或 viewport 变化时，需要通知系统重新查询 firstRect。
        textInputContext.invalidateCharacterCoordinates()
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
        super.init(frame: .zero)

        wantsLayer = true

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
    public override init(frame frameRect: NSRect) {
        fatalError("unavailable")
    }

    @available(*, unavailable, message: "请使用 init(library:initialText:viewportWidthCells:) 构造。")
    public required init?(coder: NSCoder) {
        fatalError("unavailable")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerContentsScaleIfNeeded()
        updateViewportIfNeeded()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerContentsScaleIfNeeded()
        updateViewportIfNeeded()
        needsDisplay = true
    }

    public override func layout() {
        super.layout()
        updateViewportIfNeeded()
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
        let backingSize: NSSize
        if window != nil {
            backingSize = convertToBacking(pointsSize)
        } else {
            let fallbackScale = NSScreen.main?.backingScaleFactor ?? 1
            backingSize = NSSize(width: pointsSize.width * fallbackScale, height: pointsSize.height * fallbackScale)
        }

        let widthPx = UInt32(max(1, Int(backingSize.width.rounded())))
        let heightPx = UInt32(max(1, Int(backingSize.height.rounded())))
        let newScale: CGFloat
        if pointsSize.width > 0, pointsSize.height > 0 {
            let sx = backingSize.width / pointsSize.width
            let sy = backingSize.height / pointsSize.height
            newScale = (sx + sy) * 0.5
        } else {
            newScale = NSScreen.main?.backingScaleFactor ?? 1
        }

        guard widthPx != viewportWidthPx || heightPx != viewportHeightPx || newScale != scaleFactor else {
            return
        }

        viewportWidthPx = widthPx
        viewportHeightPx = heightPx
        scaleFactor = newScale

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

        let required = Int(widthPx) * Int(heightPx) * 4
        if pixelBuffer.count != required {
            pixelBuffer = Array(repeating: 0, count: required)
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

        needsDisplay = true
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        updateViewportIfNeeded()

        guard viewportWidthPx > 0, viewportHeightPx > 0 else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        do {
            _ = try editor.renderRGBA(into: &pixelBuffer)
        } catch {
            // 如果渲染失败，至少给出一个可见背景，避免“看起来什么都没有”
            NSColor.textBackgroundColor.setFill()
            dirtyRect.fill()
            NSLog("EditorCoreSkiaView render failed: %@", String(describing: error))
            return
        }

        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_SCALE"] == "1" {
            NSLog(
                "EditorCoreSkiaView draw debug: ctm=%@ viewport=%ux%u scaleFactor=%.3f",
                String(describing: ctx.ctm),
                viewportWidthPx,
                viewportHeightPx,
                Double(scaleFactor)
            )
        }

        pixelBuffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            guard let img = SkiaRasterCGImage.makeCGImageRGBA8888Premul(
                widthPx: Int(viewportWidthPx),
                heightPx: Int(viewportHeightPx),
                rgbaBytes: base,
                byteCount: raw.count
            ) else { return }

            // 这里不要把 `bounds` 乘以 `scaleFactor`：
            // - 在 AppKit/Retina 下，`CGContext` 的 user space 往往仍然是 “points”，即使 `ctm` 看起来是 identity；
            //   实际的像素密度由系统（backing store / layer.contentsScale）负责映射。
            // - 如果我们把 dstRect 放大（例如 bounds * scaleFactor），就会把 2x 的 backing buffer 再放大一遍，
            //   结果表现为：光标/选区移动速度不对、鼠标 hit-test 看起来“跑偏”。
            let dstRect = bounds
            SkiaRasterCGImage.drawCGImage(img, in: ctx, dstRect: dstRect, viewIsFlipped: isFlipped)
        }

        ctx.restoreGState()
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
        needsDisplay = true
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
        needsDisplay = true
        invalidateIMECharacterCoordinates()
    }

    public override func mouseUp(with event: NSEvent) {
        rectSelectionAnchorOffset = nil
        lineSelectionAnchorOffset = nil
        wordSelectionAnchorOffset = nil
        wordSelectionOrigin = nil
        editor.mouseUp()
        needsDisplay = true
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
        handleScroll(
            deltaYPoints: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
        )
    }

    // MARK: - Smooth scroll helper (testable)

    /// Smooth-scroll handler shared by `scrollWheel(with:)` and unit tests.
    ///
    /// - Parameters:
    ///   - deltaYPoints: For precise scrolling events, this is the point delta. For coarse scrolling
    ///     (mouse wheel), AppKit's delta is closer to “line units”.
    ///   - hasPreciseScrollingDeltas: Mirrors `NSEvent.hasPreciseScrollingDeltas`.
    ///   - isDirectionInvertedFromDevice: Mirrors `NSEvent.isDirectionInvertedFromDevice`.
    func handleScroll(
        deltaYPoints: CGFloat,
        hasPreciseScrollingDeltas: Bool,
        isDirectionInvertedFromDevice: Bool = false
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
            //
            // AppKit 的 `scrollingDeltaY` 会受“自然滚动”设置影响：
            // - `isDirectionInvertedFromDevice == false`: 传统滚轮方向，通常需要取反才能得到“向下滚动为正”
            // - `isDirectionInvertedFromDevice == true`: 自然滚动方向，通常不需要取反
            let docDeltaPx = isDirectionInvertedFromDevice ? deltaPx : -deltaPx
            editor.scrollByPixels(Float(docDeltaPx))
            needsDisplay = true
            invalidateIMECharacterCoordinates()
            onViewportStateDidChange?()
        }
    }

    // MARK: - Keyboard / Text input

    public override func keyDown(with event: NSEvent) {
        // 让系统把按键解释成 insertText / setMarkedText / doCommand(by:)
        interpretKeyEvents([event])
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let s = string as? String {
            text = s
        } else if let a = string as? NSAttributedString {
            text = a.string
        } else {
            text = String(describing: string)
        }

        do {
            try editor.commitText(text)
        } catch {
            NSSound.beep()
        }
        needsDisplay = true
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let s = string as? String {
            text = s
        } else if let a = string as? NSAttributedString {
            text = a.string
        } else {
            text = String(describing: string)
        }

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
                let doc = try editor.text()
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
        } catch {
            NSSound.beep()
        }
        needsDisplay = true
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    public func unmarkText() {
        editor.unmarkText()
        needsDisplay = true
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    public override func doCommand(by selector: Selector) {
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
            case #selector(moveToBeginningOfDocument(_:)):
                try editor.moveToDocumentStart()
            case #selector(moveToEndOfDocument(_:)):
                try editor.moveToDocumentEnd()
            case #selector(pageUp(_:)):
                try editor.moveVisualByPages(-1)
            case #selector(pageDown(_:)):
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
            case #selector(moveToBeginningOfDocumentAndModifySelection(_:)):
                try editor.moveToDocumentStartAndModifySelection()
            case #selector(moveToEndOfDocumentAndModifySelection(_:)):
                try editor.moveToDocumentEndAndModifySelection()
            case #selector(pageUpAndModifySelection(_:)):
                try editor.moveVisualByPagesAndModifySelection(-1)
            case #selector(pageDownAndModifySelection(_:)):
                try editor.moveVisualByPagesAndModifySelection(1)
            case #selector(moveUpAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(-1)
            case #selector(moveDownAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(1)
            case #selector(deleteBackward(_:)):
                try editor.backspace()
            case #selector(deleteForward(_:)):
                try editor.deleteForward()
            case #selector(deleteWordBackward(_:)):
                try editor.deleteWordBack()
            case #selector(deleteWordForward(_:)):
                try editor.deleteWordForward()
            case #selector(insertNewline(_:)):
                try editor.commitText("\n")
            case #selector(insertTab(_:)):
                try editor.commitText("\t")
            case #selector(cancelOperation(_:)):
                // Escape: cancel marked text / composition (restore original replaced range).
                let marked = try editor.markedRange()
                if marked.hasMarked {
                    try editor.setMarkedText("", selectedStart: 0, selectedLen: 0)
                }
            case Selector(("undo:")):
                try editor.undo()
            case Selector(("redo:")):
                try editor.redo()
            default:
                break
            }
        } catch {
            NSSound.beep()
        }
        needsDisplay = true
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    // MARK: - Clipboard

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
            needsDisplay = true
            invalidateIMECharacterCoordinates()
            onViewportStateDidChange?()
        } catch {
            NSSound.beep()
        }
    }

    @objc(paste:)
    public func paste(_ sender: Any?) {
        guard let text = pasteboard.string(forType: .string), text.isEmpty == false else { return }
        do {
            try editor.commitText(text)
        } catch {
            NSSound.beep()
        }
        needsDisplay = true
        invalidateIMECharacterCoordinates()
        onViewportStateDidChange?()
    }

    // MARK: - NSTextInputClient state queries

    public func selectedRange() -> NSRange {
        guard let text = try? editor.text() else { return NSRange(location: 0, length: 0) }
        guard let sel = try? editor.selectionOffsets() else { return NSRange(location: 0, length: 0) }
        let startUtf16 = Self.utf16Offset(fromScalarOffset: Int(sel.start), in: text)
        let endUtf16 = Self.utf16Offset(fromScalarOffset: Int(sel.end), in: text)
        return NSRange(location: startUtf16, length: max(0, endUtf16 - startUtf16))
    }

    public func markedRange() -> NSRange {
        guard let text = try? editor.text() else { return NSRange(location: NSNotFound, length: 0) }
        guard let marked = try? editor.markedRange(), marked.hasMarked else { return NSRange(location: NSNotFound, length: 0) }
        let startUtf16 = Self.utf16Offset(fromScalarOffset: Int(marked.start), in: text)
        let endUtf16 = Self.utf16Offset(fromScalarOffset: Int(marked.start + marked.len), in: text)
        return NSRange(location: startUtf16, length: max(0, endUtf16 - startUtf16))
    }

    public func hasMarkedText() -> Bool {
        guard let marked = try? editor.markedRange() else { return false }
        return marked.hasMarked
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let text = try? editor.text() else { return nil }
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
        // 这个 rect 用于 IME 候选窗定位；我们用 range.location 对应的字符 offset（UTF-16→scalar）计算 caret 的 top-left。
        actualRange?.pointee = range
        guard let window else { return .zero }
        guard let text = try? editor.text() else { return .zero }

        let scalarOffset = Self.scalarOffset(fromUTF16Offset: range.location, in: text)

        guard let pt = try? editor.charOffsetToViewPoint(offset: UInt32(scalarOffset)) else { return .zero }

        let viewPoint = convertFromBacking(NSPoint(x: CGFloat(pt.xPx), y: CGFloat(pt.yPx)))
        let viewLineHeight = convertFromBacking(NSSize(width: 0, height: CGFloat(pt.lineHeightPx))).height

        let xPt = viewPoint.x
        let yPt = viewPoint.y
        let hPt = viewLineHeight

        let rectInView = NSRect(x: xPt, y: yPt, width: 1, height: hPt)
        let rectInWindow = convert(rectInView, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    public func characterIndex(for point: NSPoint) -> Int {
        // point 是 view 坐标（points），我们做 hit-test 并返回 UTF-16 index
        guard let text = try? editor.text() else { return 0 }
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
}

extension EditorCoreSkiaView: @preconcurrency NSTextInputClient {}
