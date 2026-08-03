import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorVisualLayoutTests: XCTestCase {
    func testEditorChromeLayoutInvariantsForEmptyFindAndReplaceStates() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("layout.txt")
        try "first line\nsecond line\nthird line\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc, size: NSSize(width: 960, height: 640))
        defer { window.close() }

        assertChromeFrames(
            in: vc,
            expectedRootSize: NSSize(width: 960, height: 640),
            expectedFindHeight: 0
        )
        let emptyState = try XCTUnwrap(findView(identifier: AttoAccessibilityID.editorEmptyState, in: vc.view))
        XCTAssertTrue(vc.contentHostView.subviews.contains(emptyState))
        assertFrameCentered(emptyState.frame, in: vc.contentHostView.bounds)

        XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned, location: nil))
        vc.view.layoutSubtreeIfNeeded()
        assertChromeFrames(
            in: vc,
            expectedRootSize: NSSize(width: 960, height: 640),
            expectedFindHeight: 0
        )

        let opened = try XCTUnwrap(vc.openFileItems().first)
        let pane = try XCTUnwrap(findView(identifier: AttoAccessibilityID.editorPane(opened.id), in: vc.view) as? EditCoreUI)
        assertFrameFillsSuperview(pane, vc.contentHostView)
        XCTAssertGreaterThan(pane.editorView.frame.width, 200)
        XCTAssertGreaterThan(pane.editorView.frame.height, 200)

        vc.showFindBar()
        assertChromeFrames(
            in: vc,
            expectedRootSize: NSSize(width: 960, height: 640),
            expectedFindHeight: 42
        )
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.findSearchField, in: vc.findReplaceBarView) as? NSSearchField
        )
        XCTAssertFalse(searchField.isHidden)
        XCTAssertGreaterThanOrEqual(searchField.frame.width, 220)

        vc.showReplaceBar()
        assertChromeFrames(
            in: vc,
            expectedRootSize: NSSize(width: 960, height: 640),
            expectedFindHeight: 76
        )
        let replaceField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.findReplaceField, in: vc.findReplaceBarView) as? NSTextField
        )
        XCTAssertFalse(replaceField.isHidden)
        XCTAssertGreaterThanOrEqual(replaceField.frame.width, 180)

        window.setContentSize(NSSize(width: 720, height: 480))
        vc.view.layoutSubtreeIfNeeded()
        assertChromeFrames(
            in: vc,
            expectedRootSize: NSSize(width: 720, height: 480),
            expectedFindHeight: 76
        )
        XCTAssertGreaterThan(vc.contentHostView.frame.height, 250)
        assertStatusBarLabelsStayInsideStatusBar(vc.statusBarView)
    }

    func testSplitPaneLayoutFillsContentHostWithoutOverlap() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("split-layout.txt")
        try "abc\ndef\nghi\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc, size: NSSize(width: 960, height: 640))
        defer { window.close() }

        XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned, location: nil))
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        assertChromeFrames(
            in: vc,
            expectedRootSize: NSSize(width: 960, height: 640),
            expectedFindHeight: 0
        )

        let splitView = try XCTUnwrap(findSubview(of: NSSplitView.self, in: vc.contentHostView))
        splitView.layoutSubtreeIfNeeded()
        assertFrameFillsSuperview(splitView, vc.contentHostView)
        XCTAssertTrue(splitView.isVertical)
        XCTAssertEqual(splitView.arrangedSubviews.count, 2)

        let panes = splitView.arrangedSubviews.compactMap { $0 as? EditCoreUI }
        XCTAssertEqual(panes.count, 2)
        panes.forEach { $0.layoutSubtreeIfNeeded() }
        let orderedPanes = panes.sorted { $0.frame.minX < $1.frame.minX }
        let first = orderedPanes[0].frame
        let second = orderedPanes[1].frame

        XCTAssertGreaterThan(first.width, 100)
        XCTAssertGreaterThan(second.width, 100)
        assertClose(first.minY, splitView.bounds.minY)
        assertClose(second.minY, splitView.bounds.minY)
        assertClose(first.height, splitView.bounds.height)
        assertClose(second.height, splitView.bounds.height)
        XCTAssertLessThanOrEqual(first.maxX, second.minX + 1)
        assertClose(first.minX, splitView.bounds.minX)
        assertClose(second.maxX, splitView.bounds.maxX)

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(editorViews.count, 2)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorVisualLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL
        )
    }

    private func attachToWindow(
        _ vc: AttoEditorAreaViewController,
        size: NSSize
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.setContentSize(size)
        vc.view.frame = NSRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func assertChromeFrames(
        in vc: AttoEditorAreaViewController,
        expectedRootSize: NSSize,
        expectedFindHeight: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        vc.view.layoutSubtreeIfNeeded()

        let rootBounds = vc.view.bounds
        assertClose(rootBounds.width, expectedRootSize.width, file: file, line: line)
        assertClose(rootBounds.height, expectedRootSize.height, file: file, line: line)

        let tab = vc.tabBarView.frame
        let find = vc.findReplaceBarView.frame
        let content = vc.contentHostView.frame
        let status = vc.statusBarView.frame

        assertClose(tab.height, 30, file: file, line: line)
        assertClose(status.height, 20, file: file, line: line)
        assertClose(find.height, expectedFindHeight, file: file, line: line)

        assertClose(tab.maxY, rootBounds.maxY, file: file, line: line)
        assertClose(find.maxY, tab.minY, file: file, line: line)
        assertClose(content.maxY, find.minY, file: file, line: line)
        assertClose(content.minY, status.maxY, file: file, line: line)
        assertClose(status.minY, rootBounds.minY, file: file, line: line)

        for frame in [tab, find, content, status] {
            assertClose(frame.minX, rootBounds.minX, file: file, line: line)
            assertClose(frame.maxX, rootBounds.maxX, file: file, line: line)
        }
        XCTAssertGreaterThan(content.height, 0, file: file, line: line)
    }

    private func assertFrameFillsSuperview(
        _ view: NSView,
        _ superview: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertClose(view.frame.minX, superview.bounds.minX, file: file, line: line)
        assertClose(view.frame.minY, superview.bounds.minY, file: file, line: line)
        assertClose(view.frame.width, superview.bounds.width, file: file, line: line)
        assertClose(view.frame.height, superview.bounds.height, file: file, line: line)
    }

    private func assertFrameCentered(
        _ frame: NSRect,
        in bounds: NSRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertClose(frame.midX, bounds.midX, accuracy: 1, file: file, line: line)
        assertClose(frame.midY, bounds.midY, accuracy: 1, file: file, line: line)
    }

    private func assertStatusBarLabelsStayInsideStatusBar(
        _ statusBar: AttoStatusBarView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let labelFrames = allSubviews(in: statusBar)
            .compactMap { $0 as? NSTextField }
            .filter { $0.isHidden == false }
            .map { $0.convert($0.bounds, to: statusBar) }
            .filter { $0.width > 0 && $0.height > 0 }

        XCTAssertFalse(labelFrames.isEmpty, file: file, line: line)
        for frame in labelFrames {
            XCTAssertGreaterThanOrEqual(frame.minX, statusBar.bounds.minX - 1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, statusBar.bounds.maxX + 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, statusBar.bounds.minY - 1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, statusBar.bounds.maxY + 1, file: file, line: line)
        }
    }

    private func assertClose(
        _ actual: CGFloat,
        _ expected: CGFloat,
        accuracy: CGFloat = 0.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Double(actual), Double(expected), accuracy: Double(accuracy), file: file, line: line)
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let found = findView(identifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T {
            return v
        }
        for subview in root.subviews {
            if let found = findSubview(of: type, in: subview) {
                return found
            }
        }
        return nil
    }

    private func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var result: [T] = []
        if let v = root as? T {
            result.append(v)
        }
        for subview in root.subviews {
            result.append(contentsOf: findSubviews(of: type, in: subview))
        }
        return result
    }

    private func allSubviews(in root: NSView) -> [NSView] {
        root.subviews + root.subviews.flatMap { allSubviews(in: $0) }
    }
}
