import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testMultiDocumentEditorUIAtomicWorkspaceEditRollsBackRuntimeTextFailure() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorCoreUIFFITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("First.swift")
        let badURL = tempDir.appendingPathComponent("Bad.swift")
        try Data([0xff]).write(to: badURL)

        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let first = try multi.openTab(text: "alpha\n", viewportWidthCells: 80)
        try multi.setWorkspaceRoots([tempDir.absoluteString])
        try multi.setTabDocumentURI(firstURL.absoluteString, tabId: first)

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "\(firstURL.absoluteString)",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 5 }
                    },
                    "newText": "ALPHA"
                  }
                ]
              },
              {
                "textDocument": {
                  "uri": "\(badURL.absoluteString)",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "invalid"
                  }
                ]
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(preview.applyMode, "atomic")
        XCTAssertTrue(preview.skippedDetails.isEmpty)

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(applied.mode, "apply")
        XCTAssertEqual(applied.applyMode, "atomic")
        XCTAssertFalse(applied.applied)
        XCTAssertTrue(applied.appliedURIs.isEmpty)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == badURL.absoluteString
                && $0.operation == "text_edit"
                && $0.reason == "file_text_edit_read_failed"
        })
        XCTAssertEqual(try multi.tabText(tabId: first), "alpha\n")
        XCTAssertEqual(try Data(contentsOf: badURL), Data([0xff]))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
        let events = try multi.workspaceEditTransactionEvents()
        XCTAssertEqual(events.events.first?.result.applyMode, "atomic")
        XCTAssertEqual(events.events.first?.result.applied, false)
        XCTAssertEqual(events.events.first?.result.appliedURIs, [])
    }

    func testMultiDocumentEditorUIUndoesLastWorkspaceEditTransaction() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-edit-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let openURL = root.appendingPathComponent("src/Open.swift")
        let unopenedURL = root.appendingPathComponent("src/Unopened.swift")
        try "unopened\n".write(to: unopenedURL, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let tab = try multi.openTab(text: "open\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI(openURL.absoluteString, tabId: tab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(openURL.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 4 }
                  },
                  "newText": "OPEN"
                }
              ]
            },
            {
              "textDocument": {
                "uri": "\(unopenedURL.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 8 }
                  },
                  "newText": "UNOPENED"
                }
              ]
            }
          ]
        }
        """

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 2)
        XCTAssertEqual(try multi.tabText(tabId: tab), "OPEN\n")
        XCTAssertEqual(try String(contentsOf: unopenedURL, encoding: .utf8), "UNOPENED\n")

        let undone = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertTrue(undone.undone)
        XCTAssertEqual(undone.restoredOpenTabCount, 1)
        XCTAssertGreaterThanOrEqual(undone.restoredFilesystemEntryCount, 1)
        XCTAssertEqual(undone.restoredURIs, [openURL.absoluteString, unopenedURL.absoluteString])
        XCTAssertEqual(try multi.tabText(tabId: tab), "open\n")
        XCTAssertFalse(try multi.isTabModified(tab))
        XCTAssertEqual(try String(contentsOf: unopenedURL, encoding: .utf8), "unopened\n")

        let redone = try multi.redoLastWorkspaceEditTransaction()
        XCTAssertTrue(redone.applied)
        XCTAssertEqual(redone.mode, "redo")
        XCTAssertEqual(redone.appliedEditCount, 2)
        XCTAssertEqual(redone.appliedURIs, [openURL.absoluteString, unopenedURL.absoluteString])
        XCTAssertEqual(try multi.tabText(tabId: tab), "OPEN\n")
        XCTAssertEqual(try String(contentsOf: unopenedURL, encoding: .utf8), "UNOPENED\n")

        let undoAfterRedo = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertTrue(undoAfterRedo.undone)
        XCTAssertEqual(try multi.tabText(tabId: tab), "open\n")
        XCTAssertEqual(try String(contentsOf: unopenedURL, encoding: .utf8), "unopened\n")

        let unavailable = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertFalse(unavailable.undone)
        XCTAssertTrue(unavailable.restoredURIs.isEmpty)
    }

    func testMultiDocumentEditorUIUndoesMultipleWorkspaceEditTransactions() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let uri = "file:///project/MultiLevel.swift"
        let tab = try multi.openTab(text: "abc\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI(uri, tabId: tab)

        let firstEdit = """
        {
          "changes": {
            "\(uri)": [
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
        let firstApply = try multi.applyWorkspaceEditTransaction(firstEdit)
        XCTAssertTrue(firstApply.applied)
        XCTAssertEqual(try multi.tabText(tabId: tab), "aBc\n")

        let secondEdit = """
        {
          "changes": {
            "\(uri)": [
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
        let secondApply = try multi.applyWorkspaceEditTransaction(secondEdit)
        XCTAssertTrue(secondApply.applied)
        XCTAssertEqual(try multi.tabText(tabId: tab), "aBC\n")
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 2)

        let secondUndo = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertTrue(secondUndo.undone)
        XCTAssertEqual(try multi.tabText(tabId: tab), "aBc\n")

        let firstUndo = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertTrue(firstUndo.undone)
        XCTAssertEqual(try multi.tabText(tabId: tab), "abc\n")

        let unavailable = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertFalse(unavailable.undone)
    }

    func testMultiDocumentEditorUIRollsBackUnopenedResourceOperationsAfterRuntimeFailure() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let target = root.appendingPathComponent("src/Target.swift")
        let created = root.appendingPathComponent("generated/Created.swift")
        let blocker = root.appendingPathComponent("blocker")
        let blockedChild = root.appendingPathComponent("blocker/Child.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "target\n".write(to: target, atomically: true, encoding: .utf8)
        try "blocker\n".write(to: blocker, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(created.absoluteString)"
            },
            {
              "kind": "rename",
              "oldUri": "\(old.absoluteString)",
              "newUri": "\(target.absoluteString)",
              "options": { "overwrite": true }
            },
            {
              "kind": "create",
              "uri": "\(blockedChild.absoluteString)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target\n")

        XCTAssertThrowsError(try multi.applyWorkspaceEditTransaction(workspaceEdit))
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("generated").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "old\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target\n")
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "blocker\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedChild.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 0)
    }

    func testMultiDocumentEditorUIRollsBackUnopenedTextEditsAfterRuntimeFailure() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-text-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let target = root.appendingPathComponent("src/Target.swift")
        let blocker = root.appendingPathComponent("blocker")
        let blockedChild = root.appendingPathComponent("blocker/Child.swift")
        try "alpha\nbeta\n".write(to: target, atomically: true, encoding: .utf8)
        try "blocker\n".write(to: blocker, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(target.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 4 }
                  },
                  "newText": "BETA"
                }
              ]
            },
            {
              "kind": "create",
              "uri": "\(blockedChild.absoluteString)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nbeta\n")

        XCTAssertThrowsError(try multi.applyWorkspaceEditTransaction(workspaceEdit))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nbeta\n")
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "blocker\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedChild.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 0)
    }

    func testMultiDocumentEditorUIRollsBackOpenTabsAfterRuntimeFailure() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-open-tab-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let renamed = root.appendingPathComponent("src/Renamed.swift")
        let deleted = root.appendingPathComponent("src/Delete.swift")
        let overwritten = root.appendingPathComponent("src/Overwrite.swift")
        let blocker = root.appendingPathComponent("blocker")
        let blockedChild = root.appendingPathComponent("blocker/Child.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "delete\n".write(to: deleted, atomically: true, encoding: .utf8)
        try "existing\n".write(to: overwritten, atomically: true, encoding: .utf8)
        try "blocker\n".write(to: blocker, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let oldTab = try multi.openTab(text: "old\n", viewportWidthCells: 80)
        let deleteTab = try multi.openTab(text: "delete\n", viewportWidthCells: 80)
        let overwriteTab = try multi.openTab(text: "existing\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI(old.absoluteString, tabId: oldTab)
        try multi.setTabDocumentURI(deleted.absoluteString, tabId: deleteTab)
        try multi.setTabDocumentURI(overwritten.absoluteString, tabId: overwriteTab)
        try multi.setActiveTab(deleteTab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(old.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "edited "
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(old.absoluteString)",
              "newUri": "\(renamed.absoluteString)"
            },
            {
              "kind": "delete",
              "uri": "\(deleted.absoluteString)"
            },
            {
              "kind": "create",
              "uri": "\(overwritten.absoluteString)",
              "options": { "overwrite": true }
            },
            {
              "kind": "create",
              "uri": "\(blockedChild.absoluteString)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertEqual(try multi.tabText(tabId: oldTab), "old\n")
        XCTAssertEqual(try multi.tabDocumentURI(tabId: oldTab), old.absoluteString)
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == deleteTab })

        XCTAssertThrowsError(try multi.applyWorkspaceEditTransaction(workspaceEdit)) { error in
            XCTAssertTrue(String(describing: error).contains("open tab state was rolled back"))
        }
        XCTAssertEqual(try multi.tabText(tabId: oldTab), "old\n")
        XCTAssertFalse(try multi.isTabModified(oldTab))
        XCTAssertEqual(try multi.tabDocumentURI(tabId: oldTab), old.absoluteString)
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == deleteTab })
        XCTAssertEqual(try multi.tabText(tabId: deleteTab), "delete\n")
        XCTAssertEqual(try multi.tabDocumentURI(tabId: deleteTab), deleted.absoluteString)
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == overwriteTab })
        XCTAssertEqual(try multi.tabText(tabId: overwriteTab), "existing\n")
        XCTAssertFalse(try multi.isTabModified(overwriteTab))
        XCTAssertEqual(try multi.tabDocumentURI(tabId: overwriteTab), overwritten.absoluteString)
        XCTAssertEqual(try multi.activeTabId(), deleteTab)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertEqual(try String(contentsOf: overwritten, encoding: .utf8), "existing\n")
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "blocker\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedChild.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 0)
    }
}
