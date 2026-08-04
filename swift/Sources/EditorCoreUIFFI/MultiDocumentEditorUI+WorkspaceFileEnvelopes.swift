import CEditorCoreUIFFI
import Foundation

public typealias EcuWorkspaceFileOperationEnvelope = EcuMultiDocumentSearchEnvelope
public typealias EcuWorkspaceFileOperationEnvelopeError = EcuMultiDocumentSearchEnvelopeError
public typealias EcuWorkspaceFileOperationEnvelopeStatus = EcuMultiDocumentSearchEnvelopeStatus

public extension EcuMultiDocumentSearchEnvelope {
    func workspaceFileSearchResponse() throws -> EcuWorkspaceFileSearchResponse {
        try decodeWorkspaceFileValue(
            EcuWorkspaceFileSearchResponse.self,
            context: "multi_document_search_workspace_files_envelope_value_decode"
        )
    }

    func workspaceFileSearchResults() throws -> [EcuWorkspaceFileSearchResult] {
        try workspaceFileSearchResponse().results
    }

    func workspaceFileListResponse() throws -> EcuWorkspaceFileListResponse {
        try decodeWorkspaceFileValue(
            EcuWorkspaceFileListResponse.self,
            context: "multi_document_list_workspace_files_envelope_value_decode"
        )
    }

    func workspaceFileEntries() throws -> [EcuWorkspaceFileEntry] {
        try workspaceFileListResponse().files
    }

    func projectFileIndexSnapshot() throws -> EcuProjectFileIndexSnapshot {
        try decodeWorkspaceFileValue(
            EcuProjectFileIndexSnapshot.self,
            context: "multi_document_project_file_index_snapshot_envelope_value_decode"
        )
    }

    func projectFileIndexQueryResults() throws -> [EcuProjectFileIndexQueryResult] {
        try decodeWorkspaceFileValue(
            EcuProjectFileIndexQueryResponse.self,
            context: "multi_document_query_project_file_index_envelope_value_decode"
        ).results
    }

    func workspaceFileReplacementWorkspaceEditPayloadJSON() throws -> String {
        try workspaceFileEnvelopeValueJSON(
            context: "multi_document_workspace_file_replacement_workspace_edit_envelope_value_encode"
        )
    }

    private func decodeWorkspaceFileValue<T: Decodable>(_ type: T.Type, context: String) throws -> T {
        let json = try workspaceFileEnvelopeValueJSON(context: context)
        guard let data = json.data(using: .utf8) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidUtf8,
                context: context,
                message: "encoded envelope value is not UTF-8"
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: String(describing: error)
            )
        }
    }

    private func workspaceFileEnvelopeValueJSON(context: String) throws -> String {
        if ok == false {
            throw EditorCoreUIFFIError.ffiStatus(
                code: error?.status ?? .commandFailed,
                context: context,
                message: error?.message ?? "workspace file operation envelope failed"
            )
        }
        guard let value else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: context,
                message: "workspace file operation envelope did not contain a value"
            )
        }
        do {
            let data = try JSONEncoder().encode(value)
            guard let json = String(data: data, encoding: .utf8) else {
                throw EditorCoreUIFFIError.ffiStatus(
                    code: .invalidUtf8,
                    context: context,
                    message: "encoded envelope value is not UTF-8"
                )
            }
            return json
        } catch let error as EditorCoreUIFFIError {
            throw error
        } catch {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: String(describing: error)
            )
        }
    }
}

extension MultiDocumentEditorUI {
    private static func encodeScanOptions(
        _ options: EcuWorkspaceFileScanOptions,
        context: String
    ) throws -> String {
        do {
            let data = try JSONEncoder().encode(options)
            guard let json = String(data: data, encoding: .utf8) else {
                throw EditorCoreUIFFIError.ffiStatus(
                    code: .invalidUtf8,
                    context: context,
                    message: "encoded scan options are not UTF-8"
                )
            }
            return json
        } catch let error as EditorCoreUIFFIError {
            throw error
        } catch {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: String(describing: error)
            )
        }
    }

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

    public func listWorkspaceFilesEnvelopeJSON(
        scanOptions: EcuWorkspaceFileScanOptions
    ) throws -> String {
        let optionsJSON = try Self.encodeScanOptions(
            scanOptions,
            context: "multi_document_workspace_file_list_scan_options_encode"
        )
        return try ffiStringResult(context: "multi_document_list_workspace_files_with_options_envelope_json") {
            optionsJSON.withCString { optionsPtr in
                editor_core_ui_ffi_multi_document_list_workspace_files_with_options_envelope_json(
                    handle,
                    optionsPtr
                )
            }
        }
    }

    public func listWorkspaceFilesEnvelope(
        scanOptions: EcuWorkspaceFileScanOptions
    ) throws -> EcuWorkspaceFileOperationEnvelope {
        try decode(
            EcuWorkspaceFileOperationEnvelope.self,
            from: listWorkspaceFilesEnvelopeJSON(scanOptions: scanOptions),
            context: "multi_document_list_workspace_files_with_options_envelope_decode"
        )
    }

    public func searchWorkspaceFilesEnvelopeJSON(
        query: String,
        options: EcuSearchOptions = EcuSearchOptions(),
        scanOptions: EcuWorkspaceFileScanOptions
    ) throws -> String {
        let optionsJSON = try Self.encodeScanOptions(
            scanOptions,
            context: "multi_document_workspace_file_search_scan_options_encode"
        )
        return try ffiStringResult(context: "multi_document_search_workspace_files_with_options_envelope_json") {
            query.withCString { queryPtr in
                optionsJSON.withCString { optionsPtr in
                    editor_core_ui_ffi_multi_document_search_workspace_files_with_options_envelope_json(
                        handle,
                        queryPtr,
                        optionsPtr,
                        options.ffiCaseSensitive,
                        options.ffiWholeWord,
                        options.ffiRegex
                    )
                }
            }
        }
    }

    public func searchWorkspaceFilesEnvelope(
        query: String,
        options: EcuSearchOptions = EcuSearchOptions(),
        scanOptions: EcuWorkspaceFileScanOptions
    ) throws -> EcuMultiDocumentSearchEnvelope {
        try decode(
            EcuMultiDocumentSearchEnvelope.self,
            from: searchWorkspaceFilesEnvelopeJSON(
                query: query,
                options: options,
                scanOptions: scanOptions
            ),
            context: "multi_document_search_workspace_files_with_options_envelope_decode"
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

    public func workspaceFileReplacementWorkspaceEditEnvelopeJSON(
        query: String,
        replacement: String,
        options: EcuSearchOptions = EcuSearchOptions(),
        scanOptions: EcuWorkspaceFileScanOptions,
        applyMode: String = "atomic"
    ) throws -> String {
        let optionsJSON = try Self.encodeScanOptions(
            scanOptions,
            context: "multi_document_workspace_file_replacement_scan_options_encode"
        )
        return try ffiStringResult(context: "multi_document_workspace_file_replacement_with_options_envelope_json") {
            query.withCString { queryPtr in
                replacement.withCString { replacementPtr in
                    optionsJSON.withCString { optionsPtr in
                        applyMode.withCString { applyModePtr in
                            editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_with_options_envelope_json(
                                handle,
                                queryPtr,
                                replacementPtr,
                                optionsPtr,
                                applyModePtr,
                                options.ffiCaseSensitive,
                                options.ffiWholeWord,
                                options.ffiRegex
                            )
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
        scanOptions: EcuWorkspaceFileScanOptions,
        applyMode: String = "atomic"
    ) throws -> EcuWorkspaceFileOperationEnvelope {
        try decode(
            EcuWorkspaceFileOperationEnvelope.self,
            from: workspaceFileReplacementWorkspaceEditEnvelopeJSON(
                query: query,
                replacement: replacement,
                options: options,
                scanOptions: scanOptions,
                applyMode: applyMode
            ),
            context: "multi_document_workspace_file_replacement_with_options_envelope_decode"
        )
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
