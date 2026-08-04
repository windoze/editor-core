import CEditorCoreFFI
import Foundation

public extension LSPBridge {
    func onTypeFormattingParamsEnvelopeJSON(
        state: EditorState,
        uri: String,
        ch: String,
        optionsJSON: String? = nil
    ) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = uri.withCString { uriPtr in
            ch.withCString { chPtr in
                if let optionsJSON {
                    return optionsJSON.withCString { optionsPtr in
                        editor_core_ffi_lsp_on_type_formatting_params_envelope_json(
                            state.handle,
                            uriPtr,
                            chPtr,
                            optionsPtr
                        )
                    }
                }
                return editor_core_ffi_lsp_on_type_formatting_params_envelope_json(
                    state.handle,
                    uriPtr,
                    chPtr,
                    nil
                )
            }
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_on_type_formatting_params_envelope_json")
    }

    func onTypeFormattingParamsEnvelope(
        state: EditorState,
        uri: String,
        ch: String,
        optionsJSON: String? = nil
    ) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try onTypeFormattingParamsEnvelopeJSON(
                state: state,
                uri: uri,
                ch: ch,
                optionsJSON: optionsJSON
            ),
            context: "lsp_on_type_formatting_params_envelope_decode"
        )
    }

    func applyTextEditsEnvelopeJSON(state: EditorState, editsJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = editsJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_apply_text_edits_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_apply_text_edits_envelope_json")
    }

    func applyTextEditsEnvelope(state: EditorState, editsJSON: String) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try applyTextEditsEnvelopeJSON(state: state, editsJSON: editsJSON),
            context: "lsp_apply_text_edits_envelope_decode"
        )
    }

    func semanticTokensToIntervalsEnvelopeJSON(state: EditorState, dataJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = dataJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_semantic_tokens_to_intervals_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_semantic_tokens_to_intervals_envelope_json")
    }

    func semanticTokensToIntervalsEnvelope(state: EditorState, dataJSON: String) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try semanticTokensToIntervalsEnvelopeJSON(state: state, dataJSON: dataJSON),
            context: "lsp_semantic_tokens_to_intervals_envelope_decode"
        )
    }

    func documentHighlightsToProcessingEditEnvelopeJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_document_highlights_to_processing_edit_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(
            ptr,
            context: "lsp_document_highlights_to_processing_edit_envelope_json"
        )
    }

    func documentHighlightsToProcessingEditEnvelope(
        state: EditorState,
        resultJSON: String
    ) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try documentHighlightsToProcessingEditEnvelopeJSON(state: state, resultJSON: resultJSON),
            context: "lsp_document_highlights_to_processing_edit_envelope_decode"
        )
    }

    func inlayHintsToProcessingEditEnvelopeJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_inlay_hints_to_processing_edit_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_inlay_hints_to_processing_edit_envelope_json")
    }

    func inlayHintsToProcessingEditEnvelope(state: EditorState, resultJSON: String) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try inlayHintsToProcessingEditEnvelopeJSON(state: state, resultJSON: resultJSON),
            context: "lsp_inlay_hints_to_processing_edit_envelope_decode"
        )
    }

    func documentLinksToProcessingEditEnvelopeJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_document_links_to_processing_edit_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_document_links_to_processing_edit_envelope_json")
    }

    func documentLinksToProcessingEditEnvelope(state: EditorState, resultJSON: String) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try documentLinksToProcessingEditEnvelopeJSON(state: state, resultJSON: resultJSON),
            context: "lsp_document_links_to_processing_edit_envelope_decode"
        )
    }

    func codeLensToProcessingEditEnvelopeJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_code_lens_to_processing_edit_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_code_lens_to_processing_edit_envelope_json")
    }

    func codeLensToProcessingEditEnvelope(state: EditorState, resultJSON: String) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try codeLensToProcessingEditEnvelopeJSON(state: state, resultJSON: resultJSON),
            context: "lsp_code_lens_to_processing_edit_envelope_decode"
        )
    }

    func documentSymbolsToProcessingEditEnvelopeJSON(state: EditorState, resultJSON: String) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = resultJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_document_symbols_to_processing_edit_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_document_symbols_to_processing_edit_envelope_json")
    }

    func documentSymbolsToProcessingEditEnvelope(
        state: EditorState,
        resultJSON: String
    ) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try documentSymbolsToProcessingEditEnvelopeJSON(state: state, resultJSON: resultJSON),
            context: "lsp_document_symbols_to_processing_edit_envelope_decode"
        )
    }

    func diagnosticsToProcessingEditsEnvelopeJSON(
        state: EditorState,
        publishDiagnosticsParamsJSON: String
    ) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = publishDiagnosticsParamsJSON.withCString { jsonPtr in
            editor_core_ffi_lsp_diagnostics_to_processing_edits_envelope_json(state.handle, jsonPtr)
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_diagnostics_to_processing_edits_envelope_json")
    }

    func diagnosticsToProcessingEditsEnvelope(
        state: EditorState,
        publishDiagnosticsParamsJSON: String
    ) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try diagnosticsToProcessingEditsEnvelopeJSON(
                state: state,
                publishDiagnosticsParamsJSON: publishDiagnosticsParamsJSON
            ),
            context: "lsp_diagnostics_to_processing_edits_envelope_decode"
        )
    }

    func completionItemToTextEditsEnvelopeJSON(
        state: EditorState,
        completionItemJSON: String,
        mode: String,
        fallback: (start: Int, end: Int)?
    ) throws -> String {
        let start = UInt64(max(0, fallback?.start ?? 0))
        let end = UInt64(max(0, fallback?.end ?? 0))
        let hasFallback = fallback != nil

        let ptr: UnsafeMutablePointer<CChar>? = completionItemJSON.withCString { itemPtr in
            mode.withCString { modePtr in
                editor_core_ffi_lsp_completion_item_to_text_edits_envelope_json(
                    state.handle,
                    itemPtr,
                    modePtr,
                    start,
                    end,
                    hasFallback
                )
            }
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_completion_item_to_text_edits_envelope_json")
    }

    func completionItemToTextEditsEnvelope(
        state: EditorState,
        completionItemJSON: String,
        mode: String,
        fallback: (start: Int, end: Int)?
    ) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try completionItemToTextEditsEnvelopeJSON(
                state: state,
                completionItemJSON: completionItemJSON,
                mode: mode,
                fallback: fallback
            ),
            context: "lsp_completion_item_to_text_edits_envelope_decode"
        )
    }

    func applyCompletionItemEnvelopeJSON(
        state: EditorState,
        completionItemJSON: String,
        mode: String
    ) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = completionItemJSON.withCString { itemPtr in
            mode.withCString { modePtr in
                editor_core_ffi_lsp_apply_completion_item_envelope_json(state.handle, itemPtr, modePtr)
            }
        }
        return try ffi.takeOwnedCString(ptr, context: "lsp_apply_completion_item_envelope_json")
    }

    func applyCompletionItemEnvelope(
        state: EditorState,
        completionItemJSON: String,
        mode: String
    ) throws -> EcfLSPHelperEnvelope {
        try decodeLspEditEnvelope(
            try applyCompletionItemEnvelopeJSON(
                state: state,
                completionItemJSON: completionItemJSON,
                mode: mode
            ),
            context: "lsp_apply_completion_item_envelope_decode"
        )
    }

    private func decodeLspEditEnvelope(_ json: String, context: String) throws -> EcfLSPHelperEnvelope {
        try JSON.decode(EcfLSPHelperEnvelope.self, from: json, context: context)
    }
}
