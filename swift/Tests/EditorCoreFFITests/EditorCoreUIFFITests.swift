import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFITests: XCTestCase {
    func testLoadsLibraryAndVersion() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        XCTAssertFalse(lib.resolvedLibraryPath.isEmpty)
        XCTAssertFalse(lib.versionString().isEmpty)
    }

    func testParagraphSelectionAPIs() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\nbb\n\ncc\ndd", viewportWidthCells: 80)

        try ui.selectParagraph(atCharOffset: 0)
        let p1 = try ui.selectionOffsets()
        XCTAssertEqual(p1.start, 0)
        XCTAssertEqual(p1.end, 6) // "aa\nbb\n"

        try ui.selectParagraph(atCharOffset: 6)
        let blank = try ui.selectionOffsets()
        XCTAssertEqual(blank.start, 6)
        XCTAssertEqual(blank.end, 7) // the blank line's newline

        try ui.selectParagraph(atCharOffset: 8)
        let p2 = try ui.selectionOffsets()
        XCTAssertEqual(p2.start, 7)
        XCTAssertEqual(p2.end, 12) // "cc\ndd"

        // Union selection: from first paragraph into second paragraph.
        try ui.setParagraphSelection(anchorOffset: 0, activeOffset: 8)
        let u = try ui.selectionOffsets()
        XCTAssertEqual(u.start, 0)
        XCTAssertEqual(u.end, 12)
    }

    func testLineSelectionOffsetsAPI() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\nbb\n\ncc\ndd", viewportWidthCells: 80)

        // Anchor in line 0, drag into line 3 (inside "cc").
        try ui.setLineSelection(anchorOffset: 0, activeOffset: 8)
        let a = try ui.selectionOffsets()
        XCTAssertEqual(a.start, 0)
        XCTAssertEqual(a.end, 10) // "aa\nbb\n\ncc\n"

        // Reverse direction should produce the same range.
        try ui.setLineSelection(anchorOffset: 8, activeOffset: 0)
        let b = try ui.selectionOffsets()
        XCTAssertEqual(b.start, 0)
        XCTAssertEqual(b.end, 10)

        // Last line has no trailing newline.
        try ui.setLineSelection(anchorOffset: 10, activeOffset: 11)
        let last = try ui.selectionOffsets()
        XCTAssertEqual(last.start, 10)
        XCTAssertEqual(last.end, 12)
    }

    func testCreateInsertUndoRedoRenderAndQueries() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
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
        // 多字体 fallback：确保主字体缺字时仍能显示 CJK/Emoji（渲染层按字符挑选可用字体）。
        try ui.setFontFamiliesCSV("Menlo, PingFang SC, Apple Color Emoji")
        // Font ligatures (visual-only): should not crash even if the selected font has no ligatures.
        try ui.setFontLigaturesEnabled(true)
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

        // Inline/preedit: caret inside marked text (after first char of "你好").
        try ui.setMarkedText("你好", selectedStart: 1, selectedLen: 0)
        let selIme = try ui.selectionOffsets()
        XCTAssertEqual(selIme.start, 4) // "abc" (3) + 1
        XCTAssertEqual(selIme.end, 4)

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

        try ui.treeSitterRustEnable(highlightsQuery: "(line_comment) @comment")
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

        // Highlighted cell at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testLspSemanticTokensAffectRendering() throws {
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

        // encode_semantic_style_id(token_type=7, token_modifiers=0) => 0x0007_0000
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0007_0000, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        // Highlight cell at col=1 (line 0, utf16 start=1, len=1).
        try ui.lspApplySemanticTokens([0, 1, 1, 7, 0])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testMultiSelectionsSetGetAndInsertTextAppliesToAllCarets() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\ndef\n", viewportWidthCells: 80)

        try ui.setSelections(
            [
                EcuSelectionRange(start: 0, end: 0),
                EcuSelectionRange(start: 4, end: 4),
            ],
            primaryIndex: 0
        )

        let sels = try ui.selections()
        XCTAssertEqual(sels.ranges.count, 2)
        XCTAssertEqual(sels.primaryIndex, 0)
        XCTAssertEqual(sels.ranges[0], EcuSelectionRange(start: 0, end: 0))
        XCTAssertEqual(sels.ranges[1], EcuSelectionRange(start: 4, end: 4))

        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "Xabc\nXdef\n")
    }

    func testRectSelectionReplacesEachLineRange() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\ndef\nghi\n", viewportWidthCells: 80)

        try ui.setRectSelection(anchorOffset: 1, activeOffset: 10)
        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "aXc\ndXf\ngXi\n")
    }

    func testSelectWordAndAddAllOccurrences() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo foo foo\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        try ui.selectWord()
        try ui.addAllOccurrences()

        let sels = try ui.selections()
        XCTAssertEqual(sels.ranges.count, 3)

        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "X X X\n")
    }

    func testAddCursorAboveAndClearSecondarySelections() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\naa\naa\n", viewportWidthCells: 80)

        // line 1 col 1 => offset 4
        try ui.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        try ui.addCursorAbove()

        let sels1 = try ui.selections()
        XCTAssertEqual(sels1.ranges.count, 2)

        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "aXa\naXa\naa\n")

        try ui.clearSecondarySelections()
        let sels2 = try ui.selections()
        XCTAssertEqual(sels2.ranges.count, 1)
    }

    func testMoveAndModifySelectionExtendsFromAnchor() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)

        try ui.moveGraphemeLeftAndModifySelection()
        var sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, 1)
        XCTAssertEqual(sel.end, 2)

        try ui.moveGraphemeLeftAndModifySelection()
        sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, 0)
        XCTAssertEqual(sel.end, 2)

        try ui.moveGraphemeRightAndModifySelection()
        sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, 1)
        XCTAssertEqual(sel.end, 2)
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
        try ui.treeSitterRustEnableDefault()
        try ui.setGutterWidthCells(2)

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
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 19, y: 10), [1, 2, 3, 255])

        // Click in gutter to toggle fold.
        try ui.mouseDown(xPx: 5, yPx: 10)
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [8, 8, 8, 255])

        try ui.mouseDown(xPx: 5, yPx: 10)
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [9, 9, 9, 255])
    }

    private func pixel(_ buf: [UInt8], widthPx: UInt32, x: UInt32, y: UInt32) -> [UInt8] {
        let idx = Int((y * widthPx + x) * 4)
        return [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
