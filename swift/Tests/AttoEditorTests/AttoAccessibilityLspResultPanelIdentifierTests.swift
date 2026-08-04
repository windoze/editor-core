import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoAccessibilityIdentifierTests {
    func testLspLocationPanelExposesStableIdentifiersAndFiltersRows() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/location-panel.swift")
        let snapshot = AttoEditorAreaViewController.LspLocationResultSnapshot(
            kind: .references,
            items: [
                AttoLspDefinitionParser.LocationItem(
                    target: AttoLspDefinitionParser.Target(uri: fileURL.absoluteString, line: 0, utf16Character: 1),
                    fileDisplayName: "location-panel.swift"
                ),
                AttoLspDefinitionParser.LocationItem(
                    target: AttoLspDefinitionParser.Target(uri: fileURL.absoluteString, line: 8, utf16Character: 3),
                    fileDisplayName: "location-panel.swift"
                ),
            ]
        )

        var openedTargets: [AttoLspDefinitionParser.Target] = []
        let controller = AttoLspLocationPanelController { target in
            openedTargets.append(target)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 520))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, snapshot: snapshot))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.lspLocationPanel)
        XCTAssertEqual(panel.title, "References (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspLocationPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspLocationPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspLocationPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspLocationPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspLocationPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter references...")
        XCTAssertEqual(metadataLabel.stringValue, "Fresh | Snapshot | locations | References")
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = ":9:"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedTargets, [snapshot.items[1].target])
        XCTAssertTrue(controller.isVisible)
    }

    func testLspSymbolPanelExposesStableIdentifiersAndFiltersRows() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/symbol-panel.swift")
        let targetA = AttoLspDefinitionParser.Target(uri: fileURL.absoluteString, line: 0, utf16Character: 5)
        let targetB = AttoLspDefinitionParser.Target(uri: fileURL.absoluteString, line: 8, utf16Character: 7)
        let symbols = [
            AttoLspSymbolParser.Symbol(
                name: "openProject",
                detail: "fn()",
                kindLabel: "Function",
                containerName: nil,
                target: targetA,
                depth: 0
            ),
            AttoLspSymbolParser.Symbol(
                name: "Project",
                detail: nil,
                kindLabel: "Struct",
                containerName: "Atto",
                target: targetB,
                depth: 0
            ),
        ]
        let snapshot = AttoEditorAreaViewController.LspSymbolResultSnapshot(
            title: "Document Symbols",
            symbols: symbols,
            placeholder: "Filter document symbols..."
        )

        var openedTargets: [AttoLspDefinitionParser.Target] = []
        let controller = AttoLspSymbolPanelController(
            titleForSymbol: { symbol in "\(symbol.name) [\(symbol.kindLabel ?? "Symbol")]" },
            onOpen: { target in openedTargets.append(target) }
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

        XCTAssertTrue(controller.show(relativeTo: window, snapshot: snapshot))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.lspSymbolPanel)
        XCTAssertEqual(panel.title, "Document Symbols (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspSymbolPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspSymbolPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspSymbolPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.lspSymbolPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.lspSymbolPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter document symbols...")
        XCTAssertEqual(metadataLabel.stringValue, "Fresh | Snapshot | symbols | Document Symbols")
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "Struct"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedTargets, [targetB])
        XCTAssertTrue(controller.isVisible)
    }

    func testCodeLensPanelExposesStableIdentifiersAndFiltersRows() throws {
        let range = EcuOffsetRange(start: 0, end: 0)
        let items = [
            AttoLspCodeLensParser.Item(
                title: "Run Tests",
                range: range,
                lensJSON: #"{"command":{"command":"test.run","title":"Run Tests"}}"#,
                command: AttoLspCodeLensParser.Command(
                    title: "Run Tests",
                    command: "test.run",
                    commandJSON: #"{"command":"test.run","title":"Run Tests"}"#
                )
            ),
            AttoLspCodeLensParser.Item(
                title: "Preview Documentation",
                range: range,
                lensJSON: #"{"command":{"command":"doc.preview","title":"Preview Documentation"}}"#,
                command: AttoLspCodeLensParser.Command(
                    title: "Preview Documentation",
                    command: "doc.preview",
                    commandJSON: #"{"command":"doc.preview","title":"Preview Documentation"}"#
                )
            ),
        ]

        var appliedItems: [AttoLspCodeLensParser.Item] = []
        let controller = AttoCodeLensPanelController(
            titleForItem: { "\($0.title) - sample.swift:1:1" },
            onApply: { appliedItems.append($0) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 520))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, items: items))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.codeLensPanel)
        XCTAssertEqual(panel.title, "Code Lens (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.codeLensPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.codeLensPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.codeLensPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.codeLensPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.codeLensPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter code lens actions...")
        XCTAssertEqual(metadataLabel.stringValue, "Active Tab | 2 actions")
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "Preview"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(appliedItems, [items[1]])
        XCTAssertTrue(controller.isVisible)
    }

    func testInlayHintPanelExposesStableIdentifiersAndFiltersRows() throws {
        let range = EcuOffsetRange(start: 4, end: 4)
        let items = [
            AttoLspInlayHintParser.Item(
                title: ": Int",
                kindLabel: "Type",
                range: range,
                hintJSON: #"{"position":{"line":0,"character":4},"label":": Int","kind":1}"#,
                hint: nil
            ),
            AttoLspInlayHintParser.Item(
                title: "name:",
                kindLabel: "Parameter",
                range: range,
                hintJSON: #"{"position":{"line":1,"character":7},"label":[{"value":"name:"}],"kind":2}"#,
                hint: nil
            ),
        ]

        var resolvedItems: [AttoLspInlayHintParser.Item] = []
        let controller = AttoInlayHintPanelController(
            titleForItem: { "\($0.title) [\($0.kindLabel ?? "Hint")] - sample.swift:1:5" },
            onResolve: { resolvedItems.append($0) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 520))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, items: items))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.inlayHintPanel)
        XCTAssertEqual(panel.title, "Inlay Hints (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.inlayHintPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.inlayHintPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.inlayHintPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.inlayHintPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.inlayHintPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter inlay hints...")
        XCTAssertEqual(metadataLabel.stringValue, "Active Tab | 2 hints")
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "Parameter"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(resolvedItems, [items[1]])
        XCTAssertTrue(controller.isVisible)
    }

    func testDocumentLinkPanelExposesStableIdentifiersAndFiltersRows() throws {
        let range = EcuOffsetRange(start: 0, end: 4)
        let items = [
            AttoLspDocumentLinkParser.Item(
                title: "https://example.com/docs",
                target: "https://example.com/docs",
                tooltip: "Open docs",
                range: range,
                linkJSON: #"{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"target":"https://example.com/docs","tooltip":"Open docs"}"#,
                link: nil
            ),
            AttoLspDocumentLinkParser.Item(
                title: "Resolve project link",
                target: nil,
                tooltip: "Resolve project link",
                range: range,
                linkJSON: #"{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":4}},"tooltip":"Resolve project link","data":{"id":1}}"#,
                link: nil
            ),
        ]

        var openedItems: [AttoLspDocumentLinkParser.Item] = []
        let controller = AttoDocumentLinkPanelController(
            titleForItem: { "\($0.title) - sample.swift:1:1" },
            onOpen: { openedItems.append($0) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 540))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, items: items))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.documentLinkPanel)
        XCTAssertEqual(panel.title, "Document Links (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.documentLinkPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentLinkPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentLinkPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentLinkPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.documentLinkPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter document links...")
        XCTAssertEqual(metadataLabel.stringValue, "Active Tab | 2 links")
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "Resolve"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedItems, [items[1]])
        XCTAssertTrue(controller.isVisible)
    }

    func testDocumentColorPanelExposesStableIdentifiersAndFiltersRows() throws {
        let items = [
            AttoLspDocumentColorParser.Item(
                range: EcuSelectionRange(start: 0, end: 7),
                startLine: 0,
                startUTF16Character: 12,
                color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
            ),
            AttoLspDocumentColorParser.Item(
                range: EcuSelectionRange(start: 8, end: 15),
                startLine: 1,
                startUTF16Character: 4,
                color: AttoLspDocumentColorParser.Color(red: 0, green: 0.4, blue: 1, alpha: 1)
            ),
        ]

        var openedItems: [AttoLspDocumentColorParser.Item] = []
        let controller = AttoDocumentColorPanelController(
            titleForItem: { AttoLspDocumentColorParser.displayTitle(for: $0) },
            colorForItem: { _ in NSColor.red },
            onOpen: { openedItems.append($0) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 540))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(relativeTo: window, items: items))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.documentColorPanel)
        XCTAssertEqual(panel.title, "Document Colors (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.documentColorPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentColorPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentColorPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentColorPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.documentColorPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter document colors...")
        XCTAssertEqual(metadataLabel.stringValue, "Active Tab | 2 colors")
        XCTAssertEqual(table.numberOfRows, 2)

        let row = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.documentColorPanelSwatch, in: row))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.documentColorPanelRowTitle, in: row))

        searchField.stringValue = "#0066FF"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedItems, [items[1]])
        XCTAssertTrue(controller.isVisible)
    }

    func testHierarchyPanelExposesStableIdentifiersAndFiltersRows() throws {
        let entries = [
            AttoLspHierarchyParser.Entry(
                name: "render",
                detail: "View.swift",
                kindLabel: "function",
                target: AttoLspDefinitionParser.Target(uri: "file:///tmp/View.swift", line: 4, utf16Character: 8),
                relatedRangeCount: 2
            ),
            AttoLspHierarchyParser.Entry(
                name: "layout",
                detail: "Layout.swift",
                kindLabel: "method",
                target: AttoLspDefinitionParser.Target(uri: "file:///tmp/Layout.swift", line: 8, utf16Character: 4),
                relatedRangeCount: 1
            ),
        ]

        var openedEntries: [AttoLspHierarchyParser.Entry] = []
        let controller = AttoHierarchyPanelController(
            titleForEntry: { "\($0.name) - \($0.detail ?? "")" },
            onOpen: { openedEntries.append($0) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 540))
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(controller.show(
            relativeTo: window,
            snapshot: AttoHierarchyPanelController.Snapshot(title: "Incoming Calls", entries: entries)
        ))
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.hierarchyPanel)
        XCTAssertEqual(panel.title, "Hierarchy (2)")

        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.hierarchyPanelRoot, in: root))
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.hierarchyPanelSearchField, in: root) as? NSSearchField
        )
        let metadataLabel = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.hierarchyPanelMetadataLabel, in: root) as? NSTextField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.hierarchyPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.hierarchyPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter hierarchy results...")
        XCTAssertEqual(metadataLabel.stringValue, "Incoming Calls | 2 results")
        XCTAssertEqual(table.numberOfRows, 2)

        let row = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.hierarchyPanelRowTitle, in: row))

        searchField.stringValue = "layout"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedEntries, [entries[1]])
        XCTAssertTrue(controller.isVisible)
    }

}
