import CEditorCoreUIFFI
import Foundation

public typealias EcuLspSemanticTokensApplicationEnvelope = EcuLspDerivedStateApplicationEnvelope
public typealias EcuLspSemanticTokensApplicationEnvelopeError = EcuLspDerivedStateApplicationEnvelopeError
public typealias EcuLspSemanticTokensApplicationEnvelopeStatus = EcuLspDerivedStateApplicationEnvelopeStatus

public extension EditorUI {
    func lspApplySemanticTokensEnvelopeJSON(_ data: [UInt32]) throws -> String {
        let ptr = data.withUnsafeBufferPointer { buffer in
            editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens_envelope_json(
                handle,
                buffer.baseAddress,
                UInt32(buffer.count)
            )
        }
        guard let ptr else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_apply_semantic_tokens_envelope_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    func lspApplySemanticTokensEnvelope(_ data: [UInt32]) throws -> EcuLspSemanticTokensApplicationEnvelope {
        try Self.decodeSnapshot(
            EcuLspSemanticTokensApplicationEnvelope.self,
            from: lspApplySemanticTokensEnvelopeJSON(data),
            context: "editor_ui_lsp_apply_semantic_tokens_envelope_decode"
        )
    }

    @discardableResult
    func lspApplySemanticTokensEnvelope(
        _ result: EcuLspSemanticTokensResult,
        baseline: [UInt32] = []
    ) throws -> EcuLspSemanticTokensApplicationEnvelope {
        try lspApplySemanticTokensEnvelope(result.dataForApplying(baseline: baseline))
    }
}
