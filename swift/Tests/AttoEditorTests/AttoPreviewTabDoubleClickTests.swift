import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoPreviewTabDoubleClickTests: XCTestCase {
    func testDoubleClickPreviewTabPinsInsteadOfReplacing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoPreviewTabDoubleClickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file1 = root.appendingPathComponent("one.txt")
        let file2 = root.appendingPathComponent("two.txt")
        try "one".write(to: file1, atomically: true, encoding: .utf8)
        try "two".write(to: file2, atomically: true, encoding: .utf8)

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

        vc.openFile(url: file1, mode: .preview)
        XCTAssertTrue(tabTitles(in: vc.view).contains(file1.lastPathComponent))
        XCTAssertFalse(tabTitles(in: vc.view).contains(file2.lastPathComponent))

        let tabBar = try XCTUnwrap(findSubview(of: AttoTabBarView.self, in: vc.view))
        let chip = try XCTUnwrap(findTabChipView(title: file1.lastPathComponent, in: tabBar))

        // Double-click the preview tab to pin it.
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 2,
                pressure: 0
            )
        )
        chip.mouseDown(with: event)

        // Opening another preview should NOT replace the pinned tab.
        vc.openFile(url: file2, mode: .preview)

        let titles = tabTitles(in: vc.view)
        XCTAssertTrue(titles.contains(file1.lastPathComponent))
        XCTAssertTrue(titles.contains(file2.lastPathComponent))
    }

    private func tabTitles(in root: NSView) -> [String] {
        guard let tabBar = findSubview(of: AttoTabBarView.self, in: root) else { return [] }
        return allSubviews(in: tabBar)
            .compactMap { ($0 as? NSTextField)?.stringValue }
            .filter { $0.isEmpty == false && $0 != "No file open" }
    }

    private func findTabChipView(title: String, in root: NSView) -> NSView? {
        for v in allSubviews(in: root) {
            if v.subviews.contains(where: { ($0 as? NSTextField)?.stringValue == title }) {
                return v
            }
        }
        return nil
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

