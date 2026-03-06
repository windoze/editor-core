import AppKit
import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewHoverTests: XCTestCase {
    private func makeMouseEvent(
        type: NSEvent.EventType,
        atCharOffset offset: UInt32,
        in view: EditorCoreSkiaView,
        window: NSWindow
    ) throws -> NSEvent {
        // Use the Rust hit-test mapping to generate a stable point, then convert back to window coordinates.
        let p = try view.editor.charOffsetToViewPoint(offset: offset)

        let backingSize = view.convertToBacking(view.bounds.size)
        let sx = max(1, backingSize.width / max(1, view.bounds.size.width))
        let sy = max(1, backingSize.height / max(1, view.bounds.size.height))

        // Move inside the line box so the hit test never lands on an ambiguous boundary.
        let xPx = p.xPx + 1
        let yPx = p.yPx + p.lineHeightPx * 0.5

        let viewPoint = NSPoint(x: CGFloat(xPx) / sx, y: CGFloat(yPx) / sy)
        let windowPoint = view.convert(viewPoint, to: nil)

        let event = NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )
        XCTAssertNotNil(event, "failed to create mouse event")
        return try XCTUnwrap(event)
    }

    func testHoverCallbackFiresWithLogicalPosition() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "ab\ncde\nf", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.layoutSubtreeIfNeeded()

        var received: EditorCoreSkiaHoverInfo?
        view.onHover = { info in
            received = info
        }

        // Offset 4 is 'd' in "ab\ncde\nf" (line 1, col 1).
        let event = try makeMouseEvent(type: .mouseMoved, atCharOffset: 4, in: view, window: window)
        view.mouseMoved(with: event)

        let info = try XCTUnwrap(received)
        XCTAssertEqual(info.charOffset, 4)
        XCTAssertEqual(info.logicalLine, 1)
        XCTAssertEqual(info.logicalColumn, 1)
    }

    func testHoverExitCallbackFires() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "ab\ncde\nf", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.layoutSubtreeIfNeeded()

        // Prime hover state.
        view.onHover = { _ in }
        let move = try makeMouseEvent(type: .mouseMoved, atCharOffset: 4, in: view, window: window)
        view.mouseMoved(with: move)

        var didExit = false
        view.onHoverExit = {
            didExit = true
        }

        // `NSEvent.mouseEvent(with:)` does not support constructing a `.mouseExited` event in tests.
        // For our purposes, the concrete event payload is irrelevant (the view only uses it for `super`).
        view.mouseExited(with: move)

        XCTAssertTrue(didExit)
    }
}
