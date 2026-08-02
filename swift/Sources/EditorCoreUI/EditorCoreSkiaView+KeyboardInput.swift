import AppKit
import EditorCoreUIFFI
import Foundation
import Metal
import MetalKit

extension EditorCoreSkiaView {
    // MARK: - Keyboard / Text input

    public override func keyDown(with event: NSEvent) {
        dismissHoverUIForUserAction()

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
    func handleCommandShortcutsIfNeeded(event: NSEvent) -> Bool {
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
        dismissHoverUIForUserAction()

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
            notifySelectionDidChange(causedByTextMutation: true)
            onDidCommitText?(text)
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
        notifyViewportStateDidChange()
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        dismissHoverUIForUserAction()

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
            notifySelectionDidChange(causedByTextMutation: true)
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
        notifyViewportStateDidChange()
    }

    public func unmarkText() {
        dismissHoverUIForUserAction()

        editor.unmarkText()
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    public override func doCommand(by selector: Selector) {
        dismissHoverUIForUserAction()

        updateViewportIfNeeded()
        let t0 = perfDebugEnabled ? CFAbsoluteTimeGetCurrent() : 0
        var didEditText = false
        var didChangeSelection = false
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
                didChangeSelection = true
            case #selector(moveRight(_:)):
                let sel = try editor.selectionOffsets()
                if sel.start != sel.end {
                    try editor.setSelections([EcuSelectionRange(start: sel.end, end: sel.end)], primaryIndex: 0)
                } else {
                    try editor.moveGraphemeRight()
                }
                didChangeSelection = true
            case #selector(moveWordLeft(_:)):
                let sel = try editor.selectionOffsets()
                if sel.start != sel.end {
                    try editor.setSelections([EcuSelectionRange(start: sel.start, end: sel.start)], primaryIndex: 0)
                }
                try editor.moveWordLeft()
                didChangeSelection = true
            case #selector(moveWordRight(_:)):
                let sel = try editor.selectionOffsets()
                if sel.start != sel.end {
                    try editor.setSelections([EcuSelectionRange(start: sel.end, end: sel.end)], primaryIndex: 0)
                }
                try editor.moveWordRight()
                didChangeSelection = true
            case #selector(moveToBeginningOfLine(_:)):
                try editor.moveToVisualLineStart()
                didChangeSelection = true
            case #selector(moveToEndOfLine(_:)):
                try editor.moveToVisualLineEnd()
                didChangeSelection = true
            case #selector(moveToLeftEndOfLine(_:)):
                // Some keybindings (Home / Cmd+Left in certain layouts) map to the bidi-aware variants.
                try editor.moveToVisualLineStart()
                didChangeSelection = true
            case #selector(moveToRightEndOfLine(_:)):
                try editor.moveToVisualLineEnd()
                didChangeSelection = true
            case #selector(moveToBeginningOfDocument(_:)):
                try editor.moveToDocumentStart()
                didChangeSelection = true
            case #selector(moveToEndOfDocument(_:)):
                try editor.moveToDocumentEnd()
                didChangeSelection = true
            case #selector(scrollToBeginningOfDocument(_:)):
                // Home key in some contexts is dispatched as a "scroll" action.
                // We treat it as a caret move for editor behavior consistency.
                try editor.moveToDocumentStart()
                didChangeSelection = true
            case #selector(scrollToEndOfDocument(_:)):
                try editor.moveToDocumentEnd()
                didChangeSelection = true
            case #selector(pageUp(_:)):
                try editor.moveVisualByPages(-1)
                didChangeSelection = true
            case #selector(pageDown(_:)):
                try editor.moveVisualByPages(1)
                didChangeSelection = true
            case #selector(scrollPageUp(_:)):
                try editor.moveVisualByPages(-1)
                didChangeSelection = true
            case #selector(scrollPageDown(_:)):
                try editor.moveVisualByPages(1)
                didChangeSelection = true
            case #selector(moveUp(_:)):
                try editor.moveVisualByRows(-1)
                didChangeSelection = true
            case #selector(moveDown(_:)):
                try editor.moveVisualByRows(1)
                didChangeSelection = true
            case #selector(moveLeftAndModifySelection(_:)):
                try editor.moveGraphemeLeftAndModifySelection()
                didChangeSelection = true
            case #selector(moveRightAndModifySelection(_:)):
                try editor.moveGraphemeRightAndModifySelection()
                didChangeSelection = true
            case #selector(moveWordLeftAndModifySelection(_:)):
                try editor.moveWordLeftAndModifySelection()
                didChangeSelection = true
            case #selector(moveWordRightAndModifySelection(_:)):
                try editor.moveWordRightAndModifySelection()
                didChangeSelection = true
            case #selector(moveToBeginningOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineStartAndModifySelection()
                didChangeSelection = true
            case #selector(moveToEndOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineEndAndModifySelection()
                didChangeSelection = true
            case #selector(moveToLeftEndOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineStartAndModifySelection()
                didChangeSelection = true
            case #selector(moveToRightEndOfLineAndModifySelection(_:)):
                try editor.moveToVisualLineEndAndModifySelection()
                didChangeSelection = true
            case #selector(moveToBeginningOfDocumentAndModifySelection(_:)):
                try editor.moveToDocumentStartAndModifySelection()
                didChangeSelection = true
            case #selector(moveToEndOfDocumentAndModifySelection(_:)):
                try editor.moveToDocumentEndAndModifySelection()
                didChangeSelection = true
            case Selector(("scrollToBeginningOfDocumentAndModifySelection:")):
                try editor.moveToDocumentStartAndModifySelection()
                didChangeSelection = true
            case Selector(("scrollToEndOfDocumentAndModifySelection:")):
                try editor.moveToDocumentEndAndModifySelection()
                didChangeSelection = true
            case #selector(pageUpAndModifySelection(_:)):
                try editor.moveVisualByPagesAndModifySelection(-1)
                didChangeSelection = true
            case #selector(pageDownAndModifySelection(_:)):
                try editor.moveVisualByPagesAndModifySelection(1)
                didChangeSelection = true
            case Selector(("scrollPageUpAndModifySelection:")):
                try editor.moveVisualByPagesAndModifySelection(-1)
                didChangeSelection = true
            case Selector(("scrollPageDownAndModifySelection:")):
                try editor.moveVisualByPagesAndModifySelection(1)
                didChangeSelection = true
            case #selector(moveUpAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(-1)
                didChangeSelection = true
            case #selector(moveDownAndModifySelection(_:)):
                try editor.moveVisualByRowsAndModifySelection(1)
                didChangeSelection = true
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
                let wasSnippet = try editor.hasActiveSnippetSession()
                try editor.insertTab()
                didEditText = !wasSnippet
                didChangeSelection = true
            case #selector(insertBacktab(_:)):
                let wasSnippet = try editor.hasActiveSnippetSession()
                try editor.insertBacktab()
                didEditText = !wasSnippet
                didChangeSelection = true
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
        if didChangeSelection || didEditText {
            notifySelectionDidChange(causedByTextMutation: didEditText)
        }
        if perfDebugEnabled {
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            perfDoCommandCount += 1
            perfDoCommandTotalMs += dtMs
            perfReportIfNeeded()
        }
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    /// Jump the primary caret to the matching bracket (if any).
    ///
    /// This is a convenience wrapper that also triggers redraw + viewport observer callbacks,
    /// so hosts can wire it into command palettes / menus without re-implementing bookkeeping.
    public func moveToMatchingBracket() {
        dismissHoverUIForUserAction()

        updateViewportIfNeeded()
        do {
            try editor.moveToMatchingBracket()
        } catch {
            NSSound.beep()
            return
        }
        notifySelectionDidChange(causedByTextMutation: false)
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    /// Jump back in the editor jump list (no-op when empty).
    public func jumpBack() {
        dismissHoverUIForUserAction()

        updateViewportIfNeeded()
        do {
            try editor.jumpBack()
        } catch {
            NSSound.beep()
            return
        }
        notifySelectionDidChange(causedByTextMutation: false)
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    /// Jump forward in the editor jump list (no-op when empty).
    public func jumpForward() {
        dismissHoverUIForUserAction()

        updateViewportIfNeeded()
        do {
            try editor.jumpForward()
        } catch {
            NSSound.beep()
            return
        }
        notifySelectionDidChange(causedByTextMutation: false)
        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
    }

    static let defaultLSPFormattingOptionsJSON = """
    { "tabSize": 4, "insertSpaces": true }
    """

    /// Format the current document via LSP (`textDocument/formatting`) and apply edits locally.
    ///
    /// This is intended for explicit user actions (command palette / menu item).
    @discardableResult
    public func formatDocumentWithLSP(timeoutMs: UInt32 = 2000) -> Bool {
        let result = formatDocumentWithLSPResult(timeoutMs: timeoutMs)
        if case .unavailable = result {
            NSSound.beep()
        } else if case .failed = result {
            NSSound.beep()
        }
        return result.didApply
    }

    /// Format the current document via LSP and return a typed outcome for UI feedback/tests.
    @discardableResult
    public func formatDocumentWithLSPResult(timeoutMs: UInt32 = 2000) -> EditorCoreLSPFormattingResult {
        dismissHoverUIForUserAction()

        let didApply: Bool
        updateViewportIfNeeded()
        do {
            guard try editor.lspIsEnabled() else {
                return .unavailable("LSP is not enabled for this document.")
            }

            didApply = try editor.lspFormatDocument(
                formattingOptionsJSON: Self.defaultLSPFormattingOptionsJSON,
                timeoutMs: timeoutMs
            )
            if didApply {
                didMutateDocumentText()
                notifySelectionDidChange(causedByTextMutation: true)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
        return didApply ? .applied : .noEdits
    }

    /// Format an editor-core char-offset range via LSP (`textDocument/rangeFormatting`).
    @discardableResult
    public func formatRangeWithLSP(startOffset: UInt32, endOffset: UInt32, timeoutMs: UInt32 = 2000) -> Bool {
        let result = formatRangeWithLSPResult(startOffset: startOffset, endOffset: endOffset, timeoutMs: timeoutMs)
        if case .unavailable = result {
            NSSound.beep()
        } else if case .failed = result {
            NSSound.beep()
        }
        return result.didApply
    }

    /// Format an editor-core char-offset range via LSP and return a typed outcome for UI feedback/tests.
    @discardableResult
    public func formatRangeWithLSPResult(
        startOffset: UInt32,
        endOffset: UInt32,
        timeoutMs: UInt32 = 2000
    ) -> EditorCoreLSPFormattingResult {
        dismissHoverUIForUserAction()

        let didApply: Bool
        updateViewportIfNeeded()
        do {
            guard try editor.lspIsEnabled() else {
                return .unavailable("LSP is not enabled for this document.")
            }

            didApply = try editor.lspFormatRange(
                startOffset: startOffset,
                endOffset: endOffset,
                formattingOptionsJSON: Self.defaultLSPFormattingOptionsJSON,
                timeoutMs: timeoutMs
            )
            if didApply {
                didMutateDocumentText()
                notifySelectionDidChange(causedByTextMutation: true)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        requestRedraw()
        invalidateIMECharacterCoordinates()
        notifyViewportStateDidChange()
        return didApply ? .applied : .noEdits
    }

    /// Request LSP on-type formatting at a logical position and apply the returned edits.
    @discardableResult
    public func formatOnTypeWithLSP(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        trigger: String,
        timeoutMs: UInt32 = 2000
    ) -> Bool {
        formatOnTypeWithLSPResult(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            trigger: trigger,
            timeoutMs: timeoutMs
        ).didApply
    }

    /// Request LSP on-type formatting and return a typed outcome.
    @discardableResult
    public func formatOnTypeWithLSPResult(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        trigger: String,
        timeoutMs: UInt32 = 2000
    ) -> EditorCoreLSPFormattingResult {
        let didApply: Bool
        updateViewportIfNeeded()
        do {
            guard try editor.lspIsEnabled() else {
                return .unavailable("LSP is not enabled for this document.")
            }

            didApply = try editor.lspFormatOnType(
                logicalLine: logicalLine,
                logicalColumn: logicalColumn,
                trigger: trigger,
                formattingOptionsJSON: Self.defaultLSPFormattingOptionsJSON,
                timeoutMs: timeoutMs
            )
            if didApply {
                didMutateDocumentText()
                notifySelectionDidChange(causedByTextMutation: true)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        if didApply {
            requestRedraw()
            invalidateIMECharacterCoordinates()
            notifyViewportStateDidChange()
        }
        return didApply ? .applied : .noEdits
    }
}
