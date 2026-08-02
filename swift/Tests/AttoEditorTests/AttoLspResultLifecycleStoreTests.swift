@testable import AttoEditor
import XCTest

final class AttoLspResultLifecycleStoreTests: XCTestCase {
    func testRecordKeepsCurrentAndBoundsHistory() {
        let store = AttoLspResultLifecycleStore<Int>(maxHistoryEntries: 3)

        store.record(1)
        store.record(2)
        store.record(3)
        store.record(4)

        XCTAssertEqual(store.current, 4)
        XCTAssertEqual(store.history, [2, 3, 4])
    }

    func testMakeCurrentDoesNotDuplicateHistory() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)

        store.record("first")
        store.record("second")
        store.makeCurrent("first")

        XCTAssertEqual(store.current, "first")
        XCTAssertEqual(store.history, ["first", "second"])
    }

    func testClearDropsCurrentAndHistory() {
        let store = AttoLspResultLifecycleStore<Int>(maxHistoryEntries: 0)

        store.record(1)
        store.record(2)
        store.clear()

        XCTAssertNil(store.current)
        XCTAssertEqual(store.history, [])
    }
}
