import EditorCoreUIFFI
import Foundation

typealias AttoCommandArguments = [String: AttoCommandArgumentValue]

enum AttoCommandArgumentValue: Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case json(String)

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    var typeName: String {
        switch self {
        case .string:
            return "string"
        case .integer:
            return "integer"
        case .number:
            return "number"
        case .boolean:
            return "boolean"
        case .json:
            return "json"
        }
    }
}

extension AttoCommandArgumentValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .json("null")
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .integer(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        let jsonValue = try AttoCommandArgumentJSONValue(from: decoder)
        self = .json(jsonValue.jsonString)
    }
}

private enum AttoCommandArgumentJSONValue: Encodable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AttoCommandArgumentJSONValue])
    case object([String: AttoCommandArgumentJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AttoCommandArgumentJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AttoCommandArgumentJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                AttoCommandArgumentJSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "unsupported command argument JSON value")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8)
        else {
            return "null"
        }
        return string
    }
}

enum AttoCommandParameterKind: String, Equatable {
    case string
    case integer
    case number
    case boolean
    case json
}

struct AttoCommandArgumentChoice: Equatable {
    let title: String
    let value: AttoCommandArgumentValue

    init(title: String, value: AttoCommandArgumentValue) {
        self.title = title
        self.value = value
    }
}

struct AttoCommandParameterSchema: Equatable {
    let name: String
    let title: String
    let kind: AttoCommandParameterKind
    let isRequired: Bool
    let defaultValue: AttoCommandArgumentValue?
    let choices: [AttoCommandArgumentChoice]
    let allowsEmptyString: Bool
    let minimumInteger: Int?
    let maximumInteger: Int?
    let help: String?

    init(
        name: String,
        title: String,
        kind: AttoCommandParameterKind,
        isRequired: Bool = false,
        defaultValue: AttoCommandArgumentValue? = nil,
        choices: [AttoCommandArgumentChoice] = [],
        allowsEmptyString: Bool = true,
        minimumInteger: Int? = nil,
        maximumInteger: Int? = nil,
        help: String? = nil
    ) {
        self.name = name
        self.title = title
        self.kind = kind
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.choices = choices
        self.allowsEmptyString = allowsEmptyString
        self.minimumInteger = minimumInteger
        self.maximumInteger = maximumInteger
        self.help = help
    }

    func normalizedValue(from arguments: AttoCommandArguments) throws -> AttoCommandArgumentValue? {
        guard let rawValue = arguments[name] else {
            if let defaultValue {
                return try validate(defaultValue)
            }
            if isRequired {
                throw AttoCommandSchemaValidationError.missingParameter(name)
            }
            return nil
        }
        return try validate(rawValue)
    }

    private func validate(_ value: AttoCommandArgumentValue) throws -> AttoCommandArgumentValue {
        let normalized: AttoCommandArgumentValue
        switch (kind, value) {
        case (.string, .string):
            normalized = value
        case (.integer, .integer):
            normalized = value
        case (.number, .number):
            normalized = value
        case (.number, .integer(let integer)):
            normalized = .number(Double(integer))
        case (.boolean, .boolean):
            normalized = value
        case (.json, .json):
            normalized = value
        default:
            throw AttoCommandSchemaValidationError.typeMismatch(
                name: name,
                expected: kind.rawValue,
                actual: value.typeName
            )
        }

        if case .string(let string) = normalized,
           string.isEmpty,
           allowsEmptyString == false
        {
            throw AttoCommandSchemaValidationError.emptyString(name)
        }

        if case .integer(let integer) = normalized {
            if let minimumInteger, integer < minimumInteger {
                throw AttoCommandSchemaValidationError.integerOutOfRange(
                    name: name,
                    minimum: minimumInteger,
                    maximum: maximumInteger
                )
            }
            if let maximumInteger, integer > maximumInteger {
                throw AttoCommandSchemaValidationError.integerOutOfRange(
                    name: name,
                    minimum: minimumInteger,
                    maximum: maximumInteger
                )
            }
        }

        if choices.isEmpty == false,
           choices.contains(where: { $0.value == normalized }) == false
        {
            throw AttoCommandSchemaValidationError.invalidChoice(name)
        }

        return normalized
    }
}

enum AttoCommandMacroPolicy: String, Equatable {
    case recordable
    case recordableWithArguments
    case promptRequired
    case notRecordable
}

struct AttoCommandSchema: Equatable {
    let parameters: [AttoCommandParameterSchema]
    let macroPolicy: AttoCommandMacroPolicy
    let defaultPayloadJSON: String?
    let requiredRuntimeFeatures: EditorCoreUIFFIFeatures
    let allowsUnknownArguments: Bool

    init(
        parameters: [AttoCommandParameterSchema] = [],
        macroPolicy: AttoCommandMacroPolicy = .notRecordable,
        defaultPayloadJSON: String? = nil,
        requiredRuntimeFeatures: EditorCoreUIFFIFeatures = [],
        allowsUnknownArguments: Bool = false
    ) {
        self.parameters = parameters
        self.macroPolicy = macroPolicy
        self.defaultPayloadJSON = defaultPayloadJSON
        self.requiredRuntimeFeatures = requiredRuntimeFeatures
        self.allowsUnknownArguments = allowsUnknownArguments
    }

    var isParameterized: Bool {
        parameters.isEmpty == false
    }

    func normalizedArguments(_ arguments: AttoCommandArguments) throws -> AttoCommandArguments {
        if allowsUnknownArguments == false {
            let known = Set(parameters.map(\.name))
            if let unknown = arguments.keys.first(where: { known.contains($0) == false }) {
                throw AttoCommandSchemaValidationError.unknownParameter(unknown)
            }
        }

        var normalized: AttoCommandArguments = allowsUnknownArguments ? arguments : [:]
        for parameter in parameters {
            if let value = try parameter.normalizedValue(from: arguments) {
                normalized[parameter.name] = value
            }
        }
        return normalized
    }
}

enum AttoCommandSchemaValidationError: Error, Equatable, CustomStringConvertible {
    case missingParameter(String)
    case unknownParameter(String)
    case typeMismatch(name: String, expected: String, actual: String)
    case emptyString(String)
    case integerOutOfRange(name: String, minimum: Int?, maximum: Int?)
    case invalidChoice(String)

    var description: String {
        switch self {
        case .missingParameter(let name):
            return "Missing command parameter '\(name)'."
        case .unknownParameter(let name):
            return "Unknown command parameter '\(name)'."
        case .typeMismatch(let name, let expected, let actual):
            return "Command parameter '\(name)' expected \(expected), got \(actual)."
        case .emptyString(let name):
            return "Command parameter '\(name)' cannot be empty."
        case .integerOutOfRange(let name, let minimum, let maximum):
            switch (minimum, maximum) {
            case (.some(let min), .some(let max)):
                return "Command parameter '\(name)' must be between \(min) and \(max)."
            case (.some(let min), .none):
                return "Command parameter '\(name)' must be at least \(min)."
            case (.none, .some(let max)):
                return "Command parameter '\(name)' must be at most \(max)."
            case (.none, .none):
                return "Command parameter '\(name)' is out of range."
            }
        case .invalidChoice(let name):
            return "Command parameter '\(name)' is not an allowed choice."
        }
    }
}

extension Dictionary where Key == String, Value == AttoCommandArgumentValue {
    func string(_ name: String) -> String? {
        self[name]?.stringValue
    }

    func integer(_ name: String) -> Int? {
        self[name]?.integerValue
    }
}

extension EditorCoreUIFFIFeatures {
    static let lspInteractiveCommandRequirements: Self = [
        .lspInteractiveRequests,
        .lspStatusSnapshot,
    ]

    static let lspWorkspaceEditCommandRequirements: Self = [
        .lspInteractiveRequests,
        .lspStatusSnapshot,
        .workspaceEditApplication,
    ]

    static let workspaceEditTransactionUndoCommandRequirements: Self = [
        .multiDocumentWorkspaceEditTransaction,
        .multiDocumentWorkspaceEditTransactionUndo,
    ]

    static let workspaceEditTransactionRedoCommandRequirements: Self = [
        .multiDocumentWorkspaceEditTransaction,
        .multiDocumentWorkspaceEditTransactionRedo,
    ]

    static let workspaceEditTransactionHistoryCommandRequirements: Self = [
        .multiDocumentWorkspaceEditTransaction,
        .multiDocumentWorkspaceEditTransactionEvents,
    ]
}
