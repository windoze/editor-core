import EditorCoreUIFFI
import Foundation

enum AttoLspDefinitionParser {
    struct Target: Equatable {
        let uri: String
        let line: Int
        let utf16Character: Int
    }

    struct LocationItem: Equatable {
        let target: Target
        let fileDisplayName: String

        var displayTitle: String {
            "\(fileDisplayName):\(target.line + 1):\(target.utf16Character + 1)"
        }
    }

    static func firstTarget(fromDefinitionResultJSON json: String) -> Target? {
        targets(fromLocationResultJSON: json).first
    }

    static func firstTarget(fromDefinitionResult result: EcuLspLocationResult) -> Target? {
        targets(fromLocationResult: result).first
    }

    static func targets(fromLocationResultJSON json: String) -> [Target] {
        if let data = json.data(using: .utf8),
           let result = try? JSONDecoder().decode(EcuLspLocationResult.self, from: data)
        {
            return targets(fromLocationResult: result)
        }

        guard let data = json.data(using: .utf8) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [Target] = []
        appendTargets(from: root, into: &out)
        return out
    }

    static func targets(fromLocationResult result: EcuLspLocationResult) -> [Target] {
        result.targets.map { target in
            Target(
                uri: target.uri,
                line: Int(target.selectionRange.start.line),
                utf16Character: Int(target.selectionRange.start.utf16Character)
            )
        }
    }

    static func locationItems(fromLocationResultJSON json: String, workspaceRootURL: URL) -> [LocationItem] {
        locationItems(for: targets(fromLocationResultJSON: json), workspaceRootURL: workspaceRootURL)
    }

    static func locationItems(fromLocationResult result: EcuLspLocationResult, workspaceRootURL: URL) -> [LocationItem] {
        locationItems(for: targets(fromLocationResult: result), workspaceRootURL: workspaceRootURL)
    }

    static func locationItems(for targets: [Target], workspaceRootURL: URL) -> [LocationItem] {
        let root = workspaceRootURL.standardizedFileURL.path
        return targets.enumerated()
            .map { index, target -> (index: Int, item: LocationItem, sortGroup: Int, sortPath: String) in
                let display = fileDisplayNameAndSortKey(for: target.uri, workspaceRootPath: root)
                return (
                    index: index,
                    item: LocationItem(target: target, fileDisplayName: display.name),
                    sortGroup: display.group,
                    sortPath: display.key
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortGroup != rhs.sortGroup { return lhs.sortGroup < rhs.sortGroup }
                let pathCompare = lhs.sortPath.localizedStandardCompare(rhs.sortPath)
                if pathCompare != .orderedSame { return pathCompare == .orderedAscending }
                if lhs.item.target.line != rhs.item.target.line { return lhs.item.target.line < rhs.item.target.line }
                if lhs.item.target.utf16Character != rhs.item.target.utf16Character {
                    return lhs.item.target.utf16Character < rhs.item.target.utf16Character
                }
                return lhs.index < rhs.index
            }
            .map { $0.item }
    }

    /// Convert an LSP position (line + UTF-16 character) into an editor char offset (Unicode scalars).
    ///
    /// Notes:
    /// - LSP uses UTF-16 code units; the editor core uses Unicode scalar indices (Rust `char` offsets).
    /// - This clamps out-of-range line/column values to the end of the closest line.
    static func charOffsetForLspPosition(inText text: String, line: Int, utf16Character: Int) -> UInt32 {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.isEmpty == false else { return 0 }

        let safeLine = max(0, min(line, lines.count - 1))

        var lineStart: Int = 0
        if safeLine > 0 {
            for i in 0..<safeLine {
                lineStart += lines[i].unicodeScalars.count + 1 // + '\n'
            }
        }

        let column = scalarOffsetFromUTF16(utf16Character, in: lines[safeLine])
        return UInt32(clamping: lineStart + column)
    }

    private static func appendTargets(from any: Any, into out: inout [Target]) {
        if any is NSNull { return }

        if let arr = any as? [Any] {
            for el in arr {
                appendTargets(from: el, into: &out)
            }
            return
        }

        if let dict = any as? [String: Any] {
            if let target = parseLocation(dict) ?? parseLocationLink(dict) {
                out.append(target)
            }
            return
        }
    }

    private static func parseLocation(_ dict: [String: Any]) -> Target? {
        guard let uri = dict["uri"] as? String else { return nil }
        guard let range = dict["range"] as? [String: Any] else { return nil }
        guard let start = parseRangeStart(range) else { return nil }
        return Target(uri: uri, line: start.line, utf16Character: start.character)
    }

    private static func parseLocationLink(_ dict: [String: Any]) -> Target? {
        guard let uri = dict["targetUri"] as? String else { return nil }
        let range = (dict["targetSelectionRange"] as? [String: Any]) ?? (dict["targetRange"] as? [String: Any])
        guard let range, let start = parseRangeStart(range) else { return nil }
        return Target(uri: uri, line: start.line, utf16Character: start.character)
    }

    private static func parseRangeStart(_ range: [String: Any]) -> (line: Int, character: Int)? {
        guard let start = range["start"] as? [String: Any] else { return nil }
        guard let line = intValue(start["line"]), let character = intValue(start["character"]) else { return nil }
        return (line, character)
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private static func fileDisplayNameAndSortKey(
        for uri: String,
        workspaceRootPath root: String
    ) -> (name: String, group: Int, key: String) {
        guard let url = URL(string: uri), url.isFileURL else {
            return (uri, 2, uri)
        }

        let standardized = url.standardizedFileURL
        let path = standardized.path
        if path == root {
            return (standardized.lastPathComponent, 0, standardized.lastPathComponent)
        }
        if root == "/" {
            let relative = String(path.dropFirst())
            return (relative, 0, relative)
        }
        if path.hasPrefix(root + "/") {
            let relative = String(path.dropFirst(root.count + 1))
            return (relative, 0, relative)
        }
        return (standardized.lastPathComponent, 1, path)
    }

    private static func scalarOffsetFromUTF16(_ utf16: Int, in line: Substring) -> Int {
        if utf16 <= 0 { return 0 }

        var remaining = utf16
        var scalars = 0
        for s in line.unicodeScalars {
            // A Unicode scalar maps to either 1 (BMP) or 2 (non-BMP) UTF-16 code units.
            let len16 = s.value > 0xFFFF ? 2 : 1
            if remaining < len16 {
                break
            }
            remaining -= len16
            scalars += 1
            if remaining == 0 {
                break
            }
        }
        return scalars
    }
}
