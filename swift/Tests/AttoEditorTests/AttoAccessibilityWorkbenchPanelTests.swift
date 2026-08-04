import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoAccessibilityIdentifierTests {
    func testLspWorkbenchPanelExposesStableIdentifiersAndFiltersRows() throws {
        let items = [
            AttoLspWorkbenchPanelController.Item(
                id: "problems",
                title: "Problems",
                detail: "Active document diagnostics",
                status: "2 problems",
                isEnabled: true
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
        let controller = AttoLspWorkbenchPanelController { openedItems.append($0) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, items: items))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.lspWorkbenchPanel)
        XCTAssertEqual(panel.title, "LSP Workbench (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter LSP workbench panels...")
        XCTAssertEqual(metadataLabel.stringValue, "1 available | 2 result families")
        XCTAssertEqual(table.numberOfRows, 2)

        let row = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchPanelRowTitle, in: row))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchPanelRowDetail, in: row))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspWorkbenchPanelRowStatus, in: row))

        searchField.stringValue = "symbols"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(openedItems.isEmpty)

        searchField.stringValue = "problems"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedItems, [items[0]])
        XCTAssertTrue(controller.isVisible)
    }

    func testLspWorkbenchPanelMetadataSummarizesLifecycleStates() throws {
        let items = [
            AttoLspWorkbenchPanelController.Item(
                id: "problems",
                title: "Problems",
                detail: "Active document diagnostics",
                status: "2 problems | Fresh",
                isEnabled: true,
                lifecycleState: .fresh,
                jumpTargetCount: 1
            ),
            AttoLspWorkbenchPanelController.Item(
                id: "links",
                title: "Document Links",
                detail: "Active document links",
                status: "2 links | Stale: document edited",
                isEnabled: true,
                lifecycleState: .stale,
                isPinned: true,
                historyCount: 2,
                jumpTargetCount: 2
            ),
            AttoLspWorkbenchPanelController.Item(
                id: "colors",
                title: "Document Colors",
                detail: "Document color requests",
                status: "Error: Document colors unavailable",
                isEnabled: true,
                lifecycleState: .error,
                historyCount: 1
            ),
        ]

        XCTAssertEqual(
            AttoLspWorkbenchPanelController.metadataSummary(for: items),
            "3 available | 3 result families | 3 history entries | 3 jump targets | 1 pinned | 1 stale | 1 error"
        )
    }

    func testLspWorkbenchHistoryPanelRestoresSelectionAcrossUpdatesAndEmptyFilters() throws {
        let items = [
            AttoLspWorkbenchHistoryPanelController.Item(
                id: "locations-1",
                family: "locations",
                resultSequence: 1,
                title: "Locations",
                detail: "Definition: 1 result",
                status: "1 location | Fresh",
                recordedAt: Date(timeIntervalSince1970: 1),
                isPinned: false
            ),
            AttoLspWorkbenchHistoryPanelController.Item(
                id: "symbols-2",
                family: "symbols",
                resultSequence: 2,
                title: "Symbols",
                detail: "Document Symbols: 2 results",
                status: "2 symbols | Fresh",
                recordedAt: Date(timeIntervalSince1970: 2),
                isPinned: true
            ),
        ]

        var openedItems: [AttoLspWorkbenchHistoryPanelController.Item] = []
        let controller = AttoLspWorkbenchHistoryPanelController { openedItems.append($0) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 580))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, items: items))
        let panel = try XCTUnwrap(window.childWindows?.first)
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchHistoryPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspWorkbenchHistoryPanelTable, in: root) as? NSTableView
        )

        XCTAssertTrue(controller.selectItem(id: "symbols-2"))
        XCTAssertEqual(controller.selectedItem?.id, "symbols-2")

        controller.update(items: items)
        XCTAssertEqual(controller.selectedItem?.id, "symbols-2")
        XCTAssertEqual(table.selectedRow, 1)

        searchField.stringValue = "no matching history"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 0)
        XCTAssertNil(controller.selectedItem)
        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:))))

        searchField.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(controller.selectedItem?.id, "symbols-2")
        XCTAssertEqual(table.selectedRow, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedItems, [items[1]])
    }

    func testProblemsPanelExposesStableIdentifiersAndFiltersRows() throws {
        let diagnostics = [
            EcuDiagnostic(
                range: EcuOffsetRange(start: 0, end: 4),
                severity: .error,
                code: "E001",
                source: "swift",
                message: "Cannot find value",
                relatedInformationJSON: nil,
                dataJSON: nil
            ),
            EcuDiagnostic(
                range: EcuOffsetRange(start: 10, end: 15),
                severity: .warning,
                code: "W002",
                source: "swift",
                message: "Unused import",
                relatedInformationJSON: nil,
                dataJSON: nil
            ),
        ]

        var openedDiagnostics: [EcuDiagnostic] = []
        let controller = AttoProblemsPanelController(
            titleForDiagnostic: { diagnostic in "[\(diagnostic.severity?.rawValue ?? "problem")] \(diagnostic.message)" },
            onOpen: { diagnostic in openedDiagnostics.append(diagnostic) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 580))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, diagnostics: diagnostics))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.problemsPanel)
        XCTAssertEqual(panel.title, "Problems (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.problemsPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.problemsPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter problems...")
        XCTAssertEqual(metadataLabel.stringValue, "Problems | 2 problems")
        XCTAssertEqual(table.numberOfRows, 2)

        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        controller.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: table)
        )
        controller.update(diagnostics: diagnostics, metadataText: "Problems | 2 problems")
        XCTAssertEqual(table.selectedRow, 1)

        searchField.stringValue = "no matching diagnostics"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 0)
        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:))))

        searchField.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.selectedRow, 1)

        searchField.stringValue = "warning"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedDiagnostics, [diagnostics[1]])
        XCTAssertTrue(controller.isVisible)
    }

    func testWorkspaceProblemsPanelExposesStableIdentifiersAndFiltersRows() throws {
        let diagnostics = [
            AttoLspWorkspaceDiagnosticsParser.Diagnostic(
                target: AttoLspDefinitionParser.Target(uri: "file:///project/a.swift", line: 2, utf16Character: 4),
                endLine: 2,
                endUTF16Character: 9,
                severity: 1,
                severityLabel: "error",
                code: "E001",
                source: "swift",
                message: "Cannot find value",
                resultId: "a-1"
            ),
            AttoLspWorkspaceDiagnosticsParser.Diagnostic(
                target: AttoLspDefinitionParser.Target(uri: "file:///project/b.swift", line: 0, utf16Character: 1),
                endLine: 0,
                endUTF16Character: 3,
                severity: 2,
                severityLabel: "warning",
                code: "W002",
                source: "swift",
                message: "Unused import",
                resultId: "b-1"
            ),
        ]

        var openedDiagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic] = []
        let controller = AttoProblemsPanelController(
            titleForWorkspaceDiagnostic: { diagnostic in "[\(diagnostic.severityLabel ?? "problem")] \(diagnostic.message)" },
            onOpen: { diagnostic in openedDiagnostics.append(diagnostic) },
            accessibilityIDs: .workspaceProblems
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 580))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, workspaceDiagnostics: diagnostics))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.workspaceProblemsPanel)
        XCTAssertEqual(panel.title, "Workspace Problems (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.workspaceProblemsPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.workspaceProblemsPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter workspace problems...")
        XCTAssertEqual(metadataLabel.stringValue, "Workspace Problems | 2 problems")
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "warning"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedDiagnostics, [diagnostics[1]])
        XCTAssertTrue(controller.isVisible)
    }

}
