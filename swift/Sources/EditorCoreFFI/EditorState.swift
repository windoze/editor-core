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

        let handle: OpaquePointer? = initialText.withCString { textPtr in
            library.editorStateNewFn(textPtr, max(1, viewportWidth))
        }
        guard let handle else {
            let message = library.lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: "editor_state_new", message: message.isEmpty ? "no last_error_message" : message)
        }
        self.handle = handle
    }

    deinit {
        ffi.editorStateFreeFn(handle)
    }

    public func text() throws -> String {
        let json = try ffi.takeOwnedCString(ffi.editorStateTextFn(handle), context: "editor_state_text")
        return try JSON.decode(EditorStateTextResponse.self, from: json, context: "editor_state_text").text
    }

    public func executeJSON(_ commandJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = commandJSON.withCString { jsonPtr in
            ffi.editorStateExecuteJSONFn(handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "editor_state_execute_json")
    }

    public func fullStateJSON() throws -> String {
        try ffi.takeOwnedCString(ffi.editorStateFullStateJSONFn(handle), context: "editor_state_full_state_json")
    }

    public func textForSavingJSON() throws -> String {
        try ffi.takeOwnedCString(ffi.editorStateTextForSavingFn(handle), context: "editor_state_text_for_saving")
    }

    public func documentSymbolsJSON() throws -> String {
        try ffi.takeOwnedCString(ffi.editorStateDocumentSymbolsJSONFn(handle), context: "editor_state_document_symbols_json")
    }

    public func diagnosticsJSON() throws -> String {
        try ffi.takeOwnedCString(ffi.editorStateDiagnosticsJSONFn(handle), context: "editor_state_diagnostics_json")
    }

    public func decorationsJSON() throws -> String {
        try ffi.takeOwnedCString(ffi.editorStateDecorationsJSONFn(handle), context: "editor_state_decorations_json")
    }

    public func setLineEnding(_ lineEnding: String) throws {
        let ok = lineEnding.withCString { ptr in
            ffi.editorStateSetLineEndingFn(handle, ptr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "editor_state_set_line_ending", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func lineEndingJSON() throws -> String {
        try ffi.takeOwnedCString(ffi.editorStateGetLineEndingFn(handle), context: "editor_state_get_line_ending")
    }

    public func viewportStyledJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        try ffi.takeOwnedCString(
            ffi.editorStateViewportStyledJSONFn(handle, startVisualRow, rowCount),
            context: "editor_state_viewport_styled_json"
        )
    }

    public func minimapJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        try ffi.takeOwnedCString(
            ffi.editorStateMinimapJSONFn(handle, startVisualRow, rowCount),
            context: "editor_state_minimap_json"
        )
    }

    public func viewportComposedJSON(startVisualRow: UInt, rowCount: UInt) throws -> String {
        try ffi.takeOwnedCString(
            ffi.editorStateViewportComposedJSONFn(handle, startVisualRow, rowCount),
            context: "editor_state_viewport_composed_json"
        )
    }

    public func takeLastTextDeltaJSON() throws -> String {
        try ffi.takeOwnedCString(
            ffi.editorStateTakeLastTextDeltaJSONFn(handle),
            context: "editor_state_take_last_text_delta_json"
        )
    }

    public func lastTextDeltaJSON() throws -> String {
        try ffi.takeOwnedCString(
            ffi.editorStateLastTextDeltaJSONFn(handle),
            context: "editor_state_last_text_delta_json"
        )
    }

    public func applyProcessingEditsJSON(_ editsJSON: String) throws {
        let ok = editsJSON.withCString { jsonPtr in
            ffi.editorStateApplyProcessingEditsJSONFn(handle, jsonPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "editor_state_apply_processing_edits_json", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func documentStats() throws -> DocumentStats {
        var raw = EcfDocumentStatsRaw()
        let status = withUnsafeMutableBytes(of: &raw) { rawBytes in
            ffi.editorGetDocumentStatsFn(handle, rawBytes.baseAddress)
        }
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
            ffi.editorInsertTextUTF8Fn(handle, buf.baseAddress, UInt32(buf.count))
        }
        try ffi.ensureStatus(status, context: "insert_text_utf8")
    }

    public func moveTo(line: UInt32, column: UInt32) throws {
        let status = ffi.editorMoveToFn(handle, line, column)
        try ffi.ensureStatus(status, context: "move_to")
    }

    public func moveBy(deltaLine: Int32, deltaColumn: Int32) throws {
        let status = ffi.editorMoveByFn(handle, deltaLine, deltaColumn)
        try ffi.ensureStatus(status, context: "move_by")
    }

    public func setSelection(
        startLine: UInt32,
        startColumn: UInt32,
        endLine: UInt32,
        endColumn: UInt32,
        direction: UInt8
    ) throws {
        let status = ffi.editorSetSelectionFn(handle, startLine, startColumn, endLine, endColumn, direction)
        try ffi.ensureStatus(status, context: "set_selection")
    }

    public func clearSelection() throws {
        let status = ffi.editorClearSelectionFn(handle)
        try ffi.ensureStatus(status, context: "clear_selection")
    }

    public func backspace() throws {
        let status = ffi.editorBackspaceFn(handle)
        try ffi.ensureStatus(status, context: "backspace")
    }

    public func deleteForward() throws {
        let status = ffi.editorDeleteForwardFn(handle)
        try ffi.ensureStatus(status, context: "delete_forward")
    }

    public func undo() throws {
        let status = ffi.editorUndoFn(handle)
        try ffi.ensureStatus(status, context: "undo")
    }

    public func redo() throws {
        let status = ffi.editorRedoFn(handle)
        try ffi.ensureStatus(status, context: "redo")
    }

    public func viewportBlob(startVisualRow: UInt32, rowCount: UInt32) throws -> ViewportBlob {
        var requiredLen: UInt32 = 0
        let st1 = ffi.editorGetViewportBlobFn(handle, startVisualRow, rowCount, nil, 0, &requiredLen)
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
            return ffi.editorGetViewportBlobFn(handle, startVisualRow, rowCount, outPtr, requiredLen, &requiredLen)
        }
        try ffi.ensureStatus(st2, context: "editor_get_viewport_blob(copy)")

        if data.count != Int(requiredLen) {
            data.removeSubrange(Int(requiredLen)..<data.count)
        }
        return try ViewportBlob(data: data)
    }
}
