import Foundation
@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoPreferencesTests: XCTestCase {
    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "atto_preferences_tests_\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults(suiteName:)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return (defaults: defaults, suiteName: suiteName)
    }

    func testFontFacesMultilineTextForUIUsesSystemDefaultListWhenUnset() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedFontFaces)
        XCTAssertEqual(prefs.effectiveFontFaces, [])

        let expected: [String] = [
            "Menlo",
            "SF Mono",
            "Monaco",
            "Courier New",
            "Courier",
            "PingFang SC",
            "Hiragino Sans GB",
            "Heiti SC",
            "Apple Color Emoji",
        ]

        let got = AttoPreferences.parseMultilineFontFaces(prefs.fontFacesMultilineTextForUI())
        XCTAssertEqual(got, expected)
    }

    func testFontFacesMultilineTextForUIUsesStoredFacesWhenPresent() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        prefs.setFontFaces(["Fira Code", "PingFang SC"])

        let got = AttoPreferences.parseMultilineFontFaces(prefs.fontFacesMultilineTextForUI())
        XCTAssertEqual(got, ["Fira Code", "PingFang SC"])
    }

    func testFontFacesMultilineTextForUIShowsSystemDefaultsAfterReset() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        prefs.setFontFaces(["Fira Code"])
        prefs.setFontFaces([])

        let expected: [String] = [
            "Menlo",
            "SF Mono",
            "Monaco",
            "Courier New",
            "Courier",
            "PingFang SC",
            "Hiragino Sans GB",
            "Heiti SC",
            "Apple Color Emoji",
        ]

        let got = AttoPreferences.parseMultilineFontFaces(prefs.fontFacesMultilineTextForUI())
        XCTAssertEqual(got, expected)
    }

    func testEffectiveThemeNameUsesDefaultWhenUnset() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedThemeName)
        XCTAssertEqual(prefs.effectiveThemeName, AttoThemeManager.defaultThemeName)
    }

    func testEffectiveThemeNameUsesEnvWhenUnset() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_THEME": "Atto Light"])
        XCTAssertNil(prefs.storedThemeName)
        XCTAssertEqual(prefs.effectiveThemeName, "Atto Light")
    }

    func testEffectiveThemeNameUsesStoredValueWhenPresent() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_THEME": "Atto Light"])
        prefs.setThemeName("Atto Dark")

        XCTAssertEqual(prefs.storedThemeName, "Atto Dark")
        XCTAssertEqual(prefs.effectiveThemeName, "Atto Dark")
    }

    func testSetThemeNameNilClearsStoredValue() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        prefs.setThemeName("Atto Light")
        XCTAssertEqual(prefs.storedThemeName, "Atto Light")

        prefs.setThemeName(nil)
        XCTAssertNil(prefs.storedThemeName)
        XCTAssertEqual(prefs.effectiveThemeName, AttoThemeManager.defaultThemeName)
    }

    func testAutoPairsDefaultEnvAndStoredPreference() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedAutoPairsEnabled)
        XCTAssertTrue(prefs.effectiveAutoPairsEnabled)

        prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_AUTO_PAIRS": "0"])
        XCTAssertFalse(prefs.effectiveAutoPairsEnabled)

        prefs.setAutoPairsEnabled(true)
        XCTAssertEqual(prefs.storedAutoPairsEnabled, true)
        XCTAssertTrue(prefs.effectiveAutoPairsEnabled)

        prefs.clearAutoPairsEnabled()
        XCTAssertNil(prefs.storedAutoPairsEnabled)
        XCTAssertFalse(prefs.effectiveAutoPairsEnabled)
    }

    func testSemanticHighlightingDefaultEnvAndStoredPreference() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedSemanticHighlightingEnabled)
        XCTAssertTrue(prefs.effectiveSemanticHighlightingEnabled)

        prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_SEMANTIC_HIGHLIGHTING": "0"])
        XCTAssertFalse(prefs.effectiveSemanticHighlightingEnabled)

        prefs.setSemanticHighlightingEnabled(true)
        XCTAssertEqual(prefs.storedSemanticHighlightingEnabled, true)
        XCTAssertTrue(prefs.effectiveSemanticHighlightingEnabled)

        prefs.setSemanticHighlightingEnabled(nil)
        XCTAssertNil(prefs.storedSemanticHighlightingEnabled)
        XCTAssertFalse(prefs.effectiveSemanticHighlightingEnabled)
    }

    func testFormatOnSaveDefaultEnvAndStoredPreference() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedFormatOnSaveEnabled)
        XCTAssertFalse(prefs.effectiveFormatOnSaveEnabled)

        prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_FORMAT_ON_SAVE": "1"])
        XCTAssertTrue(prefs.effectiveFormatOnSaveEnabled)

        prefs.setFormatOnSaveEnabled(false)
        XCTAssertEqual(prefs.storedFormatOnSaveEnabled, false)
        XCTAssertFalse(prefs.effectiveFormatOnSaveEnabled)

        prefs.setFormatOnSaveEnabled(nil)
        XCTAssertNil(prefs.storedFormatOnSaveEnabled)
        XCTAssertTrue(prefs.effectiveFormatOnSaveEnabled)
    }

    func testFormatOnTypeDefaultEnvAndStoredPreference() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedFormatOnTypeEnabled)
        XCTAssertTrue(prefs.effectiveFormatOnTypeEnabled)

        prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_FORMAT_ON_TYPE": "0"])
        XCTAssertFalse(prefs.effectiveFormatOnTypeEnabled)

        prefs.setFormatOnTypeEnabled(true)
        XCTAssertEqual(prefs.storedFormatOnTypeEnabled, true)
        XCTAssertTrue(prefs.effectiveFormatOnTypeEnabled)

        prefs.setFormatOnTypeEnabled(nil)
        XCTAssertNil(prefs.storedFormatOnTypeEnabled)
        XCTAssertFalse(prefs.effectiveFormatOnTypeEnabled)
    }

    func testLspAutoRestartDefaultsEnvStoredAndClamping() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedLspAutoRestartEnabled)
        XCTAssertNil(prefs.storedLspAutoRestartMaxAttempts)
        XCTAssertNil(prefs.storedLspAutoRestartBaseDelaySeconds)
        XCTAssertTrue(prefs.effectiveLspAutoRestartEnabled)
        XCTAssertEqual(prefs.effectiveLspAutoRestartMaxAttempts, 3)
        XCTAssertEqual(prefs.effectiveLspAutoRestartBaseDelaySeconds, 5.0)

        prefs = AttoPreferences(defaults: defaults, env: [
            "ATTO_EDITOR_LSP_AUTO_RESTART": "0",
            "ATTO_EDITOR_LSP_AUTO_RESTART_MAX_ATTEMPTS": "7",
            "ATTO_EDITOR_LSP_AUTO_RESTART_BASE_DELAY_SECONDS": "2.5",
        ])
        XCTAssertFalse(prefs.effectiveLspAutoRestartEnabled)
        XCTAssertEqual(prefs.effectiveLspAutoRestartMaxAttempts, 7)
        XCTAssertEqual(prefs.effectiveLspAutoRestartBaseDelaySeconds, 2.5)

        prefs.setLspAutoRestartEnabled(true)
        prefs.setLspAutoRestartMaxAttempts(25)
        prefs.setLspAutoRestartBaseDelaySeconds(-1)

        XCTAssertEqual(prefs.storedLspAutoRestartEnabled, true)
        XCTAssertEqual(prefs.storedLspAutoRestartMaxAttempts, 10)
        XCTAssertEqual(prefs.storedLspAutoRestartBaseDelaySeconds, 0.0)
        XCTAssertTrue(prefs.effectiveLspAutoRestartEnabled)
        XCTAssertEqual(prefs.effectiveLspAutoRestartMaxAttempts, 10)
        XCTAssertEqual(prefs.effectiveLspAutoRestartBaseDelaySeconds, 0.0)
    }

    func testLspAutoRestartServerDisableListNormalizesAndToggles() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertEqual(prefs.storedLspAutoRestartDisabledServerKeys, [])
        XCTAssertEqual(
            AttoPreferences.lspAutoRestartServerKey(serverName: "  Fake-LSP  ", serverCommand: "/bin/fake-lsp"),
            "fake-lsp"
        )
        XCTAssertEqual(
            AttoPreferences.lspAutoRestartServerKey(serverName: nil, serverCommand: "  /BIN/Fake-LSP  "),
            "/bin/fake-lsp"
        )

        prefs.setLspAutoRestartDisabled(true, forServerName: " Fake-LSP ", serverCommand: nil)
        XCTAssertTrue(prefs.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertEqual(prefs.storedLspAutoRestartDisabledServerKeys, ["fake-lsp"])

        prefs.setLspAutoRestartDisabled(true, forServerName: nil, serverCommand: " /bin/Other-LSP ")
        XCTAssertEqual(prefs.storedLspAutoRestartDisabledServerKeys, ["/bin/other-lsp", "fake-lsp"])

        prefs.setLspAutoRestartDisabled(false, forServerName: "FAKE-LSP", serverCommand: nil)
        XCTAssertFalse(prefs.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertEqual(prefs.storedLspAutoRestartDisabledServerKeys, ["/bin/other-lsp"])
    }

    func testLspAutoRestartServerPolicyOverridesNormalizeAndClamp() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [
            "ATTO_EDITOR_LSP_AUTO_RESTART_MAX_ATTEMPTS": "4",
            "ATTO_EDITOR_LSP_AUTO_RESTART_BASE_DELAY_SECONDS": "9.5",
        ])
        XCTAssertEqual(prefs.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 4)
        XCTAssertEqual(prefs.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 9.5)

        prefs.setLspAutoRestartMaxAttempts(25, forServerName: " Fake-LSP ", serverCommand: nil)
        prefs.setLspAutoRestartBaseDelaySeconds(-5, forServerName: nil, serverCommand: " /BIN/Other-LSP ")

        XCTAssertTrue(prefs.hasLspAutoRestartPolicyOverrideForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertTrue(prefs.hasLspAutoRestartPolicyOverrideForServer(serverName: nil, serverCommand: "/bin/other-lsp"))
        XCTAssertEqual(prefs.storedLspAutoRestartServerMaxAttempts, ["fake-lsp": 10])
        XCTAssertEqual(prefs.storedLspAutoRestartServerBaseDelaySeconds, ["/bin/other-lsp": 0.0])
        XCTAssertEqual(prefs.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 10)
        XCTAssertEqual(
            prefs.effectiveLspAutoRestartBaseDelaySeconds(serverName: nil, serverCommand: "/bin/other-lsp"),
            0.0
        )
        XCTAssertEqual(prefs.effectiveLspAutoRestartMaxAttempts(serverName: "other", serverCommand: nil), 4)
        XCTAssertEqual(prefs.effectiveLspAutoRestartBaseDelaySeconds(serverName: "other", serverCommand: nil), 9.5)

        prefs.setLspAutoRestartDisabled(true, forServerName: "fake-lsp", serverCommand: nil)
        prefs.setLspAutoRestartBaseDelaySeconds(3, forServerName: "fake-lsp", serverCommand: nil)
        prefs.resetLspAutoRestartPolicy(forServerName: "FAKE-LSP", serverCommand: nil)
        XCTAssertFalse(prefs.hasLspAutoRestartPolicyOverrideForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertFalse(prefs.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertEqual(prefs.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 4)
        XCTAssertEqual(prefs.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 9.5)
        XCTAssertEqual(prefs.storedLspAutoRestartServerMaxAttempts, [:])
        XCTAssertEqual(prefs.storedLspAutoRestartServerBaseDelaySeconds, ["/bin/other-lsp": 0.0])
    }

    func testWrapModeDefaultEnvAndStoredPreference() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedWrapMode)
        XCTAssertEqual(prefs.effectiveWrapMode, .char)

        prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_WRAP_MODE": "word"])
        XCTAssertEqual(prefs.effectiveWrapMode, .word)

        prefs.setWrapMode(EcuWrapMode.none)
        XCTAssertEqual(prefs.storedWrapMode, EcuWrapMode.none)
        XCTAssertEqual(prefs.effectiveWrapMode, EcuWrapMode.none)

        prefs.setWrapMode(nil)
        XCTAssertNil(prefs.storedWrapMode)
        XCTAssertEqual(prefs.effectiveWrapMode, .word)
    }

    func testWrapIndentDefaultEnvAndStoredPreference() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedWrapIndent)
        XCTAssertEqual(prefs.effectiveWrapIndent, EcuWrapIndent.none)

        prefs = AttoPreferences(defaults: defaults, env: ["ATTO_EDITOR_WRAP_INDENT": "same_as_line_indent"])
        XCTAssertEqual(prefs.effectiveWrapIndent, .sameAsLineIndent)

        prefs.setWrapIndent(.fixedCells(4))
        XCTAssertEqual(prefs.storedWrapIndent, .fixedCells(4))
        XCTAssertEqual(prefs.effectiveWrapIndent, .fixedCells(4))
        XCTAssertEqual(AttoPreferences.wrapIndentStorageString(.fixedCells(4)), "fixed_cells:4")
        XCTAssertEqual(AttoPreferences.parseWrapIndentString("fixed:2"), .fixedCells(2))

        prefs.setWrapIndent(nil)
        XCTAssertNil(prefs.storedWrapIndent)
        XCTAssertEqual(prefs.effectiveWrapIndent, .sameAsLineIndent)
    }

    func testCommentConfigurationOverridesNormalizeStoreAndClear() {
        let (defaults, _) = makeIsolatedDefaults()

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertEqual(prefs.storedCommentConfigurations, [:])

        let config = AttoCommentConfiguration.lineAndBlock(";;", "#|", "|#")
        prefs.setCommentConfiguration(config, forLanguageKey: "  Lisp  ")

        XCTAssertEqual(prefs.storedCommentConfigurations, ["lisp": config])
        XCTAssertEqual(prefs.commentConfigurationOverride(forLanguageKey: "LISP"), config)

        prefs.setCommentConfiguration(nil, forLanguageKey: "lisp")
        XCTAssertEqual(prefs.storedCommentConfigurations, [:])
        XCTAssertNil(prefs.commentConfigurationOverride(forLanguageKey: "lisp"))
    }

    func testFindDefaultsEnvStoredAndScopeNormalization() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedFindCaseSensitive)
        XCTAssertNil(prefs.storedFindWholeWord)
        XCTAssertNil(prefs.storedFindRegex)
        XCTAssertNil(prefs.storedFindInFilesDefaultScope)
        XCTAssertTrue(prefs.effectiveFindCaseSensitive)
        XCTAssertFalse(prefs.effectiveFindWholeWord)
        XCTAssertFalse(prefs.effectiveFindRegex)
        XCTAssertEqual(prefs.effectiveFindInFilesDefaultScope, "opened_files")

        prefs = AttoPreferences(defaults: defaults, env: [
            "ATTO_EDITOR_FIND_CASE_SENSITIVE": "0",
            "ATTO_EDITOR_FIND_WHOLE_WORD": "1",
            "ATTO_EDITOR_FIND_REGEX": "true",
            "ATTO_EDITOR_FIND_IN_FILES_DEFAULT_SCOPE": "folder",
        ])
        XCTAssertFalse(prefs.effectiveFindCaseSensitive)
        XCTAssertTrue(prefs.effectiveFindWholeWord)
        XCTAssertTrue(prefs.effectiveFindRegex)
        XCTAssertEqual(prefs.effectiveFindInFilesDefaultScope, "workspace")

        prefs.setFindCaseSensitive(true)
        prefs.setFindWholeWord(false)
        prefs.setFindRegex(false)
        prefs.setFindInFilesDefaultScope("open_tabs")

        XCTAssertEqual(prefs.storedFindCaseSensitive, true)
        XCTAssertEqual(prefs.storedFindWholeWord, false)
        XCTAssertEqual(prefs.storedFindRegex, false)
        XCTAssertEqual(prefs.storedFindInFilesDefaultScope, "opened_files")
        XCTAssertTrue(prefs.effectiveFindCaseSensitive)
        XCTAssertFalse(prefs.effectiveFindWholeWord)
        XCTAssertFalse(prefs.effectiveFindRegex)
        XCTAssertEqual(prefs.effectiveFindInFilesDefaultScope, "opened_files")

        prefs.setFindInFilesDefaultScope(nil)
        XCTAssertNil(prefs.storedFindInFilesDefaultScope)
        XCTAssertEqual(prefs.effectiveFindInFilesDefaultScope, "workspace")
    }

    func testWorkspaceSearchGlobDefaultsEnvStoredAndNormalization() {
        let (defaults, _) = makeIsolatedDefaults()

        var prefs = AttoPreferences(defaults: defaults, env: [:])
        XCTAssertNil(prefs.storedWorkspaceSearchIncludeGlobs)
        XCTAssertNil(prefs.storedWorkspaceSearchExcludeGlobs)
        XCTAssertEqual(prefs.effectiveWorkspaceSearchIncludeGlobs, [])
        XCTAssertEqual(prefs.effectiveWorkspaceSearchExcludeGlobs, [])
        XCTAssertEqual(prefs.workspaceSearchIncludeGlobsTextForUI(), "")
        XCTAssertEqual(prefs.workspaceSearchExcludeGlobsTextForUI(), "")

        prefs = AttoPreferences(defaults: defaults, env: [
            "ATTO_EDITOR_WORKSPACE_SEARCH_INCLUDE_GLOBS": " Sources/**/*.swift, README.md\n./Docs//**\n",
            "ATTO_EDITOR_WORKSPACE_SEARCH_EXCLUDE_GLOBS": " Vendor/\n**/*.generated.swift, Vendor/** ",
        ])
        XCTAssertEqual(prefs.effectiveWorkspaceSearchIncludeGlobs, [
            "Sources/**/*.swift",
            "README.md",
            "Docs/**",
        ])
        XCTAssertEqual(prefs.effectiveWorkspaceSearchExcludeGlobs, [
            "Vendor/**",
            "**/*.generated.swift",
        ])
        XCTAssertEqual(AttoPreferences.parseWorkspaceSearchGlobsText("Sources/**,README.md\nDocs/**"), [
            "Sources/**",
            "README.md",
            "Docs/**",
        ])

        prefs.setWorkspaceSearchIncludeGlobs([
            " ./Sources/**/*.swift ",
            "README.md",
            "Sources/**/*.swift",
            "",
        ])
        prefs.setWorkspaceSearchExcludeGlobs([
            "Vendor\\",
            "Vendor/",
            "**/*.generated.swift",
            "**/*.generated.swift",
        ])

        XCTAssertEqual(prefs.storedWorkspaceSearchIncludeGlobs, [
            "Sources/**/*.swift",
            "README.md",
        ])
        XCTAssertEqual(prefs.storedWorkspaceSearchExcludeGlobs, [
            "Vendor/**",
            "**/*.generated.swift",
        ])
        XCTAssertEqual(prefs.effectiveWorkspaceSearchIncludeGlobs, [
            "Sources/**/*.swift",
            "README.md",
        ])
        XCTAssertEqual(prefs.effectiveWorkspaceSearchExcludeGlobs, [
            "Vendor/**",
            "**/*.generated.swift",
        ])
        XCTAssertEqual(prefs.workspaceSearchIncludeGlobsTextForUI(), "Sources/**/*.swift\nREADME.md")
        XCTAssertEqual(prefs.workspaceSearchExcludeGlobsTextForUI(), "Vendor/**\n**/*.generated.swift")

        prefs.setWorkspaceSearchIncludeGlobs([])
        prefs.setWorkspaceSearchExcludeGlobs([])
        XCTAssertEqual(prefs.storedWorkspaceSearchIncludeGlobs, [])
        XCTAssertEqual(prefs.storedWorkspaceSearchExcludeGlobs, [])
        XCTAssertEqual(prefs.effectiveWorkspaceSearchIncludeGlobs, [])
        XCTAssertEqual(prefs.effectiveWorkspaceSearchExcludeGlobs, [])
    }

    func testEffectiveConfigurationSnapshotRoundTripsCurrentPreferences() throws {
        let (defaults, _) = makeIsolatedDefaults()
        let prefs = AttoPreferences(defaults: defaults, env: [
            "ATTO_EDITOR_THEME": "Atto Light",
            "ATTO_EDITOR_WRAP_MODE": "word",
            "ATTO_EDITOR_LSP_AUTO_RESTART_MAX_ATTEMPTS": "4",
            "ATTO_EDITOR_LSP_AUTO_RESTART_BASE_DELAY_SECONDS": "8.5",
        ])
        prefs.setFontFaces([" Fira Code ", "PingFang SC", "fira code"])
        prefs.setFontSizePoints(16.5)
        prefs.setLigaturesEnabled(true)
        prefs.setAutoPairsEnabled(false)
        prefs.setWrapIndent(.fixedCells(3))
        prefs.setFindCaseSensitive(false)
        prefs.setFindWholeWord(true)
        prefs.setFindRegex(true)
        prefs.setWordBoundaryAsciiBoundaryChars(" . ")
        prefs.setFindInFilesDefaultScope("workspace")
        prefs.setWorkspaceSearchIncludeGlobs(["Sources/**/*.swift", "README.md"])
        prefs.setWorkspaceSearchExcludeGlobs(["**/*.generated.swift", "Vendor/"])
        prefs.setCommentConfiguration(.lineAndBlock("//", "/*", "*/"), forLanguageKey: "  Swift  ")
        prefs.setSemanticHighlightingEnabled(false)
        prefs.setFormatOnSaveEnabled(true)
        prefs.setFormatOnTypeEnabled(false)
        prefs.setLspAutoRestartDisabled(true, forServerName: " Swift-LSP ", serverCommand: nil)
        prefs.setLspAutoRestartMaxAttempts(7, forServerName: "Swift-LSP", serverCommand: nil)

        let workspaceRootURL = URL(fileURLWithPath: "/tmp/Atto Project", isDirectory: true)
        let snapshot = prefs.effectiveConfigurationSnapshot(workspaceRootURL: workspaceRootURL)

        XCTAssertEqual(snapshot.schemaVersion, AttoConfigurationSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.editor.fontFamilies, ["Fira Code", "PingFang SC"])
        XCTAssertEqual(snapshot.editor.fontSizePoints, 16.5)
        XCTAssertFalse(snapshot.editor.autoPairsEnabled)
        XCTAssertEqual(snapshot.editor.wrapMode, "word")
        XCTAssertEqual(snapshot.editor.wrapIndent, "fixed_cells:3")
        XCTAssertFalse(snapshot.editor.findCaseSensitive)
        XCTAssertTrue(snapshot.editor.findWholeWord)
        XCTAssertTrue(snapshot.editor.findRegex)
        XCTAssertEqual(snapshot.editor.wordBoundaryAsciiBoundaryChars, ".")
        XCTAssertEqual(snapshot.rendering.themeName, "Atto Light")
        XCTAssertTrue(snapshot.rendering.fontLigaturesEnabled)
        XCTAssertEqual(
            snapshot.language.commentConfigurations,
            ["swift": AttoCommentConfiguration.lineAndBlock("//", "/*", "*/")]
        )
        XCTAssertFalse(snapshot.language.semanticHighlightingEnabled)
        XCTAssertTrue(snapshot.language.formatOnSaveEnabled)
        XCTAssertFalse(snapshot.language.formatOnTypeEnabled)
        XCTAssertEqual(snapshot.language.lspAutoRestart.enabled, true)
        XCTAssertEqual(snapshot.language.lspAutoRestart.maxAttempts, 4)
        XCTAssertEqual(snapshot.language.lspAutoRestart.baseDelaySeconds, 8.5)
        XCTAssertEqual(snapshot.language.lspAutoRestart.disabledServerKeys, ["swift-lsp"])
        XCTAssertEqual(snapshot.language.lspAutoRestart.serverMaxAttempts, ["swift-lsp": 7])
        XCTAssertEqual(snapshot.workspace.rootURL, workspaceRootURL.absoluteString)
        XCTAssertEqual(snapshot.workspace.rootPath, workspaceRootURL.path)
        XCTAssertEqual(snapshot.workspace.findInFilesDefaultScope, "workspace")
        XCTAssertEqual(snapshot.workspace.workspaceSearchIncludeGlobs, ["Sources/**/*.swift", "README.md"])
        XCTAssertEqual(snapshot.workspace.workspaceSearchExcludeGlobs, ["**/*.generated.swift", "Vendor/**"])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""schema_version":1"#))
        XCTAssertTrue(json.contains(#""font_families":["Fira Code","PingFang SC"]"#))
        XCTAssertTrue(json.contains(#""block_start""#))
        XCTAssertTrue(json.contains(#""semantic_highlighting_enabled":false"#))
        XCTAssertTrue(json.contains(#""format_on_save_enabled":true"#))
        XCTAssertTrue(json.contains(#""format_on_type_enabled":false"#))

        let decoded = try JSONDecoder().decode(AttoConfigurationSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testConfigurationSnapshotIgnoresUnknownFutureFields() throws {
        let json = """
        {
          "schema_version": 99,
          "future_top_level": true,
          "editor": {
            "font_families": ["Menlo"],
            "font_size_points": 13,
            "auto_pairs_enabled": true,
            "wrap_mode": "char",
            "wrap_indent": "none",
            "future_editor_field": "ignored"
          },
          "rendering": {
            "theme_name": "Atto Dark",
            "font_ligatures_enabled": false,
            "future_rendering_field": "ignored"
          },
          "language": {
            "comment_configurations": {
              "swift": {
                "line": "//",
                "block_start": "/*",
                "block_end": "*/",
                "future_comment_field": "ignored"
              }
            },
            "lsp_auto_restart": {
              "enabled": true,
              "max_attempts": 3,
              "base_delay_seconds": 5,
              "disabled_server_keys": [],
              "server_max_attempts": {},
              "server_base_delay_seconds": {},
              "future_lsp_policy_field": "ignored"
            },
            "future_language_field": "ignored"
          },
          "workspace": {
            "root_url": "file:///tmp/project/",
            "root_path": "/tmp/project",
            "future_workspace_field": "ignored"
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(AttoConfigurationSnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 99)
        XCTAssertEqual(snapshot.editor.fontFamilies, ["Menlo"])
        XCTAssertEqual(snapshot.rendering.themeName, "Atto Dark")
        XCTAssertEqual(
            snapshot.language.commentConfigurations["swift"],
            AttoCommentConfiguration.lineAndBlock("//", "/*", "*/")
        )
        XCTAssertTrue(snapshot.language.semanticHighlightingEnabled)
        XCTAssertFalse(snapshot.language.formatOnSaveEnabled)
        XCTAssertTrue(snapshot.language.formatOnTypeEnabled)
        XCTAssertEqual(snapshot.workspace.rootPath, "/tmp/project")
        XCTAssertEqual(snapshot.workspace.findInFilesDefaultScope, "opened_files")
        XCTAssertEqual(snapshot.workspace.workspaceSearchIncludeGlobs, [])
        XCTAssertEqual(snapshot.workspace.workspaceSearchExcludeGlobs, [])
    }
}
