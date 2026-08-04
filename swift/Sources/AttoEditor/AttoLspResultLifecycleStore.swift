import Foundation
import EditorCoreUIFFI

enum AttoLspResultLifecycleState: Equatable {
    case fresh
    case stale(reason: String)
    case error(message: String)

    var isStale: Bool {
        if case .stale = self {
            return true
        }
        return false
    }

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
    private(set) var pinnedEntry: AttoLspResultLifecycleEntry<Snapshot>?
    private(set) var pinnedEntriesByKey: [String: AttoLspResultLifecycleEntry<Snapshot>] = [:]

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
        return updateState(for: currentEntry, state)
    }

    @discardableResult
    func updateState(
        for entry: AttoLspResultLifecycleEntry<Snapshot>,
        _ state: AttoLspResultLifecycleState
    ) -> AttoLspResultLifecycleEntry<Snapshot>? {
        guard let existing = matchingEntry(for: entry) else { return nil }
        guard existing.state != state else { return existing }

        let updated = AttoLspResultLifecycleEntry(
            sequence: existing.sequence,
            family: existing.family,
            title: existing.title,
            recordedAt: existing.recordedAt,
            state: state,
            snapshot: existing.snapshot
        )
        if currentEntry?.sequence == updated.sequence,
           currentEntry?.family == updated.family {
            self.currentEntry = updated
        }
        if let index = historyEntries.lastIndex(where: { $0.sequence == updated.sequence }) {
            historyEntries[index] = updated
        }
        if pinnedEntry?.sequence == updated.sequence {
            pinnedEntry = updated
        }
        for key in Array(pinnedEntriesByKey.keys) where pinnedEntriesByKey[key]?.sequence == updated.sequence {
            pinnedEntriesByKey[key] = updated
        }
        return updated
    }

    @discardableResult
    func clearCurrentStaleState() -> AttoLspResultLifecycleEntry<Snapshot>? {
        guard currentEntry?.state.isStale == true else { return nil }
        return updateCurrentState(.fresh)
    }

    @discardableResult
    func clearStaleState(
        for entry: AttoLspResultLifecycleEntry<Snapshot>
    ) -> AttoLspResultLifecycleEntry<Snapshot>? {
        guard entry.state.isStale else { return nil }
        return updateState(for: entry, .fresh)
    }

    @discardableResult
    func pinCurrent() -> AttoLspResultLifecycleEntry<Snapshot>? {
        guard let currentEntry else { return nil }
        return pin(currentEntry)
    }

    @discardableResult
    func pinLatest(family: String) -> AttoLspResultLifecycleEntry<Snapshot>? {
        let currentCandidate = currentEntry?.family == family ? currentEntry : nil
        let historyCandidate = historyEntries.reversed().first { $0.family == family }
        let entry = [currentCandidate, historyCandidate]
            .compactMap { $0 }
            .max { $0.sequence < $1.sequence }
        guard let entry else { return nil }
        return pin(entry, key: family)
    }

    @discardableResult
    func pin(
        _ entry: AttoLspResultLifecycleEntry<Snapshot>,
        key: String? = nil
    ) -> AttoLspResultLifecycleEntry<Snapshot> {
        pinnedEntry = entry
        pinnedEntriesByKey[key ?? entry.family] = entry
        return entry
    }

    @discardableResult
    func unpin(key: String) -> AttoLspResultLifecycleEntry<Snapshot>? {
        guard let removed = pinnedEntriesByKey.removeValue(forKey: key) else { return nil }
        if pinnedEntry?.sequence == removed.sequence, pinnedEntry?.family == removed.family {
            pinnedEntry = pinnedEntriesByKey.values.max { lhs, rhs in
                lhs.sequence < rhs.sequence
            }
        }
        return removed
    }

    func entries(after sequence: UInt64) -> [AttoLspResultLifecycleEntry<Snapshot>] {
        historyEntries.filter { $0.sequence > sequence }
    }

    func clear() {
        currentEntry = nil
        pinnedEntry = nil
        pinnedEntriesByKey.removeAll()
        historyEntries.removeAll()
        nextSequence = 1
    }

    private func matchingEntry(
        for entry: AttoLspResultLifecycleEntry<Snapshot>
    ) -> AttoLspResultLifecycleEntry<Snapshot>? {
        if let currentEntry,
           currentEntry.sequence == entry.sequence,
           currentEntry.family == entry.family {
            return currentEntry
        }
        return historyEntries.last {
            $0.sequence == entry.sequence && $0.family == entry.family
        }
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
        case codeLens(itemCount: Int)
        case inlayHints(itemCount: Int)
        case documentLinks(itemCount: Int)
        case documentColors(mode: String, itemCount: Int)
        case colorPresentations(itemCount: Int)
        case hierarchy(title: String, itemCount: Int)
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
    let state: AttoLspResultLifecycleState
    let payload: Payload
}

final class AttoLspResultEventStream {
    private let maxHistoryEntries: Int
    private var nextSequence: UInt64 = 1
    private(set) var events: [AttoLspResultLifecycleEvent] = []
    private(set) var pinnedEventsByFamily: [String: AttoLspResultLifecycleEvent] = [:]

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
        state: AttoLspResultLifecycleState = .fresh,
        payload: AttoLspResultLifecycleEvent.Payload
    ) -> AttoLspResultLifecycleEvent {
        let event = AttoLspResultLifecycleEvent(
            sequence: nextSequence,
            family: family,
            title: title,
            recordedAt: recordedAt,
            sourceSequence: sourceSequence,
            state: state,
            payload: payload
        )
        nextSequence += 1
        events.append(event)
        if events.count > maxHistoryEntries {
            events.removeFirst(events.count - maxHistoryEntries)
        }
        return event
    }

    @discardableResult
    func updateLatestStates(
        families: Set<String>,
        state: AttoLspResultLifecycleState
    ) -> [AttoLspResultLifecycleEvent] {
        var remaining = families
        var updated: [AttoLspResultLifecycleEvent] = []

        for index in events.indices.reversed() {
            let event = events[index]
            guard remaining.contains(event.family) else { continue }

            let replacement = AttoLspResultLifecycleEvent(
                sequence: event.sequence,
                family: event.family,
                title: event.title,
                recordedAt: event.recordedAt,
                sourceSequence: event.sourceSequence,
                state: state,
                payload: event.payload
            )
            events[index] = replacement
            if pinnedEventsByFamily[event.family]?.sequence == event.sequence {
                pinnedEventsByFamily[event.family] = replacement
            }
            updated.append(replacement)
            remaining.remove(event.family)
            if remaining.isEmpty {
                break
            }
        }

        return updated.reversed()
    }

    @discardableResult
    func clearLatestStaleStates(
        families: Set<String>
    ) -> [AttoLspResultLifecycleEvent] {
        var remaining = families
        var updated: [AttoLspResultLifecycleEvent] = []

        for index in events.indices.reversed() {
            let event = events[index]
            guard remaining.contains(event.family) else { continue }
            remaining.remove(event.family)
            guard event.state.isStale else {
                if remaining.isEmpty {
                    break
                }
                continue
            }

            let replacement = AttoLspResultLifecycleEvent(
                sequence: event.sequence,
                family: event.family,
                title: event.title,
                recordedAt: event.recordedAt,
                sourceSequence: event.sourceSequence,
                state: .fresh,
                payload: event.payload
            )
            events[index] = replacement
            if pinnedEventsByFamily[event.family]?.sequence == event.sequence {
                pinnedEventsByFamily[event.family] = replacement
            }
            updated.append(replacement)
            if remaining.isEmpty {
                break
            }
        }

        return updated.reversed()
    }

    @discardableResult
    func pinLatest(family: String) -> AttoLspResultLifecycleEvent? {
        guard let event = events.reversed().first(where: { $0.family == family }) else { return nil }
        pinnedEventsByFamily[family] = event
        return event
    }

    @discardableResult
    func unpin(family: String) -> AttoLspResultLifecycleEvent? {
        pinnedEventsByFamily.removeValue(forKey: family)
    }

    func entries(after sequence: UInt64) -> [AttoLspResultLifecycleEvent] {
        events.filter { $0.sequence > sequence }
    }

    func clear() {
        events.removeAll()
        pinnedEventsByFamily.removeAll()
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

final class AttoProjectLspLifecycleEventStore {
    private let maxHistoryEntries: Int
    private(set) var events: [EcuProjectLspLifecycleEvent] = []

    var latestSequence: UInt64 {
        events.last?.sequence ?? 0
    }

    init(maxHistoryEntries: Int) {
        self.maxHistoryEntries = max(1, maxHistoryEntries)
    }

    func record(_ event: EcuProjectLspLifecycleEvent) {
        events.append(event)
        if events.count > maxHistoryEntries {
            events.removeFirst(events.count - maxHistoryEntries)
        }
    }

    func record(contentsOf newEvents: [EcuProjectLspLifecycleEvent]) {
        for event in newEvents {
            record(event)
        }
    }

    func entries(after sequence: UInt64) -> [EcuProjectLspLifecycleEvent] {
        events.filter { $0.sequence > sequence }
    }

    func clear() {
        events.removeAll()
    }
}
