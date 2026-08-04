public enum EcuLspCallHierarchyPrepareResultShape: String, Equatable, Sendable {
    case none
    case item
    case itemArray = "item_array"
}

public struct EcuLspCallHierarchyPrepareResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspCallHierarchyPrepareResultShape
    public var items: [EcuLspCallHierarchyItem]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            items = []
            return
        }

        if let item = try? single.decode(EcuLspCallHierarchyItem.self) {
            shape = .item
            items = [item]
            return
        }

        shape = .itemArray
        items = try single.decode([EcuLspCallHierarchyItem].self)
    }
}

public enum EcuLspCallHierarchyIncomingCallsResultShape: String, Equatable, Sendable {
    case none
    case incomingCallArray = "incoming_call_array"
}

public struct EcuLspCallHierarchyIncomingCallsResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspCallHierarchyIncomingCallsResultShape
    public var calls: [EcuLspCallHierarchyIncomingCall]
    public var raw: EcuJSONValue?

    public var isEmpty: Bool {
        calls.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            calls = []
            return
        }

        shape = .incomingCallArray
        calls = try single.decode([EcuLspCallHierarchyIncomingCall].self)
    }
}

public enum EcuLspCallHierarchyOutgoingCallsResultShape: String, Equatable, Sendable {
    case none
    case outgoingCallArray = "outgoing_call_array"
}

public struct EcuLspCallHierarchyOutgoingCallsResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspCallHierarchyOutgoingCallsResultShape
    public var calls: [EcuLspCallHierarchyOutgoingCall]
    public var raw: EcuJSONValue?

    public var isEmpty: Bool {
        calls.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            calls = []
            return
        }

        shape = .outgoingCallArray
        calls = try single.decode([EcuLspCallHierarchyOutgoingCall].self)
    }
}

public struct EcuLspCallHierarchyIncomingCall: Equatable, Sendable, Decodable {
    public var from: EcuLspCallHierarchyItem
    public var fromRanges: [EcuLspRange]
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(EcuLspCallHierarchyItem.self, forKey: .from)
        fromRanges = try container.decodeIfPresent([EcuLspRange].self, forKey: .fromRanges) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case from
        case fromRanges
    }
}

public struct EcuLspCallHierarchyOutgoingCall: Equatable, Sendable, Decodable {
    public var to: EcuLspCallHierarchyItem
    public var fromRanges: [EcuLspRange]
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        to = try container.decode(EcuLspCallHierarchyItem.self, forKey: .to)
        fromRanges = try container.decodeIfPresent([EcuLspRange].self, forKey: .fromRanges) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case to
        case fromRanges
    }
}

public struct EcuLspCallHierarchyItem: Equatable, Sendable, Decodable {
    public var name: String
    public var kind: Int
    public var tags: [Int]
    public var detail: String?
    public var uri: String
    public var range: EcuLspRange
    public var selectionRange: EcuLspRange
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var target: EcuLspLocationTarget {
        EcuLspLocationTarget(
            uri: uri,
            range: range,
            selectionRange: selectionRange,
            sourceKind: .location
        )
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(Int.self, forKey: .kind)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        uri = try container.decode(String.self, forKey: .uri)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        selectionRange = try container.decode(EcuLspRange.self, forKey: .selectionRange)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case tags
        case detail
        case uri
        case range
        case selectionRange
        case data
    }
}

public enum EcuLspTypeHierarchyPrepareResultShape: String, Equatable, Sendable {
    case none
    case item
    case itemArray = "item_array"
}

public struct EcuLspTypeHierarchyPrepareResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspTypeHierarchyPrepareResultShape
    public var items: [EcuLspTypeHierarchyItem]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            items = []
            return
        }

        if let item = try? single.decode(EcuLspTypeHierarchyItem.self) {
            shape = .item
            items = [item]
            return
        }

        shape = .itemArray
        items = try single.decode([EcuLspTypeHierarchyItem].self)
    }
}

public enum EcuLspTypeHierarchyItemsResultShape: String, Equatable, Sendable {
    case none
    case itemArray = "item_array"
}

public struct EcuLspTypeHierarchyItemsResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspTypeHierarchyItemsResultShape
    public var items: [EcuLspTypeHierarchyItem]
    public var raw: EcuJSONValue?

    public var isEmpty: Bool {
        items.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            items = []
            return
        }

        shape = .itemArray
        items = try single.decode([EcuLspTypeHierarchyItem].self)
    }
}

public struct EcuLspTypeHierarchyItem: Equatable, Sendable, Decodable {
    public var name: String
    public var kind: Int
    public var tags: [Int]
    public var detail: String?
    public var uri: String
    public var range: EcuLspRange
    public var selectionRange: EcuLspRange
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var target: EcuLspLocationTarget {
        EcuLspLocationTarget(
            uri: uri,
            range: range,
            selectionRange: selectionRange,
            sourceKind: .location
        )
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(Int.self, forKey: .kind)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        uri = try container.decode(String.self, forKey: .uri)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        selectionRange = try container.decode(EcuLspRange.self, forKey: .selectionRange)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case tags
        case detail
        case uri
        case range
        case selectionRange
        case data
    }
}
