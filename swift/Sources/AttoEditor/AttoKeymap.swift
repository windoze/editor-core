import AppKit
import Foundation

struct AttoKeyBinding: Equatable {
    var keyEquivalent: String
    var modifiers: NSEvent.ModifierFlags

    init(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }
}

enum AttoKeymap {
    static let userKeymapEnv = "ATTO_EDITOR_KEYMAP_PATH"

    static let defaultBindings: [String: AttoKeyBinding] = [
        "file.new": AttoKeyBinding(keyEquivalent: "n", modifiers: [.command]),
        "file.open_file": AttoKeyBinding(keyEquivalent: "o", modifiers: [.command]),
        "file.open_folder": AttoKeyBinding(keyEquivalent: "o", modifiers: [.command, .shift]),
        "file.save": AttoKeyBinding(keyEquivalent: "s", modifiers: [.command]),
        "file.close_tab": AttoKeyBinding(keyEquivalent: "w", modifiers: [.command]),
        "editor.find": AttoKeyBinding(keyEquivalent: "f", modifiers: [.command]),
        "editor.replace": AttoKeyBinding(keyEquivalent: "f", modifiers: [.command, .option]),
        "editor.format_selection": AttoKeyBinding(keyEquivalent: "f", modifiers: [.option, .shift]),
        "editor.duplicate_lines": AttoKeyBinding(keyEquivalent: "d", modifiers: [.command, .shift]),
        "editor.delete_lines": AttoKeyBinding(keyEquivalent: "k", modifiers: [.command, .shift]),
        "editor.join_lines": AttoKeyBinding(keyEquivalent: "j", modifiers: [.command]),
        "editor.toggle_line_comment": AttoKeyBinding(keyEquivalent: "/", modifiers: [.command]),
        "editor.fold_selection": AttoKeyBinding(keyEquivalent: "[", modifiers: [.command, .option]),
        "editor.unfold": AttoKeyBinding(keyEquivalent: "]", modifiers: [.command, .option]),
        "editor.unfold_all": AttoKeyBinding(keyEquivalent: "]", modifiers: [.command, .option, .shift]),
        "view.toggle_sidebar": AttoKeyBinding(keyEquivalent: "b", modifiers: [.command]),
        "view.toggle_minimap": AttoKeyBinding(keyEquivalent: "m", modifiers: [.command]),
        "view.split_right": AttoKeyBinding(keyEquivalent: "2", modifiers: [.command, .option]),
        "view.focus_next_pane": AttoKeyBinding(keyEquivalent: "]", modifiers: [.command, .control]),
        "view.focus_previous_pane": AttoKeyBinding(keyEquivalent: "[", modifiers: [.command, .control]),
        "view.close_pane": AttoKeyBinding(keyEquivalent: "w", modifiers: [.command, .option]),
        "view.wrap.word": AttoKeyBinding(keyEquivalent: "z", modifiers: [.option]),
        "workbench.command_palette": AttoKeyBinding(keyEquivalent: "p", modifiers: [.command, .shift]),
        "go.file": AttoKeyBinding(keyEquivalent: "p", modifiers: [.command]),
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
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: AttoKeyBinding] {
        var out = defaultBindings
        for (command, binding) in loadUserBindings(fileManager: fileManager, env: env) {
            out[command] = binding
        }
        return out
    }

    static func loadUserBindings(
        fileManager: FileManager = .default,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: AttoKeyBinding] {
        let url = userKeymapURL(fileManager: fileManager, env: env)
        guard fileManager.fileExists(atPath: url.path) else { return [:] }

        do {
            let data = try Data(contentsOf: url)
            let root = try JSONDecoder().decode(UserKeymapRoot.self, from: data)
            var out: [String: AttoKeyBinding] = [:]
            for entry in root.entries {
                guard let bindingText = entry.bindingText,
                      let binding = parseBinding(bindingText)
                else { continue }
                out[entry.command] = binding
            }
            return out
        } catch {
            NSLog("AttoEditor: failed to load keymap %@: %@", url.path, String(describing: error))
            return [:]
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
        let parts = raw
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }

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

    private static func functionKey(_ value: Int) -> String {
        guard let scalar = UnicodeScalar(UInt32(value)) else { return "" }
        return String(Character(scalar))
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

    var bindingText: String? {
        if let first = keys?.first { return first }
        return key
    }
}
