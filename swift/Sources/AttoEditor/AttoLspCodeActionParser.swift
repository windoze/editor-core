import Foundation

enum AttoLspCodeActionParser {
    struct Command {
        let title: String
        let command: String
        let arguments: [Any]
        fileprivate let object: [String: Any]
    }

    struct Item {
        let title: String
        let kind: String?
        let isPreferred: Bool
        let disabledReason: String?
        let edit: [String: Any]?
        let command: Command?
        let isLegacyCommand: Bool
        fileprivate let object: [String: Any]
    }

    static func items(fromCodeActionResultJSON json: String) -> [Item] {
        guard let data = json.data(using: .utf8) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return [] }
        guard let arr = root as? [Any] else { return [] }
        return arr.compactMap { any in
            guard let dict = any as? [String: Any] else { return nil }
            return item(from: dict)
        }
    }

    static func item(fromCodeActionJSON json: String) -> Item? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = root as? [String: Any] else { return nil }
        return item(from: dict)
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

    static func rawJSON(for item: Item) -> String? {
        jsonString(item.object)
    }

    static func editJSON(for item: Item) -> String? {
        guard let edit = item.edit else { return nil }
        return jsonString(edit)
    }

    static func commandJSON(for command: Command) -> String? {
        jsonString(command.object)
    }

    private static func item(from dict: [String: Any]) -> Item? {
        guard let title = dict["title"] as? String, title.isEmpty == false else { return nil }

        let hasCodeActionFields = dict["edit"] != nil
            || dict["kind"] != nil
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
                command: command,
                isLegacyCommand: false,
                object: dict
            )
        }

        guard let command = command(from: dict) else { return nil }
        return Item(
            title: command.title,
            kind: nil,
            isPreferred: false,
            disabledReason: nil,
            edit: nil,
            command: command,
            isLegacyCommand: true,
            object: dict
        )
    }

    private static func command(from dict: [String: Any]) -> Command? {
        guard let title = dict["title"] as? String, title.isEmpty == false else { return nil }
        guard let command = dict["command"] as? String, command.isEmpty == false else { return nil }
        return Command(
            title: title,
            command: command,
            arguments: dict["arguments"] as? [Any] ?? [],
            object: dict
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
}
