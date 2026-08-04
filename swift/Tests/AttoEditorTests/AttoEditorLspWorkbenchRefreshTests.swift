@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorLspWorkbenchRefreshTests: XCTestCase {
    func testEventResultFailureHelperMarksCurrentOwnerScopedEventError() throws {
        try withTemporaryWorkspace { tempDir in
            let fileURL = tempDir.appendingPathComponent("failure-helper.swift")
            try "func run() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

            let vc = makeEditorArea(workspaceRootURL: tempDir)
            XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned))
            let tab = try XCTUnwrap(vc.activeTab)
            let owner = vc.lspDocumentResultOwner(for: tab)
            let event = vc.lspResultEventStream.record(
                family: "code_lens",
                title: "Code Lens: 1 action",
                owner: owner,
                payload: .codeLens(itemCount: 1)
            )
            let message = AttoLspResultFeedback.timeout(.codeLensRefresh)

            XCTAssertFalse(
                vc.failLspEventResult(
                    family: "code_lens",
                    message: message,
                    showFeedback: false,
                    editorView: nil,
                    beep: false
                )
            )

            let updatedEvent = try XCTUnwrap(vc._lspResultLifecycleEventsForTesting(after: 0).first {
                $0.sequence == event.sequence
            })
            XCTAssertEqual(updatedEvent.state, .error(message: message.statusText))
            let workbenchItem = try XCTUnwrap(vc.lspWorkbenchItems().first { $0.id == "code_lens" })
            XCTAssertEqual(workbenchItem.lifecycleState, .error)
            XCTAssertTrue(workbenchItem.status.contains("Error: \(message.statusText)"))
        }
    }

    func testHierarchyChildrenRefreshFailureMarksCurrentEventError() throws {
        try withTemporaryWorkspace { tempDir in
            let fileURL = tempDir.appendingPathComponent("hierarchy-refresh-failure.swift")
            try "func caller() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

            let vc = makeEditorArea(workspaceRootURL: tempDir)
            XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned))
            let tab = try XCTUnwrap(vc.activeTab)
            let target = AttoLspDefinitionParser.Target(
                uri: fileURL.absoluteString,
                line: 0,
                utf16Character: 5
            )
            let rootItem = AttoLspHierarchyParser.Item(
                name: "caller",
                detail: "Root.swift",
                kindLabel: "function",
                target: target,
                requestJSON: """
                {
                  "name": "caller",
                  "kind": 12,
                  "uri": "\(fileURL.absoluteString)",
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 16 }
                  },
                  "selectionRange": {
                    "start": { "line": 0, "character": 5 },
                    "end": { "line": 0, "character": 11 }
                  }
                }
                """
            )
            let refreshRequest = AttoEditorAreaViewController.HierarchyPanelRefreshRequest(
                tabID: tab.id,
                kind: .callIncoming,
                item: rootItem
            )
            vc.recordHierarchyPanelSnapshot(
                entries: [
                    AttoLspHierarchyParser.Entry(
                        name: "previous",
                        detail: "Previous.swift",
                        kindLabel: "function",
                        target: target,
                        relatedRangeCount: 1,
                        requestJSON: rootItem.requestJSON
                    ),
                ],
                title: "Incoming Calls",
                refreshRequest: refreshRequest
            )
            let eventSequence = try XCTUnwrap(vc._lspResultLifecycleEventsForTesting(after: 0).last {
                $0.family == "hierarchy"
            }?.sequence)

            XCTAssertFalse(vc.requestHierarchyChildren(
                for: rootItem,
                kind: .callIncoming,
                tab: tab,
                showFeedback: false,
                resultMode: .refresh
            ))

            let updatedEvent = try XCTUnwrap(vc._lspResultLifecycleEventsForTesting(after: 0).first {
                $0.sequence == eventSequence
            })
            guard case .error(let errorMessage) = updatedEvent.state else {
                return XCTFail("Expected hierarchy refresh failure to mark the current event as error")
            }
            XCTAssertTrue(errorMessage.hasPrefix("Call hierarchy: request failed"))
            let workbenchItem = try XCTUnwrap(vc.lspWorkbenchItems().first { $0.id == "hierarchy" })
            XCTAssertEqual(workbenchItem.lifecycleState, .error)
            XCTAssertTrue(workbenchItem.status.contains("Error: Call hierarchy: request failed"))
        }
    }

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
