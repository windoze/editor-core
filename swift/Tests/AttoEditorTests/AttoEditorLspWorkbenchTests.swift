import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorLspWorkbenchTests: XCTestCase {
    func testLspWorkbenchPinnedResultsFiltersHistoryToPinnedEntries() throws {
        try withTemporaryWorkspace { tempDir in
            let fileURL = tempDir.appendingPathComponent("workbench-pinned-history.swift")
            let vc = makeEditorArea(workspaceRootURL: tempDir)
            let locationTarget = AttoLspDefinitionParser.Target(
                uri: fileURL.absoluteString,
                line: 0,
                utf16Character: 0
            )
            let symbolTarget = AttoLspDefinitionParser.Target(
                uri: fileURL.absoluteString,
                line: 1,
                utf16Character: 0
            )

            vc.recordLspLocationResultSnapshot(
                AttoEditorAreaViewController.LspLocationResultSnapshot(
                    kind: .definition,
                    items: [
                        AttoLspDefinitionParser.LocationItem(
                            target: locationTarget,
                            fileDisplayName: fileURL.lastPathComponent
                        ),
                    ]
                )
            )
            vc.recordLspSymbolResultSnapshot(
                AttoEditorAreaViewController.LspSymbolResultSnapshot(
                    title: "Document Symbols",
                    symbols: [
                        AttoLspSymbolParser.Symbol(
                            name: "PinnedOnly",
                            detail: nil,
                            kindLabel: "Struct",
                            containerName: nil,
                            target: symbolTarget,
                            depth: 0
                        ),
                    ],
                    placeholder: "Filter document symbols..."
                )
            )

            vc._refreshLspWorkbenchPanelForTesting()
            XCTAssertTrue(vc._selectLspWorkbenchPanelItemForTesting(id: "symbols"))
            XCTAssertTrue(vc.pinSelectedLspWorkbenchResult())

            let pinnedItems = vc.lspWorkbenchPinnedHistoryItems()
            XCTAssertEqual(pinnedItems.map(\.family), ["symbols"])
            XCTAssertEqual(pinnedItems.first?.isPinned, true)
            XCTAssertTrue(
                AttoLspWorkbenchHistoryPanelController.metadataSummary(for: pinnedItems)
                    .contains("1 pinned")
            )

            XCTAssertTrue(vc.showLspWorkbenchPinnedResultsPanel())
            XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench pinned results: 1")

            XCTAssertTrue(vc.unpinSelectedLspWorkbenchResult())
            XCTAssertEqual(vc.lspWorkbenchPinnedHistoryItems(), [])
            XCTAssertFalse(vc.showLspWorkbenchPinnedResultsPanel())
            XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench pinned results: none")
        }
    }

    func testLspWorkbenchPinnedResultsRetainEntriesAfterHistoryBounds() throws {
        try withTemporaryWorkspace { tempDir in
            let fileURL = tempDir.appendingPathComponent("workbench-pinned-bounds.swift")
            let vc = makeEditorArea(workspaceRootURL: tempDir)

            for line in 0...AttoEditorAreaViewController.maxLspResultHistoryEntries {
                let target = AttoLspDefinitionParser.Target(
                    uri: fileURL.absoluteString,
                    line: line,
                    utf16Character: 0
                )
                vc.recordLspLocationResultSnapshot(
                    AttoEditorAreaViewController.LspLocationResultSnapshot(
                        kind: .definition,
                        items: [
                            AttoLspDefinitionParser.LocationItem(
                                target: target,
                                fileDisplayName: fileURL.lastPathComponent
                            ),
                        ]
                    )
                )
                if line == 0 {
                    XCTAssertTrue(vc.pinLspWorkbenchResult(family: "locations"))
                }
            }

            XCTAssertFalse(vc._lspLocationResultLifecycleHistoryForTesting().contains {
                $0.sequence == 1
            })
            let pinnedItem = try XCTUnwrap(vc.lspWorkbenchPinnedHistoryItems().first {
                $0.family == "locations" && $0.resultSequence == 1
            })

            XCTAssertTrue(pinnedItem.isPinned)
            XCTAssertEqual(pinnedItem.detail, "1 location")
            XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(pinnedItem))
            XCTAssertEqual(vc._lastLspLocationResultForTesting()?.items.first?.target.line, 0)
        }
    }

    func testLspWorkbenchPinnedAuxiliaryResultsRetainSnapshotsAfterHistoryBounds() throws {
        try withTemporaryWorkspace { tempDir in
            let vc = makeEditorArea(workspaceRootURL: tempDir)
            let firstColor = AttoLspDocumentColorParser.Item(
                range: EcuSelectionRange(start: 0, end: 7),
                startLine: 0,
                startUTF16Character: 0,
                color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
            )

            vc.recordDocumentColorResultLifecycle(items: [firstColor], mode: .refresh)
            XCTAssertTrue(vc.pinLspWorkbenchResult(family: "document_colors"))

            for index in 1...AttoEditorAreaViewController.maxLspResultEventHistoryEntries {
                let rangeStart = UInt32(index * 2)
                let item = AttoLspDocumentColorParser.Item(
                    range: EcuSelectionRange(start: rangeStart, end: rangeStart + 1),
                    startLine: index,
                    startUTF16Character: 0,
                    color: AttoLspDocumentColorParser.Color(red: 0, green: 0, blue: 1, alpha: 1)
                )
                vc.recordDocumentColorResultLifecycle(items: [item], mode: .refresh)
            }

            let pinnedItem = try XCTUnwrap(vc.lspWorkbenchPinnedHistoryItems().first {
                $0.family == "document_colors" && $0.resultSequence == 1
            })

            XCTAssertTrue(pinnedItem.isPinned)
            XCTAssertEqual(pinnedItem.detail, "1 color | refresh")
            XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(pinnedItem))
            XCTAssertEqual(vc._documentColorPanelItemsForTesting(), [firstColor])

            XCTAssertTrue(vc.unpinLspWorkbenchResult(family: "document_colors"))
            XCTAssertFalse(vc.lspWorkbenchPinnedHistoryItems().contains {
                $0.family == "document_colors" && $0.resultSequence == 1
            })
        }
    }

    func testDocumentColorRefreshModeUpdatesWorkbenchWithoutOpeningPanel() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()
        let item = AttoLspDocumentColorParser.Item(
            range: EcuSelectionRange(start: 13, end: 20),
            startLine: 0,
            startUTF16Character: 13,
            color: AttoLspDocumentColorParser.Color(red: 0, green: 1, blue: 0, alpha: 1)
        )

        vc.recordDocumentColorResultLifecycle(items: [item], mode: .refresh)
        vc.lastDocumentColorItems = [item]

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "document_colors" }
        XCTAssertEqual(events.map(\.payload), [.documentColors(mode: "refresh", itemCount: 1)])
        XCTAssertEqual(vc._documentColorPanelItemsForTesting(), [])

        let workbenchItem = try XCTUnwrap(
            vc.lspWorkbenchItems().first { $0.title == "Document Colors" }
        )
        XCTAssertTrue(workbenchItem.status.contains("1 color | Fresh"))
        XCTAssertEqual(workbenchItem.historyCount, 1)
    }

    func makeEditorArea(
        workspaceRootURL: URL,
        preferences: AttoPreferences = .shared,
        projectLspProcessHealthLogStore: AttoProjectLspProcessHealthLogStore = AttoProjectLspProcessHealthLogStore()
    ) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL,
            preferences: preferences,
            projectLspProcessHealthLogStore: projectLspProcessHealthLogStore
        )
    }

    private func withTemporaryWorkspace(_ body: (URL) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorLspWorkbenchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try body(tempDir)
    }
}
