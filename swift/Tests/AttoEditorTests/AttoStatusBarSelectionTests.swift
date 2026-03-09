import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoStatusBarSelectionTests: XCTestCase {
    func testStatusBarShowsSelectionRangeAndSize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoStatusBarSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.txt")
        try "ab\ncde\nf".write(to: file, atomically: true, encoding: .utf8)

        let lib = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.defaultLight()
        let vc = AttoEditorAreaViewController(library: lib, theme: theme, workspaceRootURL: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        vc.openFile(url: file, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        editorView.doCommand(by: #selector(NSResponder.moveToBeginningOfDocument(_:)))
        editorView.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))

        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        let labels = allSubviews(in: statusBar).compactMap { $0 as? NSTextField }
        let selection = labels.first(where: { $0.stringValue.hasPrefix("Sel ") })?.stringValue

        let text = try XCTUnwrap(selection)
        XCTAssertTrue(text.contains("Sel 1"), "expected selection size to be shown")
        XCTAssertTrue(text.contains("(1:1-1:2)"), "expected selection range (Ln:Col) to be shown")
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

