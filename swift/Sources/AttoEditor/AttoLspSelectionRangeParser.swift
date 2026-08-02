import EditorCoreUIFFI
import Foundation

enum AttoLspSelectionRangeParser {
    struct Candidate: Equatable {
        let start: UInt32
        let end: UInt32
    }

    static func candidates(fromResultJSON json: String, documentText: String) -> [Candidate] {
        let roots = resultRoots(fromResultJSON: json)
        var out: [Candidate] = []
        var seen = Set<String>()
        for root in roots {
            appendCandidates(from: root, documentText: documentText, into: &out, seen: &seen)
        }
        return out
    }

    static func candidates(from result: EcuLspSelectionRangeResult, documentText: String) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        for root in result.roots {
            appendCandidates(from: root, documentText: documentText, into: &out, seen: &seen)
        }
        return out
    }

    static func candidateChains(fromResultJSON json: String, documentText: String) -> [[Candidate]] {
        resultRoots(fromResultJSON: json).map { root in
            var out: [Candidate] = []
            var seen = Set<String>()
            appendCandidates(from: root, documentText: documentText, into: &out, seen: &seen)
            return out
        }
    }

    static func candidateChains(from result: EcuLspSelectionRangeResult, documentText: String) -> [[Candidate]] {
        result.roots.map { root in
            var out: [Candidate] = []
            var seen = Set<String>()
            appendCandidates(from: root, documentText: documentText, into: &out, seen: &seen)
            return out
        }
    }

    private static func resultRoots(fromResultJSON json: String) -> [Any] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return []
        }

        if let array = root as? [Any] {
            return array
        }
        if root is NSNull {
            return []
        }
        return [root]
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

    private static func appendCandidates(
        from selectionRange: EcuLspSelectionRange,
        documentText: String,
        into out: inout [Candidate],
        seen: inout Set<String>
    ) {
        let candidate = candidate(from: selectionRange.range, documentText: documentText)
        let key = "\(candidate.start):\(candidate.end)"
        if seen.insert(key).inserted {
            out.append(candidate)
        }

        if let parent = selectionRange.parent {
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

    private static func candidate(from range: EcuLspRange, documentText: String) -> Candidate {
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

        return Candidate(start: min(startOffset, endOffset), end: max(startOffset, endOffset))
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }
}
