import EditorCoreUI
import EditorCoreUIFFI
import Foundation
@testable import AttoEditor
import XCTest

final class AttoThemeManagerTests: XCTestCase {
    func testBuiltinThemesAreDiscoverableViaBundleModule() {
        let urls = AttoThemeManager.builtinThemeURLs()
        XCTAssertTrue(urls.isEmpty == false, "Expected AttoEditor builtin theme resources to be present")
    }

    func testLoadRegistryIncludesBuiltinAttoDarkTheme() {
        let registry = AttoThemeManager.loadRegistry()
        let theme = registry.theme(named: "Atto Dark")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.name, "Atto Dark")
    }

    func testCustomThemeOverridesBuiltinThemeWithSameName() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("AttoThemeManagerTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let customURL = tempDir.appendingPathComponent("override.json", isDirectory: false)
        let obj: [String: Any] = [
            "schema_version": 1,
            "name": "Atto Dark",
            "appearance": "dark",
            "editor": [
                "background": "#000102FF",
                "foreground": "#D4D4D4FF",
                "selection_background": "#264F78FF",
                "caret": "#AEAFADFF",
            ],
            "chrome": [
                "gutter_background": "#252526FF",
                "gutter_foreground": "#858585FF",
                "gutter_separator": "#333333FF",
                "fold_marker_collapsed": "#6B6B6BFF",
                "fold_marker_expanded": "#A0A0A0FF",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: customURL)

        let registry = AttoThemeManager.loadRegistry(
            builtinThemeURLs: AttoThemeManager.builtinThemeURLs(),
            customThemeURLs: [customURL]
        )

        let resolved = registry.theme(named: "Atto Dark")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.skiaTheme.editorBackground, EcuRgba8(r: 0x00, g: 0x01, b: 0x02, a: 0xFF))
    }
}

