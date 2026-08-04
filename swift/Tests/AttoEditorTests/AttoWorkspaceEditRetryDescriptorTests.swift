import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoWorkspaceEditRetryDescriptorTests: XCTestCase {
    func testRenameRetryOwnerRecordsTypedDescriptorAndHistoryOwner() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoWorkspaceEditRetryDescriptorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rename-descriptor.txt").standardizedFileURL
        try "main\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir.standardizedFileURL)
        defer {
            ctx.editorAreaController.closeWorkspaceEditHistoryPanel()
            ctx.window.close()
        }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(ctx.editorAreaController.activeTab)

        let context = AttoEditorAreaViewController.RenameRequestContext(
            tabID: tab.id,
            documentURI: fileURL.absoluteString,
            logicalLine: 3,
            logicalColumn: 5,
            newName: "renamedSymbol",
            showFeedback: false
        )
        let owner = ctx.editorAreaController.renameWorkspaceEditRequestRetryOwner(context: context)
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
            ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(
                workspaceEdit,
                requestRetryOwner: owner
            ).accepted
        )
        let latestSequence = try XCTUnwrap(ctx.editorAreaController._coreWorkspaceEditTransactionLatestSequenceForTesting())
        let recordedDescriptors = ctx.editorAreaController._workspaceEditRequestRetryDescriptorsForTesting()
        XCTAssertEqual(recordedDescriptors[latestSequence], descriptor)

        XCTAssertTrue(ctx.editorAreaController.showWorkspaceEditHistoryPanel())
        let item = try XCTUnwrap(ctx.editorAreaController._workspaceEditHistoryPanelItemsForTesting().first)
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
}
