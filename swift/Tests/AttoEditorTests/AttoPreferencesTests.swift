import Foundation
@testable import AttoEditor
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
}

