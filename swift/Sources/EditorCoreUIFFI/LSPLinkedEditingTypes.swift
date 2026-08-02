public enum EcuLspLinkedEditingRangeResultShape: String, Equatable, Sendable {
    case none
    case linkedEditingRange = "linked_editing_range"
}

public struct EcuLspLinkedEditingRangeResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspLinkedEditingRangeResultShape
    public var value: EcuLspLinkedEditingRange?
    public var raw: EcuJSONValue?

    public var ranges: [EcuLspRange] {
        value?.ranges ?? []
    }

    public var wordPattern: String? {
        value?.wordPattern
    }

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        value == nil || ranges.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            value = nil
            return
        }

        shape = .linkedEditingRange
        value = try single.decode(EcuLspLinkedEditingRange.self)
    }
}

public struct EcuLspLinkedEditingRange: Equatable, Sendable, Decodable {
    public var ranges: [EcuLspRange]
    public var wordPattern: String?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ranges = try container.decodeIfPresent([EcuLspRange].self, forKey: .ranges) ?? []
        wordPattern = try container.decodeIfPresent(String.self, forKey: .wordPattern)
    }

    private enum CodingKeys: String, CodingKey {
        case ranges
        case wordPattern
    }
}
