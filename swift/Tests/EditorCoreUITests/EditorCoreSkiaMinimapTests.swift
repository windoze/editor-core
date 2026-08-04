import AppKit
@testable import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaMinimapTests: XCTestCase {
    func testMinimapContainerShowHideTogglesWidth() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(editorView: editorView, showsMinimap: true, minimapWidth: 100)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        XCTAssertFalse(container.minimapView.isHidden)
        XCTAssertGreaterThan(container._minimapWidthConstraintForTesting.constant, 0)

        container.showsMinimap = false
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(container.minimapView.isHidden)
        XCTAssertEqual(container._minimapWidthConstraintForTesting.constant, 0)
    }

    func testMinimapPlacementLeftOrRightMovesMinimapRelativeToScrollbar() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(
            editorView: editorView,
            showsMinimap: true,
            minimapWidth: 120,
            minimapPlacement: .rightOfScrollbar
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        // Right-of-scrollbar: minimap is hosted by the minimap container.
        XCTAssertTrue(container.minimapView.superview === container)

        container.minimapPlacement = .leftOfScrollbar
        container.layoutSubtreeIfNeeded()

        // Left-of-scrollbar: minimap becomes an accessory inside the scroll container.
        XCTAssertTrue(container.minimapView.superview === container.scrollContainer)

        let scrollerFrame = container.scrollContainer._verticalScrollerForTesting.frame
        let minimapFrame = container.minimapView.frame
        XCTAssertLessThanOrEqual(minimapFrame.maxX, scrollerFrame.minX + 0.5, "expected minimap to sit left of the scrollbar when configured")
    }

    func testMinimapViewRefreshLoadsGrid() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc", viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(editorView: editorView, showsMinimap: true, minimapWidth: 120)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView)
        container.layoutSubtreeIfNeeded()

        container.minimapView._refreshNowForTesting()
        let grid = try XCTUnwrap(container.minimapView._cachedGridForTesting)
        XCTAssertEqual(grid.actualLineCount, 3)
    }

    func testMinimapDiagnosticMarkersMapLogicalLinesToRects() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc\nd\n", viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(editorView: editorView, showsMinimap: true, minimapWidth: 120)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView)
        container.layoutSubtreeIfNeeded()

        let markers = [
            EditorCoreSkiaMinimapMarker(logicalLine: 1, kind: .warning),
            EditorCoreSkiaMinimapMarker(logicalLine: 3, kind: .error),
        ]
        container.minimapView.diagnosticMarkers = markers
        container.minimapView._refreshNowForTesting()

        XCTAssertEqual(container.minimapView._diagnosticMarkersForTesting, markers)
        let rects = try container.minimapView._diagnosticMarkerRectsForTesting()
        XCTAssertEqual(rects.count, 2)
        XCTAssertLessThan(rects[0].minY, rects[1].minY)
        XCTAssertGreaterThan(rects[0].width, 0)
        XCTAssertGreaterThan(rects[0].height, 0)
        XCTAssertEqual(rects[0].maxX, container.minimapView.bounds.width, accuracy: 0.5)
    }

    func testMinimapOpacityDefaultsToHalfAndIsConfigurable() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(editorView: editorView, showsMinimap: true, minimapWidth: 100)

        XCTAssertEqual(container.minimapOpacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(container.minimapView.alphaValue, 0.5, accuracy: 0.001)

        container.minimapOpacity = 0.8
        XCTAssertEqual(container.minimapView.alphaValue, 0.8, accuracy: 0.001)
    }

    func testMinimapDragMovesViewport() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let longText = (0..<400).map(String.init).joined(separator: "\n")
        let editorView = try EditorCoreSkiaView(library: lib, initialText: longText, viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(editorView: editorView, showsMinimap: true, minimapWidth: 120)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView)
        container.layoutSubtreeIfNeeded()

        let vp0 = try editorView.editor.viewportState()
        XCTAssertEqual(vp0.scrollTop, 0)
        XCTAssertGreaterThan(vp0.totalVisualLines, 0)

        let minimap = container.minimapView
        minimap.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(minimap.bounds.height, 10)

        func makeMouseEvent(type: NSEvent.EventType, viewPoint: NSPoint) throws -> NSEvent {
            let windowPoint = minimap.convert(viewPoint, to: nil)
            let event = NSEvent.mouseEvent(
                with: type,
                location: windowPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
            return try XCTUnwrap(event)
        }

        // Drag the viewport indicator down.
        let down = try makeMouseEvent(type: .leftMouseDown, viewPoint: NSPoint(x: 10, y: 6))
        minimap.mouseDown(with: down)

        let drag = try makeMouseEvent(
            type: .leftMouseDragged,
            viewPoint: NSPoint(x: 10, y: max(6, minimap.bounds.height - 6))
        )
        minimap.mouseDragged(with: drag)
        minimap.mouseUp(with: drag)

        let vp1 = try editorView.editor.viewportState()
        XCTAssertGreaterThan(vp1.scrollTop, vp0.scrollTop, "expected minimap dragging to scroll the editor viewport")
    }

    func testMinimapBarWidthReflectsLineLengthCoverage() {
        let widthPx: CGFloat = 100
        let viewportWidthCells: UInt32 = 80

        let short = EditorCoreSkiaMinimapView._minimapBarWidthPxForTesting(
            viewportWidthCells: viewportWidthCells,
            lineTotalCells: 10,
            widthPx: widthPx
        )
        let long = EditorCoreSkiaMinimapView._minimapBarWidthPxForTesting(
            viewportWidthCells: viewportWidthCells,
            lineTotalCells: 40,
            widthPx: widthPx
        )

        XCTAssertGreaterThan(long, short)
    }

    func testMinimapBarWidthClampsAndHasMinimum() {
        let widthPx: CGFloat = 100
        let viewportWidthCells: UInt32 = 80

        let empty = EditorCoreSkiaMinimapView._minimapBarWidthPxForTesting(
            viewportWidthCells: viewportWidthCells,
            lineTotalCells: 0,
            widthPx: widthPx
        )
        XCTAssertEqual(empty, 1)

        let huge = EditorCoreSkiaMinimapView._minimapBarWidthPxForTesting(
            viewportWidthCells: viewportWidthCells,
            lineTotalCells: 10_000,
            widthPx: widthPx
        )
        XCTAssertEqual(huge, 100)
    }
}
