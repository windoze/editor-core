import Foundation

public enum EcuLspCodeActionResultShape: String, Equatable, Sendable {
    case none
    case actionArray = "action_array"
}

public struct EcuLspCodeActionResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspCodeActionResultShape
    public var items: [EcuLspCodeActionElement]
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

        shape = .actionArray
        items = try single.decode([EcuLspCodeActionElement].self)
    }
}

public enum EcuLspCodeActionElement: Equatable, Sendable, Decodable {
    case codeAction(EcuLspCodeAction)
    case command(EcuLspCommand)
    case unknown(EcuJSONValue)

    public var codeAction: EcuLspCodeAction? {
        guard case let .codeAction(action) = self else { return nil }
        return action
    }

    public var command: EcuLspCommand? {
        guard case let .command(command) = self else { return nil }
        return command
    }

    public init(from decoder: Decoder) throws {
        let raw = (try? EcuJSONValue(from: decoder)) ?? .null
        let object = Self.object(from: raw)
        let hasCodeActionFields = object.keys.contains { key in
            switch key {
            case "kind", "diagnostics", "edit", "isPreferred", "disabled", "data":
                return true
            default:
                return false
            }
        }

        if hasCodeActionFields, let action = try? EcuLspCodeAction(from: decoder) {
            self = .codeAction(action)
            return
        }

        if object["command"] != nil, let command = try? EcuLspCommand(from: decoder) {
            self = .command(command)
            return
        }

        if let action = try? EcuLspCodeAction(from: decoder) {
            self = .codeAction(action)
            return
        }

        self = .unknown(raw)
    }

    private static func object(from value: EcuJSONValue) -> [String: EcuJSONValue] {
        guard case let .object(object) = value else { return [:] }
        return object
    }
}

public struct EcuLspCodeAction: Equatable, Sendable, Decodable {
    public var title: String
    public var kind: String?
    public var diagnostics: [EcuLspCodeActionDiagnostic]
    public var isPreferred: Bool?
    public var disabled: EcuLspCodeActionDisabled?
    public var edit: EcuLspWorkspaceEdit?
    public var command: EcuLspCommand?
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        diagnostics = try container.decodeIfPresent(
            [EcuLspCodeActionDiagnostic].self,
            forKey: .diagnostics
        ) ?? []
        isPreferred = try container.decodeIfPresent(Bool.self, forKey: .isPreferred)
        disabled = try container.decodeIfPresent(EcuLspCodeActionDisabled.self, forKey: .disabled)
        edit = try container.decodeIfPresent(EcuLspWorkspaceEdit.self, forKey: .edit)
        command = try container.decodeIfPresent(EcuLspCommand.self, forKey: .command)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case kind
        case diagnostics
        case isPreferred
        case disabled
        case edit
        case command
        case data
    }
}

public struct EcuLspCodeActionDisabled: Equatable, Sendable, Decodable {
    public var reason: String
}

public struct EcuLspCodeActionDiagnostic: Equatable, Sendable, Decodable {
    public var range: EcuLspRange
    public var severity: Int?
    public var code: EcuJSONValue?
    public var codeDescription: EcuJSONValue?
    public var source: String?
    public var message: String
    public var tags: [Int]
    public var relatedInformation: [EcuJSONValue]
    public var data: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decode(EcuLspRange.self, forKey: .range)
        severity = try container.decodeIfPresent(Int.self, forKey: .severity)
        code = try container.decodeIfPresent(EcuJSONValue.self, forKey: .code)
        codeDescription = try container.decodeIfPresent(EcuJSONValue.self, forKey: .codeDescription)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        message = try container.decode(String.self, forKey: .message)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        relatedInformation = try container.decodeIfPresent(
            [EcuJSONValue].self,
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
