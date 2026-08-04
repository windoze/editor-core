import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testMultiDocumentEditorUIAtomicWorkspaceEditPreflightSkipsWithoutMutating() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let app = try multi.openTab(text: "alpha\n", viewportWidthCells: 80)
        let dirty = try multi.openTab(text: "dirty\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/App.swift", tabId: app)
        try multi.setTabDocumentURI("file:///project/Dirty.swift", tabId: dirty)
        try multi.replaceTabText(tabId: dirty, text: "dirty changed\n", markSaved: false)

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "file:///project/App.swift",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 5 }
                    },
                    "newText": "App"
                  }
                ]
              },
              {
                "kind": "delete",
                "uri": "file:///project/Dirty.swift"
              }
            ]
          }
        }
        """

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(applied.mode, "apply")
        XCTAssertEqual(applied.applyMode, "atomic")
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.appliedURIs.isEmpty)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == "file:///project/Dirty.swift"
                && $0.operation == "delete"
                && $0.reason == "resource_operation_dirty_target"
        })
        XCTAssertEqual(applied.dirtyDocumentURIs, ["file:///project/Dirty.swift"])
        let dirtyDocument = try XCTUnwrap(applied.documents.first {
            $0.uri == "file:///project/Dirty.swift"
        })
        XCTAssertTrue(dirtyDocument.isDirty)
        let dirtyConflict = try XCTUnwrap(applied.conflicts.first {
            $0.uri == "file:///project/Dirty.swift"
                && $0.operation == "delete"
                && $0.reason == "resource_operation_dirty_target"
        })
        XCTAssertEqual(dirtyConflict.kind, "dirty_document")
        XCTAssertEqual(dirtyConflict.severity, "error")
        XCTAssertEqual(dirtyConflict.applyImpact, "blocks_atomic_apply")
        XCTAssertEqual(dirtyConflict.resolution, "save_or_discard")
        XCTAssertEqual(dirtyConflict.message, "delete targets a modified open tab")
        XCTAssertEqual(try multi.tabText(tabId: app), "alpha\n")
        XCTAssertEqual(try multi.tabText(tabId: dirty), "dirty changed\n")
        XCTAssertTrue(try multi.isTabModified(dirty))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
        let events = try multi.workspaceEditTransactionEvents()
        XCTAssertEqual(events.events.first?.result.applyMode, "atomic")
        XCTAssertEqual(events.events.first?.result.applied, false)
        XCTAssertEqual(events.events.first?.result.dirtyDocumentURIs, ["file:///project/Dirty.swift"])
    }

    func testMultiDocumentEditorUIAtomicWorkspaceEditPreflightsRemovedTextEditDependency() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "delete me\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Delete.swift", tabId: tab)

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "kind": "delete",
                "uri": "file:///project/Delete.swift"
              },
              {
                "textDocument": {
                  "uri": "file:///project/Delete.swift",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "late "
                  }
                ]
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(preview.applyMode, "atomic")
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Delete.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_removed"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(applied.mode, "apply")
        XCTAssertEqual(applied.applyMode, "atomic")
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == "file:///project/Delete.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_removed"
        })
        XCTAssertEqual(try multi.tabDocumentURI(tabId: tab), "file:///project/Delete.swift")
        XCTAssertEqual(try multi.tabText(tabId: tab), "delete me\n")
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == tab })
    }

    func testMultiDocumentEditorUIPreviewsOrderedUnsupportedWorkspaceEditDependency() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "old\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Old.swift", tabId: tab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "file:///project/Old.swift"
            },
            {
              "textDocument": {
                "uri": "file:///project/Old.swift",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "later "
                }
              ]
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Old.swift"
                && $0.operation == "create"
                && $0.reason == "resource_operation_create_exists"
        })
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Old.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_unsupported"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == "file:///project/Old.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_skipped"
        })
        XCTAssertEqual(try multi.tabText(tabId: tab), "old\n")
    }

    func testMultiDocumentEditorUIReportsWorkspaceEditVersionMismatch() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "versioned", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Versioned.swift", tabId: tab)

        let edit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "file:///project/Versioned.swift",
                "version": 1
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "stale "
                }
              ]
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(edit)
        XCTAssertEqual(preview.skippedURIs, ["file:///project/Versioned.swift"])
        let document = try XCTUnwrap(preview.documents.first {
            $0.uri == "file:///project/Versioned.swift"
        })
        XCTAssertEqual(document.expectedVersion, 1)
        XCTAssertEqual(document.actualVersion, 0)
        XCTAssertTrue(document.versionMismatch)
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Versioned.swift"
                && $0.operation == "text_edit"
                && $0.reason == "version_mismatch"
        })

        let applied = try multi.applyWorkspaceEditTransaction(edit)
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(try multi.tabText(tabId: tab), "versioned")
    }
}
