import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoCoreWorkspaceDragProjectionTests: XCTestCase {
    func testSplitRightCreatesSharedDocumentPane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDragProjectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("split.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertEqual(findSubviews(of: EditorCoreSkiaView.self, in: vc.view).count, 1)
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(editorViews.count, 2)

        try editorViews[1].editor.insertText("!")
        XCTAssertEqual(try editorViews[0].editor.text(), "!abc")
        XCTAssertEqual(try editorViews[1].editor.text(), "!abc")

        let clickPoint = editorViews[0].convert(NSPoint(x: 5, y: 5), to: nil)
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        ) else {
            XCTFail("Unable to construct split pane mouseDown event")
            return
        }
        editorViews[0].mouseDown(with: mouseDown)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"?"}"#))
        XCTAssertEqual(try editorViews[0].editor.text(), "?!abc")
    }

    func testPaneFocusAndCloseCommandsUseActivePane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDragProjectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("panes.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()
        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(editorViews.count, 2)

        XCTAssertTrue(vc.focusPreviousPaneInActiveTab())
        XCTAssertTrue(vc.focusNextPaneInActiveTab())
        XCTAssertTrue(vc.closeActivePane())
        vc.view.layoutSubtreeIfNeeded()

        let remaining = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining[0] === editorViews[0])
        XCTAssertFalse(vc.closeActivePane())
    }

    func testPaneFocusUsesCoreActiveViewProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDragProjectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("focus-core-pane.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        XCTAssertTrue(vc.splitActiveTabRight())

        let tab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(tab.activePaneIndex, 1)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: 0)

        XCTAssertTrue(vc.focusNextPaneInActiveTab())
        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)
        XCTAssertEqual(tab.activePaneIndex, 1)
    }

    func testMovePaneCommandsReorderAppKitProjectionAndCoreMirror() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDragProjectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("move-panes.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.splitActiveTabRight())
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        let original = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(original.count, 3)

        XCTAssertTrue(vc.moveActivePaneLeft())
        vc.view.layoutSubtreeIfNeeded()
        var moved = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(moved.count, 3)
        XCTAssertTrue(moved[0] === original[0])
        XCTAssertTrue(moved[1] === original[2])
        XCTAssertTrue(moved[2] === original[1])
        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].viewCount, 3)
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)

        XCTAssertTrue(vc.moveActivePaneLeft())
        vc.view.layoutSubtreeIfNeeded()
        moved = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertTrue(moved[0] === original[2])
        XCTAssertTrue(moved[1] === original[0])
        XCTAssertTrue(moved[2] === original[1])
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 0)

        XCTAssertFalse(vc.moveActivePaneLeft())
        XCTAssertTrue(vc.moveActivePaneRight())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)
    }

    func testMoveAndClosePaneUseCoreActiveViewProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDragProjectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("move-core-pane.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.splitActiveTabRight())
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        let original = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(original.count, 3)
        let tab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(tab.activePaneIndex, 2)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: 0)

        XCTAssertTrue(vc.moveActivePaneRight())
        vc.view.layoutSubtreeIfNeeded()
        var moved = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(moved.count, 3)
        XCTAssertTrue(moved[0] === original[1])
        XCTAssertTrue(moved[1] === original[0])
        XCTAssertTrue(moved[2] === original[2])
        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)

        try coreDocuments.setActiveViewIndex(tabId: coreTabID, viewIndex: 0)
        XCTAssertTrue(vc.closeActivePane())
        vc.view.layoutSubtreeIfNeeded()

        moved = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(moved.count, 2)
        XCTAssertTrue(moved[0] === original[0])
        XCTAssertTrue(moved[1] === original[2])
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].viewCount, 2)
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 0)
    }

    func testTabDragReordersCoreTabProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDragProjectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-drag-tab.txt")
        let secondURL = tempDir.appendingPathComponent("second-drag-tab.txt")
        let thirdURL = tempDir.appendingPathComponent("third-drag-tab.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)
        vc.view.layoutSubtreeIfNeeded()

        let tabBar = try XCTUnwrap(findSubview(of: AttoTabBarView.self, in: vc.view))
        let firstChip = try XCTUnwrap(findTabChipView(title: "first-drag-tab.txt", in: tabBar))
        let thirdChip = try XCTUnwrap(findTabChipView(title: "third-drag-tab.txt", in: tabBar))
        let startPoint = firstChip.convert(
            NSPoint(x: firstChip.bounds.midX, y: firstChip.bounds.midY),
            to: nil
        )
        let endPoint = thirdChip.convert(
            NSPoint(x: thirdChip.bounds.maxX - 1, y: thirdChip.bounds.midY),
            to: nil
        )

        let mouseDown = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: startPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 10,
                clickCount: 1,
                pressure: 1
            )
        )
        let mouseDragged = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: endPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 11,
                clickCount: 1,
                pressure: 1
            )
        )
        let mouseUp = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: endPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 12,
                clickCount: 1,
                pressure: 0
            )
        )

        firstChip.mouseDown(with: mouseDown)
        firstChip.mouseDragged(with: mouseDragged)
        firstChip.mouseUp(with: mouseUp)

        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "second-drag-tab.txt",
            "third-drag-tab.txt",
            "first-drag-tab.txt",
        ])
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "second-drag-tab.txt",
            "third-drag-tab.txt",
            "first-drag-tab.txt",
        ])
        XCTAssertEqual(snapshot.tabs.first(where: { $0.isActive })?.title, "first-drag-tab.txt")
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL.standardizedFileURL
        )
    }

    @discardableResult
    private func attachToWindow(_ vc: AttoEditorAreaViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let view = root as? T {
            return view
        }
        for child in root.subviews {
            if let found = findSubview(of: type, in: child) {
                return found
            }
        }
        return nil
    }

    private func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var out: [T] = []
        if let view = root as? T {
            out.append(view)
        }
        for child in root.subviews {
            out.append(contentsOf: findSubviews(of: type, in: child))
        }
        return out
    }

    private func findTabChipView(title: String, in root: NSView) -> NSView? {
        findSubviews(of: NSView.self, in: root).first { view in
            view.subviews.contains { subview in
                (subview as? NSTextField)?.stringValue == title
            }
        }
    }
}
