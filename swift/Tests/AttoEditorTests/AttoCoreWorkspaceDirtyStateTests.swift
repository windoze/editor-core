import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoCoreWorkspaceDirtyStateTests: XCTestCase {
    func testDirtyCloseConfirmationUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDirtyStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("dirty-close-local.txt")
        let projectedURL = tempDir.appendingPathComponent("dirty-close-projected.txt")
        try "local".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)
        try tab.editCore.editor.insertText(" dirty")
        XCTAssertTrue(vc.isTabDirtyForDataLossDecision(tab))

        var confirmationURL: URL?
        vc._setDirtyCloseDecisionProviderForTesting { url in
            confirmationURL = url.standardizedFileURL
            return .dontSave
        }

        vc.closeTab(id: tab.id)

        XCTAssertEqual(confirmationURL, projectedURL.standardizedFileURL)
        XCTAssertTrue(vc.tabs.isEmpty)
    }

    func testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDirtyStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-opened.txt")
        let secondURL = tempDir.appendingPathComponent("second-opened.txt")
        let thirdURL = tempDir.appendingPathComponent("third-opened.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let secondCoreTabID = try XCTUnwrap(secondTab.coreTabID)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 2, toIndex: 0))
        try coreDocuments.setActiveTab(secondCoreTabID)
        try coreDocuments.replaceTabText(tabId: secondCoreTabID, text: "second dirty", markSaved: false)

        let items = vc.openFileItems()
        XCTAssertEqual(items.map { $0.url.lastPathComponent }, [
            "third-opened.txt",
            "first-opened.txt",
            "second-opened.txt",
        ])
        let dirtyItem = try XCTUnwrap(items.first { $0.url.standardizedFileURL == secondURL.standardizedFileURL })
        XCTAssertTrue(dirtyItem.isDirty)
        XCTAssertEqual(dirtyItem.title, "● second-opened.txt")

        var callbackItems: [AttoEditorAreaViewController.OpenFileItem] = []
        var callbackSelectedID: UUID?
        vc.onOpenFilesChanged = { items, selectedID in
            callbackItems = items
            callbackSelectedID = selectedID
        }
        vc.refreshTabBar()

        XCTAssertEqual(callbackItems.map { $0.url.lastPathComponent }, [
            "third-opened.txt",
            "first-opened.txt",
            "second-opened.txt",
        ])
        XCTAssertEqual(callbackSelectedID, secondTab.id)
    }

    func testReloadActiveTabUsesCoreDocumentURIProjectionAndSyncsCoreDirtyState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDirtyStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("reload-local-tab.txt")
        let projectedURL = tempDir.appendingPathComponent("reload-projected-tab.txt")
        try "local disk\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected disk\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.activeTab)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: coreTabID
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"unsaved "}"#))
        XCTAssertTrue(try coreDocuments.isTabModified(coreTabID))
        XCTAssertNotEqual(try tab.editCore.editor.text(), "projected disk\n")

        XCTAssertTrue(vc.reloadActiveTab(discardingUnsavedChanges: true))

        XCTAssertEqual(try tab.editCore.editor.text(), "projected disk\n")
        XCTAssertEqual(try coreDocuments.tabText(tabId: coreTabID), "projected disk\n")
        XCTAssertFalse(try coreDocuments.isTabModified(coreTabID))
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let snapshotTab = try XCTUnwrap(try coreDocuments.snapshot().tabs.first { $0.id == coreTabID })
        XCTAssertEqual(snapshotTab.documentURI, projectedURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(snapshotTab.title, "reload-projected-tab.txt")

        let item = try XCTUnwrap(vc.openFileItems().first { $0.id == tab.id })
        XCTAssertEqual(item.url.standardizedFileURL, projectedURL.standardizedFileURL)
        XCTAssertFalse(item.isDirty)
        XCTAssertEqual(item.title, "reload-projected-tab.txt")
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Reloaded reload-projected-tab.txt")
    }

    func testSaveActiveTabUsesCoreDocumentURIProjectionAndSyncsCoreDirtyState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDirtyStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("save-local-tab.txt")
        let projectedURL = tempDir.appendingPathComponent("save-projected-tab.txt")
        try "local disk\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected old\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.activeTab)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: coreTabID
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        var savedCallback: (url: URL, createdOnDisk: Bool)?
        vc.onDidSaveFile = { url, createdOnDisk in
            savedCallback = (url.standardizedFileURL, createdOnDisk)
        }

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"saved "}"#))
        XCTAssertTrue(try coreDocuments.isTabModified(coreTabID))

        vc.saveActiveTab()

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "local disk\n")
        XCTAssertEqual(try String(contentsOf: projectedURL, encoding: .utf8), "saved local disk\n")
        XCTAssertEqual(try tab.editCore.editor.text(), "saved local disk\n")
        XCTAssertEqual(try coreDocuments.tabText(tabId: coreTabID), "saved local disk\n")
        XCTAssertFalse(try coreDocuments.isTabModified(coreTabID))
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let snapshotTab = try XCTUnwrap(try coreDocuments.snapshot().tabs.first { $0.id == coreTabID })
        XCTAssertEqual(snapshotTab.documentURI, projectedURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(snapshotTab.title, "save-projected-tab.txt")

        let item = try XCTUnwrap(vc.openFileItems().first { $0.id == tab.id })
        XCTAssertEqual(item.url.standardizedFileURL, projectedURL.standardizedFileURL)
        XCTAssertFalse(item.isDirty)
        XCTAssertEqual(item.title, "save-projected-tab.txt")
        XCTAssertEqual(savedCallback?.url, projectedURL.standardizedFileURL)
        XCTAssertEqual(savedCallback?.createdOnDisk, false)
    }

    func testSaveAllDirtyTabsUsesCoreTabProjectionOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceDirtyStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-save-all.txt")
        let secondURL = tempDir.appendingPathComponent("second-save-all.txt")
        let thirdURL = tempDir.appendingPathComponent("third-save-all.txt")
        try "first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second\n".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third\n".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"dirty "}"#))
        vc.openFile(url: secondURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"dirty "}"#))
        vc.openFile(url: thirdURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"dirty "}"#))

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 2, toIndex: 0))
        XCTAssertEqual(try coreDocuments.snapshot().tabs.map(\.title), [
            "third-save-all.txt",
            "first-save-all.txt",
            "second-save-all.txt",
        ])

        var savedURLs: [URL] = []
        vc.onDidSaveFile = { url, _ in
            savedURLs.append(url.standardizedFileURL)
        }

        XCTAssertTrue(vc.saveAllDirtyTabs())

        XCTAssertEqual(savedURLs, [
            thirdURL.standardizedFileURL,
            firstURL.standardizedFileURL,
            secondURL.standardizedFileURL,
        ])
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "dirty first\n")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "dirty second\n")
        XCTAssertEqual(try String(contentsOf: thirdURL, encoding: .utf8), "dirty third\n")
        XCTAssertTrue(try coreDocuments.snapshot().tabs.allSatisfy { $0.isModified == false })
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
