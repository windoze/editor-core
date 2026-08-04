public enum EcuLspDocumentDiagnosticResultShape: String, Equatable, Sendable {
    case none
    case report
}

public struct EcuLspDocumentDiagnosticResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspDocumentDiagnosticResultShape
    public var report: EcuLspDiagnosticReport?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        report?.diagnostics.isEmpty ?? true
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            report = nil
            return
        }

        shape = .report
        report = try EcuLspDiagnosticReport(from: decoder)
    }
}

public enum EcuLspWorkspaceDiagnosticResultShape: String, Equatable, Sendable {
    case none
    case report
}

public struct EcuLspWorkspaceDiagnosticResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspWorkspaceDiagnosticResultShape
    public var items: [EcuLspWorkspaceDiagnosticReportItem]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        items.allSatisfy(\.diagnostics.isEmpty)
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            items = []
            return
        }

        shape = .report
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent(
            [EcuLspWorkspaceDiagnosticReportItem].self,
            forKey: .items
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

public enum EcuLspDiagnosticReportKind: Equatable, Sendable {
    case full
    case unchanged
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "full":
            self = .full
        case "unchanged":
            self = .unchanged
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .full:
            return "full"
        case .unchanged:
            return "unchanged"
        case let .unknown(raw):
            return raw
        }
    }
}

public struct EcuLspDiagnosticReport: Equatable, Sendable, Decodable {
    public var kind: String
    public var resultId: String?
    public var diagnostics: [EcuLspDiagnostic]
    public var relatedDocuments: [String: EcuLspDiagnosticReport]
    public var raw: EcuJSONValue?

    public var kindKind: EcuLspDiagnosticReportKind {
        EcuLspDiagnosticReportKind(rawValue: kind)
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "full"
        resultId = try container.decodeIfPresent(String.self, forKey: .resultId)
        diagnostics = try container.decodeIfPresent([EcuLspDiagnostic].self, forKey: .items) ?? []
        relatedDocuments = try container.decodeIfPresent(
            [String: EcuLspDiagnosticReport].self,
            forKey: .relatedDocuments
        ) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case resultId
        case items
        case relatedDocuments
    }
}

public struct EcuLspWorkspaceDiagnosticReportItem: Equatable, Sendable, Decodable {
    public var uri: String
    public var version: Int?
    public var kind: String
    public var resultId: String?
    public var diagnostics: [EcuLspDiagnostic]
    public var relatedDocuments: [String: EcuLspDiagnosticReport]
    public var raw: EcuJSONValue?

    public var kindKind: EcuLspDiagnosticReportKind {
        EcuLspDiagnosticReportKind(rawValue: kind)
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "full"
        resultId = try container.decodeIfPresent(String.self, forKey: .resultId)
        diagnostics = try container.decodeIfPresent([EcuLspDiagnostic].self, forKey: .items) ?? []
        relatedDocuments = try container.decodeIfPresent(
            [String: EcuLspDiagnosticReport].self,
            forKey: .relatedDocuments
        ) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case uri
        case version
        case kind
        case resultId
        case items
        case relatedDocuments
    }
}

public struct EcuLspDiagnostic: Equatable, Sendable, Decodable {
    public var range: EcuLspRange
    public var severity: Int?
    public var code: EcuJSONValue?
    public var codeDescription: EcuLspCodeDescription?
    public var source: String?
    public var message: String
    public var tags: [Int]
    public var relatedInformation: [EcuLspDiagnosticRelatedInformation]
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var severityKind: EcuLspDiagnosticSeverity? {
        severity.map(EcuLspDiagnosticSeverity.init(rawValue:))
    }

    public var severityLabel: String? {
        severityKind?.label
    }

    public var codeString: String? {
        switch code {
        case let .string(value):
            return value
        case let .number(value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool, .array, .object, .null, .none:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        severity = try container.decodeIfPresent(Int.self, forKey: .severity)
        code = try container.decodeIfPresent(EcuJSONValue.self, forKey: .code)
        codeDescription = try container.decodeIfPresent(EcuLspCodeDescription.self, forKey: .codeDescription)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        message = try container.decode(String.self, forKey: .message)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        relatedInformation = try container.decodeIfPresent(
            [EcuLspDiagnosticRelatedInformation].self,
            forKey: .relatedInformation
        ) ?? []
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case severity
        case code
        case codeDescription
        case source
        case message
        case tags
        case relatedInformation
        case data
    }
}

public enum EcuLspDiagnosticSeverity: Equatable, Sendable {
    case error
    case warning
    case information
    case hint
    case unknown(Int)

    public init(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .error
        case 2:
            self = .warning
        case 3:
            self = .information
        case 4:
            self = .hint
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .error:
            return 1
        case .warning:
            return 2
        case .information:
            return 3
        case .hint:
            return 4
        case let .unknown(raw):
            return raw
        }
    }

    public var label: String? {
        switch self {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .information:
            return "information"
        case .hint:
            return "hint"
        case .unknown:
            return nil
        }
    }
}

public struct EcuLspCodeDescription: Equatable, Sendable, Decodable {
    public var href: String
}

public struct EcuLspDiagnosticRelatedInformation: Equatable, Sendable, Decodable {
    public var location: EcuLspLocation
    public var message: String
}
