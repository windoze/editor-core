import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testMatchHighlightsAffectRendering() throws {
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

        // Built-in style id for match highlights: 0x0800_0004
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0004, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])
        try ui.setMatchHighlights([EcuSelectionRange(start: 1, end: 2)])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testSearchSetQuerySetsMatchHighlightsAndReturnsCount() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use spaces as matches so glyph rasterization does not affect the pixel samples.
        let ui = try EditorUI(library: lib, initialText: "a c a\n", viewportWidthCells: 80)

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

        // Built-in style id for match highlights: 0x0800_0004
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0004, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let count = try ui.setSearchQuery(" ", options: EcuSearchOptions(caseSensitive: true, wholeWord: false, regex: false))
        XCTAssertEqual(count, 2)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // First space at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
        // Second space at col=3 => x in [30..40]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 35, y: 10), [1, 200, 2, 255])
    }

    func testFindNextAndReplaceCurrentAndAll() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo foo foo\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(try ui.findNext("foo"))
        XCTAssertEqual(try ui.selectionOffsets().start, 0)
        XCTAssertEqual(try ui.selectionOffsets().end, 3)

        XCTAssertTrue(try ui.findNext("foo"))
        XCTAssertEqual(try ui.selectionOffsets().start, 4)
        XCTAssertEqual(try ui.selectionOffsets().end, 7)

        let replaced = try ui.replaceCurrent(query: "foo", replacement: "bar")
        XCTAssertEqual(replaced, 1)
        XCTAssertEqual(try ui.text(), "foo bar foo\n")

        let replacedAll = try ui.replaceAll(query: "foo", replacement: "baz")
        XCTAssertEqual(replacedAll, 2)
        XCTAssertEqual(try ui.text(), "baz bar baz\n")
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

    func testAddAllOccurrencesAcceptsSearchOptions() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo Foo foo\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)
        try ui.addAllOccurrences(options: EcuSearchOptions(caseSensitive: false))

        let sels = try ui.selections()
        XCTAssertEqual(sels.ranges.count, 3)
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
}
