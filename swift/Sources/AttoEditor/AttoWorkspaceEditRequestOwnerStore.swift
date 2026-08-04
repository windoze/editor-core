import Foundation

struct AttoWorkspaceEditRequestOwnerRecord: Codable, Equatable {
    let recordedAt: Date
    let workspaceRootURI: String
    let transactionSequence: UInt64
    let workspaceEditJSON: String?
    let descriptor: AttoWorkspaceEditRequestRetryDescriptor

    private enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
        case workspaceRootURI = "workspace_root_uri"
        case transactionSequence = "transaction_sequence"
        case workspaceEditJSON = "workspace_edit_json"
        case descriptor
    }
}

struct AttoWorkspaceEditRequestOwnerStore: Sendable {
    let logFileURL: URL
    let maxPersistedEntries: Int
    let maxLogFileBytes: Int

    init(
        logFileURL: URL = AttoWorkspaceEditRequestOwnerStore.defaultLogFileURL(),
        maxPersistedEntries: Int = 256,
        maxLogFileBytes: Int = 1 * 1024 * 1024
    ) {
        self.logFileURL = logFileURL
        self.maxPersistedEntries = max(1, maxPersistedEntries)
        self.maxLogFileBytes = max(1, maxLogFileBytes)
    }

    static func defaultLogFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport: URL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )

        return appSupport
            .appendingPathComponent("codes.unwritten.attoeditor", isDirectory: true)
            .appendingPathComponent("workspace-edit-request-owners.jsonl", isDirectory: false)
    }

    func append(
        record: AttoWorkspaceEditRequestOwnerRecord,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let line = String(decoding: try encoder.encode(record), as: UTF8.self)
        var lines = readLines(fileManager: fileManager)
        lines.append(line)
        lines = prunedLogLines(lines)
        let output = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try output.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    func loadRecent(
        workspaceRootURL: URL,
        limit: Int,
        fileManager: FileManager = .default
    ) -> [AttoWorkspaceEditRequestOwnerRecord] {
        guard limit > 0 else { return [] }
        let rootURI = workspaceRootURL.standardizedFileURL.absoluteString
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let records = readLines(fileManager: fileManager).compactMap { line -> AttoWorkspaceEditRequestOwnerRecord? in
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(AttoWorkspaceEditRequestOwnerRecord.self, from: data),
                  record.workspaceRootURI == rootURI
            else {
                return nil
            }
            return record
        }

        if records.count > limit {
            return Array(records.suffix(limit))
        }
        return records
    }

    private func readLines(fileManager: FileManager) -> [String] {
        guard fileManager.fileExists(atPath: logFileURL.path),
              let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func prunedLogLines(_ lines: [String]) -> [String] {
        let countPruned = retainLatestEntriesPerWorkspace(lines)
        return retainLinesWithinByteBudget(countPruned)
    }

    private func retainLatestEntriesPerWorkspace(_ lines: [String]) -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var countsByWorkspace: [String: Int] = [:]
        var keptReversed: [String] = []
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(AttoWorkspaceEditRequestOwnerRecord.self, from: data)
            else {
                keptReversed.append(line)
                continue
            }

            let count = countsByWorkspace[record.workspaceRootURI, default: 0]
            guard count < maxPersistedEntries else { continue }
            countsByWorkspace[record.workspaceRootURI] = count + 1
            keptReversed.append(line)
        }
        return keptReversed.reversed()
    }

    private func retainLinesWithinByteBudget(_ lines: [String]) -> [String] {
        var keptReversed: [String] = []
        var totalBytes = 0
        for line in lines.reversed() {
            let lineBytes = line.utf8.count + 1
            if totalBytes > 0, totalBytes + lineBytes > maxLogFileBytes {
                break
            }
            totalBytes += lineBytes
            keptReversed.append(line)
        }
        return keptReversed.reversed()
    }
}
