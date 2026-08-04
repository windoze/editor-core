public enum EcuLspFoldingRangeResultShape: String, Equatable, Sendable {
    case none
    case foldingRangeArray = "folding_range_array"
}

public struct EcuLspFoldingRangeResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspFoldingRangeResultShape
    public var ranges: [EcuLspFoldingRange]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        ranges.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            ranges = []
            return
        }

        shape = .foldingRangeArray
        ranges = try single.decode([EcuLspFoldingRange].self)
    }
}

public struct EcuLspFoldingRange: Equatable, Sendable, Decodable {
    public var startLine: UInt32
    public var startCharacter: UInt32?
    public var endLine: UInt32
    public var endCharacter: UInt32?
    public var kind: String?
    public var collapsedText: String?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startLine = try container.decode(UInt32.self, forKey: .startLine)
        startCharacter = try container.decodeIfPresent(UInt32.self, forKey: .startCharacter)
        endLine = try container.decode(UInt32.self, forKey: .endLine)
        endCharacter = try container.decodeIfPresent(UInt32.self, forKey: .endCharacter)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        collapsedText = try container.decodeIfPresent(String.self, forKey: .collapsedText)
    }

    private enum CodingKeys: String, CodingKey {
        case startLine
        case startCharacter
        case endLine
        case endCharacter
        case kind
        case collapsedText
    }
}
