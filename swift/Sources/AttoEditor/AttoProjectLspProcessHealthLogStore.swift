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

    init(
        logFileURL: URL = AttoProjectLspProcessHealthLogStore.defaultLogFileURL()
    ) {
        self.logFileURL = logFileURL
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
        var line = try encoder.encode(entry)
        line.append(0x0A)

        if fileManager.fileExists(atPath: logFileURL.path) {
            var data = try Data(contentsOf: logFileURL)
            data.append(line)
            try data.write(to: logFileURL, options: [.atomic])
        } else {
            try line.write(to: logFileURL, options: [.atomic])
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
}
