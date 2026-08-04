import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorLspWorkbenchTests {
    func testLspWorkbenchFirstJumpTargetUsesCurrentResultPriority() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let symbolURL = tempDir.appendingPathComponent("symbol.swift")
        let locationURL = tempDir.appendingPathComponent("location.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let symbolTarget = AttoLspDefinitionParser.Target(
            uri: symbolURL.absoluteString,
            line: 1,
            utf16Character: 2
        )
        let locationTarget = AttoLspDefinitionParser.Target(
            uri: locationURL.absoluteString,
            line: 3,
            utf16Character: 4
        )

        vc.recordLspSymbolResultSnapshot(
            AttoEditorAreaViewController.LspSymbolResultSnapshot(
                title: "Document Symbols",
                symbols: [
                    AttoLspSymbolParser.Symbol(
                        name: "SymbolOnly",
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

        XCTAssertEqual(vc.lspWorkbenchFirstJumpTarget(), symbolTarget)
        var itemsByTitle = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.title, $0) })
        XCTAssertEqual(itemsByTitle["Symbols"]?.jumpTargetCount, 1)
        XCTAssertEqual(itemsByTitle["Locations"]?.jumpTargetCount, 0)

        vc.recordLspLocationResultSnapshot(
            AttoEditorAreaViewController.LspLocationResultSnapshot(
                kind: .definition,
                items: [
                    AttoLspDefinitionParser.LocationItem(
                        target: locationTarget,
                        fileDisplayName: locationURL.lastPathComponent
                    ),
                ]
            )
        )

        XCTAssertEqual(vc.lspWorkbenchFirstJumpTarget(), locationTarget)
        itemsByTitle = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.title, $0) })
        XCTAssertEqual(itemsByTitle["Locations"]?.jumpTargetCount, 1)
        XCTAssertTrue(
            AttoLspWorkbenchPanelController.metadataSummary(for: Array(itemsByTitle.values))
                .contains("2 jump targets")
        )
    }

    func testLspWorkbenchSelectedJumpTargetUsesSelectedFamily() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let symbolURL = tempDir.appendingPathComponent("selected-symbol.swift")
        let locationURL = tempDir.appendingPathComponent("selected-location.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let symbolTarget = AttoLspDefinitionParser.Target(
            uri: symbolURL.absoluteString,
            line: 1,
            utf16Character: 2
        )
        let locationTarget = AttoLspDefinitionParser.Target(
            uri: locationURL.absoluteString,
            line: 3,
            utf16Character: 4
        )

        vc.recordLspLocationResultSnapshot(
            AttoEditorAreaViewController.LspLocationResultSnapshot(
                kind: .definition,
                items: [
                    AttoLspDefinitionParser.LocationItem(
                        target: locationTarget,
                        fileDisplayName: locationURL.lastPathComponent
                    ),
                ]
            )
        )
        vc.recordLspSymbolResultSnapshot(
            AttoEditorAreaViewController.LspSymbolResultSnapshot(
                title: "Document Symbols",
                symbols: [
                    AttoLspSymbolParser.Symbol(
                        name: "SymbolOnly",
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

        XCTAssertEqual(vc.lspWorkbenchFirstJumpTarget(), locationTarget)
        XCTAssertEqual(vc.lspWorkbenchJumpTarget(family: "symbols"), symbolTarget)
        XCTAssertEqual(vc.lspWorkbenchJumpTarget(family: "locations"), locationTarget)

        vc._refreshLspWorkbenchPanelForTesting()
        XCTAssertTrue(vc._selectLspWorkbenchPanelItemForTesting(id: "symbols"))
        XCTAssertEqual(vc._lspWorkbenchPanelSelectedItemForTesting()?.id, "symbols")
        let selectedFamily = try XCTUnwrap(vc._lspWorkbenchPanelSelectedItemForTesting()?.id)
        XCTAssertEqual(vc.lspWorkbenchJumpTarget(family: selectedFamily), symbolTarget)

        XCTAssertTrue(vc._selectLspWorkbenchPanelItemForTesting(id: "code_lens"))
        XCTAssertFalse(vc.jumpToSelectedLspWorkbenchResult())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench jump: no target for code_lens")
    }

    func testLspWorkbenchSelectedRefreshDispatchesSupportedFamilies() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-refresh.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let locationTarget = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 0,
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

        vc._refreshLspWorkbenchPanelForTesting()
        XCTAssertTrue(vc._selectLspWorkbenchPanelItemForTesting(id: "locations"))
        XCTAssertFalse(vc.lspWorkbenchCanRefresh(family: "locations"))
        XCTAssertFalse(vc.lspWorkbenchCanRefresh(family: "symbols"))
        XCTAssertFalse(vc.lspWorkbenchCanRefresh(family: "workspace_outline"))
        XCTAssertTrue(vc.lspWorkbenchCanRefresh(family: "workspace_problems"))
        XCTAssertTrue(vc.lspWorkbenchCanRefresh(family: "code_lens"))
        XCTAssertTrue(vc.lspWorkbenchCanRefresh(family: "inlay_hints"))
        XCTAssertTrue(vc.lspWorkbenchCanRefresh(family: "document_links"))
        XCTAssertTrue(vc.lspWorkbenchCanRefresh(family: "document_colors"))
        XCTAssertTrue(vc.lspWorkbenchCanRefresh(family: "hierarchy"))

        XCTAssertFalse(vc.refreshSelectedLspWorkbenchResult())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench refresh: locations cannot be refreshed")

        XCTAssertFalse(vc.refreshLspWorkbenchResult(family: "code_lens"))
        XCTAssertFalse(vc.refreshLspWorkbenchResult(family: "workspace_problems"))
        XCTAssertFalse(vc.refreshLspWorkbenchResult(family: "document_colors"))
    }

    func testLspWorkbenchSelectedClearStaleAffectsOnlySelectedFamily() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-selected-clear-stale.swift")
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
                        name: "SelectedClearStale",
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
        vc.markCurrentLspResultPanelsStale(reason: "document edited")

        var itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
        XCTAssertTrue(itemsByID["locations"]?.status.contains("Stale: document edited") == true)
        XCTAssertTrue(itemsByID["symbols"]?.status.contains("Stale: document edited") == true)

        vc._refreshLspWorkbenchPanelForTesting()
        XCTAssertTrue(vc._selectLspWorkbenchPanelItemForTesting(id: "locations"))
        XCTAssertTrue(vc.clearSelectedLspWorkbenchStaleResult())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench stale cleared: locations")

        itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
        XCTAssertTrue(itemsByID["locations"]?.status.contains("Fresh") == true)
        XCTAssertTrue(itemsByID["symbols"]?.status.contains("Stale: document edited") == true)

        XCTAssertFalse(vc.clearSelectedLspWorkbenchStaleResult())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench stale clear: none for locations")
    }

    func testLspWorkbenchSelectedPinAndUnpinAffectOnlySelectedFamily() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-selected-pin.swift")
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
                        name: "SelectedPin",
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
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench result pinned: symbols")

        var itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
        XCTAssertEqual(itemsByID["symbols"]?.isPinned, true)
        XCTAssertEqual(itemsByID["locations"]?.isPinned, false)

        XCTAssertTrue(vc._selectLspWorkbenchPanelItemForTesting(id: "locations"))
        XCTAssertTrue(vc.pinSelectedLspWorkbenchResult())
        itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
        XCTAssertEqual(itemsByID["symbols"]?.isPinned, true)
        XCTAssertEqual(itemsByID["locations"]?.isPinned, true)

        XCTAssertTrue(vc.unpinSelectedLspWorkbenchResult())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench result unpinned: locations")
        itemsByID = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.id, $0) })
        XCTAssertEqual(itemsByID["symbols"]?.isPinned, true)
        XCTAssertEqual(itemsByID["locations"]?.isPinned, false)
    }

    func testLspWorkbenchUnpinCurrentResultsClearsPinnedMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-unpin.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let target = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 0,
            utf16Character: 7
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
        vc.recordLspSymbolResultSnapshot(
            AttoEditorAreaViewController.LspSymbolResultSnapshot(
                title: "Document Symbols",
                symbols: [
                    AttoLspSymbolParser.Symbol(
                        name: "Project",
                        detail: nil,
                        kindLabel: "Struct",
                        containerName: nil,
                        target: target,
                        depth: 0
                    ),
                ],
                placeholder: "Filter document symbols..."
            )
        )

        XCTAssertTrue(vc.pinCurrentLspWorkbenchResults())
        var itemsByTitle = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.title, $0) })
        XCTAssertEqual(itemsByTitle["Locations"]?.isPinned, true)
        XCTAssertEqual(itemsByTitle["Symbols"]?.isPinned, true)
        XCTAssertTrue(
            AttoLspWorkbenchPanelController.metadataSummary(for: Array(itemsByTitle.values))
                .contains("2 pinned")
        )

        XCTAssertTrue(vc.unpinCurrentLspWorkbenchResults())
        itemsByTitle = Dictionary(uniqueKeysWithValues: vc.lspWorkbenchItems().map { ($0.title, $0) })
        XCTAssertEqual(itemsByTitle["Locations"]?.isPinned, false)
        XCTAssertEqual(itemsByTitle["Symbols"]?.isPinned, false)
        XCTAssertFalse(
            AttoLspWorkbenchPanelController.metadataSummary(for: Array(itemsByTitle.values))
                .contains("pinned")
        )

        XCTAssertFalse(vc.unpinCurrentLspWorkbenchResults())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench unpin: no pinned results")
    }

}
