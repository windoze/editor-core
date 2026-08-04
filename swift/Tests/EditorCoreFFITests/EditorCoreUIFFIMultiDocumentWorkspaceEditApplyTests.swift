import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testMultiDocumentEditorUIAppliesOpenTabResourceOperations() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "beta saved mirror", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Beta.swift", tabId: tab)

        let resourceEdit = """
        {
          "documentChanges": [
            {
              "kind": "rename",
              "oldUri": "file:///project/Beta.swift",
              "newUri": "file:///project/Renamed.swift"
            },
            {
              "textDocument": {
                "uri": "file:///project/Renamed.swift",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 4 }
                  },
                  "newText": "RENAMED"
                }
              ]
            }
          ]
        }
        """

        let resourceApply = try multi.applyWorkspaceEditTransaction(resourceEdit)
        XCTAssertTrue(resourceApply.applied)
        XCTAssertEqual(resourceApply.appliedEditCount, 1)
        XCTAssertEqual(resourceApply.appliedResourceOperationCount, 1)
        XCTAssertEqual(resourceApply.resourceOperations.count, 1)
        let operation = try XCTUnwrap(resourceApply.resourceOperations.first)
        XCTAssertEqual(operation.kind, "rename")
        XCTAssertNil(operation.uri)
        XCTAssertEqual(operation.oldURI, "file:///project/Beta.swift")
        XCTAssertEqual(operation.newURI, "file:///project/Renamed.swift")
        XCTAssertEqual(operation.affectedURIs, [
            "file:///project/Beta.swift",
            "file:///project/Renamed.swift",
        ])
        XCTAssertTrue(operation.supported)
        XCTAssertTrue(operation.applied)
        XCTAssertEqual(try multi.tabDocumentURI(tabId: tab), "file:///project/Renamed.swift")
        XCTAssertEqual(try multi.tabText(tabId: tab), "RENAMED saved mirror")
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }

    func testMultiDocumentEditorUIAppliesOpenTabResourceOperationFilesystemSideEffects() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-open-tab-resource-fs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let renamed = root.appendingPathComponent("src/Renamed.swift")
        let deleted = root.appendingPathComponent("src/Deleted.swift")
        let overwritten = root.appendingPathComponent("src/Overwrite.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "delete\n".write(to: deleted, atomically: true, encoding: .utf8)
        try "existing\n".write(to: overwritten, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let oldTab = try multi.openTab(text: "old\n", viewportWidthCells: 80)
        let deleteTab = try multi.openTab(text: "delete\n", viewportWidthCells: 80)
        let overwriteTab = try multi.openTab(text: "existing\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI(old.absoluteString, tabId: oldTab)
        try multi.setTabDocumentURI(deleted.absoluteString, tabId: deleteTab)
        try multi.setTabDocumentURI(overwritten.absoluteString, tabId: overwriteTab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "rename",
              "oldUri": "\(old.absoluteString)",
              "newUri": "\(renamed.absoluteString)"
            },
            {
              "textDocument": {
                "uri": "\(renamed.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "renamed "
                }
              ]
            },
            {
              "kind": "delete",
              "uri": "\(deleted.absoluteString)"
            },
            {
              "kind": "create",
              "uri": "\(overwritten.absoluteString)",
              "options": { "overwrite": true }
            }
          ]
        }
        """

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 1)
        XCTAssertEqual(applied.appliedResourceOperationCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "old\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertEqual(try String(contentsOf: overwritten, encoding: .utf8), "")
        XCTAssertEqual(try multi.tabDocumentURI(tabId: oldTab), renamed.absoluteString)
        XCTAssertEqual(try multi.tabText(tabId: oldTab), "renamed old\n")
        XCTAssertFalse(try multi.snapshot().tabs.contains { $0.id == deleteTab })
        XCTAssertEqual(try multi.tabText(tabId: overwriteTab), "")
        XCTAssertFalse(try multi.isTabModified(overwriteTab))
    }

    func testMultiDocumentEditorUIAppliesUnopenedWorkspaceFileTextEdits() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-edit-\(UUID().uuidString)", isDirectory: true)
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-edit-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let target = root.appendingPathComponent("Unopened.swift")
        let outside = outsideRoot.appendingPathComponent("Outside.swift")
        try "alpha\nbeta\n".write(to: target, atomically: true, encoding: .utf8)
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)

        let targetURI = target.absoluteString
        let outsideURI = outside.absoluteString
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "changes": {
            "\(targetURI)": [
              {
                "range": {
                  "start": { "line": 1, "character": 0 },
                  "end": { "line": 1, "character": 4 }
                },
                "newText": "BETA"
              }
            ],
            "\(outsideURI)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "changed "
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(preview.applied)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nbeta\n")
        let targetDocument = try XCTUnwrap(preview.documents.first { $0.uri == targetURI })
        XCTAssertFalse(targetDocument.isOpen)
        XCTAssertNil(targetDocument.tabId)
        XCTAssertEqual(targetDocument.editCount, 1)
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == outsideURI
                && $0.operation == "text_edit"
                && $0.reason == "document_outside_workspace"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedURIs, [targetURI])
        XCTAssertEqual(applied.appliedEditCount, 1)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nBETA\n")
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "outside\n")
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }

    func testMultiDocumentEditorUIAppliesUnopenedWorkspaceFileResourceOperations() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-resource-\(UUID().uuidString)", isDirectory: true)
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-resource-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let renamed = root.appendingPathComponent("src/Renamed.swift")
        let created = root.appendingPathComponent("generated/Created.swift")
        let deleted = root.appendingPathComponent("src/Deleted.swift")
        let outside = outsideRoot.appendingPathComponent("Outside.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "delete me\n".write(to: deleted, atomically: true, encoding: .utf8)

        let oldURI = old.absoluteString
        let renamedURI = renamed.absoluteString
        let createdURI = created.absoluteString
        let deletedURI = deleted.absoluteString
        let outsideURI = outside.absoluteString
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(createdURI)"
            },
            {
              "textDocument": {
                "uri": "\(createdURI)",
                "version": null
              },
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
              "oldUri": "\(oldURI)",
              "newUri": "\(renamedURI)"
            },
            {
              "kind": "delete",
              "uri": "\(deletedURI)"
            },
            {
              "kind": "create",
              "uri": "\(outsideURI)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(preview.applied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == outsideURI
                && $0.operation == "create"
                && $0.reason == "document_outside_workspace"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 1)
        XCTAssertEqual(applied.appliedResourceOperationCount, 3)
        XCTAssertTrue(applied.appliedURIs.contains(createdURI))
        XCTAssertTrue(applied.appliedURIs.contains(oldURI))
        XCTAssertTrue(applied.appliedURIs.contains(renamedURI))
        XCTAssertTrue(applied.appliedURIs.contains(deletedURI))
        XCTAssertTrue(applied.skippedURIs.contains(outsideURI))
        XCTAssertEqual(try String(contentsOf: created, encoding: .utf8), "created\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "old\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }

    func testMultiDocumentEditorUIAppliesWorkspaceEditDocumentChangesInOrder() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-order-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let draft = root.appendingPathComponent("src/Draft.swift")
        let finalFile = root.appendingPathComponent("src/Final.swift")
        let draftURI = draft.absoluteString
        let finalURI = finalFile.absoluteString
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(draftURI)"
            },
            {
              "textDocument": {
                "uri": "\(draftURI)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "draft\\n"
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(draftURI)",
              "newUri": "\(finalURI)"
            },
            {
              "textDocument": {
                "uri": "\(finalURI)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "final "
                }
              ]
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(preview.applied)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalFile.path))

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 2)
        XCTAssertEqual(applied.appliedResourceOperationCount, 2)
        XCTAssertTrue(applied.skippedURIs.isEmpty)
        XCTAssertTrue(applied.appliedURIs.contains(draftURI))
        XCTAssertTrue(applied.appliedURIs.contains(finalURI))
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertEqual(try String(contentsOf: finalFile, encoding: .utf8), "final draft\n")
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }
}
