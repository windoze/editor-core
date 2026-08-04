import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testWorkspaceDiagnosticsResultNavigatesWithoutPanelWindow() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("diagnostics.swift")
        try "first\nab😀cd\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "diag-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 2 },
                    "end": { "line": 1, "character": 4 }
                  },
                  "severity": 1,
                  "message": "demo diagnostic"
                }
              ]
            }
          ]
        }
        """))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let selections = try editorView.editor.selections()
        XCTAssertEqual(selections.ranges, [EcuSelectionRange(start: 8, end: 8)])
        XCTAssertEqual(selections.primaryIndex, 0)
    }

    func testTypedWorkspaceDiagnosticsResultNavigatesWithoutPanelWindow() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-diagnostics.swift")
        try "first\nab😀cd\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let result = try JSONDecoder().decode(EcuLspWorkspaceDiagnosticResult.self, from: Data("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "diag-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 2 },
                    "end": { "line": 1, "character": 4 }
                  },
                  "severity": 1,
                  "message": "typed diagnostic"
                }
              ]
            }
          ]
        }
        """.utf8))

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultInActiveTab(result))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let selections = try editorView.editor.selections()
        XCTAssertEqual(selections.ranges, [EcuSelectionRange(start: 8, end: 8)])
        XCTAssertEqual(selections.primaryIndex, 0)
    }

    func testWorkspaceProblemsPanelUsesStoredDiagnosticsAndRefreshesWithResults() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workspace-problems.swift")
        try "first\nsecond\nthird\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "diag-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 5 }
                  },
                  "severity": 1,
                  "source": "unit-test",
                  "message": "first workspace problem"
                },
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 6 }
                  },
                  "severity": 2,
                  "source": "unit-test",
                  "message": "second workspace warning"
                }
              ]
            }
          ]
        }
        """))

        XCTAssertEqual(vc._workspaceProblemsSnapshotForTesting().diagnostics.map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])
        var diagnosticsLifecycle = vc._diagnosticsLifecycleHistoryForTesting()
        var workspaceLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.workspace" }
        var activeLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.active" }
        XCTAssertEqual(workspaceLifecycleEntries.last?.snapshot.scope, .workspace)
        XCTAssertEqual(workspaceLifecycleEntries.last?.snapshot.problems.map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])
        XCTAssertEqual(activeLifecycleEntries.last?.snapshot.problems.map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])
        XCTAssertEqual(vc._activeMinimapDiagnosticMarkersForTesting(), [
            EditorCoreSkiaMinimapMarker(logicalLine: 0, kind: .error),
            EditorCoreSkiaMinimapMarker(logicalLine: 1, kind: .warning),
        ])
        XCTAssertEqual(vc._activeGutterDiagnosticMarkersForTesting(), [
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 0, charOffset: 0, kind: .error),
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 1, charOffset: 6, kind: .warning),
        ])
        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        var statusLabels = findSubviews(of: NSTextField.self, in: statusBar)
        XCTAssertTrue(statusLabels.contains { $0.stringValue == "Problems: 2" })

        XCTAssertTrue(vc.showWorkspaceProblemsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.workspaceProblemsPanel
        })
        XCTAssertEqual(panel.title, "Workspace Problems (2)")
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelSearchField, in: root) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter workspace problems...")
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.source), [.workspace, .workspace])
        XCTAssertTrue(vc._workspaceProblemsPanelIsVisibleForTesting())
        let diagnosticsCursor = vc._latestDiagnosticsLifecycleSequenceForTesting()
        let diagnosticsResultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()
        vc._updateStatusBarForTesting()
        XCTAssertEqual(vc._diagnosticsLifecycleEventsForTesting(after: diagnosticsCursor), [])
        XCTAssertEqual(vc._lspResultLifecycleEventsForTesting(after: diagnosticsResultEventCursor), [])

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "diag-2",
              "items": [
                {
                  "range": {
                    "start": { "line": 2, "character": 0 },
                    "end": { "line": 2, "character": 5 }
                  },
                  "severity": 1,
                  "source": "unit-test",
                  "message": "third workspace problem"
                }
              ]
            }
          ]
        }
        """))
        XCTAssertEqual(panel.title, "Workspace Problems (1)")
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.message), ["third workspace problem"])
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.source), [.workspace])
        XCTAssertEqual(vc._workspaceProblemsPanelRowCountForTesting(), 1)
        let newDiagnosticsEvents = vc._diagnosticsLifecycleEventsForTesting(after: diagnosticsCursor)
        XCTAssertEqual(newDiagnosticsEvents.map(\.family), ["diagnostics.workspace", "diagnostics.active"])
        XCTAssertEqual(newDiagnosticsEvents.last?.snapshot.problems.map(\.message), ["third workspace problem"])
        let newResultEvents = vc._lspResultLifecycleEventsForTesting(after: diagnosticsResultEventCursor)
        XCTAssertEqual(newResultEvents.map(\.family), ["diagnostics.workspace", "diagnostics.active"])
        XCTAssertEqual(newResultEvents.map(\.sourceSequence), newDiagnosticsEvents.map { Optional($0.sequence) })
        let activeDiagnosticsScope = try XCTUnwrap(newDiagnosticsEvents.last?.snapshot.scope)
        XCTAssertEqual(
            newResultEvents.map(\.payload),
            [
                .diagnostics(
                    scope: .workspace,
                    problemCount: 1,
                    markerCount: 0,
                    isStale: false,
                    staleReason: nil
                ),
                .diagnostics(
                    scope: activeDiagnosticsScope,
                    problemCount: 1,
                    markerCount: 1,
                    isStale: false,
                    staleReason: nil
                ),
            ]
        )
        diagnosticsLifecycle = vc._diagnosticsLifecycleHistoryForTesting()
        workspaceLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.workspace" }
        activeLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.active" }
        XCTAssertEqual(
            Array(workspaceLifecycleEntries.map(\.snapshot.statusText).suffix(2)),
            ["Problems: 2", "Problems: 1"]
        )
        XCTAssertEqual(activeLifecycleEntries.last?.snapshot.problems.map(\.message), ["third workspace problem"])
        XCTAssertEqual(vc._activeMinimapDiagnosticMarkersForTesting(), [
            EditorCoreSkiaMinimapMarker(logicalLine: 2, kind: .error),
        ])
        XCTAssertEqual(vc._activeGutterDiagnosticMarkersForTesting(), [
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 2, charOffset: 13, kind: .error),
        ])
        statusLabels = findSubviews(of: NSTextField.self, in: statusBar)
        XCTAssertTrue(statusLabels.contains { $0.stringValue == "Problems: 1" })
    }

    func testShowProblemsUsesDerivedDiagnosticsAndNavigatesWithoutPanelWindow() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("problems.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let diagnostics = """
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 1, "character": 1 },
                "end": { "line": 1, "character": 2 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "second line problem"
            }
          ],
          "version": 1
        }
        """
        try editorView.editor.lspApplyDiagnosticsJSON(diagnostics)

        XCTAssertTrue(vc.showProblemsInActiveTab())

        let snapshot = vc._activeDerivedStateForTesting()
        XCTAssertEqual(snapshot.diagnostics.diagnostics.count, 1)
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].message, "second line problem")
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].severity, .error)

        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 5)
        XCTAssertEqual(offsets.end, 6)
    }

    func testDiagnosticsLifecycleMarksActiveDiagnosticsStaleAfterDocumentEdit() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("diagnostics-stale.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
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
              "message": "first diagnostic"
            }
          ],
          "version": 1
        }
        """)
        vc._updateStatusBarForTesting()
        XCTAssertFalse(vc._currentDiagnosticsLifecycleEntryForTesting()?.snapshot.isStale ?? true)
        XCTAssertEqual(
            vc._currentDiagnosticsLifecycleEntryForTesting()?.snapshot.problems.map(\.message),
            ["first diagnostic"]
        )

        let baselineCursor = vc._latestDiagnosticsLifecycleSequenceForTesting()
        try editorView.editor.insertText("!")
        vc._updateStatusBarForTesting()

        let staleEvents = vc._diagnosticsLifecycleEventsForTesting(after: baselineCursor)
        XCTAssertEqual(staleEvents.map(\.family), ["diagnostics.active"])
        let staleSnapshot = try XCTUnwrap(staleEvents.last?.snapshot)
        XCTAssertTrue(staleSnapshot.isStale)
        XCTAssertEqual(staleSnapshot.staleReason, .documentEdited)
        XCTAssertEqual(staleSnapshot.problems.map(\.message), ["first diagnostic"])

        let staleCursor = vc._latestDiagnosticsLifecycleSequenceForTesting()
        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 1, "character": 0 },
                "end": { "line": 1, "character": 3 }
              },
              "severity": 2,
              "source": "unit-test",
              "message": "updated diagnostic"
            }
          ],
          "version": 2
        }
        """)
        vc._updateStatusBarForTesting()

        let refreshedEvents = vc._diagnosticsLifecycleEventsForTesting(after: staleCursor)
        XCTAssertEqual(refreshedEvents.map(\.family), ["diagnostics.active"])
        let refreshedSnapshot = try XCTUnwrap(refreshedEvents.last?.snapshot)
        XCTAssertFalse(refreshedSnapshot.isStale)
        XCTAssertNil(refreshedSnapshot.staleReason)
        XCTAssertEqual(refreshedSnapshot.problems.map(\.message), ["updated diagnostic"])
    }

    func testProblemsPanelUsesDerivedDiagnosticsAndRefreshesWithStatusUpdate() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("problems-panel.txt")
        try "abc\ndef\nghi\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
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
              "message": "first line problem"
            },
            {
              "range": {
                "start": { "line": 1, "character": 1 },
                "end": { "line": 1, "character": 2 }
              },
              "severity": 2,
              "source": "unit-test",
              "message": "second line warning"
            }
          ],
          "version": 1
        }
        """)

        XCTAssertTrue(vc.showProblemsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.problemsPanel
        })
        XCTAssertEqual(panel.title, "Problems (2)")
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelSearchField, in: root) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter problems...")
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "first line problem",
            "second line warning",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .active])
        XCTAssertTrue(vc._problemsPanelIsVisibleForTesting())

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "panel-workspace-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 3 }
                  },
                  "severity": 1,
                  "source": "workspace-test",
                  "message": "workspace current file problem"
                }
              ]
            },
            {
              "uri": "\(tempDir.appendingPathComponent("other.txt").absoluteString)",
              "kind": "full",
              "resultId": "panel-workspace-other",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 1 }
                  },
                  "severity": 2,
                  "source": "workspace-test",
                  "message": "workspace other file warning"
                }
              ]
            }
          ]
        }
        """))
        XCTAssertEqual(panel.title, "Problems (3)")
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "first line problem",
            "second line warning",
            "workspace current file problem",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .active, .workspace])

        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 2, "character": 0 },
                "end": { "line": 2, "character": 3 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "third line problem"
            }
          ],
          "version": 2
        }
        """)
        vc._updateStatusBarForTesting()
        XCTAssertEqual(panel.title, "Problems (2)")
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "third line problem",
            "workspace current file problem",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .workspace])
        XCTAssertEqual(vc._problemsPanelRowCountForTesting(), 2)
    }

    func testActiveProblemsUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("diagnostics-local.swift")
        let projectedURL = tempDir.appendingPathComponent("diagnostics-projected.swift")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

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
        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(projectedURL.standardizedFileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 3 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "active projected problem"
            }
          ],
          "version": 1
        }
        """)

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(projectedURL.standardizedFileURL.absoluteString)",
              "kind": "full",
              "resultId": "projected-diagnostics",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 1 },
                    "end": { "line": 1, "character": 2 }
                  },
                  "severity": 2,
                  "source": "workspace-test",
                  "message": "projected workspace problem"
                }
              ]
            }
          ]
        }
        """))

        let lifecycleEntry = try XCTUnwrap(vc._currentDiagnosticsLifecycleEntryForTesting())
        XCTAssertEqual(lifecycleEntry.family, "diagnostics.active")
        XCTAssertEqual(lifecycleEntry.title, "diagnostics-projected.swift")
        guard case let .activeTab(tabID: lifecycleTabID, fileURL: lifecycleURL) = lifecycleEntry.snapshot.scope else {
            return XCTFail("Expected active-tab diagnostics scope")
        }
        XCTAssertEqual(lifecycleTabID, tab.id)
        XCTAssertEqual(lifecycleURL, projectedURL.standardizedFileURL)
        XCTAssertEqual(lifecycleEntry.snapshot.problems.map(\.message), [
            "active projected problem",
            "projected workspace problem",
        ])
        XCTAssertEqual(lifecycleEntry.snapshot.problems.map(\.source), [.active, .workspace])
        XCTAssertEqual(lifecycleEntry.snapshot.markerProjections, [
            AttoDiagnosticMarkerProjection(logicalLine: 0, charOffset: 0, severity: .error, source: .active),
            AttoDiagnosticMarkerProjection(logicalLine: 1, charOffset: 5, severity: .warning, source: .workspace),
        ])

        let activeProblem = try XCTUnwrap(lifecycleEntry.snapshot.problems.first { $0.source == .active })
        XCTAssertTrue(vc.displayTitle(for: activeProblem, in: tab).contains("diagnostics-projected.swift:1:1"))

        XCTAssertTrue(vc.showProblemsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.problemsPanel
        })
        XCTAssertEqual(panel.title, "Problems (2)")
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "active projected problem",
            "projected workspace problem",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .workspace])
    }
}
