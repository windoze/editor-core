import Foundation

enum AttoWorkspaceEditParser {
    struct Position: Equatable {
        let line: Int
        let utf16Character: Int
    }

    struct Range: Equatable {
        let start: Position
        let end: Position
    }

    struct TextEdit: Equatable {
        let range: Range
        let newText: String
    }

    struct DocumentEdit: Equatable {
        let uri: String
        let edits: [TextEdit]

        var hasOverlappingEdits: Bool {
            Self.hasOverlappingEdits(edits)
        }

        private static func hasOverlappingEdits(_ edits: [TextEdit]) -> Bool {
            guard edits.count > 1 else { return false }

            let sorted = edits.sorted { a, b in
                if a.range.start != b.range.start {
                    return positionLessThan(a.range.start, b.range.start)
                }
                return positionLessThan(a.range.end, b.range.end)
            }

            for idx in 1..<sorted.count {
                if rangesOverlap(sorted[idx - 1].range, sorted[idx].range) {
                    return true
                }
            }
            return false
        }

        private static func rangesOverlap(_ a: Range, _ b: Range) -> Bool {
            positionLessThan(a.start, b.end) && positionLessThan(b.start, a.end)
        }

        private static func positionLessThan(_ lhs: Position, _ rhs: Position) -> Bool {
            if lhs.line != rhs.line {
                return lhs.line < rhs.line
            }
            return lhs.utf16Character < rhs.utf16Character
        }
    }

    struct ParseResult: Equatable {
        let documents: [DocumentEdit]
        let unsupportedURIs: [String]
    }

    struct ApplyResult: Equatable {
        let text: String
        let editCount: Int
        let hasOverlappingEdits: Bool
    }

    static func parse(_ json: String) -> ParseResult? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = root as? [String: Any]
        else {
            return nil
        }

        var documentsByURI: [String: [TextEdit]] = [:]
        var documentOrder: [String] = []
        var unsupportedURIs: [String] = []

        if let changes = object["changes"] as? [String: Any] {
            for uri in changes.keys.sorted() {
                appendDocumentURI(uri, to: &documentOrder, documentsByURI: &documentsByURI)
                documentsByURI[uri, default: []].append(contentsOf: textEdits(from: changes[uri]))
            }
        }

        if let documentChanges = object["documentChanges"] as? [Any] {
            for change in documentChanges {
                guard let changeObject = change as? [String: Any] else { continue }

                if let textDocument = changeObject["textDocument"] as? [String: Any],
                   let uri = stringValue(textDocument["uri"])
                {
                    appendDocumentURI(uri, to: &documentOrder, documentsByURI: &documentsByURI)
                    documentsByURI[uri, default: []].append(contentsOf: textEdits(from: changeObject["edits"]))
                    continue
                }

                unsupportedURIs.append(contentsOf: resourceOperationURIs(from: changeObject))
            }
        }

        let documents = documentOrder.map { uri in
            DocumentEdit(uri: uri, edits: documentsByURI[uri] ?? [])
        }

        return ParseResult(
            documents: documents,
            unsupportedURIs: uniqueSorted(unsupportedURIs)
        )
    }

    static func apply(_ document: DocumentEdit, to text: String) -> ApplyResult? {
        let hasOverlappingEdits = document.hasOverlappingEdits
        guard hasOverlappingEdits == false else {
            return ApplyResult(text: text, editCount: 0, hasOverlappingEdits: true)
        }

        struct ResolvedEdit {
            let index: Int
            let start: Int
            let end: Int
            let text: String
        }

        let scalarCount = text.unicodeScalars.count
        var resolved: [ResolvedEdit] = []
        resolved.reserveCapacity(document.edits.count)

        for (index, edit) in document.edits.enumerated() {
            let start = Int(
                AttoLspDefinitionParser.charOffsetForLspPosition(
                    inText: text,
                    line: edit.range.start.line,
                    utf16Character: edit.range.start.utf16Character
                )
            )
            let end = Int(
                AttoLspDefinitionParser.charOffsetForLspPosition(
                    inText: text,
                    line: edit.range.end.line,
                    utf16Character: edit.range.end.utf16Character
                )
            )
            let lower = min(start, end)
            let upper = max(start, end)
            guard lower <= upper, upper <= scalarCount else { return nil }
            resolved.append(ResolvedEdit(index: index, start: lower, end: upper, text: edit.newText))
        }

        resolved.sort { a, b in
            if a.start != b.start { return a.start > b.start }
            if a.end != b.end { return a.end > b.end }
            return a.index > b.index
        }

        var output = text
        for edit in resolved {
            let startIndex = output.unicodeScalars.index(output.unicodeScalars.startIndex, offsetBy: edit.start)
            let endIndex = output.unicodeScalars.index(output.unicodeScalars.startIndex, offsetBy: edit.end)
            output.unicodeScalars.replaceSubrange(startIndex..<endIndex, with: edit.text.unicodeScalars)
        }

        return ApplyResult(
            text: output,
            editCount: document.edits.count,
            hasOverlappingEdits: false
        )
    }

    private static func appendDocumentURI(
        _ uri: String,
        to order: inout [String],
        documentsByURI: inout [String: [TextEdit]]
    ) {
        if documentsByURI[uri] == nil {
            documentsByURI[uri] = []
            order.append(uri)
        }
    }

    private static func textEdits(from any: Any?) -> [TextEdit] {
        guard let edits = any as? [Any] else { return [] }
        return edits.compactMap { edit in
            guard let object = edit as? [String: Any] else { return nil }
            guard let rangeObject = object["range"] as? [String: Any] else { return nil }
            guard let range = range(from: rangeObject) else { return nil }
            return TextEdit(range: range, newText: stringValue(object["newText"]) ?? "")
        }
    }

    private static func range(from object: [String: Any]) -> Range? {
        guard let startObject = object["start"] as? [String: Any],
              let endObject = object["end"] as? [String: Any],
              let start = position(from: startObject),
              let end = position(from: endObject)
        else {
            return nil
        }
        return Range(start: start, end: end)
    }

    private static func position(from object: [String: Any]) -> Position? {
        guard let line = intValue(object["line"]),
              let character = intValue(object["character"])
        else {
            return nil
        }
        return Position(line: line, utf16Character: character)
    }

    private static func resourceOperationURIs(from object: [String: Any]) -> [String] {
        switch stringValue(object["kind"]) {
        case "create", "delete":
            return stringValue(object["uri"]).map { [$0] } ?? []
        case "rename":
            return [stringValue(object["oldUri"]), stringValue(object["newUri"])].compactMap { $0 }
        default:
            return [stringValue(object["uri"]), stringValue(object["oldUri"]), stringValue(object["newUri"])]
                .compactMap { $0 }
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let value = any as? String { return value }
        return nil
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}
