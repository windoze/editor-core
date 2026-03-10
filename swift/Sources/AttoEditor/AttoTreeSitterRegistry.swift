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
        let languages = try scanLanguages(treesitterRoot: treesitterRoot, fileManager: fileManager)
        let extensionMap = try loadExtensionMap(
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

            let wasm = url.appendingPathComponent("language.wasm", isDirectory: false)
            let highlights = url.appendingPathComponent("highlights.scm", isDirectory: false)
            guard fileManager.fileExists(atPath: wasm.path),
                  fileManager.fileExists(atPath: highlights.path)
            else { continue }

            var entry: [String: String] = [
                "wasm": "\(languageId)/language.wasm",
                "highlights": "\(languageId)/highlights.scm",
            ]

            let folds = url.appendingPathComponent("folds.scm", isDirectory: false)
            if fileManager.fileExists(atPath: folds.path) {
                entry["folds"] = "\(languageId)/folds.scm"
            }

            let tags = url.appendingPathComponent("tags.scm", isDirectory: false)
            if fileManager.fileExists(atPath: tags.path) {
                entry["tags"] = "\(languageId)/tags.scm"
            }

            let injections = url.appendingPathComponent("injections.scm", isDirectory: false)
            if fileManager.fileExists(atPath: injections.path) {
                entry["injections"] = "\(languageId)/injections.scm"
            }

            out[languageId] = entry
        }

        return out
    }

    private static func loadExtensionMap(
        treesitterRoot: URL,
        availableLanguages: Set<String>,
        fileManager: FileManager
    ) throws -> [String: String] {
        var out: [String: String] = [:]

        // Optional overrides.
        let registryJSON = treesitterRoot.appendingPathComponent("registry.json", isDirectory: false)
        if fileManager.fileExists(atPath: registryJSON.path) {
            let data = try Data(contentsOf: registryJSON)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            if let dict = obj as? [String: String] {
                out.merge(dict) { _, new in new }
            }
        }

        // Minimal defaults for AttoEditor MVP.
        if availableLanguages.contains("rust"), out["rs"] == nil {
            out["rs"] = "rust"
        }
        if availableLanguages.contains("swift"), out["swift"] == nil {
            out["swift"] = "swift"
        }

        return out
    }
}

