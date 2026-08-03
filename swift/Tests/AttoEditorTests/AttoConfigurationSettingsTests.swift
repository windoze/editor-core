import Foundation
@testable import AttoEditor
import XCTest

@MainActor
final class AttoConfigurationSettingsTests: XCTestCase {
    func testSettingsResolutionAppliesUserWorkspaceRuntimePrecedence() {
        let base = baseSnapshot()

        let user = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                fontFamilies: ["User Mono"],
                fontSizePoints: 15,
                wrapMode: "word"
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "User Theme"),
            language: AttoLanguagePreferenceSettings(
                commentConfigurations: [
                    "swift": .line("//"),
                ],
                lspAutoRestart: AttoLspAutoRestartPolicySettings(maxAttempts: 4)
            ),
            workspace: AttoWorkspacePreferenceSettings(rootPath: "/user/root")
        )

        let workspace = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                wrapMode: "none",
                wrapIndent: "same_as_line_indent"
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "Workspace Theme"),
            language: AttoLanguagePreferenceSettings(
                commentConfigurations: [
                    "python": .line("#"),
                ],
                lspAutoRestart: AttoLspAutoRestartPolicySettings(
                    disabledServerKeys: ["workspace-lsp"],
                    serverMaxAttempts: ["workspace-lsp": 2]
                )
            ),
            workspace: AttoWorkspacePreferenceSettings(rootPath: "/workspace/root")
        )

        let runtime = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(autoPairsEnabled: false),
            rendering: AttoRenderingPreferenceSettings(themeName: "Runtime Theme"),
            language: AttoLanguagePreferenceSettings(
                commentConfigurations: [
                    "swift": .lineAndBlock(";;", "#|", "|#"),
                ],
                lspAutoRestart: AttoLspAutoRestartPolicySettings(
                    baseDelaySeconds: 1.5,
                    serverBaseDelaySeconds: ["runtime-lsp": 0.5]
                )
            )
        )

        let resolution = base.resolvingSettings(user: user, workspace: workspace, runtime: runtime)
        let snapshot = resolution.snapshot

        XCTAssertEqual(resolution.appliedScopes, [.user, .workspace, .runtime])
        XCTAssertEqual(snapshot.editor.fontFamilies, ["User Mono"])
        XCTAssertEqual(snapshot.editor.fontSizePoints, 15)
        XCTAssertFalse(snapshot.editor.autoPairsEnabled)
        XCTAssertEqual(snapshot.editor.wrapMode, "none")
        XCTAssertEqual(snapshot.editor.wrapIndent, "same_as_line_indent")
        XCTAssertEqual(snapshot.rendering.themeName, "Runtime Theme")
        XCTAssertEqual(snapshot.language.commentConfigurations["rust"], .line("//"))
        XCTAssertEqual(snapshot.language.commentConfigurations["python"], .line("#"))
        XCTAssertEqual(snapshot.language.commentConfigurations["swift"], .lineAndBlock(";;", "#|", "|#"))
        XCTAssertEqual(snapshot.language.lspAutoRestart.enabled, true)
        XCTAssertEqual(snapshot.language.lspAutoRestart.maxAttempts, 4)
        XCTAssertEqual(snapshot.language.lspAutoRestart.baseDelaySeconds, 1.5)
        XCTAssertEqual(snapshot.language.lspAutoRestart.disabledServerKeys, ["workspace-lsp"])
        XCTAssertEqual(snapshot.language.lspAutoRestart.serverMaxAttempts, ["workspace-lsp": 2])
        XCTAssertEqual(snapshot.language.lspAutoRestart.serverBaseDelaySeconds, ["runtime-lsp": 0.5])
        XCTAssertEqual(snapshot.workspace.rootPath, "/workspace/root")
    }

    func testSettingsResolutionSkipsEmptyScopes() {
        let base = baseSnapshot()
        let resolution = base.resolvingSettings(
            user: AttoConfigurationSettings(),
            workspace: nil,
            runtime: AttoConfigurationSettings(editor: AttoEditorPreferenceSettings(fontSizePoints: 18))
        )

        XCTAssertEqual(resolution.appliedScopes, [.runtime])
        XCTAssertEqual(resolution.snapshot.editor.fontSizePoints, 18)
    }

    func testSettingsStorePersistsUserAndWorkspaceSettings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoConfigurationSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userSettingsURL = tempDir.appendingPathComponent("user-settings.json")
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        let store = AttoConfigurationSettingsStore(userSettingsURL: userSettingsURL)
        let userSettings = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontFamilies: ["User Mono"])
        )
        let workspaceSettings = AttoConfigurationSettings(
            rendering: AttoRenderingPreferenceSettings(themeName: "Workspace Theme")
        )

        XCTAssertNil(try store.loadUserSettings())
        XCTAssertNil(try store.loadWorkspaceSettings(workspaceRootURL: workspaceRootURL))

        try store.saveUserSettings(userSettings)
        try store.saveWorkspaceSettings(workspaceSettings, workspaceRootURL: workspaceRootURL)

        XCTAssertEqual(try store.loadUserSettings(), userSettings)
        XCTAssertEqual(try store.loadWorkspaceSettings(workspaceRootURL: workspaceRootURL), workspaceSettings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: userSettingsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: workspaceRootURL
                .appendingPathComponent(".attoeditor", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
                .path
        ))
    }

    func testSettingsDecodeIgnoresUnknownFutureFields() throws {
        let json = """
        {
          "schema_version": 2,
          "future_top_level": true,
          "editor": {
            "font_size_points": 17,
            "future_editor_field": "ignored"
          },
          "language": {
            "comment_configurations": {
              "swift": {
                "line": "//",
                "future_comment_field": "ignored"
              }
            },
            "lsp_auto_restart": {
              "max_attempts": 5,
              "future_lsp_policy_field": "ignored"
            },
            "future_language_field": "ignored"
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(AttoConfigurationSettings.self, from: data)

        XCTAssertEqual(settings.schemaVersion, 2)
        XCTAssertEqual(settings.editor?.fontSizePoints, 17)
        XCTAssertEqual(settings.language?.commentConfigurations?["swift"], .line("//"))
        XCTAssertEqual(settings.language?.lspAutoRestart?.maxAttempts, 5)
    }

    private func baseSnapshot() -> AttoConfigurationSnapshot {
        AttoConfigurationSnapshot(
            editor: AttoEditorPreferenceSnapshot(
                fontFamilies: ["Base Mono"],
                fontSizePoints: 13,
                autoPairsEnabled: true,
                wrapMode: "char",
                wrapIndent: "none"
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
                rootPath: "/base/root"
            )
        )
    }
}
