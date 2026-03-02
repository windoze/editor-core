import Foundation

private struct LspUriResponse: Decodable {
    let uri: String
}

private struct LspPathResponse: Decodable {
    let path: String
}

private struct LspEncodedResponse: Decodable {
    let encoded: String
}

private struct LspDecodedResponse: Decodable {
    let decoded: String
}

public struct LspChangedRange: Equatable, Sendable, Decodable {
    public let start: Int
    public let end: Int
}

private struct LspChangedRangesResponse: Decodable {
    let changedRanges: [LspChangedRange]
}

public struct LspInterval: Equatable, Sendable, Decodable {
    public let start: Int
    public let end: Int
    public let styleId: UInt32
}

private struct LspIntervalsResponse: Decodable {
    let intervals: [LspInterval]
}

public struct LspSemanticStyleIdDecoded: Equatable, Sendable, Decodable {
    public let tokenType: UInt32
    public let tokenModifiers: UInt32
}

public final class LSPBridge {
    public let ffi: EditorCoreFFILibrary

    public init(library: EditorCoreFFILibrary) {
        self.ffi = library
    }

    public func pathToFileURI(_ path: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = path.withCString { pathPtr in
            ffi.lspPathToFileURIFn(pathPtr)
        }
        let json = try ffi.takeOwnedCString(ptr, context: "lsp_path_to_file_uri")
        return try JSON.decode(LspUriResponse.self, from: json, context: "path_to_file_uri").uri
    }

    public func fileURIToPath(_ uri: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = uri.withCString { uriPtr in
            ffi.lspFileURIToPathFn(uriPtr)
        }
        let json = try ffi.takeOwnedCString(ptr, context: "lsp_file_uri_to_path")
        return try JSON.decode(LspPathResponse.self, from: json, context: "file_uri_to_path").path
    }

    public func percentEncodePath(_ path: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = path.withCString { pathPtr in
            ffi.lspPercentEncodePathFn(pathPtr)
        }
        let json = try ffi.takeOwnedCString(ptr, context: "lsp_percent_encode_path")
        return try JSON.decode(LspEncodedResponse.self, from: json, context: "percent_encode_path").encoded
    }

    public func percentDecodePath(_ path: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = path.withCString { pathPtr in
            ffi.lspPercentDecodePathFn(pathPtr)
        }
        let json = try ffi.takeOwnedCString(ptr, context: "lsp_percent_decode_path")
        return try JSON.decode(LspDecodedResponse.self, from: json, context: "percent_decode_path").decoded
    }

    public func charOffsetToUTF16(lineText: String, charOffset: Int) -> Int {
        let offset = max(0, charOffset)
        let value = lineText.withCString { textPtr in
            ffi.lspCharOffsetToUTF16Fn(textPtr, UInt(offset))
        }
        return Int(value)
    }

    public func utf16OffsetToCharOffset(lineText: String, utf16Offset: Int) -> Int {
        let offset = max(0, utf16Offset)
        let value = lineText.withCString { textPtr in
            ffi.lspUTF16ToCharOffsetFn(textPtr, UInt(offset))
        }
        return Int(value)
    }

    public func applyTextEditsJSON(state: EditorState, editsJSON: String) throws -> [LspChangedRange] {
        let ptr: UnsafeMutablePointer<CChar>? = editsJSON.withCString { jsonPtr in
            ffi.lspApplyTextEditsJSONFn(state.handle, jsonPtr)
        }
        let json = try ffi.takeOwnedCString(ptr, context: "lsp_apply_text_edits_json")
        return try JSON.decode(LspChangedRangesResponse.self, from: json, context: "apply_text_edits").changedRanges
    }

    public func semanticTokensToIntervalsJSON(state: EditorState, dataJSON: String) throws -> [LspInterval] {
        let ptr: UnsafeMutablePointer<CChar>? = dataJSON.withCString { jsonPtr in
            ffi.lspSemanticTokensToIntervalsJSONFn(state.handle, jsonPtr)
        }
        let json = try ffi.takeOwnedCString(ptr, context: "lsp_semantic_tokens_to_intervals_json")
        return try JSON.decode(LspIntervalsResponse.self, from: json, context: "semantic_tokens_to_intervals").intervals
    }

    public func decodeSemanticStyleId(_ styleId: UInt32) throws -> LspSemanticStyleIdDecoded {
        let ptr = ffi.lspDecodeSemanticStyleIDFn(styleId)
        let json = try ffi.takeOwnedCString(ptr, context: "lsp_decode_semantic_style_id")
        return try JSON.decode(LspSemanticStyleIdDecoded.self, from: json, context: "decode_semantic_style_id")
    }

    public func encodeSemanticStyleId(tokenType: UInt32, tokenModifiers: UInt32) -> UInt32 {
        ffi.lspEncodeSemanticStyleIDFn(tokenType, tokenModifiers)
    }

    public func documentHighlightsToProcessingEditJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            ffi.lspDocumentHighlightsToProcessingEditJSONFn(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_document_highlights_to_processing_edit_json")
    }

    public func inlayHintsToProcessingEditJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            ffi.lspInlayHintsToProcessingEditJSONFn(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_inlay_hints_to_processing_edit_json")
    }

    public func documentLinksToProcessingEditJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            ffi.lspDocumentLinksToProcessingEditJSONFn(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_document_links_to_processing_edit_json")
    }

    public func codeLensToProcessingEditJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            ffi.lspCodeLensToProcessingEditJSONFn(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_code_lens_to_processing_edit_json")
    }

    public func documentSymbolsToProcessingEditJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            ffi.lspDocumentSymbolsToProcessingEditJSONFn(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_document_symbols_to_processing_edit_json")
    }

    public func diagnosticsToProcessingEditsJSON(state: EditorState, publishDiagnosticsParamsJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = publishDiagnosticsParamsJSON.withCString { jsonPtr in
            ffi.lspDiagnosticsToProcessingEditsJSONFn(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_diagnostics_to_processing_edits_json")
    }

    public func workspaceSymbolsJSON(resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            ffi.lspWorkspaceSymbolsJSONFn(jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_workspace_symbols_json")
    }

    public func locationsJSON(resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            ffi.lspLocationsJSONFn(jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_locations_json")
    }

    public func completionItemToTextEditsJSON(
        state: EditorState,
        completionItemJSON: String,
        mode: String,
        fallback: (start: Int, end: Int)?
    ) throws -> String {
        let start = UInt(max(0, fallback?.start ?? 0))
        let end = UInt(max(0, fallback?.end ?? 0))
        let hasFallback = fallback != nil

        let ptr: UnsafeMutablePointer<CChar>? = completionItemJSON.withCString { itemPtr in
            mode.withCString { modePtr in
                ffi.lspCompletionItemToTextEditsJSONFn(
                    state.handle,
                    itemPtr,
                    modePtr,
                    start,
                    end,
                    hasFallback
                )
            }
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_completion_item_to_text_edits_json")
    }

    public func applyCompletionItemJSON(state: EditorState, completionItemJSON: String, mode: String) throws {
        let ok = completionItemJSON.withCString { itemPtr in
            mode.withCString { modePtr in
                ffi.lspApplyCompletionItemJSONFn(state.handle, itemPtr, modePtr)
            }
        }
        guard ok else {
            let message = ffi.lastErrorMessage()
            throw EditorCoreFFIError.ffiStatus(code: .internal, context: "lsp_apply_completion_item_json", message: message.isEmpty ? "no last_error_message" : message)
        }
    }
}

