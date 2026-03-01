import Foundation

public struct EditorModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}

public struct EditorKeyChord: Hashable, Sendable {
    public var key: String
    public var modifiers: EditorModifierFlags

    public init(key: String, modifiers: EditorModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public final class EditorKeybindingRegistry: @unchecked Sendable {
    private var bindings: [EditorKeyChord: EditorCommand]

    public init(bindings: [EditorKeyChord: EditorCommand] = EditorKeybindingRegistry.defaultBindings()) {
        self.bindings = bindings
    }

    public func bind(_ chord: EditorKeyChord, command: EditorCommand) {
        bindings[chord] = command
    }

    public func unbind(_ chord: EditorKeyChord) {
        bindings.removeValue(forKey: chord)
    }

    public func resolve(_ chord: EditorKeyChord) -> EditorCommand? {
        bindings[chord]
    }

    public static func defaultBindings() -> [EditorKeyChord: EditorCommand] {
        [
            EditorKeyChord(key: "z", modifiers: [.command]): .undo,
            EditorKeyChord(key: "z", modifiers: [.command, .shift]): .redo,
            EditorKeyChord(key: "\u{8}", modifiers: []): .backspace,
            EditorKeyChord(key: "\u{7F}", modifiers: []): .deleteForward,
            EditorKeyChord(key: "\t", modifiers: []): .insertTab,
            EditorKeyChord(key: "\r", modifiers: []): .insertNewline(autoIndent: true)
        ]
    }
}
