import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testWorkspaceEditApplicationMutatesTextAndDirtyState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rename.txt")
        let otherURL = tempDir.appendingPathComponent("other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
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
            ],
            "\(otherURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testWorkspaceEditTransactionUndoRestoresAppProjectionAndFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("undo-main.txt")
        let otherURL = tempDir.appendingPathComponent("undo-other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)

        let workspaceEdit = """
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
            ],
            "\(otherURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(window.title.contains("●"))

        XCTAssertTrue(vc._undoLastCoreWorkspaceEditTransactionForTesting())
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
        XCTAssertFalse(window.title.contains("●"))
        XCTAssertFalse(vc._undoLastCoreWorkspaceEditTransactionForTesting())
    }

    func testWorkspaceEditTransactionUndoCommandRestoresAppProjectionAndFiles() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("undo-command-main.txt")
        let otherURL = tempDir.appendingPathComponent("undo-command-other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(ctx.editorAreaController)

        let workspaceEdit = """
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
            ],
            "\(otherURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        XCTAssertTrue(ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(ctx.window.title.contains("●"))

        let secondWorkspaceEdit = """
        {
          "changes": {
            "\(fileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 2 },
                  "end": { "line": 0, "character": 3 }
                },
                "newText": "Z"
              }
            ]
          }
        }
        """

        XCTAssertTrue(ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(secondWorkspaceEdit))
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "aBZ\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "workspace.undo_last_workspace_edit"))
        XCTAssertTrue(delegate.executeCommand(id: "workspace.undo_last_workspace_edit"))

        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")

        XCTAssertTrue(delegate.executeCommand(id: "workspace.undo_last_workspace_edit"))

        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
        XCTAssertFalse(ctx.window.title.contains("●"))

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "workspace.redo_last_workspace_edit"))
        XCTAssertTrue(delegate.executeCommand(id: "workspace.redo_last_workspace_edit"))

        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(ctx.window.title.contains("●"))

        XCTAssertTrue(delegate.executeCommand(id: "workspace.redo_last_workspace_edit"))

        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "aBZ\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
    }

    func testWorkspaceEditRegistersAppKitUndoManagerAction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("undo-manager-main.txt")
        let otherURL = tempDir.appendingPathComponent("undo-manager-other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let undoManager = try XCTUnwrap(window.undoManager)
        XCTAssertFalse(undoManager.canUndo)

        let workspaceEdit = """
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
            ],
            "\(otherURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Workspace Edit")

        undoManager.undo()

        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(undoManager.canRedo)
        XCTAssertEqual(undoManager.redoActionName, "Workspace Edit")

        undoManager.redo()

        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(window.title.contains("●"))
        XCTAssertTrue(undoManager.canUndo)
    }

    func testWorkspaceEditHistoryPanelShowsCoreTransactionEvents() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("history-main.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer {
            ctx.editorAreaController.closeWorkspaceEditHistoryPanel()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(ctx.editorAreaController)

        let workspaceEdit = """
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

        XCTAssertTrue(ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        let secondWorkspaceEdit = """
        {
          "changes": {
            "\(fileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 2 },
                  "end": { "line": 0, "character": 3 }
                },
                "newText": "C"
              }
            ]
          }
        }
        """
        XCTAssertTrue(ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(secondWorkspaceEdit))
        XCTAssertEqual(try ctx.editorAreaController._coreWorkspaceEditTransactionLatestSequenceForTesting(), 2)
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "workspace.show_workspace_edit_history"))
        XCTAssertTrue(delegate.executeCommand(id: "workspace.show_workspace_edit_history"))
        XCTAssertTrue(ctx.editorAreaController._workspaceEditHistoryPanelIsVisibleForTesting())
        XCTAssertEqual(ctx.editorAreaController._workspaceEditHistoryPanelRowCountForTesting(), 2)

        let items = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        let firstItem = try XCTUnwrap(items.first { $0.sequence == 1 })
        let secondItem = try XCTUnwrap(items.first { $0.sequence == 2 })
        XCTAssertEqual(firstItem.operation, "apply")
        XCTAssertEqual(firstItem.status, "Applied")
        XCTAssertEqual(firstItem.workspaceEditJSON, workspaceEdit)
        XCTAssertFalse(firstItem.canUndoLatest)
        XCTAssertTrue(firstItem.detail.contains("1 text edits, 0 resource ops"))
        XCTAssertTrue(firstItem.detail.contains("history-main.txt"))
        XCTAssertEqual(secondItem.workspaceEditJSON, secondWorkspaceEdit)
        XCTAssertTrue(secondItem.canUndoLatest)
        XCTAssertTrue(secondItem.title.contains("Apply WorkspaceEdit"))

        XCTAssertTrue(ctx.editorAreaController._undoLastCoreWorkspaceEditTransactionForTesting())
        let itemsAfterOneUndo = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        XCTAssertFalse(try XCTUnwrap(itemsAfterOneUndo.first { $0.sequence == 2 }).canUndoLatest)
        XCTAssertTrue(try XCTUnwrap(itemsAfterOneUndo.first { $0.sequence == 1 }).canUndoLatest)

        XCTAssertTrue(ctx.editorAreaController._undoLastCoreWorkspaceEditTransactionForTesting())
        let itemsAfterTwoUndos = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        XCTAssertFalse(try XCTUnwrap(itemsAfterTwoUndos.first { $0.sequence == 2 }).canUndoLatest)
        XCTAssertFalse(try XCTUnwrap(itemsAfterTwoUndos.first { $0.sequence == 1 }).canUndoLatest)

        XCTAssertTrue(ctx.editorAreaController._redoLastCoreWorkspaceEditTransactionForTesting())
        let itemsAfterRedo = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        let redoItem = try XCTUnwrap(itemsAfterRedo.first { $0.sequence == 3 })
        XCTAssertEqual(redoItem.operation, "redo")
        XCTAssertTrue(redoItem.canUndoLatest)
        XCTAssertTrue(redoItem.title.contains("Redo WorkspaceEdit"))
    }

    func testWorkspaceEditHistoryPanelRerunsRecordedRequestOwner() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("history-rerun-request.txt")
        try "main\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer {
            ctx.editorAreaController.closeWorkspaceEditHistoryPanel()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(ctx.editorAreaController.activeTab)
        allowWorkspaceEditPreviewConfirmation(ctx.editorAreaController)
        var rerunCount = 0
        let requestRetryOwner = AttoWorkspaceEditRequestRetryOwner(label: "Synthetic Request") {
            rerunCount += 1
            return true
        }

        let workspaceEdit = """
        {
          "changes": {
            "\(fileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "updated "
              }
            ]
          }
        }
        """

        XCTAssertTrue(
            ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(
                workspaceEdit,
                requestRetryOwner: requestRetryOwner
            ).accepted
        )
        XCTAssertEqual(try ctx.editorAreaController._coreWorkspaceEditTransactionLatestSequenceForTesting(), 1)
        XCTAssertEqual(try tab.editCore.editor.text(), "updated main\n")

        XCTAssertTrue(delegate.executeCommand(id: "workspace.show_workspace_edit_history"))
        let items = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.sequence, 1)
        XCTAssertEqual(item.requestRetryLabel, "Synthetic Request")

        let historyPanel = try XCTUnwrap(ctx.window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.workspaceEditHistoryPanel
        })
        let root = try XCTUnwrap(historyPanel.contentView)
        let rerunRequestButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelRerunRequestButton,
                in: root
            ) as? NSButton
        )
        XCTAssertTrue(rerunRequestButton.isEnabled)

        XCTAssertTrue(invokeButtonAction(rerunRequestButton))

        XCTAssertEqual(rerunCount, 1)
        XCTAssertEqual(
            ctx.editorAreaController._transientStatusTextForTesting(),
            "Retrying WorkspaceEdit request: Synthetic Request"
        )
    }

    func testWorkspaceEditHistoryPanelOpensConflictTarget() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("history-conflict-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("history-conflict-main.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer {
            ctx.editorAreaController.closeWorkspaceEditHistoryPanel()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: dirtyURL, mode: .pinned)
        let dirtyTab = try XCTUnwrap(ctx.editorAreaController.activeTab)
        XCTAssertTrue(ctx.editorAreaController.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        ctx.editorAreaController.openFile(url: mainURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(ctx.editorAreaController)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(mainURL.absoluteString)"
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "updated "
                }
              ]
            },
            {
              "kind": "delete",
              "uri": "\(dirtyURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(try XCTUnwrap(ctx.editorAreaController.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)
        XCTAssertEqual(try XCTUnwrap(ctx.editorAreaController.activeTab).editCore.editor.text(), "updated main\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try dirtyTab.editCore.editor.text(), "!dirty\n")

        XCTAssertTrue(delegate.executeCommand(id: "workspace.show_workspace_edit_history"))
        let items = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.status, "Partial")
        XCTAssertEqual(item.conflictCount, 1)
        XCTAssertEqual(item.firstConflictURI, dirtyURL.absoluteString)
        XCTAssertEqual(item.firstSaveableConflictURI, dirtyURL.absoluteString)
        XCTAssertEqual(item.firstDiscardableConflictURI, dirtyURL.absoluteString)
        XCTAssertTrue(item.detail.contains("1 conflict"))
        XCTAssertTrue(item.detail.contains("history-conflict-dirty.txt"))

        let historyPanel = try XCTUnwrap(ctx.window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.workspaceEditHistoryPanel
        })
        let root = try XCTUnwrap(historyPanel.contentView)
        let openConflictButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelOpenConflictButton,
                in: root
            ) as? NSButton
        )
        let saveConflictButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelSaveConflictButton,
                in: root
            ) as? NSButton
        )
        let discardConflictButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelDiscardConflictButton,
                in: root
            ) as? NSButton
        )
        let saveAndReapplyButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelSaveAndReapplyButton,
                in: root
            ) as? NSButton
        )
        let discardAndReapplyButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelDiscardAndReapplyButton,
                in: root
            ) as? NSButton
        )
        let reapplyButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelReapplyButton,
                in: root
            ) as? NSButton
        )
        XCTAssertTrue(openConflictButton.isEnabled)
        XCTAssertTrue(saveConflictButton.isEnabled)
        XCTAssertTrue(discardConflictButton.isEnabled)
        XCTAssertFalse(saveAndReapplyButton.isEnabled)
        XCTAssertFalse(discardAndReapplyButton.isEnabled)
        XCTAssertTrue(reapplyButton.isEnabled)

        XCTAssertTrue(invokeButtonAction(openConflictButton))

        XCTAssertEqual(ctx.editorAreaController.selectedTabID, dirtyTab.id)
        XCTAssertEqual(ctx.editorAreaController.activeTab?.fileURL.standardizedFileURL, dirtyURL.standardizedFileURL)
        XCTAssertEqual(
            ctx.editorAreaController._transientStatusTextForTesting(),
            "Opened WorkspaceEdit conflict: \(dirtyURL.lastPathComponent)"
        )

        XCTAssertTrue(invokeButtonAction(saveConflictButton))

        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        let savedDirtyItem = try XCTUnwrap(
            ctx.editorAreaController.openFileItems().first {
                $0.url.standardizedFileURL == dirtyURL.standardizedFileURL
            }
        )
        XCTAssertFalse(savedDirtyItem.isDirty)
        XCTAssertEqual(
            ctx.editorAreaController._transientStatusTextForTesting(),
            "Saved WorkspaceEdit conflict: \(dirtyURL.lastPathComponent)"
        )

        XCTAssertTrue(ctx.editorAreaController.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"?"}"#))
        XCTAssertEqual(try dirtyTab.editCore.editor.text(), "!?dirty\n")

        XCTAssertTrue(invokeButtonAction(discardConflictButton))

        XCTAssertEqual(try dirtyTab.editCore.editor.text(), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        let discardedDirtyItem = try XCTUnwrap(
            ctx.editorAreaController.openFileItems().first {
                $0.url.standardizedFileURL == dirtyURL.standardizedFileURL
            }
        )
        XCTAssertFalse(discardedDirtyItem.isDirty)
        XCTAssertEqual(
            ctx.editorAreaController._transientStatusTextForTesting(),
            "Discarded WorkspaceEdit conflict changes: \(dirtyURL.lastPathComponent)"
        )
    }

    func testWorkspaceEditHistoryPanelSaveAndReapplyRejectedTransaction() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("history-reapply-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("history-reapply-main.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer {
            ctx.editorAreaController.closeWorkspaceEditHistoryPanel()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(ctx.editorAreaController.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        ctx.editorAreaController.openFile(url: mainURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(ctx.editorAreaController)

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "\(mainURL.absoluteString)"
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "updated "
                  }
                ]
              },
              {
                "kind": "delete",
                "uri": "\(dirtyURL.absoluteString)"
              }
            ]
          }
        }
        """

        let coreDocuments = try XCTUnwrap(ctx.editorAreaController.coreDocuments)
        try ctx.editorAreaController.syncOpenTabsToCoreBeforeWorkspaceEditApply(coreDocuments)
        let rejected = try coreDocuments.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(rejected.applied)
        XCTAssertEqual(rejected.conflicts.first?.uri, dirtyURL.absoluteString)
        XCTAssertEqual(try ctx.editorAreaController._coreWorkspaceEditTransactionLatestSequenceForTesting(), 1)
        XCTAssertEqual(try XCTUnwrap(ctx.editorAreaController.activeTab).editCore.editor.text(), "main\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))

        XCTAssertTrue(delegate.executeCommand(id: "workspace.show_workspace_edit_history"))
        let items = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.status, "Rejected")
        XCTAssertEqual(item.workspaceEditJSON, workspaceEdit)
        XCTAssertEqual(item.firstSaveableConflictURI, dirtyURL.absoluteString)
        XCTAssertEqual(item.firstDiscardableConflictURI, dirtyURL.absoluteString)

        let historyPanel = try XCTUnwrap(ctx.window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.workspaceEditHistoryPanel
        })
        let root = try XCTUnwrap(historyPanel.contentView)
        let saveAndReapplyButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelSaveAndReapplyButton,
                in: root
            ) as? NSButton
        )
        let discardAndReapplyButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelDiscardAndReapplyButton,
                in: root
            ) as? NSButton
        )
        let reapplyButton = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.workspaceEditHistoryPanelReapplyButton,
                in: root
            ) as? NSButton
        )
        XCTAssertTrue(saveAndReapplyButton.isEnabled)
        XCTAssertTrue(discardAndReapplyButton.isEnabled)
        XCTAssertTrue(reapplyButton.isEnabled)

        XCTAssertTrue(invokeButtonAction(saveAndReapplyButton))

        XCTAssertFalse(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try XCTUnwrap(ctx.editorAreaController.activeTab).editCore.editor.text(), "updated main\n")
        XCTAssertEqual(try ctx.editorAreaController._coreWorkspaceEditTransactionLatestSequenceForTesting(), 2)
        let refreshedItems = ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting()
        let reappliedItem = try XCTUnwrap(refreshedItems.first { $0.sequence == 2 })
        XCTAssertEqual(reappliedItem.status, "Applied")
        XCTAssertEqual(reappliedItem.workspaceEditJSON, workspaceEdit)
        XCTAssertEqual(
            ctx.editorAreaController._transientStatusTextForTesting(),
            "Saved conflict and reapplied WorkspaceEdit"
        )
    }
}
