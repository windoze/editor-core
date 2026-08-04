import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoAutoPairsAndBracketsTests: XCTestCase {
    func testAutoPairsAreEnabledByDefaultInAttoEditor() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoAutoPairsAndBracketsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("a.txt")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(
            library: lib,
            theme: theme,
            workspaceRootURL: tempDir,
            preferences: makeIsolatedPreferences()
        )

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
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))

        editorView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(try editorView.editor.text(), "()")
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 1)
        XCTAssertEqual(try editorView.editor.selectionOffsets().end, 1)

        // Skip-over closing delimiter.
        editorView.insertText(")", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(try editorView.editor.text(), "()")
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 2)
        XCTAssertEqual(try editorView.editor.selectionOffsets().end, 2)
    }

    func testAutoPairsCanBeDisabledFromPreferences() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoAutoPairsAndBracketsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("disabled.txt")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(
            library: lib,
            theme: theme,
            workspaceRootURL: tempDir,
            preferences: makeIsolatedPreferences(autoPairsEnabled: false)
        )

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
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))

        editorView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(try editorView.editor.text(), "(")
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 1)
        XCTAssertEqual(try editorView.editor.selectionOffsets().end, 1)
    }

    func testGoToMatchingBracketMovesCaret() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoAutoPairsAndBracketsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("b.txt")
        try "(a[b]c)".write(to: fileURL, atomically: true, encoding: .utf8)

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
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))

        // Put caret after '(' (offset 1), then jump to the matching ')'.
        try editorView.editor.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        editorView.moveToMatchingBracket()

        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 6)
        XCTAssertEqual(try editorView.editor.selectionOffsets().end, 6)
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

    private func makeIsolatedPreferences(autoPairsEnabled: Bool? = nil) -> AttoPreferences {
        let suiteName = "atto_auto_pairs_tests_\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults(suiteName:)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let prefs = AttoPreferences(defaults: defaults, env: [:])
        if let autoPairsEnabled {
            prefs.setAutoPairsEnabled(autoPairsEnabled)
        }
        return prefs
    }
}
