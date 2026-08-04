import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorLspWorkbenchTests {
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

}
