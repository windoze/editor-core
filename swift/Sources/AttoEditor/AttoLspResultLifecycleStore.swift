import Foundation
import EditorCoreUIFFI

enum AttoLspResultLifecycleState: Equatable {
    case fresh
    case stale(reason: String)
    case error(message: String)

    var displayText: String {
        switch self {
        case .fresh:
            return "Fresh"
        case .stale(let reason):
            return "Stale: \(reason)"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

struct AttoLspResultLifecycleEntry<Snapshot> {
    let sequence: UInt64
    let family: String
    let title: String
    let recordedAt: Date
    let state: AttoLspResultLifecycleState
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
        recordedAt: Date = Date(),
        state: AttoLspResultLifecycleState = .fresh
    ) -> AttoLspResultLifecycleEntry<Snapshot> {
        let entry = makeEntry(snapshot, family: family, title: title, recordedAt: recordedAt, state: state)
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
        recordedAt: Date = Date(),
        state: AttoLspResultLifecycleState = .fresh
    ) -> AttoLspResultLifecycleEntry<Snapshot> {
        let entry = makeEntry(snapshot, family: family, title: title, recordedAt: recordedAt, state: state)
        currentEntry = entry
        return entry
    }

    func makeCurrent(_ entry: AttoLspResultLifecycleEntry<Snapshot>) {
        currentEntry = entry
    }

    @discardableResult
    func updateCurrentState(
        _ state: AttoLspResultLifecycleState
    ) -> AttoLspResultLifecycleEntry<Snapshot>? {
        guard let currentEntry else { return nil }
        guard currentEntry.state != state else { return currentEntry }

        let updated = AttoLspResultLifecycleEntry(
            sequence: currentEntry.sequence,
            family: currentEntry.family,
            title: currentEntry.title,
            recordedAt: currentEntry.recordedAt,
            state: state,
            snapshot: currentEntry.snapshot
        )
        self.currentEntry = updated
        if let index = historyEntries.lastIndex(where: { $0.sequence == updated.sequence }) {
            historyEntries[index] = updated
        }
        return updated
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
        recordedAt: Date,
        state: AttoLspResultLifecycleState
    ) -> AttoLspResultLifecycleEntry<Snapshot> {
        let entry = AttoLspResultLifecycleEntry(
            sequence: nextSequence,
            family: family,
            title: title,
            recordedAt: recordedAt,
            state: state,
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
        recordedAt: Date = Date(),
        state: AttoLspResultLifecycleState = .fresh
    ) -> AttoLspResultLifecycleEntry<Snapshot>? {
        if currentEntry?.snapshot == snapshot, currentEntry?.state == state {
            return nil
        }
        return record(snapshot, family: family, title: title, recordedAt: recordedAt, state: state)
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

struct AttoProjectLspPanelErrorEvent: Equatable {
    enum Source: String, Equatable {
        case request
        case result
        case status
    }

    let sequence: UInt64
    let source: Source
    let sourceSequence: UInt64
    let tabId: UInt64?
    let viewIndex: Int?
    let viewId: UInt64?
    let family: String
    let title: String
    let slot: String
    let method: String
    let requestId: UInt64
    let status: String
    let message: String
}

final class AttoProjectLspPanelErrorEventStore {
    private let maxHistoryEntries: Int
    private var nextSequence: UInt64 = 1
    private(set) var events: [AttoProjectLspPanelErrorEvent] = []

    var latestSequence: UInt64 {
        events.last?.sequence ?? 0
    }

    init(maxHistoryEntries: Int) {
        self.maxHistoryEntries = max(1, maxHistoryEntries)
    }

    @discardableResult
    func record(
        source: AttoProjectLspPanelErrorEvent.Source,
        sourceSequence: UInt64,
        tabId: UInt64?,
        viewIndex: Int?,
        viewId: UInt64?,
        family: String,
        title: String,
        slot: String,
        method: String,
        requestId: UInt64,
        status: String,
        message: String
    ) -> AttoProjectLspPanelErrorEvent {
        let event = AttoProjectLspPanelErrorEvent(
            sequence: nextSequence,
            source: source,
            sourceSequence: sourceSequence,
            tabId: tabId,
            viewIndex: viewIndex,
            viewId: viewId,
            family: family,
            title: title,
            slot: slot,
            method: method,
            requestId: requestId,
            status: status,
            message: message
        )
        nextSequence += 1
        events.append(event)
        if events.count > maxHistoryEntries {
            events.removeFirst(events.count - maxHistoryEntries)
        }
        return event
    }

    func entries(after sequence: UInt64) -> [AttoProjectLspPanelErrorEvent] {
        events.filter { $0.sequence > sequence }
    }

    func clear() {
        events.removeAll()
        nextSequence = 1
    }
}

struct AttoProjectLspProcessHealthEvent: Equatable {
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
    let process: EcuLspProcessStatus
}

final class AttoProjectLspProcessHealthEventStore {
    private let maxHistoryEntries: Int
    private var nextSequence: UInt64 = 1
    private(set) var events: [AttoProjectLspProcessHealthEvent] = []

    var latestSequence: UInt64 {
        events.last?.sequence ?? 0
    }

    init(maxHistoryEntries: Int) {
        self.maxHistoryEntries = max(1, maxHistoryEntries)
    }

    @discardableResult
    func record(
        sourceSequence: UInt64,
        tabId: UInt64?,
        viewIndex: Int?,
        viewId: UInt64?,
        serverName: String?,
        serverCommand: String?,
        availability: String,
        state: String,
        detail: String?,
        process: EcuLspProcessStatus
    ) -> AttoProjectLspProcessHealthEvent {
        let event = AttoProjectLspProcessHealthEvent(
            sequence: nextSequence,
            sourceSequence: sourceSequence,
            tabId: tabId,
            viewIndex: viewIndex,
            viewId: viewId,
            serverName: serverName,
            serverCommand: serverCommand,
            availability: availability,
            state: state,
            detail: detail,
            process: process
        )
        nextSequence += 1
        events.append(event)
        if events.count > maxHistoryEntries {
            events.removeFirst(events.count - maxHistoryEntries)
        }
        return event
    }

    func entries(after sequence: UInt64) -> [AttoProjectLspProcessHealthEvent] {
        events.filter { $0.sequence > sequence }
    }

    func clear() {
        events.removeAll()
        nextSequence = 1
    }
}
