public enum EcuLspSelectionRangeResultShape: String, Equatable, Sendable {
    case none
    case selectionRangeArray = "selection_range_array"
}

public struct EcuLspSelectionRangeResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspSelectionRangeResultShape
    public var roots: [EcuLspSelectionRange]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        roots.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            roots = []
            return
        }

        shape = .selectionRangeArray
        roots = try single.decode([EcuLspSelectionRange].self)
    }
}

public indirect enum EcuLspSelectionRange: Equatable, Sendable, Decodable {
    case node(EcuLspSelectionRangeNode)

    public var range: EcuLspRange {
        switch self {
        case let .node(node):
            return node.range
        }
    }

    public var parent: EcuLspSelectionRange? {
        switch self {
        case let .node(node):
            return node.parent
        }
    }

    public var raw: EcuJSONValue? {
        switch self {
        case let .node(node):
            return node.raw
        }
    }

    public init(from decoder: Decoder) throws {
        self = .node(try EcuLspSelectionRangeNode(from: decoder))
    }
}

public struct EcuLspSelectionRangeNode: Equatable, Sendable, Decodable {
    public var range: EcuLspRange
    public var parent: EcuLspSelectionRange?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        parent = try container.decodeIfPresent(EcuLspSelectionRange.self, forKey: .parent)
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case parent
    }
}
