import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testImplementationMultiLocationResultUsesPanel() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("impl.swift")
        try "func one() {}\nfunc two() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc.showLspLocationResultJSONInActiveTab("""
        [
          {
            "uri": "\(fileURL.absoluteString)",
            "range": {
              "start": { "line": 0, "character": 5 },
              "end": { "line": 0, "character": 8 }
            }
          },
          {
            "uri": "\(fileURL.absoluteString)",
            "range": {
              "start": { "line": 1, "character": 5 },
              "end": { "line": 1, "character": 8 }
            }
          }
        ]
        """, kind: .implementation))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.LocationResults")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.LocationResults"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter implementations...")

        let snapshot = try XCTUnwrap(vc._lastLspLocationResultForTesting())
        XCTAssertEqual(snapshot.kind, .implementation)
        XCTAssertEqual(snapshot.items.count, 2)

        XCTAssertTrue(vc.showLspLocationPanel())
        let persistentPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.lspLocationPanel
        })
        XCTAssertEqual(persistentPanel.title, "Implementations (2)")
        let persistentRoot = try XCTUnwrap(persistentPanel.contentView)
        let persistentSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspLocationPanelSearchField,
                in: persistentRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(persistentSearchField.placeholderString, "Filter implementations...")
        let persistentMetadataLabel = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspLocationPanelMetadataLabel,
                in: persistentRoot
            ) as? NSTextField
        )
        let persistentTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspLocationPanelTable,
                in: persistentRoot
            ) as? NSTableView
        )
        XCTAssertEqual(persistentTable.numberOfRows, 2)
        XCTAssertEqual(vc._lspLocationPanelSnapshotForTesting(), snapshot)
        let panelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(panelEntry.sequence, 1)
        XCTAssertEqual(panelEntry.family, "locations")
        XCTAssertTrue(panelEntry.title.hasPrefix("Implementations:"))
        XCTAssertEqual(panelEntry.state, .fresh)
        XCTAssertEqual(panelEntry.snapshot, snapshot)
        XCTAssertEqual(persistentMetadataLabel.stringValue, "Fresh | Result #1 | locations | \(panelEntry.title)")
        XCTAssertTrue(vc._lspLocationPanelIsVisibleForTesting())

        vc._updateStatusBarForTesting()
        try editorView.editor.insertText("!")
        vc._updateStatusBarForTesting()

        let stalePanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(stalePanelEntry.sequence, panelEntry.sequence)
        XCTAssertEqual(stalePanelEntry.state, .stale(reason: "document edited"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Stale: document edited | Result #1 | locations | \(panelEntry.title)"
        )

        panel.close()
        XCTAssertTrue(vc.showLastLspLocationResults())

        let reopenedPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.LocationResults")
        })
        let reopenedRoot = try XCTUnwrap(reopenedPanel.contentView)
        let reopenedSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.LocationResults"),
                in: reopenedRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(reopenedSearchField.placeholderString, "Filter implementations...")

        reopenedPanel.close()
        XCTAssertTrue(vc.showLspLocationResultJSONInActiveTab("""
        {
          "uri": "\(fileURL.absoluteString)",
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 3 }
          }
        }
        """, kind: .definition))
        XCTAssertEqual(vc._lspLocationResultHistoryForTesting().map(\.kind), [.implementation, .definition])
        let locationEntries = vc._lspLocationResultLifecycleHistoryForTesting()
        XCTAssertEqual(locationEntries.map(\.sequence), [1, 2])
        XCTAssertEqual(locationEntries.map(\.family), ["locations", "locations"])
        XCTAssertEqual(locationEntries.map(\.state), [.stale(reason: "document edited"), .fresh])
        XCTAssertEqual(locationEntries.map(\.snapshot.kind), [.implementation, .definition])
        XCTAssertTrue(locationEntries[0].title.hasPrefix("Implementations:"))
        XCTAssertTrue(locationEntries[1].title.hasPrefix("Definitions:"))
        let resultEvents = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "locations" }
        XCTAssertEqual(resultEvents.map(\.family), ["locations", "locations"])
        XCTAssertEqual(resultEvents.map(\.sourceSequence), locationEntries.map { Optional($0.sequence) })
        XCTAssertEqual(
            resultEvents.map(\.payload),
            [
                .locations(kind: "implementation", itemCount: 2),
                .locations(kind: "definition", itemCount: 1),
            ]
        )
        let updatedPanelSnapshot = try XCTUnwrap(vc._lspLocationPanelSnapshotForTesting())
        XCTAssertEqual(updatedPanelSnapshot.kind, .definition)
        let updatedPanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(updatedPanelEntry.sequence, 2)
        XCTAssertEqual(updatedPanelEntry.family, "locations")
        XCTAssertTrue(updatedPanelEntry.title.hasPrefix("Definitions:"))
        XCTAssertEqual(updatedPanelEntry.state, .fresh)
        XCTAssertEqual(updatedPanelEntry.snapshot, updatedPanelSnapshot)
        XCTAssertEqual(persistentMetadataLabel.stringValue, "Fresh | Result #2 | locations | \(updatedPanelEntry.title)")
        XCTAssertEqual(vc._lspLocationPanelRowCountForTesting(), 1)

        let projectErrorCursor = vc._latestProjectLspPanelErrorEventSequenceForTesting()
        XCTAssertFalse(vc._recordProjectLspPanelErrorForTesting(
            family: "completion",
            title: "LSP Completion",
            slot: "completion",
            status: "error",
            message: "completion failed"
        ))
        XCTAssertTrue(vc._recordProjectLspPanelErrorForTesting(
            family: "locations",
            title: "LSP References",
            slot: "references",
            status: "error",
            message: "server busy"
        ))
        let projectErrors = vc._projectLspPanelErrorEventsForTesting(after: projectErrorCursor)
        XCTAssertEqual(projectErrors.count, 1)
        XCTAssertEqual(projectErrors[0].family, "locations")
        XCTAssertEqual(projectErrors[0].slot, "references")
        XCTAssertEqual(projectErrors[0].message, "LSP References: server busy")
        let projectErrorPanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(projectErrorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(projectErrorPanelEntry.state, .error(message: "LSP References: server busy"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: LSP References: server busy | Result #2 | locations | \(updatedPanelEntry.title)"
        )

        let activeEditorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        activeEditorView.editor.lspDisable()
        XCTAssertFalse(vc.goToImplementationInActiveTab())
        let errorPanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(errorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(errorPanelEntry.state, .error(message: "Implementation: unavailable"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: Implementation: unavailable | Result #2 | locations | \(updatedPanelEntry.title)"
        )

        XCTAssertTrue(vc.showLspLocationHistory())
        let historyPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.LocationHistory")
        })
        let historyRoot = try XCTUnwrap(historyPanel.contentView)
        let historySearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.LocationHistory"),
                in: historyRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(historySearchField.placeholderString, "Filter location history...")
        let historyTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.LocationHistory"),
                in: historyRoot
            ) as? NSTableView
        )
        XCTAssertEqual(historyTable.numberOfRows, 2)
        let firstCell = try XCTUnwrap(historyTable.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(firstCell.textField?.stringValue.contains("Definitions") == true)
    }

    func testEmptyLocationResultUsesUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("definition.swift")
        try "func call() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.showLspLocationResultJSONInActiveTab("[]", kind: .definition))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Definition: no results")
    }

    func testLspTargetNavigationUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lsp-target-source.swift")
        let projectedURL = tempDir.appendingPathComponent("lsp-target-projected.swift")
        try "aa\nlet target = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        vc.navigateToLspTarget(.init(
            uri: projectedURL.standardizedFileURL.absoluteString,
            line: 1,
            utf16Character: 4
        ))

        XCTAssertEqual(vc.tabs.count, 1)
        XCTAssertEqual(vc.selectedTabID, tab.id)

        let offsets = try tab.editCore.editor.selectionOffsets()
        let position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 4)
    }

    func testEmptySymbolResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("symbols.swift")
        try "func call() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.showDocumentSymbolResultJSONInActiveTab("[]"))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Document symbols: no results")

        XCTAssertFalse(vc.showWorkspaceSymbolResultJSONInActiveTab("[]", query: "  App  "))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Workspace symbols: no results")
    }

    func testWorkspaceOutlinePanelAggregatesDocumentSymbolSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appURL = tempDir.appendingPathComponent("App.swift")
        let modelURL = tempDir.appendingPathComponent("Model.swift")
        try "struct App {\n  func run() {}\n}\n".write(to: appURL, atomically: true, encoding: .utf8)
        try "final class Model {}\n".write(to: modelURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)

        vc.openFile(url: appURL, mode: .pinned)
        XCTAssertTrue(vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "App",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 2, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 10 }
            },
            "children": [
              {
                "name": "run",
                "detail": "fn()",
                "kind": 12,
                "range": {
                  "start": { "line": 1, "character": 2 },
                  "end": { "line": 1, "character": 15 }
                },
                "selectionRange": {
                  "start": { "line": 1, "character": 7 },
                  "end": { "line": 1, "character": 10 }
                }
              }
            ]
          }
        ]
        """))

        vc.openFile(url: modelURL, mode: .pinned)
        XCTAssertTrue(vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "Model",
            "kind": 5,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 20 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 12 },
              "end": { "line": 0, "character": 17 }
            }
          }
        ]
        """))

        let outline = vc._workspaceOutlineSnapshotForTesting()
        XCTAssertEqual(outline.documents.map(\.title), ["App.swift", "Model.swift"])
        XCTAssertEqual(outline.documents.map(\.symbolCount), [2, 1])
        XCTAssertEqual(outline.symbols.map(\.name), ["App", "run", "Model"])
        XCTAssertEqual(outline.symbols.map(\.containerName), ["App.swift", "App.swift", "Model.swift"])

        XCTAssertTrue(vc.showWorkspaceOutlinePanel())
        let persistentPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.lspSymbolPanel
        })
        XCTAssertEqual(persistentPanel.title, "Workspace Outline (3)")
        let persistentRoot = try XCTUnwrap(persistentPanel.contentView)
        let persistentSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelSearchField,
                in: persistentRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(persistentSearchField.placeholderString, "Filter workspace outline...")
        let persistentMetadataLabel = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelMetadataLabel,
                in: persistentRoot
            ) as? NSTextField
        )
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Fresh | Result #3 | symbols | Workspace Outline: 2 files, 3 symbols"
        )
        XCTAssertEqual(vc._lspSymbolPanelRowCountForTesting(), 3)
        XCTAssertEqual(vc._lspSymbolPanelSnapshotForTesting()?.symbols.map(\.name), ["App", "run", "Model"])
    }

    func testDocumentSymbolsUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("SymbolsSource.swift")
        let projectedURL = tempDir.appendingPathComponent("SymbolsProjected.swift")
        try "struct Source {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "struct Projected {}\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        XCTAssertTrue(vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "Source",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 16 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 13 }
            }
          }
        ]
        """))

        let symbolSnapshot = try XCTUnwrap(vc._lastLspSymbolResultForTesting())
        XCTAssertEqual(symbolSnapshot.symbols.map(\.target.uri), [
            projectedURL.standardizedFileURL.absoluteString,
        ])

        let outline = vc._workspaceOutlineSnapshotForTesting()
        XCTAssertEqual(outline.documents.map(\.uri), [
            projectedURL.standardizedFileURL.absoluteString,
        ])
        XCTAssertEqual(outline.symbols.map(\.target.uri), [
            projectedURL.standardizedFileURL.absoluteString,
        ])
    }

    func testWorkspaceSymbolResultCanBeReopened() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("symbols.swift")
        try "func openProject() {}\nstruct Project {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc.showWorkspaceSymbolResultJSONInActiveTab("""
        [
          {
            "name": "openProject",
            "kind": 12,
            "location": {
              "uri": "\(fileURL.absoluteString)",
              "range": {
                "start": { "line": 0, "character": 5 },
                "end": { "line": 0, "character": 16 }
              }
            }
          },
          {
            "name": "Project",
            "kind": 23,
            "location": { "uri": "\(fileURL.absoluteString)" }
          }
        ]
        """, query: "Project"))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.SymbolResults")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.SymbolResults"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter workspace symbols...")

        let snapshot = try XCTUnwrap(vc._lastLspSymbolResultForTesting())
        XCTAssertEqual(snapshot.symbols.map(\.name), ["Project", "openProject"])
        XCTAssertEqual(snapshot.placeholder, "Filter workspace symbols...")

        XCTAssertTrue(vc.showLspSymbolPanel())
        let persistentPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.lspSymbolPanel
        })
        XCTAssertEqual(persistentPanel.title, "Workspace Symbols: Project (2)")
        let persistentRoot = try XCTUnwrap(persistentPanel.contentView)
        let persistentSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelSearchField,
                in: persistentRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(persistentSearchField.placeholderString, "Filter workspace symbols...")
        let persistentMetadataLabel = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelMetadataLabel,
                in: persistentRoot
            ) as? NSTextField
        )
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Fresh | Result #1 | symbols | Workspace Symbols: Project: 2 results"
        )
        let persistentTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelTable,
                in: persistentRoot
            ) as? NSTableView
        )
        XCTAssertEqual(persistentTable.numberOfRows, 2)
        XCTAssertEqual(vc._lspSymbolPanelSnapshotForTesting(), snapshot)
        let panelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(panelEntry.sequence, 1)
        XCTAssertEqual(panelEntry.family, "symbols")
        XCTAssertEqual(panelEntry.title, "Workspace Symbols: Project: 2 results")
        XCTAssertEqual(panelEntry.state, .fresh)
        XCTAssertEqual(panelEntry.snapshot, snapshot)
        XCTAssertTrue(vc._lspSymbolPanelIsVisibleForTesting())

        vc._updateStatusBarForTesting()
        try editorView.editor.insertText("!")
        vc._updateStatusBarForTesting()

        let stalePanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(stalePanelEntry.sequence, panelEntry.sequence)
        XCTAssertEqual(stalePanelEntry.state, .stale(reason: "document edited"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Stale: document edited | Result #1 | symbols | Workspace Symbols: Project: 2 results"
        )

        panel.close()
        XCTAssertTrue(vc.showLastLspSymbolResults())

        let reopenedPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.SymbolResults")
        })
        let reopenedRoot = try XCTUnwrap(reopenedPanel.contentView)
        let reopenedSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.SymbolResults"),
                in: reopenedRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(reopenedSearchField.placeholderString, "Filter workspace symbols...")

        reopenedPanel.close()
        XCTAssertTrue(vc.showWorkspaceSymbolResultJSONInActiveTab("""
        [
          {
            "name": "openProject",
            "kind": 12,
            "location": {
              "uri": "\(fileURL.absoluteString)",
              "range": {
                "start": { "line": 0, "character": 5 },
                "end": { "line": 0, "character": 16 }
              }
            }
          }
        ]
        """, query: "Open"))

        let history = vc._lspSymbolResultHistoryForTesting()
        XCTAssertEqual(history.map(\.title), ["Workspace Symbols: Project", "Workspace Symbols: Open"])
        let symbolEntries = vc._lspSymbolResultLifecycleHistoryForTesting()
        XCTAssertEqual(symbolEntries.map(\.sequence), [1, 2])
        XCTAssertEqual(symbolEntries.map(\.family), ["symbols", "symbols"])
        XCTAssertEqual(symbolEntries.map(\.state), [.stale(reason: "document edited"), .fresh])
        XCTAssertEqual(symbolEntries.map(\.snapshot.title), ["Workspace Symbols: Project", "Workspace Symbols: Open"])
        XCTAssertEqual(symbolEntries.map(\.title), ["Workspace Symbols: Project: 2 results", "Workspace Symbols: Open: 1 results"])
        let resultEvents = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "symbols" }
        XCTAssertEqual(resultEvents.map(\.family), ["symbols", "symbols"])
        XCTAssertEqual(resultEvents.map(\.sourceSequence), symbolEntries.map { Optional($0.sequence) })
        XCTAssertEqual(
            resultEvents.map(\.payload),
            [
                .symbols(title: "Workspace Symbols: Project", itemCount: 2),
                .symbols(title: "Workspace Symbols: Open", itemCount: 1),
            ]
        )
        let updatedPanelSnapshot = try XCTUnwrap(vc._lspSymbolPanelSnapshotForTesting())
        XCTAssertEqual(updatedPanelSnapshot.title, "Workspace Symbols: Open")
        let updatedPanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(updatedPanelEntry.sequence, 2)
        XCTAssertEqual(updatedPanelEntry.family, "symbols")
        XCTAssertEqual(updatedPanelEntry.title, "Workspace Symbols: Open: 1 results")
        XCTAssertEqual(updatedPanelEntry.state, .fresh)
        XCTAssertEqual(updatedPanelEntry.snapshot, updatedPanelSnapshot)
        XCTAssertEqual(persistentMetadataLabel.stringValue, "Fresh | Result #2 | symbols | Workspace Symbols: Open: 1 results")
        XCTAssertEqual(vc._lspSymbolPanelRowCountForTesting(), 1)

        let projectErrorCursor = vc._latestProjectLspPanelErrorEventSequenceForTesting()
        XCTAssertFalse(vc._recordProjectLspPanelErrorForTesting(
            family: "locations",
            title: "LSP References",
            slot: "references",
            status: "success",
            message: "ignored"
        ))
        XCTAssertTrue(vc._recordProjectLspPanelErrorForTesting(
            family: "symbols",
            title: "LSP Workspace Symbols",
            slot: "workspace_symbols",
            status: "timeout",
            message: ""
        ))
        let projectErrors = vc._projectLspPanelErrorEventsForTesting(after: projectErrorCursor)
        XCTAssertEqual(projectErrors.count, 1)
        XCTAssertEqual(projectErrors[0].family, "symbols")
        XCTAssertEqual(projectErrors[0].slot, "workspace_symbols")
        XCTAssertEqual(projectErrors[0].message, "LSP Workspace Symbols: timeout")
        let projectErrorPanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(projectErrorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(projectErrorPanelEntry.state, .error(message: "LSP Workspace Symbols: timeout"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: LSP Workspace Symbols: timeout | Result #2 | symbols | Workspace Symbols: Open: 1 results"
        )

        let activeEditorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        activeEditorView.editor.lspDisable()
        XCTAssertFalse(vc.showWorkspaceSymbolsInActiveTab(query: "Broken"))
        let errorPanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(errorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(errorPanelEntry.state, .error(message: "Workspace symbols: unavailable"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: Workspace symbols: unavailable | Result #2 | symbols | Workspace Symbols: Open: 1 results"
        )

        XCTAssertTrue(vc.showLspSymbolHistory())
        let historyPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.SymbolHistory")
        })
        let historyRoot = try XCTUnwrap(historyPanel.contentView)
        let historySearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.SymbolHistory"),
                in: historyRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(historySearchField.placeholderString, "Filter symbol history...")
        let historyTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.SymbolHistory"),
                in: historyRoot
            ) as? NSTableView
        )
        XCTAssertEqual(historyTable.numberOfRows, 2)
        let firstCell = try XCTUnwrap(historyTable.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(firstCell.textField?.stringValue.contains("Workspace Symbols: Open") == true)
    }

    func testEmptyCodeActionResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-code-actions.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._showCodeActionResultJSONForTesting("[]", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Code actions: no results")
    }

    func testEmptyRenameResultUsesUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-rename.swift")
        try "let oldName = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._applyRenameResultJSONForTesting(#"{}"#, newName: "newName", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Rename: no results")
    }

    func testEmptyHierarchyResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-hierarchy.swift")
        try "func caller() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._showHierarchyResultJSONForTesting("[]", kind: "callIncoming", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Call hierarchy: no results")

        XCTAssertFalse(vc._showHierarchyResultJSONForTesting("[]", kind: "typeSupertypes", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Type hierarchy: no results")
    }

    func testRenameResultRecordsLspResultEvent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rename-event.swift")
        try "let oldName = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._applyRenameResultJSONForTesting("""
        {
          "changes": {
            "\(fileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 4 },
                  "end": { "line": 0, "character": 11 }
                },
                "newText": "newName"
              }
            ]
          }
        }
        """, newName: "newName"))

        XCTAssertEqual(try editorView.editor.text(), "let newName = 1\n")
        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
        let renameEvents = events.filter { $0.family == "rename" }
        XCTAssertEqual(renameEvents.count, 1)
        XCTAssertEqual(renameEvents.last?.title, "Rename: newName")
        XCTAssertNil(renameEvents.last?.sourceSequence)
        XCTAssertEqual(
            renameEvents.last?.payload,
            .rename(newName: "newName", documentCount: 1, resourceOperationCount: 0, applied: true)
        )
    }

    func testRenameResultUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rename-source-uri.swift")
        let projectedURL = tempDir.appendingPathComponent("rename-projected-uri.swift")
        try "let oldName = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        XCTAssertTrue(vc._applyRenameResultJSONForTesting("""
        {
          "changes": {
            "\(projectedURL.standardizedFileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 4 },
                  "end": { "line": 0, "character": 11 }
                },
                "newText": "newName"
              }
            ]
          }
        }
        """, newName: "newName"))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "let newName = 1\n")
        XCTAssertEqual(try String(contentsOf: projectedURL, encoding: .utf8), "projected\n")
    }

    func testRenameCandidateUsesSelectionOrIdentifierAtCaret() throws {
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "alpha", caretOffset: 0),
            "alpha"
        )
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "", caretOffset: 7),
            "alpha"
        )
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "", caretOffset: 9),
            "alpha"
        )
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "alpha\nbeta", caretOffset: 0),
            "let"
        )
    }

    func testPrepareRenameDialogSeedUsesPlaceholderRangeAndFallback() throws {
        let fallback = AttoLspRenameSupport.DialogSeed(initialName: "fallback", placeholder: nil)

        let placeholderJSON = """
        {
          "range": {
            "start": { "line": 0, "character": 4 },
            "end": { "line": 0, "character": 9 }
          },
          "placeholder": "serverName"
        }
        """
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: placeholderJSON,
                fallback: fallback
            ),
            AttoLspRenameSupport.DialogSeed(initialName: "serverName", placeholder: "serverName")
        )

        let rangeOnlyJSON = """
        {
          "start": { "line": 0, "character": 4 },
          "end": { "line": 0, "character": 9 }
        }
        """
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: rangeOnlyJSON,
                fallback: fallback
            ).initialName,
            "alpha"
        )

        let emojiText = "let emoji_\u{1F600} = 1\n"
        let emojiRangeJSON = """
        {
          "start": { "line": 0, "character": 4 },
          "end": { "line": 0, "character": 12 }
        }
        """
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: emojiText,
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: emojiRangeJSON,
                fallback: fallback
            ).initialName,
            "emoji_\u{1F600}"
        )

        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: #"{"defaultBehavior":true}"#,
                fallback: fallback
            ),
            fallback
        )
    }

    func testPrepareRenameDialogSeedUsesTypedResult() throws {
        let fallback = AttoLspRenameSupport.DialogSeed(initialName: "fallback", placeholder: "Fallback")
        let placeholder = try JSONDecoder().decode(EcuLspPrepareRenameResult.self, from: Data("""
        {
          "range": {
            "start": { "line": 0, "character": 4 },
            "end": { "line": 0, "character": 9 }
          },
          "placeholder": "serverName"
        }
        """.utf8))

        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResult: placeholder,
                fallback: fallback
            ),
            AttoLspRenameSupport.DialogSeed(initialName: "serverName", placeholder: "serverName")
        )

        let rangeOnly = try JSONDecoder().decode(EcuLspPrepareRenameResult.self, from: Data("""
        {
          "start": { "line": 0, "character": 4 },
          "end": { "line": 0, "character": 9 }
        }
        """.utf8))
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResult: rangeOnly,
                fallback: fallback
            ),
            AttoLspRenameSupport.DialogSeed(initialName: "alpha", placeholder: "Fallback")
        )

        let defaultBehavior = try JSONDecoder().decode(
            EcuLspPrepareRenameResult.self,
            from: Data(#"{"defaultBehavior":true}"#.utf8)
        )
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResult: defaultBehavior,
                fallback: fallback
            ),
            fallback
        )
    }
}
