import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoEditorInteractionPolishTests: XCTestCase {
    func testCompletionPopupRestoresEditorFocusWhenDismissed() throws {
        let items = AttoLspCompletionParser.items(
            fromCompletionResultJSON: #"{"items":[{"label":"print","kind":3,"detail":"fn"}]}"#
        )
        XCTAssertFalse(items.isEmpty)

        let editorView = AttoFocusableTestView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let window = NSWindow(
            contentRect: editorView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let controller = AttoCompletionListController()
        defer {
            controller.hide(restoreFocus: false)
            window.close()
        }

        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(editorView))

        controller.show(
            items: items,
            relativeTo: editorView,
            anchorRect: NSRect(x: 24, y: 300, width: 8, height: 18)
        ) { _, _ in }
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertTrue(panel.parent === window)
        XCTAssertEqual((panel as? NSPanel)?.isFloatingPanel, true)

        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertFalse(window.firstResponder === editorView)

        controller.hide()
        XCTAssertTrue(window.firstResponder === editorView)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }
}

private final class AttoFocusableTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
