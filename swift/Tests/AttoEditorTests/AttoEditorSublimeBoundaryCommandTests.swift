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

    func testSublimeBuildSystemRunsSingleWorkspaceBuildAndShowsOutput() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorSublimeBuildSystemTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let buildURL = tempDir.appendingPathComponent("Echo.sublime-build")
        try """
        {
          "name": "Echo Build",
          "cmd": ["/bin/sh", "-c", "printf build-ok"]
        }
        """.write(to: buildURL, atomically: true, encoding: .utf8)

        let delegate = AttoAppDelegate(keyBindings: [:])
        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }

        XCTAssertTrue(delegate.executeCommand(id: "build.run"))
        XCTAssertTrue(waitForMainRunLoop {
            delegate._sublimeOutputTextForTesting().contains("Build finished: Echo Build")
        })
        XCTAssertTrue(delegate._sublimeOutputTextForTesting().contains("build-ok"))
        XCTAssertEqual(ctx.editorAreaController._transientStatusTextForTesting(), "Build finished: Echo Build")
    }

    func testPackageResourceCommandOpensSingleResource() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorPackageResourceTests-\(UUID().uuidString)", isDirectory: true)
        let packageDir = tempDir.appendingPathComponent("Packages/User", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let resourceURL = packageDir.appendingPathComponent("Preferences.sublime-settings")
        try "{}\n".write(to: resourceURL, atomically: true, encoding: .utf8)

        let delegate = AttoAppDelegate(keyBindings: [:])
        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }

        XCTAssertTrue(delegate.executeCommand(id: "package.open_resource"))
        XCTAssertTrue(ctx.editorAreaController.containsFile(url: resourceURL))
        XCTAssertEqual(
            ctx.editorAreaController._transientStatusTextForTesting(),
            "Opened package resource: Packages/User/Preferences.sublime-settings"
        )
    }

    private func waitForMainRunLoop(
        timeout: TimeInterval = 3,
        _ predicate: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return predicate()
    }
}
