import Foundation

enum AttoFindInFilesSearchEngine {
    nonisolated static func filteredWorkspaceFiles(
        _ files: [URL],
        rootURL: URL,
        includeGlobs: [String],
        excludeGlobs: [String]
    ) -> [URL] {
        guard includeGlobs.isEmpty == false || excludeGlobs.isEmpty == false else {
            return files
        }

        return files.filter { url in
            let relativePath = relativePathForDisplay(url, rootURL: rootURL)
            return isWorkspaceSearchPathIncluded(
                relativePath,
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs
            )
        }
    }

    nonisolated static func isWorkspaceSearchPathIncluded(
        _ relativePath: String,
        includeGlobs: [String],
        excludeGlobs: [String]
    ) -> Bool {
        let path = relativePath.replacingOccurrences(of: "\\", with: "/")
        let include = normalizedGlobPatterns(includeGlobs)
        let exclude = normalizedGlobPatterns(excludeGlobs)

        let included = include.isEmpty || include.contains { globMatches(path: path, pattern: $0) }
        guard included else { return false }
        return exclude.contains { globMatches(path: path, pattern: $0) } == false
    }

    nonisolated static func normalizedGlobPatterns(_ patterns: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for pattern in patterns {
            var normalized = pattern
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/")
            while normalized.contains("//") {
                normalized = normalized.replacingOccurrences(of: "//", with: "/")
            }
            if normalized.hasPrefix("./") {
                normalized.removeFirst(2)
            }
            if normalized.hasSuffix("/") {
                normalized.append("**")
            }
            guard normalized.isEmpty == false else { continue }
            guard seen.insert(normalized).inserted else { continue }
            out.append(normalized)
        }
        return out
    }

    nonisolated static func search(
        query: String,
        options: AttoFindInFilesViewController.SearchOptions,
        inFiles files: [URL]
    ) -> [AttoFindInFilesViewController.SearchResult] {
        var out: [AttoFindInFilesViewController.SearchResult] = []
        out.reserveCapacity(128)

        let maxResults = 2000
        for url in files {
            if out.count >= maxResults { break }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, lineSub) in lines.enumerated() {
                if out.count >= maxResults { break }

                let line = String(lineSub)
                guard let range = firstSearchRange(
                    query: query,
                    options: options,
                    in: line
                ) else {
                    continue
                }

                let col1 = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let preview = trimmed.count > 240 ? String(trimmed.prefix(240)) + "…" : trimmed
                out.append(
                    AttoFindInFilesViewController.SearchResult(
                        url: url.standardizedFileURL,
                        line1: idx + 1,
                        column1: col1,
                        lineText: preview
                    )
                )
            }
        }

        out.sort { a, b in
            if a.url.path != b.url.path { return a.url.path < b.url.path }
            if a.line1 != b.line1 { return a.line1 < b.line1 }
            return a.column1 < b.column1
        }
        return out
    }

    nonisolated private static func globMatches(path: String, pattern: String) -> Bool {
        let candidates: [String]
        if pattern.contains("/") {
            candidates = [path]
        } else {
            candidates = path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
        }

        return candidates.contains { candidate in
            guard let regex = try? NSRegularExpression(
                pattern: globRegex(pattern),
                options: [.caseInsensitive]
            ) else {
                return false
            }
            let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            return regex.firstMatch(in: candidate, options: [], range: range) != nil
        }
    }

    nonisolated private static func globRegex(_ pattern: String) -> String {
        var out = "^"
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let char = pattern[index]
            let next = pattern.index(after: index)

            if char == "*" {
                if next < pattern.endIndex, pattern[next] == "*" {
                    let afterDoubleStar = pattern.index(after: next)
                    if afterDoubleStar < pattern.endIndex, pattern[afterDoubleStar] == "/" {
                        out += "(?:.*/)?"
                        index = pattern.index(after: afterDoubleStar)
                    } else {
                        out += ".*"
                        index = afterDoubleStar
                    }
                } else {
                    out += "[^/]*"
                    index = next
                }
                continue
            }

            if char == "?" {
                out += "[^/]"
                index = next
                continue
            }

            out += NSRegularExpression.escapedPattern(for: String(char))
            index = next
        }

        out += "$"
        return out
    }

    nonisolated private static func firstSearchRange(
        query: String,
        options: AttoFindInFilesViewController.SearchOptions,
        in line: String
    ) -> Range<String.Index>? {
        if options.regex {
            let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: query, options: regexOptions) else {
                return nil
            }
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in regex.matches(in: line, options: [], range: nsRange) {
                guard let range = Range(match.range, in: line), range.isEmpty == false else {
                    continue
                }
                if options.wholeWord == false || isWholeWordRange(range, in: line) {
                    return range
                }
            }
            return nil
        }

        let compareOptions: String.CompareOptions = options.caseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive]
        var searchRange = line.startIndex..<line.endIndex
        while let range = line.range(of: query, options: compareOptions, range: searchRange) {
            if options.wholeWord == false || isWholeWordRange(range, in: line) {
                return range
            }
            guard range.upperBound < line.endIndex else { return nil }
            searchRange = range.upperBound..<line.endIndex
        }
        return nil
    }

    nonisolated private static func isWholeWordRange(_ range: Range<String.Index>, in line: String) -> Bool {
        guard range.isEmpty == false else { return false }
        if range.lowerBound > line.startIndex {
            let before = line[line.index(before: range.lowerBound)]
            if isSearchWordCharacter(before) {
                return false
            }
        }
        if range.upperBound < line.endIndex {
            let after = line[range.upperBound]
            if isSearchWordCharacter(after) {
                return false
            }
        }
        return true
    }

    nonisolated private static func isSearchWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    nonisolated private static func relativePathForDisplay(_ url: URL, rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == root {
            return url.lastPathComponent
        }
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}
