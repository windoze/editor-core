import AppKit
import XCTest

@testable import EditorCoreAppKit

@MainActor
final class EditorCoreCoordinateMappingTests: XCTestCase {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    func test_window_backing_to_view_backing_flips_y_and_offsets() throws {
        let viewTopLeftInWindowBacking = NSPoint(x: 100, y: 200)
        let p = NSPoint(x: 110, y: 190)

        let out = EditorCoreCoordinateMapping.windowBackingToViewBackingPx(
            windowBackingPoint: p,
            viewTopLeftInWindowBacking: viewTopLeftInWindowBacking
        )

        XCTAssertEqual(out.x, 10)
        XCTAssertEqual(out.y, 10)
    }

    func test_window_point_to_view_backing_px_for_fullsize_flipped_content_view() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView = view

        let backingSize = view.convertToBacking(view.bounds.size)

        let p0 = view.convert(NSPoint(x: 0, y: 0), to: nil)
        let p1 = view.convert(NSPoint(x: 0, y: view.bounds.height), to: nil)
        let topLeftInWindow = (p0.y >= p1.y) ? p0 : p1

        let bottomRightInWindow = NSPoint(
            x: topLeftInWindow.x + view.bounds.width,
            y: topLeftInWindow.y - view.bounds.height
        )

        let (x0, y0) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(windowPoint: topLeftInWindow, view: view)
        XCTAssertEqual(Double(x0), 0, accuracy: 0.0001)
        XCTAssertEqual(Double(y0), 0, accuracy: 0.0001)

        let (x1, y1) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(windowPoint: bottomRightInWindow, view: view)
        XCTAssertEqual(Double(x1), Double(backingSize.width), accuracy: 0.0001)
        XCTAssertEqual(Double(y1), Double(backingSize.height), accuracy: 0.0001)
    }

    func test_window_point_to_view_backing_px_for_offset_flipped_subview() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = container

        let view = FlippedView(frame: NSRect(x: 20, y: 30, width: 200, height: 100))
        container.addSubview(view)

        let backingSize = view.convertToBacking(view.bounds.size)

        let p0 = view.convert(NSPoint(x: 0, y: 0), to: nil)
        let p1 = view.convert(NSPoint(x: 0, y: view.bounds.height), to: nil)
        let topLeftInWindow = (p0.y >= p1.y) ? p0 : p1

        let bottomRightInWindow = NSPoint(
            x: topLeftInWindow.x + view.bounds.width,
            y: topLeftInWindow.y - view.bounds.height
        )

        let (x0, y0) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(windowPoint: topLeftInWindow, view: view)
        XCTAssertEqual(Double(x0), 0, accuracy: 0.0001)
        XCTAssertEqual(Double(y0), 0, accuracy: 0.0001)

        let (x1, y1) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(windowPoint: bottomRightInWindow, view: view)
        XCTAssertEqual(Double(x1), Double(backingSize.width), accuracy: 0.0001)
        XCTAssertEqual(Double(y1), Double(backingSize.height), accuracy: 0.0001)
    }
}
