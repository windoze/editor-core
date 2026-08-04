import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testWorkspaceEditPreviewConfirmationCanCancelCoreTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("preview-cancel.txt")
        let otherURL = tempDir.appendingPathComponent("preview-other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        var capturedPreview: AttoWorkspaceEditPreview?
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            capturedPreview = preview
            return .cancel
        }
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

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )

        let preview = try XCTUnwrap(capturedPreview)
        XCTAssertTrue(preview.requiresConfirmation)
        XCTAssertTrue(preview.displayText.contains("Workspace edit preview."))
        XCTAssertTrue(preview.displayText.contains("preview-cancel.txt"))
        XCTAssertTrue(preview.displayText.contains("preview-other.txt"))
        XCTAssertEqual(preview.sections.count, 2)
        XCTAssertTrue(preview.sections.contains { section in
            section.title == "preview-cancel.txt"
                && section.detailText.contains("-abc")
                && section.detailText.contains("+aBc")
        })
        XCTAssertTrue(preview.sections.contains { section in
            section.title == "preview-other.txt"
                && section.detailText.contains("-other")
                && section.detailText.contains("+Xother")
        })
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Workspace edit cancelled")

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
    }

    func testWorkspaceEditPreviewBlocksAtomicConflictEvenWhenDecisionProviderApplies() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("atomic-dirty-delete.txt")
        let otherURL = tempDir.appendingPathComponent("atomic-other.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))

        var capturedPreview: AttoWorkspaceEditPreview?
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            capturedPreview = preview
            return .apply
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "\(otherURL.absoluteString)"
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "X"
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

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )

        let preview = try XCTUnwrap(capturedPreview)
        XCTAssertEqual(preview.applyMode, "atomic")
        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.applyButtonTitle, "Resolve Conflicts First")
        XCTAssertTrue(preview.displayText.contains("will block atomic apply"))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Resolve WorkspaceEdit conflicts before applying")

        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        let dirtyItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == dirtyURL.standardizedFileURL })
        XCTAssertTrue(dirtyItem.isDirty)
    }

    func testWorkspaceEditRuntimeResourceFailureShowsRollbackPopover() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let activeURL = tempDir.appendingPathComponent("active.txt")
        let oldURL = tempDir.appendingPathComponent("src/Old.swift")
        let targetURL = tempDir.appendingPathComponent("src/Target.swift")
        let createdURL = tempDir.appendingPathComponent("generated/Created.swift")
        let blockerURL = tempDir.appendingPathComponent("blocker")
        let blockedChildURL = tempDir.appendingPathComponent("blocker/Child.swift")
        try "active\n".write(to: activeURL, atomically: true, encoding: .utf8)
        try "old\n".write(to: oldURL, atomically: true, encoding: .utf8)
        try "target\n".write(to: targetURL, atomically: true, encoding: .utf8)
        try "blocker\n".write(to: blockerURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: activeURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "kind": "create",
                "uri": "\(createdURL.absoluteString)"
              },
              {
                "kind": "rename",
                "oldUri": "\(oldURL.absoluteString)",
                "newUri": "\(targetURL.absoluteString)",
                "options": { "overwrite": true }
              },
              {
                "kind": "create",
                "uri": "\(blockedChildURL.absoluteString)"
              }
            ]
          }
        }
        """

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertEqual(try String(contentsOf: oldURL, encoding: .utf8), "old\n")
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "target\n")
        XCTAssertEqual(try String(contentsOf: blockerURL, encoding: .utf8), "blocker\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("generated").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedChildURL.path))

        let popoverText = try XCTUnwrap(vc.workspaceEditPopoverLabel?.stringValue)
        XCTAssertTrue(popoverText.contains("Workspace edit failed."))
        XCTAssertTrue(popoverText.contains("Filesystem side effects were rolled back."))
        XCTAssertTrue(popoverText.contains("No WorkspaceEdit transaction was recorded."))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Workspace edit failed")
    }

    func testWorkspaceEditUnsupportedResourceOperationShowsPartialSummary() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let activeURL = tempDir.appendingPathComponent("unsupported-main.txt")
        try "main\n".write(to: activeURL, atomically: true, encoding: .utf8)

        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorOutside-\(UUID().uuidString)", isDirectory: true)
        let outsideOldURL = outsideRoot.appendingPathComponent("UnsupportedOld.swift")
        let outsideNewURL = outsideRoot.appendingPathComponent("UnsupportedNew.swift")

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: activeURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(activeURL.absoluteString)"
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 4 }
                  },
                  "newText": "MAIN"
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(outsideOldURL.absoluteString)",
              "newUri": "\(outsideNewURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).editCore.editor.text(), "MAIN\n")

        let popoverText = try XCTUnwrap(vc.workspaceEditPopoverLabel?.stringValue)
        XCTAssertTrue(popoverText.contains("Workspace edit partially applied."))
        XCTAssertTrue(popoverText.contains("UnsupportedNew.swift [unsupported operation]"))
        XCTAssertTrue(popoverText.contains("UnsupportedOld.swift [unsupported operation]"))
    }

    func testWorkspaceEditPreviewOpenConflictDecisionSelectsTargetTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("open-conflict-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("open-conflict-main.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        let dirtyTab = try XCTUnwrap(vc.activeTab)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)
        XCTAssertEqual(vc.activeTab?.fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        var capturedPreview: AttoWorkspaceEditPreview?
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            capturedPreview = preview
            return .openConflict(dirtyURL.absoluteString)
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )

        let preview = try XCTUnwrap(capturedPreview)
        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.firstConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(vc.selectedTabID, dirtyTab.id)
        XCTAssertEqual(vc.activeTab?.fileURL.standardizedFileURL, dirtyURL.standardizedFileURL)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Opened WorkspaceEdit conflict: \(dirtyURL.lastPathComponent)")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "main\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
    }

    func testWorkspaceEditPreviewSaveConflictDecisionSavesTargetTabBeforeRetry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("save-conflict-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("save-conflict-main.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        let dirtyTab = try XCTUnwrap(vc.activeTab)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        let dirtyTextBeforeSave = try dirtyTab.editCore.editor.text()
        vc.openFile(url: mainURL, mode: .pinned)
        XCTAssertEqual(vc.activeTab?.fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        var capturedPreview: AttoWorkspaceEditPreview?
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            capturedPreview = preview
            return .saveConflict(dirtyURL.absoluteString)
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )

        let preview = try XCTUnwrap(capturedPreview)
        XCTAssertEqual(preview.firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), dirtyTextBeforeSave)
        let savedDirtyItem = try XCTUnwrap(
            vc.openFileItems().first { $0.url.standardizedFileURL == dirtyURL.standardizedFileURL }
        )
        XCTAssertFalse(savedDirtyItem.isDirty)
        XCTAssertEqual(vc.activeTab?.fileURL.standardizedFileURL, mainURL.standardizedFileURL)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Saved WorkspaceEdit conflict: \(dirtyURL.lastPathComponent)")

        vc._setWorkspaceEditPreviewDecisionProviderForTesting { _ in .apply }
        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).editCore.editor.text(), "updated main\n")
    }

    func testWorkspaceEditPreviewDiscardConflictDecisionReloadsTargetTabBeforeRetry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("discard-conflict-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("discard-conflict-main.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        let dirtyTab = try XCTUnwrap(vc.activeTab)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        XCTAssertNotEqual(try dirtyTab.editCore.editor.text(), "dirty\n")
        vc.openFile(url: mainURL, mode: .pinned)
        XCTAssertEqual(vc.activeTab?.fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        var capturedPreview: AttoWorkspaceEditPreview?
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            capturedPreview = preview
            return .discardConflict(dirtyURL.absoluteString)
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )

        let preview = try XCTUnwrap(capturedPreview)
        XCTAssertEqual(preview.firstDiscardableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "dirty\n")
        XCTAssertEqual(try dirtyTab.editCore.editor.text(), "dirty\n")
        let discardedDirtyItem = try XCTUnwrap(
            vc.openFileItems().first { $0.url.standardizedFileURL == dirtyURL.standardizedFileURL }
        )
        XCTAssertFalse(discardedDirtyItem.isDirty)
        XCTAssertEqual(vc.activeTab?.fileURL.standardizedFileURL, mainURL.standardizedFileURL)
        XCTAssertEqual(
            vc._transientStatusTextForTesting(),
            "Discarded WorkspaceEdit conflict changes: \(dirtyURL.lastPathComponent)"
        )

        vc._setWorkspaceEditPreviewDecisionProviderForTesting { _ in .apply }
        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).editCore.editor.text(), "updated main\n")
    }

    func testWorkspaceEditPreviewSaveAndRetryDecisionAppliesAfterSavingTargetTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("save-retry-conflict-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("save-retry-conflict-main.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)

        var previews: [AttoWorkspaceEditPreview] = []
        var decisions: [AttoWorkspaceEditPreviewDecision] = [
            .saveAndRetry(dirtyURL.absoluteString),
            .apply,
        ]
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return decisions.removeFirst()
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(decisions.count, 0)
        XCTAssertEqual(previews.count, 2)
        XCTAssertFalse(previews[0].canApply)
        XCTAssertEqual(previews[0].firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertTrue(previews[1].canApply)
        XCTAssertTrue(previews[1].conflicts.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).editCore.editor.text(), "updated main\n")
    }

    func testWorkspaceEditPreviewDiscardAndRetryDecisionAppliesAfterReloadingTargetTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("discard-retry-conflict-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("discard-retry-conflict-main.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)

        var previews: [AttoWorkspaceEditPreview] = []
        var decisions: [AttoWorkspaceEditPreviewDecision] = [
            .discardAndRetry(dirtyURL.absoluteString),
            .apply,
        ]
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return decisions.removeFirst()
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(decisions.count, 0)
        XCTAssertEqual(previews.count, 2)
        XCTAssertFalse(previews[0].canApply)
        XCTAssertEqual(previews[0].firstDiscardableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertTrue(previews[1].canApply)
        XCTAssertTrue(previews[1].conflicts.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).editCore.editor.text(), "updated main\n")
    }

    func testRenameWorkspaceEditSaveAndRetryRerunsRenameRequestInsteadOfOldPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("rename-retry-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("rename-retry-main.txt")
        let captureURL = tempDir.appendingPathComponent("rename-retry-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("rename-retry-fake-lsp.sh")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)
        let mainTab = try XCTUnwrap(vc.activeTab)
        try mainTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: mainURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelRenameUI()
            mainTab.editCore.editor.lspDisable()
        }

        var previews: [AttoWorkspaceEditPreview] = []
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return .saveAndRetry(dirtyURL.absoluteString)
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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

        XCTAssertTrue(vc._applyRenameResultJSONForTesting(workspaceEdit, newName: "renamedSymbol"))

        XCTAssertEqual(previews.count, 1)
        XCTAssertFalse(previews[0].canApply)
        XCTAssertEqual(previews[0].firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "main\n")
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/rename""#
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/rename""#), captured)
        XCTAssertTrue(captured.contains(#""newName":"renamedSymbol""#), captured)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Retrying WorkspaceEdit request: Rename: renamedSymbol")
    }

    func testCodeActionWorkspaceEditSaveAndRetryRerunsCodeActionRequestInsteadOfOldPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("code-action-retry-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("code-action-retry-main.txt")
        let captureURL = tempDir.appendingPathComponent("code-action-retry-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("code-action-retry-fake-lsp.py")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)
        try writeCodeActionFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)
        let mainTab = try XCTUnwrap(vc.activeTab)
        try mainTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: mainURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelCodeActionUI()
            mainTab.editCore.editor.lspDisable()
        }

        var previews: [AttoWorkspaceEditPreview] = []
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return .saveAndRetry(dirtyURL.absoluteString)
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let requestContext = try vc.codeActionRequestContext(
            tab: mainTab,
            onlyKinds: ["quickfix"],
            showFeedback: true
        )

        let resultJSON = """
        [
          {
            "title": "Fix conflict",
            "kind": "quickfix",
            "edit": {
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
        ]
        """
        let item = try XCTUnwrap(AttoLspCodeActionParser.items(fromCodeActionResultJSON: resultJSON).first)

        XCTAssertTrue(vc.applyCodeAction(item, showFeedback: true, requestContext: requestContext))

        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews[0].firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "main\n")
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/codeAction""#
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/codeAction""#), captured)
        XCTAssertTrue(captured.contains(#""only":["quickfix"]"#), captured)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Retrying WorkspaceEdit request: Code Actions: quickfix")
    }

    func testCodeLensCommandWorkspaceEditSaveAndRetryRerunsExecuteCommandInsteadOfOldPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("code-lens-retry-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("code-lens-retry-main.txt")
        let captureURL = tempDir.appendingPathComponent("code-lens-retry-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("code-lens-retry-fake-lsp.py")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let resultJSON = """
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
        try writeExecuteCommandWorkspaceEditFakeLspServerScript(
            captureURL: captureURL,
            scriptURL: scriptURL,
            resultJSON: resultJSON
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)
        let mainTab = try XCTUnwrap(vc.activeTab)
        try mainTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: mainURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelExecuteCommandUI()
            mainTab.editCore.editor.lspDisable()
        }

        var previews: [AttoWorkspaceEditPreview] = []
        var decisions: [AttoWorkspaceEditPreviewDecision] = [
            .saveAndRetry(dirtyURL.absoluteString),
            .cancel,
        ]
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return decisions.removeFirst()
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let item = try XCTUnwrap(AttoLspCodeLensParser.item(fromCodeLensJSON: """
        {
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 0 }
          },
          "command": {
            "title": "Apply command edit",
            "command": "atto.applyEdit",
            "arguments": []
          }
        }
        """))

        XCTAssertTrue(vc.applyCodeLens(item))

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"workspace/executeCommand""#,
            minimumOccurrences: 2
        )
        XCTAssertEqual(occurrenceCount(of: #""method":"workspace/executeCommand""#, in: captured), 2)
        waitUntil { previews.count >= 2 }
        XCTAssertEqual(previews.count, 2)
        XCTAssertFalse(previews[0].canApply)
        XCTAssertEqual(previews[0].firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertTrue(previews[1].canApply)
        XCTAssertTrue(previews[1].conflicts.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "main\n")
    }

    func testInlayHintResolveWorkspaceEditSaveAndRetryRerunsResolveRequestInsteadOfOldPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("inlay-retry-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("inlay-retry-main.txt")
        let captureURL = tempDir.appendingPathComponent("inlay-retry-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("inlay-retry-fake-lsp.py")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)
        try writeInlayHintResolveFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)
        let mainTab = try XCTUnwrap(vc.activeTab)
        try mainTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: mainURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelInlayHintResolveUI()
            mainTab.editCore.editor.lspDisable()
        }

        var previews: [AttoWorkspaceEditPreview] = []
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return .saveAndRetry(dirtyURL.absoluteString)
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let hintJSON = """
        {
          "position": { "line": 0, "character": 0 },
          "label": ": String"
        }
        """
        let context = AttoEditorAreaViewController.InlayHintResolveContext(
            tabID: mainTab.id,
            hintJSON: hintJSON,
            showFeedback: true
        )
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

        XCTAssertTrue(
            vc.applyWorkspaceEditJSONToActiveTab(
                workspaceEdit,
                requestRetryOwner: vc.inlayHintResolveWorkspaceEditRequestRetryOwner(context: context)
            ).accepted
        )

        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews[0].firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "main\n")
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"inlayHint/resolve""#
        )
        XCTAssertTrue(captured.contains(#""method":"inlayHint/resolve""#), captured)
        XCTAssertTrue(captured.contains(#"": String""#), captured)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Retrying WorkspaceEdit request: Inlay Hint Resolve")
    }

    func testColorPresentationWorkspaceEditSaveAndRetryRerunsColorPresentationRequest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("color-presentation-retry-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("color-presentation-retry-main.txt")
        let captureURL = tempDir.appendingPathComponent("color-presentation-retry-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("color-presentation-retry-fake-lsp.py")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "#ff0000\n".write(to: mainURL, atomically: true, encoding: .utf8)
        try writeColorPresentationFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)
        let mainTab = try XCTUnwrap(vc.activeTab)
        try mainTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: mainURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelColorPresentationUI()
            mainTab.editCore.editor.lspDisable()
        }

        var previews: [AttoWorkspaceEditPreview] = []
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return .saveAndRetry(dirtyURL.absoluteString)
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let context = AttoEditorAreaViewController.ColorPresentationRequestContext(
            tabID: mainTab.id,
            item: AttoLspDocumentColorParser.Item(
                range: EcuSelectionRange(start: 0, end: 7),
                startLine: 0,
                startUTF16Character: 0,
                color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
            ),
            showFeedback: true
        )
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

        XCTAssertTrue(
            vc.applyWorkspaceEditJSONToActiveTab(
                workspaceEdit,
                requestRetryOwner: vc.colorPresentationWorkspaceEditRequestRetryOwner(context: context)
            ).accepted
        )

        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews[0].firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "#ff0000\n")
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/colorPresentation""#
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/colorPresentation""#), captured)
        XCTAssertTrue(captured.contains(#""red":1"#), captured)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Retrying WorkspaceEdit request: Color Presentation")
    }

    func testFormattingWorkspaceEditSaveAndRetryRerunsFormattingRequestInsteadOfOldPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("formatting-retry-dirty.txt")
        let mainURL = tempDir.appendingPathComponent("formatting-retry-main.txt")
        let captureURL = tempDir.appendingPathComponent("formatting-retry-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("formatting-retry-fake-lsp.py")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)
        try writeFormattingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)
        let mainTab = try XCTUnwrap(vc.activeTab)
        try mainTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: mainURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            vc.cancelFormattingUI()
            mainTab.editCore.editor.lspDisable()
        }

        var previews: [AttoWorkspaceEditPreview] = []
        var decisions: [AttoWorkspaceEditPreviewDecision] = [
            .saveAndRetry(dirtyURL.absoluteString),
            .cancel,
        ]
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return decisions.isEmpty ? .cancel : decisions.removeFirst()
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let context = AttoEditorAreaViewController.FormattingRequestContext(
            tabID: mainTab.id,
            kind: .document,
            showFeedback: true
        )
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

        XCTAssertTrue(
            vc.applyWorkspaceEditJSONToActiveTab(
                workspaceEdit,
                requestRetryOwner: vc.formattingWorkspaceEditRequestRetryOwner(context: context)
            ).accepted
        )

        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews[0].firstSaveableConflictTargetURI, dirtyURL.absoluteString)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "main\n")
        XCTAssertEqual(try XCTUnwrap(vc.activeTab).fileURL.standardizedFileURL, mainURL.standardizedFileURL)

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/formatting""#
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/formatting""#), captured)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Retrying WorkspaceEdit request: Format Document")
    }
}
