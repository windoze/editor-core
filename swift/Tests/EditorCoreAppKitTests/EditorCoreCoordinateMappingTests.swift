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
        let sx = backingSize.width / view.bounds.width
        let sy = backingSize.height / view.bounds.height

        let viewPoint = NSPoint(x: 10, y: 15)
        let windowPoint = view.convert(viewPoint, to: nil)
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(windowPoint: windowPoint, view: view)

        XCTAssertEqual(Double(xPx), Double(viewPoint.x * sx), accuracy: 0.0001)
        XCTAssertEqual(Double(yPx), Double(viewPoint.y * sy), accuracy: 0.0001)
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
        let sx = backingSize.width / view.bounds.width
        let sy = backingSize.height / view.bounds.height

        let viewPoint = NSPoint(x: 7, y: 9)
        let windowPoint = view.convert(viewPoint, to: nil)
        let (xPx, yPx) = EditorCoreCoordinateMapping.windowPointToViewBackingPx(windowPoint: windowPoint, view: view)

        XCTAssertEqual(Double(xPx), Double(viewPoint.x * sx), accuracy: 0.0001)
        XCTAssertEqual(Double(yPx), Double(viewPoint.y * sy), accuracy: 0.0001)
    }
}
