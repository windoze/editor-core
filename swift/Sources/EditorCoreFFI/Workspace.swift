import Foundation

public struct OpenBufferResult: Equatable, Sendable, Decodable {
    public let bufferId: UInt64
    public let viewId: UInt64
}

public struct CreateViewResult: Equatable, Sendable, Decodable {
    public let viewId: UInt64
}

public final class Workspace {
    public let ffi: EditorCoreFFILibrary
    let handle: OpaquePointer

    public init(library: EditorCoreFFILibrary) throws {
        self.ffi = library
        guard let handle = library.workspaceNewFn() else {
            let message = library.lastErrorMessage()
            throw EditorCoreFFIError.ffiReturnedNull(context: "workspace_new", message: message.isEmpty ? "no last_error_message" : message)
        }
        self.handle = handle
    }

    deinit {
        ffi.workspaceFreeFn(handle)
    }

    public func openBuffer(uri: String?, text: String, viewportWidth: UInt) throws -> OpenBufferResult {
        let ptr: UnsafeMutablePointer<CChar>? = text.withCString { textPtr in
            if let uri {
                return uri.withCString { uriPtr in
                    ffi.workspaceOpenBufferFn(handle, uriPtr, textPtr, max(1, viewportWidth))
                }
            }
            return ffi.workspaceOpenBufferFn(handle, nil, textPtr, max(1, viewportWidth))
        }
        let json = try ffi.takeOwnedCString(ptr, context: "workspace_open_buffer")
        return try JSON.decode(OpenBufferResult.self, from: json, context: "open_buffer_result")
    }

    public func createView(bufferId: UInt64, viewportWidth: UInt) throws -> UInt64 {
        let ptr = ffi.workspaceCreateViewFn(handle, bufferId, max(1, viewportWidth))
        let json = try ffi.takeOwnedCString(ptr, context: "workspace_create_view")
        let decoded = try JSON.decode(CreateViewResult.self, from: json, context: "create_view_result")
        return decoded.viewId
    }

    public func executeJSON(viewId: UInt64, commandJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = commandJSON.withCString { jsonPtr in
            ffi.workspaceExecuteJSONFn(handle, viewId, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_execute_json")
    }

    public func closeBuffer(bufferId: UInt64) -> Bool {
        ffi.workspaceCloseBufferFn(handle, bufferId)
    }

    public func closeView(viewId: UInt64) -> Bool {
        ffi.workspaceCloseViewFn(handle, viewId)
    }

    public func setActiveView(viewId: UInt64) -> Bool {
        ffi.workspaceSetActiveViewFn(handle, viewId)
    }

    public func infoJSON() throws -> String {
        try ffi.takeOwnedCString(ffi.workspaceInfoJSONFn(handle), context: "workspace_info_json")
    }

    public func applyProcessingEditsJSON(bufferId: UInt64, editsJSON: String) throws {
        let ok = editsJSON.withCString { editsPtr in
            ffi.workspaceApplyProcessingEditsJSONFn(handle, bufferId, editsPtr)
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "workspace_apply_processing_edits_json", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func bufferTextJSON(bufferId: UInt64) throws -> String {
        try ffi.takeOwnedCString(ffi.workspaceBufferTextJSONFn(handle, bufferId), context: "workspace_buffer_text_json")
    }

    public func viewportStateJSON(viewId: UInt64) throws -> String {
        try ffi.takeOwnedCString(ffi.workspaceViewportStateJSONFn(handle, viewId), context: "workspace_viewport_state_json")
    }

    public func setViewportHeight(viewId: UInt64, height: UInt) throws {
        let ok = ffi.workspaceSetViewportHeightFn(handle, viewId, height)
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
        let ok = ffi.workspaceSetSmoothScrollStateFn(handle, viewId, topVisualRow, subRowOffset, overscanRows)
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "workspace_set_smooth_scroll_state", message: message.isEmpty ? "no last_error_message" : message)
        }
    }

    public func viewportStyledJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        try ffi.takeOwnedCString(
            ffi.workspaceViewportStyledJSONFn(handle, viewId, startVisualRow, rowCount),
            context: "workspace_viewport_styled_json"
        )
    }

    public func minimapJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        try ffi.takeOwnedCString(
            ffi.workspaceMinimapJSONFn(handle, viewId, startVisualRow, rowCount),
            context: "workspace_minimap_json"
        )
    }

    public func viewportComposedJSON(viewId: UInt64, startVisualRow: UInt, rowCount: UInt) throws -> String {
        try ffi.takeOwnedCString(
            ffi.workspaceViewportComposedJSONFn(handle, viewId, startVisualRow, rowCount),
            context: "workspace_viewport_composed_json"
        )
    }

    public func searchAllOpenBuffersJSON(query: String, optionsJSON: String? = nil) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = query.withCString { queryPtr in
            if let optionsJSON {
                return optionsJSON.withCString { optionsPtr in
                    ffi.workspaceSearchAllOpenBuffersJSONFn(handle, queryPtr, optionsPtr)
                }
            }
            return ffi.workspaceSearchAllOpenBuffersJSONFn(handle, queryPtr, nil)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_search_all_open_buffers_json")
    }

    public func applyTextEditsJSON(_ editsJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = editsJSON.withCString { editsPtr in
            ffi.workspaceApplyTextEditsJSONFn(handle, editsPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "workspace_apply_text_edits_json")
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
            ffi.workspaceInsertTextUTF8Fn(handle, viewId, buf.baseAddress, UInt32(buf.count))
        }
        try ffi.ensureStatus(status, context: "workspace_insert_text_utf8")
    }

    public func moveTo(viewId: UInt64, line: UInt32, column: UInt32) throws {
        let status = ffi.workspaceMoveToFn(handle, viewId, line, column)
        try ffi.ensureStatus(status, context: "workspace_move_to")
    }

    public func backspace(viewId: UInt64) throws {
        let status = ffi.workspaceBackspaceFn(handle, viewId)
        try ffi.ensureStatus(status, context: "workspace_backspace")
    }

    public func viewportBlob(viewId: UInt64, startVisualRow: UInt32, rowCount: UInt32) throws -> ViewportBlob {
        var requiredLen: UInt32 = 0
        let st1 = ffi.workspaceGetViewportBlobFn(handle, viewId, startVisualRow, rowCount, nil, 0, &requiredLen)
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
            return ffi.workspaceGetViewportBlobFn(handle, viewId, startVisualRow, rowCount, outPtr, requiredLen, &requiredLen)
        }
        try ffi.ensureStatus(st2, context: "workspace_get_viewport_blob(copy)")

        if data.count != Int(requiredLen) {
            data.removeSubrange(Int(requiredLen)..<data.count)
        }
        return try ViewportBlob(data: data)
    }
}
