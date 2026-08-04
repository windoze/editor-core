import CEditorCoreUIFFI

public typealias EcuWorkspaceFileOperationEnvelope = EcuMultiDocumentSearchEnvelope
public typealias EcuWorkspaceFileOperationEnvelopeError = EcuMultiDocumentSearchEnvelopeError
public typealias EcuWorkspaceFileOperationEnvelopeStatus = EcuMultiDocumentSearchEnvelopeStatus

extension MultiDocumentEditorUI {
    public func listWorkspaceFilesEnvelopeJSON(
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        maxResults: UInt32 = 10_000
    ) throws -> String {
        let includeJSON = try Self.encodeStringArray(
            includeGlobs,
            context: "multi_document_workspace_file_list_include_globs_encode"
        )
        let excludeJSON = try Self.encodeStringArray(
            excludeGlobs,
            context: "multi_document_workspace_file_list_exclude_globs_encode"
        )
        return try ffiStringResult(context: "multi_document_list_workspace_files_envelope_json") {
            includeJSON.withCString { includePtr in
                excludeJSON.withCString { excludePtr in
                    editor_core_ui_ffi_multi_document_list_workspace_files_envelope_json(
                        handle,
                        includePtr,
                        excludePtr,
                        maxResults
                    )
                }
            }
        }
    }

    public func listWorkspaceFilesEnvelope(
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        maxResults: UInt32 = 10_000
    ) throws -> EcuWorkspaceFileOperationEnvelope {
        try decode(
            EcuWorkspaceFileOperationEnvelope.self,
            from: listWorkspaceFilesEnvelopeJSON(
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs,
                maxResults: maxResults
            ),
            context: "multi_document_list_workspace_files_envelope_decode"
        )
    }

    public func refreshProjectFileIndexEnvelopeJSON(maxResults: UInt32 = 10_000) throws -> String {
        try ffiStringResult(context: "multi_document_refresh_project_file_index_envelope_json") {
            editor_core_ui_ffi_multi_document_refresh_project_file_index_envelope_json(handle, maxResults)
        }
    }

    public func refreshProjectFileIndexEnvelope(
        maxResults: UInt32 = 10_000
    ) throws -> EcuWorkspaceFileOperationEnvelope {
        try decode(
            EcuWorkspaceFileOperationEnvelope.self,
            from: refreshProjectFileIndexEnvelopeJSON(maxResults: maxResults),
            context: "multi_document_refresh_project_file_index_envelope_decode"
        )
    }

    public func projectFileIndexSnapshotEnvelopeJSON() throws -> String {
        try ffiStringResult(context: "multi_document_project_file_index_snapshot_envelope_json") {
            editor_core_ui_ffi_multi_document_project_file_index_snapshot_envelope_json(handle)
        }
    }

    public func projectFileIndexSnapshotEnvelope() throws -> EcuWorkspaceFileOperationEnvelope {
        try decode(
            EcuWorkspaceFileOperationEnvelope.self,
            from: projectFileIndexSnapshotEnvelopeJSON(),
            context: "multi_document_project_file_index_snapshot_envelope_decode"
        )
    }

    public func queryProjectFileIndexEnvelopeJSON(query: String, maxResults: UInt32 = 200) throws -> String {
        try ffiStringResult(context: "multi_document_query_project_file_index_envelope_json") {
            query.withCString { queryPtr in
                editor_core_ui_ffi_multi_document_query_project_file_index_envelope_json(
                    handle,
                    queryPtr,
                    maxResults
                )
            }
        }
    }

    public func queryProjectFileIndexEnvelope(
        query: String,
        maxResults: UInt32 = 200
    ) throws -> EcuWorkspaceFileOperationEnvelope {
        try decode(
            EcuWorkspaceFileOperationEnvelope.self,
            from: queryProjectFileIndexEnvelopeJSON(query: query, maxResults: maxResults),
            context: "multi_document_query_project_file_index_envelope_decode"
        )
    }

    public func workspaceFileReplacementWorkspaceEditEnvelopeJSON(
        query: String,
        replacement: String,
        options: EcuSearchOptions = EcuSearchOptions(),
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        applyMode: String = "atomic",
        maxResults: UInt32 = 2000
    ) throws -> String {
        let includeJSON = try Self.encodeStringArray(
            includeGlobs,
            context: "multi_document_workspace_file_replacement_include_globs_encode"
        )
        let excludeJSON = try Self.encodeStringArray(
            excludeGlobs,
            context: "multi_document_workspace_file_replacement_exclude_globs_encode"
        )
        return try ffiStringResult(context: "multi_document_workspace_file_replacement_workspace_edit_envelope_json") {
            query.withCString { queryPtr in
                replacement.withCString { replacementPtr in
                    includeJSON.withCString { includePtr in
                        excludeJSON.withCString { excludePtr in
                            applyMode.withCString { applyModePtr in
                                editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_envelope_json(
                                    handle,
                                    queryPtr,
                                    replacementPtr,
                                    includePtr,
                                    excludePtr,
                                    applyModePtr,
                                    options.ffiCaseSensitive,
                                    options.ffiWholeWord,
                                    options.ffiRegex,
                                    maxResults
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    public func workspaceFileReplacementWorkspaceEditEnvelope(
        query: String,
        replacement: String,
        options: EcuSearchOptions = EcuSearchOptions(),
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        applyMode: String = "atomic",
        maxResults: UInt32 = 2000
    ) throws -> EcuWorkspaceFileOperationEnvelope {
        try decode(
            EcuWorkspaceFileOperationEnvelope.self,
            from: workspaceFileReplacementWorkspaceEditEnvelopeJSON(
                query: query,
                replacement: replacement,
                options: options,
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs,
                applyMode: applyMode,
                maxResults: maxResults
            ),
            context: "multi_document_workspace_file_replacement_workspace_edit_envelope_decode"
        )
    }
}
