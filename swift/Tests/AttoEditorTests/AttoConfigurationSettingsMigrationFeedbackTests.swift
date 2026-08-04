import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoConfigurationSettingsMigrationFeedbackTests: XCTestCase {
    func testSettingsStoreMigratesLegacyAliasesToCanonicalSchema() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoConfigurationSettingsMigrationFeedbackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userSettingsURL = tempDir.appendingPathComponent("settings.json")
        let legacyJSON = """
        {
          "editor": {
            "font_face": "Legacy Mono",
            "font_size": 18,
            "word_wrap": false
          },
          "rendering": {
            "theme": "Atto Light"
          },
          "language": {
            "lsp_auto_restart_enabled": false,
            "lsp_auto_restart_max_attempts": 5,
            "lsp_auto_restart_base_delay_seconds": 2.5
          }
        }
        """
        try legacyJSON.write(to: userSettingsURL, atomically: true, encoding: .utf8)

        let store = AttoConfigurationSettingsStore(userSettingsURL: userSettingsURL)
        let outcome = try store.loadUserSettingsOutcome()
        let settings = try XCTUnwrap(outcome.settings)

        XCTAssertEqual(settings.schemaVersion, AttoConfigurationSettings.currentSchemaVersion)
        XCTAssertEqual(settings.editor?.fontFamilies, ["Legacy Mono"])
        XCTAssertEqual(settings.editor?.fontSizePoints, 18)
        XCTAssertEqual(settings.editor?.wrapMode, "none")
        XCTAssertEqual(settings.rendering?.themeName, "Atto Light")
        XCTAssertEqual(settings.language?.lspAutoRestart?.enabled, false)
        XCTAssertEqual(settings.language?.lspAutoRestart?.maxAttempts, 5)
        XCTAssertEqual(settings.language?.lspAutoRestart?.baseDelaySeconds, 2.5)

        guard case .migrated(_, _, let fromSchemaVersion)? = outcome.event else {
            return XCTFail("Expected migration event")
        }
        XCTAssertEqual(fromSchemaVersion, AttoConfigurationSettings.legacySchemaVersion)

        let migratedJSON = try String(contentsOf: userSettingsURL, encoding: .utf8)
        XCTAssertTrue(migratedJSON.contains("\"font_families\""))
        XCTAssertTrue(migratedJSON.contains("\"font_size_points\""))
        XCTAssertTrue(migratedJSON.contains("\"wrap_mode\""))
        XCTAssertTrue(migratedJSON.contains("\"theme_name\""))
        XCTAssertTrue(migratedJSON.contains("\"lsp_auto_restart\""))
        XCTAssertFalse(migratedJSON.contains("\"font_face\""))
        XCTAssertFalse(migratedJSON.contains("\"font_size\""))
        XCTAssertFalse(migratedJSON.contains("\"word_wrap\""))
        XCTAssertFalse(migratedJSON.contains("\"lsp_auto_restart_enabled\""))
    }

    func testSettingsSchemaPageReportsInvalidUserSettingsFallback() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoConfigurationSettingsMigrationFeedbackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userSettingsURL = tempDir.appendingPathComponent("settings.json")
        try "{ invalid json".write(to: userSettingsURL, atomically: true, encoding: .utf8)

        let store = AttoConfigurationSettingsStore(userSettingsURL: userSettingsURL)
        let page = AttoSettingsSchemaPageViewController(settingsStore: store)
        _ = page.view

        XCTAssertTrue(page.statusTextForTesting().contains("User Settings invalid; using fallback settings"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: userSettingsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userSettingsURL.appendingPathExtension("invalid").path))
    }

    func testAppDelegateReportsInvalidWorkspaceSettingsFallbackAfterWindowExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoConfigurationSettingsMigrationFeedbackTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        try store.saveUserSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 14)
        ))

        let delegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: store
        )
        let ctx = delegate._createWindowForTesting(workspaceRootURL: workspaceRootURL)
        addTeardownBlock {
            delegate._closeWindowsForTesting()
        }

        let workspaceSettingsURL = AttoConfigurationSettingsStore.workspaceSettingsURL(
            forWorkspaceRootURL: workspaceRootURL
        )
        try FileManager.default.createDirectory(
            at: workspaceSettingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{ invalid json".write(to: workspaceSettingsURL, atomically: true, encoding: .utf8)

        delegate._applyEditorPreferencesForTesting()

        XCTAssertEqual(
            ctx.editorAreaController._transientStatusTextForTesting(),
            "Workspace Settings invalid; using fallback settings"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceSettingsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceSettingsURL.appendingPathExtension("invalid").path))
        XCTAssertEqual(ctx.editorAreaController._configurationSnapshotForTesting().editor.fontSizePoints, 14)
    }
}
