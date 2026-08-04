@testable import AttoEditor
import Foundation
import XCTest

final class AttoLspResultOwnerLifecycleTests: XCTestCase {
    func testRecordIfChangedRecordsSameSnapshotWhenOwnerChanges() {
        let store = AttoLspResultLifecycleStore<String>(maxHistoryEntries: 3)
        let firstOwner = documentOwner(tabID: "00000000-0000-0000-0000-000000000001", coreTabID: 1, file: "first.swift")
        let secondOwner = documentOwner(tabID: "00000000-0000-0000-0000-000000000002", coreTabID: 2, file: "second.swift")

        let first = store.recordIfChanged("same", family: "diagnostics", title: "First", owner: firstOwner)
        let duplicate = store.recordIfChanged("same", family: "diagnostics", title: "Duplicate", owner: firstOwner)
        let second = store.recordIfChanged("same", family: "diagnostics", title: "Second", owner: secondOwner)

        XCTAssertNotNil(first)
        XCTAssertNil(duplicate)
        XCTAssertNotNil(second)
        XCTAssertEqual(store.history, ["same", "same"])
        XCTAssertEqual(store.historyEntries.map(\.owner), [firstOwner, secondOwner])
        XCTAssertEqual(store.currentEntry?.title, "Second")
    }

    func testResultEventStreamFiltersUpdatesAndPinsByOwner() {
        let stream = AttoLspResultEventStream(maxHistoryEntries: 4)
        let firstOwner = documentOwner(tabID: "00000000-0000-0000-0000-000000000001", coreTabID: 1, file: "first.swift")
        let secondOwner = documentOwner(tabID: "00000000-0000-0000-0000-000000000002", coreTabID: 2, file: "second.swift")

        let first = stream.record(
            family: "document_links",
            title: "Document Links: 1 link",
            owner: firstOwner,
            payload: .documentLinks(itemCount: 1)
        )
        let second = stream.record(
            family: "document_links",
            title: "Document Links: 2 links",
            owner: secondOwner,
            payload: .documentLinks(itemCount: 2)
        )
        let ownerMatchesFirst: (AttoLspResultOwner?) -> Bool = { $0 == .some(firstOwner) }

        let staleState = AttoLspResultLifecycleState.stale(reason: "document edited")
        let updated = stream.updateLatestStates(
            families: ["document_links"],
            state: staleState,
            ownerMatches: ownerMatchesFirst
        )

        XCTAssertEqual(updated.map(\.sequence), [first.sequence])
        XCTAssertEqual(stream.events.map(\.state), [staleState, .fresh])
        XCTAssertEqual(stream.pinLatest(family: "document_links", ownerMatches: ownerMatchesFirst)?.sequence, first.sequence)
        XCTAssertEqual(stream.pinnedEventsByFamily["document_links"]?.sequence, first.sequence)
        XCTAssertEqual(stream.pinnedEventsByFamily["document_links"]?.owner, firstOwner)

        let cleared = stream.clearLatestStaleStates(
            families: ["document_links"],
            ownerMatches: ownerMatchesFirst
        )

        XCTAssertEqual(cleared.map(\.sequence), [first.sequence])
        XCTAssertEqual(stream.events.map(\.state), [.fresh, .fresh])
        XCTAssertEqual(stream.pinnedEventsByFamily["document_links"]?.state, .fresh)
        XCTAssertEqual(second.owner, secondOwner)
    }

    private func documentOwner(tabID: String, coreTabID: UInt64, file: String) -> AttoLspResultOwner {
        AttoLspResultOwner.document(
            tabID: UUID(uuidString: tabID)!,
            coreTabID: coreTabID,
            documentURI: "file:///workspace/\(file)",
            workspaceRootURI: "file:///workspace/"
        )
    }
}
