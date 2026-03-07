import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoDirtyStateTests: XCTestCase {
    func testTabDirtyDotResetsWhenUndoBackToClean() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoDirtyStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("a.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: tempDir)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: fileURL, mode: .pinned)
        XCTAssertFalse(window.title.contains("●"), "expected newly opened file to be clean")

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        editorView.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(window.title.contains("●"), "expected edit to mark the tab dirty")

        editorView.undo(nil)
        XCTAssertFalse(window.title.contains("●"), "expected undo back to clean state to clear dirty mark")
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

