import AppKit
@testable import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaScrollContainerTests: XCTestCase {
    func testScrollContainerUpdatesScrollerAndAppliesScrollState() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let longText = "a\nb\nc\n" + String(repeating: "x\n", count: 300)
        let editorView = try EditorCoreSkiaView(library: lib, initialText: longText, viewportWidthCells: 80)
        let container = EditorCoreSkiaScrollContainer(editorView: editorView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        container._updateScrollerForTesting()

        let scroller = container._verticalScrollerForTesting
        XCTAssertFalse(scroller.isHidden)
        XCTAssertLessThan(scroller.knobProportion, 1.0)
        XCTAssertEqual(scroller.doubleValue, 0.0, accuracy: 0.0001)

        // Drag the scroller to the middle and ensure the editor scroll position changes.
        container._applyScrollerProportionForTesting(0.5)
        container._updateScrollerForTesting()

        let vp = try editorView.editor.viewportState()
        XCTAssertGreaterThan(vp.scrollTop, 0)
        XCTAssertGreaterThan(container._verticalScrollerForTesting.doubleValue, 0.0)
    }

    func testScrollContainerTrackClickPagesSmoothly() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let longText = "a\nb\nc\n" + String(repeating: "x\n", count: 400)
        let editorView = try EditorCoreSkiaView(library: lib, initialText: longText, viewportWidthCells: 80)
        let container = EditorCoreSkiaScrollContainer(editorView: editorView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        let vp0 = try editorView.editor.viewportState()
        XCTAssertEqual(vp0.scrollTop, 0)

        let total = max(1.0, Double(vp0.totalVisualLines))
        let visible = Double(max(1, vp0.heightRows ?? vp0.totalVisualLines))
        let maxScroll = max(0.0, total - visible)
        XCTAssertGreaterThan(maxScroll, 0.0, "test requires a scrollable document")

        // Simulate a click in the empty track area (page down).
        container._requestPageScrollForTesting(direction: 1)

        // Advance a few animation frames manually (tests disable the internal timer).
        var sawFractional = false
        for _ in 0..<240 {
            container._pagingTickForTesting(mouseButtonsMask: 1)
            let vp = try editorView.editor.viewportState()
            if vp.subRowOffset != 0 { sawFractional = true }

            let pos = Double(vp.scrollTop) + Double(vp.subRowOffset) / 65536.0
            if abs(pos - min(visible, maxScroll)) < 0.75 {
                break
            }
        }

        let vp1 = try editorView.editor.viewportState()
        let pos1 = Double(vp1.scrollTop) + Double(vp1.subRowOffset) / 65536.0
        XCTAssertEqual(pos1, min(visible, maxScroll), accuracy: 0.75)
        XCTAssertTrue(sawFractional, "expected smooth paging to use sub-row offsets (fractional scroll)")

        // Stop the paging loop.
        container._stopPagingScrollForTesting()
    }

    func testScrollContainerTrackClickHoldRepeatsWhilePressed() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let longText = "a\nb\nc\n" + String(repeating: "x\n", count: 2_000)
        let editorView = try EditorCoreSkiaView(library: lib, initialText: longText, viewportWidthCells: 80)
        let container = EditorCoreSkiaScrollContainer(editorView: editorView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        let vp0 = try editorView.editor.viewportState()
        let visible = Double(max(1, vp0.heightRows ?? vp0.totalVisualLines))
        XCTAssertGreaterThan(vp0.totalVisualLines, UInt32(visible) + 50, "test requires a scrollable document")

        // Simulate: click track far below and keep mouse pressed (hold).
        container._beginTrackClickHoldForTesting(targetProportion: 0.99, direction: 1)
        container._requestPageScrollForTesting(direction: 1)

        var exceededOnePage = false
        for _ in 0..<600 {
            container._pagingTickForTesting(mouseButtonsMask: 1)
            let vp = try editorView.editor.viewportState()
            let pos = Double(vp.scrollTop) + Double(vp.subRowOffset) / 65536.0
            if pos > visible + max(1.0, visible * 0.25) {
                exceededOnePage = true
                break
            }
        }
        XCTAssertTrue(exceededOnePage, "expected holding track click to keep paging beyond a single page while mouse is pressed")
        container._stopPagingScrollForTesting()
    }

    func testScrollContainerTrackClickHoldStopsExtendingAfterRelease() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let longText = "a\nb\nc\n" + String(repeating: "x\n", count: 2_000)
        let editorView = try EditorCoreSkiaView(library: lib, initialText: longText, viewportWidthCells: 80)
        let container = EditorCoreSkiaScrollContainer(editorView: editorView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        let vp0 = try editorView.editor.viewportState()
        let visible = Double(max(1, vp0.heightRows ?? vp0.totalVisualLines))
        XCTAssertGreaterThan(vp0.totalVisualLines, UInt32(visible) + 50, "test requires a scrollable document")

        // Start a held track click, but release quickly before the first page finishes.
        container._beginTrackClickHoldForTesting(targetProportion: 0.99, direction: 1)
        container._requestPageScrollForTesting(direction: 1)
        container._pagingTickForTesting(mouseButtonsMask: 1)

        // Release: should stop *extending* to further pages, but still complete the current smooth page.
        container._pagingTickForTesting(mouseButtonsMask: 0)

        for _ in 0..<600 {
            if container._isPagingActiveForTesting == false { break }
            container._pagingTickForTesting(mouseButtonsMask: 0)
        }

        let vp1 = try editorView.editor.viewportState()
        let pos1 = Double(vp1.scrollTop) + Double(vp1.subRowOffset) / 65536.0
        XCTAssertEqual(pos1, visible, accuracy: 0.75, "expected a single page scroll after releasing the mouse")
    }
}
