import Foundation

enum AttoLspSelectionRangeParser {
    struct Candidate: Equatable {
        let start: UInt32
        let end: UInt32
    }

    static func candidates(fromResultJSON json: String, documentText: String) -> [Candidate] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return []
        }

        let roots: [Any]
        if let array = root as? [Any] {
            roots = array
        } else if root is NSNull {
            roots = []
        } else {
            roots = [root]
        }

        var out: [Candidate] = []
        var seen = Set<String>()
        for root in roots {
            appendCandidates(from: root, documentText: documentText, into: &out, seen: &seen)
        }
        return out
    }

    static func nextCandidate(
        from candidates: [Candidate],
        currentStart: UInt32,
        currentEnd: UInt32
    ) -> Candidate? {
        let start = min(currentStart, currentEnd)
        let end = max(currentStart, currentEnd)

        return candidates.first { candidate in
            candidate.start <= start &&
            candidate.end >= end &&
            (candidate.start < start || candidate.end > end)
        }
    }

    private static func appendCandidates(
        from any: Any,
        documentText: String,
        into out: inout [Candidate],
        seen: inout Set<String>
    ) {
        guard let dict = any as? [String: Any] else { return }

        if let candidate = candidate(from: dict["range"], documentText: documentText) {
            let key = "\(candidate.start):\(candidate.end)"
            if seen.insert(key).inserted {
                out.append(candidate)
            }
        }

        if let parent = dict["parent"], !(parent is NSNull) {
            appendCandidates(from: parent, documentText: documentText, into: &out, seen: &seen)
        }
    }

    private static func candidate(from any: Any?, documentText: String) -> Candidate? {
        guard let range = any as? [String: Any],
              let start = range["start"] as? [String: Any],
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

        return Candidate(start: min(startOffset, endOffset), end: max(startOffset, endOffset))
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }
}
