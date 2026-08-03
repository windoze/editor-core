import CEditorCoreFFI
import Foundation

func checkedFFIUInt32(_ value: UInt, context: String) throws -> UInt32 {
    guard value <= UInt(UInt32.max) else {
        throw EditorCoreFFIError.ffiStatus(
            code: .invalidArgument,
            context: context,
            message: "value exceeds uint32_t range: \(value)"
        )
    }
    return UInt32(value)
}

public struct DocumentStats: Equatable, Sendable {
    public let lineCount: UInt64
    public let charCount: UInt64
    public let byteCount: UInt64
    public let isModified: Bool
    public let version: UInt64

    init(raw: EcfDocumentStats) {
        self.lineCount = raw.line_count
        self.charCount = raw.char_count
        self.byteCount = raw.byte_count
        self.isModified = raw.is_modified != 0
        self.version = raw.version
    }
}

public struct WorkspaceInfo: Equatable, Sendable {
    public let bufferCount: UInt64
    public let viewCount: UInt64
    public let isEmpty: Bool
    public let activeViewId: UInt64?
    public let activeBufferId: UInt64?

    init(raw: EcfWorkspaceInfo) {
        self.bufferCount = raw.buffer_count
        self.viewCount = raw.view_count
        self.isEmpty = raw.is_empty != 0
        self.activeViewId = raw.has_active_view_id != 0 ? raw.active_view_id : nil
        self.activeBufferId = raw.has_active_buffer_id != 0 ? raw.active_buffer_id : nil
    }
}

public struct WorkspaceViewportState: Equatable, Sendable {
    public let widthCells: UInt32
    public let heightRows: UInt32?
    public let scrollTop: UInt32
    public let subRowOffset: UInt32
    public let overscanRows: UInt32
    public let visibleStart: UInt32
    public let visibleEnd: UInt32
    public let prefetchStart: UInt32
    public let prefetchEnd: UInt32
    public let totalVisualLines: UInt32

    init(raw: EcfWorkspaceViewportState) {
        self.widthCells = raw.width_cells
        self.heightRows = raw.has_height != 0 ? raw.height_rows : nil
        self.scrollTop = raw.scroll_top
        self.subRowOffset = raw.sub_row_offset
        self.overscanRows = raw.overscan_rows
        self.visibleStart = raw.visible_start
        self.visibleEnd = raw.visible_end
        self.prefetchStart = raw.prefetch_start
        self.prefetchEnd = raw.prefetch_end
        self.totalVisualLines = raw.total_visual_lines
    }
}

public struct EcfTextEdit: Equatable, Sendable {
    public let start: UInt32
    public let end: UInt32
    public let text: String

    public init(start: UInt32, end: UInt32, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    var jsonObject: [String: Any] {
        [
            "start": Int(start),
            "end": Int(end),
            "text": text,
        ]
    }
}

public indirect enum EcfJSONValue: Equatable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([EcfJSONValue])
    case object([String: EcfJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([EcfJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: EcfJSONValue].self))
        }
    }
}

public struct EcfJSONCommandEnvelope: Equatable, Sendable, Decodable {
    public var ok: Bool
    public var value: EcfJSONValue?
    public var error: EcfJSONCommandError?
    public var version: UInt32

    public init(ok: Bool, value: EcfJSONValue?, error: EcfJSONCommandError?, version: UInt32) {
        self.ok = ok
        self.value = value
        self.error = error
        self.version = version
    }
}

public struct EcfJSONCommandError: Equatable, Sendable, Decodable {
    public var code: String
    public var status: EcfStatus?
    public var message: String

    public init(code: String, status: EcfStatus?, message: String) {
        self.code = code
        self.status = status
        self.message = message
    }

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
            status = EcfStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

public enum EcfMinimapEnvelopeStatus: Hashable, Sendable {
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

public struct EcfMinimapEnvelope: Equatable, Sendable, Decodable {
    public let ok: Bool
    public let status: String
    public let surface: String
    public let viewId: UInt64?
    public let startVisualRow: UInt32
    public let count: UInt32
    public let value: EcfJSONValue?
    public let error: EcfMinimapEnvelopeError?
    public let version: UInt32

    public var statusKind: EcfMinimapEnvelopeStatus {
        EcfMinimapEnvelopeStatus(rawValue: status)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case status
        case surface
        case viewId
        case viewIdSnake = "view_id"
        case startVisualRow
        case startVisualRowSnake = "start_visual_row"
        case count
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        surface = try container.decodeIfPresent(String.self, forKey: .surface) ?? "unknown"
        viewId = try container.decodeIfPresent(UInt64.self, forKey: .viewId)
            ?? container.decodeIfPresent(UInt64.self, forKey: .viewIdSnake)
        startVisualRow = try container.decodeIfPresent(UInt32.self, forKey: .startVisualRow)
            ?? container.decodeIfPresent(UInt32.self, forKey: .startVisualRowSnake)
            ?? 0
        count = try container.decodeIfPresent(UInt32.self, forKey: .count) ?? 0
        if container.contains(.value) {
            value = try container.decode(EcfJSONValue.self, forKey: .value)
        } else {
            value = nil
        }
        error = try container.decodeIfPresent(EcfMinimapEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcfMinimapEnvelopeError: Equatable, Sendable, Decodable {
    public let code: String
    public let status: EcfStatus?
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
            status = EcfStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

public typealias EcfRenderingSnapshotEnvelope = EcfMinimapEnvelope
public typealias EcfRenderingSnapshotEnvelopeError = EcfMinimapEnvelopeError
public typealias EcfRenderingSnapshotEnvelopeStatus = EcfMinimapEnvelopeStatus

public struct EcfAutoPair: Equatable, Sendable {
    public let open: String
    public let close: String

    public init(open: String, close: String) {
        self.open = open
        self.close = close
    }

    var jsonObject: [String: Any] {
        [
            "open": open,
            "close": close,
        ]
    }
}

public struct EcfAutoPairsConfig: Equatable, Sendable {
    public var enabled: Bool?
    public var pairs: [EcfAutoPair]?
    public var wrapSelection: Bool?
    public var skipOverClosing: Bool?
    public var deletePair: Bool?

    public init(
        enabled: Bool? = nil,
        pairs: [EcfAutoPair]? = nil,
        wrapSelection: Bool? = nil,
        skipOverClosing: Bool? = nil,
        deletePair: Bool? = nil
    ) {
        self.enabled = enabled
        self.pairs = pairs
        self.wrapSelection = wrapSelection
        self.skipOverClosing = skipOverClosing
        self.deletePair = deletePair
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        if let enabled { object["enabled"] = enabled }
        if let pairs { object["pairs"] = pairs.map(\.jsonObject) }
        if let wrapSelection { object["wrap_selection"] = wrapSelection }
        if let skipOverClosing { object["skip_over_closing"] = skipOverClosing }
        if let deletePair { object["delete_pair"] = deletePair }
        return object
    }
}
