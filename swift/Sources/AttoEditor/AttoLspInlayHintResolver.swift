import EditorCoreUIFFI
import Foundation

enum AttoLspInlayHintResolver {
    struct Command {
        let title: String
        let commandJSON: String
    }

    static func displayText(for hint: EcuLspInlayHint) -> String? {
        var sections: [String] = []

        if let tooltip = tooltipText(hint.tooltip) {
            sections.append(tooltip)
        }

        switch hint.label {
        case let .parts(parts):
            for part in parts {
                if let tooltip = tooltipText(part.tooltip) {
                    sections.append("\(part.value)\n\(tooltip)")
                }
            }
        case .string:
            break
        }

        if sections.isEmpty {
            let label = hint.label.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty == false {
                sections.append(label)
            }
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    static func workspaceEditJSON(for hint: EcuLspInlayHint, documentURI: String) -> String? {
        guard hint.textEdits.isEmpty == false else { return nil }
        return jsonString([
            "changes": [
                documentURI: hint.textEdits.map(textEditObject),
            ],
        ])
    }

    static func command(for hint: EcuLspInlayHint) -> Command? {
        guard case let .parts(parts) = hint.label else { return nil }
        for part in parts {
            guard let command = part.command else { continue }
            guard let title = nonEmptyString(command.title) else { continue }
            guard let commandJSON = commandJSON(for: command) else { continue }
            return Command(title: title, commandJSON: commandJSON)
        }
        return nil
    }

    private static func tooltipText(_ tooltip: EcuLspInlayHintTooltip?) -> String? {
        let value: String?
        switch tooltip {
        case let .string(text):
            value = text
        case let .markup(markup):
            value = markup.value
        case .raw, .none:
            value = nil
        }

        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func textEditObject(_ edit: EcuLspTextEdit) -> [String: Any] {
        [
            "range": [
                "start": positionObject(edit.range.start),
                "end": positionObject(edit.range.end),
            ],
            "newText": edit.newText,
        ]
    }

    private static func positionObject(_ position: EcuLspPosition) -> [String: Any] {
        [
            "line": Int(position.line),
            "character": Int(position.utf16Character),
        ]
    }

    private static func commandJSON(for command: EcuLspCommand) -> String? {
        guard nonEmptyString(command.command) != nil else { return nil }
        var object: [String: Any] = [
            "title": command.title,
            "command": command.command,
        ]
        if command.arguments.isEmpty == false {
            object["arguments"] = command.arguments.map(\.jsonCompatibleObject)
        }
        return jsonString(object)
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
