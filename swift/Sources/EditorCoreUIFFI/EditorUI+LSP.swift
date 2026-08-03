import CEditorCoreUIFFI
import Foundation
import Metal

extension EditorUI {
    public func lspEnable(command: String, args: String? = nil, rootURI: String, documentURI: String, languageId: String) throws {
        let status: Int32 = command.withCString { cmdCStr in
            rootURI.withCString { rootCStr in
                documentURI.withCString { docCStr in
                    languageId.withCString { langCStr in
                        if let args {
                            return args.withCString { argsCStr in
                                editor_core_ui_ffi_editor_ui_lsp_enable(handle, cmdCStr, argsCStr, rootCStr, docCStr, langCStr)
                            }
                        }
                        return editor_core_ui_ffi_editor_ui_lsp_enable(handle, cmdCStr, nil, rootCStr, docCStr, langCStr)
                    }
                }
            }
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_enable")
    }

    public func lspDisable() {
        editor_core_ui_ffi_editor_ui_lsp_disable(handle)
    }

    @discardableResult
    public func lspShutdown() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_shutdown(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_shutdown")
        return out != 0
    }

    public func lspDidChangeWorkspaceFolders(
        added: [EcuLspWorkspaceFolder],
        removed: [EcuLspWorkspaceFolder]
    ) throws {
        let encoder = JSONEncoder()
        let addedData = try encoder.encode(added)
        let removedData = try encoder.encode(removed)
        guard let addedJSON = String(data: addedData, encoding: .utf8),
              let removedJSON = String(data: removedData, encoding: .utf8)
        else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_did_change_workspace_folders_encode",
                message: "failed to encode workspace folders JSON"
            )
        }

        let status = addedJSON.withCString { addedPtr in
            removedJSON.withCString { removedPtr in
                editor_core_ui_ffi_editor_ui_lsp_did_change_workspace_folders_json(
                    handle,
                    addedPtr,
                    removedPtr
                )
            }
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_did_change_workspace_folders_json")
    }

    public func lspDidOpenDocument(uri: String, languageId: String, version: Int32 = 1, text: String) throws {
        let status = uri.withCString { uriPtr in
            languageId.withCString { languagePtr in
                text.withCString { textPtr in
                    editor_core_ui_ffi_editor_ui_lsp_did_open_document(
                        handle,
                        uriPtr,
                        languagePtr,
                        version,
                        textPtr
                    )
                }
            }
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_did_open_document")
    }

    public func lspDidChangeDocument(uri: String, text: String) throws {
        let status = uri.withCString { uriPtr in
            text.withCString { textPtr in
                editor_core_ui_ffi_editor_ui_lsp_did_change_document(handle, uriPtr, textPtr)
            }
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_did_change_document")
    }

    public func lspDidSaveDocument(uri: String, text: String? = nil) throws {
        let status = uri.withCString { uriPtr in
            if let text {
                return text.withCString { textPtr in
                    editor_core_ui_ffi_editor_ui_lsp_did_save_document(handle, uriPtr, textPtr)
                }
            }
            return editor_core_ui_ffi_editor_ui_lsp_did_save_document(handle, uriPtr, nil)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_did_save_document")
    }

    public func lspDidCloseDocument(uri: String) throws {
        let status = uri.withCString { uriPtr in
            editor_core_ui_ffi_editor_ui_lsp_did_close_document(handle, uriPtr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_did_close_document")
    }

    public func lspIsEnabled() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_is_enabled(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_is_enabled")
        return out != 0
    }

    /// Get a best-effort LSP status snapshot as JSON.
    ///
    /// This is intended for status bars and debugging overlays.
    public func lspStatusJSON() throws -> String {
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_lsp_status_json(handle, &ptr)
        try library.ensureStatus(status, context: "editor_ui_lsp_status_json")
        guard let ptr else {
            return "{}"
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspStatusSnapshot() throws -> EcuLspStatusSnapshot {
        try Self.decodeSnapshot(
            EcuLspStatusSnapshot.self,
            from: lspStatusJSON(),
            context: "editor_ui_lsp_status_snapshot"
        )
    }

    public func lspResultEventsLatestSequence() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_result_events_latest_sequence(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_result_events_latest_sequence")
        return out
    }

    public func lspResultEventsJSON(after sequence: UInt64 = 0) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_lsp_result_events_json(handle, sequence) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_result_events_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspResultEvents(after sequence: UInt64 = 0) throws -> EcuLspResultEventsSnapshot {
        try Self.decodeSnapshot(
            EcuLspResultEventsSnapshot.self,
            from: lspResultEventsJSON(after: sequence),
            context: "editor_ui_lsp_result_events"
        )
    }

    public func lspRequestEventsLatestSequence() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_events_latest_sequence(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_events_latest_sequence")
        return out
    }

    public func lspRequestEventsJSON(after sequence: UInt64 = 0) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_lsp_request_events_json(handle, sequence) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_request_events_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspRequestEvents(after sequence: UInt64 = 0) throws -> EcuLspRequestEventsSnapshot {
        try Self.decodeSnapshot(
            EcuLspRequestEventsSnapshot.self,
            from: lspRequestEventsJSON(after: sequence),
            context: "editor_ui_lsp_request_events"
        )
    }

    public func stateEventsLatestSequence() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_state_events_latest_sequence(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_state_events_latest_sequence")
        return out
    }

    public func stateEventsJSON(after sequence: UInt64 = 0) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_state_events_json(handle, sequence) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_state_events_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func stateEvents(after sequence: UInt64 = 0) throws -> EcuEditorUIStateEventsSnapshot {
        try Self.decodeSnapshot(
            EcuEditorUIStateEventsSnapshot.self,
            from: stateEventsJSON(after: sequence),
            context: "editor_ui_state_events"
        )
    }

    public func eventStreamEnvelopeJSON(streamRawValue: String, after sequence: UInt64 = 0) throws -> String {
        guard let ptr = streamRawValue.withCString({ streamPtr in
            editor_core_ui_ffi_editor_ui_event_stream_envelope_json(handle, streamPtr, sequence)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_event_stream_envelope_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func eventStreamEnvelopeJSON(stream: EcuEventStreamName, after sequence: UInt64 = 0) throws -> String {
        try eventStreamEnvelopeJSON(streamRawValue: stream.rawValue, after: sequence)
    }

    public func eventStreamEnvelope(
        streamRawValue: String,
        after sequence: UInt64 = 0
    ) throws -> EcuJSONEventStreamEnvelope {
        try Self.decodeSnapshot(
            EcuJSONEventStreamEnvelope.self,
            from: eventStreamEnvelopeJSON(streamRawValue: streamRawValue, after: sequence),
            context: "editor_ui_event_stream_envelope_decode"
        )
    }

    public func eventStreamEnvelope(
        stream: EcuEventStreamName,
        after sequence: UInt64 = 0
    ) throws -> EcuJSONEventStreamEnvelope {
        try eventStreamEnvelope(streamRawValue: stream.rawValue, after: sequence)
    }

    public func lspCancelRequest(_ requestId: UInt64) throws -> Bool {
        var recorded: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_cancel_request(handle, requestId, &recorded)
        try library.ensureStatus(status, context: "editor_ui_lsp_cancel_request")
        return recorded != 0
    }

    public func lspMarkRequestTimedOut(_ requestId: UInt64) throws -> Bool {
        var recorded: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_mark_request_timed_out(handle, requestId, &recorded)
        try library.ensureStatus(status, context: "editor_ui_lsp_mark_request_timed_out")
        return recorded != 0
    }

    /// Request an LSP hover (`textDocument/hover`) for a logical position.
    ///
    /// Notes:
    /// - `logicalLine` / `logicalColumn` are 0-based and counted in Unicode scalars.
    /// - This request is non-blocking; the result is delivered via internal LSP polling.
    public func lspRequestHover(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_hover(handle, logicalLine, logicalColumn, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_hover")
        return out
    }

    /// Take the last LSP hover `result` payload as JSON (`Hover | null`).
    ///
    /// Returns `nil` when there is no new hover result.
    public func lspTakeLastHoverResultJSON() throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json(handle, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_lsp_take_last_hover_json")
        guard has != 0, let ptr else { return nil }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspTakeLastHoverResult() throws -> EcuLspHoverResult? {
        guard let json = try lspTakeLastHoverResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspHoverResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_hover_decode"
        )
    }

    /// Request LSP go-to-definition (`textDocument/definition`) for a logical position.
    ///
    /// Notes:
    /// - `logicalLine` / `logicalColumn` are 0-based and counted in Unicode scalars.
    /// - This request is non-blocking; the result is delivered via internal LSP polling.
    public func lspRequestDefinition(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_definition(handle, logicalLine, logicalColumn, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_definition")
        return out
    }

    /// Take the last LSP definition `result` payload as JSON (`Definition | null`).
    ///
    /// Returns `nil` when there is no new definition result.
    public func lspTakeLastDefinitionResultJSON() throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json(handle, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_lsp_take_last_definition_json")
        guard has != 0, let ptr else { return nil }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspTakeLastDefinitionResult() throws -> EcuLspLocationResult? {
        guard let json = try lspTakeLastDefinitionResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspLocationResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_definition_decode"
        )
    }

    func lspRequestPosition(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        context: String,
        _ request: (UInt32, UInt32, UnsafeMutablePointer<UInt64>) -> Int32
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = request(logicalLine, logicalColumn, &out)
        try library.ensureStatus(status, context: context)
        return out
    }

    func lspTakeLastResultJSON(
        context: String,
        _ take: (UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
    ) throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = take(&has, &ptr)
        try library.ensureStatus(status, context: context)
        guard has != 0, let ptr else { return nil }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspTakeLastResultEnvelopeJSON(slotRawValue: String) throws -> String {
        guard let ptr = slotRawValue.withCString({ slotPtr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_result_envelope_json(handle, slotPtr)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_take_last_result_envelope_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspTakeLastResultEnvelopeJSON(slot: EcuLspResultSlot) throws -> String {
        try lspTakeLastResultEnvelopeJSON(slotRawValue: slot.rawValue)
    }

    public func lspTakeLastResultEnvelope(slotRawValue: String) throws -> EcuLspResultEnvelope {
        try Self.decodeSnapshot(
            EcuLspResultEnvelope.self,
            from: lspTakeLastResultEnvelopeJSON(slotRawValue: slotRawValue),
            context: "editor_ui_lsp_take_last_result_envelope_decode"
        )
    }

    public func lspTakeLastResultEnvelope(slot: EcuLspResultSlot) throws -> EcuLspResultEnvelope {
        try lspTakeLastResultEnvelope(slotRawValue: slot.rawValue)
    }

    func lspRequestJSON(
        _ json: String,
        context: String,
        _ request: (UnsafePointer<CChar>, UnsafeMutablePointer<UInt64>) -> Int32
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = json.withCString { cstr in
            request(cstr, &out)
        }
        try library.ensureStatus(status, context: context)
        return out
    }

    public func lspRequestDeclaration(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_declaration"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_declaration(handle, line, column, out)
        }
    }

    public func lspTakeLastDeclarationResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_declaration_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_declaration_json(handle, has, ptr)
        }
    }

    public func lspTakeLastDeclarationResult() throws -> EcuLspLocationResult? {
        guard let json = try lspTakeLastDeclarationResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspLocationResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_declaration_decode"
        )
    }

    public func lspRequestTypeDefinition(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_type_definition"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_type_definition(handle, line, column, out)
        }
    }

    public func lspTakeLastTypeDefinitionResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_type_definition_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_type_definition_json(handle, has, ptr)
        }
    }

    public func lspTakeLastTypeDefinitionResult() throws -> EcuLspLocationResult? {
        guard let json = try lspTakeLastTypeDefinitionResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspLocationResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_type_definition_decode"
        )
    }

    public func lspRequestImplementation(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_implementation"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_implementation(handle, line, column, out)
        }
    }

    public func lspTakeLastImplementationResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_implementation_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_implementation_json(handle, has, ptr)
        }
    }

    public func lspTakeLastImplementationResult() throws -> EcuLspLocationResult? {
        guard let json = try lspTakeLastImplementationResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspLocationResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_implementation_decode"
        )
    }

    public func lspRequestReferences(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        includeDeclaration: Bool = true
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_references(
            handle,
            logicalLine,
            logicalColumn,
            includeDeclaration ? 1 : 0,
            &out
        )
        try library.ensureStatus(status, context: "editor_ui_lsp_request_references")
        return out
    }

    public func lspTakeLastReferencesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_references_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_references_json(handle, has, ptr)
        }
    }

    public func lspTakeLastReferencesResult() throws -> EcuLspLocationResult? {
        guard let json = try lspTakeLastReferencesResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspLocationResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_references_decode"
        )
    }

    public func lspRequestCompletion(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_completion"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_completion(handle, line, column, out)
        }
    }

    public func lspTakeLastCompletionResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_completion_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_completion_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCompletionResult() throws -> EcuLspCompletionResult? {
        guard let json = try lspTakeLastCompletionResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCompletionResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_completion_decode"
        )
    }

    public func lspRequestCompletionItemResolve(itemJSON: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = itemJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_completion_item_resolve(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_completion_item_resolve")
        return out
    }

    public func lspTakeLastCompletionItemResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_completion_item_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_completion_item_resolve_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCompletionItemResolveResult() throws -> EcuLspCompletionItem? {
        guard let json = try lspTakeLastCompletionItemResolveResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCompletionItem.self,
            from: json,
            context: "editor_ui_lsp_take_last_completion_item_resolve_decode"
        )
    }

    public func lspRequestSignatureHelp(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_signature_help"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_signature_help(handle, line, column, out)
        }
    }

    public func lspTakeLastSignatureHelpResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_signature_help_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_signature_help_json(handle, has, ptr)
        }
    }

    public func lspTakeLastSignatureHelpResult() throws -> EcuLspSignatureHelpResult? {
        guard let json = try lspTakeLastSignatureHelpResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspSignatureHelpResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_signature_help_decode"
        )
    }

    public func lspRequestPrepareRename(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_prepare_rename"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_prepare_rename(handle, line, column, out)
        }
    }

    public func lspTakeLastPrepareRenameResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_prepare_rename_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_rename_json(handle, has, ptr)
        }
    }

    public func lspTakeLastPrepareRenameResult() throws -> EcuLspPrepareRenameResult? {
        guard let json = try lspTakeLastPrepareRenameResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspPrepareRenameResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_prepare_rename_decode"
        )
    }

    public func lspRequestRename(logicalLine: UInt32, logicalColumn: UInt32, newName: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = newName.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_rename(handle, logicalLine, logicalColumn, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_rename")
        return out
    }

    public func lspTakeLastRenameResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_rename_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_rename_json(handle, has, ptr)
        }
    }

    public func lspTakeLastRenameResult() throws -> EcuLspWorkspaceEdit? {
        guard let json = try lspTakeLastRenameResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspWorkspaceEdit.self,
            from: json,
            context: "editor_ui_lsp_take_last_rename_decode"
        )
    }

    public func lspRequestCodeAction(
        startOffset: UInt32,
        endOffset: UInt32,
        contextJSON: String = #"{"diagnostics":[]}"#
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = contextJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_code_action(handle, startOffset, endOffset, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_code_action")
        return out
    }

    public func lspTakeLastCodeActionResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_action_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCodeActionResult() throws -> EcuLspCodeActionResult? {
        guard let json = try lspTakeLastCodeActionResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCodeActionResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_code_action_decode"
        )
    }

    public func lspRequestCodeActionResolve(actionJSON: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = actionJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_code_action_resolve(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_code_action_resolve")
        return out
    }

    public func lspTakeLastCodeActionResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_action_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_resolve_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCodeActionResolveResult() throws -> EcuLspCodeAction? {
        guard let json = try lspTakeLastCodeActionResolveResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCodeAction.self,
            from: json,
            context: "editor_ui_lsp_take_last_code_action_resolve_decode"
        )
    }

    public func lspRequestExecuteCommand(commandJSON: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = commandJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_execute_command(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_execute_command")
        return out
    }

    public func lspTakeLastExecuteCommandResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_execute_command_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_execute_command_json(handle, has, ptr)
        }
    }

    public func lspRequestCodeLens() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_code_lens(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_code_lens")
        return out
    }

    public func lspTakeLastCodeLensResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_lens_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCodeLensResult() throws -> EcuLspCodeLensResult? {
        guard let json = try lspTakeLastCodeLensResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCodeLensResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_code_lens_decode"
        )
    }

    public func lspRequestCodeLensResolve(lensJSON: String) throws -> UInt64 {
        try lspRequestJSON(lensJSON, context: "editor_ui_lsp_request_code_lens_resolve") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_code_lens_resolve(handle, cstr, out)
        }
    }

    public func lspTakeLastCodeLensResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_code_lens_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_resolve_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCodeLensResolveResult() throws -> EcuLspCodeLens? {
        guard let json = try lspTakeLastCodeLensResolveResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCodeLens.self,
            from: json,
            context: "editor_ui_lsp_take_last_code_lens_resolve_decode"
        )
    }

    public func lspRequestInlayHints(startOffset: UInt32, endOffset: UInt32) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_inlay_hints(
            handle,
            startOffset,
            endOffset,
            &out
        )
        try library.ensureStatus(status, context: "editor_ui_lsp_request_inlay_hints")
        return out
    }

    public func lspTakeLastInlayHintsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_inlay_hints_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hints_json(handle, has, ptr)
        }
    }

    public func lspTakeLastInlayHintsResult() throws -> EcuLspInlayHintResult? {
        guard let json = try lspTakeLastInlayHintsResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspInlayHintResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_inlay_hints_decode"
        )
    }

    public func lspRequestInlayHintResolve(hintJSON: String) throws -> UInt64 {
        try lspRequestJSON(hintJSON, context: "editor_ui_lsp_request_inlay_hint_resolve") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_inlay_hint_resolve(handle, cstr, out)
        }
    }

    public func lspTakeLastInlayHintResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_inlay_hint_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hint_resolve_json(handle, has, ptr)
        }
    }

    public func lspTakeLastInlayHintResolveResult() throws -> EcuLspInlayHint? {
        guard let json = try lspTakeLastInlayHintResolveResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspInlayHint.self,
            from: json,
            context: "editor_ui_lsp_take_last_inlay_hint_resolve_decode"
        )
    }

    public func lspRequestDocumentLinks() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_document_links(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_document_links")
        return out
    }

    public func lspTakeLastDocumentLinksResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_links_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_links_json(handle, has, ptr)
        }
    }

    public func lspTakeLastDocumentLinksResult() throws -> EcuLspDocumentLinkResult? {
        guard let json = try lspTakeLastDocumentLinksResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspDocumentLinkResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_document_links_decode"
        )
    }

    public func lspRequestDocumentLinkResolve(linkJSON: String) throws -> UInt64 {
        try lspRequestJSON(linkJSON, context: "editor_ui_lsp_request_document_link_resolve") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_document_link_resolve(handle, cstr, out)
        }
    }

    public func lspTakeLastDocumentLinkResolveResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_link_resolve_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_link_resolve_json(handle, has, ptr)
        }
    }

    public func lspTakeLastDocumentLinkResolveResult() throws -> EcuLspDocumentLink? {
        guard let json = try lspTakeLastDocumentLinkResolveResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspDocumentLink.self,
            from: json,
            context: "editor_ui_lsp_take_last_document_link_resolve_decode"
        )
    }

    public func lspRequestDocumentSymbols() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_document_symbols(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_document_symbols")
        return out
    }

    public func lspTakeLastDocumentSymbolsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_symbols_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_symbols_json(handle, has, ptr)
        }
    }

    public func lspTakeLastDocumentSymbolsResult() throws -> EcuLspDocumentSymbolResult? {
        guard let json = try lspTakeLastDocumentSymbolsResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspDocumentSymbolResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_document_symbols_decode"
        )
    }

    public func lspRequestFoldingRanges() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_folding_ranges")
        return out
    }

    public func lspTakeLastFoldingRangesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_folding_ranges_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_folding_ranges_json(handle, has, ptr)
        }
    }

    public func lspTakeLastFoldingRangesResult() throws -> EcuLspFoldingRangeResult? {
        guard let json = try lspTakeLastFoldingRangesResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspFoldingRangeResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_folding_ranges_decode"
        )
    }

    public func lspRequestSemanticTokensFull() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_semantic_tokens_full(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_semantic_tokens_full")
        return out
    }

    public func lspTakeLastSemanticTokensFullResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_semantic_tokens_full_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_semantic_tokens_full_json(handle, has, ptr)
        }
    }

    public func lspTakeLastSemanticTokensFullResult() throws -> EcuLspSemanticTokensResult? {
        guard let json = try lspTakeLastSemanticTokensFullResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspSemanticTokensResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_semantic_tokens_full_decode"
        )
    }

    public func lspRequestSemanticTokensDelta(previousResultId: String? = nil) throws -> UInt64 {
        var out: UInt64 = 0
        let status: Int32
        if let previousResultId {
            status = previousResultId.withCString { previousPtr in
                editor_core_ui_ffi_editor_ui_lsp_request_semantic_tokens_delta(handle, previousPtr, &out)
            }
        } else {
            status = editor_core_ui_ffi_editor_ui_lsp_request_semantic_tokens_delta(handle, nil, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_semantic_tokens_delta")
        return out
    }

    public func lspTakeLastSemanticTokensDeltaResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_semantic_tokens_delta_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_semantic_tokens_delta_json(handle, has, ptr)
        }
    }

    public func lspTakeLastSemanticTokensDeltaResult() throws -> EcuLspSemanticTokensResult? {
        guard let json = try lspTakeLastSemanticTokensDeltaResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspSemanticTokensResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_semantic_tokens_delta_decode"
        )
    }

    public func lspRequestSemanticTokensRange(
        startLine: UInt32,
        startColumn: UInt32,
        endLine: UInt32,
        endColumn: UInt32
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_semantic_tokens_range(
            handle,
            startLine,
            startColumn,
            endLine,
            endColumn,
            &out
        )
        try library.ensureStatus(status, context: "editor_ui_lsp_request_semantic_tokens_range")
        return out
    }

    public func lspTakeLastSemanticTokensRangeResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_semantic_tokens_range_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_semantic_tokens_range_json(handle, has, ptr)
        }
    }

    public func lspTakeLastSemanticTokensRangeResult() throws -> EcuLspSemanticTokensResult? {
        guard let json = try lspTakeLastSemanticTokensRangeResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspSemanticTokensResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_semantic_tokens_range_decode"
        )
    }

    public func lspRequestSelectionRange(positionsJSON: String) throws -> UInt64 {
        try lspRequestJSON(positionsJSON, context: "editor_ui_lsp_request_selection_range") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_selection_range(handle, cstr, out)
        }
    }

    public func lspTakeLastSelectionRangeResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_selection_range_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_selection_range_json(handle, has, ptr)
        }
    }

    public func lspTakeLastSelectionRangeResult() throws -> EcuLspSelectionRangeResult? {
        guard let json = try lspTakeLastSelectionRangeResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspSelectionRangeResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_selection_range_decode"
        )
    }

    public func lspRequestLinkedEditingRange(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_linked_editing_range"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_linked_editing_range(handle, line, column, out)
        }
    }

    public func lspTakeLastLinkedEditingRangeResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_linked_editing_range_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_linked_editing_range_json(handle, has, ptr)
        }
    }

    public func lspTakeLastLinkedEditingRangeResult() throws -> EcuLspLinkedEditingRangeResult? {
        guard let json = try lspTakeLastLinkedEditingRangeResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspLinkedEditingRangeResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_linked_editing_range_decode"
        )
    }

    public func lspRequestDocumentDiagnostic(previousResultId: String? = nil) throws -> UInt64 {
        var out: UInt64 = 0
        let status: Int32
        if let previousResultId {
            status = previousResultId.withCString { cstr in
                editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(handle, cstr, &out)
            }
        } else {
            status = editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(handle, nil, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_document_diagnostic")
        return out
    }

    public func lspTakeLastDocumentDiagnosticResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_diagnostic_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_diagnostic_json(handle, has, ptr)
        }
    }

    public func lspTakeLastDocumentDiagnosticResult() throws -> EcuLspDocumentDiagnosticResult? {
        guard let json = try lspTakeLastDocumentDiagnosticResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspDocumentDiagnosticResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_document_diagnostic_decode"
        )
    }

    public func lspRequestWorkspaceDiagnostic(previousResultIdsJSON: String = "[]") throws -> UInt64 {
        try lspRequestJSON(previousResultIdsJSON, context: "editor_ui_lsp_request_workspace_diagnostic") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_workspace_diagnostic(handle, cstr, out)
        }
    }

    public func lspTakeLastWorkspaceDiagnosticResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_workspace_diagnostic_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_diagnostic_json(handle, has, ptr)
        }
    }

    public func lspTakeLastWorkspaceDiagnosticResult() throws -> EcuLspWorkspaceDiagnosticResult? {
        guard let json = try lspTakeLastWorkspaceDiagnosticResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspWorkspaceDiagnosticResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_workspace_diagnostic_decode"
        )
    }

    public func lspRequestDocumentColor() throws -> UInt64 {
        var out: UInt64 = 0
        let status = editor_core_ui_ffi_editor_ui_lsp_request_document_color(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_lsp_request_document_color")
        return out
    }

    public func lspTakeLastDocumentColorResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_document_color_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_document_color_json(handle, has, ptr)
        }
    }

    public func lspTakeLastDocumentColorResult() throws -> EcuLspDocumentColorResult? {
        guard let json = try lspTakeLastDocumentColorResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspDocumentColorResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_document_color_decode"
        )
    }

    public func lspRequestColorPresentation(
        startOffset: UInt32,
        endOffset: UInt32,
        colorJSON: String
    ) throws -> UInt64 {
        var out: UInt64 = 0
        let status = colorJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_color_presentation(
                handle,
                startOffset,
                endOffset,
                cstr,
                &out
            )
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_color_presentation")
        return out
    }

    public func lspTakeLastColorPresentationResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_color_presentation_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_color_presentation_json(handle, has, ptr)
        }
    }

    public func lspTakeLastColorPresentationResult() throws -> EcuLspColorPresentationResult? {
        guard let json = try lspTakeLastColorPresentationResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspColorPresentationResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_color_presentation_decode"
        )
    }

    public func lspRequestPrepareCallHierarchy(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_prepare_call_hierarchy"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_prepare_call_hierarchy(handle, line, column, out)
        }
    }

    public func lspTakeLastPrepareCallHierarchyResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_prepare_call_hierarchy_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_call_hierarchy_json(handle, has, ptr)
        }
    }

    public func lspTakeLastPrepareCallHierarchyResult() throws -> EcuLspCallHierarchyPrepareResult? {
        guard let json = try lspTakeLastPrepareCallHierarchyResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCallHierarchyPrepareResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_prepare_call_hierarchy_decode"
        )
    }

    public func lspRequestCallHierarchyIncomingCalls(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_call_hierarchy_incoming_calls") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_incoming_calls(handle, cstr, out)
        }
    }

    public func lspTakeLastCallHierarchyIncomingCallsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_call_hierarchy_incoming_calls_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_incoming_calls_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCallHierarchyIncomingCallsResult() throws -> EcuLspCallHierarchyIncomingCallsResult? {
        guard let json = try lspTakeLastCallHierarchyIncomingCallsResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCallHierarchyIncomingCallsResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_call_hierarchy_incoming_calls_decode"
        )
    }

    public func lspRequestCallHierarchyOutgoingCalls(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_call_hierarchy_outgoing_calls") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_outgoing_calls(handle, cstr, out)
        }
    }

    public func lspTakeLastCallHierarchyOutgoingCallsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_call_hierarchy_outgoing_calls_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_outgoing_calls_json(handle, has, ptr)
        }
    }

    public func lspTakeLastCallHierarchyOutgoingCallsResult() throws -> EcuLspCallHierarchyOutgoingCallsResult? {
        guard let json = try lspTakeLastCallHierarchyOutgoingCallsResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspCallHierarchyOutgoingCallsResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_call_hierarchy_outgoing_calls_decode"
        )
    }

    public func lspRequestPrepareTypeHierarchy(logicalLine: UInt32, logicalColumn: UInt32) throws -> UInt64 {
        try lspRequestPosition(
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            context: "editor_ui_lsp_request_prepare_type_hierarchy"
        ) { line, column, out in
            editor_core_ui_ffi_editor_ui_lsp_request_prepare_type_hierarchy(handle, line, column, out)
        }
    }

    public func lspTakeLastPrepareTypeHierarchyResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_prepare_type_hierarchy_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_type_hierarchy_json(handle, has, ptr)
        }
    }

    public func lspTakeLastPrepareTypeHierarchyResult() throws -> EcuLspTypeHierarchyPrepareResult? {
        guard let json = try lspTakeLastPrepareTypeHierarchyResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspTypeHierarchyPrepareResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_prepare_type_hierarchy_decode"
        )
    }

    public func lspRequestTypeHierarchySupertypes(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_type_hierarchy_supertypes") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_supertypes(handle, cstr, out)
        }
    }

    public func lspTakeLastTypeHierarchySupertypesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_type_hierarchy_supertypes_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_supertypes_json(handle, has, ptr)
        }
    }

    public func lspTakeLastTypeHierarchySupertypesResult() throws -> EcuLspTypeHierarchyItemsResult? {
        guard let json = try lspTakeLastTypeHierarchySupertypesResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspTypeHierarchyItemsResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_type_hierarchy_supertypes_decode"
        )
    }

    public func lspRequestTypeHierarchySubtypes(itemJSON: String) throws -> UInt64 {
        try lspRequestJSON(itemJSON, context: "editor_ui_lsp_request_type_hierarchy_subtypes") { cstr, out in
            editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_subtypes(handle, cstr, out)
        }
    }

    public func lspTakeLastTypeHierarchySubtypesResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_type_hierarchy_subtypes_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_subtypes_json(handle, has, ptr)
        }
    }

    public func lspTakeLastTypeHierarchySubtypesResult() throws -> EcuLspTypeHierarchyItemsResult? {
        guard let json = try lspTakeLastTypeHierarchySubtypesResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspTypeHierarchyItemsResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_type_hierarchy_subtypes_decode"
        )
    }

    public func lspRequestWorkspaceSymbols(query: String) throws -> UInt64 {
        var out: UInt64 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_request_workspace_symbols(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_request_workspace_symbols")
        return out
    }

    public func lspTakeLastWorkspaceSymbolsResultJSON() throws -> String? {
        try lspTakeLastResultJSON(context: "editor_ui_lsp_take_last_workspace_symbols_json") { has, ptr in
            editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_symbols_json(handle, has, ptr)
        }
    }

    public func lspTakeLastWorkspaceSymbolsResult() throws -> EcuLspWorkspaceSymbolResult? {
        guard let json = try lspTakeLastWorkspaceSymbolsResultJSON() else { return nil }
        return try Self.decodeSnapshot(
            EcuLspWorkspaceSymbolResult.self,
            from: json,
            context: "editor_ui_lsp_take_last_workspace_symbols_decode"
        )
    }

    /// Format the current document via LSP (`textDocument/formatting`) and apply edits locally.
    ///
    /// Notes:
    /// - This is a blocking request intended for explicit user actions (e.g. "Format Document").
    /// - `formattingOptionsJSON` should match LSP `FormattingOptions`.
    @discardableResult
    public func lspFormatDocument(formattingOptionsJSON: String? = nil, timeoutMs: UInt32 = 2000) throws -> Bool {
        var applied: UInt8 = 0
        let status: Int32
        if let formattingOptionsJSON {
            status = formattingOptionsJSON.withCString { cstr in
                editor_core_ui_ffi_editor_ui_lsp_format_document(handle, cstr, timeoutMs, &applied)
            }
        } else {
            status = editor_core_ui_ffi_editor_ui_lsp_format_document(handle, nil, timeoutMs, &applied)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_format_document")
        return applied != 0
    }

    /// Format a range via LSP (`textDocument/rangeFormatting`) and apply edits locally.
    ///
    /// Offsets use editor-core char offsets. `formattingOptionsJSON` should match LSP `FormattingOptions`.
    @discardableResult
    public func lspFormatRange(
        startOffset: UInt32,
        endOffset: UInt32,
        formattingOptionsJSON: String? = nil,
        timeoutMs: UInt32 = 2000
    ) throws -> Bool {
        var applied: UInt8 = 0
        let status: Int32
        if let formattingOptionsJSON {
            status = formattingOptionsJSON.withCString { cstr in
                editor_core_ui_ffi_editor_ui_lsp_format_range(
                    handle,
                    startOffset,
                    endOffset,
                    cstr,
                    timeoutMs,
                    &applied
                )
            }
        } else {
            status = editor_core_ui_ffi_editor_ui_lsp_format_range(
                handle,
                startOffset,
                endOffset,
                nil,
                timeoutMs,
                &applied
            )
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_format_range")
        return applied != 0
    }

    /// Request on-type formatting via LSP (`textDocument/onTypeFormatting`) and apply edits locally.
    ///
    /// `logicalLine` and `logicalColumn` are the logical editor position after `trigger` was inserted.
    @discardableResult
    public func lspFormatOnType(
        logicalLine: UInt32,
        logicalColumn: UInt32,
        trigger: String,
        formattingOptionsJSON: String? = nil,
        timeoutMs: UInt32 = 2000
    ) throws -> Bool {
        var applied: UInt8 = 0
        let status = trigger.withCString { triggerCStr in
            if let formattingOptionsJSON {
                formattingOptionsJSON.withCString { optionsCStr in
                    editor_core_ui_ffi_editor_ui_lsp_format_on_type(
                        handle,
                        logicalLine,
                        logicalColumn,
                        triggerCStr,
                        optionsCStr,
                        timeoutMs,
                        &applied
                    )
                }
            } else {
                editor_core_ui_ffi_editor_ui_lsp_format_on_type(
                    handle,
                    logicalLine,
                    logicalColumn,
                    triggerCStr,
                    nil,
                    timeoutMs,
                    &applied
                )
            }
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_format_on_type")
        return applied != 0
    }

    /// Poll and apply any completed async processing (Tree-sitter highlighting/folding).
    ///
    /// This call is non-blocking: it never waits for background work.
    ///
    /// - Returns:
    ///   - `applied`: whether new processing edits were applied.
    ///   - `pending`: whether there is still work pending in the background.
    public func pollProcessing() throws -> (applied: Bool, pending: Bool) {
        var applied: UInt8 = 0
        var pending: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_poll_processing(handle, &applied, &pending)
        try library.ensureStatus(status, context: "editor_ui_poll_processing")
        return (applied != 0, pending != 0)
    }

    public func treeSitterStyleId(forCapture captureName: String) throws -> UInt32 {
        var out: UInt32 = 0
        let status = captureName.withCString { cstr in
            editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_style_id_for_capture")
        return out
    }

    public func treeSitterCapture(forStyleId styleId: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(handle, styleId) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_treesitter_capture_for_style_id", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspApplyDiagnosticsJSON(_ publishDiagnosticsParamsJSON: String) throws {
        let status = publishDiagnosticsParamsJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_diagnostics_json")
    }

    public func lspApplyInlayHintsJSON(_ inlayHintsResultJSON: String) throws {
        let status = inlayHintsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_inlay_hints_json")
    }

    public func lspApplyCodeLensJSON(_ codeLensResultJSON: String) throws {
        let status = codeLensResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_code_lens_json")
    }

    public func lspApplyDocumentLinksJSON(_ documentLinksResultJSON: String) throws {
        let status = documentLinksResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_links_json")
    }

    public func lspApplyDocumentHighlightsJSON(_ documentHighlightsResultJSON: String) throws {
        let status = documentHighlightsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_highlights_json")
    }

    public func lspApplyDocumentSymbolsJSON(_ documentSymbolsResultJSON: String) throws {
        let status = documentSymbolsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_symbols_json")
    }

    public func lspApplyFoldingRangesJSON(_ foldingRangesResultJSON: String) throws {
        let status = foldingRangesResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_folding_ranges_json")
    }

    public func lspApplyFoldingRanges(_ result: EcuLspFoldingRangeResult) throws {
        try lspApplyFoldingRangesJSON(result.rawJSONString ?? "null")
    }

    @discardableResult
    public func lspApplyWorkspaceEditJSON(_ workspaceEditJSON: String, documentURI: String? = nil) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = workspaceEditJSON.withCString { editPtr in
            if let documentURI {
                return documentURI.withCString { uriPtr in
                    editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(handle, editPtr, uriPtr)
                }
            }
            return editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(handle, editPtr, nil)
        }
        guard let ptr else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_apply_workspace_edit_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspApplySemanticTokens(_ data: [UInt32]) throws {
        let status = data.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_semantic_tokens")
    }

    @discardableResult
    public func lspApplySemanticTokens(
        _ result: EcuLspSemanticTokensResult,
        baseline: [UInt32] = []
    ) throws -> [UInt32] {
        let data = try result.dataForApplying(baseline: baseline)
        try lspApplySemanticTokens(data)
        return data
    }
}
