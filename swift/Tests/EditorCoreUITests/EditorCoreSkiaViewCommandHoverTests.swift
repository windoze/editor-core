import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewCommandHoverTests: XCTestCase {
    private func makeMouseEvent(
        type: NSEvent.EventType,
        atCharOffset offset: UInt32,
        in view: EditorCoreSkiaView,
        window: NSWindow,
        modifierFlags: NSEvent.ModifierFlags
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
            clickCount: 0,
            pressure: 0
        )
        XCTAssertNotNil(event, "failed to create mouse event")
        return try XCTUnwrap(event)
    }

    private func makeWindow(with view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.layoutSubtreeIfNeeded()
        return window
    }

    private func pixel(_ rgba: [UInt8], widthPx: Int, x: Int, y: Int) -> [UInt8] {
        let idx = (y * widthPx + x) * 4
        if idx < 0 || idx + 3 >= rgba.count {
            return [0, 0, 0, 0]
        }
        return [rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]]
    }

    func testCmdHoverAppliesUnderlineStyleAndShowsNonBackgroundPixels() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "HELLO WORLD\n", viewportWidthCells: 80)
        let window = makeWindow(with: view)
        _ = window

        view.onCommandHover = { _ in true }

        // Use a deterministic software render target for sampling.
        try view.editor.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try view.editor.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        let bg = [UInt8(0xFF), UInt8(0xFF), UInt8(0xFF), UInt8(0xFF)]

        // Baseline: no underline yet.
        do {
            var rgba: [UInt8] = []
            _ = try view.editor.renderRGBA(into: &rgba)
            let p = try view.editor.charOffsetToViewPoint(offset: 1) // inside "HELLO"
            let x = Int(p.xPx + 5)
            let baseY = Int(p.yPx + p.lineHeightPx - 1)
            let samples = (0..<4).map { dy in pixel(rgba, widthPx: 200, x: x, y: baseY - dy) }
            XCTAssertTrue(samples.allSatisfy { $0 == bg }, "expected no underline pixels before Cmd-hover")
        }

        // Cmd-hover over the token.
        let move = try makeMouseEvent(type: .mouseMoved, atCharOffset: 1, in: view, window: window, modifierFlags: [.command])
        view.mouseMoved(with: move)

        // After hover: underline should introduce non-background pixels near the bottom of the line box.
        do {
            var rgba: [UInt8] = []
            _ = try view.editor.renderRGBA(into: &rgba)
            let p = try view.editor.charOffsetToViewPoint(offset: 1)
            let x = Int(p.xPx + 5)
            let baseY = Int(p.yPx + p.lineHeightPx - 1)
            let samples = (0..<4).map { dy in pixel(rgba, widthPx: 200, x: x, y: baseY - dy) }
            XCTAssertTrue(samples.contains(where: { $0 != bg }), "expected underline pixels after Cmd-hover")

            // Outside the token ("WORLD"), pixels at the underline row should stay background.
            let p2 = try view.editor.charOffsetToViewPoint(offset: 7) // inside "WORLD"
            let x2 = Int(p2.xPx + 5)
            let samples2 = (0..<4).map { dy in pixel(rgba, widthPx: 200, x: x2, y: baseY - dy) }
            XCTAssertTrue(samples2.allSatisfy { $0 == bg }, "expected underline to not affect other tokens")
        }
    }
}
