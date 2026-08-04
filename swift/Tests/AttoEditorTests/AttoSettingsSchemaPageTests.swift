import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoSettingsSchemaPageTests: XCTestCase {
    func testSettingsSchemaRowsExposeEffectiveSourceOverrideAndValidation() {
        let schema = AttoConfigurationSettingsSchema.current
        let userSettings = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 14)
        )
        let workspaceSettings = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                fontSizePoints: 16,
                wrapMode: "paragraph"
            ),
            scopedSettings: [
                AttoScopedConfigurationSettings(
                    selectors: ["source.swift"],
                    editor: AttoEditorPreferenceSettings(fontSizePoints: 20)
                ),
            ]
        )
        let runtimeSettings = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 18)
        )
        let validationIssues = [
            schema.validate(userSettings, scope: .user),
            schema.validate(workspaceSettings, scope: .workspace),
            schema.validate(runtimeSettings, scope: .runtime),
        ].flatMap(\.issues)

        let rows = AttoSettingsSchemaRows.make(
            schema: schema,
            baseSnapshot: baseSnapshot(),
            userSettings: userSettings,
            workspaceSettings: workspaceSettings,
            runtimeSettings: runtimeSettings,
            validationIssues: validationIssues
        )

        let fontSizeRow = row("editor.font_size_points", in: rows)
        XCTAssertEqual(fontSizeRow.effectiveValue, "18")
        XCTAssertEqual(fontSizeRow.source, "Runtime")
        XCTAssertEqual(
            fontSizeRow.overrideValue,
            "User: 14; Workspace: 16; Workspace Scoped[0] (source.swift): 20; Runtime: 18"
        )
        XCTAssertEqual(fontSizeRow.validationError, "")

        let wrapModeRow = row("editor.wrap_mode", in: rows)
        XCTAssertEqual(wrapModeRow.effectiveValue, "paragraph")
        XCTAssertEqual(wrapModeRow.source, "Workspace")
        XCTAssertEqual(wrapModeRow.overrideValue, "Workspace: paragraph")
        XCTAssertEqual(
            wrapModeRow.validationError,
            "Workspace: Value 'paragraph' is not one of: none, char, word."
        )
    }

    func testPreferencesSettingsPageLoadsSchemaRowsFromStoreAndRuntimeOverrides() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoSettingsSchemaPageTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let settingsStore = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        try settingsStore.saveUserSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 14)
        ))
        try settingsStore.saveWorkspaceSettings(AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                fontSizePoints: 16,
                wrapMode: "paragraph"
            )
        ), workspaceRootURL: workspaceRootURL)

        let controller = AttoPreferencesWindowController(
            settingsStore: settingsStore,
            workspaceRootURLProvider: { workspaceRootURL },
            runtimeSettingsProvider: {
                AttoConfigurationSettings(
                    editor: AttoEditorPreferenceSettings(fontSizePoints: 18)
                )
            }
        )
        addTeardownBlock {
            controller.close()
        }

        let rows = controller._settingsSchemaRowsForTesting()
        let fontSizeRow = row("editor.font_size_points", in: rows)
        XCTAssertEqual(fontSizeRow.effectiveValue, "18")
        XCTAssertEqual(fontSizeRow.source, "Runtime")
        XCTAssertEqual(fontSizeRow.overrideValue, "User: 14; Workspace: 16; Runtime: 18")

        let wrapModeRow = row("editor.wrap_mode", in: rows)
        XCTAssertEqual(wrapModeRow.effectiveValue, "paragraph")
        XCTAssertEqual(wrapModeRow.source, "Workspace")
        XCTAssertEqual(
            wrapModeRow.validationError,
            "Workspace: Value 'paragraph' is not one of: none, char, word."
        )
    }

    private func row(
        _ keyPath: String,
        in rows: [AttoSettingsSchemaRow],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AttoSettingsSchemaRow {
        guard let row = rows.first(where: { $0.keyPath == keyPath }) else {
            XCTFail("Missing row for \(keyPath)", file: file, line: line)
            return AttoSettingsSchemaRow(
                keyPath: keyPath,
                title: "",
                valueKind: .string,
                effectiveValue: "",
                source: "",
                overrideValue: "",
                validationError: ""
            )
        }
        return row
    }

    private func baseSnapshot() -> AttoConfigurationSnapshot {
        AttoConfigurationSnapshot(
            editor: AttoEditorPreferenceSnapshot(
                fontFamilies: ["Base Mono"],
                fontSizePoints: 13,
                autoPairsEnabled: true,
                wrapMode: "char",
                wrapIndent: "none",
                findCaseSensitive: true,
                findWholeWord: false,
                findRegex: false
            ),
            rendering: AttoRenderingPreferenceSnapshot(
                themeName: "Base Theme",
                fontLigaturesEnabled: false
            ),
            language: AttoLanguagePreferenceSnapshot(
                commentConfigurations: [
                    "rust": .line("//"),
                ],
                lspAutoRestart: AttoLspAutoRestartPolicySnapshot(
                    enabled: true,
                    maxAttempts: 3,
                    baseDelaySeconds: 5,
                    disabledServerKeys: [],
                    serverMaxAttempts: [:],
                    serverBaseDelaySeconds: [:]
                )
            ),
            workspace: AttoWorkspacePreferenceSnapshot(
                rootURL: "file:///base/root/",
                rootPath: "/base/root",
                findInFilesDefaultScope: "opened_files",
                workspaceSearchIncludeGlobs: [],
                workspaceSearchExcludeGlobs: []
            )
        )
    }
}
