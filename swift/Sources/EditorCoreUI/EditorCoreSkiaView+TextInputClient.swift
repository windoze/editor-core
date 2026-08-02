import AppKit
import EditorCoreUIFFI
import Foundation
import Metal
import MetalKit

extension EditorCoreSkiaView {
    // MARK: - Clipboard

    public override func selectAll(_ sender: Any?) {
        dismissHoverUIForUserAction()

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
            notifySelectionDidChange(causedByTextMutation: false)
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    @objc(undo:)
    public func undo(_ sender: Any?) {
        dismissHoverUIForUserAction()

        do {
            try editor.undo()
            didMutateDocumentText()
            notifySelectionDidChange(causedByTextMutation: true)
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    @objc(redo:)
    public func redo(_ sender: Any?) {
        dismissHoverUIForUserAction()

        do {
            try editor.redo()
            didMutateDocumentText()
            notifySelectionDidChange(causedByTextMutation: true)
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    @objc(copy:)
    public func copy(_ sender: Any?) {
        dismissHoverUIForUserAction()

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
        dismissHoverUIForUserAction()

        do {
            let text = try editor.selectedText()
            guard text.isEmpty == false else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            try editor.deleteSelectionsOnly()
            didMutateDocumentText()
            notifySelectionDidChange(causedByTextMutation: true)
            requestRedraw()
            invalidateIMECharacterCoordinates()
            notifyViewportStateDidChange()
        } catch {
            NSSound.beep()
        }
    }

    @objc(paste:)
    public func paste(_ sender: Any?) {
        dismissHoverUIForUserAction()

        updateViewportIfNeeded()
        guard let text = pasteboard.string(forType: .string), text.isEmpty == false else { return }
        do {
            try editor.pasteText(text)
            didMutateDocumentText()
            notifySelectionDidChange(causedByTextMutation: true)
        } catch {
            NSSound.beep()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
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

    static func scalarOffset(fromUTF16Offset targetUtf16Offset: Int, in text: String) -> Int {
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

    static func utf16Offset(fromScalarOffset targetScalarOffset: Int, in text: String) -> Int {
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
