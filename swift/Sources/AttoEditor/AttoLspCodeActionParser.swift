import EditorCoreUIFFI
import Foundation

enum AttoLspCodeActionParser {
    struct Command {
        let title: String
        let command: String
        let arguments: [Any]
        fileprivate let object: [String: Any]
        fileprivate let rawJSONString: String?
    }

    struct Item {
        let title: String
        let kind: String?
        let isPreferred: Bool
        let disabledReason: String?
        let edit: [String: Any]?
        let workspaceEdit: EcuLspWorkspaceEdit?
        let command: Command?
        let isLegacyCommand: Bool
        fileprivate let object: [String: Any]
        fileprivate let rawJSONString: String?
    }

    static func items(fromCodeActionResultJSON json: String) -> [Item] {
        if let data = json.data(using: .utf8),
           let result = try? JSONDecoder().decode(EcuLspCodeActionResult.self, from: data)
        {
            return items(fromCodeActionResult: result)
        }

        guard let data = json.data(using: .utf8) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return [] }
        guard let arr = root as? [Any] else { return [] }
        return arr.compactMap { any in
            guard let dict = any as? [String: Any] else { return nil }
            return item(from: dict)
        }
    }

    static func items(fromCodeActionResult result: EcuLspCodeActionResult) -> [Item] {
        result.items.compactMap(item(fromCodeActionElement:))
    }

    static func item(fromCodeActionJSON json: String) -> Item? {
        if let data = json.data(using: .utf8),
           let action = try? JSONDecoder().decode(EcuLspCodeAction.self, from: data)
        {
            return item(fromCodeAction: action)
        }

        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = root as? [String: Any] else { return nil }
        return item(from: dict)
    }

    static func item(fromCodeAction action: EcuLspCodeAction) -> Item? {
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else { return nil }

        let object = action.raw.flatMap(jsonObject) as? [String: Any] ?? [:]
        let editObject = action.edit?.raw.flatMap(jsonObject) as? [String: Any]
        let commandRaw = action.raw.flatMap(commandRawValue)
        let command: Command?
        if let typedCommand = action.command {
            command = self.command(from: typedCommand, raw: commandRaw)
        } else {
            command = nil
        }
        return Item(
            title: action.title,
            kind: action.kind,
            isPreferred: action.isPreferred ?? false,
            disabledReason: action.disabled?.reason,
            edit: editObject,
            workspaceEdit: action.edit,
            command: command,
            isLegacyCommand: false,
            object: object,
            rawJSONString: action.rawJSONString
        )
    }

    static func displayTitle(for item: Item) -> String {
        var suffix: [String] = []
        if let kind = item.kind, kind.isEmpty == false {
            suffix.append(kind)
        } else if item.isLegacyCommand {
            suffix.append("command")
        }
        if item.isPreferred {
            suffix.append("preferred")
        }
        if let reason = item.disabledReason, reason.isEmpty == false {
            suffix.append("disabled: \(reason)")
        }
        if suffix.isEmpty {
            return item.title
        }
        return "\(item.title)  [\(suffix.joined(separator: ", "))]"
    }

    static func filteredItems(_ items: [Item], onlyKinds: [String]) -> [Item] {
        let filters = onlyKinds.filter { $0.isEmpty == false }
        guard filters.isEmpty == false else { return items }
        return items.filter { item in
            guard let kind = item.kind, kind.isEmpty == false else { return false }
            return filters.contains { filter in
                kind == filter || kind.hasPrefix(filter + ".")
            }
        }
    }

    static func rawJSON(for item: Item) -> String? {
        if let rawJSONString = item.rawJSONString {
            return rawJSONString
        }
        return jsonString(item.object)
    }

    static func workspaceEdit(for item: Item) -> EcuLspWorkspaceEdit? {
        item.workspaceEdit
    }

    static func editJSON(for item: Item) -> String? {
        if let rawJSONString = item.workspaceEdit?.rawJSONString {
            return rawJSONString
        }
        guard let edit = item.edit else { return nil }
        return jsonString(edit)
    }

    static func commandJSON(for command: Command) -> String? {
        if let rawJSONString = command.rawJSONString {
            return rawJSONString
        }
        return jsonString(command.object)
    }

    private static func item(fromCodeActionElement element: EcuLspCodeActionElement) -> Item? {
        switch element {
        case .codeAction(let action):
            return item(fromCodeAction: action)
        case .command(let command):
            return item(fromCommand: command)
        case .unknown:
            return nil
        }
    }

    private static func item(fromCommand command: EcuLspCommand) -> Item? {
        guard let parsedCommand = self.command(from: command, raw: nil) else { return nil }
        return Item(
            title: parsedCommand.title,
            kind: nil,
            isPreferred: false,
            disabledReason: nil,
            edit: nil,
            workspaceEdit: nil,
            command: parsedCommand,
            isLegacyCommand: true,
            object: parsedCommand.object,
            rawJSONString: parsedCommand.rawJSONString
        )
    }

    private static func item(from dict: [String: Any]) -> Item? {
        guard let title = dict["title"] as? String, title.isEmpty == false else { return nil }

        let hasCodeActionFields = dict["edit"] != nil
            || dict["kind"] != nil
            || dict["diagnostics"] != nil
            || dict["data"] != nil
            || dict["disabled"] != nil
            || dict["isPreferred"] != nil

        if hasCodeActionFields {
            let command = (dict["command"] as? [String: Any]).flatMap(command(from:))
            let disabled = dict["disabled"] as? [String: Any]
            return Item(
                title: title,
                kind: dict["kind"] as? String,
                isPreferred: boolValue(dict["isPreferred"]),
                disabledReason: disabled?["reason"] as? String,
                edit: dict["edit"] as? [String: Any],
                workspaceEdit: nil,
                command: command,
                isLegacyCommand: false,
                object: dict,
                rawJSONString: nil
            )
        }

        guard let command = command(from: dict) else { return nil }
        return Item(
            title: command.title,
            kind: nil,
            isPreferred: false,
            disabledReason: nil,
            edit: nil,
            workspaceEdit: nil,
            command: command,
            isLegacyCommand: true,
            object: dict,
            rawJSONString: nil
        )
    }

    private static func command(from dict: [String: Any]) -> Command? {
        guard let title = dict["title"] as? String, title.isEmpty == false else { return nil }
        guard let command = dict["command"] as? String, command.isEmpty == false else { return nil }
        return Command(
            title: title,
            command: command,
            arguments: dict["arguments"] as? [Any] ?? [],
            object: dict,
            rawJSONString: nil
        )
    }

    private static func command(from command: EcuLspCommand, raw: EcuJSONValue?) -> Command? {
        guard command.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
        guard command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }

        let object = raw.flatMap(jsonObject) as? [String: Any] ?? [
            "title": command.title,
            "command": command.command,
            "arguments": command.arguments.map(\.jsonCompatibleObject),
        ]
        return Command(
            title: command.title,
            command: command.command,
            arguments: command.arguments.map(\.jsonCompatibleObject),
            object: object,
            rawJSONString: raw?.jsonString
        )
    }

    private static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func boolValue(_ any: Any?) -> Bool {
        if let v = any as? Bool { return v }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }

    private static func jsonObject(_ value: EcuJSONValue) -> Any {
        value.jsonCompatibleObject
    }

    private static func commandRawValue(from value: EcuJSONValue) -> EcuJSONValue? {
        guard case let .object(object) = value else { return nil }
        return object["command"]
    }
}
