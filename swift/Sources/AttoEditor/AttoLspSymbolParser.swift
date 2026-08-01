import Foundation

enum AttoLspSymbolParser {
    struct Symbol: Equatable {
        let name: String
        let detail: String?
        let kindLabel: String?
        let containerName: String?
        let target: AttoLspDefinitionParser.Target
        let depth: Int
    }

    static func documentSymbols(fromResultJSON json: String, documentURI: String) -> [Symbol] {
        guard let root = jsonRoot(json) else { return [] }
        guard let arr = root as? [Any] else { return [] }

        var out: [Symbol] = []
        for item in arr {
            appendDocumentSymbol(item, documentURI: documentURI, depth: 0, into: &out)
        }
        return out
    }

    static func workspaceSymbols(fromResultJSON json: String) -> [Symbol] {
        guard let root = jsonRoot(json) else { return [] }
        guard let arr = root as? [Any] else { return [] }

        var out: [Symbol] = []
        for item in arr {
            guard let dict = item as? [String: Any] else { continue }
            guard let name = nonEmptyString(dict["name"]) else { continue }
            guard let location = dict["location"] as? [String: Any] else { continue }
            guard let target = parseTarget(fromLocation: location) else { continue }

            out.append(Symbol(
                name: name,
                detail: nonEmptyString(dict["detail"]),
                kindLabel: kindLabel(dict["kind"]),
                containerName: nonEmptyString(dict["containerName"]),
                target: target,
                depth: 0
            ))
        }
        return out
    }

    private static func appendDocumentSymbol(
        _ any: Any,
        documentURI: String,
        depth: Int,
        into out: inout [Symbol]
    ) {
        guard let dict = any as? [String: Any] else { return }
        guard let name = nonEmptyString(dict["name"]) else { return }

        let target: AttoLspDefinitionParser.Target?
        if let location = dict["location"] as? [String: Any] {
            target = parseTarget(fromLocation: location)
        } else {
            let selection = (dict["selectionRange"] as? [String: Any])
                ?? (dict["selection_range"] as? [String: Any])
                ?? (dict["range"] as? [String: Any])
            target = parseTarget(fromRange: selection, uri: documentURI)
        }

        if let target {
            out.append(Symbol(
                name: name,
                detail: nonEmptyString(dict["detail"]),
                kindLabel: kindLabel(dict["kind"]),
                containerName: nonEmptyString(dict["containerName"]),
                target: target,
                depth: depth
            ))
        }

        guard let children = dict["children"] as? [Any] else { return }
        for child in children {
            appendDocumentSymbol(child, documentURI: documentURI, depth: depth + 1, into: &out)
        }
    }

    private static func parseTarget(fromLocation location: [String: Any]) -> AttoLspDefinitionParser.Target? {
        guard let uri = nonEmptyString(location["uri"]) else { return nil }
        if let range = location["range"] as? [String: Any] {
            return parseTarget(fromRange: range, uri: uri)
        }

        // LSP 3.17 `WorkspaceSymbol.location` can be `{ uri }` without a range.
        return AttoLspDefinitionParser.Target(uri: uri, line: 0, utf16Character: 0)
    }

    private static func parseTarget(fromRange range: [String: Any]?, uri: String) -> AttoLspDefinitionParser.Target? {
        guard let range else { return nil }
        guard let start = range["start"] as? [String: Any] else { return nil }
        guard let line = intValue(start["line"]), let character = intValue(start["character"]) else {
            return nil
        }
        return AttoLspDefinitionParser.Target(uri: uri, line: line, utf16Character: character)
    }

    private static func jsonRoot(_ json: String) -> Any? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func nonEmptyString(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : s
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private static func kindLabel(_ any: Any?) -> String? {
        if let label = stringKindLabel(any) { return label }
        guard let n = intValue(any) else { return nil }
        return lspKindLabels[n]
    }

    private static func stringKindLabel(_ any: Any?) -> String? {
        if let s = any as? String {
            return s
        }
        if let dict = any as? [String: Any] {
            if let s = dict["kind"] as? String { return s }
            if let n = intValue(dict["value"]) { return lspKindLabels[n] }
        }
        return nil
    }

    private static let lspKindLabels: [Int: String] = [
        1: "file",
        2: "module",
        3: "namespace",
        4: "package",
        5: "class",
        6: "method",
        7: "property",
        8: "field",
        9: "constructor",
        10: "enum",
        11: "interface",
        12: "function",
        13: "variable",
        14: "constant",
        15: "string",
        16: "number",
        17: "boolean",
        18: "array",
        19: "object",
        20: "key",
        21: "null",
        22: "enum member",
        23: "struct",
        24: "event",
        25: "operator",
        26: "type parameter",
    ]
}
