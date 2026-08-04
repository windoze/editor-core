import EditorCoreUIFFI
import Foundation

enum AttoLspLinkedEditingParser {
    struct Result: Equatable {
        let ranges: [EcuSelectionRange]
        let wordPattern: String?

        func primaryIndex(containing offset: UInt32) -> UInt32 {
            for (index, range) in ranges.enumerated() {
                let start = min(range.start, range.end)
                let end = max(range.start, range.end)
                if offset >= start, offset <= end {
                    return UInt32(index)
                }
            }
            return 0
        }
    }

    static func result(fromLinkedEditingRangeResultJSON json: String, documentText: String) -> Result? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }
        if root is NSNull {
            return nil
        }
        guard let object = root as? [String: Any] else {
            return nil
        }

        let ranges = selectionRanges(from: object["ranges"], documentText: documentText)
        guard ranges.isEmpty == false else {
            return nil
        }
        let wordPattern = object["wordPattern"] as? String
        guard rangesAreConsistent(ranges, documentText: documentText, wordPattern: wordPattern) else {
            return nil
        }
        return Result(ranges: ranges, wordPattern: wordPattern)
    }

    static func result(from result: EcuLspLinkedEditingRangeResult, documentText: String) -> Result? {
        guard result.shape == .linkedEditingRange else {
            return nil
        }

        let ranges = selectionRanges(from: result.ranges, documentText: documentText)
        guard ranges.isEmpty == false else {
            return nil
        }
        guard rangesAreConsistent(ranges, documentText: documentText, wordPattern: result.wordPattern) else {
            return nil
        }
        return Result(ranges: ranges, wordPattern: result.wordPattern)
    }

    private static func selectionRanges(from any: Any?, documentText: String) -> [EcuSelectionRange] {
        guard let array = any as? [Any] else { return [] }

        var out: [EcuSelectionRange] = []
        var seen = Set<String>()
        for element in array {
            guard let object = element as? [String: Any],
                  let range = selectionRange(from: object, documentText: documentText)
            else {
                continue
            }
            let key = "\(range.start):\(range.end)"
            if seen.insert(key).inserted {
                out.append(range)
            }
        }
        return out
    }

    private static func selectionRanges(from ranges: [EcuLspRange], documentText: String) -> [EcuSelectionRange] {
        var out: [EcuSelectionRange] = []
        var seen = Set<String>()
        for range in ranges {
            let selection = selectionRange(from: range, documentText: documentText)
            let key = "\(selection.start):\(selection.end)"
            if seen.insert(key).inserted {
                out.append(selection)
            }
        }
        return out
    }

    private static func selectionRange(from object: [String: Any], documentText: String) -> EcuSelectionRange? {
        guard let start = object["start"] as? [String: Any],
              let end = object["end"] as? [String: Any],
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
        return EcuSelectionRange(start: min(startOffset, endOffset), end: max(startOffset, endOffset))
    }

    private static func selectionRange(from range: EcuLspRange, documentText: String) -> EcuSelectionRange {
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
        return EcuSelectionRange(start: min(startOffset, endOffset), end: max(startOffset, endOffset))
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }

    private static func rangesAreConsistent(
        _ ranges: [EcuSelectionRange],
        documentText: String,
        wordPattern: String?
    ) -> Bool {
        guard let texts = selectedTexts(for: ranges, documentText: documentText) else {
            return false
        }
        guard let first = texts.first, first.isEmpty == false else {
            return false
        }
        guard texts.allSatisfy({ $0 == first }) else {
            return false
        }
        return texts.allSatisfy { matchesWordPattern($0, wordPattern: wordPattern) }
    }

    private static func selectedTexts(for ranges: [EcuSelectionRange], documentText: String) -> [String]? {
        let scalars = Array(documentText.unicodeScalars)
        var out: [String] = []
        for range in ranges {
            let start = Int(min(range.start, range.end))
            let end = Int(max(range.start, range.end))
            guard start >= 0, end <= scalars.count, start <= end else {
                return nil
            }
            out.append(String(String.UnicodeScalarView(scalars[start..<end])))
        }
        return out
    }

    private static func matchesWordPattern(_ text: String, wordPattern: String?) -> Bool {
        guard let wordPattern = wordPattern?.trimmingCharacters(in: .whitespacesAndNewlines),
              wordPattern.isEmpty == false
        else {
            return true
        }
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else {
            return true
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return false
        }
        return match.range.location == 0 && match.range.length == range.length
    }
}
