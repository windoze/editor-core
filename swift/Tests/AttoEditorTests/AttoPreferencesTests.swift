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
}
