import Foundation

enum AttoSublimeSyntax {
    static func findSyntaxPath(
        for fileURL: URL,
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let ext = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ext.isEmpty { return nil }

        let candidates = candidateFilenames(forExtension: ext)
        if candidates.isEmpty { return nil }

        var searchDirs: [URL] = []

        // 1) Same directory as the file (most local override).
        searchDirs.append(fileURL.deletingLastPathComponent())
        // 2) Workspace root (project-level config).
        searchDirs.append(workspaceRootURL)

        // 3) App support config dir: `~/Library/Application Support/codes.unwritten.attoeditor/sublime/`.
        if let paths = try? AttoTreeSitterRegistry.defaultPaths(fileManager: fileManager) {
            let sublimeRoot = paths.configRoot.appendingPathComponent("sublime", isDirectory: true)
            // Best-effort: create directory so users can discover the convention.
            try? fileManager.createDirectory(at: sublimeRoot, withIntermediateDirectories: true)
            searchDirs.append(sublimeRoot)
        }

        // 4) Optional override via env.
        if let root = ProcessInfo.processInfo.environment["ATTO_EDITOR_SUBLIME_ROOT"]
            ?? ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_SUBLIME_ROOT"],
           root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            let url = URL(fileURLWithPath: root, isDirectory: true)
            searchDirs.append(url)
        }

        for dir in searchDirs {
            for filename in candidates {
                let path = dir.appendingPathComponent(filename, isDirectory: false).path
                if fileManager.fileExists(atPath: path) {
                    return path
                }
            }
        }

        return nil
    }

    private static func candidateFilenames(forExtension ext: String) -> [String] {
        let ext = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ext.isEmpty { return [] }

        // Keep parity with the TUI demo defaults where possible.
        switch ext {
        case "rs":
            return ["Rust.sublime-syntax"]
        case "toml":
            return ["TOML.sublime-syntax"]
        case "json":
            return ["JSON.sublime-syntax"]
        case "ini", "conf":
            return ["INI.sublime-syntax"]
        case "md", "markdown":
            return ["Markdown.sublime-syntax"]
        default:
            break
        }

        let cap = ext.prefix(1).uppercased() + ext.dropFirst()
        let raw: [String] = [
            "\(ext).sublime-syntax",
            "\(ext.uppercased()).sublime-syntax",
            "\(cap).sublime-syntax",
        ]

        // De-dupe while preserving order.
        var out: [String] = []
        var seen: Set<String> = []
        for s in raw {
            if seen.contains(s) { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }
}

