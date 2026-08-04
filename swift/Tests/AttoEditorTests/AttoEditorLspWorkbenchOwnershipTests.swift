@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorLspWorkbenchOwnershipTests: XCTestCase {
    func testLspWorkbenchCurrentResultsFollowActiveTabOwnership() throws {
        try withTemporaryWorkspace { tempDir in
            let firstURL = tempDir.appendingPathComponent("owned-first.swift")
            let secondURL = tempDir.appendingPathComponent("owned-second.swift")
            try "first\n".write(to: firstURL, atomically: true, encoding: .utf8)
            try "second\n".write(to: secondURL, atomically: true, encoding: .utf8)

            let vc = makeEditorArea(workspaceRootURL: tempDir)
            XCTAssertTrue(vc.openFile(url: firstURL, mode: .pinned))
            let firstTabID = try XCTUnwrap(
                vc.openFileItems().first { $0.url.standardizedFileURL == firstURL.standardizedFileURL }?.id
            )
            let firstTab = try XCTUnwrap(vc.activeTab)
            let locationTarget = AttoLspDefinitionParser.Target(
                uri: firstURL.absoluteString,
                line: 0,
                utf16Character: 0
            )
            vc.recordLspLocationResultSnapshot(
                AttoEditorAreaViewController.LspLocationResultSnapshot(
                    kind: .definition,
                    items: [
                        AttoLspDefinitionParser.LocationItem(
                            target: locationTarget,
                            fileDisplayName: firstURL.lastPathComponent
                        ),
                    ]
                )
            )

            let color = AttoLspDocumentColorParser.Item(
                range: EcuSelectionRange(start: 0, end: 5),
                startLine: 0,
                startUTF16Character: 0,
                color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let colorOwner = vc.lspDocumentResultOwner(for: firstTab)
            vc.recordDocumentColorResultLifecycle(items: [color], mode: .refresh, owner: colorOwner)
            vc.lastDocumentColorItems = [color]
            vc.lastDocumentColorOwner = colorOwner

            XCTAssertTrue(vc.openFile(url: secondURL, mode: .pinned))
            var itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
            XCTAssertEqual(itemsByID["locations"]?.isEnabled, false)
            XCTAssertEqual(itemsByID["locations"]?.status, "0 locations")
            XCTAssertEqual(itemsByID["locations"]?.historyCount, 1)
            XCTAssertEqual(itemsByID["document_colors"]?.status, "request on open")
            XCTAssertEqual(itemsByID["document_colors"]?.historyCount, 1)
            XCTAssertFalse(vc.showLspLocationPanel())

            vc.selectTab(id: firstTabID)
            itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
            XCTAssertEqual(itemsByID["locations"]?.isEnabled, true)
            XCTAssertTrue(itemsByID["locations"]?.status.hasPrefix("1 location | Fresh | Result #") == true)
            XCTAssertEqual(itemsByID["document_colors"]?.isEnabled, true)
            XCTAssertTrue(itemsByID["document_colors"]?.status.hasPrefix("1 color | Fresh | Result #") == true)
            XCTAssertTrue(vc.showLspLocationPanel())
        }
    }

    func testLspWorkbenchHistoryRestoreSelectsOwningTab() throws {
        try withTemporaryWorkspace { tempDir in
            let firstURL = tempDir.appendingPathComponent("history-first.swift")
            let secondURL = tempDir.appendingPathComponent("history-second.swift")
            try "first\n".write(to: firstURL, atomically: true, encoding: .utf8)
            try "second\n".write(to: secondURL, atomically: true, encoding: .utf8)

            let vc = makeEditorArea(workspaceRootURL: tempDir)
            XCTAssertTrue(vc.openFile(url: firstURL, mode: .pinned))
            let locationTarget = AttoLspDefinitionParser.Target(
                uri: firstURL.absoluteString,
                line: 0,
                utf16Character: 0
            )
            vc.recordLspLocationResultSnapshot(
                AttoEditorAreaViewController.LspLocationResultSnapshot(
                    kind: .definition,
                    items: [
                        AttoLspDefinitionParser.LocationItem(
                            target: locationTarget,
                            fileDisplayName: firstURL.lastPathComponent
                        ),
                    ]
                )
            )
            let historyItem = try XCTUnwrap(vc.lspWorkbenchHistoryItems(family: "locations").first)

            XCTAssertTrue(vc.openFile(url: secondURL, mode: .pinned))
            XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, secondURL.standardizedFileURL)

            XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(historyItem))
            XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, firstURL.standardizedFileURL)
            XCTAssertEqual(vc._lastLspLocationResultForTesting()?.items.first?.target, locationTarget)
            XCTAssertEqual(vc.lspWorkbenchJumpTarget(family: "locations"), locationTarget)
            XCTAssertTrue(vc.showLspLocationPanel())
        }
    }

    func testPinnedAuxiliaryHistoryRestoreUsesOwnerAndPinnedMetadataAfterHistoryBounds() throws {
        try withTemporaryWorkspace { tempDir in
            let firstURL = tempDir.appendingPathComponent("pinned-first.swift")
            let secondURL = tempDir.appendingPathComponent("pinned-second.swift")
            try "first\n".write(to: firstURL, atomically: true, encoding: .utf8)
            try "second\n".write(to: secondURL, atomically: true, encoding: .utf8)

            let vc = makeEditorArea(workspaceRootURL: tempDir)
            XCTAssertTrue(vc.openFile(url: firstURL, mode: .pinned))
            let firstTab = try XCTUnwrap(vc.activeTab)
            let firstOwner = vc.lspDocumentResultOwner(for: firstTab)
            let firstColor = documentColor(rangeStart: 0, line: 0, red: 1, blue: 0)
            vc.recordDocumentColorResultLifecycle(items: [firstColor], mode: .refresh, owner: firstOwner)
            let firstEventSequence = vc._latestLspResultLifecycleEventSequenceForTesting()
            XCTAssertTrue(vc.pinLspWorkbenchResult(family: "document_colors"))

            XCTAssertTrue(vc.openFile(url: secondURL, mode: .pinned))
            let secondTab = try XCTUnwrap(vc.activeTab)
            let secondOwner = vc.lspDocumentResultOwner(for: secondTab)
            for index in 1...AttoEditorAreaViewController.maxLspResultEventHistoryEntries {
                let rangeStart = UInt32(index * 2)
                let item = documentColor(rangeStart: rangeStart, line: index, red: 0, blue: 1)
                vc.recordDocumentColorResultLifecycle(items: [item], mode: .refresh, owner: secondOwner)
            }

            XCTAssertFalse(vc._lspResultLifecycleEventsForTesting(after: 0).contains {
                $0.sequence == firstEventSequence
            })
            let pinnedItem = try XCTUnwrap(vc.lspWorkbenchPinnedHistoryItems().first {
                $0.family == "document_colors" && $0.resultSequence == firstEventSequence
            })

            XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(pinnedItem))
            XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, firstURL.standardizedFileURL)
            XCTAssertEqual(vc._documentColorPanelItemsForTesting(), [firstColor])
            let itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
            XCTAssertEqual(itemsByID["document_colors"]?.isPinned, true)
            XCTAssertTrue(
                itemsByID["document_colors"]?.status.hasPrefix("1 color | Fresh | Result #\(firstEventSequence)") == true
            )
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
            .appendingPathComponent("AttoEditorLspWorkbenchOwnershipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try body(tempDir)
    }

    private func documentColor(
        rangeStart: UInt32,
        line: Int,
        red: Double,
        blue: Double
    ) -> AttoLspDocumentColorParser.Item {
        AttoLspDocumentColorParser.Item(
            range: EcuSelectionRange(start: rangeStart, end: rangeStart + 1),
            startLine: line,
            startUTF16Character: 0,
            color: AttoLspDocumentColorParser.Color(red: red, green: 0, blue: blue, alpha: 1)
        )
    }
}
