public enum EcuLspInlayHintResultShape: String, Equatable, Sendable {
    case none
    case hintArray = "hint_array"
    case error
}

public struct EcuLspInlayHintResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspInlayHintResultShape
    public var hints: [EcuLspInlayHint]
    public var error: EcuLspResponseError?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        hints.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            hints = []
            error = nil
            return
        }

        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.error) {
            shape = .error
            hints = []
            error = try container.decode(EcuLspResponseError.self, forKey: .error)
            return
        }

        shape = .hintArray
        hints = try single.decode([EcuLspInlayHint].self)
        error = nil
    }

    private enum CodingKeys: String, CodingKey {
        case error
    }
}

public struct EcuLspInlayHint: Equatable, Sendable, Decodable {
    public var position: EcuLspPosition
    public var label: EcuLspInlayHintLabel
    public var kind: EcuLspInlayHintKind?
    public var textEdits: [EcuLspTextEdit]
    public var tooltip: EcuLspInlayHintTooltip?
    public var paddingLeft: Bool?
    public var paddingRight: Bool?
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(EcuLspPosition.self, forKey: .position)
        label = try container.decode(EcuLspInlayHintLabel.self, forKey: .label)
        kind = try container.decodeIfPresent(EcuLspInlayHintKind.self, forKey: .kind)
        textEdits = try container.decodeIfPresent([EcuLspTextEdit].self, forKey: .textEdits) ?? []
        tooltip = try container.decodeIfPresent(EcuLspInlayHintTooltip.self, forKey: .tooltip)
        paddingLeft = try container.decodeIfPresent(Bool.self, forKey: .paddingLeft)
        paddingRight = try container.decodeIfPresent(Bool.self, forKey: .paddingRight)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case position
        case label
        case kind
        case textEdits
        case tooltip
        case paddingLeft
        case paddingRight
        case data
    }
}

public enum EcuLspInlayHintLabel: Equatable, Sendable, Decodable {
    case string(String)
    case parts([EcuLspInlayHintLabelPart])

    public var plainText: String {
        switch self {
        case let .string(value):
            return value
        case let .parts(parts):
            return parts.map(\.value).joined()
        }
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            self = .string(value)
            return
        }
        self = .parts(try single.decode([EcuLspInlayHintLabelPart].self))
    }
}

public struct EcuLspInlayHintLabelPart: Equatable, Sendable, Decodable {
    public var value: String
    public var tooltip: EcuLspInlayHintTooltip?
    public var location: EcuLspLocation?
    public var command: EcuLspCommand?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .value)
        tooltip = try container.decodeIfPresent(EcuLspInlayHintTooltip.self, forKey: .tooltip)
        location = try container.decodeIfPresent(EcuLspLocation.self, forKey: .location)
        command = try container.decodeIfPresent(EcuLspCommand.self, forKey: .command)
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case tooltip
        case location
        case command
    }
}

public enum EcuLspInlayHintTooltip: Equatable, Sendable, Decodable {
    case string(String)
    case markup(EcuLspMarkupContent)
    case raw(EcuJSONValue)

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? single.decode(EcuLspMarkupContent.self) {
            self = .markup(value)
            return
        }
        self = .raw(try EcuJSONValue(from: decoder))
    }
}

public enum EcuLspInlayHintKind: Equatable, Sendable, Decodable {
    case type
    case parameter
    case unknown(Int)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Int.self)
        switch value {
        case 1:
            self = .type
        case 2:
            self = .parameter
        default:
            self = .unknown(value)
        }
    }
}

public enum EcuLspDocumentLinkResultShape: String, Equatable, Sendable {
    case none
    case linkArray = "link_array"
    case error
}

public struct EcuLspDocumentLinkResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspDocumentLinkResultShape
    public var links: [EcuLspDocumentLink]
    public var error: EcuLspResponseError?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        links.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            links = []
            error = nil
            return
        }

        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.error) {
            shape = .error
            links = []
            error = try container.decode(EcuLspResponseError.self, forKey: .error)
            return
        }

        shape = .linkArray
        links = try single.decode([EcuLspDocumentLink].self)
        error = nil
    }

    private enum CodingKeys: String, CodingKey {
        case error
    }
}

public struct EcuLspDocumentLink: Equatable, Sendable, Decodable {
    public var range: EcuLspRange
    public var target: String?
    public var tooltip: String?
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case target
        case tooltip
        case data
    }
}
