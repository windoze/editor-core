import CEditorCoreUIFFI
import Foundation

public enum EcuLspDerivedStateApplicationOperation: Hashable, Sendable {
    case applyDiagnostics
    case applyInlayHints
    case applyCodeLens
    case applyDocumentLinks
    case applyDocumentHighlights
    case applyDocumentSymbols
    case applyFoldingRanges
    case applySemanticTokens
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "apply_diagnostics":
            self = .applyDiagnostics
        case "apply_inlay_hints":
            self = .applyInlayHints
        case "apply_code_lens":
            self = .applyCodeLens
        case "apply_document_links":
            self = .applyDocumentLinks
        case "apply_document_highlights":
            self = .applyDocumentHighlights
        case "apply_document_symbols":
            self = .applyDocumentSymbols
        case "apply_folding_ranges":
            self = .applyFoldingRanges
        case "apply_semantic_tokens":
            self = .applySemanticTokens
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .applyDiagnostics:
            return "apply_diagnostics"
        case .applyInlayHints:
            return "apply_inlay_hints"
        case .applyCodeLens:
            return "apply_code_lens"
        case .applyDocumentLinks:
            return "apply_document_links"
        case .applyDocumentHighlights:
            return "apply_document_highlights"
        case .applyDocumentSymbols:
            return "apply_document_symbols"
        case .applyFoldingRanges:
            return "apply_folding_ranges"
        case .applySemanticTokens:
            return "apply_semantic_tokens"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspDerivedStateApplicationEnvelopeStatus: Hashable, Sendable {
    case success
    case error
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "success":
            self = .success
        case "error":
            self = .error
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .success:
            return "success"
        case .error:
            return "error"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public struct EcuLspDerivedStateApplicationValue: Decodable, Equatable, Sendable {
    public let applied: Bool
    public let dataLen: UInt32?

    private enum CodingKeys: String, CodingKey {
        case applied
        case dataLen
        case dataLenSnake = "data_len"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applied = try container.decodeIfPresent(Bool.self, forKey: .applied) ?? false
        dataLen = try container.decodeIfPresent(UInt32.self, forKey: .dataLen)
            ?? container.decodeIfPresent(UInt32.self, forKey: .dataLenSnake)
    }
}

public struct EcuLspDerivedStateApplicationEnvelope: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let operation: String
    public let status: String
    public let value: EcuLspDerivedStateApplicationValue?
    public let rawValue: EcuJSONValue?
    public let error: EcuLspDerivedStateApplicationEnvelopeError?
    public let version: UInt32

    public var operationKind: EcuLspDerivedStateApplicationOperation {
        EcuLspDerivedStateApplicationOperation(rawValue: operation)
    }

    public var statusKind: EcuLspDerivedStateApplicationEnvelopeStatus {
        EcuLspDerivedStateApplicationEnvelopeStatus(rawValue: status)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case operation
        case status
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "unknown"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        value = try container.decodeIfPresent(EcuLspDerivedStateApplicationValue.self, forKey: .value)
        if container.contains(.value) {
            rawValue = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            rawValue = nil
        }
        error = try container.decodeIfPresent(EcuLspDerivedStateApplicationEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuLspDerivedStateApplicationEnvelopeError: Decodable, Equatable, Sendable {
    public let code: String
    public let status: EcuStatus?
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case code
        case status
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        if let rawStatus = try container.decodeIfPresent(Int32.self, forKey: .status) {
            status = EcuStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

public extension EditorUI {
    func lspApplyDiagnosticsEnvelopeJSON(_ publishDiagnosticsParamsJSON: String) throws -> String {
        try lspDerivedStateApplicationEnvelopeJSON(
            publishDiagnosticsParamsJSON,
            context: "editor_ui_lsp_apply_diagnostics_envelope_json"
        ) { handle, jsonPtr in
            editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_envelope_json(handle, jsonPtr)
        }
    }

    func lspApplyInlayHintsEnvelopeJSON(_ inlayHintsResultJSON: String) throws -> String {
        try lspDerivedStateApplicationEnvelopeJSON(
            inlayHintsResultJSON,
            context: "editor_ui_lsp_apply_inlay_hints_envelope_json"
        ) { handle, jsonPtr in
            editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_envelope_json(handle, jsonPtr)
        }
    }

    func lspApplyCodeLensEnvelopeJSON(_ codeLensResultJSON: String) throws -> String {
        try lspDerivedStateApplicationEnvelopeJSON(
            codeLensResultJSON,
            context: "editor_ui_lsp_apply_code_lens_envelope_json"
        ) { handle, jsonPtr in
            editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_envelope_json(handle, jsonPtr)
        }
    }

    func lspApplyDocumentLinksEnvelopeJSON(_ documentLinksResultJSON: String) throws -> String {
        try lspDerivedStateApplicationEnvelopeJSON(
            documentLinksResultJSON,
            context: "editor_ui_lsp_apply_document_links_envelope_json"
        ) { handle, jsonPtr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_links_envelope_json(handle, jsonPtr)
        }
    }

    func lspApplyDocumentHighlightsEnvelopeJSON(_ documentHighlightsResultJSON: String) throws -> String {
        try lspDerivedStateApplicationEnvelopeJSON(
            documentHighlightsResultJSON,
            context: "editor_ui_lsp_apply_document_highlights_envelope_json"
        ) { handle, jsonPtr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_envelope_json(handle, jsonPtr)
        }
    }

    func lspApplyDocumentSymbolsEnvelopeJSON(_ documentSymbolsResultJSON: String) throws -> String {
        try lspDerivedStateApplicationEnvelopeJSON(
            documentSymbolsResultJSON,
            context: "editor_ui_lsp_apply_document_symbols_envelope_json"
        ) { handle, jsonPtr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_envelope_json(handle, jsonPtr)
        }
    }

    func lspApplyFoldingRangesEnvelopeJSON(_ foldingRangesResultJSON: String) throws -> String {
        try lspDerivedStateApplicationEnvelopeJSON(
            foldingRangesResultJSON,
            context: "editor_ui_lsp_apply_folding_ranges_envelope_json"
        ) { handle, jsonPtr in
            editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_envelope_json(handle, jsonPtr)
        }
    }

    func lspApplyDiagnosticsEnvelope(_ publishDiagnosticsParamsJSON: String) throws -> EcuLspDerivedStateApplicationEnvelope {
        try decodeLspDerivedStateApplicationEnvelope(
            lspApplyDiagnosticsEnvelopeJSON(publishDiagnosticsParamsJSON)
        )
    }

    func lspApplyInlayHintsEnvelope(_ inlayHintsResultJSON: String) throws -> EcuLspDerivedStateApplicationEnvelope {
        try decodeLspDerivedStateApplicationEnvelope(lspApplyInlayHintsEnvelopeJSON(inlayHintsResultJSON))
    }

    func lspApplyCodeLensEnvelope(_ codeLensResultJSON: String) throws -> EcuLspDerivedStateApplicationEnvelope {
        try decodeLspDerivedStateApplicationEnvelope(lspApplyCodeLensEnvelopeJSON(codeLensResultJSON))
    }

    func lspApplyDocumentLinksEnvelope(_ documentLinksResultJSON: String) throws -> EcuLspDerivedStateApplicationEnvelope {
        try decodeLspDerivedStateApplicationEnvelope(lspApplyDocumentLinksEnvelopeJSON(documentLinksResultJSON))
    }

    func lspApplyDocumentHighlightsEnvelope(_ documentHighlightsResultJSON: String) throws -> EcuLspDerivedStateApplicationEnvelope {
        try decodeLspDerivedStateApplicationEnvelope(
            lspApplyDocumentHighlightsEnvelopeJSON(documentHighlightsResultJSON)
        )
    }

    func lspApplyDocumentSymbolsEnvelope(_ documentSymbolsResultJSON: String) throws -> EcuLspDerivedStateApplicationEnvelope {
        try decodeLspDerivedStateApplicationEnvelope(lspApplyDocumentSymbolsEnvelopeJSON(documentSymbolsResultJSON))
    }

    func lspApplyFoldingRangesEnvelope(_ foldingRangesResultJSON: String) throws -> EcuLspDerivedStateApplicationEnvelope {
        try decodeLspDerivedStateApplicationEnvelope(lspApplyFoldingRangesEnvelopeJSON(foldingRangesResultJSON))
    }

    private func lspDerivedStateApplicationEnvelopeJSON(
        _ resultJSON: String,
        context: String,
        call: (OpaquePointer?, UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    ) throws -> String {
        let ptr = resultJSON.withCString { jsonPtr in
            call(handle, jsonPtr)
        }
        guard let ptr else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: context,
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    private func decodeLspDerivedStateApplicationEnvelope(
        _ json: String
    ) throws -> EcuLspDerivedStateApplicationEnvelope {
        try Self.decodeSnapshot(
            EcuLspDerivedStateApplicationEnvelope.self,
            from: json,
            context: "editor_ui_lsp_derived_state_application_envelope_decode"
        )
    }
}
