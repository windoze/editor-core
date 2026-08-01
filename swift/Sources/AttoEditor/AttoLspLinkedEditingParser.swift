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
        return Result(ranges: ranges, wordPattern: object["wordPattern"] as? String)
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

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }
}
