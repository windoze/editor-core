import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoWorkspaceEditRetryDescriptorTests: XCTestCase {
    func testRequestOwnerStorePersistsRecentWorkspaceDescriptors() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoWorkspaceEditRetryDescriptorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootA = tempDir.appendingPathComponent("root-a", isDirectory: true).standardizedFileURL
        let rootB = tempDir.appendingPathComponent("root-b", isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let store = AttoWorkspaceEditRequestOwnerStore(
            logFileURL: tempDir.appendingPathComponent("workspace-edit-request-owners.jsonl"),
            maxPersistedEntries: 2
        )
        let descriptorA1 = AttoWorkspaceEditRequestRetryDescriptor.unknown(label: "First")
        let descriptorA2 = AttoWorkspaceEditRequestRetryDescriptor.unknown(label: "Second")
        let descriptorA3 = AttoWorkspaceEditRequestRetryDescriptor.unknown(label: "Third")
        let descriptorB = AttoWorkspaceEditRequestRetryDescriptor.unknown(label: "Other Root")

        try store.append(record: AttoWorkspaceEditRequestOwnerRecord(
            recordedAt: Date(timeIntervalSince1970: 1),
            workspaceRootURI: rootA.absoluteString,
            transactionSequence: 1,
            workspaceEditJSON: #"{"changes":{}}"#,
            descriptor: descriptorA1
        ))
        try store.append(record: AttoWorkspaceEditRequestOwnerRecord(
            recordedAt: Date(timeIntervalSince1970: 2),
            workspaceRootURI: rootA.absoluteString,
            transactionSequence: 2,
            workspaceEditJSON: #"{"changes":{"a":[]}}"#,
            descriptor: descriptorA2
        ))
        try store.append(record: AttoWorkspaceEditRequestOwnerRecord(
            recordedAt: Date(timeIntervalSince1970: 3),
            workspaceRootURI: rootB.absoluteString,
            transactionSequence: 1,
            workspaceEditJSON: #"{"changes":{"b":[]}}"#,
            descriptor: descriptorB
        ))
        try store.append(record: AttoWorkspaceEditRequestOwnerRecord(
            recordedAt: Date(timeIntervalSince1970: 4),
            workspaceRootURI: rootA.absoluteString,
            transactionSequence: 3,
            workspaceEditJSON: #"{"changes":{"c":[]}}"#,
            descriptor: descriptorA3
        ))

        XCTAssertEqual(store.loadRecent(workspaceRootURL: rootA, limit: 10).map(\.transactionSequence), [2, 3])
        XCTAssertEqual(store.loadRecent(workspaceRootURL: rootA, limit: 1).map(\.descriptor.label), ["Third"])
        XCTAssertEqual(store.loadRecent(workspaceRootURL: rootB, limit: 10).map(\.descriptor.label), ["Other Root"])
    }

    func testRenameRetryOwnerRecordsTypedDescriptorAndHistoryOwner() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoWorkspaceEditRetryDescriptorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ownerStore = AttoWorkspaceEditRequestOwnerStore(
            logFileURL: tempDir.appendingPathComponent("workspace-edit-request-owners.jsonl")
        )
        let fileURL = tempDir.appendingPathComponent("rename-descriptor.txt").standardizedFileURL
        try "main\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir.standardizedFileURL, ownerStore: ownerStore)
        let window = attachToWindow(vc)
        defer {
            vc.closeWorkspaceEditHistoryPanel()
            window.close()
        }
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)

        let context = AttoEditorAreaViewController.RenameRequestContext(
            tabID: tab.id,
            documentURI: fileURL.absoluteString,
            logicalLine: 3,
            logicalColumn: 5,
            newName: "renamedSymbol",
            showFeedback: false
        )
        let owner = vc.renameWorkspaceEditRequestRetryOwner(context: context)
        let descriptor = owner.descriptor

        XCTAssertEqual(descriptor.kind, .rename)
        XCTAssertEqual(descriptor.label, "Rename: renamedSymbol")
        XCTAssertEqual(descriptor.workspaceRootURI, tempDir.standardizedFileURL.absoluteString)
        XCTAssertEqual(descriptor.documentURI, fileURL.absoluteString)
        XCTAssertEqual(descriptor.source.tabID, tab.id)
        XCTAssertEqual(descriptor.source.coreTabID, tab.coreTabID)
        XCTAssertEqual(descriptor.source.title, fileURL.lastPathComponent)
        XCTAssertEqual(descriptor.source.documentURI, fileURL.absoluteString)
        XCTAssertNil(descriptor.invalidationReason)
        XCTAssertTrue(descriptor.canRerun)

        let parameters = Dictionary(uniqueKeysWithValues: descriptor.parameterSummary.map { ($0.name, $0.value) })
        XCTAssertEqual(parameters["logicalLine"], "3")
        XCTAssertEqual(parameters["logicalColumn"], "5")
        XCTAssertEqual(parameters["newName"], "renamedSymbol")
        XCTAssertEqual(parameters["showFeedback"], "false")

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
            vc.applyWorkspaceEditJSONToActiveTab(
                workspaceEdit,
                requestRetryOwner: owner
            ).accepted
        )
        let latestSequence = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let recordedDescriptors = vc._workspaceEditRequestRetryDescriptorsForTesting()
        XCTAssertEqual(recordedDescriptors[latestSequence], descriptor)

        XCTAssertTrue(vc.showWorkspaceEditHistoryPanel())
        let item = try XCTUnwrap(vc._workspaceEditHistoryPanelItemsForTesting().first)
        XCTAssertEqual(item.sequence, latestSequence)
        XCTAssertEqual(item.requestRetryLabel, descriptor.label)
        XCTAssertEqual(item.requestRetryDescriptor, descriptor)
    }

    func testCompletionRetryOwnerRecordsRequestParameterSummary() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoWorkspaceEditRetryDescriptorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion-descriptor.txt").standardizedFileURL
        try "main\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir.standardizedFileURL)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(ctx.editorAreaController.activeTab)
        let context = AttoEditorAreaViewController.CompletionRequestContext(
            tabID: tab.id,
            logicalLine: 1,
            logicalColumn: 2,
            fallbackStart: 3,
            fallbackEnd: 4,
            beepOnFailure: false,
            showFeedback: true
        )

        let descriptor = ctx.editorAreaController.completionWorkspaceEditRequestRetryOwner(context: context).descriptor

        XCTAssertEqual(descriptor.kind, .completion)
        XCTAssertEqual(descriptor.label, "Completion")
        XCTAssertEqual(descriptor.workspaceRootURI, tempDir.standardizedFileURL.absoluteString)
        XCTAssertEqual(descriptor.documentURI, fileURL.absoluteString)
        XCTAssertEqual(descriptor.source.tabID, tab.id)
        XCTAssertEqual(descriptor.source.coreTabID, tab.coreTabID)
        XCTAssertNil(descriptor.invalidationReason)

        let parameters = Dictionary(uniqueKeysWithValues: descriptor.parameterSummary.map { ($0.name, $0.value) })
        XCTAssertEqual(parameters["logicalLine"], "1")
        XCTAssertEqual(parameters["logicalColumn"], "2")
        XCTAssertEqual(parameters["fallbackStart"], "3")
        XCTAssertEqual(parameters["fallbackEnd"], "4")
        XCTAssertEqual(parameters["beepOnFailure"], "false")
        XCTAssertEqual(parameters["showFeedback"], "true")
    }

    func testHistoryUsesPersistedDescriptorWhenClosureCacheIsGone() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoWorkspaceEditRetryDescriptorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ownerStore = AttoWorkspaceEditRequestOwnerStore(
            logFileURL: tempDir.appendingPathComponent("workspace-edit-request-owners.jsonl")
        )
        let fileURL = tempDir.appendingPathComponent("persisted-history-owner.txt").standardizedFileURL
        try "main\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir.standardizedFileURL, ownerStore: ownerStore)
        let window = attachToWindow(vc)
        defer {
            vc.closeWorkspaceEditHistoryPanel()
            window.close()
        }
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let context = AttoEditorAreaViewController.RenameRequestContext(
            tabID: tab.id,
            documentURI: fileURL.absoluteString,
            logicalLine: 0,
            logicalColumn: 0,
            newName: "persistedName",
            showFeedback: true
        )
        let owner = vc.renameWorkspaceEditRequestRetryOwner(context: context)
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

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit, requestRetryOwner: owner).accepted)
        let latestSequence = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
        XCTAssertEqual(vc._workspaceEditRequestOwnerRecordsForTesting().map(\.transactionSequence), [latestSequence])

        vc.workspaceEditRequestRetryOwnersByTransactionSequence.removeAll()
        XCTAssertTrue(vc.showWorkspaceEditHistoryPanel())
        let item = try XCTUnwrap(vc._workspaceEditHistoryPanelItemsForTesting().first)

        XCTAssertEqual(item.sequence, latestSequence)
        XCTAssertEqual(item.requestRetryLabel, "Rename: persistedName")
        XCTAssertEqual(item.requestRetryDescriptor?.kind, .rename)
        XCTAssertEqual(item.requestRetryDescriptor?.invalidationReason, .requestClosureUnavailable)
        XCTAssertEqual(item.requestRetryUnavailableReason, "retry closure unavailable")
        XCTAssertFalse(item.canRerunRequest)
        XCTAssertTrue(item.detail.contains("Request: Rename: persistedName unavailable (retry closure unavailable)"))
    }

    func testPreviewPanelDisablesConflictRetryButtonsWhenRequestCannotRerun() throws {
        let descriptor = AttoWorkspaceEditRequestRetryDescriptor
            .unknown(label: "Rename: persistedName")
            .invalidated(.requestClosureUnavailable)
        var preview = try dirtyDocumentConflictPreview()
        preview.requestRetryDescriptor = descriptor

        let panelController = AttoWorkspaceEditPreviewPanelController()
        let panel = panelController.showForTesting(relativeTo: nil, preview: preview)
        defer { panelController.closeForTesting() }

        let saveAndRetryButton: NSButton = try XCTUnwrap(findView(
            identifiedBy: AttoAccessibilityID.workspaceEditPreviewSaveAndRetryButton,
            in: panel.contentView
        ))
        let discardAndRetryButton: NSButton = try XCTUnwrap(findView(
            identifiedBy: AttoAccessibilityID.workspaceEditPreviewDiscardAndRetryButton,
            in: panel.contentView
        ))
        let summaryLabel: NSTextField = try XCTUnwrap(findView(
            identifiedBy: AttoAccessibilityID.workspaceEditPreviewSummary,
            in: panel.contentView
        ))

        XCTAssertFalse(saveAndRetryButton.isHidden)
        XCTAssertFalse(discardAndRetryButton.isHidden)
        XCTAssertFalse(saveAndRetryButton.isEnabled)
        XCTAssertFalse(discardAndRetryButton.isEnabled)
        XCTAssertEqual(saveAndRetryButton.toolTip, "Cannot retry Rename: persistedName: retry closure unavailable")
        XCTAssertEqual(discardAndRetryButton.toolTip, "Cannot retry Rename: persistedName: retry closure unavailable")
        XCTAssertTrue(summaryLabel.stringValue.contains(
            "Request: Rename: persistedName unavailable (retry closure unavailable)"
        ))
    }

    func testPreviewSaveAndRetryDoesNotSaveConflictWhenRequestCannotRerun() throws {
        try assertPreviewRetryDecisionDoesNotResolveConflictWhenRequestCannotRerun { uri in
            .saveAndRetry(uri)
        }
    }

    func testPreviewDiscardAndRetryDoesNotDiscardConflictWhenRequestCannotRerun() throws {
        try assertPreviewRetryDecisionDoesNotResolveConflictWhenRequestCannotRerun { uri in
            .discardAndRetry(uri)
        }
    }

    private func makeEditorArea(
        workspaceRootURL: URL,
        ownerStore: AttoWorkspaceEditRequestOwnerStore
    ) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL,
            workspaceEditRequestOwnerStore: ownerStore
        )
    }

    @discardableResult
    private func attachToWindow(_ vc: AttoEditorAreaViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func assertPreviewRetryDecisionDoesNotResolveConflictWhenRequestCannotRerun(
        decision: @escaping (String) -> AttoWorkspaceEditPreviewDecision
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoWorkspaceEditRetryDescriptorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ownerStore = AttoWorkspaceEditRequestOwnerStore(
            logFileURL: tempDir.appendingPathComponent("workspace-edit-request-owners.jsonl")
        )
        let dirtyURL = tempDir.appendingPathComponent("dirty-conflict.txt").standardizedFileURL
        let mainURL = tempDir.appendingPathComponent("main.txt").standardizedFileURL
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)
        try "main\n".write(to: mainURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir.standardizedFileURL, ownerStore: ownerStore)
        let window = attachToWindow(vc)
        defer {
            vc._setWorkspaceEditPreviewDecisionProviderForTesting(nil)
            window.close()
        }

        vc.openFile(url: dirtyURL, mode: .pinned)
        let dirtyTab = try XCTUnwrap(vc.activeTab)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))
        vc.openFile(url: mainURL, mode: .pinned)

        let descriptor = AttoWorkspaceEditRequestRetryDescriptor
            .unknown(label: "Rename: persistedName")
            .invalidated(.requestClosureUnavailable)
        var rerunCount = 0
        let owner = AttoWorkspaceEditRequestRetryOwner(descriptor: descriptor) {
            rerunCount += 1
            return true
        }
        var previews: [AttoWorkspaceEditPreview] = []
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            previews.append(preview)
            return decision(dirtyURL.absoluteString)
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

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit, requestRetryOwner: owner).accepted)
        XCTAssertEqual(rerunCount, 0)
        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews[0].requestRetryDescriptor, descriptor)
        XCTAssertFalse(previews[0].canResolveConflictAndRetry)
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertEqual(try String(contentsOf: dirtyURL, encoding: .utf8), "dirty\n")
        XCTAssertEqual(try dirtyTab.editCore.editor.text(), "!dirty\n")
        XCTAssertEqual(try String(contentsOf: mainURL, encoding: .utf8), "main\n")
        XCTAssertEqual(vc._transientStatusTextForTesting(), descriptor.retryUnavailableStatusText)
    }

    private func dirtyDocumentConflictPreview() throws -> AttoWorkspaceEditPreview {
        let result = try JSONDecoder().decode(EcuWorkspaceEditTransactionResult.self, from: Data("""
        {
          "mode": "preview",
          "apply_mode": "atomic",
          "applied": false,
          "applied_uris": [],
          "applied_edit_count": 0,
          "applied_resource_operation_count": 0,
          "conflicts": [
            {
              "uri": "file:///project/dirty.swift",
              "kind": "dirty_document",
              "severity": "error",
              "apply_impact": "blocks_atomic_apply",
              "resolution": "save_or_discard",
              "reason": "resource_operation_dirty_target",
              "operation": "delete",
              "message": "delete targets a modified open tab"
            }
          ],
          "skipped_uris": ["file:///project/dirty.swift"],
          "documents": [
            {
              "uri": "file:///project/dirty.swift",
              "edit_count": 0,
              "is_open": true,
              "is_dirty": true
            }
          ]
        }
        """.utf8))
        return AttoWorkspaceEditPreview(result: result)
    }

    private func findView<T: NSView>(identifiedBy identifier: String, in root: NSView?) -> T? {
        guard let root else { return nil }
        if root.identifier?.rawValue == identifier {
            return root as? T
        }
        for subview in root.subviews {
            if let match: T = findView(identifiedBy: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
