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
                wrapMode: "word",
                findCaseSensitive: false,
                wordBoundaryAsciiBoundaryChars: ","
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "User Theme"),
            language: AttoLanguagePreferenceSettings(
                commentConfigurations: [
                    "swift": .line("//"),
                ],
                semanticHighlightingEnabled: true,
                formatOnSaveEnabled: false,
                formatOnTypeEnabled: false,
                lspAutoRestart: AttoLspAutoRestartPolicySettings(maxAttempts: 4)
            ),
            workspace: AttoWorkspacePreferenceSettings(
                rootPath: "/user/root",
                findInFilesDefaultScope: "opened_files",
                workspaceSearchIncludeGlobs: ["Sources/**/*.swift"],
                workspaceSearchExcludeGlobs: ["**/*.generated.swift"]
            )
        )

        let workspace = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                wrapMode: "none",
                wrapIndent: "same_as_line_indent",
                findWholeWord: true,
                wordBoundaryAsciiBoundaryChars: "."
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "Workspace Theme"),
            language: AttoLanguagePreferenceSettings(
                commentConfigurations: [
                    "python": .line("#"),
                ],
                semanticHighlightingEnabled: false,
                formatOnSaveEnabled: true,
                formatOnTypeEnabled: true,
                lspAutoRestart: AttoLspAutoRestartPolicySettings(
                    disabledServerKeys: ["workspace-lsp"],
                    serverMaxAttempts: ["workspace-lsp": 2]
                )
            ),
            workspace: AttoWorkspacePreferenceSettings(
                rootPath: "/workspace/root",
                findInFilesDefaultScope: "workspace",
                workspaceSearchExcludeGlobs: ["Vendor/**"]
            )
        )

        let runtime = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(
                autoPairsEnabled: false,
                findRegex: true,
                wordBoundaryAsciiBoundaryChars: "/"
            ),
            rendering: AttoRenderingPreferenceSettings(themeName: "Runtime Theme"),
            language: AttoLanguagePreferenceSettings(
                commentConfigurations: [
                    "swift": .lineAndBlock(";;", "#|", "|#"),
                ],
                semanticHighlightingEnabled: true,
                formatOnSaveEnabled: false,
                formatOnTypeEnabled: false,
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
        XCTAssertFalse(snapshot.editor.findCaseSensitive)
        XCTAssertTrue(snapshot.editor.findWholeWord)
        XCTAssertTrue(snapshot.editor.findRegex)
        XCTAssertEqual(snapshot.editor.wordBoundaryAsciiBoundaryChars, "/")
        XCTAssertEqual(snapshot.rendering.themeName, "Runtime Theme")
        XCTAssertEqual(snapshot.language.commentConfigurations["rust"], .line("//"))
        XCTAssertEqual(snapshot.language.commentConfigurations["python"], .line("#"))
        XCTAssertEqual(snapshot.language.commentConfigurations["swift"], .lineAndBlock(";;", "#|", "|#"))
        XCTAssertTrue(snapshot.language.semanticHighlightingEnabled)
        XCTAssertFalse(snapshot.language.formatOnSaveEnabled)
        XCTAssertFalse(snapshot.language.formatOnTypeEnabled)
        XCTAssertEqual(snapshot.language.lspAutoRestart.enabled, true)
        XCTAssertEqual(snapshot.language.lspAutoRestart.maxAttempts, 4)
        XCTAssertEqual(snapshot.language.lspAutoRestart.baseDelaySeconds, 1.5)
        XCTAssertEqual(snapshot.language.lspAutoRestart.disabledServerKeys, ["workspace-lsp"])
        XCTAssertEqual(snapshot.language.lspAutoRestart.serverMaxAttempts, ["workspace-lsp": 2])
        XCTAssertEqual(snapshot.language.lspAutoRestart.serverBaseDelaySeconds, ["runtime-lsp": 0.5])
        XCTAssertEqual(snapshot.workspace.rootPath, "/workspace/root")
        XCTAssertEqual(snapshot.workspace.findInFilesDefaultScope, "workspace")
        XCTAssertEqual(snapshot.workspace.workspaceSearchIncludeGlobs, ["Sources/**/*.swift"])
        XCTAssertEqual(snapshot.workspace.workspaceSearchExcludeGlobs, ["Vendor/**"])
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

    func testSettingsResolutionAppliesMatchingScopedSettings() {
        let base = baseSnapshot()
        let user = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 14),
            scopedSettings: [
                AttoScopedConfigurationSettings(
                    selector: "source.swift",
                    editor: AttoEditorPreferenceSettings(
                        fontSizePoints: 15,
                        findCaseSensitive: false
                    ),
                    language: AttoLanguagePreferenceSettings(formatOnSaveEnabled: false)
                ),
            ]
        )
        let workspace = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 16),
            scopedSettings: [
                AttoScopedConfigurationSettings(
                    selectors: ["*.swift"],
                    editor: AttoEditorPreferenceSettings(
                        fontSizePoints: 17,
                        wrapMode: "none"
                    ),
                    rendering: AttoRenderingPreferenceSettings(themeName: "Workspace Swift")
                ),
            ]
        )
        let runtime = AttoConfigurationSettings(
            scopedSettings: [
                AttoScopedConfigurationSettings(
                    selectors: ["language:swift"],
                    editor: AttoEditorPreferenceSettings(fontSizePoints: 18),
                    language: AttoLanguagePreferenceSettings(formatOnTypeEnabled: false)
                ),
            ]
        )

        let resolution = base.resolvingSettings(
            user: user,
            workspace: workspace,
            runtime: runtime,
            documentContext: AttoConfigurationDocumentContext(
                fileURL: URL(fileURLWithPath: "/tmp/Sources/AppDelegate.swift"),
                languageId: "swift"
            )
        )
        let snapshot = resolution.snapshot

        XCTAssertEqual(resolution.appliedScopes, [
            .user,
            .userScoped,
            .workspace,
            .workspaceScoped,
            .runtimeScoped,
        ])
        XCTAssertEqual(snapshot.editor.fontSizePoints, 18)
        XCTAssertEqual(snapshot.editor.wrapMode, "none")
        XCTAssertFalse(snapshot.editor.findCaseSensitive)
        XCTAssertEqual(snapshot.rendering.themeName, "Workspace Swift")
        XCTAssertFalse(snapshot.language.formatOnSaveEnabled)
        XCTAssertFalse(snapshot.language.formatOnTypeEnabled)
    }

    func testSettingsResolutionSkipsNonMatchingScopedSettings() {
        let base = baseSnapshot()
        let user = AttoConfigurationSettings(
            scopedSettings: [
                AttoScopedConfigurationSettings(
                    selectors: ["source.swift", "*.swift"],
                    editor: AttoEditorPreferenceSettings(fontSizePoints: 20)
                ),
            ]
        )

        let resolution = base.resolvingSettings(
            user: user,
            documentContext: AttoConfigurationDocumentContext(
                fileURL: URL(fileURLWithPath: "/tmp/README.md"),
                languageId: "markdown"
            )
        )

        XCTAssertEqual(resolution.appliedScopes, [])
        XCTAssertEqual(resolution.snapshot.editor.fontSizePoints, 13)
    }

    func testScopedSettingsMatchGlobFileExtensionAndBareLanguageSelectors() {
        let swiftContext = AttoConfigurationDocumentContext(
            fileURL: URL(fileURLWithPath: "/tmp/project/Sources/View.SWIFT"),
            languageId: "swift"
        )
        let markdownContext = AttoConfigurationDocumentContext(
            fileURL: URL(fileURLWithPath: "/tmp/project/Docs/README.md"),
            languageId: "markdown"
        )

        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["path:**/sources/*.swift"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["ext:swift"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["swift"]).matches(swiftContext))
        XCTAssertTrue(AttoScopedConfigurationSettings(selectors: ["filename:readme.md"]).matches(markdownContext))
        XCTAssertFalse(AttoScopedConfigurationSettings(selectors: ["source.swift"]).matches(markdownContext))
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

    func testSettingsStoreBacksUpCorruptSettingsWithoutOverwritingExistingBackup() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoConfigurationSettingsCorruptBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userSettingsURL = tempDir.appendingPathComponent("settings.json")
        let existingBackupURL = userSettingsURL.appendingPathExtension("invalid")
        let numberedBackupURL = URL(fileURLWithPath: "\(existingBackupURL.path).1", isDirectory: false)
        try "previous backup".write(to: existingBackupURL, atomically: true, encoding: .utf8)
        try "{ invalid json".write(to: userSettingsURL, atomically: true, encoding: .utf8)

        let store = AttoConfigurationSettingsStore(userSettingsURL: userSettingsURL)
        XCTAssertNil(try store.loadUserSettings())

        XCTAssertFalse(FileManager.default.fileExists(atPath: userSettingsURL.path))
        XCTAssertEqual(try String(contentsOf: existingBackupURL, encoding: .utf8), "previous backup")
        XCTAssertEqual(try String(contentsOf: numberedBackupURL, encoding: .utf8), "{ invalid json")

        let replacement = AttoConfigurationSettings(
            editor: AttoEditorPreferenceSettings(fontSizePoints: 21)
        )
        try store.saveUserSettings(replacement)
        XCTAssertEqual(try store.loadUserSettings(), replacement)
    }

    func testSettingsStoreMigratesLegacySettingsAndPreservesOriginalBackup() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoConfigurationSettingsMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userSettingsURL = tempDir.appendingPathComponent("settings.json")
        let existingBackupURL = userSettingsURL
            .appendingPathExtension("v0")
            .appendingPathExtension("backup")
        let numberedBackupURL = URL(fileURLWithPath: "\(existingBackupURL.path).1", isDirectory: false)
        try "previous migration backup".write(to: existingBackupURL, atomically: true, encoding: .utf8)

        let legacyJSON = """
        {
          "editor": {
            "font_size_points": 18,
            "wrap_mode": "none"
          },
          "rendering": {
            "theme_name": "Atto Light"
          }
        }
        """
        try legacyJSON.write(to: userSettingsURL, atomically: true, encoding: .utf8)

        let store = AttoConfigurationSettingsStore(userSettingsURL: userSettingsURL)
        let settings = try XCTUnwrap(try store.loadUserSettings())

        XCTAssertEqual(settings.schemaVersion, AttoConfigurationSettings.currentSchemaVersion)
        XCTAssertEqual(settings.editor?.fontSizePoints, 18)
        XCTAssertEqual(settings.editor?.wrapMode, "none")
        XCTAssertEqual(settings.rendering?.themeName, "Atto Light")
        XCTAssertEqual(try String(contentsOf: existingBackupURL, encoding: .utf8), "previous migration backup")
        XCTAssertEqual(try String(contentsOf: numberedBackupURL, encoding: .utf8), legacyJSON)

        let migratedData = try Data(contentsOf: userSettingsURL)
        let migratedOnDisk = try JSONDecoder().decode(AttoConfigurationSettings.self, from: migratedData)
        XCTAssertEqual(migratedOnDisk.schemaVersion, AttoConfigurationSettings.currentSchemaVersion)
        XCTAssertEqual(migratedOnDisk.editor?.fontSizePoints, 18)
    }

    func testSettingsDecodeIgnoresUnknownFutureFields() throws {
        let json = """
        {
          "schema_version": 2,
          "future_top_level": true,
          "editor": {
            "font_size_points": 17,
            "find_case_sensitive": false,
            "find_whole_word": true,
            "find_regex": true,
            "word_boundary_ascii_boundary_chars": ".",
            "future_editor_field": "ignored"
          },
          "workspace": {
            "find_in_files_default_scope": "workspace",
            "workspace_search_include_globs": ["Sources/**/*.swift"],
            "workspace_search_exclude_globs": ["**/*.generated.swift"],
            "future_workspace_field": "ignored"
          },
          "scoped_settings": [
            {
              "selector": "source.swift",
              "selectors": ["*.swift"],
              "editor": {
                "font_size_points": 19,
                "future_scoped_editor_field": "ignored"
              },
              "language": {
                "format_on_save_enabled": false
              },
              "future_scoped_field": "ignored"
            }
          ],
          "language": {
            "semantic_highlighting_enabled": false,
            "format_on_save_enabled": true,
            "format_on_type_enabled": false,
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
        XCTAssertEqual(settings.editor?.findCaseSensitive, false)
        XCTAssertEqual(settings.editor?.findWholeWord, true)
        XCTAssertEqual(settings.editor?.findRegex, true)
        XCTAssertEqual(settings.editor?.wordBoundaryAsciiBoundaryChars, ".")
        XCTAssertEqual(settings.workspace?.findInFilesDefaultScope, "workspace")
        XCTAssertEqual(settings.workspace?.workspaceSearchIncludeGlobs, ["Sources/**/*.swift"])
        XCTAssertEqual(settings.workspace?.workspaceSearchExcludeGlobs, ["**/*.generated.swift"])
        XCTAssertEqual(settings.language?.semanticHighlightingEnabled, false)
        XCTAssertEqual(settings.language?.formatOnSaveEnabled, true)
        XCTAssertEqual(settings.language?.formatOnTypeEnabled, false)
        XCTAssertEqual(settings.language?.commentConfigurations?["swift"], .line("//"))
        XCTAssertEqual(settings.language?.lspAutoRestart?.maxAttempts, 5)
        XCTAssertEqual(settings.scopedSettings.count, 1)
        XCTAssertEqual(settings.scopedSettings.first?.selectors, ["source.swift", "*.swift"])
        XCTAssertEqual(settings.scopedSettings.first?.editor?.fontSizePoints, 19)
        XCTAssertEqual(settings.scopedSettings.first?.language?.formatOnSaveEnabled, false)
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
