import CEditorCoreFFI
import Foundation

public struct OpenBufferResult: Equatable, Sendable, Decodable {
    public let bufferId: UInt64
    public let viewId: UInt64
}

public final class Workspace {
    public let ffi: EditorCoreFFILibrary
    let handle: OpaquePointer

    public init(library: EditorCoreFFILibrary) throws {
        self.ffi = library
        guard let handle = editor_core_ffi_workspace_new() else {
            let message = library.lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: "workspace_new", message: message.isEmpty ? "no last_error_message" : message)
        }
        self.handle = handle
    }

    deinit {
        editor_core_ffi_workspace_free(handle)
    }

    public func openBuffer(uri: String?, text: String, viewportWidth: UInt) throws -> OpenBufferResult {
        var raw = EcfOpenBufferResult()
        let width = try checkedFFIUInt32(max(1, viewportWidth), context: "workspace_open_buffer_typed.viewport_width")
        let status: Int32 = text.withCString { textPtr in
            if let uri {
                return uri.withCString { uriPtr in
                    editor_core_ffi_workspace_open_buffer_typed(handle, uriPtr, textPtr, width, &raw)
                }
            }
            return editor_core_ffi_workspace_open_buffer_typed(handle, nil, textPtr, width, &raw)
        }
        try ffi.ensureStatus(status, context: "workspace_open_buffer_typed")
        return OpenBufferResult(bufferId: raw.buffer_id, viewId: raw.view_id)
    }

    public func createView(bufferId: UInt64, viewportWidth: UInt) throws -> UInt64 {
        var raw = EcfCreateViewResult()
        let width = try checkedFFIUInt32(max(1, viewportWidth), context: "workspace_create_view_typed.viewport_width")
        let status = editor_core_ffi_workspace_create_view_typed(handle, bufferId, width, &raw)
        try ffi.ensureStatus(status, context: "workspace_create_view_typed")
        return raw.view_id
    }

    public func executeJSON(viewId: UInt64, commandJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = commandJSON.withCString { jsonPtr in
            editor_core_ffi_workspace_execute_json(handle, viewId, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_execute_json")
    }

    public func executeEnvelopeJSON(viewId: UInt64, commandJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = commandJSON.withCString { jsonPtr in
            editor_core_ffi_workspace_execute_envelope_json(handle, viewId, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_execute_envelope_json")
    }

    public func executeEnvelope(viewId: UInt64, commandJSON: String) throws -> EcfJSONCommandEnvelope {
        try JSON.decode(
            EcfJSONCommandEnvelope.self,
            from: executeEnvelopeJSON(viewId: viewId, commandJSON: commandJSON),
            context: "workspace_execute_envelope"
        )
    }

    @discardableResult
    private func executeCommandObject(viewId: UInt64, _ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw EditorCoreFFIError.ffiStatus(
                code: .invalidArgument,
                context: "workspace_encode_command_json",
                message: "failed to encode command JSON as UTF-8"
            )
        }
        return try executeJSON(viewId: viewId, commandJSON: json)
    }

    @discardableResult
    private func executeEditorCommand(
        viewId: UInt64,
        kind: String,
        op: String,
        fields: [String: Any] = [:]
    ) throws -> String {
        var object: [String: Any] = ["kind": kind, "op": op]
        for (key, value) in fields {
            object[key] = value
        }
        return try executeCommandObject(viewId: viewId, object)
    }

    public func closeBuffer(bufferId: UInt64) -> Bool {
        editor_core_ffi_workspace_close_buffer(handle, bufferId)
    }

    public func closeView(viewId: UInt64) -> Bool {
        editor_core_ffi_workspace_close_view(handle, viewId)
    }

    public func setActiveView(viewId: UInt64) -> Bool {
        editor_core_ffi_workspace_set_active_view(handle, viewId)
    }

    public func info() throws -> WorkspaceInfo {
        var raw = EcfWorkspaceInfo()
        let status = editor_core_ffi_workspace_get_info(handle, &raw)
        try ffi.ensureStatus(status, context: "workspace_get_info")
        return WorkspaceInfo(raw: raw)
    }

    public func infoJSON() throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_workspace_info_json(handle), context: "workspace_info_json")
    }

    public func applyProcessingEditsJSON(bufferId: UInt64, editsJSON: String) throws {
        let ok = editsJSON.withCString { editsPtr in
            editor_core_ffi_workspace_apply_processing_edits_json(handle, bufferId, editsPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "workspace_apply_processing_edits_json", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func bufferTextJSON(bufferId: UInt64) throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_workspace_buffer_text_json(handle, bufferId), context: "workspace_buffer_text_json")
    }

    public func viewportStateJSON(viewId: UInt64) throws -> String {
        try ffi.takeOwnedCString(editor_core_ffi_workspace_viewport_state_json(handle, viewId), context: "workspace_viewport_state_json")
    }

    public func viewportState(viewId: UInt64) throws -> WorkspaceViewportState {
        var raw = EcfWorkspaceViewportState()
        let status = editor_core_ffi_workspace_get_viewport_state(handle, viewId, &raw)
        try ffi.ensureStatus(status, context: "workspace_get_viewport_state")
        return WorkspaceViewportState(raw: raw)
    }

    public func setViewportHeight(viewId: UInt64, height: UInt) throws {
        let height = try checkedFFIUInt32(height, context: "workspace_set_viewport_height.height")
        let ok = editor_core_ffi_workspace_set_viewport_height(handle, viewId, height)
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "workspace_set_viewport_height", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func setSmoothScrollState(
        viewId: UInt64,
        topVisualRow: UInt,
        subRowOffset: UInt16,
        overscanRows: UInt
    ) throws {
        let top = try checkedFFIUInt32(topVisualRow, context: "workspace_set_smooth_scroll_state.top_visual_row")
        let overscan = try checkedFFIUInt32(overscanRows, context: "workspace_set_smooth_scroll_state.overscan_rows")
        let ok = editor_core_ffi_workspace_set_smooth_scroll_state(handle, viewId, top, subRowOffset, overscan)
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "workspace_set_smooth_scroll_state", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func viewportStyledJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "workspace_viewport_styled_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "workspace_viewport_styled_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_workspace_viewport_styled_json(handle, viewId, start, count),
            context: "workspace_viewport_styled_json"
        )
    }

    public func viewportStyledEnvelopeJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "workspace_viewport_styled_envelope_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "workspace_viewport_styled_envelope_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_workspace_viewport_styled_envelope_json(handle, viewId, start, count),
            context: "workspace_viewport_styled_envelope_json"
        )
    }

    public func viewportStyledEnvelope(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> EcfRenderingSnapshotEnvelope {
        try JSON.decode(
            EcfRenderingSnapshotEnvelope.self,
            from: viewportStyledEnvelopeJSON(viewId: viewId, startVisualRow: startVisualRow, rowCount: rowCount),
            context: "workspace_viewport_styled_envelope"
        )
    }

    public func minimapJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "workspace_minimap_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "workspace_minimap_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_workspace_minimap_json(handle, viewId, start, count),
            context: "workspace_minimap_json"
        )
    }

    public func minimapEnvelopeJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "workspace_minimap_envelope_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "workspace_minimap_envelope_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_workspace_minimap_envelope_json(handle, viewId, start, count),
            context: "workspace_minimap_envelope_json"
        )
    }

    public func minimapEnvelope(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> EcfMinimapEnvelope {
        try JSON.decode(
            EcfMinimapEnvelope.self,
            from: minimapEnvelopeJSON(viewId: viewId, startVisualRow: startVisualRow, rowCount: rowCount),
            context: "workspace_minimap_envelope"
        )
    }

    public func viewportComposedJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "workspace_viewport_composed_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "workspace_viewport_composed_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_workspace_viewport_composed_json(handle, viewId, start, count),
            context: "workspace_viewport_composed_json"
        )
    }

    public func viewportComposedEnvelopeJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        let start = try checkedFFIUInt32(startVisualRow, context: "workspace_viewport_composed_envelope_json.start_visual_row")
        let count = try checkedFFIUInt32(rowCount, context: "workspace_viewport_composed_envelope_json.count")
        return try ffi.takeOwnedCString(
            editor_core_ffi_workspace_viewport_composed_envelope_json(handle, viewId, start, count),
            context: "workspace_viewport_composed_envelope_json"
        )
    }

    public func viewportComposedEnvelope(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> EcfRenderingSnapshotEnvelope {
        try JSON.decode(
            EcfRenderingSnapshotEnvelope.self,
            from: viewportComposedEnvelopeJSON(viewId: viewId, startVisualRow: startVisualRow, rowCount: rowCount),
            context: "workspace_viewport_composed_envelope"
        )
    }

    public func searchAllOpenBuffersJSON(query: String, optionsJSON: String? = nil) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = query.withCString { queryPtr in
            if let optionsJSON {
                return optionsJSON.withCString { optionsPtr in
                    editor_core_ffi_workspace_search_all_open_buffers_json(handle, queryPtr, optionsPtr)
                }
            }
            return editor_core_ffi_workspace_search_all_open_buffers_json(handle, queryPtr, nil)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_search_all_open_buffers_json")
    }

    public func searchAllOpenBuffersEnvelopeJSON(query: String, optionsJSON: String? = nil) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = query.withCString { queryPtr in
            if let optionsJSON {
                return optionsJSON.withCString { optionsPtr in
                    editor_core_ffi_workspace_search_all_open_buffers_envelope_json(handle, queryPtr, optionsPtr)
                }
            }
            return editor_core_ffi_workspace_search_all_open_buffers_envelope_json(handle, queryPtr, nil)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_search_all_open_buffers_envelope_json")
    }

    public func searchAllOpenBuffersEnvelope(query: String, optionsJSON: String? = nil) throws -> EcfWorkspaceResultEnvelope {
        try JSON.decode(
            EcfWorkspaceResultEnvelope.self,
            from: searchAllOpenBuffersEnvelopeJSON(query: query, optionsJSON: optionsJSON),
            context: "workspace_search_all_open_buffers_envelope"
        )
    }

    public func applyTextEditsJSON(_ editsJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = editsJSON.withCString { editsPtr in
            editor_core_ffi_workspace_apply_text_edits_json(handle, editsPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_apply_text_edits_json")
    }

    public func applyTextEditsEnvelopeJSON(_ editsJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = editsJSON.withCString { editsPtr in
            editor_core_ffi_workspace_apply_text_edits_envelope_json(handle, editsPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_apply_text_edits_envelope_json")
    }

    public func applyTextEditsEnvelope(_ editsJSON: String) throws -> EcfWorkspaceResultEnvelope {
        try JSON.decode(
            EcfWorkspaceResultEnvelope.self,
            from: applyTextEditsEnvelopeJSON(editsJSON),
            context: "workspace_apply_text_edits_envelope"
        )
    }

    public func insertText(viewId: UInt64, _ text: String) throws {
        if text.isEmpty {
            return
        }
        let bytes = Array(text.utf8)
        guard bytes.count <= Int(UInt32.max) else {
            throw EditorCoreFFIError.ffiStatus(code: .invalidArgument, context: "workspace_insert_text_utf8", message: "text too large")
        }
        let status = bytes.withUnsafeBufferPointer { buf in
            editor_core_ffi_workspace_insert_text_utf8(handle, viewId, buf.baseAddress, UInt32(buf.count))
        }
        try ffi.ensureStatus(status, context: "workspace_insert_text_utf8")
    }

    @discardableResult
    public func typeChar(viewId: UInt64, _ ch: String) throws -> String {
        try executeEditorCommand(viewId: viewId, kind: "edit", op: "type_char", fields: ["ch": ch])
    }

    @discardableResult
    public func replaceCoalescingUndo(
        viewId: UInt64,
        start: UInt32,
        length: UInt32,
        text: String
    ) throws -> String {
        try executeEditorCommand(
            viewId: viewId,
            kind: "edit",
            op: "replace_coalescing_undo",
            fields: ["start": Int(start), "length": Int(length), "text": text]
        )
    }

    @discardableResult
    public func replaceCoalescingUndoWithSelection(
        viewId: UInt64,
        start: UInt32,
        length: UInt32,
        text: String,
        selectionStart: UInt32,
        selectionEnd: UInt32
    ) throws -> String {
        try executeEditorCommand(
            viewId: viewId,
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
        viewId: UInt64,
        start: UInt32,
        end: UInt32,
        snippet: String,
        additionalEdits: [EcfTextEdit] = []
    ) throws -> String {
        try executeEditorCommand(
            viewId: viewId,
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
    public func snippetNextPlaceholder(viewId: UInt64) throws -> String {
        try executeEditorCommand(viewId: viewId, kind: "cursor", op: "snippet_next_placeholder")
    }

    @discardableResult
    public func snippetPrevPlaceholder(viewId: UInt64) throws -> String {
        try executeEditorCommand(viewId: viewId, kind: "cursor", op: "snippet_prev_placeholder")
    }

    @discardableResult
    public func moveToMatchingBracket(viewId: UInt64) throws -> String {
        try executeEditorCommand(viewId: viewId, kind: "cursor", op: "move_to_matching_bracket")
    }

    @discardableResult
    public func setAutoPairsConfig(viewId: UInt64, _ config: EcfAutoPairsConfig) throws -> String {
        try executeEditorCommand(
            viewId: viewId,
            kind: "view",
            op: "set_auto_pairs_config",
            fields: ["config": config.jsonObject]
        )
    }

    @discardableResult
    public func setAutoPairsEnabled(viewId: UInt64, _ enabled: Bool) throws -> String {
        try executeEditorCommand(
            viewId: viewId,
            kind: "view",
            op: "set_auto_pairs_enabled",
            fields: ["enabled": enabled]
        )
    }

    @discardableResult
    public func updateBracketMatchHighlights(viewId: UInt64) throws -> String {
        try executeEditorCommand(viewId: viewId, kind: "style", op: "update_bracket_match_highlights")
    }

    @discardableResult
    public func clearBracketMatchHighlights(viewId: UInt64) throws -> String {
        try executeEditorCommand(viewId: viewId, kind: "style", op: "clear_bracket_match_highlights")
    }

    public func moveTo(viewId: UInt64, line: UInt32, column: UInt32) throws {
        let status = editor_core_ffi_workspace_move_to(handle, viewId, line, column)
        try ffi.ensureStatus(status, context: "workspace_move_to")
    }

    public func backspace(viewId: UInt64) throws {
        let status = editor_core_ffi_workspace_backspace(handle, viewId)
        try ffi.ensureStatus(status, context: "workspace_backspace")
    }

    public func viewportBlob(viewId: UInt64, startVisualRow: UInt32, rowCount: UInt32) throws -> ViewportBlob {
        var requiredLen: UInt32 = 0
        let st1 = editor_core_ffi_workspace_get_viewport_blob(handle, viewId, startVisualRow, rowCount, nil, 0, &requiredLen)
        if let code = EcfStatus(rawValue: st1), code == .ok {
            // Unexpected but not impossible; continue with requiredLen.
        } else if let code = EcfStatus(rawValue: st1), code == .bufferTooSmall {
            // Expected path.
        } else {
            try ffi.ensureStatus(st1, context: "workspace_get_viewport_blob(size_probe)")
        }

        guard requiredLen > 0 else {
            throw EditorCoreFFIError.invalidViewportBlob(reason: "reported size is 0")
        }

        var data = Data(count: Int(requiredLen))
        let st2: Int32 = data.withUnsafeMutableBytes { rawBuf in
            let outPtr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return editor_core_ffi_workspace_get_viewport_blob(handle, viewId, startVisualRow, rowCount, outPtr, requiredLen, &requiredLen)
        }
        try ffi.ensureStatus(st2, context: "workspace_get_viewport_blob(copy)")

        if data.count != Int(requiredLen) {
            data.removeSubrange(Int(requiredLen)..<data.count)
        }
        return try ViewportBlob(data: data)
    }
}
