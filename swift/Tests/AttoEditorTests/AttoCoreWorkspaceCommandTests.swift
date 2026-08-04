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

    func testPinActiveTabUsesCoreActivePreviewProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("pin-first.txt")
        let secondURL = tempDir.appendingPathComponent("pin-second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        vc.openFile(url: secondURL, mode: .preview)
        let secondTab = try XCTUnwrap(vc.activeTab)

        vc.selectTab(id: firstTab.id)
        XCTAssertEqual(vc.selectedTabID, firstTab.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let secondCoreTabID = try XCTUnwrap(secondTab.coreTabID)
        try coreDocuments.setActiveTab(secondCoreTabID)
        XCTAssertEqual(vc.activeTab?.id, secondTab.id)
        XCTAssertTrue(try coreDocuments.isPreviewTab(secondCoreTabID))
        XCTAssertTrue(secondTab.isPreview)

        XCTAssertTrue(vc.pinActiveTabIfPreview())

        XCTAssertFalse(try coreDocuments.isPreviewTab(secondCoreTabID))
        XCTAssertFalse(secondTab.isPreview)
        XCTAssertEqual(firstTab.isPreview, false)
        let secondItem = try XCTUnwrap(vc.openFileItems().first { $0.id == secondTab.id })
        XCTAssertFalse(secondItem.isPreview)
    }

    func testOpenPreviewUsesCorePreviewProjectionForReplacement() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-preview.txt")
        let secondURL = tempDir.appendingPathComponent("second-preview.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        XCTAssertTrue(vc.openFile(url: firstURL, mode: .preview))
        let firstTab = try XCTUnwrap(vc.activeTab)
        let firstTabID = firstTab.id
        let firstCoreTabID = try XCTUnwrap(firstTab.coreTabID)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.isPreviewTab(firstCoreTabID))

        firstTab.isPreview = false
        XCTAssertTrue(vc.openFile(url: secondURL, mode: .preview))

        XCTAssertFalse(vc.tabs.contains { $0.id == firstTabID })
        XCTAssertEqual(vc.tabs.count, 1)
        let replacementTab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(replacementTab.coreTabID, firstCoreTabID)
        XCTAssertEqual(replacementTab.fileURL.standardizedFileURL, secondURL.standardizedFileURL)
        XCTAssertTrue(try coreDocuments.isPreviewTab(firstCoreTabID))
        let items = vc.openFileItems()
        XCTAssertEqual(items.map { $0.url.standardizedFileURL }, [secondURL.standardizedFileURL])
        XCTAssertEqual(items.map(\.isPreview), [true])
        let snapshot = try coreDocuments.snapshot()
        XCTAssertEqual(snapshot.tabs.map(\.documentURI), [secondURL.standardizedFileURL.absoluteString])
        XCTAssertEqual(snapshot.tabs.map(\.isPreview), [true])
    }

    func testOpenPinnedExistingTabUsesCorePreviewProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("existing-preview.txt")
        try "preview".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        XCTAssertTrue(vc.openFile(url: fileURL, mode: .preview))
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.isPreviewTab(coreTabID))

        tab.isPreview = false
        XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned))

        XCTAssertEqual(vc.activeTab?.id, tab.id)
        XCTAssertFalse(tab.isPreview)
        XCTAssertFalse(try coreDocuments.isPreviewTab(coreTabID))
        let item = try XCTUnwrap(vc.openFileItems().first { $0.id == tab.id })
        XCTAssertFalse(item.isPreview)
    }

    func testMoveTabCommandsReorderAppKitProjectionAndCoreMirror() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-tab.txt")
        let secondURL = tempDir.appendingPathComponent("second-tab.txt")
        let thirdURL = tempDir.appendingPathComponent("third-tab.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-tab.txt",
            "second-tab.txt",
            "third-tab.txt",
        ])
        XCTAssertFalse(vc.moveActiveTabRight())

        XCTAssertTrue(vc.moveActiveTabLeft())
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-tab.txt",
            "third-tab.txt",
            "second-tab.txt",
        ])
        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-tab.txt",
            "third-tab.txt",
            "second-tab.txt",
        ])
        XCTAssertEqual(snapshot.tabs.first(where: { $0.isActive })?.title, "third-tab.txt")

        XCTAssertTrue(vc.moveActiveTabLeft())
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "third-tab.txt",
            "first-tab.txt",
            "second-tab.txt",
        ])
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "third-tab.txt",
            "first-tab.txt",
            "second-tab.txt",
        ])
        XCTAssertEqual(snapshot.tabs.first(where: { $0.isActive })?.title, "third-tab.txt")

        XCTAssertFalse(vc.moveActiveTabLeft())
        XCTAssertTrue(vc.moveActiveTabRight())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-tab.txt",
            "third-tab.txt",
            "second-tab.txt",
        ])
    }

    func testMoveTabCommandUsesCoreActiveTabProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-core-move.txt")
        let secondURL = tempDir.appendingPathComponent("second-core-move.txt")
        let thirdURL = tempDir.appendingPathComponent("third-core-move.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setActiveTab(try XCTUnwrap(secondTab.coreTabID))
        XCTAssertEqual(vc.selectedTabID, vc.tabs.last?.id)
        XCTAssertEqual(vc.activeTab?.id, secondTab.id)

        XCTAssertTrue(vc.moveActiveTabLeft())

        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "second-core-move.txt",
            "first-core-move.txt",
            "third-core-move.txt",
        ])
        XCTAssertEqual(snapshot.tabs.first(where: { $0.isActive })?.title, "second-core-move.txt")
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "second-core-move.txt",
            "first-core-move.txt",
            "third-core-move.txt",
        ])
    }

    func testSelectAndOpenFileUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-uri.txt")
        let secondURL = tempDir.appendingPathComponent("second-uri.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed-uri.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "renamed".write(to: renamedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)

        let firstTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == firstURL.standardizedFileURL })
        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        XCTAssertEqual(vc.selectedTabID, secondTab.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            renamedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(firstTab.coreTabID)
        )
        XCTAssertEqual(firstTab.fileURL.standardizedFileURL, firstURL.standardizedFileURL)
        XCTAssertTrue(vc.openFileItems().contains { $0.url.standardizedFileURL == renamedURL.standardizedFileURL })

        vc.selectFile(url: renamedURL)
        XCTAssertEqual(vc.selectedTabID, firstTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === firstTab.editCore })

        vc.selectFile(url: secondURL)
        XCTAssertEqual(vc.selectedTabID, secondTab.id)

        XCTAssertTrue(vc.openFile(url: renamedURL, mode: .pinned))
        XCTAssertEqual(vc.tabs.count, 2)
        XCTAssertEqual(vc.selectedTabID, firstTab.id)
        XCTAssertEqual(try coreDocuments.snapshot().tabs.count, 2)
    }

    func testOpenFileLocationUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-location-uri.txt")
        let secondURL = tempDir.appendingPathComponent("second-location-uri.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed-location-uri.txt")
        try "aa\nbb\ncc\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "renamed".write(to: renamedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)

        let firstTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == firstURL.standardizedFileURL })
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            renamedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(firstTab.coreTabID)
        )

        XCTAssertTrue(vc.openFile(
            url: renamedURL,
            mode: .pinned,
            location: .init(line1: 2, column1: 2)
        ))
        XCTAssertEqual(vc.tabs.count, 2)
        XCTAssertEqual(vc.selectedTabID, firstTab.id)

        let offsets = try firstTab.editCore.editor.selectionOffsets()
        let position = try firstTab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 1)
    }

    func testActiveTabProjectionUsesCoreActiveTabWhenAvailable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-active.txt")
        let secondURL = tempDir.appendingPathComponent("second-active.txt")
        let thirdURL = tempDir.appendingPathComponent("third-active.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)
        XCTAssertEqual(vc.selectedTabID, vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL }?.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let secondCoreTabID = try XCTUnwrap(secondTab.coreTabID)
        try coreDocuments.setActiveTab(secondCoreTabID)

        XCTAssertEqual(vc.activeTab?.id, secondTab.id)
        let keymapContext = vc.keymapContextForActiveState()
        XCTAssertEqual(keymapContext.values["file_name"], .string("second-active.txt"))
        XCTAssertEqual(keymapContext.values["file_extension"], .string("txt"))

        vc.updateWindowTitle()
        XCTAssertEqual(window.title, "AttoEditor — second-active.txt")
    }

    func testRefreshTabBarProjectsAppKitContentToCoreActiveTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-content.txt")
        let secondURL = tempDir.appendingPathComponent("second-content.txt")
        let thirdURL = tempDir.appendingPathComponent("third-content.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let thirdTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL })
        XCTAssertEqual(vc.selectedTabID, thirdTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === thirdTab.editCore })

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setActiveTab(try XCTUnwrap(secondTab.coreTabID))
        XCTAssertEqual(vc.activeTab?.id, secondTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === thirdTab.editCore })

        vc.refreshTabBar()

        XCTAssertEqual(vc.selectedTabID, secondTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === secondTab.editCore })
        XCTAssertFalse(vc.contentHostView.subviews.contains { $0 === thirdTab.editCore })
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
