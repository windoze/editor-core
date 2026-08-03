import CEditorCoreUIFFI
import Foundation

public enum EcuLspStatusEnvelopeStatus: Hashable, Sendable {
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

public struct EcuLspStatusEnvelope: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let value: EcuLspStatusSnapshot?
    public let rawValue: EcuJSONValue?
    public let error: EcuLspStatusEnvelopeError?
    public let version: UInt32

    public var statusKind: EcuLspStatusEnvelopeStatus {
        EcuLspStatusEnvelopeStatus(rawValue: status)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case status
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        value = try container.decodeIfPresent(EcuLspStatusSnapshot.self, forKey: .value)
        if container.contains(.value) {
            rawValue = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            rawValue = nil
        }
        error = try container.decodeIfPresent(EcuLspStatusEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuLspStatusEnvelopeError: Decodable, Equatable, Sendable {
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
    func lspStatusEnvelopeJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_lsp_status_envelope_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_lsp_status_envelope_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    func lspStatusEnvelope() throws -> EcuLspStatusEnvelope {
        try Self.decodeSnapshot(
            EcuLspStatusEnvelope.self,
            from: lspStatusEnvelopeJSON(),
            context: "editor_ui_lsp_status_envelope_decode"
        )
    }
}
