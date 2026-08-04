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

    func testLspWorkbenchHistoryItemsSummarizeResultEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-history.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let target = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 2,
            utf16Character: 4
        )

        vc.recordLspLocationResultSnapshot(
            AttoEditorAreaViewController.LspLocationResultSnapshot(
                kind: .references,
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
        XCTAssertTrue(vc.finishHierarchyRefresh(
            [
                AttoLspHierarchyParser.Entry(
                    name: "render",
                    detail: "View.swift",
                    kindLabel: "function",
                    target: target,
                    relatedRangeCount: 1,
                    requestJSON: #"{"name":"render","uri":"file:///workbench-history.swift"}"#
                ),
            ],
            kind: .callIncoming,
            refreshRequest: nil,
            showFeedback: false,
            editorView: nil
        ))
        XCTAssertTrue(vc.pinCurrentLspWorkbenchResults())

        let items = vc.lspWorkbenchHistoryItems()
        let families = Set(items.map(\.family))
        XCTAssertTrue(families.isSuperset(of: ["locations", "symbols", "hierarchy"]))
        XCTAssertTrue(items.contains { $0.family == "locations" && $0.detail == "1 location" })
        XCTAssertTrue(items.contains { $0.family == "symbols" && $0.detail == "1 symbol" })
        XCTAssertTrue(items.contains { $0.family == "hierarchy" && $0.detail.contains("1 result") })
        XCTAssertEqual(items.filter(\.isPinned).count, 3)
        XCTAssertTrue(
            AttoLspWorkbenchHistoryPanelController.metadataSummary(for: items)
                .contains("3 pinned")
        )
        XCTAssertTrue(
            AttoLspWorkbenchHistoryPanelController.metadataSummary(for: items)
                .contains("history entries")
        )
    }

    func testLspWorkbenchHistoryOpenRestoresLocationAndSymbolEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-history-restore.swift")
        try "struct First {}\nstruct Second {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)

        let firstTarget = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 0,
            utf16Character: 7
        )
        let secondTarget = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 1,
            utf16Character: 7
        )

        vc.recordLspLocationResultSnapshot(
            AttoEditorAreaViewController.LspLocationResultSnapshot(
                kind: .references,
                items: [
                    AttoLspDefinitionParser.LocationItem(
                        target: firstTarget,
                        fileDisplayName: fileURL.lastPathComponent
                    ),
                ]
            )
        )
        vc.recordLspLocationResultSnapshot(
            AttoEditorAreaViewController.LspLocationResultSnapshot(
                kind: .references,
                items: [
                    AttoLspDefinitionParser.LocationItem(
                        target: secondTarget,
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
                        name: "First",
                        detail: nil,
                        kindLabel: "Struct",
                        containerName: nil,
                        target: firstTarget,
                        depth: 0
                    ),
                ],
                placeholder: "Filter document symbols..."
            )
        )
        vc.recordLspSymbolResultSnapshot(
            AttoEditorAreaViewController.LspSymbolResultSnapshot(
                title: "Document Symbols",
                symbols: [
                    AttoLspSymbolParser.Symbol(
                        name: "Second",
                        detail: nil,
                        kindLabel: "Struct",
                        containerName: nil,
                        target: secondTarget,
                        depth: 0
                    ),
                ],
                placeholder: "Filter document symbols..."
            )
        )

        let items = vc.lspWorkbenchHistoryItems()
        let firstLocationItem = try XCTUnwrap(items.first {
            $0.family == "locations" && $0.resultSequence == 1
        })
        let firstSymbolItem = try XCTUnwrap(items.first {
            $0.family == "symbols" && $0.resultSequence == 1
        })

        XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(firstLocationItem))
        XCTAssertEqual(vc._lastLspLocationResultForTesting()?.items.first?.target.line, 0)
        XCTAssertEqual(vc._lspLocationResultLifecycleHistoryForTesting().first?.sequence, firstLocationItem.resultSequence)

        XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(firstSymbolItem))
        XCTAssertEqual(vc._lastLspSymbolResultForTesting()?.symbols.first?.name, "First")
    }

    func testLspWorkbenchHistoryRestoresAuxiliarySnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let target = AttoLspDefinitionParser.Target(
            uri: tempDir.appendingPathComponent("history.swift").absoluteString,
            line: 0,
            utf16Character: 0
        )
        let firstColor = AttoLspDocumentColorParser.Item(
            range: EcuSelectionRange(start: 0, end: 7),
            startLine: 0,
            startUTF16Character: 0,
            color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let secondColor = AttoLspDocumentColorParser.Item(
            range: EcuSelectionRange(start: 8, end: 15),
            startLine: 1,
            startUTF16Character: 0,
            color: AttoLspDocumentColorParser.Color(red: 0, green: 0, blue: 1, alpha: 1)
        )
        let firstEntry = AttoLspHierarchyParser.Entry(
            name: "first",
            detail: "A.swift",
            kindLabel: "function",
            target: target,
            relatedRangeCount: 0,
            requestJSON: #"{"name":"first"}"#
        )
        let secondEntry = AttoLspHierarchyParser.Entry(
            name: "second",
            detail: "B.swift",
            kindLabel: "function",
            target: target,
            relatedRangeCount: 0,
            requestJSON: #"{"name":"second"}"#
        )

        vc.recordDocumentColorResultLifecycle(items: [firstColor], mode: .refresh)
        vc.recordDocumentColorResultLifecycle(items: [secondColor], mode: .refresh)
        vc.recordHierarchyPanelSnapshot(entries: [firstEntry], title: "First Hierarchy")
        vc.recordHierarchyPanelSnapshot(entries: [secondEntry], title: "Second Hierarchy")

        let historyItems = vc.lspWorkbenchHistoryItems()
        let firstColorItem = try XCTUnwrap(historyItems.first {
            $0.family == "document_colors" && $0.resultSequence == 1
        })
        let firstHierarchyItem = try XCTUnwrap(historyItems.first {
            $0.family == "hierarchy" && $0.title == "First Hierarchy"
        })

        XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(firstColorItem))
        XCTAssertEqual(vc._documentColorPanelItemsForTesting(), [firstColor])

        XCTAssertTrue(vc.restoreLspWorkbenchHistoryCurrentEntry(firstHierarchyItem))
        XCTAssertEqual(vc._hierarchyPanelSnapshotForTesting()?.title, "First Hierarchy")
        XCTAssertEqual(vc._hierarchyPanelEntriesForTesting(), [firstEntry])
    }

    func testLspWorkbenchSelectedHistoryFiltersToSelectedFamily() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-selected-history.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)

        let firstTarget = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 0,
            utf16Character: 0
        )
        let secondTarget = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 1,
            utf16Character: 0
        )

        vc.recordLspLocationResultSnapshot(
            AttoEditorAreaViewController.LspLocationResultSnapshot(
                kind: .references,
                items: [
                    AttoLspDefinitionParser.LocationItem(
                        target: firstTarget,
                        fileDisplayName: fileURL.lastPathComponent
                    ),
                ]
            )
        )
        vc.recordLspLocationResultSnapshot(
            AttoEditorAreaViewController.LspLocationResultSnapshot(
                kind: .references,
                items: [
                    AttoLspDefinitionParser.LocationItem(
                        target: secondTarget,
                        fileDisplayName: fileURL.lastPathComponent
                    ),
                ]
            )
        )

        vc._refreshLspWorkbenchPanelForTesting()
        XCTAssertTrue(vc._selectLspWorkbenchPanelItemForTesting(id: "locations"))
        XCTAssertEqual(vc._lspWorkbenchPanelSelectedItemForTesting()?.id, "locations")

        XCTAssertTrue(vc.showSelectedLspWorkbenchHistory())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP workbench history: 2 for locations")
        let historyItems = vc.lspWorkbenchHistoryItems(family: "locations")
        XCTAssertEqual(historyItems.count, 2)
        XCTAssertEqual(Set(historyItems.map(\.family)), ["locations"])
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

    private func makeEditorArea(
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
