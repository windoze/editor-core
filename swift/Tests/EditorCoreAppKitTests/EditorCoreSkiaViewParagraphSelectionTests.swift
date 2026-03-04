import AppKit
import EditorCoreAppKit
import XCTest

@MainActor
final class EditorCoreSkiaViewParagraphSelectionTests: XCTestCase {
    func testTripleClickSelectsLineThenDragSelectsParagraphUnion() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "aa\nbb\n\ncc\ndd", viewportWidthCells: 80)

        // Put the view in a real window so coordinate conversions behave like the demo.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        // 1) Triple click at the beginning => select first line ("aa\n").
        let p0 = try windowPointForCharOffset(0, in: view)
        let down = try makeMouseEvent(type: .leftMouseDown, locationInWindow: p0, window: window, clickCount: 3)
        view.mouseDown(with: down)

        let s1 = try view.editor.selectionOffsets()
        XCTAssertEqual(s1.start, 0)
        XCTAssertEqual(s1.end, 3)

        // 2) Drag to the second paragraph => union selection should cover both paragraphs and the blank line between.
        let p8 = try windowPointForCharOffset(8, in: view) // inside "cc"
        let drag = try makeMouseEvent(type: .leftMouseDragged, locationInWindow: p8, window: window, clickCount: 3)
        view.mouseDragged(with: drag)

        let s2 = try view.editor.selectionOffsets()
        XCTAssertEqual(s2.start, 0)
        XCTAssertEqual(s2.end, 12)

        // 3) Mouse up clears internal drag state (should not crash).
        let up = try makeMouseEvent(type: .leftMouseUp, locationInWindow: p8, window: window, clickCount: 3)
        view.mouseUp(with: up)
    }
}

@MainActor
private func windowPointForCharOffset(_ offset: UInt32, in view: EditorCoreSkiaView) throws -> NSPoint {
    let p = try view.editor.charOffsetToViewPoint(offset: offset)

    let boundsSize = view.bounds.size
    let backingSize = view.convertToBacking(boundsSize)
    let sx = boundsSize.width > 0 ? (backingSize.width / boundsSize.width) : 1
    let sy = boundsSize.height > 0 ? (backingSize.height / boundsSize.height) : 1

    // `charOffsetToViewPoint` gives us the cell-aligned top of the row; click near the middle of the row.
    let xPt = CGFloat(p.xPx) / sx + 1
    let yPt = CGFloat(p.yPx) / sy + (CGFloat(p.lineHeightPx) / sy) * 0.5
    let viewPoint = NSPoint(x: xPt, y: yPt)
    return view.convert(viewPoint, to: nil)
}

@MainActor
private func makeMouseEvent(
    type: NSEvent.EventType,
    locationInWindow: NSPoint,
    window: NSWindow,
    clickCount: Int
) throws -> NSEvent {
    let t = ProcessInfo.processInfo.systemUptime
    guard let e = NSEvent.mouseEvent(
        with: type,
        location: locationInWindow,
        modifierFlags: [],
        timestamp: t,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
    ) else {
        throw XCTSkip("无法构造 NSEvent.mouseEvent，跳过三击拖拽段落选择测试。")
    }
    return e
}
