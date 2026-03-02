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

    private func pixel(_ buf: [UInt8], widthPx: UInt32, x: UInt32, y: UInt32) -> [UInt8] {
        let idx = Int((y * widthPx + x) * 4)
        return [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}

