import Foundation

public enum EcuLspDocumentSymbolResultShape: String, Equatable, Sendable {
    case none
    case documentSymbolArray = "document_symbol_array"
    case symbolInformationArray = "symbol_information_array"
    case mixedArray = "mixed_array"
}

public struct EcuLspDocumentSymbolResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspDocumentSymbolResultShape
    public var items: [EcuLspDocumentSymbolElement]
    public var raw: EcuJSONValue?

    public var documentSymbols: [EcuLspDocumentSymbol] {
        items.compactMap(\.documentSymbol)
    }

    public var symbolInformation: [EcuLspSymbolInformation] {
        items.compactMap(\.symbolInformation)
    }

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

        items = try single.decode([EcuLspDocumentSymbolElement].self)
        let documentSymbolCount = items.compactMap(\.documentSymbol).count
        let symbolInformationCount = items.compactMap(\.symbolInformation).count
        if symbolInformationCount == 0 {
            shape = .documentSymbolArray
        } else if documentSymbolCount == 0 {
            shape = .symbolInformationArray
        } else {
            shape = .mixedArray
        }
    }
}

public enum EcuLspDocumentSymbolElement: Equatable, Sendable, Decodable {
    case documentSymbol(EcuLspDocumentSymbol)
    case symbolInformation(EcuLspSymbolInformation)
    case unknown(EcuJSONValue)

    public var documentSymbol: EcuLspDocumentSymbol? {
        guard case let .documentSymbol(symbol) = self else { return nil }
        return symbol
    }

    public var symbolInformation: EcuLspSymbolInformation? {
        guard case let .symbolInformation(symbol) = self else { return nil }
        return symbol
    }

    public init(from decoder: Decoder) throws {
        let raw = (try? EcuJSONValue(from: decoder)) ?? .null
        let object = Self.object(from: raw)

        if object["location"] != nil, let symbol = try? EcuLspSymbolInformation(from: decoder) {
            self = .symbolInformation(symbol)
            return
        }

        if let symbol = try? EcuLspDocumentSymbol(from: decoder) {
            self = .documentSymbol(symbol)
            return
        }

        self = .unknown(raw)
    }

    private static func object(from value: EcuJSONValue) -> [String: EcuJSONValue] {
        guard case let .object(object) = value else { return [:] }
        return object
    }
}

public enum EcuLspWorkspaceSymbolResultShape: String, Equatable, Sendable {
    case none
    case workspaceSymbolArray = "workspace_symbol_array"
}

public struct EcuLspWorkspaceSymbolResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspWorkspaceSymbolResultShape
    public var symbols: [EcuLspWorkspaceSymbol]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var isEmpty: Bool {
        symbols.isEmpty
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            symbols = []
            return
        }

        shape = .workspaceSymbolArray
        symbols = try single.decode([EcuLspWorkspaceSymbol].self)
    }
}

public struct EcuLspDocumentSymbol: Equatable, Sendable, Decodable {
    public var name: String
    public var detail: String?
    public var kind: Int
    public var tags: [Int]
    public var deprecated: Bool?
    public var range: EcuLspRange
    public var selectionRange: EcuLspRange
    public var children: [EcuLspDocumentSymbol]
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        kind = try container.decode(Int.self, forKey: .kind)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        selectionRange = try container.decode(EcuLspRange.self, forKey: .selectionRange)
        children = try container.decodeIfPresent([EcuLspDocumentSymbol].self, forKey: .children) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case detail
        case kind
        case tags
        case deprecated
        case range
        case selectionRange
        case children
    }
}

public struct EcuLspSymbolInformation: Equatable, Sendable, Decodable {
    public var name: String
    public var kind: Int
    public var tags: [Int]
    public var deprecated: Bool?
    public var location: EcuLspLocation
    public var containerName: String?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(Int.self, forKey: .kind)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated)
        location = try container.decode(EcuLspLocation.self, forKey: .location)
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case tags
        case deprecated
        case location
        case containerName
    }
}

public struct EcuLspWorkspaceSymbol: Equatable, Sendable, Decodable {
    public var name: String
    public var detail: String?
    public var kind: Int
    public var tags: [Int]
    public var containerName: String?
    public var location: EcuLspWorkspaceSymbolLocation?
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        kind = try container.decode(Int.self, forKey: .kind)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
        location = try container.decodeIfPresent(EcuLspWorkspaceSymbolLocation.self, forKey: .location)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case detail
        case kind
        case tags
        case containerName
        case location
        case data
    }
}

public enum EcuLspWorkspaceSymbolLocation: Equatable, Sendable, Decodable {
    case location(EcuLspLocation)
    case uri(String)
    case unknown(EcuJSONValue)

    public var target: EcuLspLocationTarget? {
        switch self {
        case let .location(location):
            return EcuLspLocationTarget(
                uri: location.uri,
                range: location.range,
                selectionRange: location.range,
                sourceKind: .location
            )
        case let .uri(uri):
            let zero = EcuLspRange(
                start: EcuLspPosition(line: 0, utf16Character: 0),
                end: EcuLspPosition(line: 0, utf16Character: 0)
            )
            return EcuLspLocationTarget(
                uri: uri,
                range: zero,
                selectionRange: zero,
                sourceKind: .location
            )
        case .unknown:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = (try? EcuJSONValue(from: decoder)) ?? .null
        if let location = try? EcuLspLocation(from: decoder) {
            self = .location(location)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uri = try container.decodeIfPresent(String.self, forKey: .uri) {
            self = .uri(uri)
            return
        }

        self = .unknown(raw)
    }

    private enum CodingKeys: String, CodingKey {
        case uri
    }
}
