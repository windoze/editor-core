import Foundation

struct AttoLspResultLifecycleEntry<Snapshot> {
    let sequence: UInt64
    let family: String
    let title: String
    let recordedAt: Date
    let snapshot: Snapshot
}

extension AttoLspResultLifecycleEntry: Equatable where Snapshot: Equatable {}

final class AttoLspResultLifecycleStore<Snapshot> {
    private let maxHistoryEntries: Int
    private var nextSequence: UInt64 = 1
    private(set) var currentEntry: AttoLspResultLifecycleEntry<Snapshot>?
    private(set) var historyEntries: [AttoLspResultLifecycleEntry<Snapshot>] = []

    var current: Snapshot? {
        currentEntry?.snapshot
    }

    var history: [Snapshot] {
        historyEntries.map(\.snapshot)
    }

    var latestSequence: UInt64 {
        max(currentEntry?.sequence ?? 0, historyEntries.last?.sequence ?? 0)
    }

    init(maxHistoryEntries: Int) {
        self.maxHistoryEntries = max(1, maxHistoryEntries)
    }

    @discardableResult
    func record(
        _ snapshot: Snapshot,
        family: String = "unknown",
        title: String = "",
        recordedAt: Date = Date()
    ) -> AttoLspResultLifecycleEntry<Snapshot> {
        let entry = makeEntry(snapshot, family: family, title: title, recordedAt: recordedAt)
        currentEntry = entry
        historyEntries.append(entry)
        if historyEntries.count > maxHistoryEntries {
            historyEntries.removeFirst(historyEntries.count - maxHistoryEntries)
        }
        return entry
    }

    @discardableResult
    func makeCurrent(
        _ snapshot: Snapshot,
        family: String = "unknown",
        title: String = "",
        recordedAt: Date = Date()
    ) -> AttoLspResultLifecycleEntry<Snapshot> {
        let entry = makeEntry(snapshot, family: family, title: title, recordedAt: recordedAt)
        currentEntry = entry
        return entry
    }

    func makeCurrent(_ entry: AttoLspResultLifecycleEntry<Snapshot>) {
        currentEntry = entry
    }

    func entries(after sequence: UInt64) -> [AttoLspResultLifecycleEntry<Snapshot>] {
        historyEntries.filter { $0.sequence > sequence }
    }

    func clear() {
        currentEntry = nil
        historyEntries.removeAll()
        nextSequence = 1
    }

    private func makeEntry(
        _ snapshot: Snapshot,
        family: String,
        title: String,
        recordedAt: Date
    ) -> AttoLspResultLifecycleEntry<Snapshot> {
        let entry = AttoLspResultLifecycleEntry(
            sequence: nextSequence,
            family: family,
            title: title,
            recordedAt: recordedAt,
            snapshot: snapshot
        )
        nextSequence += 1
        return entry
    }
}

extension AttoLspResultLifecycleStore where Snapshot: Equatable {
    @discardableResult
    func recordIfChanged(
        _ snapshot: Snapshot,
        family: String = "unknown",
        title: String = "",
        recordedAt: Date = Date()
    ) -> AttoLspResultLifecycleEntry<Snapshot>? {
        guard current != snapshot else { return nil }
        return record(snapshot, family: family, title: title, recordedAt: recordedAt)
    }
}

struct AttoLspResultLifecycleEvent: Equatable {
    enum Payload: Equatable {
        case locations(kind: String, itemCount: Int)
        case symbols(title: String, itemCount: Int)
        case completion(itemCount: Int)
        case codeActions(onlyKinds: [String], itemCount: Int)
        case rename(newName: String, documentCount: Int, resourceOperationCount: Int, applied: Bool)
        case documentColors(mode: String, itemCount: Int)
        case colorPresentations(itemCount: Int)
        case diagnostics(
            scope: AttoDiagnosticsLifecycleSnapshot.Scope,
            problemCount: Int,
            markerCount: Int,
            isStale: Bool,
            staleReason: AttoDiagnosticsStaleReason?
        )
    }

    let sequence: UInt64
    let family: String
    let title: String
    let recordedAt: Date
    let sourceSequence: UInt64?
    let payload: Payload
}

final class AttoLspResultEventStream {
    private let maxHistoryEntries: Int
    private var nextSequence: UInt64 = 1
    private(set) var events: [AttoLspResultLifecycleEvent] = []

    var latestSequence: UInt64 {
        events.last?.sequence ?? 0
    }

    init(maxHistoryEntries: Int) {
        self.maxHistoryEntries = max(1, maxHistoryEntries)
    }

    @discardableResult
    func record(
        family: String,
        title: String,
        recordedAt: Date = Date(),
        sourceSequence: UInt64? = nil,
        payload: AttoLspResultLifecycleEvent.Payload
    ) -> AttoLspResultLifecycleEvent {
        let event = AttoLspResultLifecycleEvent(
            sequence: nextSequence,
            family: family,
            title: title,
            recordedAt: recordedAt,
            sourceSequence: sourceSequence,
            payload: payload
        )
        nextSequence += 1
        events.append(event)
        if events.count > maxHistoryEntries {
            events.removeFirst(events.count - maxHistoryEntries)
        }
        return event
    }

    func entries(after sequence: UInt64) -> [AttoLspResultLifecycleEvent] {
        events.filter { $0.sequence > sequence }
    }

    func clear() {
        events.removeAll()
        nextSequence = 1
    }
}
