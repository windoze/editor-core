import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testApplySnippetCommandUsesPrimarySelection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("snippet.txt")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.applySnippetInActiveTab("println!(${1:msg})$0"))
        XCTAssertEqual(try editorView.editor.text(), "println!(msg)")
        XCTAssertTrue(try editorView.editor.hasActiveSnippetSession())
    }

    func testAddOccurrenceCommandsUseFindSearchOptions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("occurrences.txt")
        try "foo Foo foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        vc.showFindBar()

        let caseSensitiveButton = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.findCaseSensitiveButton, in: vc.view) as? NSButton
        )
        caseSensitiveButton.state = .off

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)

        XCTAssertTrue(vc.addAllOccurrencesInActiveTab())
        XCTAssertEqual(try editorView.editor.selections().ranges.count, 3)
    }

    func testSettingsCommandsCreateAndOpenSettingsFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceRootURL = tempDir.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settingsStore = AttoConfigurationSettingsStore(
            userSettingsURL: tempDir.appendingPathComponent("user-settings.json")
        )
        let delegate = AttoAppDelegate(
            keyBindings: [:],
            configurationSettingsStore: settingsStore
        )
        let ctx = delegate._createWindowForTesting(workspaceRootURL: workspaceRootURL)
        defer { ctx.window.close() }

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "settings.open_workspace_settings"))
        XCTAssertTrue(delegate.executeCommand(id: "settings.open_workspace_settings"))

        let workspaceSettingsURL = AttoConfigurationSettingsStore.workspaceSettingsURL(
            forWorkspaceRootURL: workspaceRootURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceSettingsURL.path))
        var settingsText = try String(contentsOf: workspaceSettingsURL, encoding: .utf8)
        XCTAssertTrue(settingsText.contains(#""_examples""#), settingsText)
        XCTAssertTrue(settingsText.contains(#""scoped_settings""#), settingsText)
        let workspaceSettings = try XCTUnwrap(
            settingsStore.loadWorkspaceSettings(workspaceRootURL: workspaceRootURL)
        )
        XCTAssertEqual(workspaceSettings.schemaVersion, AttoConfigurationSettings.currentSchemaVersion)
        XCTAssertEqual(workspaceSettings.scopedSettings, [])
        XCTAssertEqual(
            ctx.editorAreaController.activeTab?.fileURL.standardizedFileURL,
            workspaceSettingsURL.standardizedFileURL
        )
        XCTAssertEqual(ctx.editorAreaController._transientStatusTextForTesting(), "Opened Workspace Settings")

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "settings.open_user_settings"))
        XCTAssertTrue(delegate.executeCommand(id: "settings.open_user_settings"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsStore.userSettingsURL.path))
        settingsText = try String(contentsOf: settingsStore.userSettingsURL, encoding: .utf8)
        XCTAssertTrue(settingsText.contains(#""_examples""#), settingsText)
        let userSettings = try XCTUnwrap(settingsStore.loadUserSettings())
        XCTAssertEqual(userSettings.schemaVersion, AttoConfigurationSettings.currentSchemaVersion)
        XCTAssertEqual(userSettings.scopedSettings, [])
        XCTAssertEqual(
            ctx.editorAreaController.activeTab?.fileURL.standardizedFileURL,
            settingsStore.userSettingsURL.standardizedFileURL
        )
        XCTAssertEqual(ctx.editorAreaController._transientStatusTextForTesting(), "Opened User Settings")
    }

    func testReloadFileCommandReloadsActiveTabFromDisk() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("reload-command.txt")
        try "before\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(ctx.editorAreaController.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)

        try "after\n".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "file.reload"))
        XCTAssertTrue(delegate.executeCommand(id: "file.reload"))
        XCTAssertEqual(try tab.editCore.editor.text(), "after\n")
        XCTAssertEqual(try ctx.editorAreaController.coreDocuments?.tabText(tabId: coreTabID), "after\n")
        XCTAssertEqual(try ctx.editorAreaController.coreDocuments?.isTabModified(coreTabID), false)
        XCTAssertEqual(ctx.editorAreaController._transientStatusTextForTesting(), "Reloaded reload-command.txt")
    }

    func testPinTabCommandPinsActivePreviewTab() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("pin-command.txt")
        try "preview\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .preview)
        let tab = try XCTUnwrap(ctx.editorAreaController.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let coreDocuments = try XCTUnwrap(ctx.editorAreaController.coreDocuments)
        XCTAssertTrue(tab.isPreview)
        XCTAssertTrue(try coreDocuments.isPreviewTab(coreTabID))

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "file.pin_tab"))
        XCTAssertTrue(delegate.executeCommand(id: "file.pin_tab"))

        XCTAssertFalse(tab.isPreview)
        XCTAssertFalse(try coreDocuments.isPreviewTab(coreTabID))
        let item = try XCTUnwrap(ctx.editorAreaController.openFileItems().first { $0.id == tab.id })
        XCTAssertFalse(item.isPreview)
    }

    func testCursorMovementCommandsUseRegisteredCommandPath() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let text = "abc def\nghi jkl\n"
        let fileURL = tempDir.appendingPathComponent("cursor.txt")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_word_right"))
        var offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 3)
        XCTAssertEqual(offsets.end, 3)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_right"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 4)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.select_word_right"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 7)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_left"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 4)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.document_end"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, UInt32(text.count))
        XCTAssertEqual(offsets.end, UInt32(text.count))

        XCTAssertTrue(delegate.executeCommand(id: "cursor.select_document_start"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 0)
        XCTAssertEqual(offsets.end, UInt32(text.count))
    }

    func testActiveEditorCommandJSONMutatesTextAndDirtyState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("a.txt")
        try "a\nb\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"duplicate_lines"}"#))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "a\na\nb\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testToggleLineCommentUsesFileLanguageDefault() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("script.py")
        try "print(1)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "# print(1)\n")
    }

    func testToggleLineCommentUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("script-local.txt")
        let projectedURL = tempDir.appendingPathComponent("script-projected.py")
        try "print(1)\n".write(to: fileURL, atomically: true, encoding: .utf8)

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

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "# print(1)\n")
    }

    func testToggleLineCommentUsesUserLanguageOverride() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "atto_command_comment_override_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setCommentConfiguration(.line("##"), forLanguageKey: "python")

        let fileURL = tempDir.appendingPathComponent("script.py")
        try "print(1)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "## print(1)\n")
    }

    func testToggleCommentUsesBlockLanguageConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("index.html")
        try "<div></div>\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 11)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "<!--<div></div>-->\n")
    }

    func testOpenFileAppliesLanguageIndentationConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("script.js")
        try "{".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.moveTo(line: 0, column: 1)
        try editorView.editor.insertNewline(autoIndent: true)

        XCTAssertEqual(try editorView.editor.text(), "{\n  ")
    }

    func testLanguageIndentationConfigUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("indent-local.txt")
        let projectedURL = tempDir.appendingPathComponent("indent-projected.js")
        try "{".write(to: fileURL, atomically: true, encoding: .utf8)

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

        vc.applyLanguageConfiguration(for: tab)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.moveTo(line: 0, column: 1)
        try editorView.editor.insertNewline(autoIndent: true)

        XCTAssertEqual(try editorView.editor.text(), "{\n  ")
    }

    func testGoToLineCommandParsesInputAndMovesCaret() throws {
        XCTAssertEqual(
            AttoEditorAreaViewController.parseGoToLineTarget("3:2"),
            AttoEditorAreaViewController.GoToLineTarget(line1: 3, column1: 2)
        )
        XCTAssertEqual(
            AttoEditorAreaViewController.parseGoToLineTarget("4"),
            AttoEditorAreaViewController.GoToLineTarget(line1: 4, column1: 1)
        )
        XCTAssertNil(AttoEditorAreaViewController.parseGoToLineTarget("0:1"))
        XCTAssertNil(AttoEditorAreaViewController.parseGoToLineTarget("3:"))
        XCTAssertNil(AttoEditorAreaViewController.parseGoToLineTarget("abc"))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("goto-line.txt")
        try "aa\nbb\ncc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertTrue(vc.goToLineInActiveTab(input: "3:2"))
        let offsets = try editorView.editor.selectionOffsets()
        let pos = try editorView.editor.charOffsetToLogicalPosition(offset: offsets.end)
        XCTAssertEqual(pos.line, 2)
        XCTAssertEqual(pos.column, 1)

        XCTAssertFalse(vc.goToLineInActiveTab(input: "x:y"))
    }

    func testCoreMultiDocumentMirrorTracksTabsAndPanes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)

        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.workspaceRoots, [tempDir.standardizedFileURL.absoluteString])

        let alternateRoot = tempDir.appendingPathComponent("alternate", isDirectory: true)
        try FileManager.default.createDirectory(at: alternateRoot, withIntermediateDirectories: true)
        vc.setWorkspaceRootURL(alternateRoot)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.workspaceRoots, [alternateRoot.standardizedFileURL.absoluteString])
        vc.setWorkspaceRootURL(tempDir)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.workspaceRoots, [tempDir.standardizedFileURL.absoluteString])

        vc.openFile(url: firstURL, mode: .preview)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "first.txt")
        XCTAssertEqual(snapshot.tabs[0].documentURI, firstURL.standardizedFileURL.absoluteString)
        XCTAssertTrue(snapshot.tabs[0].isPreview)

        vc.openFile(url: secondURL, mode: .preview)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "second.txt")
        XCTAssertEqual(snapshot.tabs[0].documentURI, secondURL.standardizedFileURL.absoluteString)
        XCTAssertTrue(snapshot.tabs[0].isPreview)

        vc.openFile(url: secondURL, mode: .pinned)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "second.txt")
        XCTAssertEqual(snapshot.tabs[0].documentURI, secondURL.standardizedFileURL.absoluteString)
        XCTAssertFalse(snapshot.tabs[0].isPreview)
        XCTAssertEqual(snapshot.activeTabId, snapshot.tabs[0].id)

        XCTAssertTrue(vc.splitActiveTabRight())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].viewCount, 2)
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)

        XCTAssertTrue(vc.focusPreviousPaneInActiveTab())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 0)

        XCTAssertTrue(vc.closeActivePane())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].viewCount, 1)
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 0)

        vc.closeActiveTab()
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.isEmpty)
        XCTAssertNil(snapshot.activeTabId)
    }

    func testPreviewReplacementCloseCallbackUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("preview-close-local.txt")
        let projectedURL = tempDir.appendingPathComponent("preview-close-projected.txt")
        let secondURL = tempDir.appendingPathComponent("preview-close-next.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        XCTAssertTrue(vc.openFile(url: firstURL, mode: .preview))

        let tab = try XCTUnwrap(vc.activeTab)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, firstURL.standardizedFileURL)

        var closedURLs: [URL] = []
        vc.onDidCloseFile = { closedURLs.append($0.standardizedFileURL) }
        XCTAssertTrue(vc.openFile(url: secondURL, mode: .preview))

        XCTAssertEqual(closedURLs, [projectedURL.standardizedFileURL])
        XCTAssertEqual(vc.openFileItems().map { $0.url.standardizedFileURL }, [secondURL.standardizedFileURL])
    }

    func testCoreMultiDocumentMirrorTracksEditedTextDirtyAndSearch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("mirror.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        let tabId = try XCTUnwrap(snapshot.activeTabId)
        var tabSnapshot = try XCTUnwrap(snapshot.tabs.first { $0.id == tabId })
        XCTAssertEqual(tabSnapshot.documentURI, fileURL.standardizedFileURL.absoluteString)
        XCTAssertFalse(tabSnapshot.isModified)

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" needle"}"#))

        let results = try XCTUnwrap(vc._coreMultiDocumentSearchForTesting(query: "needle"))
        XCTAssertEqual(results.map(\.tabId), [tabId])
        XCTAssertEqual(results.flatMap(\.matches).count, 1)

        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        tabSnapshot = try XCTUnwrap(snapshot.tabs.first { $0.id == tabId })
        XCTAssertTrue(tabSnapshot.isModified)

        vc.saveActiveTab()
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        tabSnapshot = try XCTUnwrap(snapshot.tabs.first { $0.id == tabId })
        XCTAssertFalse(tabSnapshot.isModified)
    }

    func testFindInOpenTabsUsesCoreMirrorForUnsavedText() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("opened-search.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" needle"}"#))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha")

        let results = vc.findInOpenTabs(query: "needle")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(results[0].line1, 1)
        XCTAssertEqual(results[0].column1, 2)
        XCTAssertEqual(results[0].lineText, "needlealpha")
    }

    func testFindInOpenTabsUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("opened-search-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("projected-opened-search-uri.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)
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

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" needle"}"#))

        let results = vc.findInOpenTabs(query: "needle")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url.standardizedFileURL, projectedURL.standardizedFileURL)
        XCTAssertEqual(results[0].line1, 1)
        XCTAssertEqual(results[0].column1, 2)
        XCTAssertEqual(results[0].lineText, "needlealpha")
    }

    func testFindInOpenTabsUsesCoreSearchOptions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("opened-search-options.txt")
        try "Needle needle word sword\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let insensitive = vc.findInOpenTabs(
            query: "needle",
            options: AttoFindInFilesViewController.SearchOptions(
                caseSensitive: false,
                wholeWord: false,
                regex: false
            )
        )
        XCTAssertEqual(insensitive.count, 2)

        let sensitive = vc.findInOpenTabs(
            query: "needle",
            options: AttoFindInFilesViewController.SearchOptions(
                caseSensitive: true,
                wholeWord: false,
                regex: false
            )
        )
        XCTAssertEqual(sensitive.count, 1)
        XCTAssertEqual(sensitive[0].column1, 8)

        let wholeWord = vc.findInOpenTabs(
            query: "word",
            options: AttoFindInFilesViewController.SearchOptions(
                caseSensitive: false,
                wholeWord: true,
                regex: false
            )
        )
        XCTAssertEqual(wholeWord.count, 1)
        XCTAssertEqual(wholeWord[0].column1, 15)
    }

    func testFindInWorkspaceFilesUsesCoreWorkspaceSearch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("src/main.rs")
        let optionsURL = tempDir.appendingPathComponent("src/options.swift")
        let readmeURL = tempDir.appendingPathComponent("README.md")
        try "fn main() {\n    let needle = 1;\n}\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "Needle\nneedle\nalpha7\n".write(to: optionsURL, atomically: true, encoding: .utf8)
        try "needle in docs\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let results = try XCTUnwrap(
            vc.findInWorkspaceFiles(query: "needle", includeGlobs: ["*.rs"], excludeGlobs: [])
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url.standardizedFileURL, sourceURL.standardizedFileURL)
        XCTAssertEqual(results[0].line1, 2)
        XCTAssertEqual(results[0].column1, 9)
        XCTAssertEqual(results[0].lineText, "let needle = 1;")

        let excluded = try XCTUnwrap(
            vc.findInWorkspaceFiles(query: "needle", includeGlobs: [], excludeGlobs: ["src/**"])
        )
        XCTAssertEqual(excluded.map(\.url.standardizedFileURL), [readmeURL.standardizedFileURL])

        let caseSensitive = try XCTUnwrap(
            vc.findInWorkspaceFiles(
                query: "Needle",
                includeGlobs: ["*.swift"],
                excludeGlobs: [],
                options: AttoFindInFilesViewController.SearchOptions(
                    caseSensitive: true,
                    wholeWord: false,
                    regex: false
                )
            )
        )
        XCTAssertEqual(caseSensitive.count, 1)
        XCTAssertEqual(caseSensitive[0].url.standardizedFileURL, optionsURL.standardizedFileURL)
        XCTAssertEqual(caseSensitive[0].line1, 1)
        XCTAssertEqual(caseSensitive[0].column1, 1)

        let caseInsensitive = try XCTUnwrap(
            vc.findInWorkspaceFiles(
                query: "needle",
                includeGlobs: ["*.swift"],
                excludeGlobs: [],
                options: AttoFindInFilesViewController.SearchOptions(
                    caseSensitive: false,
                    wholeWord: false,
                    regex: false
                )
            )
        )
        XCTAssertEqual(caseInsensitive.count, 2)

        let regex = try XCTUnwrap(
            vc.findInWorkspaceFiles(
                query: #"alpha\d"#,
                includeGlobs: ["*.swift"],
                excludeGlobs: [],
                options: AttoFindInFilesViewController.SearchOptions(
                    caseSensitive: true,
                    wholeWord: false,
                    regex: true
                )
            )
        )
        XCTAssertEqual(regex.count, 1)
        XCTAssertEqual(regex[0].line1, 3)

        let literal = try XCTUnwrap(
            vc.findInWorkspaceFiles(
                query: #"alpha\d"#,
                includeGlobs: ["*.swift"],
                excludeGlobs: [],
                options: AttoFindInFilesViewController.SearchOptions(
                    caseSensitive: true,
                    wholeWord: false,
                    regex: false
                )
            )
        )
        XCTAssertTrue(literal.isEmpty)
    }

    func testQuickOpenUsesCoreWorkspaceFileListWhenAvailable() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cachedURL = tempDir.appendingPathComponent("src/cached.rs")
        try "fn cached() {}\n".write(to: cachedURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        XCTAssertEqual(ctx.fileIndex.entries().map(\.relativePath), ["src/cached.rs"])

        let coreOnlyURL = tempDir.appendingPathComponent("src/core_only.rs")
        try "fn core_only() {}\n".write(to: coreOnlyURL, atomically: true, encoding: .utf8)
        let coreModelURL = tempDir.appendingPathComponent("src/core_model.rs")
        try "fn core_model() {}\n".write(to: coreModelURL, atomically: true, encoding: .utf8)

        let entries = ctx.workspaceFileEntries()
        XCTAssertEqual(entries.map(\.relativePath), ["src/cached.rs", "src/core_model.rs", "src/core_only.rs"])
        let coreIndex = try XCTUnwrap(ctx.editorAreaController.coreDocuments?.projectFileIndexSnapshot())
        XCTAssertEqual(coreIndex.files.map(\.relativePath), ["src/cached.rs", "src/core_model.rs", "src/core_only.rs"])

        let quickOpenTitles = delegate._quickOpenCommandsForTesting().map(\.title)
        XCTAssertTrue(quickOpenTitles.contains("src/cached.rs"))
        XCTAssertTrue(quickOpenTitles.contains("src/core_only.rs"))

        let queriedTitles = delegate._quickOpenCommandsForTesting(query: "cm").map(\.title)
        XCTAssertEqual(queriedTitles, ["src/core_model.rs"])
    }

    func testCloseTabGroupCommandsUseCoreTabProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close.txt")
        let secondURL = tempDir.appendingPathComponent("second-close.txt")
        let thirdURL = tempDir.appendingPathComponent("third-close.txt")
        let fourthURL = tempDir.appendingPathComponent("fourth-close.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)
        try "fourth".write(to: fourthURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)
        vc.openFile(url: fourthURL, mode: .pinned)

        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let thirdTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL })
        let fourthTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == fourthURL.standardizedFileURL })
        XCTAssertEqual(vc.selectedTabID, fourthTab.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 3, toIndex: 1))
        try coreDocuments.setActiveTab(try XCTUnwrap(secondTab.coreTabID))
        XCTAssertEqual(vc.activeTab?.id, secondTab.id)

        XCTAssertEqual(vc.closeTabsToRightOfActiveTab(), 1)
        XCTAssertFalse(vc.tabs.contains { $0.id == thirdTab.id })
        XCTAssertTrue(vc.tabs.contains { $0.id == fourthTab.id })
        XCTAssertEqual(vc.selectedTabID, secondTab.id)

        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-close.txt",
            "fourth-close.txt",
            "second-close.txt",
        ])
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-close.txt",
            "fourth-close.txt",
            "second-close.txt",
        ])

        XCTAssertEqual(vc.closeOtherTabsForActiveTab(), 2)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), ["second-close.txt"])
        XCTAssertEqual(snapshot.activeTabId, try XCTUnwrap(secondTab.coreTabID))
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, ["second-close.txt"])
    }

    func testCloseAllTabsUsesCoreTabProjectionOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close-all.txt")
        let secondURL = tempDir.appendingPathComponent("second-close-all.txt")
        let thirdURL = tempDir.appendingPathComponent("third-close-all.txt")
        let fourthURL = tempDir.appendingPathComponent("fourth-close-all.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)
        try "fourth".write(to: fourthURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)
        vc.openFile(url: fourthURL, mode: .pinned)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 3, toIndex: 1))
        XCTAssertEqual(try coreDocuments.snapshot().tabs.map(\.title), [
            "first-close-all.txt",
            "fourth-close-all.txt",
            "second-close-all.txt",
            "third-close-all.txt",
        ])

        var closedNames: [String] = []
        vc.onDidCloseFile = { url in
            closedNames.append(url.lastPathComponent)
        }

        XCTAssertEqual(vc.closeAllTabsForWindow(), 4)
        XCTAssertEqual(closedNames, [
            "first-close-all.txt",
            "fourth-close-all.txt",
            "second-close-all.txt",
            "third-close-all.txt",
        ])
        XCTAssertTrue(vc.tabs.isEmpty)
        XCTAssertTrue(vc.openFileItems().isEmpty)

        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.isEmpty)
        XCTAssertNil(snapshot.activeTabId)
    }

    func testCloseTabCallbackUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("close-local.txt")
        let projectedURL = tempDir.appendingPathComponent("close-projected.txt")
        try "close".write(to: fileURL, atomically: true, encoding: .utf8)

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

        var closedURLs: [URL] = []
        vc.onDidCloseFile = { closedURLs.append($0.standardizedFileURL) }
        vc.closeTab(id: tab.id)

        XCTAssertTrue(vc.tabs.isEmpty)
        XCTAssertEqual(closedURLs, [projectedURL.standardizedFileURL])
    }

    func testSessionSnapshotUsesCoreTabProjectionWhenAvailable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-session.txt")
        let secondURL = tempDir.appendingPathComponent("second-session.txt")
        let thirdURL = tempDir.appendingPathComponent("third-session.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let thirdTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL })
        let thirdCoreTabID = try XCTUnwrap(thirdTab.coreTabID)
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-session.txt",
            "second-session.txt",
            "third-session.txt",
        ])

        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 2, toIndex: 0))
        try coreDocuments.setActiveTab(thirdCoreTabID)
        XCTAssertEqual(try coreDocuments.splitTab(thirdCoreTabID, viewportWidthCells: 120), 1)
        try coreDocuments.setActiveViewIndex(tabId: thirdCoreTabID, viewIndex: 1)

        let session = vc.makeSessionSnapshot()
        XCTAssertEqual(session.tabs.map { URL(fileURLWithPath: $0.filePath).lastPathComponent }, [
            "third-session.txt",
            "first-session.txt",
            "second-session.txt",
        ])
        XCTAssertEqual(session.selectedTabIndex, 0)
        XCTAssertEqual(session.tabs[0].paneCount, 2)
        XCTAssertEqual(session.tabs[0].activePaneIndex, 1)
        XCTAssertEqual(session.tabs[0].paneLayout?.axis, .horizontal)
        XCTAssertEqual(session.tabs[0].paneLayout?.flattenedPaneCount, 2)
        XCTAssertEqual(session.tabs[0].paneLayout?.clampedActivePaneIndex, 1)
    }

    func testCoreTabTitleUpdateUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("title-local-tab.txt")
        let projectedURL = tempDir.appendingPathComponent("title-projected-tab.txt")
        try "title".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        try coreDocuments.setTabDocumentURI(projectedURL.standardizedFileURL.absoluteString, tabId: coreTabID)
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        vc.updateCoreTabTitle(tab)

        let snapshotTab = try XCTUnwrap(try coreDocuments.snapshot().tabs.first { $0.id == coreTabID })
        XCTAssertEqual(snapshotTab.title, "title-projected-tab.txt")
    }

    func testCloseActiveTabUsesCoreActiveFallbackProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close-active.txt")
        let secondURL = tempDir.appendingPathComponent("second-close-active.txt")
        let thirdURL = tempDir.appendingPathComponent("third-close-active.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let firstTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == firstURL.standardizedFileURL })
        let thirdTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL })
        XCTAssertEqual(vc.selectedTabID, thirdTab.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 2, toIndex: 0))
        XCTAssertEqual(try coreDocuments.snapshot().tabs.map(\.title), [
            "third-close-active.txt",
            "first-close-active.txt",
            "second-close-active.txt",
        ])

        vc.closeActiveTab()

        XCTAssertFalse(vc.tabs.contains { $0.id == thirdTab.id })
        XCTAssertEqual(vc.selectedTabID, firstTab.id)
        XCTAssertEqual(vc.activeTab?.id, firstTab.id)
        let snapshot = try coreDocuments.snapshot()
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-close-active.txt",
            "second-close-active.txt",
        ])
        XCTAssertEqual(snapshot.activeTabId, firstTab.coreTabID)
    }

    func testWindowTitleUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("title-local.txt")
        let projectedURL = tempDir.appendingPathComponent("title-projected.txt")
        try "title".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        vc.updateWindowTitle()
        XCTAssertEqual(window.title, "AttoEditor — title-projected.txt")
    }

    func testSessionRestoreRestoresSplitPanesIntoCoreMirror() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session-split.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        XCTAssertTrue(vc.splitActiveTabRight())
        XCTAssertTrue(vc.focusPreviousPaneInActiveTab())

        let snapshot = vc.makeSessionSnapshot()
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].paneCount, 2)
        XCTAssertEqual(snapshot.tabs[0].activePaneIndex, 0)

        let restored = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(restored)
        restored.restoreSession(tabs: snapshot.tabs, selectedTabIndex: snapshot.selectedTabIndex)
        restored.view.layoutSubtreeIfNeeded()

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: restored.view)
        XCTAssertEqual(editorViews.count, 2)

        let restoredSnapshot = restored.makeSessionSnapshot()
        XCTAssertEqual(restoredSnapshot.tabs.count, 1)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneCount, 2)
        XCTAssertEqual(restoredSnapshot.tabs[0].activePaneIndex, 0)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.axis, .horizontal)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.flattenedPaneCount, 2)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.clampedActivePaneIndex, 0)

        let coreSnapshot = try XCTUnwrap(restored._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(coreSnapshot.tabs.count, 1)
        XCTAssertEqual(coreSnapshot.tabs[0].viewCount, 2)
        XCTAssertEqual(coreSnapshot.tabs[0].activeViewIndex, 0)
    }

    func testSessionSnapshotRestoresUnsavedUntitledBuffers() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let untitledURL = tempDir.appendingPathComponent("untitled-1.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: untitledURL.path))

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        XCTAssertTrue(vc.openFile(url: untitledURL, mode: .pinned, isUntitled: true))

        let tab = try XCTUnwrap(vc.tabs.first)
        try tab.editCore.editor.insertText("draft text\n")

        let snapshot = vc.makeSessionSnapshot()
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].filePath, untitledURL.standardizedFileURL.path)
        XCTAssertEqual(snapshot.tabs[0].isUntitled, true)
        XCTAssertEqual(snapshot.tabs[0].unsavedText, "draft text\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: untitledURL.path))

        let restored = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(restored)
        restored.restoreSession(tabs: snapshot.tabs, selectedTabIndex: snapshot.selectedTabIndex)

        let restoredTab = try XCTUnwrap(restored.tabs.first)
        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restoredTab.fileURL.standardizedFileURL, untitledURL.standardizedFileURL)
        XCTAssertTrue(restoredTab.isUntitled)
        XCTAssertEqual(try restoredTab.editCore.editor.text(), "draft text\n")
        XCTAssertTrue(restored.isTabDirtyForDataLossDecision(restoredTab))
        XCTAssertFalse(FileManager.default.fileExists(atPath: untitledURL.path))

        let restoredSnapshot = restored.makeSessionSnapshot()
        XCTAssertEqual(restoredSnapshot.tabs.count, 1)
        XCTAssertEqual(restoredSnapshot.tabs[0].isUntitled, true)
        XCTAssertEqual(restoredSnapshot.tabs[0].unsavedText, "draft text\n")

        let coreDocuments = try XCTUnwrap(restored.coreDocuments)
        let coreSnapshot = try coreDocuments.snapshot()
        let coreTab = try XCTUnwrap(coreSnapshot.tabs.first)
        XCTAssertTrue(coreTab.isModified)
        XCTAssertEqual(try coreDocuments.tabText(tabId: coreTab.id), "draft text\n")
    }

    func testSessionRestorePrefersPaneLayoutSnapshotOverLegacyPaneCount() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session-layout.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let tabSnapshot = AttoTabSnapshot(
            filePath: fileURL.path,
            isPreview: false,
            showsMinimap: true,
            paneCount: 1,
            activePaneIndex: 0,
            paneLayout: AttoPaneLayoutSnapshot.horizontalSplit(paneCount: 3, activePaneIndex: 2)
        )

        let restored = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(restored)
        restored.restoreSession(tabs: [tabSnapshot], selectedTabIndex: 0)
        restored.view.layoutSubtreeIfNeeded()

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: restored.view)
        XCTAssertEqual(editorViews.count, 3)

        let restoredSnapshot = restored.makeSessionSnapshot()
        XCTAssertEqual(restoredSnapshot.tabs.count, 1)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneCount, 3)
        XCTAssertEqual(restoredSnapshot.tabs[0].activePaneIndex, 2)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.flattenedPaneCount, 3)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.clampedActivePaneIndex, 2)

        let coreSnapshot = try XCTUnwrap(restored._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(coreSnapshot.tabs.count, 1)
        XCTAssertEqual(coreSnapshot.tabs[0].viewCount, 3)
        XCTAssertEqual(coreSnapshot.tabs[0].activeViewIndex, 2)
    }
}
