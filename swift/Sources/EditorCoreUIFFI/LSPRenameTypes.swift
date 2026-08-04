import Foundation

public enum EcuLspPrepareRenameResultShape: String, Equatable, Sendable {
    case none
    case range
    case rangePlaceholder = "range_placeholder"
    case defaultBehavior = "default_behavior"
    case unknown
}

public struct EcuLspPrepareRenameResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspPrepareRenameResultShape
    public var range: EcuLspRange?
    public var placeholder: String?
    public var defaultBehavior: Bool?
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            range = nil
            placeholder = nil
            defaultBehavior = nil
            return
        }

        if let range = try? single.decode(EcuLspRange.self) {
            shape = .range
            self.range = range
            placeholder = nil
            defaultBehavior = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let defaultBehavior = try container.decodeIfPresent(Bool.self, forKey: .defaultBehavior) {
            shape = .defaultBehavior
            range = nil
            placeholder = nil
            self.defaultBehavior = defaultBehavior
            return
        }

        if let range = try container.decodeIfPresent(EcuLspRange.self, forKey: .range) {
            shape = .rangePlaceholder
            self.range = range
            placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
            defaultBehavior = nil
            return
        }

        shape = .unknown
        range = nil
        placeholder = nil
        defaultBehavior = nil
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case placeholder
        case defaultBehavior
    }
}

public struct EcuLspWorkspaceEdit: Equatable, Sendable, Decodable {
    public var changes: [String: [EcuLspTextEdit]]
    public var documentChanges: [EcuLspWorkspaceDocumentChange]
    public var changeAnnotations: [String: EcuJSONValue]
    public var raw: EcuJSONValue?

    public var rawJSONString: String? {
        raw?.jsonString
    }

    public var documentEditCount: Int {
        changes.values.reduce(0) { $0 + $1.count } + documentChanges.reduce(0) { total, change in
            guard case let .textDocumentEdit(edit) = change else { return total }
            return total + edit.edits.count
        }
    }

    public var resourceOperationCount: Int {
        documentChanges.reduce(0) { total, change in
            change.resourceOperation == nil ? total : total + 1
        }
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        changes = try container.decodeIfPresent([String: [EcuLspTextEdit]].self, forKey: .changes) ?? [:]
        documentChanges = try container.decodeIfPresent(
            [EcuLspWorkspaceDocumentChange].self,
            forKey: .documentChanges
        ) ?? []
        changeAnnotations = try container.decodeIfPresent(
            [String: EcuJSONValue].self,
            forKey: .changeAnnotations
        ) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case changes
        case documentChanges
        case changeAnnotations
    }
}

public enum EcuLspWorkspaceDocumentChange: Equatable, Sendable, Decodable {
    case textDocumentEdit(EcuLspTextDocumentEdit)
    case createFile(EcuLspCreateFile)
    case renameFile(EcuLspRenameFile)
    case deleteFile(EcuLspDeleteFile)
    case unknown(EcuJSONValue)

    public var textDocumentEdit: EcuLspTextDocumentEdit? {
        guard case let .textDocumentEdit(edit) = self else { return nil }
        return edit
    }

    public var resourceOperation: EcuLspResourceOperation? {
        switch self {
        case let .createFile(operation):
            return .create(operation)
        case let .renameFile(operation):
            return .rename(operation)
        case let .deleteFile(operation):
            return .delete(operation)
        case .textDocumentEdit, .unknown:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = (try? EcuJSONValue(from: decoder)) ?? .null

        if let edit = try? EcuLspTextDocumentEdit(from: decoder) {
            self = .textDocumentEdit(edit)
            return
        }

        let container = try decoder.container(keyedBy: KindCodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind)
        switch kind {
        case "create":
            self = .createFile(try EcuLspCreateFile(from: decoder))
        case "rename":
            self = .renameFile(try EcuLspRenameFile(from: decoder))
        case "delete":
            self = .deleteFile(try EcuLspDeleteFile(from: decoder))
        default:
            self = .unknown(raw)
        }
    }

    private enum KindCodingKeys: String, CodingKey {
        case kind
    }
}

public struct EcuLspTextDocumentEdit: Equatable, Sendable, Decodable {
    public var textDocument: EcuLspOptionalVersionedTextDocumentIdentifier
    public var edits: [EcuLspTextEdit]
    public var raw: EcuJSONValue?

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textDocument = try container.decode(EcuLspOptionalVersionedTextDocumentIdentifier.self, forKey: .textDocument)
        edits = try container.decodeIfPresent([EcuLspTextEdit].self, forKey: .edits) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case textDocument
        case edits
    }
}

public struct EcuLspOptionalVersionedTextDocumentIdentifier: Equatable, Sendable, Decodable {
    public var uri: String
    public var version: Int?
}

public enum EcuLspResourceOperation: Equatable, Sendable {
    case create(EcuLspCreateFile)
    case rename(EcuLspRenameFile)
    case delete(EcuLspDeleteFile)

    public var affectedURIs: [String] {
        switch self {
        case let .create(operation):
            return [operation.uri]
        case let .rename(operation):
            return [operation.oldUri, operation.newUri]
        case let .delete(operation):
            return [operation.uri]
        }
    }
}

public struct EcuLspCreateFile: Equatable, Sendable, Decodable {
    public var kind: String
    public var uri: String
    public var options: EcuLspCreateFileOptions?
    public var annotationId: String?
}

public struct EcuLspRenameFile: Equatable, Sendable, Decodable {
    public var kind: String
    public var oldUri: String
    public var newUri: String
    public var options: EcuLspRenameFileOptions?
    public var annotationId: String?
}

public struct EcuLspDeleteFile: Equatable, Sendable, Decodable {
    public var kind: String
    public var uri: String
    public var options: EcuLspDeleteFileOptions?
    public var annotationId: String?
}

public struct EcuLspCreateFileOptions: Equatable, Sendable, Decodable {
    public var overwrite: Bool?
    public var ignoreIfExists: Bool?
}

public struct EcuLspRenameFileOptions: Equatable, Sendable, Decodable {
    public var overwrite: Bool?
    public var ignoreIfExists: Bool?
}

public struct EcuLspDeleteFileOptions: Equatable, Sendable, Decodable {
    public var recursive: Bool?
    public var ignoreIfNotExists: Bool?
}

public extension EcuJSONValue {
    var jsonCompatibleObject: Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .number(value):
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map { $0.jsonCompatibleObject }
        case let .object(values):
            return values.mapValues { $0.jsonCompatibleObject }
        }
    }

    var jsonString: String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: jsonCompatibleObject,
            options: [.fragmentsAllowed]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
