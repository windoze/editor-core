import EditorCoreUIFFI
import Foundation

/// Project LSP process health 的持久化 I/O 层。
///
/// 这是 App 级日志桥接：workspace root 只作为 core/project 身份元数据写入记录，
/// 不在 Swift 侧新建 workspace ownership。
struct AttoProjectLspProcessHealthLogEntry: Codable, Equatable {
    struct Process: Codable, Equatable {
        let pid: UInt32?
        let state: String
        let exitCode: Int32?
        let signal: Int32?
        let stderrTail: String?
    }

    let recordedAt: Date
    let workspaceRootURI: String
    let sequence: UInt64
    let sourceSequence: UInt64
    let tabId: UInt64?
    let viewIndex: Int?
    let viewId: UInt64?
    let serverName: String?
    let serverCommand: String?
    let availability: String
    let state: String
    let detail: String?
    let process: Process
}

struct AttoProjectLspProcessHealthLogStore: Sendable {
    let logFileURL: URL
    let maxPersistedEntries: Int

    init(
        logFileURL: URL = AttoProjectLspProcessHealthLogStore.defaultLogFileURL(),
        maxPersistedEntries: Int = 2_000
    ) {
        self.logFileURL = logFileURL
        self.maxPersistedEntries = max(1, maxPersistedEntries)
    }

    static func defaultLogFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport: URL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("lsp-process-health.jsonl", isDirectory: false)
    }

    func append(
        event: AttoProjectLspProcessHealthEvent,
        workspaceRootURL: URL,
        recordedAt: Date = Date(),
        fileManager: FileManager = .default
    ) throws {
        let entry = AttoProjectLspProcessHealthLogEntry(
            recordedAt: recordedAt,
            workspaceRootURI: workspaceRootURL.standardizedFileURL.absoluteString,
            sequence: event.sequence,
            sourceSequence: event.sourceSequence,
            tabId: event.tabId,
            viewIndex: event.viewIndex,
            viewId: event.viewId,
            serverName: event.serverName,
            serverCommand: event.serverCommand,
            availability: event.availability,
            state: event.state,
            detail: event.detail,
            process: AttoProjectLspProcessHealthLogEntry.Process(
                pid: event.process.pid,
                state: event.process.state.rawValue,
                exitCode: event.process.exitCode,
                signal: event.process.signal,
                stderrTail: event.process.stderrTail
            )
        )
        try append(entry: entry, fileManager: fileManager)
    }

    func append(
        entry: AttoProjectLspProcessHealthLogEntry,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let line = String(decoding: try encoder.encode(entry), as: UTF8.self)

        if fileManager.fileExists(atPath: logFileURL.path) {
            let existingData = try Data(contentsOf: logFileURL)
            let existingText = String(data: existingData, encoding: .utf8) ?? ""
            var lines = existingText.split(whereSeparator: \.isNewline).map(String.init)
            lines.append(line)
            lines = retainLatestEntriesPerWorkspace(lines)
            let output = lines.joined(separator: "\n") + "\n"
            try output.write(to: logFileURL, atomically: true, encoding: .utf8)
        } else {
            try (line + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }

    func loadRecent(
        workspaceRootURL: URL,
        limit: Int,
        fileManager: FileManager = .default
    ) -> [AttoProjectLspProcessHealthLogEntry] {
        guard limit > 0,
              fileManager.fileExists(atPath: logFileURL.path),
              let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let rootURI = workspaceRootURL.standardizedFileURL.absoluteString
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [AttoProjectLspProcessHealthLogEntry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(AttoProjectLspProcessHealthLogEntry.self, from: lineData),
                  entry.workspaceRootURI == rootURI
            else {
                continue
            }
            entries.append(entry)
        }
        if entries.count > limit {
            return Array(entries.suffix(limit))
        }
        return entries
    }

    func exportJSONL(
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        let lines = try matchingJSONLLines(workspaceRootURL: workspaceRootURL, fileManager: fileManager)
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    func exportJSONL(
        workspaceRootURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let lines = try matchingJSONLLines(workspaceRootURL: workspaceRootURL, fileManager: fileManager)
        guard lines.isEmpty == false else {
            return 0
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let output = lines.joined(separator: "\n") + "\n"
        try output.write(to: destinationURL, atomically: true, encoding: .utf8)
        return lines.count
    }

    @discardableResult
    func clear(
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        guard fileManager.fileExists(atPath: logFileURL.path) else {
            return 0
        }

        let rootURI = workspaceRootURL.standardizedFileURL.absoluteString
        let data = try Data(contentsOf: logFileURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var keptLines: [String] = []
        var removedCount = 0
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(AttoProjectLspProcessHealthLogEntry.self, from: lineData)
            else {
                keptLines.append(line)
                continue
            }

            if entry.workspaceRootURI == rootURI {
                removedCount += 1
            } else {
                keptLines.append(line)
            }
        }

        guard removedCount > 0 else {
            return 0
        }

        let output = keptLines.isEmpty ? "" : keptLines.joined(separator: "\n") + "\n"
        try output.write(to: logFileURL, atomically: true, encoding: .utf8)
        return removedCount
    }

    private func matchingJSONLLines(
        workspaceRootURL: URL,
        fileManager: FileManager
    ) throws -> [String] {
        guard fileManager.fileExists(atPath: logFileURL.path) else {
            return []
        }

        let rootURI = workspaceRootURL.standardizedFileURL.absoluteString
        let data = try Data(contentsOf: logFileURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let rawLine = String(line)
            guard let lineData = rawLine.data(using: .utf8),
                  let entry = try? decoder.decode(AttoProjectLspProcessHealthLogEntry.self, from: lineData),
                  entry.workspaceRootURI == rootURI
            else {
                return nil
            }
            return rawLine
        }
    }

    private func retainLatestEntriesPerWorkspace(_ lines: [String]) -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var countsByWorkspace: [String: Int] = [:]
        var keptReversed: [String] = []
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(AttoProjectLspProcessHealthLogEntry.self, from: lineData)
            else {
                keptReversed.append(line)
                continue
            }

            let count = countsByWorkspace[entry.workspaceRootURI, default: 0]
            guard count < maxPersistedEntries else {
                continue
            }
            countsByWorkspace[entry.workspaceRootURI] = count + 1
            keptReversed.append(line)
        }
        return keptReversed.reversed()
    }
}
