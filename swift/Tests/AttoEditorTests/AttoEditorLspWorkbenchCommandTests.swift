import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testLspWorkbenchPanelSummarizesResultFamilies() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench.txt")
        try "docs\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDocumentLinksJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 4 }
            },
            "target": "https://example.com/docs",
            "tooltip": "Open docs"
          }
        ]
        """)

        XCTAssertTrue(vc.showLspWorkbenchPanel())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.lspWorkbenchPanel
        })
        XCTAssertEqual(panel.title, "LSP Workbench (10)")

        let root = try XCTUnwrap(panel.contentView)
        let metadata = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(metadata.stringValue, "4 available | 10 result families | 1 history entry")
        XCTAssertEqual(table.numberOfRows, 10)
        XCTAssertEqual(vc._lspWorkbenchPanelRowCountForTesting(), 10)

        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertEqual(statuses["Document Links"], "1 link")
        XCTAssertEqual(statuses["Document Colors"], "request on open")
        XCTAssertEqual(statuses["Locations"], "0 locations")
        XCTAssertTrue(vc._lspWorkbenchPanelIsVisibleForTesting())
    }

    func testLspWorkbenchDockSummarizesResultFamiliesInline() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-dock.txt")
        try "docs\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDocumentLinksJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 4 }
            },
            "target": "https://example.com/docs",
            "tooltip": "Open docs"
          }
        ]
        """)

        XCTAssertFalse(vc._lspWorkbenchDockIsVisibleForTesting())
        XCTAssertTrue(vc.showLspWorkbenchDock())
        let dockRoot = try XCTUnwrap(findView(identifier: AttoAccessibilityID.lspWorkbenchDock, in: vc.view))
        let metadata = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchDockMetadataLabel, in: dockRoot) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchDockTable, in: dockRoot) as? NSTableView
        )

        XCTAssertEqual(metadata.stringValue, "4 available | 10 result families | 1 history entry")
        XCTAssertEqual(table.numberOfRows, 10)
        XCTAssertEqual(vc._lspWorkbenchDockRowCountForTesting(), 10)

        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchDockItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertEqual(statuses["Document Links"], "1 link")
        XCTAssertEqual(statuses["Document Colors"], "request on open")
        XCTAssertTrue(vc._selectLspWorkbenchDockItemForTesting(id: "document_links"))
        XCTAssertEqual(vc._lspWorkbenchDockSelectedItemForTesting()?.id, "document_links")
        XCTAssertTrue(vc._lspWorkbenchDockIsVisibleForTesting())

        vc.hideLspWorkbenchDock()
        XCTAssertFalse(vc._lspWorkbenchDockIsVisibleForTesting())
    }

    func testLspWorkbenchPanelShowsLifecycleStateForLocationsAndSymbols() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-lifecycle.swift")
        try "struct Project {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let target = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 0,
            utf16Character: 7
        )
        let locationSnapshot = AttoEditorAreaViewController.LspLocationResultSnapshot(
            kind: .definition,
            items: [
                AttoLspDefinitionParser.LocationItem(
                    target: target,
                    fileDisplayName: fileURL.lastPathComponent
                ),
            ]
        )
        let symbolSnapshot = AttoEditorAreaViewController.LspSymbolResultSnapshot(
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

        vc.recordLspLocationResultSnapshot(locationSnapshot)
        vc.recordLspSymbolResultSnapshot(symbolSnapshot)

        XCTAssertTrue(vc.showLspWorkbenchPanel())

        func statuses() -> [String: String] {
            Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
                ($0.title, $0.status)
            })
        }

        var current = statuses()
        let freshLocationPrefix = "1 location | Fresh | Result #1 | locations | Definitions:"
        let staleLocationPrefix = "1 location | Stale: document edited | Result #1 | locations | Definitions:"
        XCTAssertTrue(current["Locations"]?.hasPrefix(freshLocationPrefix) == true)
        XCTAssertEqual(
            current["Symbols"],
            "1 symbol | Fresh | Result #1 | symbols | Document Symbols: 1 results"
        )

        vc.markCurrentLspResultPanelsStale(reason: "document edited")

        current = statuses()
        XCTAssertTrue(current["Locations"]?.hasPrefix(staleLocationPrefix) == true)
        XCTAssertEqual(
            current["Symbols"],
            "1 symbol | Stale: document edited | Result #1 | symbols | Document Symbols: 1 results"
        )

        vc.markCurrentLspSymbolResultError(
            AttoLspResultFeedback.Message(
                statusText: "Workspace symbols: server busy",
                detailText: "Workspace symbols failed."
            )
        )

        current = statuses()
        XCTAssertTrue(current["Locations"]?.hasPrefix(staleLocationPrefix) == true)
        XCTAssertEqual(
            current["Symbols"],
            "1 symbol | Error: Workspace symbols: server busy | Result #1 | symbols | Document Symbols: 1 results"
        )
        XCTAssertEqual(vc._lspWorkbenchPanelRowCountForTesting(), 10)
        XCTAssertTrue(vc._lspWorkbenchPanelIsVisibleForTesting())
    }

    func testLspWorkbenchPanelShowsDiagnosticsLifecycleState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-problems.swift")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 3 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "active problem"
            }
          ],
          "version": 1
        }
        """)
        vc._updateStatusBarForTesting()

        XCTAssertTrue(vc.showLspWorkbenchPanel())

        func statuses() -> [String: String] {
            Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
                ($0.title, $0.status)
            })
        }

        var current = statuses()
        XCTAssertTrue(current["Problems"]?.hasPrefix("1 problem | Fresh | Result #") == true)
        XCTAssertTrue(current["Problems"]?.contains(" | diagnostics.active | workbench-problems.swift") == true)

        try editorView.editor.insertText("!")
        vc._updateStatusBarForTesting()

        current = statuses()
        XCTAssertTrue(current["Problems"]?.hasPrefix("1 problem | Stale: document edited | Result #") == true)
        XCTAssertTrue(current["Problems"]?.contains(" | diagnostics.active | workbench-problems.swift") == true)

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "workspace-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 3 }
                  },
                  "severity": 2,
                  "source": "unit-test",
                  "message": "workspace warning"
                }
              ]
            }
          ]
        }
        """))

        current = statuses()
        XCTAssertTrue(current["Workspace Problems"]?.hasPrefix("1 problem | Fresh | Result #") == true)
        XCTAssertTrue(current["Workspace Problems"]?.contains(" | diagnostics.workspace | Workspace Problems") == true)
        XCTAssertEqual(vc._lspWorkbenchPanelRowCountForTesting(), 10)
        XCTAssertTrue(vc._lspWorkbenchPanelIsVisibleForTesting())
    }

    func testLspWorkbenchPanelKeepsSymbolsAndWorkspaceOutlineEntriesSeparate() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-outline.swift")
        try "struct Project {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "Project",
            "kind": 5,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 17 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 14 }
            }
          }
        ]
        """))

        XCTAssertTrue(vc.showWorkspaceOutlinePanel())
        XCTAssertTrue(vc.showLspWorkbenchPanel())

        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertEqual(
            statuses["Symbols"],
            "1 symbol | Fresh | Result #1 | symbols | Document Symbols: 1 results"
        )
        XCTAssertEqual(
            statuses["Workspace Outline"],
            "1 symbol | Fresh | Result #2 | symbols | Workspace Outline: 1 file, 1 symbol"
        )
        XCTAssertEqual(vc._lspWorkbenchPanelRowCountForTesting(), 10)
        XCTAssertTrue(vc._lspWorkbenchPanelIsVisibleForTesting())
    }

    func testLspWorkbenchPanelShowsDocumentColorLifecycleEvent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workbench-colors.swift")
        try "let color = #ff0000\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showDocumentColorResultJSONInActiveTab("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 12 },
              "end": { "line": 0, "character": 19 }
            },
            "color": { "red": 1, "green": 0, "blue": 0, "alpha": 1 }
          }
        ]
        """))

        XCTAssertTrue(vc.showLspWorkbenchPanel())
        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(statuses["Document Colors"]?.hasPrefix("1 color | Fresh | Result #") == true)
        XCTAssertTrue(
            statuses["Document Colors"]?.contains(" | document_colors | Document Colors: 1 color") == true
        )

        vc.markCurrentLspResultPanelsStale(reason: "document edited")
        let staleStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(staleStatuses["Document Colors"]?.hasPrefix("1 color | Stale: document edited | Result #") == true)
        XCTAssertTrue(
            staleStatuses["Document Colors"]?.contains(" | document_colors | Document Colors: 1 color") == true
        )

        XCTAssertFalse(vc.showDocumentColorsInActiveTab(showFeedback: false))
        let errorStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(
            errorStatuses["Document Colors"]?.hasPrefix("1 color | Error: Document colors: unavailable | Result #") == true
        )
        XCTAssertTrue(
            errorStatuses["Document Colors"]?.contains(" | document_colors | Document Colors: 1 color") == true
        )
        XCTAssertEqual(vc._lspWorkbenchPanelRowCountForTesting(), 10)
        XCTAssertTrue(vc._lspWorkbenchPanelIsVisibleForTesting())
    }

    func testHierarchyResultEntriesRetainExpansionRequestJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hierarchy-expand.swift")
        let entries = AttoLspHierarchyParser.incomingCalls(fromResultJSON: """
        [
          {
            "from": {
              "name": "render",
              "kind": 12,
              "detail": "View.swift",
              "uri": "\(fileURL.absoluteString)",
              "selectionRange": {
                "start": { "line": 3, "character": 9 },
                "end": { "line": 3, "character": 15 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 4, "character": 12 },
                "end": { "line": 4, "character": 18 }
              }
            ]
          }
        ]
        """)
        let entry = try XCTUnwrap(entries.first)
        let vc = makeEditorArea(workspaceRootURL: tempDir)

        XCTAssertEqual(entry.name, "render")
        XCTAssertEqual(entry.target.line, 4)
        XCTAssertEqual(entry.target.utf16Character, 12)
        let item = try XCTUnwrap(vc.hierarchyExpansionItem(from: entry))
        XCTAssertEqual(item.name, "render")
        XCTAssertEqual(item.target.line, 4)
        XCTAssertEqual(item.target.utf16Character, 12)
        XCTAssertTrue(item.requestJSON.contains(#""name":"render""#))
        XCTAssertTrue(item.requestJSON.contains(#""selectionRange""#))
    }

    func testHierarchyRefreshModeUpdatesWorkbenchWithoutOpeningQuickPanel() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hierarchy-refresh.swift")
        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()
        let target = AttoLspDefinitionParser.Target(
            uri: fileURL.absoluteString,
            line: 2,
            utf16Character: 8
        )
        let rootItem = AttoLspHierarchyParser.Item(
            name: "caller",
            detail: "Root.swift",
            kindLabel: "function",
            target: target,
            requestJSON: #"{"name":"caller","uri":"file:///hierarchy-refresh.swift"}"#
        )
        let refreshRequest = AttoEditorAreaViewController.HierarchyPanelRefreshRequest(
            tabID: UUID(),
            kind: .callIncoming,
            item: rootItem
        )
        let entry = AttoLspHierarchyParser.Entry(
            name: "render",
            detail: "View.swift",
            kindLabel: "function",
            target: target,
            relatedRangeCount: 1
        )

        XCTAssertTrue(vc.finishHierarchyRefresh(
            [entry],
            kind: .callIncoming,
            refreshRequest: refreshRequest,
            showFeedback: false,
            editorView: nil
        ))

        let snapshot = try XCTUnwrap(vc._hierarchyPanelSnapshotForTesting())
        XCTAssertEqual(snapshot.title, "Incoming Calls")
        XCTAssertEqual(snapshot.entries.map(\.name), ["render"])
        XCTAssertEqual(vc._hierarchyPanelRefreshRequestForTesting(), refreshRequest)
        XCTAssertFalse(vc._hierarchyPanelIsVisibleForTesting())

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "hierarchy" }
        XCTAssertEqual(events.map(\.payload), [.hierarchy(title: "Incoming Calls", itemCount: 1)])

        let workbenchItem = try XCTUnwrap(vc.lspWorkbenchItems().first { $0.title == "Hierarchy" })
        XCTAssertTrue(workbenchItem.status.hasPrefix("1 result | Fresh | Result #"))
        XCTAssertTrue(workbenchItem.status.contains(" | hierarchy | Incoming Calls"))
        XCTAssertEqual(workbenchItem.historyCount, 1)
        XCTAssertEqual(workbenchItem.jumpTargetCount, 1)
    }

    func testHierarchyPanelUsesLastHierarchyResults() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hierarchy.swift")
        try "func caller() { render() }\nfunc layout() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._showHierarchyResultJSONForTesting("""
        [
          {
            "from": {
              "name": "render",
              "kind": 12,
              "detail": "View.swift",
              "uri": "\(fileURL.absoluteString)",
              "selectionRange": {
                "start": { "line": 0, "character": 16 },
                "end": { "line": 0, "character": 22 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 0, "character": 16 },
                "end": { "line": 0, "character": 22 }
              }
            ]
          },
          {
            "from": {
              "name": "layout",
              "kind": 6,
              "detail": "Layout.swift",
              "uri": "\(fileURL.absoluteString)",
              "selectionRange": {
                "start": { "line": 1, "character": 5 },
                "end": { "line": 1, "character": 11 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 1, "character": 5 },
                "end": { "line": 1, "character": 11 }
              }
            ]
          }
        ]
        """, kind: "callIncoming"))

        XCTAssertTrue(vc.showHierarchyPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.hierarchyPanel
        })
        XCTAssertEqual(panel.title, "Hierarchy (2)")

        let root = try XCTUnwrap(panel.contentView)
        let metadata = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.hierarchyPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.hierarchyPanelTable, in: root) as? NSTableView
        )
        XCTAssertTrue(metadata.stringValue.hasPrefix("2 results | Fresh | Result #"))
        XCTAssertTrue(metadata.stringValue.contains(" | hierarchy | Incoming Calls"))
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._hierarchyPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._hierarchyPanelEntriesForTesting().map(\.name), ["render", "layout"])
        XCTAssertTrue(vc._hierarchyPanelIsVisibleForTesting())

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "hierarchy" }
        XCTAssertEqual(events.map(\.payload), [.hierarchy(title: "Incoming Calls", itemCount: 2)])

        XCTAssertTrue(vc.showLspWorkbenchPanel())
        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(statuses["Hierarchy"]?.hasPrefix("2 results | Fresh | Result #") == true)
        XCTAssertTrue(statuses["Hierarchy"]?.contains(" | hierarchy | Incoming Calls") == true)

        vc.markCurrentLspResultPanelsStale(reason: "document edited")
        let staleStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(staleStatuses["Hierarchy"]?.hasPrefix("2 results | Stale: document edited | Result #") == true)
        XCTAssertTrue(staleStatuses["Hierarchy"]?.contains(" | hierarchy | Incoming Calls") == true)

        XCTAssertFalse(vc.requestLspHierarchyAtPrimaryCaret(kind: .callIncoming, showFeedback: false))
        let errorStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(errorStatuses["Hierarchy"]?.hasPrefix("2 results | Error: Call hierarchy: unavailable | Result #") == true)
        XCTAssertTrue(errorStatuses["Hierarchy"]?.contains(" | hierarchy | Incoming Calls") == true)
    }
}
