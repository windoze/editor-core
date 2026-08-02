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
}
