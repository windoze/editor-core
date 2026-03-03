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

    private var pixelBuffer: [UInt8] = []
    private var viewportWidthPx: UInt32 = 0
    private var viewportHeightPx: UInt32 = 0
    private var scaleFactor: CGFloat = 1

    private var lineHeightPx: Float = 18
    private var gutterWidthCells: UInt32 = 4

    private var rectSelectionAnchorOffset: UInt32?

    private lazy var textInputContext = NSTextInputContext(client: self)

    public override var acceptsFirstResponder: Bool { true }
    public override var isFlipped: Bool { true }
    public override var inputContext: NSTextInputContext? { textInputContext }

    public init(library: EditorCoreUIFFILibrary, initialText: String = "", viewportWidthCells: UInt32 = 120) throws {
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
        updateViewportIfNeeded()
    }

    public override func layout() {
        super.layout()
        updateViewportIfNeeded()
    }

    private func updateViewportIfNeeded() {
        let newScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let widthPx = UInt32(max(1, Int(bounds.width * newScale)))
        let heightPx = UInt32(max(1, Int(bounds.height * newScale)))

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

        needsDisplay = true
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

        pixelBuffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            guard let img = SkiaRasterCGImage.makeCGImageRGBA8888Premul(
                widthPx: Int(viewportWidthPx),
                heightPx: Int(viewportHeightPx),
                rgbaBytes: base,
                byteCount: raw.count
            ) else { return }

            let dstRect = SkiaRasterCGImage.destinationRectInCurrentContext(
                viewBounds: bounds,
                viewScaleFactor: scaleFactor,
                ctx: ctx
            )
            SkiaRasterCGImage.drawCGImage(img, in: ctx, dstRect: dstRect, viewIsFlipped: isFlipped)
        }

        ctx.restoreGState()
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let xPx = Float(p.x * scaleFactor)
        let yPx = Float(p.y * scaleFactor)

        rectSelectionAnchorOffset = nil

        do {
            if event.modifierFlags.contains(.command) {
                // Cmd+Click: add a new caret at point (multi-cursor).
                let offset = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                try editor.addCaret(atCharOffset: offset, makePrimary: true)
            } else if event.modifierFlags.contains(.option) {
                // Option+Drag: rectangular (box) selection.
                let anchor = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                rectSelectionAnchorOffset = anchor
                try editor.setRectSelection(anchorOffset: anchor, activeOffset: anchor)
            } else {
                try editor.mouseDown(xPx: xPx, yPx: yPx)

                // Double/triple click selection.
                if event.clickCount == 2 {
                    try editor.selectWord()
                } else if event.clickCount >= 3 {
                    try editor.selectLine()
                }
            }
        } catch {
            NSSound.beep()
        }
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let xPx = Float(p.x * scaleFactor)
        let yPx = Float(p.y * scaleFactor)
        do {
            if let anchor = rectSelectionAnchorOffset {
                let active = try editor.viewPointToCharOffset(xPx: xPx, yPx: yPx)
                try editor.setRectSelection(anchorOffset: anchor, activeOffset: active)
            } else {
                try editor.mouseDragged(xPx: xPx, yPx: yPx)
            }
        } catch {
            NSSound.beep()
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        rectSelectionAnchorOffset = nil
        editor.mouseUp()
        needsDisplay = true
    }

    public override func scrollWheel(with event: NSEvent) {
        // scrollingDeltaY：正值通常代表向上滚动（内容向下），这里换算成“行数”增量
        let lineHeightPt = CGFloat(max(1, lineHeightPx)) / scaleFactor
        if lineHeightPt > 0 {
            let rows = Int32((event.scrollingDeltaY / lineHeightPt).rounded())
            if rows != 0 {
                editor.scrollByRows(-rows)
                needsDisplay = true
            }
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
            try editor.setMarkedText(text)
        } catch {
            NSSound.beep()
        }
        needsDisplay = true
    }

    public func unmarkText() {
        editor.unmarkText()
        needsDisplay = true
    }

    public override func doCommand(by selector: Selector) {
        do {
            switch selector {
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
            case #selector(moveUp(_:)):
                try editor.moveVisualByRows(-1)
            case #selector(moveDown(_:)):
                try editor.moveVisualByRows(1)
            case #selector(moveLeftAndModifySelection(_:)):
                try editor.moveGraphemeLeftAndModifySelection()
            case #selector(moveRightAndModifySelection(_:)):
                try editor.moveGraphemeRightAndModifySelection()
            case #selector(moveUpAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(-1)
            case #selector(moveDownAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(1)
            case #selector(deleteBackward(_:)):
                try editor.backspace()
            case #selector(deleteForward(_:)):
                try editor.deleteForward()
            case #selector(insertNewline(_:)):
                try editor.commitText("\n")
            case #selector(insertTab(_:)):
                try editor.commitText("\t")
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

        let xPt = CGFloat(pt.xPx) / scaleFactor
        let yPt = CGFloat(pt.yPx) / scaleFactor
        let hPt = CGFloat(pt.lineHeightPx) / scaleFactor

        let rectInView = NSRect(x: xPt, y: yPt, width: 1, height: hPt)
        let rectInWindow = convert(rectInView, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    public func characterIndex(for point: NSPoint) -> Int {
        // point 是 view 坐标（points），我们做 hit-test 并返回 UTF-16 index
        guard let text = try? editor.text() else { return 0 }
        let xPx = Float(point.x * scaleFactor)
        let yPx = Float(point.y * scaleFactor)
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
