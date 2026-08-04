import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testWorkspaceSymbolsPromptRequiresActiveEditor() throws {
        let vc = makeEditorArea(workspaceRootURL: FileManager.default.temporaryDirectory)
        _ = vc.view

        XCTAssertFalse(vc.promptWorkspaceSymbolsInActiveTab(initialQuery: "app"))
    }

    func testWorkspaceSymbolsPromptRequiresEnabledLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("symbols.swift")
        try "func app() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.promptWorkspaceSymbolsInActiveTab(initialQuery: "app"))
        XCTAssertNil(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.WorkspaceSymbolSearch")
        })
    }

    func testApplyFoldingRangesResultUpdatesDerivedState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("folds.txt")
        try """
        import A
        import B
        let value = 1
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(
            vc.applyFoldingRangesResultJSONToActiveTab(
                #"[{"startLine":0,"endLine":1,"kind":"imports"}]"#
            )
        )

        let regions = vc._activeDerivedStateForTesting().foldingRegions.regions
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startLine, 0)
        XCTAssertEqual(regions[0].endLine, 1)
        XCTAssertFalse(regions[0].isCollapsed)
        XCTAssertEqual(regions[0].placeholder, "use ...")
    }

    func testApplyTypedFoldingRangesResultUpdatesDerivedState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-folds.txt")
        try """
        import A
        import B
        let value = 1
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let result = try JSONDecoder().decode(EcuLspFoldingRangeResult.self, from: Data("""
        [
          {
            "startLine": 0,
            "endLine": 1,
            "kind": "imports"
          }
        ]
        """.utf8))

        XCTAssertTrue(vc.applyFoldingRangesResultToActiveTab(result))

        let regions = vc._activeDerivedStateForTesting().foldingRegions.regions
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startLine, 0)
        XCTAssertEqual(regions[0].endLine, 1)
        XCTAssertFalse(regions[0].isCollapsed)
        XCTAssertEqual(regions[0].placeholder, "use ...")
    }

    func testUnifiedLspFeedbackUpdatesTransientStatusForEmptyFoldingRanges() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-folds.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let result = try JSONDecoder().decode(EcuLspFoldingRangeResult.self, from: Data("[]".utf8))
        XCTAssertTrue(vc.applyFoldingRangesResultToActiveTab(result, showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Folding ranges: no results")
    }

    func testApplyTypedSemanticTokensResultUpdatesDerivedStateAndBaseline() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("semantic.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let full = try JSONDecoder().decode(EcuLspSemanticTokensResult.self, from: Data("""
        {
          "resultId": "full-1",
          "data": [0, 4, 5, 7, 0]
        }
        """.utf8))

        XCTAssertTrue(vc.applySemanticTokensResultToActiveTab(full))
        var baseline = try XCTUnwrap(vc._activeSemanticTokensBaselineForTesting())
        XCTAssertEqual(baseline.resultId, "full-1")
        XCTAssertEqual(baseline.data, [0, 4, 5, 7, 0])
        var semanticLayer = try XCTUnwrap(vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 })
        var interval = try XCTUnwrap(semanticLayer.intervals.first)
        XCTAssertEqual(interval.start, 4)
        XCTAssertEqual(interval.end, 9)
        XCTAssertEqual(interval.styleId, 0x0007_0000)

        let delta = try JSONDecoder().decode(EcuLspSemanticTokensResult.self, from: Data("""
        {
          "resultId": "delta-1",
          "edits": [
            { "start": 2, "deleteCount": 1, "data": [3] }
          ]
        }
        """.utf8))

        XCTAssertTrue(vc.applySemanticTokensResultToActiveTab(delta))
        baseline = try XCTUnwrap(vc._activeSemanticTokensBaselineForTesting())
        XCTAssertEqual(baseline.resultId, "delta-1")
        XCTAssertEqual(baseline.data, [0, 4, 3, 7, 0])
        semanticLayer = try XCTUnwrap(vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 })
        interval = try XCTUnwrap(semanticLayer.intervals.first)
        XCTAssertEqual(interval.start, 4)
        XCTAssertEqual(interval.end, 7)
        XCTAssertEqual(interval.styleId, 0x0007_0000)
    }

    func testSemanticHighlightingPreferenceSkipsTypedSemanticTokens() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("semantic-disabled.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let suiteName = "atto_editor_command_semantic_disabled_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        var snapshot = preferences.effectiveConfigurationSnapshot(workspaceRootURL: tempDir)
        snapshot.language.semanticHighlightingEnabled = false

        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir,
            configurationSnapshot: snapshot,
            preferences: preferences
        )
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let full = try JSONDecoder().decode(EcuLspSemanticTokensResult.self, from: Data("""
        {
          "resultId": "full-1",
          "data": [0, 4, 5, 7, 0]
        }
        """.utf8))

        XCTAssertFalse(vc.applySemanticTokensResultToActiveTab(full))
        let baseline = try XCTUnwrap(vc._activeSemanticTokensBaselineForTesting())
        XCTAssertNil(baseline.resultId)
        XCTAssertEqual(baseline.data, [])
        let semanticLayer = vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 }
        XCTAssertTrue(semanticLayer?.intervals.isEmpty ?? true)
    }

    func testApplyingSemanticHighlightingPreferenceClearsExistingTokens() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("semantic-clear.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let full = try JSONDecoder().decode(EcuLspSemanticTokensResult.self, from: Data("""
        {
          "resultId": "full-1",
          "data": [0, 4, 5, 7, 0]
        }
        """.utf8))

        XCTAssertTrue(vc.applySemanticTokensResultToActiveTab(full))
        XCTAssertNotNil(vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 })

        var snapshot = vc._configurationSnapshotForTesting()
        snapshot.language.semanticHighlightingEnabled = false
        vc.updateConfigurationSnapshot(snapshot)
        vc.applyEditorPreferences()

        let baseline = try XCTUnwrap(vc._activeSemanticTokensBaselineForTesting())
        XCTAssertNil(baseline.resultId)
        XCTAssertEqual(baseline.data, [])
        let semanticLayer = vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 }
        XCTAssertTrue(semanticLayer?.intervals.isEmpty ?? true)
    }

    func testRefreshCodeLensRequiresEnabledLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens.txt")
        try "func demo() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.refreshCodeLensInActiveTab(showFeedback: false))
    }

    func testRefreshAuxiliaryLspDecorationsRequireEnabledLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auxiliary.txt")
        try "let value = demo()\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.refreshInlayHintsInActiveTab(showFeedback: false))
        XCTAssertFalse(vc.refreshDocumentLinksInActiveTab(showFeedback: false))
    }

    func testUnresolvedDocumentLinkClickUsesResolveFeedbackWhenLspDisabled() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("links.txt")
        try "a c\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDocumentLinksJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "data": { "id": 42 }
          }
        ]
        """)

        let point = try editorView.editor.charOffsetToViewPoint(offset: 1)
        XCTAssertFalse(editorView.openDocumentLinkIfPresent(xPx: point.xPx + 1, yPx: point.yPx + 1))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Document link resolve: unavailable")
    }

    func testDocumentLinkPanelUsesDerivedDecorations() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("links-panel.txt")
        let text = """
        docs
        local
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._applyDocumentLinksResultJSONForTesting("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 4 }
            },
            "target": "https://example.com/docs",
            "tooltip": "Open docs"
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 5 }
            },
            "tooltip": "Resolve local link",
            "data": { "id": 7 }
          }
        ]
        """))

        XCTAssertTrue(vc.showDocumentLinksPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.documentLinkPanel
        })
        XCTAssertEqual(panel.title, "Document Links (2)")

        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentLinkPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentLinkPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(searchField.placeholderString, "Filter document links...")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._documentLinkPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._documentLinkPanelItemsForTesting().map(\.title), [
            "https://example.com/docs",
            "Resolve local link",
        ])
        XCTAssertEqual(vc._documentLinkPanelItemsForTesting().map(\.target), [
            "https://example.com/docs",
            nil,
        ])
        XCTAssertTrue(vc._documentLinkPanelIsVisibleForTesting())

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "document_links" }
        XCTAssertEqual(events.map(\.payload), [.documentLinks(itemCount: 2)])

        XCTAssertTrue(vc.showLspWorkbenchPanel())
        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(statuses["Document Links"]?.hasPrefix("2 links | Fresh | Result #") == true)
        XCTAssertTrue(
            statuses["Document Links"]?.contains(" | document_links | Document Links: 2 links") == true
        )

        vc.markCurrentLspResultPanelsStale(reason: "document edited")
        let staleStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(staleStatuses["Document Links"]?.hasPrefix("2 links | Stale: document edited | Result #") == true)
        XCTAssertTrue(
            staleStatuses["Document Links"]?.contains(" | document_links | Document Links: 2 links") == true
        )

        XCTAssertFalse(vc.refreshDocumentLinksInActiveTab(showFeedback: false))
        let errorStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(errorStatuses["Document Links"]?.hasPrefix("2 links | Error: Document links: unavailable | Result #") == true)
        XCTAssertTrue(
            errorStatuses["Document Links"]?.contains(" | document_links | Document Links: 2 links") == true
        )
    }

    func testInlayHintClickUsesResolveFeedbackWhenLspDisabled() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hints.txt")
        try "ab\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let hintJSON = """
        {
          "position": { "line": 0, "character": 1 },
          "label": ": Int",
          "data": { "id": 42 }
        }
        """
        XCTAssertFalse(editorView.onInlayHintClick?(hintJSON) ?? true)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Inlay hint resolve: unavailable")
    }

    func testInlayHintPanelUsesDerivedDecorations() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("inlay-panel.swift")
        let text = """
        let value = makeValue()
        call(value)
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._applyInlayHintsResultJSONForTesting("""
        [
          {
            "position": { "line": 0, "character": 9 },
            "label": ": Int",
            "kind": 1
          },
          {
            "position": { "line": 1, "character": 5 },
            "label": [{ "value": "argument:" }],
            "kind": 2
          }
        ]
        """))

        XCTAssertTrue(vc.showInlayHintsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.inlayHintPanel
        })
        XCTAssertEqual(panel.title, "Inlay Hints (2)")

        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.inlayHintPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.inlayHintPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(searchField.placeholderString, "Filter inlay hints...")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._inlayHintPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._inlayHintPanelItemsForTesting().map(\.title), [": Int", "argument:"])
        XCTAssertEqual(vc._inlayHintPanelItemsForTesting().compactMap(\.kindLabel), ["Type", "Parameter"])
        XCTAssertTrue(vc._inlayHintPanelIsVisibleForTesting())

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "inlay_hints" }
        XCTAssertEqual(events.map(\.payload), [.inlayHints(itemCount: 2)])

        XCTAssertTrue(vc.showLspWorkbenchPanel())
        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(statuses["Inlay Hints"]?.hasPrefix("2 hints | Fresh | Result #") == true)
        XCTAssertTrue(
            statuses["Inlay Hints"]?.contains(" | inlay_hints | Inlay Hints: 2 hints") == true
        )

        vc.markCurrentLspResultPanelsStale(reason: "document edited")
        let staleStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(staleStatuses["Inlay Hints"]?.hasPrefix("2 hints | Stale: document edited | Result #") == true)
        XCTAssertTrue(
            staleStatuses["Inlay Hints"]?.contains(" | inlay_hints | Inlay Hints: 2 hints") == true
        )

        XCTAssertFalse(vc.refreshInlayHintsInActiveTab(showFeedback: false))
        let errorStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(errorStatuses["Inlay Hints"]?.hasPrefix("2 hints | Error: Inlay hints: unavailable | Result #") == true)
        XCTAssertTrue(
            errorStatuses["Inlay Hints"]?.contains(" | inlay_hints | Inlay Hints: 2 hints") == true
        )
    }

    func testCodeLensAtCursorFiltersActionsToCurrentLine() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens.swift")
        let text = """
        func one() {}
        func two() {}
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyCodeLensJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 0 }
            },
            "command": { "title": "Run One", "command": "test.runOne" }
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 0 }
            },
            "command": { "title": "Run Two", "command": "test.runTwo" }
          }
        ]
        """)
        let secondLineStart = UInt32("func one() {}\n".unicodeScalars.count)
        try editorView.editor.setSelections(
            [EcuSelectionRange(start: secondLineStart, end: secondLineStart)],
            primaryIndex: 0
        )

        XCTAssertTrue(vc.showCodeLensActionsAtCursorInActiveTab())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.CodeLens")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.CodeLens"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter current-line code lens actions...")

        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.CodeLens"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("Run Two") == true)
        XCTAssertFalse(cell.textField?.stringValue.contains("Run One") == true)
    }

    func testCodeLensPanelUsesDerivedDecorations() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens-panel.swift")
        let text = """
        func one() {}
        func two() {}
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._applyCodeLensResultJSONForTesting("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 0 }
            },
            "command": { "title": "Run One", "command": "test.runOne" }
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 0 }
            },
            "command": { "title": "Run Two", "command": "test.runTwo" }
          }
        ]
        """))

        XCTAssertTrue(vc.showCodeLensPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.codeLensPanel
        })
        XCTAssertEqual(panel.title, "Code Lens (2)")

        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.codeLensPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.codeLensPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(searchField.placeholderString, "Filter code lens actions...")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._codeLensPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._codeLensPanelItemsForTesting().map(\.title), ["Run One", "Run Two"])
        XCTAssertTrue(vc._codeLensPanelIsVisibleForTesting())

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "code_lens" }
        XCTAssertEqual(events.map(\.payload), [.codeLens(itemCount: 2)])

        XCTAssertTrue(vc.showLspWorkbenchPanel())
        let statuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(statuses["Code Lens"]?.hasPrefix("2 actions | Fresh | Result #") == true)
        XCTAssertTrue(
            statuses["Code Lens"]?.contains(" | code_lens | Code Lens: 2 actions") == true
        )

        vc.markCurrentLspResultPanelsStale(reason: "document edited")
        let staleStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(staleStatuses["Code Lens"]?.hasPrefix("2 actions | Stale: document edited | Result #") == true)
        XCTAssertTrue(
            staleStatuses["Code Lens"]?.contains(" | code_lens | Code Lens: 2 actions") == true
        )

        XCTAssertFalse(vc.refreshCodeLensInActiveTab(showFeedback: false))
        let errorStatuses = Dictionary(uniqueKeysWithValues: vc._lspWorkbenchPanelItemsForTesting().map {
            ($0.title, $0.status)
        })
        XCTAssertTrue(errorStatuses["Code Lens"]?.hasPrefix("2 actions | Error: Code lens: unavailable | Result #") == true)
        XCTAssertTrue(
            errorStatuses["Code Lens"]?.contains(" | code_lens | Code Lens: 2 actions") == true
        )
    }

    func testCodeLensCommandWorkspaceEditResultAppliesViaCoreTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("code-lens-command-main.txt")
        let captureURL = tempDir.appendingPathComponent("code-lens-command-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("code-lens-command-fake-lsp.py")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let resultJSON = """
        {
          "changes": {
            "\(fileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ]
          }
        }
        """
        try writeExecuteCommandWorkspaceEditFakeLspServerScript(
            captureURL: captureURL,
            scriptURL: scriptURL,
            resultJSON: resultJSON
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelExecuteCommandUI()
            tab.editCore.editor.lspDisable()
        }

        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let item = try XCTUnwrap(AttoLspCodeLensParser.item(fromCodeLensJSON: """
        {
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 0 }
          },
          "command": {
            "title": "Apply edit",
            "command": "atto.applyEdit",
            "arguments": []
          }
        }
        """))

        XCTAssertTrue(vc.applyCodeLens(item))
        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"workspace/executeCommand""#
        )
        XCTAssertTrue(captured.contains(#""method":"workspace/executeCommand""#), captured)
        XCTAssertEqual(
            waitForCoreWorkspaceEditTransactionSequence(vc, expected: coreTransactionCursor + 1),
            coreTransactionCursor + 1
        )
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).editCore.editor.text(), "aBc\n")
    }

    func testCodeLensActionTitlesUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens-local.swift")
        let projectedURL = tempDir.appendingPathComponent("lens-projected.swift")
        let text = """
        func one() {}
        func two() {}
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyCodeLensJSON("""
        [
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 0 }
            },
            "command": { "title": "Run Two", "command": "test.runTwo" }
          }
        ]
        """)
        let secondLineStart = UInt32("func one() {}\n".unicodeScalars.count)
        try editorView.editor.setSelections(
            [EcuSelectionRange(start: secondLineStart, end: secondLineStart)],
            primaryIndex: 0
        )

        XCTAssertTrue(vc.showCodeLensActionsAtCursorInActiveTab())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.CodeLens")
        })
        let root = try XCTUnwrap(panel.contentView)
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.CodeLens"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        let title = try XCTUnwrap(cell.textField?.stringValue)
        XCTAssertTrue(title.contains("Run Two"))
        XCTAssertTrue(title.contains("lens-projected.swift:2:1"))
        XCTAssertFalse(title.contains("lens-local.swift"))
    }

    func testTypedCodeLensResultSummaryUsesTypedPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)

        let result = try JSONDecoder().decode(EcuLspCodeLensResult.self, from: Data("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 0 }
            },
            "command": { "title": "Run One", "command": "test.runOne" }
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 0 }
            },
            "command": { "title": "Run Two", "command": "test.runTwo" }
          }
        ]
        """.utf8))

        let summary = vc._codeLensResultSummaryForTesting(result)
        XCTAssertNil(summary.errorMessage)
        XCTAssertEqual(summary.count, 2)

        let error = try JSONDecoder().decode(EcuLspCodeLensResult.self, from: Data("""
        {
          "error": {
            "code": -32603,
            "message": "code lens failed"
          }
        }
        """.utf8))

        let errorSummary = vc._codeLensResultSummaryForTesting(error)
        XCTAssertEqual(errorSummary.errorMessage, "code lens failed")
        XCTAssertEqual(errorSummary.count, 0)
    }

    func testTypedAuxiliaryResultSummariesUseTypedPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)

        let inlayHints = try JSONDecoder().decode(EcuLspInlayHintResult.self, from: Data("""
        [
          {
            "position": { "line": 0, "character": 4 },
            "label": ": Int",
            "kind": 1
          },
          {
            "position": { "line": 1, "character": 7 },
            "label": [{ "value": "name:" }],
            "kind": 2
          }
        ]
        """.utf8))
        let inlaySummary = vc._inlayHintResultSummaryForTesting(inlayHints)
        XCTAssertNil(inlaySummary.errorMessage)
        XCTAssertEqual(inlaySummary.count, 2)

        let documentLinks = try JSONDecoder().decode(EcuLspDocumentLinkResult.self, from: Data("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 5 }
            },
            "target": "file:///tmp/readme.md"
          }
        ]
        """.utf8))
        let linkSummary = vc._documentLinkResultSummaryForTesting(documentLinks)
        XCTAssertNil(linkSummary.errorMessage)
        XCTAssertEqual(linkSummary.count, 1)

        let error = try JSONDecoder().decode(EcuLspDocumentLinkResult.self, from: Data("""
        {
          "error": {
            "code": -32603,
            "message": "links failed"
          }
        }
        """.utf8))
        let errorSummary = vc._documentLinkResultSummaryForTesting(error)
        XCTAssertEqual(errorSummary.errorMessage, "links failed")
        XCTAssertEqual(errorSummary.count, 0)
    }

    func testResolvedInlayHintUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("inlay-source-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("inlay-projected-uri.txt")
        try "alpha\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let hint = try JSONDecoder().decode(EcuLspInlayHint.self, from: Data("""
        {
          "position": { "line": 0, "character": 0 },
          "label": ": String",
          "textEdits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "hint "
            }
          ]
        }
        """.utf8))
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))

        XCTAssertTrue(vc.consumeResolvedInlayHint(hint, in: editorView, showFeedback: false))
        XCTAssertEqual(try editorView.editor.text(), "hint alpha\n")
        XCTAssertEqual(try String(contentsOf: projectedURL, encoding: .utf8), "projected\n")
    }

    func testApplyLinkedEditingRangeResultCreatesMulticursorSelections() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("linked.txt")
        try "foo + foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 7, end: 7)], primaryIndex: 0)

        let json = """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """

        XCTAssertTrue(vc.applyLinkedEditingRangeResultJSONToActiveTab(json, caretOffset: 7))

        let selections = try editorView.editor.selections()
        XCTAssertEqual(
            selections.ranges,
            [
                EcuSelectionRange(start: 0, end: 3),
                EcuSelectionRange(start: 6, end: 9),
            ]
        )
        XCTAssertEqual(selections.primaryIndex, 1)
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())
    }

    func testApplyTypedLinkedEditingRangeResultCreatesMulticursorSelections() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-linked.txt")
        try "foo + foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 7, end: 7)], primaryIndex: 0)

        let result = try JSONDecoder().decode(EcuLspLinkedEditingRangeResult.self, from: Data("""
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """.utf8))

        XCTAssertTrue(vc.applyLinkedEditingRangeResultToActiveTab(result, caretOffset: 7))

        let selections = try editorView.editor.selections()
        XCTAssertEqual(
            selections.ranges,
            [
                EcuSelectionRange(start: 0, end: 3),
                EcuSelectionRange(start: 6, end: 9),
            ]
        )
        XCTAssertEqual(selections.primaryIndex, 1)
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())
    }

    func testApplyLinkedEditingRangeResultRejectsWordPatternMismatch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("linked-mismatch.txt")
        try "123 + 123\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        let json = """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """

        XCTAssertFalse(vc.applyLinkedEditingRangeResultJSONToActiveTab(json, caretOffset: 0))

        let selections = try editorView.editor.selections()
        XCTAssertEqual(selections.ranges, [EcuSelectionRange(start: 0, end: 0)])
        XCTAssertEqual(selections.primaryIndex, 0)
        XCTAssertFalse(vc._linkedEditingSessionIsActiveForTesting())
    }

    func testLinkedEditingSessionPersistsAcrossTextMutationAndExitsOnNavigation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("linked-session.txt")
        try "foo + foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 7, end: 7)], primaryIndex: 0)

        let json = """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """

        XCTAssertTrue(vc.applyLinkedEditingRangeResultJSONToActiveTab(json, caretOffset: 7))
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"view","op":"set_wrap_mode","mode":"word"}"#))
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())

        editorView.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(try editorView.editor.text(), "b + b\n")
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())

        XCTAssertTrue(vc.performCursorMovementCommand(.moveLeft))
        XCTAssertFalse(vc._linkedEditingSessionIsActiveForTesting())
    }

    func testDocumentColorPanelUsesDocumentColorResults() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("colors-panel.txt")
        let text = """
        let red = "#ff0000"
        let blue = "#0066ff"
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showDocumentColorPanelResultJSONInActiveTab("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 11 },
              "end": { "line": 0, "character": 18 }
            },
            "color": { "red": 1, "green": 0, "blue": 0, "alpha": 1 }
          },
          {
            "range": {
              "start": { "line": 1, "character": 12 },
              "end": { "line": 1, "character": 19 }
            },
            "color": { "red": 0, "green": 0.4, "blue": 1, "alpha": 1 }
          }
        ]
        """))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.documentColorPanel
        })
        XCTAssertEqual(panel.title, "Document Colors (2)")

        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentColorPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentColorPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(searchField.placeholderString, "Filter document colors...")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._documentColorPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._documentColorPanelItemsForTesting().map { AttoLspDocumentColorParser.hexString(for: $0.color) }, [
            "#FF0000",
            "#0066FF",
        ])
        XCTAssertTrue(vc._documentColorPanelIsVisibleForTesting())
    }

    func testApplyColorPresentationMutatesActiveDocument() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("color.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let presentation = try XCTUnwrap(AttoLspDocumentColorParser.presentations(
            fromColorPresentationResultJSON: """
            [
              {
                "label": "rgb(255, 0, 0)",
                "textEdit": {
                  "range": {
                    "start": { "line": 0, "character": 13 },
                    "end": { "line": 0, "character": 20 }
                  },
                  "newText": "rgb(255, 0, 0)"
                }
              }
            ]
            """,
            documentText: try editorView.editor.text()
        ).first)

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(vc.applyColorPresentationToActiveTab(presentation))
        XCTAssertEqual(try editorView.editor.text(), "let color = \"rgb(255, 0, 0)\"\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testEmptyColorResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-color.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)
        let tabID = try XCTUnwrap(vc.openFileItems().first?.id)

        XCTAssertFalse(vc.showDocumentColorResultJSONInActiveTab("[]", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Document colors: no results")

        let item = AttoLspDocumentColorParser.Item(
            range: EcuSelectionRange(start: 13, end: 20),
            startLine: 0,
            startUTF16Character: 13,
            color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        XCTAssertFalse(vc.showColorPresentationResultJSONInActiveTab(
            "[]",
            item: item,
            tabID: tabID,
            showFeedback: true
        ))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Color presentations: no results")
    }

    func testPickDocumentColorResultOpensPickerAtColorRange() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("pick-color.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        var pickerWasOpened = false
        vc._setDocumentColorPickerForTesting { initialColor in
            pickerWasOpened = true
            XCTAssertEqual(initialColor.redComponent, 1, accuracy: 0.001)
            XCTAssertEqual(initialColor.greenComponent, 0, accuracy: 0.001)
            XCTAssertEqual(initialColor.blueComponent, 0, accuracy: 0.001)
            XCTAssertEqual(initialColor.alphaComponent, 1, accuracy: 0.001)
            return nil
        }
        defer { vc._setDocumentColorPickerForTesting(nil) }

        XCTAssertTrue(vc.pickDocumentColorResultJSONInActiveTab("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 13 },
              "end": { "line": 0, "character": 20 }
            },
            "color": { "red": 1, "green": 0, "blue": 0, "alpha": 1 }
          }
        ]
        """))

        XCTAssertTrue(pickerWasOpened)
        XCTAssertEqual(
            try editorView.editor.selections().ranges,
            [EcuSelectionRange(start: 13, end: 20)]
        )
    }

    func testApplySelectionRangeResultExpandsActiveSelection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("selection.txt")
        try "let value = call(arg)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 17, end: 20)], primaryIndex: 0)

        let resultJSON = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 17 },
              "end": { "line": 0, "character": 20 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 12 },
                "end": { "line": 0, "character": 21 }
              },
              "parent": {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 21 }
                }
              }
            }
          }
        ]
        """

        XCTAssertTrue(vc.applySelectionRangeResultJSONToActiveTab(resultJSON))
        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 12)
        XCTAssertEqual(offsets.end, 21)
    }

    func testApplyTypedSelectionRangeResultExpandsActiveSelection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-selection.txt")
        try "let value = call(arg)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 17, end: 20)], primaryIndex: 0)

        let result = try JSONDecoder().decode(EcuLspSelectionRangeResult.self, from: Data("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 17 },
              "end": { "line": 0, "character": 20 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 12 },
                "end": { "line": 0, "character": 21 }
              }
            }
          }
        ]
        """.utf8))

        XCTAssertTrue(vc.applySelectionRangeResultToActiveTab(result))
        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 12)
        XCTAssertEqual(offsets.end, 21)
    }

    func testApplySelectionRangeResultExpandsMultipleSelectionsByResultOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("selection-multi.txt")
        try "let one = call(a)\nlet two = call(b)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections(
            [
                EcuSelectionRange(start: 15, end: 16),
                EcuSelectionRange(start: 33, end: 34),
            ],
            primaryIndex: 1
        )

        let resultJSON = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 15 },
              "end": { "line": 0, "character": 16 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 10 },
                "end": { "line": 0, "character": 17 }
              }
            }
          },
          {
            "range": {
              "start": { "line": 1, "character": 15 },
              "end": { "line": 1, "character": 16 }
            },
            "parent": {
              "range": {
                "start": { "line": 1, "character": 10 },
                "end": { "line": 1, "character": 17 }
              }
            }
          }
        ]
        """

        XCTAssertTrue(vc.applySelectionRangeResultJSONToActiveTab(resultJSON))
        let selections = try editorView.editor.selections()
        XCTAssertEqual(
            selections.ranges,
            [
                EcuSelectionRange(start: 10, end: 17),
                EcuSelectionRange(start: 28, end: 35),
            ]
        )
        XCTAssertEqual(selections.primaryIndex, 1)
    }
}
