import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoCoreWorkspaceSessionRestoreTests: XCTestCase {
    func testSessionRestoreProjectsCoreTabsIntoSwiftAndAppKitState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceSessionRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-session.txt")
        let secondURL = tempDir.appendingPathComponent("second-session.txt")
        try "first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let tabSnapshots = [
            AttoTabSnapshot(
                filePath: firstURL.path,
                isPreview: false,
                showsMinimap: true,
                paneCount: 1,
                activePaneIndex: 0,
                paneLayout: AttoPaneLayoutSnapshot.horizontalSplit(paneCount: 2, activePaneIndex: 1)
            ),
            AttoTabSnapshot(
                filePath: secondURL.path,
                isPreview: true,
                showsMinimap: false,
                paneCount: 1,
                activePaneIndex: 0,
                paneLayout: AttoPaneLayoutSnapshot.horizontalSplit(paneCount: 1, activePaneIndex: 0)
            ),
        ]

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }

        var projectedSelections: [UUID?] = []
        vc.onOpenFilesChanged = { _, selectedID in
            projectedSelections.append(selectedID)
        }

        vc.restoreSession(tabs: tabSnapshots, selectedTabIndex: 1)
        vc.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(vc.tabs.count, 2)
        let restoredFirst = try XCTUnwrap(vc.tabs.first {
            vc.projectedFileURL(for: $0) == firstURL.standardizedFileURL
        })
        let restoredSecond = try XCTUnwrap(vc.tabs.first {
            vc.projectedFileURL(for: $0) == secondURL.standardizedFileURL
        })

        XCTAssertEqual(vc.selectedTabID, restoredSecond.id)
        XCTAssertEqual(vc.activeTab?.id, restoredSecond.id)
        XCTAssertEqual(projectedSelections.last ?? nil, restoredSecond.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === restoredSecond.editCore })
        XCTAssertFalse(vc.contentHostView.subviews.contains { $0 === restoredFirst.editCore })

        let items = vc.openFileItems()
        XCTAssertEqual(items.map(\.id), [restoredFirst.id, restoredSecond.id])
        XCTAssertEqual(items.map { $0.url.standardizedFileURL }, [
            firstURL.standardizedFileURL,
            secondURL.standardizedFileURL,
        ])
        XCTAssertEqual(items.map(\.isPreview), [false, true])

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreSnapshot = try coreDocuments.snapshot()
        XCTAssertEqual(coreSnapshot.activeTabId, restoredSecond.coreTabID)
        XCTAssertEqual(coreSnapshot.tabs.map(\.documentURI), [
            firstURL.standardizedFileURL.absoluteString,
            secondURL.standardizedFileURL.absoluteString,
        ])
        XCTAssertEqual(coreSnapshot.tabs.map(\.isPreview), [false, true])

        let coreFirst = try XCTUnwrap(coreSnapshot.tabs.first { $0.id == restoredFirst.coreTabID })
        XCTAssertEqual(coreFirst.viewCount, 2)
        XCTAssertEqual(coreFirst.activeViewIndex, 1)

        let coreSecond = try XCTUnwrap(coreSnapshot.tabs.first { $0.id == restoredSecond.coreTabID })
        XCTAssertEqual(coreSecond.viewCount, 1)
        XCTAssertEqual(coreSecond.activeViewIndex, 0)
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
}
