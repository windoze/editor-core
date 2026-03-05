import AppKit
@testable import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewKeyboardScrollTests: XCTestCase {
    func testMoveDownScrollsToKeepCaretVisible() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let lines = (0..<80).map(String.init).joined(separator: "\n")
        let view = try EditorCoreSkiaView(library: lib, initialText: lines, viewportWidthCells: 80)

        // Use a small window so the caret will go out of the viewport unless we scroll.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        let vp0 = try view.editor.viewportState()
        XCTAssertEqual(vp0.scrollTop, 0)

        // Move down enough times that we must scroll.
        for _ in 0..<20 {
            view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        }

        let vp1 = try view.editor.viewportState()
        XCTAssertGreaterThan(vp1.scrollTop, 0)
    }
}

