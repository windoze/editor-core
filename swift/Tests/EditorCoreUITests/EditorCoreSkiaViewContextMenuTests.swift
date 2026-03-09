import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewContextMenuTests: XCTestCase {
    private func makeRightMouseDownEvent(
        atCharOffset offset: UInt32,
        in view: EditorCoreSkiaView,
        window: NSWindow
    ) throws -> NSEvent {
        let p = try view.editor.charOffsetToViewPoint(offset: offset)

        let backingSize = view.convertToBacking(view.bounds.size)
        let sx = max(1, backingSize.width / max(1, view.bounds.size.width))
        let sy = max(1, backingSize.height / max(1, view.bounds.size.height))

        let xPx = p.xPx + 1
        let yPx = p.yPx + p.lineHeightPx * 0.5
        let viewPoint = NSPoint(x: CGFloat(xPx) / sx, y: CGFloat(yPx) / sy)
        let windowPoint = view.convert(viewPoint, to: nil)

        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
        XCTAssertNotNil(event)
        return try XCTUnwrap(event)
    }

    private func findItem(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first(where: { $0.title == title })
    }

    func testDefaultContextMenuEnablesItemsBasedOnSelectionAndPasteboard() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "one two", viewportWidthCells: 80)

        let pb = NSPasteboard(name: NSPasteboard.Name("EditorCoreSkiaViewContextMenuTests-\(UUID().uuidString)"))
        pb.clearContents()
        view.pasteboard = pb

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

        // No selection => Cut/Copy disabled, Paste disabled.
        let event0 = try makeRightMouseDownEvent(atCharOffset: 0, in: view, window: window)
        let menu0 = try XCTUnwrap(view.menu(for: event0))
        XCTAssertEqual(findItem("Cut", in: menu0)?.isEnabled, false)
        XCTAssertEqual(findItem("Copy", in: menu0)?.isEnabled, false)
        XCTAssertEqual(findItem("Paste", in: menu0)?.isEnabled, false)
        XCTAssertEqual(findItem("Select All", in: menu0)?.isEnabled, true)

        // Non-empty selection => Cut/Copy enabled.
        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)
        let menu1 = try XCTUnwrap(view.menu(for: event0))
        XCTAssertEqual(findItem("Cut", in: menu1)?.isEnabled, true)
        XCTAssertEqual(findItem("Copy", in: menu1)?.isEnabled, true)

        // Pasteboard contains text => Paste enabled.
        pb.clearContents()
        pb.setString("XYZ", forType: .string)
        let menu2 = try XCTUnwrap(view.menu(for: event0))
        XCTAssertEqual(findItem("Paste", in: menu2)?.isEnabled, true)
    }

    func testContextMenuProviderOverridesDefault() throws {
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

        var captured: EditorCoreSkiaContextMenuContext?
        view.contextMenuProvider = { ctx in
            captured = ctx
            let menu = NSMenu(title: "Custom")
            menu.addItem(NSMenuItem(title: "Hello", action: nil, keyEquivalent: ""))
            return menu
        }

        let event = try makeRightMouseDownEvent(atCharOffset: 4, in: view, window: window)
        let menu = try XCTUnwrap(view.menu(for: event))
        XCTAssertEqual(menu.title, "Custom")
        XCTAssertEqual(menu.items.first?.title, "Hello")

        let ctx = try XCTUnwrap(captured)
        XCTAssertEqual(ctx.charOffset, 4)
        XCTAssertEqual(ctx.logicalLine, 1)
        XCTAssertEqual(ctx.logicalColumn, 1)
    }
}

