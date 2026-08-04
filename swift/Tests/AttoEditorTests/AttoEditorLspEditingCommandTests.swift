import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testCodeActionResultRecordsLspResultEvent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("code-actions.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._showCodeActionResultJSONForTesting("""
        [
          {
            "title": "Fix import",
            "kind": "quickfix",
            "isPreferred": true
          },
          {
            "title": "Extract method",
            "kind": "refactor.extract"
          }
        ]
        """, onlyKinds: ["quickfix"]))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.CodeActions")
        })
        let root = try XCTUnwrap(panel.contentView)
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.CodeActions"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
        XCTAssertEqual(events.map(\.family), ["code_actions"])
        XCTAssertEqual(events.last?.title, "Code Actions: quickfix: 1 result")
        XCTAssertNil(events.last?.sourceSequence)
        XCTAssertEqual(events.last?.payload, .codeActions(onlyKinds: ["quickfix"], itemCount: 1))
    }

    func testCompletionResultRecordsLspResultEvent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion.swift")
        try "pri".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._showCompletionResultJSONForTesting("""
        {
          "isIncomplete": false,
          "items": [
            { "label": "print", "kind": 3, "detail": "(value: Any)" },
            { "label": "private", "kind": 14 }
          ]
        }
        """))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.completionPanel
        })
        let root = try XCTUnwrap(panel.contentView)
        let table = try XCTUnwrap(findView(identifier: AttoAccessibilityID.completionTable, in: root) as? NSTableView)
        XCTAssertEqual(table.numberOfRows, 2)

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
        XCTAssertEqual(events.map(\.family), ["completion"])
        XCTAssertEqual(events.last?.title, "Completion: 2 items")
        XCTAssertNil(events.last?.sourceSequence)
        XCTAssertEqual(events.last?.payload, .completion(itemCount: 2))
    }

    func testEmptyCompletionResultUsesUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion-empty.swift")
        try "pri".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._showCompletionResultJSONForTesting(#"{ "isIncomplete": false, "items": [] }"#))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Completion: no results")
    }

    func testCompletionAdditionalTextEditsApplyViaWorkspaceEditTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion-workspace-edit.swift")
        try "import Old\npri\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let tab = try XCTUnwrap(vc.activeTab)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 14, end: 14)], primaryIndex: 0)
        let context = try vc.completionRequestContextForCurrentSelection(tab, beepOnFailure: false, showFeedback: true)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let item = try XCTUnwrap(AttoLspCompletionParser.items(fromCompletionResultJSON: """
        [
          {
            "label": "print",
            "textEdit": {
              "range": {
                "start": { "line": 1, "character": 0 },
                "end": { "line": 1, "character": 3 }
              },
              "newText": "print()"
            },
            "additionalTextEdits": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 10 }
                },
                "newText": "import New"
              }
            ]
          }
        ]
        """).first)

        XCTAssertTrue(vc.applyCompletionItem(item, context: context, beepOnFailure: false))
        XCTAssertEqual(try editorView.editor.text(), "import New\nprint()\n")
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertTrue(window.title.contains("●"))
    }

    func testSnippetCompletionAdditionalTextEditsUseWorkspaceEditTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion-snippet-workspace-edit.swift")
        try "import Old\npri\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let tab = try XCTUnwrap(vc.activeTab)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 14, end: 14)], primaryIndex: 0)
        let context = try vc.completionRequestContextForCurrentSelection(tab, beepOnFailure: false, showFeedback: true)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let item = try XCTUnwrap(AttoLspCompletionParser.items(fromCompletionResultJSON: """
        [
          {
            "label": "print",
            "insertTextFormat": 2,
            "textEdit": {
              "range": {
                "start": { "line": 1, "character": 0 },
                "end": { "line": 1, "character": 3 }
              },
              "newText": "print(${1:value})$0"
            },
            "additionalTextEdits": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 10 }
                },
                "newText": "import Foundation"
              }
            ]
          }
        ]
        """).first)

        XCTAssertTrue(vc.applyCompletionItem(item, context: context, beepOnFailure: false))
        XCTAssertEqual(try editorView.editor.text(), "import Foundation\nprint(value)\n")
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertTrue(try editorView.editor.hasActiveSnippetSession())
        XCTAssertTrue(window.title.contains("●"))

        XCTAssertTrue(vc._undoLastCoreWorkspaceEditTransactionForTesting())
        XCTAssertEqual(try editorView.editor.text(), "import Old\npri\n")
        XCTAssertFalse(try editorView.editor.hasActiveSnippetSession())
    }

    func testSnippetCompletionAdditionalDocumentEditsUseWorkspaceEditTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion-snippet-cross-file.swift")
        let otherURL = tempDir.appendingPathComponent("completion-snippet-imports.swift")
        try "pri\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "import Old\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: otherURL, mode: .pinned)
        let otherTab = try XCTUnwrap(vc.activeTab)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let tab = try XCTUnwrap(vc.activeTab)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 3, end: 3)], primaryIndex: 0)
        let context = try vc.completionRequestContextForCurrentSelection(tab, beepOnFailure: false, showFeedback: true)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let item = try XCTUnwrap(AttoLspCompletionParser.items(fromCompletionResultJSON: """
        [
          {
            "label": "print",
            "insertTextFormat": 2,
            "textEdit": {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 3 }
              },
              "newText": "print(${1:value})$0"
            },
            "attoAdditionalTextDocumentEdits": [
              {
                "textDocument": { "uri": "\(otherURL.absoluteString)" },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 10 }
                    },
                    "newText": "import Foundation"
                  }
                ]
              }
            ]
          }
        ]
        """).first)

        XCTAssertTrue(vc.applyCompletionItem(item, context: context, beepOnFailure: false))
        XCTAssertEqual(try editorView.editor.text(), "print(value)\n")
        XCTAssertEqual(try otherTab.editCore.editor.text(), "import Foundation\n")
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertTrue(try editorView.editor.hasActiveSnippetSession())

        XCTAssertTrue(vc._undoLastCoreWorkspaceEditTransactionForTesting())
        XCTAssertEqual(try editorView.editor.text(), "pri\n")
        XCTAssertEqual(try otherTab.editCore.editor.text(), "import Old\n")
        XCTAssertFalse(try editorView.editor.hasActiveSnippetSession())
    }

    func testCompletionWorkspaceEditRetryOwnerRerunsCompletionRequest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion-retry.swift")
        let captureURL = tempDir.appendingPathComponent("completion-retry-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("completion-retry-fake-lsp.py")
        try "pri\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try writeCompletionFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 3, end: 3)], primaryIndex: 0)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelCompletionUI()
            tab.editCore.editor.lspDisable()
        }

        let context = try vc.completionRequestContextForCurrentSelection(tab, beepOnFailure: false, showFeedback: true)
        XCTAssertTrue(vc.retryCompletionWorkspaceEditRequest(context: context))

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/completion""#
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/completion""#), captured)
        XCTAssertTrue(captured.contains(#""line":0"#), captured)
        XCTAssertTrue(captured.contains(#""character":3"#), captured)
    }

    func testFormattingResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("formatting.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.formatDocumentWithLspInActiveTab())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Format document: unavailable")

        XCTAssertFalse(vc.formatSelectionWithLspInActiveTab())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Format selection: no results")
    }

    func testFormattingEditsApplyViaWorkspaceEditTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("formatting-transaction.txt")
        try "unformatted\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("formatting-transaction-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("formatting-transaction-fake-lsp.py")
        try writeFormattingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelFormattingUI()
            tab.editCore.editor.lspDisable()
        }

        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        XCTAssertTrue(vc.formatDocumentWithLspInActiveTab())
        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/formatting""#
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/formatting""#), captured)
        XCTAssertEqual(
            waitForCoreWorkspaceEditTransactionSequence(vc, expected: coreTransactionCursor + 1),
            coreTransactionCursor + 1
        )
        XCTAssertEqual(try tab.editCore.editor.text(), "formatted\n")
    }

    func testDocumentColorResultsRecordLspResultEvents() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("color-events.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let tabID = try XCTUnwrap(vc.openFileItems().first?.id)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        let documentColorJSON = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 13 },
              "end": { "line": 0, "character": 20 }
            },
            "color": { "red": 1, "green": 0, "blue": 0, "alpha": 1 }
          }
        ]
        """
        XCTAssertTrue(vc.showDocumentColorResultJSONInActiveTab(documentColorJSON))
        let item = try XCTUnwrap(AttoLspDocumentColorParser.items(
            fromDocumentColorResultJSON: documentColorJSON,
            documentText: try editorView.editor.text()
        ).first)

        XCTAssertTrue(vc.showColorPresentationResultJSONInActiveTab("""
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
          },
          { "label": "#ff0000" }
        ]
        """, item: item, tabID: tabID))

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "document_colors" || $0.family == "color_presentations" }
        XCTAssertEqual(events.map(\.family), ["document_colors", "color_presentations"])
        XCTAssertEqual(
            events.map(\.payload),
            [
                .documentColors(mode: "presentations", itemCount: 1),
                .colorPresentations(itemCount: 2),
            ]
        )
    }

    func testColorPresentationEditsApplyViaWorkspaceEditTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("color-presentation-transaction.txt")
        try "let color = #ff0000\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)
        let tabID = try XCTUnwrap(vc.openFileItems().first?.id)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let item = AttoLspDocumentColorParser.Item(
            range: EcuSelectionRange(start: 12, end: 19),
            startLine: 0,
            startUTF16Character: 12,
            color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
        )

        XCTAssertTrue(vc.showColorPresentationResultJSONInActiveTab("""
        [
          {
            "label": "rgb(255, 0, 0)",
            "textEdit": {
              "range": {
                "start": { "line": 0, "character": 12 },
                "end": { "line": 0, "character": 19 }
              },
              "newText": "rgb(255, 0, 0)"
            },
            "additionalTextEdits": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "// palette\\n"
              }
            ]
          }
        ]
        """, item: item, tabID: tabID))

        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertEqual(
            try XCTUnwrap(vc.activeTab).editCore.editor.text(),
            "// palette\nlet color = rgb(255, 0, 0)\n"
        )
    }
}
