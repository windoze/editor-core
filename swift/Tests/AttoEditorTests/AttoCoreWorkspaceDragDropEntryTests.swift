import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoCoreWorkspaceDragDropEntryTests: XCTestCase {
    func testDraggingTabBelowTabBarDropsItIntoSplit() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-tab-split.txt")
        let secondURL = tempDir.appendingPathComponent("second-tab-split.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.view.layoutSubtreeIfNeeded()

        let tabBar = try XCTUnwrap(findSubview(of: AttoTabBarView.self, in: vc.view))
        let secondChip = try XCTUnwrap(findTabChipView(title: "second-tab-split.txt", in: tabBar))
        let startPoint = secondChip.convert(
            NSPoint(x: secondChip.bounds.midX, y: secondChip.bounds.midY),
            to: nil
        )
        let dropPoint = vc.contentHostView.convert(
            NSPoint(x: vc.contentHostView.bounds.midX, y: vc.contentHostView.bounds.maxY - 24),
            to: nil
        )

        secondChip.mouseDown(with: try mouseEvent(.leftMouseDown, point: startPoint, window: window, number: 20))
        secondChip.mouseDragged(with: try mouseEvent(.leftMouseDragged, point: dropPoint, window: window, number: 21))
        secondChip.mouseUp(with: try mouseEvent(.leftMouseUp, point: dropPoint, window: window, number: 22))
        vc.view.layoutSubtreeIfNeeded()

        let activeTab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(activeTab.fileURL.lastPathComponent, "second-tab-split.txt")
        XCTAssertEqual(activeTab.panes.count, 2)
        XCTAssertEqual(findSubviews(of: EditorCoreSkiaView.self, in: vc.view).count, 2)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(activeTab.coreTabID)
        XCTAssertEqual(try coreDocuments.viewCount(tabId: coreTabID), 2)

        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-tab-split.txt",
            "second-tab-split.txt",
        ])
        let splitTab = try XCTUnwrap(snapshot.tabs.first { $0.title == "second-tab-split.txt" })
        XCTAssertTrue(splitTab.isActive)
        XCTAssertEqual(splitTab.viewCount, 2)
        XCTAssertEqual(splitTab.activeViewIndex, 1)
    }

    func testSplitDropReordersPaneProjectionThroughCore() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("pane-drop.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        XCTAssertTrue(vc.splitActiveTabRight())
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        let original = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(original.count, 3)

        XCTAssertTrue(vc.dropPaneInActiveTab(fromProjectedIndex: 0, toProjectedIndex: 2))
        vc.view.layoutSubtreeIfNeeded()

        let moved = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(moved.count, 3)
        XCTAssertTrue(moved[0] === original[1])
        XCTAssertTrue(moved[1] === original[2])
        XCTAssertTrue(moved[2] === original[0])

        let activeTab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(activeTab.activePaneIndex, 2)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(activeTab.coreTabID)
        XCTAssertEqual(try coreDocuments.viewCount(tabId: coreTabID), 3)

        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        let tabSnapshot = try XCTUnwrap(snapshot.tabs.first)
        XCTAssertEqual(tabSnapshot.viewCount, 3)
        XCTAssertEqual(tabSnapshot.activeViewIndex, 2)
    }

    private func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDragDropEntryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
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

    private func mouseEvent(
        _ type: NSEvent.EventType,
        point: NSPoint,
        window: NSWindow,
        number: Int
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )
        )
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
