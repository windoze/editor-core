import Foundation

/// Session 文件的纯 I/O 层（不依赖 AppKit，不触碰 UI 状态）。
struct AttoSessionStore: Sendable {
    let sessionFileURL: URL

    init(
        sessionFileURL: URL = AttoSessionStore.defaultSessionFileURL()
    ) {
        self.sessionFileURL = sessionFileURL
    }

    static func defaultSessionFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport: URL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        let configRoot = appSupport.appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
        return configRoot.appendingPathComponent("session.json", isDirectory: false)
    }

    func load(fileManager: FileManager = .default) -> AttoSessionSnapshot? {
        guard fileManager.fileExists(atPath: sessionFileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: sessionFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(AttoSessionSnapshot.self, from: data)

            guard snap.schemaVersion == AttoSessionSnapshot.currentSchemaVersion else {
                return nil
            }

            return snap
        } catch {
            // session 文件损坏或不兼容：保留副本，避免每次启动都反复失败。
            let suffix = AttoSessionStore.timestampSuffix()
            let backupURL = URL(fileURLWithPath: sessionFileURL.path + ".corrupt-\(suffix)")
            do {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.removeItem(at: backupURL)
                }
                try fileManager.moveItem(at: sessionFileURL, to: backupURL)
            } catch {
                // ignore
            }
            return nil
        }
    }

    func save(_ snapshot: AttoSessionSnapshot, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: sessionFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        try data.write(to: sessionFileURL, options: [.atomic])
    }

    private static func timestampSuffix(now: Date = Date()) -> String {
        // 用本地时区生成一个文件名安全的时间戳：yyyyMMdd-HHmmss
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now)
    }
}
