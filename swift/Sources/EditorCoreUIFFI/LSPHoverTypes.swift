import Foundation

public enum EcuLspHoverResultShape: String, Equatable, Sendable {
    case none
    case hover
}

public struct EcuLspHoverResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspHoverResultShape
    public var contents: [EcuLspHoverContent]
    public var range: EcuLspRange?
    public var raw: EcuJSONValue?

    public var isEmpty: Bool {
        displayText == nil
    }

    public var displayText: String? {
        let text = contents.compactMap(\.text).joined(separator: "\n\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            contents = []
            range = nil
            raw = .null
            return
        }

        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = .hover
        contents = try container.decodeIfPresent(EcuLspHoverContentList.self, forKey: .contents)?.parts ?? []
        range = try container.decodeIfPresent(EcuLspRange.self, forKey: .range)
    }

    private enum CodingKeys: String, CodingKey {
        case contents
        case range
    }
}

public enum EcuLspHoverContent: Equatable, Sendable, Decodable {
    case plain(String)
    case markup(kind: String, value: String)
    case markedString(language: String, value: String)
    case unknown(EcuJSONValue)

    public var text: String? {
        let value: String?
        switch self {
        case let .plain(text):
            value = text
        case let .markup(_, text):
            value = text
        case let .markedString(_, text):
            value = text
        case .unknown:
            value = nil
        }

        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            self = .plain(value)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if
            let kind = try container.decodeIfPresent(String.self, forKey: .kind),
            let value = try container.decodeIfPresent(String.self, forKey: .value)
        {
            self = .markup(kind: kind, value: value)
            return
        }

        if
            let language = try container.decodeIfPresent(String.self, forKey: .language),
            let value = try container.decodeIfPresent(String.self, forKey: .value)
        {
            self = .markedString(language: language, value: value)
            return
        }

        self = .unknown(try EcuJSONValue(from: decoder))
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case language
        case value
    }
}

private struct EcuLspHoverContentList: Decodable {
    var parts: [EcuLspHoverContent]

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let parts = try? single.decode([EcuLspHoverContent].self) {
            self.parts = parts
        } else {
            self.parts = [try EcuLspHoverContent(from: decoder)]
        }
    }
}
