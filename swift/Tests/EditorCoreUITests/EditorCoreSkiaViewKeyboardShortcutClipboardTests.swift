import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewKeyboardShortcutClipboardTests: XCTestCase {
    private func sendCmdKey(
        _ key: String,
        shift: Bool = false,
        to view: EditorCoreSkiaView,
        in window: NSWindow
    ) {
        var flags: NSEvent.ModifierFlags = [.command]
        if shift {
            flags.insert(.shift)
        }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key.lowercased(),
            isARepeat: false,
            keyCode: 0
        )
        XCTAssertNotNil(event, "failed to create key event")
        if let event {
            view.keyDown(with: event)
        }
    }

    func testCmdC_CmdX_CmdVWorkWithoutMenu() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "one two three", viewportWidthCells: 80)

        // Use a private pasteboard to avoid touching the user's real clipboard.
        let pb = NSPasteboard(name: NSPasteboard.Name("EditorCoreSkiaViewKeyboardShortcutClipboardTests-\(UUID().uuidString)"))
        pb.clearContents()
        view.pasteboard = pb

        // Put the view in a real window to match demo behavior.
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

        // Cmd+C copies selection.
        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)
        sendCmdKey("c", to: view, in: window)
        XCTAssertEqual(pb.string(forType: .string), "one")

        // Cmd+X cuts selection.
        try view.editor.setSelections([EcuSelectionRange(start: 4, end: 7)], primaryIndex: 0)
        sendCmdKey("x", to: view, in: window)
        XCTAssertEqual(pb.string(forType: .string), "two")
        XCTAssertEqual(try view.editor.text(), "one  three")

        // Cmd+V pastes at caret.
        pb.clearContents()
        pb.setString("XYZ", forType: .string)
        try view.editor.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        sendCmdKey("v", to: view, in: window)
        XCTAssertEqual(try view.editor.text(), "one XYZ three")
    }
}

