@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorLspWorkbenchRefreshTests: XCTestCase {
    func testDocumentColorRefreshEmptyResultRecordsFreshZeroColors() throws {
        try withTemporaryWorkspace { tempDir in
            let fileURL = tempDir.appendingPathComponent("empty-colors.swift")
            try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

            let vc = makeEditorArea(workspaceRootURL: tempDir)
            XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned))
            let tab = try XCTUnwrap(vc.activeTab)
            let owner = vc.lspDocumentResultOwner(for: tab)
            let oldColor = AttoLspDocumentColorParser.Item(
                range: EcuSelectionRange(start: 0, end: 3),
                startLine: 0,
                startUTF16Character: 0,
                color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            vc.recordDocumentColorResultLifecycle(items: [oldColor], mode: .refresh, owner: owner)
            vc.lastDocumentColorItems = [oldColor]
            vc.lastDocumentColorOwner = owner
            vc.markCurrentLspEventResultError(
                family: "document_colors",
                message: AttoLspResultFeedback.timeout(.documentColors)
            )
            let eventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

            XCTAssertTrue(vc.refreshDocumentColorResultJSONInActiveTab("[]", showFeedback: true))

            let events = vc._lspResultLifecycleEventsForTesting(after: eventCursor)
                .filter { $0.family == "document_colors" }
            let emptyEvent = try XCTUnwrap(events.last)
            XCTAssertEqual(emptyEvent.payload, .documentColors(mode: "refresh", itemCount: 0))
            XCTAssertEqual(emptyEvent.state, .fresh)
            XCTAssertEqual(vc._documentColorPanelItemsForTesting(), [])

            let workbenchItem = try XCTUnwrap(vc.lspWorkbenchItems().first { $0.id == "document_colors" })
            XCTAssertEqual(workbenchItem.lifecycleState, .fresh)
            XCTAssertEqual(workbenchItem.historyCount, 2)
            XCTAssertTrue(workbenchItem.status.hasPrefix("0 colors | Fresh | Result #\(emptyEvent.sequence)"))
        }
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL
        )
    }

    private func withTemporaryWorkspace(_ body: (URL) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorLspWorkbenchRefreshTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try body(tempDir)
    }
}
