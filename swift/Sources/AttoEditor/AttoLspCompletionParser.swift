import EditorCoreUIFFI
import Foundation

enum AttoLspCompletionParser {
    struct Item {
        let label: String
        let detail: String?
        let documentation: String?
        let commitCharacters: [String]
        let kind: Int?
        let kindLabel: String?
        let filterText: String?
        let sortText: String?
        fileprivate let object: [String: Any]
    }

    struct ApplicationPlan: Equatable {
        let start: UInt32
        let end: UInt32
        let text: String
        let isSnippet: Bool
        let additionalEdits: [EcuTextEdit]
    }

    static func items(fromCompletionResultJSON json: String) -> [Item] {
        guard let data = json.data(using: .utf8) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return [] }
        guard !(root is NSNull) else { return [] }

        let rawItems: [Any]
        if let arr = root as? [Any] {
            rawItems = arr
        } else if let dict = root as? [String: Any], let arr = dict["items"] as? [Any] {
            rawItems = arr
        } else {
            return []
        }

        return rawItems.compactMap { any in
            guard let dict = any as? [String: Any] else { return nil }
            return item(from: dict)
        }
    }

    static func item(fromCompletionItemJSON json: String) -> Item? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = root as? [String: Any] else { return nil }
        return item(from: dict)
    }

    static func rawJSON(for item: Item) -> String? {
        jsonString(item.object)
    }

    static func displayTitle(for item: Item) -> String {
        var suffix: [String] = []
        if let kindLabel = item.kindLabel {
            suffix.append("[\(kindLabel)]")
        }
        if let detail = item.detail, detail.isEmpty == false {
            suffix.append(detail)
        }
        if suffix.isEmpty {
            return item.label
        }
        return "\(item.label)  \(suffix.joined(separator: " "))"
    }

    static func previewText(for item: Item) -> String? {
        var lines: [String] = [item.label]

        var metadata: [String] = []
        if let kindLabel = item.kindLabel {
            metadata.append(kindLabel)
        }
        if let detail = item.detail, detail.isEmpty == false {
            metadata.append(detail)
        }
        if metadata.isEmpty == false {
            lines.append(metadata.joined(separator: "  "))
        }

        if let documentation = item.documentation, documentation.isEmpty == false {
            lines.append("")
            lines.append(documentation)
        }

        if item.commitCharacters.isEmpty == false {
            lines.append("")
            lines.append("Commit characters: \(item.commitCharacters.joined(separator: " "))")
        }

        let text = lines.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    static func identifierFallbackRange(in text: String, caretOffset: UInt32) -> (start: UInt32, end: UInt32) {
        let scalars = Array(text.unicodeScalars)
        let end = max(0, min(Int(caretOffset), scalars.count))
        var start = end
        while start > 0, isIdentifierScalar(scalars[start - 1]) {
            start -= 1
        }
        return (UInt32(clamping: start), UInt32(clamping: end))
    }

    static func applicationPlan(
        for item: Item,
        documentText: String,
        fallbackStart: UInt32,
        fallbackEnd: UInt32
    ) -> ApplicationPlan? {
        let isSnippet = intValue(item.object["insertTextFormat"]) == 2
        let additionalEdits = textEdits(from: item.object["additionalTextEdits"], documentText: documentText)

        if let edit = mainTextEdit(from: item.object["textEdit"], documentText: documentText) {
            return ApplicationPlan(
                start: edit.start,
                end: edit.end,
                text: edit.text,
                isSnippet: isSnippet,
                additionalEdits: additionalEdits
            )
        }

        guard let fallbackText = fallbackInsertText(from: item.object) else { return nil }
        return ApplicationPlan(
            start: min(fallbackStart, fallbackEnd),
            end: max(fallbackStart, fallbackEnd),
            text: fallbackText,
            isSnippet: isSnippet,
            additionalEdits: additionalEdits
        )
    }

    private static func mainTextEdit(from any: Any?, documentText: String) -> EcuTextEdit? {
        guard let dict = any as? [String: Any] else { return nil }

        if let range = dict["range"] as? [String: Any],
           let text = stringValue(dict["newText"])
        {
            return textEdit(range: range, text: text, documentText: documentText)
        }

        if let insert = dict["insert"] as? [String: Any],
           let text = stringValue(dict["newText"])
        {
            return textEdit(range: insert, text: text, documentText: documentText)
        }

        return nil
    }

    private static func item(from dict: [String: Any]) -> Item? {
        guard let label = dict["label"] as? String, label.isEmpty == false else { return nil }
        let kind = intValue(dict["kind"])
        return Item(
            label: label,
            detail: stringValue(dict["detail"]),
            documentation: documentationText(dict["documentation"]),
            commitCharacters: stringArray(dict["commitCharacters"]),
            kind: kind,
            kindLabel: kind.flatMap(kindLabel),
            filterText: stringValue(dict["filterText"]),
            sortText: stringValue(dict["sortText"]),
            object: dict
        )
    }

    private static func textEdits(from any: Any?, documentText: String) -> [EcuTextEdit] {
        guard let arr = any as? [Any] else { return [] }
        return arr.compactMap { el in
            guard let dict = el as? [String: Any] else { return nil }
            guard let range = dict["range"] as? [String: Any] else { return nil }
            guard let text = stringValue(dict["newText"]) else { return nil }
            return textEdit(range: range, text: text, documentText: documentText)
        }
    }

    private static func textEdit(range: [String: Any], text: String, documentText: String) -> EcuTextEdit? {
        guard let start = range["start"] as? [String: Any],
              let end = range["end"] as? [String: Any],
              let startLine = intValue(start["line"]),
              let startCharacter = intValue(start["character"]),
              let endLine = intValue(end["line"]),
              let endCharacter = intValue(end["character"])
        else {
            return nil
        }

        let startOffset = AttoLspDefinitionParser.charOffsetForLspPosition(
            inText: documentText,
            line: startLine,
            utf16Character: startCharacter
        )
        let endOffset = AttoLspDefinitionParser.charOffsetForLspPosition(
            inText: documentText,
            line: endLine,
            utf16Character: endCharacter
        )
        return EcuTextEdit(start: min(startOffset, endOffset), end: max(startOffset, endOffset), text: text)
    }

    private static func fallbackInsertText(from dict: [String: Any]) -> String? {
        if let insertText = stringValue(dict["insertText"]), insertText.isEmpty == false {
            return insertText
        }
        if let label = stringValue(dict["label"]), label.isEmpty == false {
            return label
        }
        return nil
    }

    private static func kindLabel(_ kind: Int) -> String? {
        switch kind {
        case 1: return "Text"
        case 2: return "Method"
        case 3: return "Function"
        case 4: return "Constructor"
        case 5: return "Field"
        case 6: return "Variable"
        case 7: return "Class"
        case 8: return "Interface"
        case 9: return "Module"
        case 10: return "Property"
        case 11: return "Unit"
        case 12: return "Value"
        case 13: return "Enum"
        case 14: return "Keyword"
        case 15: return "Snippet"
        case 16: return "Color"
        case 17: return "File"
        case 18: return "Reference"
        case 19: return "Folder"
        case 20: return "EnumMember"
        case 21: return "Constant"
        case 22: return "Struct"
        case 23: return "Event"
        case 24: return "Operator"
        case 25: return "TypeParameter"
        default: return nil
        }
    }

    private static func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "_" { return true }
        if scalar.value >= 48, scalar.value <= 57 { return true }
        if scalar.value >= 65, scalar.value <= 90 { return true }
        if scalar.value >= 97, scalar.value <= 122 { return true }
        return false
    }

    private static func stringValue(_ any: Any?) -> String? {
        any as? String
    }

    private static func documentationText(_ any: Any?) -> String? {
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : s
        }
        if let dict = any as? [String: Any],
           let value = dict["value"] as? String
        {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : value
        }
        return nil
    }

    private static func stringArray(_ any: Any?) -> [String] {
        guard let arr = any as? [Any] else { return [] }
        return arr.compactMap { value in
            guard let string = value as? String, string.isEmpty == false else { return nil }
            return string
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
