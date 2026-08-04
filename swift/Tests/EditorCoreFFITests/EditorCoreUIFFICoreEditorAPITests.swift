import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testCloneViewSharesTextAndHasIndependentScrollState() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui1 = try EditorUI(
            library: lib,
            initialText: "abc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n",
            viewportWidthCells: 80
        )
        let ui2 = try ui1.cloneView(viewportWidthCells: 80)

        // View state is independent.
        try ui1.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        try ui2.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        XCTAssertEqual(try ui1.selectionOffsets().start, 0)
        XCTAssertEqual(try ui2.selectionOffsets().start, 4)

        // Text edits are shared.
        try ui1.insertText("X")
        XCTAssertEqual(try ui2.text(), "Xabc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n")

        // Each view tracks its own selection, but receives the same text delta.
        let s2 = try ui2.selectionOffsets()
        XCTAssertEqual(s2.start, 5)
        XCTAssertEqual(s2.end, 5)

        // Scroll is view-local.
        try ui1.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui2.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui1.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)
        try ui2.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        ui1.setSmoothScrollState(topVisualRow: 1, subRowOffset: 0)
        ui2.setSmoothScrollState(topVisualRow: 3, subRowOffset: 0)

        XCTAssertEqual(try ui1.viewportState().scrollTop, 1)
        XCTAssertEqual(try ui2.viewportState().scrollTop, 3)
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

    func testCharOffsetToLogicalPosition() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "ab\ncde\nf", viewportWidthCells: 80)

        let p = try ui.charOffsetToLogicalPosition(offset: 4) // 'd'
        XCTAssertEqual(p.line, 1)
        XCTAssertEqual(p.column, 1)
    }

    func testMinimapJSON() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a\nb\nc", viewportWidthCells: 80)

        let minimap = try JSONTestHelpers.object(try ui.minimapJSON(startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(minimap["lines"])
        XCTAssertEqual(minimap["start_visual_row"] as? Int, 0)
        XCTAssertEqual(minimap["count"] as? Int, 20)
        XCTAssertEqual(minimap["actual_line_count"] as? Int, 3)
    }

    func testSmoothScrollByPixelsAffectsHitTestingAndViewPointMapping() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        // Scroll down by half a row: content should move up by 5px.
        ui.scrollByPixels(5)

        // "b" starts at char offset 2 ("a\nb..."), its y should be (1*10 - 5) = 5.
        let pB = try ui.charOffsetToViewPoint(offset: 2)
        XCTAssertEqual(pB.yPx, 5)

        // Hit test must account for smooth scroll:
        // y < 5 => line 0 ("a"), y >= 5 => line 1 ("b")
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 0, yPx: 4), 0)
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 0, yPx: 5), 2)
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 0, yPx: 9), 2)
    }

    func testViewportStateAndSetSmoothScrollState() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "0\n1\n2\n3\n4\n5\n6\n7", viewportWidthCells: 80)
        try ui.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        let vp0 = try ui.viewportState()
        XCTAssertEqual(vp0.totalVisualLines, 8)
        XCTAssertEqual(vp0.heightRows, 2)
        XCTAssertEqual(vp0.scrollTop, 0)
        XCTAssertEqual(vp0.subRowOffset, 0)

        ui.setSmoothScrollState(topVisualRow: 3, subRowOffset: 32768)
        let vp1 = try ui.viewportState()
        XCTAssertEqual(vp1.scrollTop, 3)
        XCTAssertEqual(vp1.subRowOffset, 32768)

        // Clamp to max scroll (total - height = 6).
        ui.setSmoothScrollState(topVisualRow: 999, subRowOffset: 65535)
        let vp2 = try ui.viewportState()
        XCTAssertEqual(vp2.scrollTop, 6)
        XCTAssertEqual(vp2.subRowOffset, 0)
    }

    func testRevealPrimaryCaretScrollsToShowCaret() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let text = (0..<100).map { _ in "x" }.joined(separator: "\n")
        let ui = try EditorUI(library: lib, initialText: text, viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 14, lineHeightPx: 10, cellWidthPx: 8, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 800, heightPx: 50, scale: 1)
        ui.setSmoothScrollState(topVisualRow: 0, subRowOffset: 0)

        // Line 50, col 0 in "x\nx\n..." => offset 50*(1+1) = 100.
        try ui.setSelections([EcuSelectionRange(start: 100, end: 100)], primaryIndex: 0)
        try ui.revealPrimaryCaret()

        let vp = try ui.viewportState()
        XCTAssertEqual(vp.heightRows, 5)
        XCTAssertEqual(vp.scrollTop, 46)
    }
}
