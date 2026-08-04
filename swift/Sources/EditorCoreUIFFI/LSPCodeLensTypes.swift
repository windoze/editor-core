public enum EcuLspCodeLensResultShape: String, Equatable, Sendable {
    case none
    case lensArray = "lens_array"
    case error
}

public struct EcuLspCodeLensResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspCodeLensResultShape
    public var items: [EcuLspCodeLens]
    public var error: EcuLspResponseError?
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
            error = nil
            return
        }

        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.error) {
            shape = .error
            items = []
            error = try container.decode(EcuLspResponseError.self, forKey: .error)
            return
        }

        shape = .lensArray
        items = try single.decode([EcuLspCodeLens].self)
        error = nil
    }

    private enum CodingKeys: String, CodingKey {
        case error
    }
}

public struct EcuLspCodeLens: Equatable, Sendable, Decodable {
    public var range: EcuLspRange
    public var command: EcuLspCommand?
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        command = try container.decodeIfPresent(EcuLspCommand.self, forKey: .command)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case command
        case data
    }
}

public struct EcuLspResponseError: Equatable, Sendable, Decodable {
    public var code: Int?
    public var message: String
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? "Unknown LSP error."
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }
}
