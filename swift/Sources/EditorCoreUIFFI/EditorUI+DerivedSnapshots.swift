import CEditorCoreUIFFI
import Foundation

public enum EcuDerivedSnapshotName: String, Hashable, Sendable {
    case diagnostics
    case decorations
    case documentSymbols = "document_symbols"
    case foldingRegions = "folding_regions"
    case styleIntervals = "style_intervals"
}

public enum EcuDerivedSnapshotEnvelopeStatus: Hashable, Sendable {
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

public struct EcuDerivedSnapshotEnvelopeRange: Decodable, Equatable, Sendable {
    public let start: UInt32
    public let end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(UInt32.self, forKey: .start) ?? 0
        end = try container.decodeIfPresent(UInt32.self, forKey: .end) ?? 0
    }
}

public struct EcuDerivedSnapshotEnvelope: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let snapshot: String?
    public let range: EcuDerivedSnapshotEnvelopeRange
    public let status: String
    public let value: EcuJSONValue?
    public let error: EcuDerivedSnapshotEnvelopeError?
    public let version: UInt32

    public var statusKind: EcuDerivedSnapshotEnvelopeStatus {
        EcuDerivedSnapshotEnvelopeStatus(rawValue: status)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case snapshot
        case range
        case status
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        snapshot = try container.decodeIfPresent(String.self, forKey: .snapshot)
        range = try container.decodeIfPresent(EcuDerivedSnapshotEnvelopeRange.self, forKey: .range)
            ?? EcuDerivedSnapshotEnvelopeRange(start: 0, end: 0)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        if container.contains(.value) {
            value = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            value = nil
        }
        error = try container.decodeIfPresent(EcuDerivedSnapshotEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuDerivedSnapshotEnvelopeError: Decodable, Equatable, Sendable {
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
    func derivedSnapshotEnvelopeJSON(
        snapshotRawValue: String,
        start: UInt32 = 0,
        end: UInt32 = 0
    ) throws -> String {
        guard let ptr = snapshotRawValue.withCString({
            editor_core_ui_ffi_editor_ui_derived_snapshot_envelope_json(handle, $0, start, end)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_derived_snapshot_envelope_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    func derivedSnapshotEnvelopeJSON(
        snapshot: EcuDerivedSnapshotName,
        start: UInt32 = 0,
        end: UInt32 = 0
    ) throws -> String {
        try derivedSnapshotEnvelopeJSON(snapshotRawValue: snapshot.rawValue, start: start, end: end)
    }

    func derivedSnapshotEnvelope(
        snapshotRawValue: String,
        start: UInt32 = 0,
        end: UInt32 = 0
    ) throws -> EcuDerivedSnapshotEnvelope {
        try Self.decodeSnapshot(
            EcuDerivedSnapshotEnvelope.self,
            from: derivedSnapshotEnvelopeJSON(snapshotRawValue: snapshotRawValue, start: start, end: end),
            context: "editor_ui_derived_snapshot_envelope_decode"
        )
    }

    func derivedSnapshotEnvelope(
        snapshot: EcuDerivedSnapshotName,
        start: UInt32 = 0,
        end: UInt32 = 0
    ) throws -> EcuDerivedSnapshotEnvelope {
        try derivedSnapshotEnvelope(snapshotRawValue: snapshot.rawValue, start: start, end: end)
    }
}
