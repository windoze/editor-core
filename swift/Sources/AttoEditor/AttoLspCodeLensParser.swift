import EditorCoreUIFFI
import Foundation

enum AttoLspCodeLensParser {
    struct Command: Equatable {
        let title: String
        let command: String
        let commandJSON: String
    }

    struct Item: Equatable {
        let title: String
        let range: EcuOffsetRange
        let lensJSON: String
        let command: Command?
    }

    static func items(fromDecorationsSnapshot snapshot: EcuDecorationsSnapshot) -> [Item] {
        snapshot.layers.flatMap { layer in
            layer.decorations.compactMap { decoration in
                guard isCodeLensKind(decoration.kind) else { return nil }
                guard let lensJSON = decoration.dataJSON else { return nil }
                return item(
                    fromCodeLensJSON: lensJSON,
                    fallbackTitle: decoration.text,
                    fallbackRange: decoration.range
                )
            }
        }
    }

    static func item(
        fromCodeLensJSON json: String,
        fallbackTitle: String? = nil,
        fallbackRange: EcuOffsetRange = EcuOffsetRange(start: 0, end: 0)
    ) -> Item? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = root as? [String: Any] else { return nil }

        let command = (dict["command"] as? [String: Any]).flatMap(command(from:))
        let title = command?.title ?? nonEmptyString(fallbackTitle) ?? "Code Lens"

        return Item(
            title: title,
            range: fallbackRange,
            lensJSON: json,
            command: command
        )
    }

    static func displayTitle(for item: Item, location: String?) -> String {
        guard let location, location.isEmpty == false else {
            return item.title
        }
        return "\(item.title) — \(location)"
    }

    private static func command(from dict: [String: Any]) -> Command? {
        guard let title = nonEmptyString(dict["title"]) else { return nil }
        guard let command = nonEmptyString(dict["command"]) else { return nil }
        guard let commandJSON = jsonString(dict) else { return nil }

        return Command(title: title, command: command, commandJSON: commandJSON)
    }

    private static func isCodeLensKind(_ value: EcuJSONValue) -> Bool {
        guard case .object(let dict) = value else { return false }
        guard case .string(let kind)? = dict["kind"] else { return false }
        return kind == "code_lens"
    }

    private static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func nonEmptyString(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : s
    }
}
