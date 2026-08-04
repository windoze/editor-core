@testable import AttoEditor
import XCTest

@MainActor
final class AttoRuntimeConfigurationSettingsTests: XCTestCase {
    func testSettingsStorePersistsAndClearsRuntimeSettings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoRuntimeConfigurationSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        let settings = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 18, wrapMode: "none")
        )

        XCTAssertNil(try store.loadRuntimeSettings())
        try store.saveRuntimeSettings(settings)
        XCTAssertEqual(try store.loadRuntimeSettings(), settings)

        try store.clearRuntimeSettings()
        XCTAssertNil(try store.loadRuntimeSettings())
        try store.clearRuntimeSettings()
        XCTAssertNil(try store.loadRuntimeSettings())
    }

    func testDelegateLoadsPersistedRuntimeOverridesAndClearCommandRollsBackToWorkspaceSettings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoRuntimeConfigurationSettingsTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        try store.saveUserSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 14, wrapMode: "word")
        ))
        try store.saveWorkspaceSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 16, wrapMode: "char")
        ), workspaceRootURL: workspaceRootURL)
        try store.saveRuntimeSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 18, wrapMode: "none")
        ))

        let firstDelegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: store
        )
        let firstContext = firstDelegate._createWindowForTesting(workspaceRootURL: workspaceRootURL)
        addTeardownBlock {
            firstDelegate._closeWindowsForTesting()
        }

        var snapshot = firstContext.editorAreaController._configurationSnapshotForTesting()
        XCTAssertEqual(snapshot.editor.fontSizePoints, 18)
        XCTAssertEqual(snapshot.editor.wrapMode, "none")

        XCTAssertTrue(firstDelegate.executeCommand(id: "settings.clear_runtime_overrides"))
        XCTAssertNil(try store.loadRuntimeSettings())
        snapshot = firstContext.editorAreaController._configurationSnapshotForTesting()
        XCTAssertEqual(snapshot.editor.fontSizePoints, 16)
        XCTAssertEqual(snapshot.editor.wrapMode, "char")

        let secondDelegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: store
        )
        let secondContext = secondDelegate._createWindowForTesting(workspaceRootURL: workspaceRootURL)
        addTeardownBlock {
            secondDelegate._closeWindowsForTesting()
        }

        snapshot = secondContext.editorAreaController._configurationSnapshotForTesting()
        XCTAssertEqual(snapshot.editor.fontSizePoints, 16)
        XCTAssertEqual(snapshot.editor.wrapMode, "char")
    }

    func testRuntimeOverrideCommandsUseSettingsMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoRuntimeConfigurationSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        let delegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: store
        )
        let commands = delegate._defaultCommandsForTesting()

        for commandID in [
            "settings.open_runtime_overrides",
            "settings.validate_runtime_overrides",
            "settings.clear_runtime_overrides",
        ] {
            let command = try XCTUnwrap(commands.first { $0.id == commandID })
            XCTAssertEqual(command.group, "Settings")
            XCTAssertFalse(command.requiresEditor)
            XCTAssertTrue(command.isEnabled)

            let schema = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: commandID))
            XCTAssertEqual(schema.macroPolicy, .notRecordable)
            XCTAssertFalse(schema.isParameterized)
        }
    }
}
