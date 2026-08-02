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
        XCTAssertEqual(fourth.sequence, 4)
        XCTAssertEqual(store.currentEntry?.sequence, 4)
        XCTAssertEqual(store.historyEntries.map(\.sequence), [2, 3, 4])
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
}
