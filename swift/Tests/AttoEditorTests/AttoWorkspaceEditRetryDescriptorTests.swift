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
}
