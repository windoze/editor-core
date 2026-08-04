import EditorCoreUIFFI
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

    enum ResourceOperation: Equatable {
        struct CreateFile: Equatable {
            let uri: String
            let overwrite: Bool
            let ignoreIfExists: Bool
        }

        struct RenameFile: Equatable {
            let oldURI: String
            let newURI: String
            let overwrite: Bool
            let ignoreIfExists: Bool
        }

        struct DeleteFile: Equatable {
            let uri: String
            let recursive: Bool
            let ignoreIfNotExists: Bool
        }

        case create(CreateFile)
        case rename(RenameFile)
        case delete(DeleteFile)

        var affectedURIs: [String] {
            switch self {
            case .create(let op):
                return [op.uri]
            case .rename(let op):
                return [op.oldURI, op.newURI]
            case .delete(let op):
                return [op.uri]
            }
        }
    }

    struct ParseResult: Equatable {
        let documents: [DocumentEdit]
        let resourceOperations: [ResourceOperation]
        let unsupportedURIs: [String]

        var isEmpty: Bool {
            documents.isEmpty && resourceOperations.isEmpty && unsupportedURIs.isEmpty
        }
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

        let workspaceEditObject: [String: Any]
        if let nestedWorkspaceEdit = object["workspaceEdit"] {
            guard let nestedObject = nestedWorkspaceEdit as? [String: Any] else {
                return nil
            }
            workspaceEditObject = nestedObject
        } else {
            workspaceEditObject = object
        }

        var documentsByURI: [String: [TextEdit]] = [:]
        var documentOrder: [String] = []
        var resourceOperations: [ResourceOperation] = []
        var unsupportedURIs: [String] = []

        if let changes = workspaceEditObject["changes"] as? [String: Any] {
            for uri in changes.keys.sorted() {
                appendDocumentURI(uri, to: &documentOrder, documentsByURI: &documentsByURI)
                documentsByURI[uri, default: []].append(contentsOf: textEdits(from: changes[uri]))
            }
        }

        if let documentChanges = workspaceEditObject["documentChanges"] as? [Any] {
            for change in documentChanges {
                guard let changeObject = change as? [String: Any] else { continue }

                if let textDocument = changeObject["textDocument"] as? [String: Any],
                   let uri = stringValue(textDocument["uri"])
                {
                    appendDocumentURI(uri, to: &documentOrder, documentsByURI: &documentsByURI)
                    documentsByURI[uri, default: []].append(contentsOf: textEdits(from: changeObject["edits"]))
                    continue
                }

                if let operation = resourceOperation(from: changeObject) {
                    resourceOperations.append(operation)
                } else {
                    unsupportedURIs.append(contentsOf: resourceOperationURIs(from: changeObject))
                }
            }
        }

        let documents = documentOrder.map { uri in
            DocumentEdit(uri: uri, edits: documentsByURI[uri] ?? [])
        }

        return ParseResult(
            documents: documents,
            resourceOperations: resourceOperations,
            unsupportedURIs: uniqueSorted(unsupportedURIs)
        )
    }

    static func parse(_ workspaceEdit: EcuLspWorkspaceEdit) -> ParseResult {
        var documentsByURI: [String: [TextEdit]] = [:]
        var documentOrder: [String] = []
        var resourceOperations: [ResourceOperation] = []
        var unsupportedURIs: [String] = []

        for uri in workspaceEdit.changes.keys.sorted() {
            appendDocumentURI(uri, to: &documentOrder, documentsByURI: &documentsByURI)
            documentsByURI[uri, default: []].append(contentsOf: textEdits(from: workspaceEdit.changes[uri] ?? []))
        }

        for change in workspaceEdit.documentChanges {
            switch change {
            case .textDocumentEdit(let edit):
                let uri = edit.textDocument.uri
                appendDocumentURI(uri, to: &documentOrder, documentsByURI: &documentsByURI)
                documentsByURI[uri, default: []].append(contentsOf: textEdits(from: edit.edits))
            case .createFile(let operation):
                resourceOperations.append(.create(ResourceOperation.CreateFile(
                    uri: operation.uri,
                    overwrite: operation.options?.overwrite ?? false,
                    ignoreIfExists: operation.options?.ignoreIfExists ?? false
                )))
            case .renameFile(let operation):
                resourceOperations.append(.rename(ResourceOperation.RenameFile(
                    oldURI: operation.oldUri,
                    newURI: operation.newUri,
                    overwrite: operation.options?.overwrite ?? false,
                    ignoreIfExists: operation.options?.ignoreIfExists ?? false
                )))
            case .deleteFile(let operation):
                resourceOperations.append(.delete(ResourceOperation.DeleteFile(
                    uri: operation.uri,
                    recursive: operation.options?.recursive ?? false,
                    ignoreIfNotExists: operation.options?.ignoreIfNotExists ?? false
                )))
            case .unknown(let raw):
                unsupportedURIs.append(contentsOf: resourceOperationURIs(from: raw))
            }
        }

        let documents = documentOrder.map { uri in
            DocumentEdit(uri: uri, edits: documentsByURI[uri] ?? [])
        }

        return ParseResult(
            documents: documents,
            resourceOperations: resourceOperations,
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

    private static func textEdits(from edits: [EcuLspTextEdit]) -> [TextEdit] {
        edits.map { edit in
            TextEdit(
                range: Range(
                    start: Position(
                        line: Int(edit.range.start.line),
                        utf16Character: Int(edit.range.start.utf16Character)
                    ),
                    end: Position(
                        line: Int(edit.range.end.line),
                        utf16Character: Int(edit.range.end.utf16Character)
                    )
                ),
                newText: edit.newText
            )
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

    private static func resourceOperationURIs(from value: EcuJSONValue) -> [String] {
        guard case let .object(object) = value else { return [] }
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

    private static func resourceOperation(from object: [String: Any]) -> ResourceOperation? {
        let options = object["options"] as? [String: Any]
        switch stringValue(object["kind"]) {
        case "create":
            guard let uri = stringValue(object["uri"]) else { return nil }
            return .create(ResourceOperation.CreateFile(
                uri: uri,
                overwrite: boolValue(options?["overwrite"]) ?? false,
                ignoreIfExists: boolValue(options?["ignoreIfExists"]) ?? false
            ))
        case "rename":
            guard let oldURI = stringValue(object["oldUri"]),
                  let newURI = stringValue(object["newUri"])
            else { return nil }
            return .rename(ResourceOperation.RenameFile(
                oldURI: oldURI,
                newURI: newURI,
                overwrite: boolValue(options?["overwrite"]) ?? false,
                ignoreIfExists: boolValue(options?["ignoreIfExists"]) ?? false
            ))
        case "delete":
            guard let uri = stringValue(object["uri"]) else { return nil }
            return .delete(ResourceOperation.DeleteFile(
                uri: uri,
                recursive: boolValue(options?["recursive"]) ?? false,
                ignoreIfNotExists: boolValue(options?["ignoreIfNotExists"]) ?? false
            ))
        default:
            return nil
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }

    private static func boolValue(_ any: Any?) -> Bool? {
        if let value = any as? Bool { return value }
        if let number = any as? NSNumber { return number.boolValue }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let value = any as? String { return value }
        return nil
    }

    private static func stringValue(_ value: EcuJSONValue?) -> String? {
        guard case let .string(value) = value else { return nil }
        return value
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}
