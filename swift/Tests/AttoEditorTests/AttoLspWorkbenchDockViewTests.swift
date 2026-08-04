import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoLspWorkbenchDockViewTests: XCTestCase {
    func testDockViewExposesStableIdentifiersAndFiltersRows() throws {
        let items = [
            AttoLspWorkbenchPanelController.Item(
                id: "problems",
                title: "Problems",
                detail: "Active document diagnostics",
                status: "2 problems",
                isEnabled: true,
                historyCount: 1
            ),
            AttoLspWorkbenchPanelController.Item(
                id: "symbols",
                title: "Symbols",
                detail: "Latest symbol result",
                status: "0 symbols",
                isEnabled: false
            ),
        ]

        var openedItems: [AttoLspWorkbenchPanelController.Item] = []
        var historyItems: [AttoLspWorkbenchPanelController.Item] = []
        var didClose = false
        let dockView = AttoLspWorkbenchDockView(
            onOpen: { openedItems.append($0) },
            onOpenHistory: { historyItems.append($0) },
            onClose: { didClose = true }
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 260))
        root.addSubview(dockView)
        dockView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dockView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dockView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            dockView.topAnchor.constraint(equalTo: root.topAnchor),
            dockView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        dockView.update(items: items)
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(dockView.identifier?.rawValue, AttoAccessibilityID.lspWorkbenchDock)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchDockSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchDockMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchDockTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchDockCloseButton, in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchDockScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter LSP workbench...")
        XCTAssertEqual(metadataLabel.stringValue, "1 available | 2 result families | 1 history entry")
        XCTAssertEqual(table.numberOfRows, 2)

        let row = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchDockRowTitle, in: row))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchDockRowDetail, in: row))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchDockRowStatus, in: row))

        searchField.stringValue = "symbols"
        dockView.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertTrue(dockView.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(openedItems.isEmpty)

        searchField.stringValue = "problems"
        dockView.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertTrue(dockView.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedItems, [items[0]])
        XCTAssertTrue(dockView.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveRight(_:))))
        XCTAssertEqual(historyItems, [items[0]])
        XCTAssertTrue(dockView.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertTrue(didClose)
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let match = findView(identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
