@testable import AttoEditor
import XCTest

final class AttoLspResultLifecycleStoreTests: XCTestCase {
    func testRecordKeepsCurrentAndBoundsHistory() {
        let store = AttoLspResultLifecycleStore<Int>(maxHistoryEntries: 3)
        let firstDate = Date(timeIntervalSince1970: 100)

        let first = store.record(1, family: "numbers", title: "One", recordedAt: firstDate)
        store.record(2)
        store.record(3)
        let fourth = store.record(4, family: "numbers", title: "Four")

        XCTAssertEqual(store.current, 4)
        XCTAssertEqual(store.history, [2, 3, 4])
        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(first.family, "numbers")
        XCTAssertEqual(first.title, "One")
        XCTAssertEqual(first.recordedAt, firstDate)
        XCTAssertEqual(first.state, .fresh)
        XCTAssertEqual(fourth.sequence, 4)
        XCTAssertEqual(fourth.state, .fresh)
        XCTAssertEqual(store.latestSequence, 4)
        XCTAssertEqual(store.currentEntry?.sequence, 4)
        XCTAssertEqual(store.historyEntries.map(\.sequence), [2, 3, 4])
        XCTAssertEqual(store.entries(after: 2).map(\.snapshot), [3, 4])
        XCTAssertEqual(store.entries(after: 4).map(\.snapshot), [])
    }

    func testMakeCurrentDoesNotDuplicateHistory() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.record("first", family: "symbols", title: "First")
        store.record("second")
        store.makeCurrent(first)

        XCTAssertEqual(store.current, "first")
        XCTAssertEqual(store.history, ["first", "second"])
        XCTAssertEqual(store.currentEntry, first)
        XCTAssertEqual(store.historyEntries.map(\.title), ["First", ""])
    }

    func testMakeCurrentSnapshotCreatesEntryWithoutAddingHistory() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        store.record("first")
        let current = store.makeCurrent("manual", family: "locations", title: "Manual")

        XCTAssertEqual(store.current, "manual")
        XCTAssertEqual(store.history, ["first"])
        XCTAssertEqual(current.sequence, 2)
        XCTAssertEqual(current.family, "locations")
        XCTAssertEqual(current.title, "Manual")
        XCTAssertEqual(current.state, .fresh)
    }

    func testRecordIfChangedSkipsDuplicateCurrentSnapshot() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.recordIfChanged("same", family: "diagnostics", title: "Initial")
        let duplicate = store.recordIfChanged("same", family: "diagnostics", title: "Duplicate")
        let changed = store.recordIfChanged("changed", family: "diagnostics", title: "Changed")

        XCTAssertNotNil(first)
        XCTAssertNil(duplicate)
        XCTAssertNotNil(changed)
        XCTAssertEqual(store.history, ["same", "changed"])
        XCTAssertEqual(store.historyEntries.map(\.title), ["Initial", "Changed"])
        XCTAssertEqual(store.current, "changed")
    }

    func testRecordIfChangedRecordsSameSnapshotWhenStateChanges() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.recordIfChanged("same", family: "symbols", title: "Initial")
        let stale = store.recordIfChanged(
            "same",
            family: "symbols",
            title: "Stale",
            state: .stale(reason: "document edited")
        )

        XCTAssertNotNil(first)
        XCTAssertNotNil(stale)
        XCTAssertEqual(store.history, ["same", "same"])
        XCTAssertEqual(store.historyEntries.map(\.state), [.fresh, .stale(reason: "document edited")])
        XCTAssertEqual(store.currentEntry?.title, "Stale")
    }

    func testUpdateCurrentStateKeepsSequenceAndUpdatesHistoryEntry() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        let first = store.record("first", family: "locations", title: "First")
        store.record("second", family: "locations", title: "Second")
        store.makeCurrent(first)

        let updated = store.updateCurrentState(.stale(reason: "document edited"))

        XCTAssertEqual(updated?.sequence, first.sequence)
        XCTAssertEqual(updated?.family, first.family)
        XCTAssertEqual(updated?.title, first.title)
        XCTAssertEqual(updated?.recordedAt, first.recordedAt)
        XCTAssertEqual(updated?.snapshot, first.snapshot)
        XCTAssertEqual(updated?.state, .stale(reason: "document edited"))
        XCTAssertEqual(store.currentEntry?.state, .stale(reason: "document edited"))
        XCTAssertEqual(store.historyEntries.map(\.state), [.stale(reason: "document edited"), .fresh])

        let duplicate = store.updateCurrentState(.stale(reason: "document edited"))
        XCTAssertEqual(duplicate, updated)
        XCTAssertEqual(store.historyEntries.map(\.sequence), [1, 2])
    }

    func testNewRecordAfterStaleStateIsFreshByDefault() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        store.record("first")
        store.updateCurrentState(.stale(reason: "document edited"))
        let second = store.record("second")

        XCTAssertEqual(second.state, .fresh)
        XCTAssertEqual(store.currentEntry?.state, .fresh)
        XCTAssertEqual(store.historyEntries.map(\.state), [.stale(reason: "document edited"), .fresh])
    }

    func testClearDropsCurrentAndHistory() {
        let store = AttoLspResultLifecycleStore<Int>(maxHistoryEntries: 0)

        store.record(1)
        store.record(2)
        store.clear()

        XCTAssertNil(store.current)
        XCTAssertEqual(store.history, [])
        XCTAssertNil(store.currentEntry)
        XCTAssertEqual(store.historyEntries, [])

        let next = store.record(3)
        XCTAssertEqual(next.sequence, 1)
    }

    func testResultEventStreamBoundsAndFiltersBySequence() {
        let stream = AttoLspResultEventStream(maxHistoryEntries: 2)
        let firstDate = Date(timeIntervalSince1970: 200)

        let first = stream.record(
            family: "locations",
            title: "Definitions: 1 result",
            recordedAt: firstDate,
            sourceSequence: 10,
            payload: .locations(kind: "definition", itemCount: 1)
        )
        let second = stream.record(
            family: "symbols",
            title: "Workspace Symbols: 2 results",
            sourceSequence: 11,
            payload: .symbols(title: "Workspace Symbols", itemCount: 2)
        )
        let third = stream.record(
            family: "diagnostics.active",
            title: "main.swift",
            sourceSequence: 12,
            payload: .diagnostics(
                scope: .workspace,
                problemCount: 3,
                markerCount: 0,
                isStale: true,
                staleReason: .workspaceRefreshRequested
            )
        )

        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(first.recordedAt, firstDate)
        XCTAssertEqual(first.sourceSequence, Optional<UInt64>(10))
        XCTAssertEqual(stream.latestSequence, 3)
        XCTAssertEqual(stream.events.map(\.sequence), [2, 3])
        XCTAssertEqual(stream.entries(after: 2), [third])
        XCTAssertEqual(stream.entries(after: 3), [])
        XCTAssertEqual(second.payload, .symbols(title: "Workspace Symbols", itemCount: 2))
        XCTAssertEqual(
            third.payload,
            .diagnostics(
                scope: .workspace,
                problemCount: 3,
                markerCount: 0,
                isStale: true,
                staleReason: .workspaceRefreshRequested
            )
        )

        stream.clear()
        XCTAssertEqual(stream.events, [])
        XCTAssertEqual(stream.latestSequence, 0)
        XCTAssertEqual(
            stream.record(
                family: "locations",
                title: "References: 1 result",
                sourceSequence: 1,
                payload: .locations(kind: "references", itemCount: 1)
            ).sequence,
            1
        )
    }
}
