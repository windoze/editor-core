import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoCoreWorkspaceCommandTests: XCTestCase {
    func testCloseOtherTabsPreflightsDirtyTargetsBeforeCoreGroupClose() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close-other.txt")
        let secondURL = tempDir.appendingPathComponent("second-close-other.txt")
        let thirdURL = tempDir.appendingPathComponent("third-close-other.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer {
            vc._setDirtyCloseDecisionProviderForTesting(nil)
            window.close()
        }

        XCTAssertTrue(vc.openFile(url: firstURL, mode: .pinned))
        XCTAssertTrue(vc.openFile(url: secondURL, mode: .pinned))
        XCTAssertTrue(vc.openFile(url: thirdURL, mode: .pinned))

        let firstTab = try XCTUnwrap(vc.tabs.first {
            vc.projectedFileURL(for: $0) == firstURL.standardizedFileURL
        })
        let secondTab = try XCTUnwrap(vc.tabs.first {
            vc.projectedFileURL(for: $0) == secondURL.standardizedFileURL
        })
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)

        vc.selectTab(id: firstTab.id)
        try secondTab.editCore.editor.insertText("dirty ")
        XCTAssertTrue(vc.isTabDirtyForDataLossDecision(secondTab))

        var confirmationURLs: [URL] = []
        var closedURLs: [URL] = []
        vc._setDirtyCloseDecisionProviderForTesting { url in
            confirmationURLs.append(url.standardizedFileURL)
            return .cancel
        }
        vc.onDidCloseFile = { url in
            closedURLs.append(url.standardizedFileURL)
        }

        XCTAssertEqual(vc.closeOtherTabsForActiveTab(), 0)

        XCTAssertEqual(confirmationURLs, [secondURL.standardizedFileURL])
        XCTAssertTrue(closedURLs.isEmpty)
        XCTAssertEqual(vc.tabs.map { vc.projectedFileURL(for: $0).lastPathComponent }, [
            "first-close-other.txt",
            "second-close-other.txt",
            "third-close-other.txt",
        ])
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-close-other.txt",
            "second-close-other.txt",
            "third-close-other.txt",
        ])

        let snapshot = try coreDocuments.snapshot()
        XCTAssertEqual(snapshot.activeTabId, firstTab.coreTabID)
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-close-other.txt",
            "second-close-other.txt",
            "third-close-other.txt",
        ])
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
