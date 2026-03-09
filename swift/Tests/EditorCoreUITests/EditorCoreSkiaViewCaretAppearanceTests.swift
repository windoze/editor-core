import AppKit
@testable import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewCaretAppearanceTests: XCTestCase {
    func testCaretWidthPointsAppliesScaledPxToRust() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "", viewportWidthCells: 80)

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        host.addSubview(editorView)
        editorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: host.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()

        editorView.caretWidthPoints = 3.0

        let expectedPx = Float(3.0 * window.backingScaleFactor)
        XCTAssertEqual(
            editorView._lastAppliedCaretWidthPxForTesting ?? 0,
            expectedPx,
            accuracy: 0.25,
            "expected caret width points to be multiplied by backingScaleFactor before sending to Rust"
        )
    }

    func testCaretBlinkTickTogglesVisibilityWhenEnabled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "abc", viewportWidthCells: 80)

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        host.addSubview(editorView)
        editorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: host.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView)
        host.layoutSubtreeIfNeeded()

        editorView.caretBlinkEnabled = true
        editorView.caretBlinkIntervalSeconds = 0.2

        // Initial should be visible.
        XCTAssertEqual(editorView._lastAppliedCaretVisibleForTesting, true)

        // Manual tick toggles to hidden.
        editorView._caretBlinkTickForTesting()
        XCTAssertEqual(editorView._lastAppliedCaretVisibleForTesting, false)

        // And back to visible.
        editorView._caretBlinkTickForTesting()
        XCTAssertEqual(editorView._lastAppliedCaretVisibleForTesting, true)

        // Disabling blinking forces caret to stay visible (tick should not hide it).
        editorView.caretBlinkEnabled = false
        editorView._caretBlinkTickForTesting()
        XCTAssertEqual(editorView._lastAppliedCaretVisibleForTesting, true)
    }
}

