import CEditorCoreUIFFI
import Foundation

public enum EcuProjectLspLifecycleEnvelopeOperation: Hashable, Sendable {
    case startPlan
    case stopPlan
    case restartPlan
    case lifecycleEvents
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "start_plan":
            self = .startPlan
        case "stop_plan":
            self = .stopPlan
        case "restart_plan":
            self = .restartPlan
        case "lifecycle_events":
            self = .lifecycleEvents
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .startPlan:
            return "start_plan"
        case .stopPlan:
            return "stop_plan"
        case .restartPlan:
            return "restart_plan"
        case .lifecycleEvents:
            return "lifecycle_events"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuProjectLspLifecycleEnvelopeStatus: Hashable, Sendable {
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

public struct EcuProjectLspLifecycleEnvelope: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let operation: String?
    public let status: String
    public let value: EcuJSONValue?
    public let error: EcuProjectLspLifecycleEnvelopeError?
    public let version: UInt32

    public var operationKind: EcuProjectLspLifecycleEnvelopeOperation? {
        operation.map(EcuProjectLspLifecycleEnvelopeOperation.init(rawValue:))
    }

    public var statusKind: EcuProjectLspLifecycleEnvelopeStatus {
        EcuProjectLspLifecycleEnvelopeStatus(rawValue: status)
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
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        if container.contains(.value) {
            value = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            value = nil
        }
        error = try container.decodeIfPresent(EcuProjectLspLifecycleEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuProjectLspLifecycleEnvelopeError: Decodable, Equatable, Sendable {
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

extension MultiDocumentEditorUI {
    public func projectLspLifecycleEnvelopeJSON(
        operationRawValue: String,
        after sequence: UInt64 = 0
    ) throws -> String {
        try ffiStringResult(context: "multi_document_project_lsp_lifecycle_envelope_json") {
            operationRawValue.withCString { operationPtr in
                editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
                    handle,
                    operationPtr,
                    sequence
                )
            }
        }
    }

    public func projectLspLifecycleEnvelope(
        operationRawValue: String,
        after sequence: UInt64 = 0
    ) throws -> EcuProjectLspLifecycleEnvelope {
        try decode(
            EcuProjectLspLifecycleEnvelope.self,
            from: projectLspLifecycleEnvelopeJSON(operationRawValue: operationRawValue, after: sequence),
            context: "multi_document_project_lsp_lifecycle_envelope_decode"
        )
    }

    public func projectLspLifecycleEnvelope(
        operation: EcuProjectLspLifecycleEnvelopeOperation,
        after sequence: UInt64 = 0
    ) throws -> EcuProjectLspLifecycleEnvelope {
        try projectLspLifecycleEnvelope(operationRawValue: operation.rawValue, after: sequence)
    }

    public func projectLspStartPlanEnvelope() throws -> EcuProjectLspLifecycleEnvelope {
        try projectLspLifecycleEnvelope(operation: .startPlan)
    }

    public func projectLspStopPlanEnvelope() throws -> EcuProjectLspLifecycleEnvelope {
        try projectLspLifecycleEnvelope(operation: .stopPlan)
    }

    public func projectLspRestartPlanEnvelope() throws -> EcuProjectLspLifecycleEnvelope {
        try projectLspLifecycleEnvelope(operation: .restartPlan)
    }

    public func projectLspLifecycleEventsEnvelope(
        after sequence: UInt64 = 0
    ) throws -> EcuProjectLspLifecycleEnvelope {
        try projectLspLifecycleEnvelope(operation: .lifecycleEvents, after: sequence)
    }
}
