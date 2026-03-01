import Foundation

public enum EditorWrapMode: String, Equatable, Hashable, Sendable {
    case none
    case char
    case word
}

public enum EditorWrapIndent: Equatable, Hashable, Sendable {
    case none
    case sameAsLineIndent
    case fixedCells(Int)
}

public enum EditorTabKeyBehavior: String, Equatable, Hashable, Sendable {
    case tab
    case spaces
}

public struct EditorSearchOptions: Equatable, Hashable, Sendable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var regex: Bool

    public init(caseSensitive: Bool = true, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.regex = regex
    }
}

public struct EditorTextEditSpec: Equatable, Hashable, Sendable {
    public var startOffset: Int
    public var endOffset: Int
    public var replacementText: String

    public init(startOffset: Int, endOffset: Int, replacementText: String) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.replacementText = replacementText
    }
}

public enum EditorCommand: Equatable, Sendable {
    case insertText(String)
    case insertTab
    case insertNewline(autoIndent: Bool)
    case backspace
    case deleteForward
    case undo
    case redo

    case moveTo(EditorPosition)
    case moveBy(deltaLine: Int, deltaColumn: Int)
    case moveWordLeft
    case moveWordRight
    case setSelection(EditorSelection)
    case clearSelection

    case setViewportWidth(Int)
    case setWrapMode(EditorWrapMode)
    case setWrapIndent(EditorWrapIndent)
    case setTabWidth(Int)
    case setTabKeyBehavior(EditorTabKeyBehavior)

    case fold(startLine: Int, endLine: Int)
    case unfold(startLine: Int)
    case unfoldAll

    case replaceCurrent(query: String, replacement: String, options: EditorSearchOptions)
    case replaceAll(query: String, replacement: String, options: EditorSearchOptions)
    case applyTextEdits([EditorTextEditSpec])
}

public enum EditorCommandResult: Equatable, Sendable {
    case success
    case text(String)
    case position(EditorPosition)
    case offset(Int)
    case searchMatch(startOffset: Int, endOffset: Int)
    case searchNotFound
    case replaceResult(count: Int)
}

public struct EditorCommandError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}
