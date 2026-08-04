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
    struct ReconciliationEvent: Equatable, Sendable {
        let transactionSequence: UInt64
        let workspaceEditJSON: String?
    }

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
        let rootIdentities = Self.workspaceRootIdentities(
            workspaceRootURL: workspaceRootURL,
            workspaceRootURIs: []
        )

        let records = readRecords(fileManager: fileManager).filter { record in
            rootIdentities.contains(Self.workspaceRootIdentity(forURI: record.workspaceRootURI))
        }

        if records.count > limit {
            return Array(records.suffix(limit))
        }
        return records
    }

    func loadReconciled(
        workspaceRootURL: URL,
        workspaceRootURIs: [String] = [],
        events: [ReconciliationEvent],
        limit: Int,
        fileManager: FileManager = .default
    ) -> [AttoWorkspaceEditRequestOwnerRecord] {
        guard limit > 0, events.isEmpty == false else { return [] }
        let rootIdentities = Self.workspaceRootIdentities(
            workspaceRootURL: workspaceRootURL,
            workspaceRootURIs: workspaceRootURIs
        )
        var eventsBySequence: [UInt64: ReconciliationEvent] = [:]
        for event in events {
            eventsBySequence[event.transactionSequence] = event
        }

        var latestRecordBySequence: [UInt64: AttoWorkspaceEditRequestOwnerRecord] = [:]
        var sequenceOrder: [UInt64] = []
        for record in readRecords(fileManager: fileManager) {
            guard rootIdentities.contains(Self.workspaceRootIdentity(forURI: record.workspaceRootURI)),
                  let event = eventsBySequence[record.transactionSequence],
                  Self.record(record, matches: event)
            else {
                continue
            }

            if latestRecordBySequence[record.transactionSequence] != nil {
                sequenceOrder.removeAll { $0 == record.transactionSequence }
            }
            latestRecordBySequence[record.transactionSequence] = record
            sequenceOrder.append(record.transactionSequence)
        }

        let records = sequenceOrder.compactMap { latestRecordBySequence[$0] }
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

    private func readRecords(fileManager: FileManager) -> [AttoWorkspaceEditRequestOwnerRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return readLines(fileManager: fileManager).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(AttoWorkspaceEditRequestOwnerRecord.self, from: data)
        }
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

            let workspaceIdentity = Self.workspaceRootIdentity(forURI: record.workspaceRootURI)
            let count = countsByWorkspace[workspaceIdentity, default: 0]
            guard count < maxPersistedEntries else { continue }
            countsByWorkspace[workspaceIdentity] = count + 1
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

    private static func record(
        _ record: AttoWorkspaceEditRequestOwnerRecord,
        matches event: ReconciliationEvent
    ) -> Bool {
        guard let recordWorkspaceEditJSON = record.workspaceEditJSON else { return true }
        return recordWorkspaceEditJSON == event.workspaceEditJSON
    }

    private static func workspaceRootIdentities(
        workspaceRootURL: URL,
        workspaceRootURIs: [String]
    ) -> Set<String> {
        var identities: Set<String> = [workspaceRootIdentity(forURL: workspaceRootURL)]
        for uri in workspaceRootURIs {
            identities.insert(workspaceRootIdentity(forURI: uri))
        }
        return identities
    }

    private static func workspaceRootIdentity(forURL url: URL) -> String {
        normalizedFilePath(url)
    }

    private static func workspaceRootIdentity(forURI uri: String) -> String {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return trimmed }
        if let url = URL(string: trimmed), url.isFileURL {
            return normalizedFilePath(url)
        }
        if trimmed.hasPrefix("/") {
            return normalizedFilePath(URL(fileURLWithPath: trimmed, isDirectory: true))
        }
        return trimmed
    }

    private static func normalizedFilePath(_ url: URL) -> String {
        let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path, isDirectory: true)
        return fileURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
