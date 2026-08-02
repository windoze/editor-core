public enum EcuLspSignatureHelpResultShape: String, Equatable, Sendable {
    case none
    case help
}

public struct EcuLspSignatureHelpResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspSignatureHelpResultShape
    public var signatures: [EcuLspSignatureInformation]
    public var activeSignature: Int
    public var activeParameter: Int?
    public var raw: EcuJSONValue?

    public var isEmpty: Bool {
        signatures.isEmpty
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            signatures = []
            activeSignature = 0
            activeParameter = nil
            raw = .null
            return
        }

        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = .help
        signatures = try container.decodeIfPresent([EcuLspSignatureInformation].self, forKey: .signatures) ?? []
        activeSignature = try container.decodeIfPresent(Int.self, forKey: .activeSignature) ?? 0
        activeParameter = try container.decodeIfPresent(Int.self, forKey: .activeParameter)
    }

    private enum CodingKeys: String, CodingKey {
        case signatures
        case activeSignature
        case activeParameter
    }
}

public struct EcuLspSignatureInformation: Equatable, Sendable, Decodable {
    public var label: String
    public var documentation: EcuLspDocumentation?
    public var parameters: [EcuLspParameterInformation]
    public var activeParameter: Int?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        documentation = try container.decodeIfPresent(EcuLspDocumentation.self, forKey: .documentation)
        parameters = try container.decodeIfPresent([EcuLspParameterInformation].self, forKey: .parameters) ?? []
        activeParameter = try container.decodeIfPresent(Int.self, forKey: .activeParameter)
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case documentation
        case parameters
        case activeParameter
    }
}

public struct EcuLspParameterInformation: Equatable, Sendable, Decodable {
    public var label: EcuLspParameterLabel
    public var documentation: EcuLspDocumentation?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(EcuLspParameterLabel.self, forKey: .label)
        documentation = try container.decodeIfPresent(EcuLspDocumentation.self, forKey: .documentation)
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case documentation
    }
}

public enum EcuLspParameterLabel: Equatable, Sendable, Decodable {
    case string(String)
    case utf16Range(start: UInt32, end: UInt32)
    case unknown(EcuJSONValue)

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            self = .string(value)
            return
        }

        if let range = try? single.decode([UInt32].self),
           range.count == 2,
           range[1] > range[0]
        {
            self = .utf16Range(start: range[0], end: range[1])
            return
        }

        self = .unknown(try EcuJSONValue(from: decoder))
    }
}
