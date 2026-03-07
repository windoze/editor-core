import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoFileExplorerDoubleClickTests: XCTestCase {
    func testDoubleClickDirectoryTogglesExpansion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoFileExplorerDoubleClickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dir = root.appendingPathComponent("dir", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let vc = AttoFileExplorerViewController(rootURL: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()

        let outlineView = try XCTUnwrap(findSubview(of: NSOutlineView.self, in: vc.view))
        outlineView.reloadData()
        outlineView.layoutSubtreeIfNeeded()

        guard let (row, item) = findRow(named: "dir", in: outlineView) else {
            XCTFail("expected to find directory row in outline view")
            return
        }

        XCTAssertFalse(outlineView.isItemExpanded(item), "directory should start collapsed")

        XCTAssertGreaterThanOrEqual(row, 0)
        vc._handleDoubleClick(item: item)
        XCTAssertTrue(outlineView.isItemExpanded(item), "expected double-click to expand directory")

        vc._handleDoubleClick(item: item)
        XCTAssertFalse(outlineView.isItemExpanded(item), "expected double-click to collapse directory")
    }

    private func findRow(named name: String, in outlineView: NSOutlineView) -> (row: Int, item: Any)? {
        for row in 0..<outlineView.numberOfRows {
            guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView else {
                continue
            }
            if cell.textField?.stringValue == name {
                guard let item = outlineView.item(atRow: row) else { continue }
                return (row, item)
            }
        }
        return nil
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
