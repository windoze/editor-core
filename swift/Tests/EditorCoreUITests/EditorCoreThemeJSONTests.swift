import EditorCoreUI
import EditorCoreUIFFI
import Foundation
import XCTest

final class EditorCoreThemeJSONTests: XCTestCase {
    func testParseThemeJSONSupportsHexAndObjectColorsAndSelectors() throws {
        let obj: [String: Any] = [
            "schema_version": 1,
            "name": "Test Theme",
            "appearance": "dark",
            "editor": [
                "background": "#010203",
                "foreground": "#111213FF",
                "selection_background": ["r": 10, "g": 20, "b": 30, "a": 40],
                "caret": "#FF00FFFF",
            ],
            "chrome": [
                "gutter_background": "#0A0B0CFF",
                "gutter_foreground": "#0D0E0FFF",
                "gutter_separator": "#101112FF",
                "fold_marker_collapsed": "#131415FF",
                "fold_marker_expanded": "#161718FF",
                "minimap_background": NSNull(),
                "scrollbar_background": NSNull(),
                "scrollbar_foreground": NSNull(),
            ],
            "style_overrides": [
                [
                    "style": ["builtin": "inlayHint"],
                    "foreground": "#010203",
                    "italic": true,
                ],
                [
                    "style": ["reserved": "gutterForeground"],
                    "foreground": ["r": 1, "g": 2, "b": 3],
                ],
                [
                    "style": ["lsp_semantic": ["token_type": "keyword", "modifiers": ["readonly"]]],
                    "foreground": "#C586C0FF",
                    "underline": "single",
                ],
            ],
            "tree_sitter_capture_overrides": [
                [
                    "capture": "comment",
                    "foreground": "#00FF00FF",
                    "italic": true,
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        let theme = try EditorCoreThemeLoader.parseThemeJSON(data)

        XCTAssertEqual(theme.schemaVersion, 1)
        XCTAssertEqual(theme.name, "Test Theme")
        XCTAssertEqual(theme.appearance, .dark)

        XCTAssertEqual(theme.skiaTheme.editorBackground, EcuRgba8(r: 0x01, g: 0x02, b: 0x03, a: 0xFF))
        XCTAssertEqual(theme.skiaTheme.selectionBackground, EcuRgba8(r: 10, g: 20, b: 30, a: 40))
        XCTAssertEqual(theme.skiaTheme.caret, EcuRgba8(r: 0xFF, g: 0x00, b: 0xFF, a: 0xFF))

        XCTAssertEqual(theme.skiaTheme.styleOverrides.count, 3)
        XCTAssertEqual(theme.skiaTheme.styleOverrides[0].styleId, EditorCoreSkiaBuiltinStyleId.inlayHint)
        XCTAssertEqual(theme.skiaTheme.styleOverrides[1].styleId, EditorCoreSkiaReservedStyleId.gutterForeground)

        let keywordReadonly = EditorCoreSkiaLspSemanticStyleId.styleId(
            tokenType: "keyword",
            modifierBits: EditorCoreSkiaLspSemanticStyleId.modifierBit(named: "readonly")
        )
        XCTAssertNotNil(keywordReadonly)
        XCTAssertEqual(theme.skiaTheme.styleOverrides[2].styleId, keywordReadonly ?? 0)

        XCTAssertEqual(theme.skiaTheme.treeSitterCaptureOverrides.count, 1)
        XCTAssertEqual(theme.skiaTheme.treeSitterCaptureOverrides[0].capture, "comment")
        XCTAssertEqual(theme.skiaTheme.treeSitterCaptureOverrides[0].spec.foreground, EcuRgba8(r: 0x00, g: 0xFF, b: 0x00, a: 0xFF))
        XCTAssertEqual(theme.skiaTheme.treeSitterCaptureOverrides[0].spec.italic, true)
    }

    func testParseThemeJSONSkipsInvalidOverrideEntries() throws {
        let obj: [String: Any] = [
            "schema_version": 1,
            "name": "Theme With Bad Overrides",
            "editor": [
                "background": "#000000FF",
                "foreground": "#FFFFFFFF",
                "selection_background": "#112233FF",
                "caret": "#FFFFFFFF",
            ],
            "chrome": [
                "gutter_background": "#000000FF",
                "gutter_foreground": "#777777FF",
                "gutter_separator": "#333333FF",
                "fold_marker_collapsed": "#555555FF",
                "fold_marker_expanded": "#666666FF",
            ],
            "style_overrides": [
                [
                    "style": ["builtin": "unknown_builtin"],
                    "foreground": "#FF0000FF",
                ],
                [
                    "style": ["style_id": "not-a-number"],
                    "foreground": "#00FF00FF",
                ],
                [
                    "style": ["builtin": "inlayHint"],
                    "foreground": "#0000FFFF",
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        let theme = try EditorCoreThemeLoader.parseThemeJSON(data)

        // The first two entries are skipped; the last one is valid.
        XCTAssertEqual(theme.skiaTheme.styleOverrides.count, 1)
        XCTAssertEqual(theme.skiaTheme.styleOverrides[0].styleId, EditorCoreSkiaBuiltinStyleId.inlayHint)
    }

    func testThemeRegistryCustomOverridesBuiltinByNameCaseInsensitive() {
        func makeSkiaTheme(background: EcuRgba8) -> EditorCoreSkiaTheme {
            EditorCoreSkiaTheme(
                editorBackground: background,
                editorForeground: EcuRgba8(r: 0, g: 0, b: 0, a: 255),
                selectionBackground: EcuRgba8(r: 0, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 0, a: 255),
                gutterBackground: EcuRgba8(r: 0, g: 0, b: 0, a: 255),
                gutterForeground: EcuRgba8(r: 0, g: 0, b: 0, a: 255),
                gutterSeparator: EcuRgba8(r: 0, g: 0, b: 0, a: 255),
                foldMarkerCollapsed: EcuRgba8(r: 0, g: 0, b: 0, a: 255),
                foldMarkerExpanded: EcuRgba8(r: 0, g: 0, b: 0, a: 255)
            )
        }

        let builtin = EditorCoreThemeDefinition(
            schemaVersion: 1,
            name: "Atto Dark",
            appearance: .dark,
            skiaTheme: makeSkiaTheme(background: EcuRgba8(r: 1, g: 2, b: 3, a: 255))
        )
        let custom = EditorCoreThemeDefinition(
            schemaVersion: 1,
            name: "atto dark",
            appearance: .dark,
            skiaTheme: makeSkiaTheme(background: EcuRgba8(r: 9, g: 8, b: 7, a: 255))
        )

        var registry = EditorCoreThemeRegistry()
        registry.register(.init(theme: builtin, source: .builtin, url: nil))
        registry.register(.init(theme: custom, source: .custom, url: nil))

        let resolved = registry.theme(named: "ATTO DARK")
        XCTAssertEqual(resolved?.skiaTheme.editorBackground, EcuRgba8(r: 9, g: 8, b: 7, a: 255))
    }
}
