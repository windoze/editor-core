public enum EcuLspCompletionResultShape: String, Equatable, Sendable {
    case none
    case itemArray = "item_array"
    case list
}

public struct EcuLspCompletionResult: Equatable, Sendable, Decodable {
    public var shape: EcuLspCompletionResultShape
    public var isIncomplete: Bool
    public var itemDefaults: EcuJSONValue?
    public var items: [EcuLspCompletionItem]

    public var isEmpty: Bool {
        items.isEmpty
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            shape = .none
            isIncomplete = false
            itemDefaults = nil
            items = []
            return
        }

        if let items = try? single.decode([EcuLspCompletionItem].self) {
            shape = .itemArray
            isIncomplete = false
            itemDefaults = nil
            self.items = items
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = .list
        isIncomplete = try container.decodeIfPresent(Bool.self, forKey: .isIncomplete) ?? false
        itemDefaults = try container.decodeIfPresent(EcuJSONValue.self, forKey: .itemDefaults)
        items = try container.decodeIfPresent([EcuLspCompletionItem].self, forKey: .items) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case isIncomplete
        case itemDefaults
        case items
    }
}

public struct EcuLspCompletionItem: Equatable, Sendable, Decodable {
    public var label: String
    public var labelDetails: EcuLspCompletionItemLabelDetails?
    public var kind: Int?
    public var tags: [Int]
    public var detail: String?
    public var documentation: EcuLspDocumentation?
    public var deprecated: Bool?
    public var preselect: Bool?
    public var sortText: String?
    public var filterText: String?
    public var insertText: String?
    public var insertTextFormat: Int?
    public var insertTextMode: Int?
    public var textEdit: EcuLspCompletionTextEdit?
    public var textEditText: String?
    public var additionalTextEdits: [EcuLspTextEdit]
    public var commitCharacters: [String]
    public var command: EcuLspCommand?
    public var data: EcuJSONValue?
    public var raw: EcuJSONValue?

    public var kindKind: EcuLspCompletionItemKind? {
        kind.map(EcuLspCompletionItemKind.init(rawValue:))
    }

    public var tagKinds: [EcuLspCompletionItemTag] {
        tags.map(EcuLspCompletionItemTag.init(rawValue:))
    }

    public var insertTextFormatKind: EcuLspInsertTextFormat? {
        insertTextFormat.map(EcuLspInsertTextFormat.init(rawValue:))
    }

    public var insertTextModeKind: EcuLspInsertTextMode? {
        insertTextMode.map(EcuLspInsertTextMode.init(rawValue:))
    }

    public init(from decoder: Decoder) throws {
        raw = try? EcuJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        labelDetails = try container.decodeIfPresent(EcuLspCompletionItemLabelDetails.self, forKey: .labelDetails)
        kind = try container.decodeIfPresent(Int.self, forKey: .kind)
        tags = try container.decodeIfPresent([Int].self, forKey: .tags) ?? []
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        documentation = try container.decodeIfPresent(EcuLspDocumentation.self, forKey: .documentation)
        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated)
        preselect = try container.decodeIfPresent(Bool.self, forKey: .preselect)
        sortText = try container.decodeIfPresent(String.self, forKey: .sortText)
        filterText = try container.decodeIfPresent(String.self, forKey: .filterText)
        insertText = try container.decodeIfPresent(String.self, forKey: .insertText)
        insertTextFormat = try container.decodeIfPresent(Int.self, forKey: .insertTextFormat)
        insertTextMode = try container.decodeIfPresent(Int.self, forKey: .insertTextMode)
        textEdit = try container.decodeIfPresent(EcuLspCompletionTextEdit.self, forKey: .textEdit)
        textEditText = try container.decodeIfPresent(String.self, forKey: .textEditText)
        additionalTextEdits = try container.decodeIfPresent([EcuLspTextEdit].self, forKey: .additionalTextEdits) ?? []
        commitCharacters = try container.decodeIfPresent([String].self, forKey: .commitCharacters) ?? []
        command = try container.decodeIfPresent(EcuLspCommand.self, forKey: .command)
        data = try container.decodeIfPresent(EcuJSONValue.self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case labelDetails
        case kind
        case tags
        case detail
        case documentation
        case deprecated
        case preselect
        case sortText
        case filterText
        case insertText
        case insertTextFormat
        case insertTextMode
        case textEdit
        case textEditText
        case additionalTextEdits
        case commitCharacters
        case command
        case data
    }
}

public struct EcuLspCompletionItemLabelDetails: Equatable, Sendable, Decodable {
    public var detail: String?
    public var description: String?
}

public enum EcuLspCompletionItemKind: Equatable, Sendable {
    case text
    case method
    case function
    case constructor
    case field
    case variable
    case `class`
    case interface
    case module
    case property
    case unit
    case value
    case `enum`
    case keyword
    case snippet
    case color
    case file
    case reference
    case folder
    case enumMember
    case constant
    case `struct`
    case event
    case `operator`
    case typeParameter
    case unknown(Int)

    public init(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .text
        case 2:
            self = .method
        case 3:
            self = .function
        case 4:
            self = .constructor
        case 5:
            self = .field
        case 6:
            self = .variable
        case 7:
            self = .class
        case 8:
            self = .interface
        case 9:
            self = .module
        case 10:
            self = .property
        case 11:
            self = .unit
        case 12:
            self = .value
        case 13:
            self = .enum
        case 14:
            self = .keyword
        case 15:
            self = .snippet
        case 16:
            self = .color
        case 17:
            self = .file
        case 18:
            self = .reference
        case 19:
            self = .folder
        case 20:
            self = .enumMember
        case 21:
            self = .constant
        case 22:
            self = .struct
        case 23:
            self = .event
        case 24:
            self = .operator
        case 25:
            self = .typeParameter
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .text:
            return 1
        case .method:
            return 2
        case .function:
            return 3
        case .constructor:
            return 4
        case .field:
            return 5
        case .variable:
            return 6
        case .class:
            return 7
        case .interface:
            return 8
        case .module:
            return 9
        case .property:
            return 10
        case .unit:
            return 11
        case .value:
            return 12
        case .enum:
            return 13
        case .keyword:
            return 14
        case .snippet:
            return 15
        case .color:
            return 16
        case .file:
            return 17
        case .reference:
            return 18
        case .folder:
            return 19
        case .enumMember:
            return 20
        case .constant:
            return 21
        case .struct:
            return 22
        case .event:
            return 23
        case .operator:
            return 24
        case .typeParameter:
            return 25
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspCompletionItemTag: Equatable, Sendable {
    case deprecated
    case unknown(Int)

    public init(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .deprecated
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .deprecated:
            return 1
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspInsertTextFormat: Equatable, Sendable {
    case plainText
    case snippet
    case unknown(Int)

    public init(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .plainText
        case 2:
            self = .snippet
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .plainText:
            return 1
        case .snippet:
            return 2
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspInsertTextMode: Equatable, Sendable {
    case asIs
    case adjustIndentation
    case unknown(Int)

    public init(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .asIs
        case 2:
            self = .adjustIndentation
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .asIs:
            return 1
        case .adjustIndentation:
            return 2
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public enum EcuLspDocumentation: Equatable, Sendable, Decodable {
    case plain(String)
    case markup(kind: String, value: String)
    case unknown(EcuJSONValue)

    public var text: String? {
        switch self {
        case let .plain(value):
            return value
        case let .markup(_, value):
            return value
        case .unknown:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            self = .plain(value)
            return
        }

        if let markup = try? single.decode(EcuLspMarkupContent.self) {
            self = .markup(kind: markup.kind, value: markup.value)
            return
        }

        self = .unknown(try EcuJSONValue(from: decoder))
    }
}

public struct EcuLspMarkupContent: Equatable, Sendable, Decodable {
    public var kind: String
    public var value: String
}

public struct EcuLspPosition: Equatable, Sendable, Decodable {
    public var line: UInt32
    public var utf16Character: UInt32

    private enum CodingKeys: String, CodingKey {
        case line
        case utf16Character = "character"
    }
}

public struct EcuLspRange: Equatable, Sendable, Decodable {
    public var start: EcuLspPosition
    public var end: EcuLspPosition
}

public struct EcuLspTextEdit: Equatable, Sendable, Decodable {
    public var range: EcuLspRange
    public var newText: String
}

public struct EcuLspInsertReplaceEdit: Equatable, Sendable, Decodable {
    public var newText: String
    public var insert: EcuLspRange
    public var replace: EcuLspRange
}

public enum EcuLspCompletionTextEdit: Equatable, Sendable, Decodable {
    case textEdit(EcuLspTextEdit)
    case insertReplace(EcuLspInsertReplaceEdit)
    case unknown(EcuJSONValue)

    public var newText: String? {
        switch self {
        case let .textEdit(edit):
            return edit.newText
        case let .insertReplace(edit):
            return edit.newText
        case .unknown:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let edit = try? single.decode(EcuLspTextEdit.self) {
            self = .textEdit(edit)
            return
        }
        if let edit = try? single.decode(EcuLspInsertReplaceEdit.self) {
            self = .insertReplace(edit)
            return
        }
        self = .unknown(try EcuJSONValue(from: decoder))
    }
}

public struct EcuLspCommand: Equatable, Sendable, Decodable {
    public var title: String
    public var command: String
    public var arguments: [EcuJSONValue]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decodeIfPresent([EcuJSONValue].self, forKey: .arguments) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case command
        case arguments
    }
}
