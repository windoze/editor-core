import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testFormatOnSaveRunsBeforeWritingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("format-on-save.txt")
        try "unformatted\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("format-on-save-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("format-on-save-fake-lsp.py")
        try writeFormattingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let suiteName = "atto_editor_command_format_on_save_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        var snapshot = preferences.effectiveConfigurationSnapshot(workspaceRootURL: tempDir)
        snapshot.language.formatOnSaveEnabled = true
        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir,
            configurationSnapshot: snapshot,
            preferences: preferences
        )
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { tab.editCore.editor.lspDisable() }

        XCTAssertTrue(vc.saveTab(tab))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "formatted\n")

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: "textDocument/didSave"
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/formatting""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didSave""#), captured)
    }

    func testSaveDoesNotFormatWhenFormatOnSaveDisabled() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("format-on-save-disabled.txt")
        try "unformatted\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("format-on-save-disabled-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("format-on-save-disabled-fake-lsp.py")
        try writeFormattingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let suiteName = "atto_editor_command_format_on_save_disabled_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir,
            preferences: preferences
        )
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { tab.editCore.editor.lspDisable() }

        XCTAssertTrue(vc.saveTab(tab))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "unformatted\n")

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: "textDocument/didSave"
        )
        XCTAssertFalse(captured.contains(#""method":"textDocument/formatting""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didSave""#), captured)
    }

    func testFormatOnTypePreferenceDisablesAutomaticOnTypeFormatting() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("format-on-type-disabled.txt")
        try "let value = 1".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("format-on-type-disabled-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("format-on-type-disabled-fake-lsp.py")
        try writeOnTypeFormattingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let suiteName = "atto_editor_command_format_on_type_disabled_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        var snapshot = preferences.effectiveConfigurationSnapshot(workspaceRootURL: tempDir)
        snapshot.language.formatOnTypeEnabled = false
        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir,
            configurationSnapshot: snapshot,
            preferences: preferences
        )
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { tab.editCore.editor.lspDisable() }

        tab.editCore.editorView.insertText(";", replacementRange: NSRange(location: NSNotFound, length: 0))

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: "textDocument/didChange"
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/didChange""#), captured)
        XCTAssertFalse(captured.contains(#""method":"textDocument/onTypeFormatting""#), captured)
    }

    func testSaveAndCloseNotifyLspDocumentLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lifecycle.txt")
        try "initial".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("lifecycle-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("lifecycle-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { tab.editCore.editor.lspDisable() }

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" saved"}"#))
        vc.saveActiveTab()
        vc.closeActiveTab()

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: "textDocument/didClose"
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/didSave""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didClose""#), captured)
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(" savedinitial"), captured)
    }

    func testOpenSaveAndCloseNotifyExistingLspSessions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second opened".write(to: secondURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("open-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("open-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        try firstTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { firstTab.editCore.editor.lspDisable() }

        vc.openFile(url: secondURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"changed "}"#))
        vc.saveActiveTab()
        vc.closeActiveTab()

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: "textDocument/didClose"
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/didOpen""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didChange""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didSave""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didClose""#), captured)
        XCTAssertTrue(captured.contains(secondURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(#""languageId":"plaintext""#), captured)
        XCTAssertTrue(captured.contains("changed"), captured)
        XCTAssertTrue(captured.contains("second opened"), captured)
    }

    func testCloseAllTabsReleasesOwnedLspSessionsWithoutDuplicateDidClose() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close.txt")
        let secondURL = tempDir.appendingPathComponent("second-close.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        let firstCaptureURL = tempDir.appendingPathComponent("first-close-lsp-stdin.txt")
        let secondCaptureURL = tempDir.appendingPathComponent("second-close-lsp-stdin.txt")
        let firstScriptURL = tempDir.appendingPathComponent("first-close-fake-lsp.sh")
        let secondScriptURL = tempDir.appendingPathComponent("second-close-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: firstCaptureURL, scriptURL: firstScriptURL)
        try writeFakeLspServerScript(captureURL: secondCaptureURL, scriptURL: secondScriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        try firstTab.editCore.editor.lspEnable(
            command: firstScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )

        vc.openFile(url: secondURL, mode: .pinned)
        let secondTab = try XCTUnwrap(vc.activeTab)
        try secondTab.editCore.editor.lspEnable(
            command: secondScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: secondURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )

        _ = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )
        _ = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertEqual(vc.closeAllTabsForWindow(), 2)

        let firstCaptured = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didClose""#
        )
        let secondCaptured = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didClose""#
        )
        XCTAssertEqual(
            occurrenceCount(of: #""method":"textDocument/didClose""#, in: firstCaptured),
            1,
            firstCaptured
        )
        XCTAssertEqual(
            occurrenceCount(of: #""method":"textDocument/didClose""#, in: secondCaptured),
            1,
            secondCaptured
        )
        XCTAssertFalse(try firstTab.editCore.editor.lspIsEnabled())
        XCTAssertFalse(try secondTab.editCore.editor.lspIsEnabled())
        XCTAssertTrue(vc.tabs.isEmpty)
        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.isEmpty)
    }
}
