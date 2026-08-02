import CEditorCoreUIFFI
import Foundation
import Metal

extension EditorUI {
    public func setMarkedText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_marked_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_marked_text")
    }

    /// Set IME marked text (preedit) with selection and optional replacement range.
    ///
    /// - `selectedStart/selectedLen`: selection within `text` (Unicode scalar offsets).
    /// - `replaceStart/replaceLen`: document char-offset range to replace.
    ///   Pass `UInt32.max` for `replaceStart` to let Rust pick (existing marked range / current selection).
    public func setMarkedText(
        _ text: String,
        selectedStart: UInt32,
        selectedLen: UInt32,
        replaceStart: UInt32 = UInt32.max,
        replaceLen: UInt32 = 0
    ) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_marked_text_ex(handle, cstr, selectedStart, selectedLen, replaceStart, replaceLen)
        }
        try library.ensureStatus(status, context: "editor_ui_set_marked_text_ex")
    }

    public func unmarkText() {
        editor_core_ui_ffi_editor_ui_unmark_text(handle)
    }

    public func commitText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_commit_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_commit_text")
    }

    /// Paste text from the clipboard.
    ///
    /// Notes:
    /// - This always uses the bulk insert path in Rust (no auto-pairs), even for a single character,
    ///   to match typical editor semantics for paste operations.
    public func pasteText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_paste_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_paste_text")
    }

    public func mouseDown(xPx: Float, yPx: Float) throws {
        try mouseDownEx(xPx: xPx, yPx: yPx, modifiers: 0, clickCount: 1)
    }

    /// Mouse down with modifier + click-count support.
    ///
    /// - Parameters:
    ///   - modifiers: bit layout mirrors the C header (`editor_core_ui_ffi.h`)
    ///   - clickCount: 1=single, 2=double, 3=triple, 4+=paragraph.
    public func mouseDownEx(
        xPx: Float,
        yPx: Float,
        modifiers: UInt32,
        clickCount: UInt32
    ) throws {
        let status = editor_core_ui_ffi_editor_ui_mouse_down_ex(handle, xPx, yPx, modifiers, clickCount)
        try library.ensureStatus(status, context: "editor_ui_mouse_down_ex")
    }

    public func mouseDragged(xPx: Float, yPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_mouse_dragged(handle, xPx, yPx)
        try library.ensureStatus(status, context: "editor_ui_mouse_dragged")
    }

    public func mouseUp() {
        editor_core_ui_ffi_editor_ui_mouse_up(handle)
    }
}
