import AppKit
@testable import AttoEditor
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testSublimeBoundaryCommandsExposeDiscoverableFeedback() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorSublimeBoundaryCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let delegate = AttoAppDelegate(keyBindings: [:])
        for feature in AttoSublimeFeatureBoundary.allCases {
            XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: feature.commandID), feature.commandID)
        }

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }

        let ids = Set(delegate._defaultCommandsForTesting().map(\.id))
        for feature in AttoSublimeFeatureBoundary.allCases {
            XCTAssertTrue(ids.contains(feature.commandID), feature.commandID)
            XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: feature.commandID), feature.commandID)
            XCTAssertEqual(
                delegate._commandSchemaForTesting(commandID: feature.commandID)?.macroPolicy,
                .notRecordable,
                feature.commandID
            )
            XCTAssertTrue(delegate.executeCommand(id: feature.commandID), feature.commandID)
            XCTAssertEqual(ctx.editorAreaController._transientStatusTextForTesting(), feature.statusText)
        }
    }
}
