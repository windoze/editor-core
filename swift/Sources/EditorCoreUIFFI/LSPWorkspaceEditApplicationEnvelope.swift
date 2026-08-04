import CEditorCoreUIFFI
import Foundation

public struct EcuLspWorkspaceEditAppliedDocument: Decodable, Equatable, Sendable {
    public let uri: String
    public let editCount: Int
    public let hasOverlappingEdits: Bool

    private enum CodingKeys: String, CodingKey {
        case uri
        case editCount = "edit_count"
        case hasOverlappingEdits = "has_overlapping_edits"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
        editCount = try container.decodeIfPresent(Int.self, forKey: .editCount) ?? 0
        hasOverlappingEdits = try container.decodeIfPresent(Bool.self, forKey: .hasOverlappingEdits) ?? false
    }
}

public struct EcuLspWorkspaceEditApplicationResult: Decodable, Equatable, Sendable {
    public let applied: Bool
    public let appliedURI: String?
    public let appliedEditCount: Int
    public let skippedURIs: [String]
    public let documents: [EcuLspWorkspaceEditAppliedDocument]

    private enum CodingKeys: String, CodingKey {
        case applied
        case appliedURI = "applied_uri"
        case appliedEditCount = "applied_edit_count"
        case skippedURIs = "skipped_uris"
        case documents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applied = try container.decodeIfPresent(Bool.self, forKey: .applied) ?? false
        appliedURI = try container.decodeIfPresent(String.self, forKey: .appliedURI)
        appliedEditCount = try container.decodeIfPresent(Int.self, forKey: .appliedEditCount) ?? 0
        skippedURIs = try container.decodeIfPresent([String].self, forKey: .skippedURIs) ?? []
        documents = try container.decodeIfPresent([EcuLspWorkspaceEditAppliedDocument].self, forKey: .documents) ?? []
    }
}

public enum EcuLspWorkspaceEditApplicationEnvelopeStatus: Hashable, Sendable {
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

public struct EcuLspWorkspaceEditApplicationEnvelope: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let documentURI: String?
    public let value: EcuLspWorkspaceEditApplicationResult?
    public let rawValue: EcuJSONValue?
    public let error: EcuLspWorkspaceEditApplicationEnvelopeError?
    public let version: UInt32

    public var statusKind: EcuLspWorkspaceEditApplicationEnvelopeStatus {
        EcuLspWorkspaceEditApplicationEnvelopeStatus(rawValue: status)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case status
        case documentURI = "document_uri"
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        documentURI = try container.decodeIfPresent(String.self, forKey: .documentURI)
        value = try container.decodeIfPresent(EcuLspWorkspaceEditApplicationResult.self, forKey: .value)
        if container.contains(.value) {
            rawValue = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            rawValue = nil
        }
        error = try container.decodeIfPresent(EcuLspWorkspaceEditApplicationEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuLspWorkspaceEditApplicationEnvelopeError: Decodable, Equatable, Sendable {
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
    func lspApplyWorkspaceEditEnvelopeJSON(
        _ workspaceEditJSON: String,
        documentURI: String? = nil
    ) throws -> String {
        let ptr: UnsafeMutablePointer<CChar>? = workspaceEditJSON.withCString { editPtr in
            if let documentURI {
                return documentURI.withCString { uriPtr in
                    editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_envelope_json(handle, editPtr, uriPtr)
                }
            }
            return editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_envelope_json(handle, editPtr, nil)
        }
        guard let ptr else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_apply_workspace_edit_envelope_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    func lspApplyWorkspaceEditEnvelope(
        _ workspaceEditJSON: String,
        documentURI: String? = nil
    ) throws -> EcuLspWorkspaceEditApplicationEnvelope {
        try Self.decodeSnapshot(
            EcuLspWorkspaceEditApplicationEnvelope.self,
            from: lspApplyWorkspaceEditEnvelopeJSON(workspaceEditJSON, documentURI: documentURI),
            context: "editor_ui_lsp_apply_workspace_edit_envelope_decode"
        )
    }
}
