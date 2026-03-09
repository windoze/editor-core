import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewGraphemeDeletionTests: XCTestCase {
    func testBackspaceAndDeleteForwardDeleteWholeGraphemeCluster() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()

        // "á" = 'a' + COMBINING ACUTE ACCENT (2 Unicode scalars, 1 grapheme cluster).
        let s = "a\u{0301}"

        // Backspace at end deletes the entire grapheme cluster.
        do {
            let view = try EditorCoreSkiaView(library: lib, initialText: s, viewportWidthCells: 80)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            view.layoutSubtreeIfNeeded()

            try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)
            view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            XCTAssertEqual(try view.editor.text(), "")
        }

        // Delete-forward at start deletes the entire grapheme cluster.
        do {
            let view = try EditorCoreSkiaView(library: lib, initialText: s, viewportWidthCells: 80)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            view.layoutSubtreeIfNeeded()

            try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
            view.doCommand(by: #selector(NSResponder.deleteForward(_:)))
            XCTAssertEqual(try view.editor.text(), "")
        }
    }
}

