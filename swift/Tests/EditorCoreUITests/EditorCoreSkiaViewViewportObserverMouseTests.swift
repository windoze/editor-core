import AppKit
@testable import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewViewportObserverMouseTests: XCTestCase {
    private func makeMouseEvent(
        type: NSEvent.EventType,
        atCharOffset offset: UInt32,
        in view: EditorCoreSkiaView,
        window: NSWindow,
        clickCount: Int = 1,
        modifierFlags: NSEvent.ModifierFlags = []
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
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 0
        )
        XCTAssertNotNil(event, "failed to create mouse event")
        return try XCTUnwrap(event)
    }

    func testViewportObserverFiresOnMouseDownSelectionChange() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
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

        var fired = 0
        let token = view.addViewportStateObserver {
            fired += 1
        }
        _ = token

        let down = try makeMouseEvent(type: .leftMouseDown, atCharOffset: 4, in: view, window: window)
        view.mouseDown(with: down)

        XCTAssertEqual(fired, 1, "expected mouse selection changes to notify viewport observers (for status bar updates)")
    }
}

