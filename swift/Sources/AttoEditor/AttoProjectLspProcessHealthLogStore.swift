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

struct AttoProjectLspProcessHealthLogFilter: Equatable {
    private enum Predicate: Equatable {
        case text(String)
        case server(String)
        case availability(String)
        case state(String)
        case process(String)
        case pid(String)
        case exitCode(String)
        case signal(String)
        case detail(String)
        case stderr(String)
        case tab(String)
        case view(String)
        case since(Date?)
        case until(Date?)
    }

    private let predicates: [Predicate]

    init(query: String) {
        predicates = query
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Self.predicate(for: String($0)) }
    }

    var isEmpty: Bool {
        predicates.isEmpty
    }

    func matches(_ entry: AttoProjectLspProcessHealthLogEntry) -> Bool {
        predicates.allSatisfy { predicate in
            switch predicate {
            case .text(let value):
                return searchableText(entry).contains(value)
            case .server(let value):
                return contains(entry.serverName, value) || contains(entry.serverCommand, value)
            case .availability(let value):
                return contains(entry.availability, value)
            case .state(let value):
                return contains(entry.state, value)
            case .process(let value):
                return contains(entry.process.state, value)
            case .pid(let value):
                return numericMatches(entry.process.pid.map(String.init), value)
            case .exitCode(let value):
                return numericMatches(entry.process.exitCode.map(String.init), value)
            case .signal(let value):
                return numericMatches(entry.process.signal.map(String.init), value)
            case .detail(let value):
                return contains(entry.detail, value)
            case .stderr(let value):
                return contains(entry.process.stderrTail, value)
            case .tab(let value):
                return numericMatches(entry.tabId.map(String.init), value)
            case .view(let value):
                let viewOrdinal = entry.viewIndex.map { String($0 + 1) }
                return numericMatches(viewOrdinal, value) || numericMatches(entry.viewId.map(String.init), value)
            case .since(let date):
                guard let date else { return false }
                return entry.recordedAt >= date
            case .until(let date):
                guard let date else { return false }
                return entry.recordedAt <= date
            }
        }
    }

    private static func predicate(for token: String) -> Predicate? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[1].isEmpty == false else {
            return .text(trimmed.lowercased())
        }

        let key = parts[0].lowercased()
        let value = parts[1].lowercased()
        switch key {
        case "server":
            return .server(value)
        case "availability":
            return .availability(value)
        case "state":
            return .state(value)
        case "process":
            return .process(value)
        case "pid":
            return .pid(value)
        case "exit", "exit_code", "exitcode":
            return .exitCode(value)
        case "signal":
            return .signal(value)
        case "detail":
            return .detail(value)
        case "stderr":
            return .stderr(value)
        case "tab":
            return .tab(value)
        case "view":
            return .view(value)
        case "since":
            return .since(parseDate(parts[1]))
        case "until":
            return .until(parseDate(parts[1]))
        default:
            return .text(trimmed.lowercased())
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        if let timestamp = TimeInterval(value) {
            return Date(timeIntervalSince1970: timestamp)
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: value)
    }

    private func searchableText(_ entry: AttoProjectLspProcessHealthLogEntry) -> String {
        [
            entry.serverName,
            entry.serverCommand,
            entry.availability,
            entry.state,
            entry.detail,
            entry.process.state,
            entry.process.pid.map(String.init),
            entry.process.exitCode.map(String.init),
            entry.process.signal.map(String.init),
            entry.process.stderrTail,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func contains(_ text: String?, _ value: String) -> Bool {
        text?.lowercased().contains(value) == true
    }

    private func numericMatches(_ text: String?, _ value: String) -> Bool {
        guard let text else { return false }
        if let expected = Int64(value), let actual = Int64(text) {
            return actual == expected
        }
        return text.lowercased().contains(value)
    }
}

struct AttoProjectLspProcessHealthLogStore: Sendable {
    let logFileURL: URL
    let maxPersistedEntries: Int
    let maxLogFileBytes: Int
    let maxEntryAge: TimeInterval?

    init(
        logFileURL: URL = AttoProjectLspProcessHealthLogStore.defaultLogFileURL(),
        maxPersistedEntries: Int = 2_000,
        maxLogFileBytes: Int = 4 * 1024 * 1024,
        maxEntryAge: TimeInterval? = 30 * 24 * 60 * 60
    ) {
        self.logFileURL = logFileURL
        self.maxPersistedEntries = max(1, maxPersistedEntries)
        self.maxLogFileBytes = max(1, maxLogFileBytes)
        self.maxEntryAge = maxEntryAge
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
            lines = prunedLogLines(lines)
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
        queryRecent(workspaceRootURL: workspaceRootURL, query: "", limit: limit, fileManager: fileManager)
    }

    func queryRecent(
        workspaceRootURL: URL,
        query: String,
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
        let filter = AttoProjectLspProcessHealthLogFilter(query: query)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [AttoProjectLspProcessHealthLogEntry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(AttoProjectLspProcessHealthLogEntry.self, from: lineData),
                  entry.workspaceRootURI == rootURI,
                  filter.isEmpty || filter.matches(entry)
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

    private func prunedLogLines(_ lines: [String]) -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let agePrunedLines = retainEntriesWithinAge(lines, decoder: decoder)
        let countPrunedLines = retainLatestEntriesPerWorkspace(agePrunedLines, decoder: decoder)
        return retainLinesWithinByteBudget(countPrunedLines)
    }

    private func retainEntriesWithinAge(_ lines: [String], decoder: JSONDecoder) -> [String] {
        guard let maxEntryAge, maxEntryAge > 0,
              let newestDate = latestRecordedAt(in: lines, decoder: decoder)
        else {
            return lines
        }

        let cutoff = newestDate.addingTimeInterval(-maxEntryAge)
        return lines.filter { line in
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(AttoProjectLspProcessHealthLogEntry.self, from: lineData)
            else {
                return true
            }
            return entry.recordedAt >= cutoff
        }
    }

    private func latestRecordedAt(in lines: [String], decoder: JSONDecoder) -> Date? {
        lines.compactMap { line in
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(AttoProjectLspProcessHealthLogEntry.self, from: lineData)
            else {
                return nil
            }
            return entry.recordedAt
        }.max()
    }

    private func retainLatestEntriesPerWorkspace(_ lines: [String], decoder: JSONDecoder) -> [String] {
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

    private func retainLinesWithinByteBudget(_ lines: [String]) -> [String] {
        var keptReversed: [String] = []
        var byteCount = 0
        for line in lines.reversed() {
            let lineBytes = line.lengthOfBytes(using: .utf8) + 1
            guard keptReversed.isEmpty || byteCount + lineBytes <= maxLogFileBytes else {
                continue
            }
            keptReversed.append(line)
            byteCount += lineBytes
        }
        return keptReversed.reversed()
    }
}
