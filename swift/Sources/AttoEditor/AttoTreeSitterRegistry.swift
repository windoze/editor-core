import Foundation

enum AttoTreeSitterRegistry {
    struct Paths {
        let configRoot: URL
        let treesitterRoot: URL
    }

    static func defaultPaths(fileManager: FileManager = .default) throws -> Paths {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let configRoot = appSupport.appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
        let treesitterRoot = configRoot.appendingPathComponent("treesitter", isDirectory: true)

        try fileManager.createDirectory(at: configRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: treesitterRoot, withIntermediateDirectories: true)

        return Paths(configRoot: configRoot, treesitterRoot: treesitterRoot)
    }

    static func buildRegistryJSON(
        treesitterRoot: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        // If the user has provided a full schema-versioned registry JSON on disk, prefer it.
        //
        // This is the most flexible path (custom filenames, non-conventional layouts, etc.).
        // We still rewrite `root_dir` so relative paths resolve against the actual on-disk root.
        if let userRegistryJSON = loadUserRegistryJSONIfPresent(
            treesitterRoot: treesitterRoot,
            fileManager: fileManager
        ) {
            return userRegistryJSON
        }

        let languages = try scanLanguages(treesitterRoot: treesitterRoot, fileManager: fileManager)
        let extensionMap = loadExtensionMap(
            treesitterRoot: treesitterRoot,
            availableLanguages: Set(languages.keys),
            fileManager: fileManager
        )

        let obj: [String: Any] = [
            "schema_version": 1,
            "root_dir": treesitterRoot.path,
            "extension_map": extensionMap,
            "languages": languages,
        ]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AttoTreeSitterRegistry", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "failed to encode registry json as utf-8",
            ])
        }
        return json
    }

    private static func loadUserRegistryJSONIfPresent(
        treesitterRoot: URL,
        fileManager: FileManager
    ) -> String? {
        let registryURL = treesitterRoot.appendingPathComponent("registry.json", isDirectory: false)
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: registryURL),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              var dict = obj as? [String: Any]
        else {
            return nil
        }

        // Detect a full schema-versioned registry.
        //
        // Note: An extension override map is a plain `{ "rs": "rust" }` dictionary; it will not
        // include `schema_version` or `languages`.
        let schemaVersion: Int? = {
            if let n = dict["schema_version"] as? Int {
                return n
            }
            if let n = dict["schema_version"] as? NSNumber {
                return n.intValue
            }
            return nil
        }()

        guard schemaVersion == 1, dict["languages"] != nil else {
            return nil
        }

        dict["root_dir"] = treesitterRoot.path

        guard JSONSerialization.isValidJSONObject(dict),
              let outData = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let out = String(data: outData, encoding: .utf8)
        else {
            return nil
        }

        return out
    }

    private static func scanLanguages(
        treesitterRoot: URL,
        fileManager: FileManager
    ) throws -> [String: [String: String]] {
        let entries = try fileManager.contentsOfDirectory(
            at: treesitterRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var out: [String: [String: String]] = [:]
        for url in entries {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let languageId = url.lastPathComponent
            if languageId.isEmpty { continue }

            guard let wasmURL = resolveWasmURL(languageDir: url, languageId: languageId, fileManager: fileManager),
                  let highlightsURL = resolveQueryURL(languageDir: url, queryFileName: "highlights.scm", fileManager: fileManager),
                  let wasmRel = makeRelativeLanguagePath(languageId: languageId, languageDir: url, fileURL: wasmURL),
                  let highlightsRel = makeRelativeLanguagePath(languageId: languageId, languageDir: url, fileURL: highlightsURL)
            else {
                continue
            }

            var entry: [String: String] = [
                "wasm": wasmRel,
                "highlights": highlightsRel,
            ]

            if let foldsURL = resolveQueryURL(languageDir: url, queryFileName: "folds.scm", fileManager: fileManager),
               let foldsRel = makeRelativeLanguagePath(languageId: languageId, languageDir: url, fileURL: foldsURL)
            {
                entry["folds"] = foldsRel
            }

            if let tagsURL = resolveQueryURL(languageDir: url, queryFileName: "tags.scm", fileManager: fileManager),
               let tagsRel = makeRelativeLanguagePath(languageId: languageId, languageDir: url, fileURL: tagsURL)
            {
                entry["tags"] = tagsRel
            }

            if let injectionsURL = resolveQueryURL(languageDir: url, queryFileName: "injections.scm", fileManager: fileManager),
               let injectionsRel = makeRelativeLanguagePath(languageId: languageId, languageDir: url, fileURL: injectionsURL)
            {
                entry["injections"] = injectionsRel
            }

            out[languageId] = entry
        }

        return out
    }

    private static func loadExtensionMap(
        treesitterRoot: URL,
        availableLanguages: Set<String>,
        fileManager: FileManager
    ) -> [String: String] {
        var out: [String: String] = [:]

        // Optional overrides.
        let registryJSON = treesitterRoot.appendingPathComponent("registry.json", isDirectory: false)
        if fileManager.fileExists(atPath: registryJSON.path) {
            // Best-effort: ignore parse errors and keep going with defaults.
            do {
                let data = try Data(contentsOf: registryJSON)
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = obj as? [String: String] {
                    out.merge(dict) { _, new in new }
                }
            } catch {
                // ignore
            }
        }

        // Minimal defaults for AttoEditor MVP.
        if availableLanguages.contains("rust"), out["rs"] == nil {
            out["rs"] = "rust"
        }
        if availableLanguages.contains("swift"), out["swift"] == nil {
            out["swift"] = "swift"
        }

        // Default convention: treat `<language_id>/` as `<extension> -> <language_id>`.
        //
        // This makes dropping a folder like `treesitter/rusk/` immediately work for `.rusk` files,
        // while still allowing explicit overrides via `registry.json`.
        for languageId in availableLanguages {
            let key = languageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty { continue }
            if out[key] == nil {
                out[key] = languageId
            }
        }

        return out
    }

    private static func resolveWasmURL(
        languageDir: URL,
        languageId: String,
        fileManager: FileManager
    ) -> URL? {
        let preferred: [URL] = [
            languageDir.appendingPathComponent("language.wasm", isDirectory: false),
            languageDir.appendingPathComponent("\(languageId).wasm", isDirectory: false),
            languageDir.appendingPathComponent("tree-sitter-\(languageId).wasm", isDirectory: false),
        ]
        for url in preferred {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        // Fallback: if there's exactly one `.wasm` file in the directory, use it.
        guard let entries = try? fileManager.contentsOfDirectory(
            at: languageDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let wasmFiles = entries.filter { url in
            guard url.pathExtension.lowercased() == "wasm" else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
        if wasmFiles.count == 1 {
            return wasmFiles[0]
        }

        return nil
    }

    private static func resolveQueryURL(
        languageDir: URL,
        queryFileName: String,
        fileManager: FileManager
    ) -> URL? {
        let rootCandidate = languageDir.appendingPathComponent(queryFileName, isDirectory: false)
        if fileManager.fileExists(atPath: rootCandidate.path) {
            return rootCandidate
        }

        let queriesCandidate = languageDir
            .appendingPathComponent("queries", isDirectory: true)
            .appendingPathComponent(queryFileName, isDirectory: false)
        if fileManager.fileExists(atPath: queriesCandidate.path) {
            return queriesCandidate
        }

        return nil
    }

    private static func makeRelativeLanguagePath(
        languageId: String,
        languageDir: URL,
        fileURL: URL
    ) -> String? {
        let base = languageDir.path
        let full = fileURL.path
        guard full.hasPrefix(base + "/") else {
            return nil
        }
        let suffixStart = full.index(full.startIndex, offsetBy: base.count + 1)
        let suffix = String(full[suffixStart...])
        if suffix.isEmpty { return nil }
        return "\(languageId)/\(suffix)"
    }
}
