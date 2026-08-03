import CEditorCoreFFI
import Foundation

private struct EditorStateTextResponse: Decodable {
    let text: String
}

public final class EditorState {
    public let ffi: EditorCoreFFILibrary
    let handle: OpaquePointer

    public init(
        library: EditorCoreFFILibrary,
        initialText: String,
        viewportWidth: UInt
    ) throws {
        self.ffi = library
        let width = try checkedFFIUInt32(max(1, viewportWidth), context: "editor_state_new.viewport_width")

        let handle: OpaquePointer? = initialText.withCString { textPtr in
            return editor_core_ffi_editor_state_new(textPtr, width)
        }
        guard let handle else {
            let message = library.lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: "editor_state_new", message: message.isEmpty ? "no last_error_message" : message)
        }
        self.handle = handle
    }

    deinit {
        editor_core_ffi_editor_state_free(handle)
    }

    public func text() throws -> String {
        let json = try ffi.takeOwnedCString(editor_core_ffi_editor_state_text(handle), context: "editor_state_text")
        return try JSON.decode(EditorStateTextResponse.self, from: json, context: "editor_state_text").text
    }

    public func executeJSON(_ commandJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = commandJSON.withCString { jsonPtr in
            editor_core_ffi_editor_state_execute_json(handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "editor_state_execute_json")
    }

    public func executeEnvelopeJSON(_ commandJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = commandJSON.withCString { jsonPtr in
            editor_core_ffi_editor_state_execute_envelope_json(handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "editor_state_execute_envelope_json")
    }

    public func executeEnvelope(_ commandJSON: String) throws -> EcfJSONCommandEnvelope {
        try JSON.decode(
            EcfJSONCommandEnvelope.self,
            from: executeEnvelopeJSON(commandJSON),
            context: "editor_state_execute_envelope"
        )
    }

    @discardableResult
    private func executeCommandObject(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw EditorCoreFFIError.ffiStatus(
                code: .invalidArgument,
                context: "editor_state_encode_command_json",
                message: "failed to encode command JSON as UTF-8"
            )
        }
        return try executeJSON(json)
    }

    @discardableResult
    private func executeEditorCommand(kind: String, op: String, fields: [String: Any] = [:]) throws -> String {
        var object: [String: Any] = ["kind": kind, "op": op]
        for (key, value) in fields {
            object[key] = value
        }
        return try executeCommandObject(object)
    }

    public func fullStateJSON() throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_editor_state_full_state_json(handle), context: "editor_state_full_state_json")
    }

    public func textForSavingJSON() throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_editor_state_text_for_saving(handle), context: "editor_state_text_for_saving")
    }

    public func documentSymbolsJSON() throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_editor_state_document_symbols_json(handle), context: "editor_state_document_symbols_json")
    }

    public func diagnosticsJSON() throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_editor_state_diagnostics_json(handle), context: "editor_state_diagnostics_json")
    }

    public func decorationsJSON() throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_editor_state_decorations_json(handle), context: "editor_state_decorations_json")
    }

    public func derivedSnapshotEnvelopeJSON(_ snapshot: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = snapshot.withCString { snapshotPtr in
            editor_core_ffi_editor_state_derived_snapshot_envelope_json(handle, snapshotPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "editor_state_derived_snapshot_envelope_json")
    }

    public func derivedSnapshotEnvelope(_ snapshot: String) throws -> EcfDerivedSnapshotEnvelope {
        try JSON.decode(
            EcfDerivedSnapshotEnvelope.self,
            from: derivedSnapshotEnvelopeJSON(snapshot),
            context: "editor_state_derived_snapshot_envelope"
        )
    }

    public func setLineEnding(_ lineEnding: String) throws {
        let ok = lineEnding.withCString { ptr in
            editor_core_ffi_editor_state_set_line_ending(handle, ptr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "editor_state_set_line_ending", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func lineEndingJSON() throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_editor_state_get_line_ending(handle), context: "editor_state_get_line_ending")
    }

    public func viewportStyledJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "editor_state_viewport_styled_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "editor_state_viewport_styled_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_viewport_styled_json(handle, start, count),
            context: "editor_state_viewport_styled_json"
        )
    }

    public func viewportStyledEnvelopeJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "editor_state_viewport_styled_envelope_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "editor_state_viewport_styled_envelope_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_viewport_styled_envelope_json(handle, start, count),
            context: "editor_state_viewport_styled_envelope_json"
        )
    }

    public func viewportStyledEnvelope(startVisualRow: UInt, rowCount: UInt) throws -> EcfRenderingSnapshotEnvelope {
        try JSON.decode(
            EcfRenderingSnapshotEnvelope.self,
            from: viewportStyledEnvelopeJSON(startVisualRow: startVisualRow, rowCount: rowCount),
            context: "editor_state_viewport_styled_envelope"
        )
    }

    public func minimapJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "editor_state_minimap_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "editor_state_minimap_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_minimap_json(handle, start, count),
            context: "editor_state_minimap_json"
        )
    }

    public func minimapEnvelopeJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "editor_state_minimap_envelope_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "editor_state_minimap_envelope_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_minimap_envelope_json(handle, start, count),
            context: "editor_state_minimap_envelope_json"
        )
    }

    public func minimapEnvelope(startVisualRow: UInt, rowCount: UInt) throws -> EcfMinimapEnvelope {
        try JSON.decode(
            EcfMinimapEnvelope.self,
            from: minimapEnvelopeJSON(startVisualRow: startVisualRow, rowCount: rowCount),
            context: "editor_state_minimap_envelope"
        )
    }

    public func viewportComposedJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "editor_state_viewport_composed_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "editor_state_viewport_composed_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_viewport_composed_json(handle, start, count),
            context: "editor_state_viewport_composed_json"
        )
    }

    public func viewportComposedEnvelopeJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "editor_state_viewport_composed_envelope_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "editor_state_viewport_composed_envelope_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_viewport_composed_envelope_json(handle, start, count),
            context: "editor_state_viewport_composed_envelope_json"
        )
    }

    public func viewportComposedEnvelope(startVisualRow: UInt, rowCount: UInt) throws -> EcfRenderingSnapshotEnvelope {
        try JSON.decode(
            EcfRenderingSnapshotEnvelope.self,
            from: viewportComposedEnvelopeJSON(startVisualRow: startVisualRow, rowCount: rowCount),
            context: "editor_state_viewport_composed_envelope"
        )
    }

    public func takeLastTextDeltaJSON() throws -> String {
        try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_take_last_text_delta_json(handle),
            context: "editor_state_take_last_text_delta_json"
        )
    }

    public func lastTextDeltaJSON() throws -> String {
        try ffi.takeOwnedCString(
            editor_core_ffi_editor_state_last_text_delta_json(handle),
            context: "editor_state_last_text_delta_json"
        )
    }

    public func applyProcessingEditsJSON(_ editsJSON: String) throws {
        let ok = editsJSON.withCString { jsonPtr in
            editor_core_ffi_editor_state_apply_processing_edits_json(handle, jsonPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "editor_state_apply_processing_edits_json", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func documentStats() throws -> DocumentStats {
        var raw = EcfDocumentStats()
        let status = editor_core_ffi_editor_get_document_stats(handle, &raw)
        try ffi.ensureStatus(status, context: "editor_get_document_stats")
        return DocumentStats(raw: raw)
    }

    public func insertText(_ text: String) throws {
        if text.isEmpty {
            return
        }
        let bytes = Array(text.utf8)
        guard bytes.count <= Int(UInt32.max) else {
            throw EditorCoreFFIError.ffiStatus(code: .invalidArgument, context: "insert_text_utf8", message: "text too large")
        }
        let status = bytes.withUnsafeBufferPointer { buf in
            editor_core_ffi_editor_insert_text_utf8(handle, buf.baseAddress, UInt32(buf.count))
        }
        try ffi.ensureStatus(status, context: "insert_text_utf8")
    }

    @discardableResult
    public func typeChar(_ ch: String) throws -> String {
        try executeEditorCommand(kind: "edit", op: "type_char", fields: ["ch": ch])
    }

    @discardableResult
    public func replaceCoalescingUndo(start: UInt32, length: UInt32, text: String) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace_coalescing_undo",
            fields: ["start": Int(start), "length": Int(length), "text": text]
        )
    }

    @discardableResult
    public func replaceCoalescingUndoWithSelection(
        start: UInt32,
        length: UInt32,
        text: String,
        selectionStart: UInt32,
        selectionEnd: UInt32
    ) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace_coalescing_undo_with_selection",
            fields: [
                "start": Int(start),
                "length": Int(length),
                "text": text,
                "selection_start": Int(selectionStart),
                "selection_end": Int(selectionEnd),
            ]
        )
    }

    @discardableResult
    public func applySnippet(
        start: UInt32,
        end: UInt32,
        snippet: String,
        additionalEdits: [EcfTextEdit] = []
    ) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "apply_snippet",
            fields: [
                "start": Int(start),
                "end": Int(end),
                "snippet": snippet,
                "additional_edits": additionalEdits.map(\.jsonObject),
            ]
        )
    }

    @discardableResult
    public func snippetNextPlaceholder() throws -> String {
        try executeEditorCommand(kind: "cursor", op: "snippet_next_placeholder")
    }

    @discardableResult
    public func snippetPrevPlaceholder() throws -> String {
        try executeEditorCommand(kind: "cursor", op: "snippet_prev_placeholder")
    }

    @discardableResult
    public func moveToMatchingBracket() throws -> String {
        try executeEditorCommand(kind: "cursor", op: "move_to_matching_bracket")
    }

    @discardableResult
    public func setAutoPairsConfig(_ config: EcfAutoPairsConfig) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_auto_pairs_config",
            fields: ["config": config.jsonObject]
        )
    }

    @discardableResult
    public func setAutoPairsEnabled(_ enabled: Bool) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_auto_pairs_enabled",
            fields: ["enabled": enabled]
        )
    }

    @discardableResult
    public func updateBracketMatchHighlights() throws -> String {
        try executeEditorCommand(kind: "style", op: "update_bracket_match_highlights")
    }

    @discardableResult
    public func clearBracketMatchHighlights() throws -> String {
        try executeEditorCommand(kind: "style", op: "clear_bracket_match_highlights")
    }

    public func moveTo(line: UInt32, column: UInt32) throws {
        let status = editor_core_ffi_editor_move_to(handle, line, column)
        try ffi.ensureStatus(status, context: "move_to")
    }

    public func moveBy(deltaLine: Int32, deltaColumn: Int32) throws {
        let status = editor_core_ffi_editor_move_by(handle, deltaLine, deltaColumn)
        try ffi.ensureStatus(status, context: "move_by")
    }

    public func setSelection(
        startLine: UInt32,
        startColumn: UInt32,
        endLine: UInt32,
        endColumn: UInt32,
        direction: UInt8
    ) throws {
        let status = editor_core_ffi_editor_set_selection(handle, startLine, startColumn, endLine, endColumn, direction)
        try ffi.ensureStatus(status, context: "set_selection")
    }

    public func clearSelection() throws {
        let status = editor_core_ffi_editor_clear_selection(handle)
        try ffi.ensureStatus(status, context: "clear_selection")
    }

    public func backspace() throws {
        let status = editor_core_ffi_editor_backspace(handle)
        try ffi.ensureStatus(status, context: "backspace")
    }

    public func deleteForward() throws {
        let status = editor_core_ffi_editor_delete_forward(handle)
        try ffi.ensureStatus(status, context: "delete_forward")
    }

    public func undo() throws {
        let status = editor_core_ffi_editor_undo(handle)
        try ffi.ensureStatus(status, context: "undo")
    }

    public func redo() throws {
        let status = editor_core_ffi_editor_redo(handle)
        try ffi.ensureStatus(status, context: "redo")
    }

    public func viewportBlob(startVisualRow: UInt32, rowCount: UInt32) throws -> ViewportBlob {
        var requiredLen: UInt32 = 0
        let st1 = editor_core_ffi_editor_get_viewport_blob(handle, startVisualRow, rowCount, nil, 0, &requiredLen)
        if let code = EcfStatus(rawValue: st1), code == .ok {
            // Unexpected but not impossible; continue with requiredLen.
        } else if let code = EcfStatus(rawValue: st1), code == .bufferTooSmall {
            // Expected path.
        } else {
            try ffi.ensureStatus(st1, context: "editor_get_viewport_blob(size_probe)")
        }

        guard requiredLen > 0 else {
            throw EditorCoreFFIError.invalidViewportBlob(reason: "reported size is 0")
        }

        var data = Data(count: Int(requiredLen))
        let st2: Int32 = data.withUnsafeMutableBytes { rawBuf in
            let outPtr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return editor_core_ffi_editor_get_viewport_blob(handle, startVisualRow, rowCount, outPtr, requiredLen, &requiredLen)
        }
        try ffi.ensureStatus(st2, context: "editor_get_viewport_blob(copy)")

        if data.count != Int(requiredLen) {
            data.removeSubrange(Int(requiredLen)..<data.count)
        }
        return try ViewportBlob(data: data)
    }
}
