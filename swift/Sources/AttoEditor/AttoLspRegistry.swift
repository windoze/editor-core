import Foundation

enum AttoLspRegistry {
    struct ServerConfig: Equatable, Sendable {
        let command: String
        let args: String?
        let languageId: String?
    }

    static func defaultServersFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport: URL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        let configRoot = appSupport.appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
        let lspDir = configRoot.appendingPathComponent("lsp", isDirectory: true)
        return lspDir.appendingPathComponent("servers.json", isDirectory: false)
    }

    static func loadServerMap(
        fileManager: FileManager = .default
    ) -> [String: ServerConfig] {
        let url = defaultServersFileURL(fileManager: fileManager)
        return loadServerMap(from: url, fileManager: fileManager)
    }

    static func loadServerMap(
        from url: URL,
        fileManager: FileManager = .default
    ) -> [String: ServerConfig] {
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            return try parseServersJSON(data)
        } catch {
            NSLog(
                "AttoEditor: failed to load LSP servers.json (path=%@): %@",
                url.path,
                String(describing: error)
            )

            return [:]
        }
    }

    static func parseServersJSON(_ data: Data) throws -> [String: ServerConfig] {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            return [:]
        }

        // Accept either:
        // 1) { "schema_version": 1, "extension_map": { ... } }
        // 2) { "rs": "rust-analyzer", "py": { ... } } (legacy / minimal form)
        let schemaVersion: Int? = {
            if let n = dict["schema_version"] as? Int { return n }
            if let n = dict["schema_version"] as? NSNumber { return n.intValue }
            return nil
        }()

        if let schemaVersion, schemaVersion != 1 {
            return [:]
        }

        let mapValue: Any = dict["extension_map"] ?? dict
        guard let mapDict = mapValue as? [String: Any] else {
            return [:]
        }

        var out: [String: ServerConfig] = [:]
        for (rawExt, rawValue) in mapDict {
            guard let ext = normalizeExtensionKey(rawExt) else { continue }

            // Allow explicit disable: "rs": null
            if rawValue is NSNull {
                out.removeValue(forKey: ext)
                continue
            }

            guard let entry = parseServerEntry(rawValue) else { continue }
            out[ext] = entry
        }

        return out
    }

    private static func parseServerEntry(_ value: Any) -> ServerConfig? {
        if let cmd = value as? String {
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return ServerConfig(command: trimmed, args: nil, languageId: nil)
        }

        guard let dict = value as? [String: Any] else {
            return nil
        }

        let command: String? = {
            if let s = dict["command"] as? String { return s }
            if let s = dict["cmd"] as? String { return s }
            return nil
        }()

        guard let command else { return nil }
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cmd.isEmpty == false else { return nil }

        let args: String? = {
            if let s = dict["args"] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return nil
        }()

        let languageIdRaw: String? = {
            if let s = dict["language_id"] as? String { return s }
            if let s = dict["languageId"] as? String { return s }
            return nil
        }()

        let languageId = languageIdRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = (languageId?.isEmpty == false) ? languageId : nil

        return ServerConfig(command: cmd, args: args, languageId: lang)
    }

    private static func normalizeExtensionKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let noDot = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
        let ext = noDot.lowercased()
        return ext.isEmpty ? nil : ext
    }
}
