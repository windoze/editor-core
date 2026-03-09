import Foundation

enum AttoLspDefinitionParser {
    struct Target: Equatable {
        let uri: String
        let line: Int
        let utf16Character: Int
    }

    static func firstTarget(fromDefinitionResultJSON json: String) -> Target? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstTarget(from: root)
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

    private static func firstTarget(from any: Any) -> Target? {
        if any is NSNull { return nil }

        if let arr = any as? [Any] {
            for el in arr {
                if let t = firstTarget(from: el) {
                    return t
                }
            }
            return nil
        }

        if let dict = any as? [String: Any] {
            return parseLocation(dict) ?? parseLocationLink(dict)
        }

        return nil
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

