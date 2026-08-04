import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoLanguageFallbackExperienceTests: XCTestCase {
    func testParserAndServerUnavailableFallbackReasonsReachStatusBar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoLanguageFallbackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("plain.noattofallback")
        try "plain".write(to: file, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: root)
        vc._setLspEnvironmentProviderForTesting { [:] }
        _ = attachToWindow(vc)

        XCTAssertTrue(vc.openFile(url: file, mode: .pinned))
        let tab = try XCTUnwrap(vc.tabs.first)
        XCTAssertEqual(tab.languageSupportSource, .plainText)
        XCTAssertTrue(tab.languageFallbackReasons.contains("No LSP server is configured for .noattofallback."))
        XCTAssertTrue(tab.languageFallbackReasons.contains("Tree-sitter parser is unavailable; trying Sublime syntax fallback."))
        XCTAssertTrue(tab.languageFallbackReasons.contains("No Sublime syntax fallback was found."))

        vc._updateStatusBarForTesting()

        let sourceLabel = try languageSourceLabel(in: vc)
        let tooltip = try XCTUnwrap(sourceLabel.toolTip)
        XCTAssertTrue(tooltip.contains("Language source: plain text"), tooltip)
        XCTAssertTrue(tooltip.contains("No LSP server is configured for .noattofallback."), tooltip)
        XCTAssertTrue(tooltip.contains("Tree-sitter parser is unavailable"), tooltip)
        XCTAssertTrue(tooltip.contains("No Sublime syntax fallback was found."), tooltip)
    }

    func testLargeFileDisablesLanguageModeSwitching() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoLanguageLargeFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("large.rs")
        try "abcdef".write(to: file, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: root)
        vc.documentLoadLargeFileByteLimit = 4
        _ = attachToWindow(vc)

        XCTAssertTrue(vc.openFile(url: file, mode: .pinned))
        let tab = try XCTUnwrap(vc.tabs.first)
        XCTAssertEqual(tab.languageSupportSource, .plainText)
        XCTAssertEqual(tab.languageProcessingDisabledReason, "large file 6 bytes")
        XCTAssertTrue(tab.suppressesAutomaticLspStart)

        vc._updateStatusBarForTesting()

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let popUp = try XCTUnwrap(findSubview(of: NSPopUpButton.self, in: statusBar))
        XCTAssertFalse(popUp.isEnabled)

        let tooltip = try XCTUnwrap(languageSourceLabel(in: vc).toolTip)
        XCTAssertTrue(tooltip.contains("Large file (6 bytes) opened with language services disabled."), tooltip)

        vc.setSyntaxLanguageForActiveTab(languageId: "rust")
        XCTAssertEqual(tab.languageSupportSource, .plainText)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Language mode unavailable: large file 6 bytes")
    }

    func testReloadToLargeFileClearsLanguageMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoLanguageReloadLargeFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("reload.rs")
        try "small".write(to: file, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: root)
        vc.documentLoadLargeFileByteLimit = 8
        _ = attachToWindow(vc)

        XCTAssertTrue(vc.openFile(url: file, mode: .pinned))
        let tab = try XCTUnwrap(vc.tabs.first)
        tab.syntaxLanguageId = "rust"
        tab.languageSupportSource = .treeSitter
        vc.syncCoreTabLanguageId(tab)
        XCTAssertEqual(try vc._coreMultiDocumentSnapshotForTesting()?.tabs.first?.languageId, "rust")

        try "0123456789".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(vc.reloadActiveTab(discardingUnsavedChanges: true))

        XCTAssertEqual(try tab.editCore.editor.text(), "0123456789")
        XCTAssertNil(tab.syntaxLanguageId)
        XCTAssertEqual(tab.languageSupportSource, .plainText)
        XCTAssertEqual(tab.languageProcessingDisabledReason, "large file 10 bytes")
        XCTAssertTrue(tab.suppressesAutomaticLspStart)
        XCTAssertNil(try vc._coreMultiDocumentSnapshotForTesting()?.tabs.first?.languageId)
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL
        )
    }

    @discardableResult
    private func attachToWindow(_ vc: AttoEditorAreaViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func languageSourceLabel(in vc: AttoEditorAreaViewController) throws -> NSTextField {
        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        return try XCTUnwrap(labels.first {
            $0.identifier?.rawValue == AttoAccessibilityID.statusBarLanguageSourceLabel
        })
    }

    private func allSubviews(in root: NSView) -> [NSView] {
        var out: [NSView] = []
        var stack: [NSView] = [root]
        while let v = stack.popLast() {
            out.append(v)
            stack.append(contentsOf: v.subviews)
        }
        return out
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T { return v }
        for child in root.subviews {
            if let found = findSubview(of: type, in: child) {
                return found
            }
        }
        return nil
    }
}
