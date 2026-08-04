import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testWorkspaceEditPreviewTextUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("preview-source-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("preview-projected-uri.txt")
        try "alpha\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected\n".write(to: projectedURL, atomically: true, encoding: .utf8)

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

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"unsaved "}"#))

        XCTAssertEqual(
            vc.workspaceEditPreviewText(for: projectedURL.standardizedFileURL.absoluteString),
            "unsaved alpha\n"
        )
    }

    func testWorkspaceEditApplyPreservesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("apply-source-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("apply-projected-uri.txt")
        try "alpha\n".write(to: fileURL, atomically: true, encoding: .utf8)
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

        let workspaceEdit = """
        {
          "changes": {
            "\(projectedURL.standardizedFileURL.absoluteString)": [
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

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "updated alpha\n")
        XCTAssertEqual(vc.tabs.count, 1)
        XCTAssertEqual(tab.fileURL.standardizedFileURL, projectedURL.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: projectedURL, encoding: .utf8), "projected\n")
    }

    func testWorkspaceEditApplicationUsesCoreVersionPreflight() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("versioned.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(fileURL.absoluteString)",
                "version": 1
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 2 }
                  },
                  "newText": "B"
                }
              ]
            }
          ]
        }
        """

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "abc\n")
        XCTAssertFalse(window.title.contains("●"))

        let popoverText = try XCTUnwrap(vc.workspaceEditPopoverLabel?.stringValue)
        XCTAssertTrue(popoverText.contains("Workspace edit was not applied."), popoverText)
        XCTAssertTrue(
            popoverText.contains("versioned.txt (1 edit) [text_edit: version_mismatch]"),
            popoverText
        )
    }

    func testWorkspaceEditApplicationMutatesAlreadyOpenCrossFileTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "abc\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "def\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.selectFile(url: firstURL)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "changes": {
            "\(firstURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "\(secondURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "E"
              }
            ]
          }
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )

        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")

        vc.selectFile(url: secondURL)
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "dEf\n")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "def\n")

        let secondItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == secondURL.standardizedFileURL })
        XCTAssertTrue(secondItem.isDirty)
    }

    func testWorkspaceEditOpenTabProjectionCreatesUndoGroups() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("undo-first.txt")
        let secondURL = tempDir.appendingPathComponent("undo-second.txt")
        try "abc\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "def\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.selectFile(url: firstURL)
        allowWorkspaceEditPreviewConfirmation(vc)

        let workspaceEdit = """
        {
          "changes": {
            "\(firstURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "\(secondURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "E"
              }
            ]
          }
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))

        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        editorView.undo(nil)
        XCTAssertEqual(try editorView.editor.text(), "abc\n")

        vc.selectFile(url: secondURL)
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "dEf\n")
        editorView.undo(nil)
        XCTAssertEqual(try editorView.editor.text(), "def\n")
    }

    func testWorkspaceEditResourceOperationsApplyToUnopenedLocalFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let activeURL = tempDir.appendingPathComponent("active.txt")
        let createdURL = tempDir.appendingPathComponent("created.txt")
        let oldURL = tempDir.appendingPathComponent("old.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed.txt")
        let removedURL = tempDir.appendingPathComponent("removed.txt")
        try "active\n".write(to: activeURL, atomically: true, encoding: .utf8)
        try "old\n".write(to: oldURL, atomically: true, encoding: .utf8)
        try "remove\n".write(to: removedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: activeURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(createdURL.absoluteString)",
              "options": { "overwrite": true }
            },
            {
              "textDocument": { "uri": "\(createdURL.absoluteString)", "version": null },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "created\\n"
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(oldURL.absoluteString)",
              "newUri": "\(renamedURL.absoluteString)"
            },
            {
              "kind": "delete",
              "uri": "\(removedURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertEqual(try String(contentsOf: createdURL, encoding: .utf8), "created\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "old\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "active\n")
    }

    func testWorkspaceEditResourceOperationRenamesOpenTabAndAppliesFollowingEdits() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldURL = tempDir.appendingPathComponent("old-open.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed-open.txt")
        try "old\n".write(to: oldURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: oldURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "rename",
              "oldUri": "\(oldURL.absoluteString)",
              "newUri": "\(renamedURL.absoluteString)"
            },
            {
              "textDocument": { "uri": "\(renamedURL.absoluteString)", "version": null },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "renamed "
                }
              ]
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "old\n")

        let items = vc.openFileItems()
        XCTAssertFalse(items.contains { $0.url.standardizedFileURL == oldURL.standardizedFileURL })
        let renamedItem = try XCTUnwrap(items.first { $0.url.standardizedFileURL == renamedURL.standardizedFileURL })
        XCTAssertTrue(renamedItem.isDirty)
        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.contains { tab in
            tab.documentURI == renamedURL.standardizedFileURL.absoluteString
        })

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "renamed old\n")
    }

    func testWorkspaceEditResourceOperationDeletesOpenCleanTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keepURL = tempDir.appendingPathComponent("keep.txt")
        let deleteURL = tempDir.appendingPathComponent("delete-open.txt")
        try "keep\n".write(to: keepURL, atomically: true, encoding: .utf8)
        try "delete\n".write(to: deleteURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: keepURL, mode: .pinned)
        vc.openFile(url: deleteURL, mode: .pinned)
        vc.selectFile(url: keepURL)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(deleteURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleteURL.path))
        XCTAssertFalse(vc.openFileItems().contains { $0.url.standardizedFileURL == deleteURL.standardizedFileURL })
        XCTAssertTrue(vc.openFileItems().contains { $0.url.standardizedFileURL == keepURL.standardizedFileURL })
    }

    func testWorkspaceEditRemovedTabCallbackUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keepURL = tempDir.appendingPathComponent("keep-projected-delete.txt")
        let localURL = tempDir.appendingPathComponent("delete-local-open.txt")
        let projectedURL = tempDir.appendingPathComponent("delete-projected-open.txt")
        try "keep\n".write(to: keepURL, atomically: true, encoding: .utf8)
        try "delete\n".write(to: localURL, atomically: true, encoding: .utf8)
        try "projected delete\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: keepURL, mode: .pinned)
        vc.openFile(url: localURL, mode: .pinned)
        vc.selectFile(url: keepURL)
        allowWorkspaceEditPreviewConfirmation(vc)

        let tab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == localURL.standardizedFileURL })
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, localURL.standardizedFileURL)

        var closedURLs: [URL] = []
        vc.onDidCloseFile = { closedURLs.append($0.standardizedFileURL) }

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(projectedURL.standardizedFileURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertFalse(vc.tabs.contains { $0.id == tab.id })
        XCTAssertEqual(closedURLs, [projectedURL.standardizedFileURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))
    }

    func testWorkspaceEditResourceOperationOverwritesOpenCleanTabCreate() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("overwrite-open.txt")
        try "existing\n".write(to: url, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: url, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(url.absoluteString)",
              "options": { "overwrite": true }
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "")
        let item = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == url.standardizedFileURL })
        XCTAssertFalse(item.isDirty)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "")
    }

    func testWorkspaceEditResourceOperationSkipsDirtyOpenTabDelete() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("dirty-delete.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(dirtyURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        let dirtyItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == dirtyURL.standardizedFileURL })
        XCTAssertTrue(dirtyItem.isDirty)
    }

    func testWorkspaceEditResourceOperationUsesCoreDirtyWhenSwiftCacheIsStale() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("core-dirty-delete.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))

        vc._setActiveTabDirtyCacheForTesting(false)
        XCTAssertTrue(vc._activeTabDirtyForDataLossDecisionForTesting())

        vc._setActiveTabDirtyCacheForTesting(false)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(dirtyURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        let dirtyItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == dirtyURL.standardizedFileURL })
        XCTAssertTrue(dirtyItem.isDirty)
    }

    func testFindInFilesWorkspaceReplaceUsesCoreWorkspaceEditTransaction() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("src/main.rs")
        let readmeURL = tempDir.appendingPathComponent("README.md")
        try "alpha1 in source\nalphaX in source\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "alpha2 in docs\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: sourceURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(ctx.editorAreaController)
        ctx.findInFilesController.setWorkspaceSearchGlobs(include: ["*.rs"], exclude: [])
        ctx.findInFilesController._setSearchOptionsForTesting(
            AttoFindInFilesViewController.SearchOptions(
                caseSensitive: true,
                wholeWord: false,
                regex: true
            )
        )
        ctx.findInFilesController.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(ctx.findInFilesController._replaceAllButtonIsEnabledForTesting(query: #"alpha(\d)"#))
        XCTAssertFalse(ctx.findInFilesController._replaceAllButtonIsEnabledForTesting(
            query: #"alpha(\d)"#,
            scope: .openedFiles
        ))

        let coreTransactionCursor = try XCTUnwrap(
            ctx.editorAreaController._coreWorkspaceEditTransactionLatestSequenceForTesting()
        )
        XCTAssertTrue(ctx.findInFilesController._replaceWorkspaceMatchesForTesting(
            query: #"alpha(\d)"#,
            replacement: "beta$1",
            scope: .workspace
        ))

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "alpha1 in source\nalphaX in source\n")
        XCTAssertEqual(try String(contentsOf: readmeURL, encoding: .utf8), "alpha2 in docs\n")
        XCTAssertEqual(try ctx.editorAreaController.activeTab?.editCore.editor.text(), "beta1 in source\nalphaX in source\n")
        XCTAssertEqual(
            try XCTUnwrap(ctx.editorAreaController._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
    }
}
