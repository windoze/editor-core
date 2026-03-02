import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFITests: XCTestCase {
    func testLoadsLibraryAndVersion() throws {
        let lib = try EditorCoreUIFFILibrary()
        XCTAssertFalse(lib.resolvedLibraryPath.isEmpty)
        XCTAssertFalse(lib.versionString().isEmpty)
    }

    func testCreateInsertUndoRedoRenderAndQueries() throws {
        let lib = try EditorCoreUIFFILibrary()
        let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)

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

        var rgba: [UInt8] = []
        let n = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(n, 80 * 40 * 4)
        XCTAssertEqual(rgba.count, 80 * 40 * 4)

        // 背景色在空白区域必须是我们设置的值
        XCTAssertEqual(pixel(rgba, widthPx: 80, x: 70, y: 30), [10, 20, 30, 255])

        // 编辑 + undo/redo
        try ui.insertText("abc")
        XCTAssertEqual(try ui.text(), "abc")
        try ui.undo()
        XCTAssertEqual(try ui.text(), "")
        try ui.redo()
        XCTAssertEqual(try ui.text(), "abc")

        // IME marked text（Rust UI 层实现）
        try ui.setMarkedText("你")
        let marked1 = try ui.markedRange()
        XCTAssertTrue(marked1.hasMarked)
        XCTAssertEqual(marked1.len, 1)

        try ui.setMarkedText("你好")
        let marked2 = try ui.markedRange()
        XCTAssertTrue(marked2.hasMarked)
        XCTAssertEqual(marked2.len, 2)

        try ui.commitText("你好!")
        let marked3 = try ui.markedRange()
        XCTAssertFalse(marked3.hasMarked)
        XCTAssertEqual(try ui.text(), "abc你好!")

        // selection offsets: no selection => start == end == caret
        let sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, sel.end)

        // offset <-> view point mapping
        let p = try ui.charOffsetToViewPoint(offset: 0)
        XCTAssertEqual(p.xPx, 0)
        XCTAssertEqual(p.yPx, 0)
        XCTAssertEqual(p.lineHeightPx, 20)

        let hit = try ui.viewPointToCharOffset(xPx: 25, yPx: 10)
        XCTAssertEqual(hit, 2)
    }

    func testStyleColorsOverrideAffectsRendering() throws {
        let lib = try EditorCoreUIFFILibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

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

        // 给中间字符 'b' 加一个 style id，然后下发该 style 的背景色覆盖。
        try ui.addStyle(start: 1, end: 2, styleId: 42)
        try ui.setStyleColors([EcuStyleColors(styleId: 42, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // 'b' 对应 x in [10..20]，取中心像素。
        XCTAssertEqual(pixel(rgba, widthPx: 80, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testSublimeHighlightScopeMappingAndRendering() throws {
        let lib = try EditorCoreUIFFILibrary()
        let ui = try EditorUI(library: lib, initialText: "a #c\n", viewportWidthCells: 80)

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

        // "a #c" => '#' at col=2 => x in [20..30]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 25, y: 10), [1, 200, 2, 255])
    }

    func testTreeSitterHighlightCaptureMappingAndRendering() throws {
        let lib = try EditorCoreUIFFILibrary()
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

        try ui.treeSitterRustEnable(highlightsQuery: "(line_comment) @comment")
        let styleId = try ui.treeSitterStyleId(forCapture: "comment")
        XCTAssertEqual(try ui.treeSitterCapture(forStyleId: styleId), "comment")

        try ui.setStyleColors([EcuStyleColors(styleId: styleId, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Comment starts at col=0 => x in [0..10]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [1, 200, 2, 255])
    }

    func testLspDiagnosticsAffectRendering() throws {
        let lib = try EditorCoreUIFFILibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

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

        // LSP diagnostics style id encoding: 0x0400_0000 | severity
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0400_0000 | 1, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

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

        // 'b' at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testLspSemanticTokensAffectRendering() throws {
        let lib = try EditorCoreUIFFILibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

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

        // encode_semantic_style_id(token_type=7, token_modifiers=0) => 0x0007_0000
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0007_0000, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        // Highlight 'b' (line 0, utf16 start=1, len=1).
        try ui.lspApplySemanticTokens([0, 1, 1, 7, 0])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    private func pixel(_ buf: [UInt8], widthPx: UInt32, x: UInt32, y: UInt32) -> [UInt8] {
        let idx = Int((y * widthPx + x) * 4)
        return [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
