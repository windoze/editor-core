@testable import AttoEditor
import Foundation
import XCTest

final class AttoWorkspaceOutlineStoreTests: XCTestCase {
    func testWorkspaceOutlineStoreAggregatesDocumentsInOpenOrder() {
        let store = AttoWorkspaceOutlineStore()
        let firstURL = URL(fileURLWithPath: "/tmp/project/App.swift")
        let secondURL = URL(fileURLWithPath: "/tmp/project/Model.swift")

        let app = symbol(
            name: "App",
            kindLabel: "struct",
            uri: firstURL.absoluteString,
            line: 0,
            utf16Character: 7
        )
        let run = symbol(
            name: "run",
            detail: "fn()",
            kindLabel: "function",
            containerName: "App",
            uri: firstURL.absoluteString,
            line: 4,
            utf16Character: 4
        )
        let model = symbol(
            name: "Model",
            kindLabel: "class",
            uri: secondURL.absoluteString,
            line: 1,
            utf16Character: 6
        )

        store.upsertDocument(
            tabID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            coreTabID: 11,
            fileURL: firstURL,
            symbols: [app, run]
        )
        let snapshot = store.upsertDocument(
            tabID: UUID(uuidString: "00000000-0000-0000-0000-000000000002"),
            coreTabID: 12,
            fileURL: secondURL,
            symbols: [model]
        )

        XCTAssertEqual(snapshot.documents.map(\.title), ["App.swift", "Model.swift"])
        XCTAssertEqual(snapshot.documents.map(\.symbolCount), [2, 1])
        XCTAssertEqual(snapshot.symbols.map(\.name), ["App", "run", "Model"])
        XCTAssertEqual(snapshot.symbols[0].containerName, "App.swift")
        XCTAssertEqual(snapshot.symbols[1].containerName, "App")
        XCTAssertEqual(snapshot.symbols[2].containerName, "Model.swift")
    }

    func testWorkspaceOutlineStoreUpdatesAndRemovesDocuments() {
        let store = AttoWorkspaceOutlineStore()
        let fileURL = URL(fileURLWithPath: "/tmp/project/App.swift")

        store.upsertDocument(
            tabID: nil,
            coreTabID: nil,
            fileURL: fileURL,
            symbols: [symbol(name: "Old", uri: fileURL.absoluteString)]
        )
        var snapshot = store.upsertDocument(
            tabID: nil,
            coreTabID: nil,
            fileURL: fileURL,
            symbols: [symbol(name: "New", uri: fileURL.absoluteString)]
        )
        XCTAssertEqual(snapshot.documents.count, 1)
        XCTAssertEqual(snapshot.symbols.map(\.name), ["New"])

        snapshot = store.removeDocument(fileURL: fileURL)
        XCTAssertEqual(snapshot, .empty)

        store.upsertDocument(
            tabID: nil,
            coreTabID: nil,
            fileURL: fileURL,
            symbols: [symbol(name: "Again", uri: fileURL.absoluteString)]
        )
        XCTAssertFalse(store.isEmpty)
        store.clear()
        XCTAssertEqual(store.snapshot, .empty)
        XCTAssertTrue(store.isEmpty)
    }

    private func symbol(
        name: String,
        detail: String? = nil,
        kindLabel: String? = nil,
        containerName: String? = nil,
        uri: String,
        line: Int = 0,
        utf16Character: Int = 0,
        depth: Int = 0
    ) -> AttoLspSymbolParser.Symbol {
        AttoLspSymbolParser.Symbol(
            name: name,
            detail: detail,
            kindLabel: kindLabel,
            containerName: containerName,
            target: AttoLspDefinitionParser.Target(
                uri: uri,
                line: line,
                utf16Character: utf16Character
            ),
            depth: depth
        )
    }
}
