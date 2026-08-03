import AppKit
import Foundation

struct AttoKeyBinding: Equatable {
    var keyEquivalent: String
    var modifiers: NSEvent.ModifierFlags

    init(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    var displayText: String {
        var parts: [String] = []
        if modifiers.contains(.control) {
            parts.append("ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("option")
        }
        if modifiers.contains(.shift) {
            parts.append("shift")
        }
        if modifiers.contains(.command) {
            parts.append("cmd")
        }
        parts.append(AttoKeymap.displayText(forKeyEquivalent: keyEquivalent))
        return parts.joined(separator: "+")
    }
}

struct AttoKeySequence: Equatable {
    var bindings: [AttoKeyBinding]

    var isChord: Bool {
        bindings.count > 1
    }
}

enum AttoKeymapContextValue: Equatable {
    case bool(Bool)
    case string(String)
    case number(Double)
    case list([AttoKeymapContextValue])

    var stringValue: String? {
        switch self {
        case .bool(let value):
            return value ? "true" : "false"
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .list:
            return nil
        }
    }
}

struct AttoKeymapContext: Equatable {
    var values: [String: AttoKeymapContextValue]

    init(values: [String: AttoKeymapContextValue] = [:]) {
        self.values = values
    }
}

struct AttoKeymapConflict: Equatable {
    let binding: AttoKeyBinding
    let keptCommand: String
    let shadowedCommand: String
}

struct AttoKeymapSequenceConflict: Equatable {
    let sequence: AttoKeySequence
    let keptCommand: String
    let shadowedCommand: String
}

struct AttoKeymapResolution: Equatable {
    let bindings: [String: AttoKeyBinding]
    let sequences: [String: AttoKeySequence]
    let arguments: [String: AttoCommandArguments]
    let conflicts: [AttoKeymapConflict]
    let sequenceConflicts: [AttoKeymapSequenceConflict]
}

enum AttoKeymap {
    static let userKeymapEnv = "ATTO_EDITOR_KEYMAP_PATH"

    static let defaultBindings: [String: AttoKeyBinding] = [
        "file.new": AttoKeyBinding(keyEquivalent: "n", modifiers: [.command]),
        "file.open_file": AttoKeyBinding(keyEquivalent: "o", modifiers: [.command]),
        "file.open_folder": AttoKeyBinding(keyEquivalent: "o", modifiers: [.command, .shift]),
        "file.save": AttoKeyBinding(keyEquivalent: "s", modifiers: [.command]),
        "file.close_tab": AttoKeyBinding(keyEquivalent: "w", modifiers: [.command]),
        "file.move_tab_left": AttoKeyBinding(keyEquivalent: "[", modifiers: [.command, .shift]),
        "file.move_tab_right": AttoKeyBinding(keyEquivalent: "]", modifiers: [.command, .shift]),
        "editor.find": AttoKeyBinding(keyEquivalent: "f", modifiers: [.command]),
        "editor.replace": AttoKeyBinding(keyEquivalent: "f", modifiers: [.command, .option]),
        "workspace.undo_last_workspace_edit": AttoKeyBinding(keyEquivalent: "z", modifiers: [.command, .option]),
        "workspace.redo_last_workspace_edit": AttoKeyBinding(keyEquivalent: "z", modifiers: [.command, .option, .shift]),
        "editor.format_selection": AttoKeyBinding(keyEquivalent: "f", modifiers: [.option, .shift]),
        "editor.duplicate_lines": AttoKeyBinding(keyEquivalent: "d", modifiers: [.command, .shift]),
        "editor.delete_lines": AttoKeyBinding(keyEquivalent: "k", modifiers: [.command, .shift]),
        "editor.move_lines_up": AttoKeyBinding(keyEquivalent: functionKey(NSUpArrowFunctionKey), modifiers: [.command, .control]),
        "editor.move_lines_down": AttoKeyBinding(keyEquivalent: functionKey(NSDownArrowFunctionKey), modifiers: [.command, .control]),
        "editor.join_lines": AttoKeyBinding(keyEquivalent: "j", modifiers: [.command]),
        "editor.select_line": AttoKeyBinding(keyEquivalent: "l", modifiers: [.command]),
        "editor.add_next_occurrence": AttoKeyBinding(keyEquivalent: "d", modifiers: [.command]),
        "editor.add_all_occurrences": AttoKeyBinding(keyEquivalent: "g", modifiers: [.command, .control]),
        "editor.toggle_line_comment": AttoKeyBinding(keyEquivalent: "/", modifiers: [.command]),
        "editor.fold_selection": AttoKeyBinding(keyEquivalent: "[", modifiers: [.command, .option]),
        "editor.unfold": AttoKeyBinding(keyEquivalent: "]", modifiers: [.command, .option]),
        "editor.unfold_all": AttoKeyBinding(keyEquivalent: "]", modifiers: [.command, .option, .shift]),
        "view.toggle_sidebar": AttoKeyBinding(keyEquivalent: "b", modifiers: [.command]),
        "view.toggle_minimap": AttoKeyBinding(keyEquivalent: "m", modifiers: [.command]),
        "view.split_right": AttoKeyBinding(keyEquivalent: "2", modifiers: [.command, .option]),
        "view.focus_next_pane": AttoKeyBinding(keyEquivalent: "]", modifiers: [.command, .control]),
        "view.focus_previous_pane": AttoKeyBinding(keyEquivalent: "[", modifiers: [.command, .control]),
        "view.move_pane_left": AttoKeyBinding(keyEquivalent: functionKey(NSLeftArrowFunctionKey), modifiers: [.command, .option, .control]),
        "view.move_pane_right": AttoKeyBinding(keyEquivalent: functionKey(NSRightArrowFunctionKey), modifiers: [.command, .option, .control]),
        "view.close_pane": AttoKeyBinding(keyEquivalent: "w", modifiers: [.command, .option]),
        "view.wrap.word": AttoKeyBinding(keyEquivalent: "z", modifiers: [.option]),
        "workbench.command_palette": AttoKeyBinding(keyEquivalent: "p", modifiers: [.command, .shift]),
        "macro.toggle_recording": AttoKeyBinding(keyEquivalent: "q", modifiers: [.control]),
        "macro.replay_last": AttoKeyBinding(keyEquivalent: "q", modifiers: [.control, .shift]),
        "go.file": AttoKeyBinding(keyEquivalent: "p", modifiers: [.command]),
        "go.line": AttoKeyBinding(keyEquivalent: "g", modifiers: [.control]),
        "lsp.document_symbols": AttoKeyBinding(keyEquivalent: "r", modifiers: [.command]),
        "lsp.workspace_symbols": AttoKeyBinding(keyEquivalent: "r", modifiers: [.command, .shift]),
        "lsp.completion": AttoKeyBinding(keyEquivalent: " ", modifiers: [.control]),
        "lsp.signature_help": AttoKeyBinding(keyEquivalent: " ", modifiers: [.control, .shift]),
        "lsp.rename": AttoKeyBinding(keyEquivalent: functionKey(NSF2FunctionKey), modifiers: []),
        "lsp.code_actions": AttoKeyBinding(keyEquivalent: ".", modifiers: [.command]),
        "go.matching_bracket": AttoKeyBinding(keyEquivalent: "m", modifiers: [.control]),
        "search.find_in_files": AttoKeyBinding(keyEquivalent: "f", modifiers: [.command, .shift]),
        "workbench.preferences": AttoKeyBinding(keyEquivalent: ",", modifiers: [.command]),
    ]

    static func resolvedBindings(
        fileManager: FileManager = .default,
        env: [String: String] = ProcessInfo.processInfo.environment,
        context: AttoKeymapContext = AttoKeymapContext()
    ) -> [String: AttoKeyBinding] {
        resolvedKeymap(fileManager: fileManager, env: env, context: context).bindings
    }

    static func resolvedKeymap(
        fileManager: FileManager = .default,
        env: [String: String] = ProcessInfo.processInfo.environment,
        context: AttoKeymapContext = AttoKeymapContext()
    ) -> AttoKeymapResolution {
        var resolver = BindingResolver()
        for command in defaultBindings.keys.sorted() {
            guard let binding = defaultBindings[command] else { continue }
            resolver.apply(command: command, binding: binding)
        }
        for entry in loadUserEntries(fileManager: fileManager, env: env, context: context) {
            guard let sequence = parseSequence(entry.bindingSequenceTexts)
            else { continue }
            resolver.apply(command: entry.command, sequence: sequence, arguments: entry.args)
        }
        return resolver.resolution()
    }

    static func loadUserBindings(
        fileManager: FileManager = .default,
        env: [String: String] = ProcessInfo.processInfo.environment,
        context: AttoKeymapContext = AttoKeymapContext()
    ) -> [String: AttoKeyBinding] {
        var resolver = BindingResolver()
        for entry in loadUserEntries(fileManager: fileManager, env: env, context: context) {
            guard let sequence = parseSequence(entry.bindingSequenceTexts), sequence.isChord == false,
                  let binding = sequence.bindings.first
            else { continue }
            resolver.apply(command: entry.command, binding: binding, arguments: entry.args)
        }
        return resolver.resolution().bindings
    }

    private static func loadUserEntries(
        fileManager: FileManager = .default,
        env: [String: String] = ProcessInfo.processInfo.environment,
        context: AttoKeymapContext
    ) -> [UserKeymapEntry] {
        let url = userKeymapURL(fileManager: fileManager, env: env)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let root = try JSONDecoder().decode(UserKeymapRoot.self, from: data)
            return root.entries.filter { $0.applies(to: context) }
        } catch {
            NSLog("AttoEditor: failed to load keymap %@: %@", url.path, String(describing: error))
            return []
        }
    }

    static func userKeymapURL(
        fileManager: FileManager = .default,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let path = env[userKeymapEnv]?.trimmingCharacters(in: .whitespacesAndNewlines),
           path.isEmpty == false
        {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
            .appendingPathComponent("keymap.json", isDirectory: false)
    }

    static func parseBinding(_ raw: String) -> AttoKeyBinding? {
        let normalizedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesLiteralPlusKey = normalizedRaw.hasSuffix("+")
        var parts = normalizedRaw
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
        if usesLiteralPlusKey {
            parts.append("plus")
        }

        guard parts.isEmpty == false else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var key: String?

        for part in parts {
            switch part {
            case "cmd", "command", "super", "meta":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            case "option", "opt", "alt":
                modifiers.insert(.option)
            case "control", "ctrl":
                modifiers.insert(.control)
            default:
                guard key == nil else { return nil }
                key = keyEquivalent(for: part)
            }
        }

        guard let key, key.isEmpty == false else { return nil }
        return AttoKeyBinding(keyEquivalent: key, modifiers: modifiers)
    }

    static func parseSequence(_ raw: [String]) -> AttoKeySequence? {
        guard raw.isEmpty == false else { return nil }
        let bindings = raw.compactMap { parseBinding($0) }
        guard bindings.count == raw.count else { return nil }
        return AttoKeySequence(bindings: bindings)
    }

    static func binding(for event: NSEvent) -> AttoKeyBinding? {
        guard event.type == .keyDown else { return nil }
        guard let raw = event.charactersIgnoringModifiers ?? event.characters,
              raw.isEmpty == false
        else { return nil }

        let keyEquivalent: String
        if raw.count == 1, raw.unicodeScalars.first?.value ?? 0 < 0xF700 {
            keyEquivalent = raw.lowercased()
        } else {
            keyEquivalent = raw
        }

        var modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        modifiers.remove(.capsLock)
        return AttoKeyBinding(keyEquivalent: keyEquivalent, modifiers: modifiers)
    }

    private static func keyEquivalent(for token: String) -> String {
        switch token {
        case "space":
            return " "
        case "tab":
            return "\t"
        case "enter", "return":
            return "\r"
        case "escape", "esc":
            return "\u{1b}"
        case "backspace":
            return "\u{7f}"
        case "delete", "del", "forwarddelete", "forward_delete", "forward-delete":
            return functionKey(NSDeleteFunctionKey)
        case "insert", "ins":
            return functionKey(NSInsertFunctionKey)
        case "begin":
            return functionKey(NSBeginFunctionKey)
        case "clear":
            return functionKey(NSClearLineFunctionKey)
        case "help":
            return functionKey(NSHelpFunctionKey)
        case "plus", "add":
            return "+"
        case "minus", "hyphen":
            return "-"
        case "equal", "equals":
            return "="
        case "comma":
            return ","
        case "period", "dot":
            return "."
        case "slash", "forwardslash", "forward_slash", "forward-slash":
            return "/"
        case "backslash", "back_slash", "back-slash":
            return "\\"
        case "semicolon":
            return ";"
        case "quote", "apostrophe", "singlequote", "single_quote", "single-quote":
            return "'"
        case "doublequote", "double_quote", "double-quote", "quotedbl":
            return "\""
        case "grave", "backquote", "back_quote", "back-quote", "graveaccent", "grave_accent", "grave-accent":
            return "`"
        case "leftbracket", "left_bracket", "left-bracket", "openbracket", "open_bracket", "open-bracket":
            return "["
        case "rightbracket", "right_bracket", "right-bracket", "closebracket", "close_bracket", "close-bracket":
            return "]"
        case "up", "arrowup", "up_arrow", "up-arrow":
            return functionKey(NSUpArrowFunctionKey)
        case "down", "arrowdown", "down_arrow", "down-arrow":
            return functionKey(NSDownArrowFunctionKey)
        case "left", "arrowleft", "left_arrow", "left-arrow":
            return functionKey(NSLeftArrowFunctionKey)
        case "right", "arrowright", "right_arrow", "right-arrow":
            return functionKey(NSRightArrowFunctionKey)
        case "home":
            return functionKey(NSHomeFunctionKey)
        case "end":
            return functionKey(NSEndFunctionKey)
        case "pageup", "page_up", "page-up":
            return functionKey(NSPageUpFunctionKey)
        case "pagedown", "page_down", "page-down":
            return functionKey(NSPageDownFunctionKey)
        case "f1": return functionKey(NSF1FunctionKey)
        case "f2": return functionKey(NSF2FunctionKey)
        case "f3": return functionKey(NSF3FunctionKey)
        case "f4": return functionKey(NSF4FunctionKey)
        case "f5": return functionKey(NSF5FunctionKey)
        case "f6": return functionKey(NSF6FunctionKey)
        case "f7": return functionKey(NSF7FunctionKey)
        case "f8": return functionKey(NSF8FunctionKey)
        case "f9": return functionKey(NSF9FunctionKey)
        case "f10": return functionKey(NSF10FunctionKey)
        case "f11": return functionKey(NSF11FunctionKey)
        case "f12": return functionKey(NSF12FunctionKey)
        case "f13": return functionKey(NSF13FunctionKey)
        case "f14": return functionKey(NSF14FunctionKey)
        case "f15": return functionKey(NSF15FunctionKey)
        case "f16": return functionKey(NSF16FunctionKey)
        case "f17": return functionKey(NSF17FunctionKey)
        case "f18": return functionKey(NSF18FunctionKey)
        case "f19": return functionKey(NSF19FunctionKey)
        case "f20": return functionKey(NSF20FunctionKey)
        default:
            return token
        }
    }

    static func displayText(forKeyEquivalent keyEquivalent: String) -> String {
        switch keyEquivalent {
        case " ":
            return "space"
        case "\t":
            return "tab"
        case "\r":
            return "enter"
        case "\u{1b}":
            return "escape"
        case "\u{7f}":
            return "backspace"
        case functionKey(NSDeleteFunctionKey):
            return "delete"
        case functionKey(NSInsertFunctionKey):
            return "insert"
        case functionKey(NSBeginFunctionKey):
            return "begin"
        case functionKey(NSClearLineFunctionKey):
            return "clear"
        case functionKey(NSHelpFunctionKey):
            return "help"
        case functionKey(NSUpArrowFunctionKey):
            return "up"
        case functionKey(NSDownArrowFunctionKey):
            return "down"
        case functionKey(NSLeftArrowFunctionKey):
            return "left"
        case functionKey(NSRightArrowFunctionKey):
            return "right"
        case functionKey(NSHomeFunctionKey):
            return "home"
        case functionKey(NSEndFunctionKey):
            return "end"
        case functionKey(NSPageUpFunctionKey):
            return "pageup"
        case functionKey(NSPageDownFunctionKey):
            return "pagedown"
        case functionKey(NSF1FunctionKey):
            return "f1"
        case functionKey(NSF2FunctionKey):
            return "f2"
        case functionKey(NSF3FunctionKey):
            return "f3"
        case functionKey(NSF4FunctionKey):
            return "f4"
        case functionKey(NSF5FunctionKey):
            return "f5"
        case functionKey(NSF6FunctionKey):
            return "f6"
        case functionKey(NSF7FunctionKey):
            return "f7"
        case functionKey(NSF8FunctionKey):
            return "f8"
        case functionKey(NSF9FunctionKey):
            return "f9"
        case functionKey(NSF10FunctionKey):
            return "f10"
        case functionKey(NSF11FunctionKey):
            return "f11"
        case functionKey(NSF12FunctionKey):
            return "f12"
        case functionKey(NSF13FunctionKey):
            return "f13"
        case functionKey(NSF14FunctionKey):
            return "f14"
        case functionKey(NSF15FunctionKey):
            return "f15"
        case functionKey(NSF16FunctionKey):
            return "f16"
        case functionKey(NSF17FunctionKey):
            return "f17"
        case functionKey(NSF18FunctionKey):
            return "f18"
        case functionKey(NSF19FunctionKey):
            return "f19"
        case functionKey(NSF20FunctionKey):
            return "f20"
        default:
            return keyEquivalent
        }
    }

    private static func functionKey(_ value: Int) -> String {
        guard let scalar = UnicodeScalar(UInt32(value)) else { return "" }
        return String(Character(scalar))
    }

    private struct BindingKey: Hashable {
        let keyEquivalent: String
        let modifiersRawValue: UInt

        init(_ binding: AttoKeyBinding) {
            self.keyEquivalent = binding.keyEquivalent
            self.modifiersRawValue = binding.modifiers.rawValue
        }
    }

    private struct SequenceKey: Hashable {
        let bindings: [BindingKey]

        init(_ sequence: AttoKeySequence) {
            self.bindings = sequence.bindings.map(BindingKey.init)
        }
    }

    private struct BindingResolver {
        private var bindings: [String: AttoKeyBinding] = [:]
        private var sequences: [String: AttoKeySequence] = [:]
        private var arguments: [String: AttoCommandArguments] = [:]
        private var ownersByBinding: [BindingKey: String] = [:]
        private var ownersBySequence: [SequenceKey: String] = [:]
        private var conflicts: [AttoKeymapConflict] = []
        private var sequenceConflicts: [AttoKeymapSequenceConflict] = []

        mutating func apply(command: String, binding: AttoKeyBinding, arguments newArguments: AttoCommandArguments? = nil) {
            let bindingKey = BindingKey(binding)

            removeExistingBinding(for: command)
            removeExistingSequence(for: command)

            if let shadowed = ownersByBinding[bindingKey], shadowed != command {
                bindings.removeValue(forKey: shadowed)
                arguments.removeValue(forKey: shadowed)
                conflicts.append(AttoKeymapConflict(
                    binding: binding,
                    keptCommand: command,
                    shadowedCommand: shadowed
                ))
            }

            bindings[command] = binding
            if let newArguments {
                arguments[command] = newArguments
            } else {
                arguments.removeValue(forKey: command)
            }
            ownersByBinding[bindingKey] = command
        }

        mutating func apply(command: String, sequence: AttoKeySequence, arguments newArguments: AttoCommandArguments? = nil) {
            if sequence.isChord == false, let binding = sequence.bindings.first {
                apply(command: command, binding: binding, arguments: newArguments)
                return
            }

            let sequenceKey = SequenceKey(sequence)
            removeExistingBinding(for: command)
            removeExistingSequence(for: command)

            if let shadowed = ownersBySequence[sequenceKey], shadowed != command {
                sequences.removeValue(forKey: shadowed)
                arguments.removeValue(forKey: shadowed)
                sequenceConflicts.append(AttoKeymapSequenceConflict(
                    sequence: sequence,
                    keptCommand: command,
                    shadowedCommand: shadowed
                ))
            }

            sequences[command] = sequence
            if let newArguments {
                arguments[command] = newArguments
            } else {
                arguments.removeValue(forKey: command)
            }
            ownersBySequence[sequenceKey] = command
        }

        private mutating func removeExistingBinding(for command: String) {
            if let oldBinding = bindings.removeValue(forKey: command) {
                let oldKey = BindingKey(oldBinding)
                if ownersByBinding[oldKey] == command {
                    ownersByBinding.removeValue(forKey: oldKey)
                }
            }
        }

        private mutating func removeExistingSequence(for command: String) {
            if let oldSequence = sequences.removeValue(forKey: command) {
                let oldKey = SequenceKey(oldSequence)
                if ownersBySequence[oldKey] == command {
                    ownersBySequence.removeValue(forKey: oldKey)
                }
            }
        }

        func resolution() -> AttoKeymapResolution {
            AttoKeymapResolution(
                bindings: bindings,
                sequences: sequences,
                arguments: arguments,
                conflicts: conflicts,
                sequenceConflicts: sequenceConflicts
            )
        }
    }
}

private struct UserKeymapRoot: Decodable {
    var entries: [UserKeymapEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let entries = try? container.decode([UserKeymapEntry].self) {
            self.entries = entries
            return
        }
        if let wrapped = try? container.decode(WrappedUserKeymap.self) {
            self.entries = wrapped.bindings
            return
        }
        self.entries = []
    }
}

private struct WrappedUserKeymap: Decodable {
    var bindings: [UserKeymapEntry]
}

private struct UserKeymapEntry: Decodable {
    var keys: [String]?
    var key: String?
    var command: String
    var args: AttoCommandArguments?
    var context: [AttoKeymapCondition]?

    var bindingText: String? {
        if let first = keys?.first { return first }
        return key
    }

    var bindingSequenceTexts: [String] {
        if let keys, keys.isEmpty == false { return keys }
        if let key { return [key] }
        return []
    }

    func applies(to keymapContext: AttoKeymapContext) -> Bool {
        guard let context, context.isEmpty == false else { return true }
        return context.allSatisfy { $0.matches(keymapContext) }
    }
}

private struct AttoKeymapCondition: Decodable, Equatable {
    enum Operator: Equatable {
        case equal
        case notEqual
        case regexMatch
        case notRegexMatch
        case regexContains
        case notRegexContains
        case unknown(String)

        init(rawValue: String?) {
            switch rawValue?.lowercased() {
            case nil, "", "equal":
                self = .equal
            case "not_equal":
                self = .notEqual
            case "regex_match":
                self = .regexMatch
            case "not_regex_match":
                self = .notRegexMatch
            case "regex_contains":
                self = .regexContains
            case "not_regex_contains":
                self = .notRegexContains
            case .some(let raw):
                self = .unknown(raw)
            }
        }
    }

    var key: String
    var op: Operator
    var operand: AttoKeymapContextValue
    var matchAll: Bool

    private enum CodingKeys: String, CodingKey {
        case key
        case op = "operator"
        case operand
        case matchAll = "match_all"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.op = Operator(rawValue: try container.decodeIfPresent(String.self, forKey: .op))
        self.operand = (try? container.decode(AttoKeymapContextValue.self, forKey: .operand)) ?? .bool(true)
        self.matchAll = (try? container.decode(Bool.self, forKey: .matchAll)) ?? false
    }

    func matches(_ context: AttoKeymapContext) -> Bool {
        guard let actual = context.values[key] else { return false }
        if case .list(let values) = actual {
            guard values.isEmpty == false else { return false }
            if matchAll {
                return values.allSatisfy { matchesSingleValue($0) }
            }
            return values.contains { matchesSingleValue($0) }
        }
        return matchesSingleValue(actual)
    }

    private func matchesSingleValue(_ actual: AttoKeymapContextValue) -> Bool {
        switch op {
        case .equal:
            return actual == operand
        case .notEqual:
            return actual != operand
        case .regexMatch:
            return regexMatches(actual: actual, operand: operand, mode: .full)
        case .notRegexMatch:
            return regexMatches(actual: actual, operand: operand, mode: .full) == false
        case .regexContains:
            return regexMatches(actual: actual, operand: operand, mode: .contains)
        case .notRegexContains:
            return regexMatches(actual: actual, operand: operand, mode: .contains) == false
        case .unknown:
            return false
        }
    }

    private enum RegexMatchMode {
        case full
        case contains
    }

    private func regexMatches(
        actual: AttoKeymapContextValue,
        operand: AttoKeymapContextValue,
        mode: RegexMatchMode
    ) -> Bool {
        guard let actualString = actual.stringValue,
              let pattern = operand.stringValue,
              let regex = try? NSRegularExpression(pattern: pattern, options: [])
        else { return false }
        let range = NSRange(actualString.startIndex..<actualString.endIndex, in: actualString)
        guard let match = regex.firstMatch(in: actualString, options: [], range: range) else {
            return false
        }
        switch mode {
        case .full:
            return match.range.location == range.location && match.range.length == range.length
        case .contains:
            return true
        }
    }
}

extension AttoKeymapContextValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
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
        if let value = try? container.decode([AttoKeymapContextValue].self) {
            self = .list(value)
            return
        }
        throw DecodingError.typeMismatch(
            AttoKeymapContextValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "unsupported keymap context value")
        )
    }
}
