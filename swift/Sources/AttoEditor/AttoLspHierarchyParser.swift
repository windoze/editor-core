import EditorCoreUIFFI
import Foundation

enum AttoLspHierarchyParser {
    struct Item: Equatable {
        let name: String
        let detail: String?
        let kindLabel: String?
        let target: AttoLspDefinitionParser.Target
        let requestJSON: String
    }

    struct Entry: Equatable {
        let name: String
        let detail: String?
        let kindLabel: String?
        let target: AttoLspDefinitionParser.Target
        let relatedRangeCount: Int?
    }

    static func prepareCallItems(fromResultJSON json: String) -> [Item] {
        hierarchyItems(fromResultJSON: json)
    }

    static func prepareCallItems(from result: EcuLspCallHierarchyPrepareResult) -> [Item] {
        result.items.compactMap { item(from: $0) }
    }

    static func prepareTypeItems(fromResultJSON json: String) -> [Item] {
        hierarchyItems(fromResultJSON: json)
    }

    static func prepareTypeItems(from result: EcuLspTypeHierarchyPrepareResult) -> [Item] {
        result.items.compactMap { item(from: $0) }
    }

    static func incomingCalls(fromResultJSON json: String) -> [Entry] {
        guard let root = jsonRoot(json) else { return [] }
        guard let calls = root as? [Any] else { return [] }

        return calls.compactMap { any in
            guard let dict = any as? [String: Any] else { return nil }
            guard let from = dict["from"] as? [String: Any] else { return nil }
            guard let item = parseItem(from) else { return nil }

            let ranges = dict["fromRanges"] as? [[String: Any]] ?? []
            let target = ranges.compactMap { parseTarget(fromRange: $0, uri: item.target.uri) }.first
                ?? item.target

            return Entry(
                name: item.name,
                detail: item.detail,
                kindLabel: item.kindLabel,
                target: target,
                relatedRangeCount: ranges.isEmpty ? nil : ranges.count
            )
        }
    }

    static func incomingCalls(from result: EcuLspCallHierarchyIncomingCallsResult) -> [Entry] {
        result.calls.compactMap { call -> Entry? in
            guard let item = item(from: call.from) else { return nil }
            let target = call.fromRanges.compactMap { targetFromRange($0, uri: call.from.uri) }.first
                ?? item.target
            return Entry(
                name: item.name,
                detail: item.detail,
                kindLabel: item.kindLabel,
                target: target,
                relatedRangeCount: call.fromRanges.isEmpty ? nil : call.fromRanges.count
            )
        }
    }

    static func outgoingCalls(fromResultJSON json: String) -> [Entry] {
        guard let root = jsonRoot(json) else { return [] }
        guard let calls = root as? [Any] else { return [] }

        return calls.compactMap { any in
            guard let dict = any as? [String: Any] else { return nil }
            guard let to = dict["to"] as? [String: Any] else { return nil }
            guard let item = parseItem(to) else { return nil }
            let ranges = dict["fromRanges"] as? [[String: Any]] ?? []

            return Entry(
                name: item.name,
                detail: item.detail,
                kindLabel: item.kindLabel,
                target: item.target,
                relatedRangeCount: ranges.isEmpty ? nil : ranges.count
            )
        }
    }

    static func outgoingCalls(from result: EcuLspCallHierarchyOutgoingCallsResult) -> [Entry] {
        result.calls.compactMap { call -> Entry? in
            guard let item = item(from: call.to) else { return nil }
            return Entry(
                name: item.name,
                detail: item.detail,
                kindLabel: item.kindLabel,
                target: item.target,
                relatedRangeCount: call.fromRanges.isEmpty ? nil : call.fromRanges.count
            )
        }
    }

    static func typeHierarchyEntries(fromResultJSON json: String) -> [Entry] {
        hierarchyItems(fromResultJSON: json).map { item in
            Entry(
                name: item.name,
                detail: item.detail,
                kindLabel: item.kindLabel,
                target: item.target,
                relatedRangeCount: nil
            )
        }
    }

    static func typeHierarchyEntries(from result: EcuLspTypeHierarchyItemsResult) -> [Entry] {
        result.items.compactMap { typedItem -> Entry? in
            guard let item = item(from: typedItem) else { return nil }
            return Entry(
                name: item.name,
                detail: item.detail,
                kindLabel: item.kindLabel,
                target: item.target,
                relatedRangeCount: nil
            )
        }
    }

    private static func hierarchyItems(fromResultJSON json: String) -> [Item] {
        guard let root = jsonRoot(json) else { return [] }

        if root is NSNull {
            return []
        }

        if let arr = root as? [Any] {
            return arr.compactMap { any in
                guard let dict = any as? [String: Any] else { return nil }
                return parseItem(dict)
            }
        }

        if let dict = root as? [String: Any], let item = parseItem(dict) {
            return [item]
        }

        return []
    }

    private static func parseItem(_ dict: [String: Any]) -> Item? {
        guard let name = nonEmptyString(dict["name"]) else { return nil }
        guard let uri = nonEmptyString(dict["uri"]) else { return nil }
        let selectionRange = (dict["selectionRange"] as? [String: Any])
            ?? (dict["selection_range"] as? [String: Any])
            ?? (dict["range"] as? [String: Any])
        guard let target = parseTarget(fromRange: selectionRange, uri: uri) else { return nil }
        guard let requestJSON = jsonString(from: dict) else { return nil }

        return Item(
            name: name,
            detail: nonEmptyString(dict["detail"]),
            kindLabel: kindLabel(dict["kind"]),
            target: target,
            requestJSON: requestJSON
        )
    }

    private static func item(from item: EcuLspCallHierarchyItem) -> Item? {
        guard let name = nonEmptyString(item.name) else { return nil }
        guard let requestJSON = item.rawJSONString else { return nil }
        return Item(
            name: name,
            detail: nonEmptyString(item.detail),
            kindLabel: kindLabel(item.kind),
            target: targetFromRange(item.selectionRange, uri: item.uri),
            requestJSON: requestJSON
        )
    }

    private static func item(from item: EcuLspTypeHierarchyItem) -> Item? {
        guard let name = nonEmptyString(item.name) else { return nil }
        guard let requestJSON = item.rawJSONString else { return nil }
        return Item(
            name: name,
            detail: nonEmptyString(item.detail),
            kindLabel: kindLabel(item.kind),
            target: targetFromRange(item.selectionRange, uri: item.uri),
            requestJSON: requestJSON
        )
    }

    private static func parseTarget(
        fromRange range: [String: Any]?,
        uri: String
    ) -> AttoLspDefinitionParser.Target? {
        guard let range else { return nil }
        guard let start = range["start"] as? [String: Any] else { return nil }
        guard let line = intValue(start["line"]), let character = intValue(start["character"]) else {
            return nil
        }
        return AttoLspDefinitionParser.Target(uri: uri, line: line, utf16Character: character)
    }

    private static func targetFromRange(
        _ range: EcuLspRange,
        uri: String
    ) -> AttoLspDefinitionParser.Target {
        AttoLspDefinitionParser.Target(
            uri: uri,
            line: Int(range.start.line),
            utf16Character: Int(range.start.utf16Character)
        )
    }

    private static func jsonRoot(_ json: String) -> Any? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func jsonString(from object: Any) -> String? {
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

    private static func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private static func kindLabel(_ any: Any?) -> String? {
        if let s = any as? String {
            return s
        }
        if let n = intValue(any) {
            return lspKindLabels[n]
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
