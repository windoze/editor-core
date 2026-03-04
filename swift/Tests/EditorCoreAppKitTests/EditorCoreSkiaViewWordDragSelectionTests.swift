import AppKit
import EditorCoreAppKit
import XCTest

@MainActor
final class EditorCoreSkiaViewWordDragSelectionTests: XCTestCase {
    func testDoubleClickThenDragExpandsByWord() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "one two three", viewportWidthCells: 80)

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

        // Double click at the beginning of "two" (offset 4) => select "two".
        let p4 = try windowPointForCharOffset(4, in: view)
        let down = try makeMouseEvent(type: .leftMouseDown, locationInWindow: p4, window: window, clickCount: 2)
        view.mouseDown(with: down)

        let s1 = try view.editor.selectionOffsets()
        XCTAssertEqual(s1.start, 4)
        XCTAssertEqual(s1.end, 7)

        // Drag into "three" (offset 8) => expand selection by word to include it.
        let p8 = try windowPointForCharOffset(8, in: view)
        let drag1 = try makeMouseEvent(type: .leftMouseDragged, locationInWindow: p8, window: window, clickCount: 2)
        view.mouseDragged(with: drag1)

        let s2 = try view.editor.selectionOffsets()
        XCTAssertEqual(s2.start, 4)
        XCTAssertEqual(s2.end, 13)

        // Change drag direction: expand-only means we extend to include "one" as well.
        let p0 = try windowPointForCharOffset(0, in: view)
        let drag2 = try makeMouseEvent(type: .leftMouseDragged, locationInWindow: p0, window: window, clickCount: 2)
        view.mouseDragged(with: drag2)

        let s3 = try view.editor.selectionOffsets()
        XCTAssertEqual(s3.start, 0)
        XCTAssertEqual(s3.end, 13)

        let up = try makeMouseEvent(type: .leftMouseUp, locationInWindow: p0, window: window, clickCount: 2)
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
        throw XCTSkip("无法构造 NSEvent.mouseEvent，跳过双击拖拽按词扩选测试。")
    }
    return e
}

