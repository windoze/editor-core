import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewCommandClickTests: XCTestCase {
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

    private func makeMouseEvent(
        type: NSEvent.EventType,
        atViewBackingXPx xPx: Float,
        yPx: Float,
        in view: EditorCoreSkiaView,
        window: NSWindow,
        clickCount: Int = 1,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        let backingSize = view.convertToBacking(view.bounds.size)
        let sx = max(1, backingSize.width / max(1, view.bounds.size.width))
        let sy = max(1, backingSize.height / max(1, view.bounds.size.height))

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

    private func makeWindow(with view: NSView) -> NSWindow {
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
        return window
    }

    func testCmdOptionClickAddsCaretAndDoesNotCallOnCommandClick() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "ab\ncde\nf", viewportWidthCells: 80)
        let window = makeWindow(with: view)
        _ = window

        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        var called = 0
        view.onCommandClick = { _ in
            called += 1
            return true
        }

        let down = try makeMouseEvent(
            type: .leftMouseDown,
            atCharOffset: 4,
            in: view,
            window: window,
            modifierFlags: [.command, .option]
        )
        view.mouseDown(with: down)

        XCTAssertEqual(called, 0, "Cmd+Option+Click should be reserved for multi-cursor, not cmd-click hooks")

        let sel = try view.editor.selections()
        XCTAssertEqual(sel.ranges.count, 2, "expected Cmd+Option+Click to add a caret")
        XCTAssertTrue(sel.ranges.contains(where: { $0.start == 0 && $0.end == 0 }))
        XCTAssertTrue(sel.ranges.contains(where: { $0.start == 4 && $0.end == 4 }))
    }

    func testCmdClickInvokesOnCommandClickAndDoesNotMoveCaretWhenHandled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "ab\ncde\nf", viewportWidthCells: 80)
        let window = makeWindow(with: view)
        _ = window

        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        var called = 0
        view.onCommandClick = { ctx in
            called += 1
            XCTAssertEqual(ctx.charOffset, 4)
            XCTAssertEqual(ctx.logicalLine, 1)
            XCTAssertEqual(ctx.logicalColumn, 1)
            return true
        }

        let down = try makeMouseEvent(
            type: .leftMouseDown,
            atCharOffset: 4,
            in: view,
            window: window,
            modifierFlags: [.command]
        )
        view.mouseDown(with: down)

        XCTAssertEqual(called, 1)
        let offsets = try view.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 0)
        XCTAssertEqual(offsets.end, 0)
    }

    func testCmdClickOnCodeLensInvokesCodeLensHookBeforeCommandClick() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "line1\nline2\n", viewportWidthCells: 80)
        let window = makeWindow(with: view)
        _ = window

        try view.editor.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try view.editor.setViewportPx(widthPx: 400, heightPx: 80, scale: 1)
        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "command": { "title": "Run tests", "command": "test.run" }
          }
        ]
        """
        try view.editor.lspApplyCodeLensJSON(result)

        var codeLensJSON: String?
        var commandClickCount = 0
        view.onCodeLensClick = { json in
            codeLensJSON = json
            return true
        }
        view.onCommandClick = { _ in
            commandClickCount += 1
            return true
        }

        let down = try makeMouseEvent(
            type: .leftMouseDown,
            atViewBackingXPx: 5,
            yPx: 10,
            in: view,
            window: window,
            modifierFlags: [.command]
        )
        view.mouseDown(with: down)

        XCTAssertEqual(commandClickCount, 0)
        XCTAssertNotNil(codeLensJSON)
        XCTAssertTrue(codeLensJSON?.contains(#""command":"test.run""#) == true)

        let offsets = try view.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 0)
        XCTAssertEqual(offsets.end, 0)
    }

    func testCmdClickFallsBackToCaretMoveWhenNotHandled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "ab\ncde\nf", viewportWidthCells: 80)
        let window = makeWindow(with: view)
        _ = window

        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        var called = 0
        view.onCommandClick = { ctx in
            called += 1
            XCTAssertEqual(ctx.charOffset, 4)
            return false
        }

        let down = try makeMouseEvent(
            type: .leftMouseDown,
            atCharOffset: 4,
            in: view,
            window: window,
            modifierFlags: [.command]
        )
        view.mouseDown(with: down)

        XCTAssertEqual(called, 1)
        let offsets = try view.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 4)
    }
}
