import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testStyleColorsOverrideAffectsRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the styled cell so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 40, scale: 1)

        // 给中间字符（一个空格）加一个 style id，然后下发该 style 的背景色覆盖。
        try ui.addStyle(start: 1, end: 2, styleId: 42)
        try ui.setStyleColors([EcuStyleColors(styleId: 42, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Styled cell 对应 x in [10..20]，取中心像素。
        XCTAssertEqual(pixel(rgba, widthPx: 80, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testRenderDrawsSomeTextPixels() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "M", viewportWidthCells: 80)

        // Make caret/selection invisible so only glyph pixels can differ from background.
        let bg = EcuRgba8(r: 10, g: 20, b: 30, a: 255)
        try ui.setTheme(
            EcuTheme(
                background: bg,
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: bg,
                caret: bg
            )
        )
        try ui.setRenderMetrics(fontSize: 20, lineHeightPx: 40, cellWidthPx: 20, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 40, scale: 1)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        let bgPx: [UInt8] = [bg.r, bg.g, bg.b, bg.a]
        var hasNonBackground = false
        for i in stride(from: 0, to: rgba.count, by: 4) {
            if Array(rgba[i..<min(i + 4, rgba.count)]) != bgPx {
                hasNonBackground = true
                break
            }
        }
        XCTAssertTrue(hasNonBackground, "expected at least one non-background pixel from glyph rendering")
    }

    func testSublimeHighlightScopeMappingAndRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Put a space after '#' so we can sample a highlighted cell without glyph pixels.
        let ui = try EditorUI(library: lib, initialText: "a # \n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        let yaml = """
        %YAML 1.2
        ---
        name: Demo
        scope: source.demo
        contexts:
          main:
            - match: "#.*$"
              scope: comment.line.demo
        """
        try ui.sublimeSetSyntaxYAML(yaml)

        let styleId = try ui.sublimeStyleId(forScope: "comment.line.demo")
        XCTAssertEqual(try ui.sublimeScope(forStyleId: styleId), "comment.line.demo")

        try ui.setStyleColors([EcuStyleColors(styleId: styleId, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // "a # " => space at col=3 is highlighted => x in [30..40]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 35, y: 10), [1, 200, 2, 255])
    }

    func testTreeSitterHighlightCaptureMappingAndRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "// c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        try setTestTreeSitterRegistry(ui)
        try ui.treeSitterEnableLanguage("rust")
        try waitForAsyncProcessing(ui)
        let styleId = try ui.treeSitterStyleId(forCapture: "comment")
        XCTAssertEqual(try ui.treeSitterCapture(forStyleId: styleId), "comment")

        try ui.setStyleColors([EcuStyleColors(styleId: styleId, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Comment contains a space at col=2 => x in [20..30]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 25, y: 10), [1, 200, 2, 255])
    }

    func testLspDiagnosticsAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // LSP diagnostics style id encoding: 0x0400_0100 | severity
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0400_0100 | 1, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let params = """
        {
          "uri": "file:///test",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 2 }
              },
              "severity": 1,
              "message": "unit"
            }
          ],
          "version": 1
        }
        """
        try ui.lspApplyDiagnosticsJSON(params)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Highlighted cell at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testGutterRendersFoldMarkerAndClickTogglesFold() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "fn main() {\n  let x = 1;\n}\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 60, scale: 1)
        try setTestTreeSitterRegistry(ui)
        try ui.treeSitterEnableLanguage("rust")
        try waitForAsyncProcessing(ui)
        // Ensure there is space for both the fold-marker column (2 cells) and line numbers.
        try ui.setGutterWidthCells(4)
        // Use block style to keep pixel assertions deterministic (chevrons are anti-aliased).
        try ui.setFoldMarkerStyle(.block)

        // Reserved overlay style ids (see `editor-core-render-skia`).
        let gutterBg: UInt32 = 0x0600_0001
        let gutterFg: UInt32 = 0x0600_0002
        let foldCollapsed: UInt32 = 0x0600_0004
        let foldExpanded: UInt32 = 0x0600_0005

        try ui.setStyleColors([
            // Make gutter background visible; keep numbers "invisible" for deterministic pixel tests.
            EcuStyleColors(styleId: gutterBg, background: EcuRgba8(r: 1, g: 2, b: 3, a: 255)),
            EcuStyleColors(styleId: gutterFg, foreground: EcuRgba8(r: 1, g: 2, b: 3, a: 255)),
            EcuStyleColors(styleId: foldExpanded, background: EcuRgba8(r: 9, g: 9, b: 9, a: 255)),
            EcuStyleColors(styleId: foldCollapsed, background: EcuRgba8(r: 8, g: 8, b: 8, a: 255)),
        ])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [9, 9, 9, 255])
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 25, y: 10), [1, 2, 3, 255])

        // Click in gutter to toggle fold.
        try ui.mouseDown(xPx: 5, yPx: 10)
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [8, 8, 8, 255])

        try ui.mouseDown(xPx: 5, yPx: 10)
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [9, 9, 9, 255])
    }
}
