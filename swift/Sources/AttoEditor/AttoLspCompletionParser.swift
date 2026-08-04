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
        fileprivate let rawJSONString: String?
        fileprivate let typedItem: EcuLspCompletionItem?
    }

    struct ApplicationPlan: Equatable {
        let start: UInt32
        let end: UInt32
        let text: String
        let isSnippet: Bool
        let additionalEdits: [EcuTextEdit]
        let additionalDocumentEdits: [DocumentTextEdits]
    }

    struct DocumentTextEdits: Equatable {
        let documentURI: String
        let edits: [RawTextEdit]
    }

    struct RawTextEdit: Equatable {
        let startLine: UInt32
        let startUTF16Character: UInt32
        let endLine: UInt32
        let endUTF16Character: UInt32
        let text: String

        var jsonObject: [String: Any] {
            [
                "range": [
                    "start": [
                        "line": Int(startLine),
                        "character": Int(startUTF16Character),
                    ],
                    "end": [
                        "line": Int(endLine),
                        "character": Int(endUTF16Character),
                    ],
                ],
                "newText": text,
            ]
        }
    }

    static func items(fromCompletionResultJSON json: String) -> [Item] {
        if let data = json.data(using: .utf8),
           let result = try? JSONDecoder().decode(EcuLspCompletionResult.self, from: data)
        {
            return items(fromCompletionResult: result)
        }

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

    static func items(fromCompletionResult result: EcuLspCompletionResult) -> [Item] {
        result.items.compactMap(item(fromCompletionItem:))
    }

    static func item(fromCompletionItemJSON json: String) -> Item? {
        if let data = json.data(using: .utf8),
           let item = try? JSONDecoder().decode(EcuLspCompletionItem.self, from: data)
        {
            return self.item(fromCompletionItem: item)
        }

        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = root as? [String: Any] else { return nil }
        return item(from: dict)
    }

    static func item(fromCompletionItem item: EcuLspCompletionItem) -> Item? {
        let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.isEmpty == false else { return nil }

        let rawJSONString = item.raw.flatMap(jsonString)
        let object = item.raw.flatMap(jsonObject) as? [String: Any] ?? [:]
        return Item(
            label: item.label,
            detail: item.detail,
            documentation: item.documentation?.text,
            commitCharacters: item.commitCharacters.filter { $0.isEmpty == false },
            kind: item.kind,
            kindLabel: item.kind.flatMap(kindLabel),
            filterText: item.filterText,
            sortText: item.sortText,
            object: object,
            rawJSONString: rawJSONString,
            typedItem: item
        )
    }

    static func rawJSON(for item: Item) -> String? {
        if let rawJSONString = item.rawJSONString {
            return rawJSONString
        }
        return jsonString(item.object)
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

    static func isCommitCharacter(_ character: String, for item: Item) -> Bool {
        guard character.isEmpty == false else { return false }
        return item.commitCharacters.contains(character)
    }

    static func filteredItems(_ items: [Item], prefix: String) -> [Item] {
        guard prefix.isEmpty == false else { return items }
        return items.filter { item in
            completionFilterText(for: item).range(
                of: prefix,
                options: [.caseInsensitive, .anchored]
            ) != nil
        }
    }

    static func completionPrefix(in text: String, start: UInt32, caretOffset: UInt32) -> String? {
        let scalars = Array(text.unicodeScalars)
        let start = Int(start)
        let end = Int(caretOffset)
        guard start >= 0, end >= start, end <= scalars.count else { return nil }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[start..<end])
        return String(out)
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
        if let typedItem = item.typedItem {
            return applicationPlan(
                for: typedItem,
                documentText: documentText,
                fallbackStart: fallbackStart,
                fallbackEnd: fallbackEnd
            )
        }

        let isSnippet = intValue(item.object["insertTextFormat"]) == 2
        let additionalEdits = textEdits(from: item.object["additionalTextEdits"], documentText: documentText)
        let additionalDocumentEdits = textDocumentEdits(from: item.object)

        if let edit = mainTextEdit(from: item.object["textEdit"], documentText: documentText) {
            return ApplicationPlan(
                start: edit.start,
                end: edit.end,
                text: edit.text,
                isSnippet: isSnippet,
                additionalEdits: additionalEdits,
                additionalDocumentEdits: additionalDocumentEdits
            )
        }

        guard let fallbackText = fallbackInsertText(from: item.object) else { return nil }
        return ApplicationPlan(
            start: min(fallbackStart, fallbackEnd),
            end: max(fallbackStart, fallbackEnd),
            text: fallbackText,
            isSnippet: isSnippet,
            additionalEdits: additionalEdits,
            additionalDocumentEdits: additionalDocumentEdits
        )
    }

    private static func applicationPlan(
        for item: EcuLspCompletionItem,
        documentText: String,
        fallbackStart: UInt32,
        fallbackEnd: UInt32
    ) -> ApplicationPlan? {
        let isSnippet = item.insertTextFormatKind == .snippet
        let additionalEdits = textEdits(from: item.additionalTextEdits, documentText: documentText)
        let rawObject = item.raw.flatMap(jsonObject(from:)) as? [String: Any] ?? [:]
        let additionalDocumentEdits = textDocumentEdits(from: rawObject)

        if let edit = textEdit(from: item.textEdit, documentText: documentText) {
            return ApplicationPlan(
                start: edit.start,
                end: edit.end,
                text: edit.text,
                isSnippet: isSnippet,
                additionalEdits: additionalEdits,
                additionalDocumentEdits: additionalDocumentEdits
            )
        }

        guard let fallbackText = fallbackInsertText(from: item) else { return nil }
        return ApplicationPlan(
            start: min(fallbackStart, fallbackEnd),
            end: max(fallbackStart, fallbackEnd),
            text: fallbackText,
            isSnippet: isSnippet,
            additionalEdits: additionalEdits,
            additionalDocumentEdits: additionalDocumentEdits
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

    private static func textEdit(
        from completionTextEdit: EcuLspCompletionTextEdit?,
        documentText: String
    ) -> EcuTextEdit? {
        guard let completionTextEdit else { return nil }

        switch completionTextEdit {
        case let .textEdit(edit):
            return textEdit(range: edit.range, text: edit.newText, documentText: documentText)
        case let .insertReplace(edit):
            return textEdit(range: edit.insert, text: edit.newText, documentText: documentText)
        case .unknown:
            return nil
        }
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
            object: dict,
            rawJSONString: jsonString(dict),
            typedItem: nil
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

    private static func textEdits(from edits: [EcuLspTextEdit], documentText: String) -> [EcuTextEdit] {
        edits.compactMap { edit in
            textEdit(range: edit.range, text: edit.newText, documentText: documentText)
        }
    }

    private static func textDocumentEdits(from object: [String: Any]) -> [DocumentTextEdits] {
        // LSP additionalTextEdits are current-document only; these optional extension shapes
        // carry raw LSP text edits for other documents and are applied through WorkspaceEdit.
        let candidates = [
            object["attoAdditionalTextDocumentEdits"],
            object["atto_additional_text_document_edits"],
            object["additionalTextDocumentEdits"],
            object["additional_text_document_edits"],
            object["additionalTextEditsByDocument"],
            object["additional_text_edits_by_document"],
        ]
        guard let source = candidates.compactMap({ $0 }).first else { return [] }

        if let grouped = source as? [String: Any] {
            return grouped.keys.sorted().compactMap { uri in
                let edits = rawTextEdits(from: grouped[uri])
                return edits.isEmpty ? nil : DocumentTextEdits(documentURI: uri, edits: edits)
            }
        }

        guard let entries = source as? [Any] else { return [] }
        return entries.compactMap { entry in
            guard let dict = entry as? [String: Any] else { return nil }
            let uri = stringValue(dict["documentURI"])
                ?? stringValue(dict["document_uri"])
                ?? stringValue(dict["uri"])
                ?? ((dict["textDocument"] as? [String: Any]).flatMap { stringValue($0["uri"]) })
            guard let uri, uri.isEmpty == false else { return nil }

            let edits = rawTextEdits(
                from: dict["edits"]
                    ?? dict["textEdits"]
                    ?? dict["text_edits"]
                    ?? dict["additionalTextEdits"]
                    ?? dict["additional_text_edits"]
            )
            return edits.isEmpty ? nil : DocumentTextEdits(documentURI: uri, edits: edits)
        }
    }

    private static func rawTextEdits(from any: Any?) -> [RawTextEdit] {
        guard let arr = any as? [Any] else { return [] }
        return arr.compactMap(rawTextEdit(from:))
    }

    private static func rawTextEdit(from any: Any) -> RawTextEdit? {
        guard let dict = any as? [String: Any],
              let range = dict["range"] as? [String: Any],
              let start = range["start"] as? [String: Any],
              let end = range["end"] as? [String: Any],
              let startLine = intValue(start["line"]),
              let startCharacter = intValue(start["character"]),
              let endLine = intValue(end["line"]),
              let endCharacter = intValue(end["character"]),
              startLine >= 0,
              startCharacter >= 0,
              endLine >= 0,
              endCharacter >= 0,
              let text = stringValue(dict["newText"])
        else {
            return nil
        }

        return RawTextEdit(
            startLine: UInt32(clamping: startLine),
            startUTF16Character: UInt32(clamping: startCharacter),
            endLine: UInt32(clamping: endLine),
            endUTF16Character: UInt32(clamping: endCharacter),
            text: text
        )
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

    private static func textEdit(range: EcuLspRange, text: String, documentText: String) -> EcuTextEdit? {
        let startOffset = AttoLspDefinitionParser.charOffsetForLspPosition(
            inText: documentText,
            line: Int(range.start.line),
            utf16Character: Int(range.start.utf16Character)
        )
        let endOffset = AttoLspDefinitionParser.charOffsetForLspPosition(
            inText: documentText,
            line: Int(range.end.line),
            utf16Character: Int(range.end.utf16Character)
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

    private static func fallbackInsertText(from item: EcuLspCompletionItem) -> String? {
        if let insertText = item.insertText, insertText.isEmpty == false {
            return insertText
        }
        if let textEditText = item.textEditText, textEditText.isEmpty == false {
            return textEditText
        }
        if item.label.isEmpty == false {
            return item.label
        }
        return nil
    }

    private static func completionFilterText(for item: Item) -> String {
        if let filterText = item.filterText, filterText.isEmpty == false {
            return filterText
        }
        return item.label
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

    private static func jsonString(_ value: EcuJSONValue) -> String? {
        jsonString(jsonObject(from: value))
    }

    private static func jsonObject(from value: EcuJSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .number(value):
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map { jsonObject(from: $0) }
        case let .object(values):
            return values.mapValues { jsonObject(from: $0) }
        }
    }
}
