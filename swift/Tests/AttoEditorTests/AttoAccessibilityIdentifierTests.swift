import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoAccessibilityIdentifierTests: XCTestCase {
    func testMainMenuExposesStableIdentifiers() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)

        XCTAssertNotNil(findMenuItem(identifier: AttoAccessibilityID.menu("File"), in: menu))
        XCTAssertNotNil(findMenuItem(identifier: AttoAccessibilityID.menu("Edit"), in: menu))
        XCTAssertNotNil(findMenuItem(identifier: AttoAccessibilityID.menu("Selection"), in: menu))
        XCTAssertNotNil(findMenuItem(identifier: AttoAccessibilityID.menu("View"), in: menu))
        XCTAssertNotNil(findMenuItem(identifier: AttoAccessibilityID.menu("Go"), in: menu))
        XCTAssertNotNil(findMenuItem(identifier: AttoAccessibilityID.menu("WordWrap"), in: menu))

        let duplicate = try XCTUnwrap(findMenuItem(commandID: "editor.duplicate_lines", in: menu))
        XCTAssertEqual(duplicate.identifier?.rawValue, AttoAccessibilityID.commandMenuItem("editor.duplicate_lines"))
    }

    func testEditorChromeAndTabsExposeStableIdentifiers() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoAccessibilityIdentifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("main.txt")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view

        XCTAssertEqual(vc.view.identifier?.rawValue, AttoAccessibilityID.editorArea)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.tabBar, in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findReplaceBar, in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.editorContentHost, in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.editorEmptyState, in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.statusBar, in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.statusBarLanguagePopUp, in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.statusBarPositionLabel, in: vc.view))

        XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned, location: nil))
        let opened = try XCTUnwrap(vc.openFileItems().first)

        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.tabChip(opened.id), in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.tabTitle(opened.id), in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.tabCloseButton(opened.id), in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.editorPane(opened.id), in: vc.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.editorView(opened.id), in: vc.view))
    }

    func testSidebarAndSearchPanelsExposeStableIdentifiers() throws {
        let root = FileManager.default.temporaryDirectory
        let fileExplorer = AttoFileExplorerViewController(rootURL: root)
        let openedFiles = AttoOpenedFilesViewController(rootURL: root)
        let findInFiles = AttoFindInFilesViewController(rootURL: root)
        let sidebar = AttoSidebarViewController(
            fileExplorerController: fileExplorer,
            openedFilesController: openedFiles,
            findInFilesController: findInFiles
        )

        _ = sidebar.view
        XCTAssertEqual(sidebar.view.identifier?.rawValue, AttoAccessibilityID.sidebar)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.sidebarTabBar, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.sidebarTabControl, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.sidebarContentHost, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.fileExplorer, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.fileExplorerOutline, in: sidebar.view))

        sidebar.selectTab(.openedFiles)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.openedFiles, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.openedFilesTable, in: sidebar.view))

        sidebar.selectTab(.findInFiles)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFiles, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesQueryField, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesScopeControl, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesStatusLabel, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesTable, in: sidebar.view))
    }

    func testCommandPalettePanelExposesStableIdentifiers() throws {
        let prefix = "AttoEditor.TestPalette"
        let controller = AttoCommandPaletteController(accessibilityPrefix: prefix) {
            [
                AttoCommandPaletteCommand(id: "test.one", title: "Test One") {},
                AttoCommandPaletteCommand(id: "test.two", title: "Test Two") {},
            ]
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        window.makeKeyAndOrderFront(nil)
        controller.show(relativeTo: window)

        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.commandPalettePanel(prefix: prefix))
        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.commandPaletteRoot(prefix: prefix), in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: prefix), in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.commandPaletteTable(prefix: prefix), in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.commandPaletteScrollView(prefix: prefix), in: root))
    }

    func testCommandPaletteSupportsInitialQueryAndDynamicReload() throws {
        let prefix = "AttoEditor.DynamicPalette"
        var commands = [
            AttoCommandPaletteCommand(id: "symbol.alpha", title: "Alpha Symbol") {},
            AttoCommandPaletteCommand(id: "symbol.beta", title: "Beta Symbol") {},
        ]
        var searchChanges: [String] = []
        let controller = AttoCommandPaletteController(
            accessibilityPrefix: prefix,
            filtersCommands: false,
            searchTextDidChange: { searchChanges.append($0) },
            commandsProvider: { commands }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        window.makeKeyAndOrderFront(nil)
        controller.show(relativeTo: window, placeholder: "Search symbols...", initialQuery: "Project")

        let panel = try XCTUnwrap(window.childWindows?.first)
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: prefix), in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.commandPaletteTable(prefix: prefix), in: root) as? NSTableView
        )

        XCTAssertEqual(searchField.placeholderString, "Search symbols...")
        XCTAssertEqual(searchField.stringValue, "Project")
        XCTAssertEqual(table.numberOfRows, 2)

        commands = [
            AttoCommandPaletteCommand(id: "symbol.gamma", title: "Gamma Result") {},
        ]
        controller.reloadCommands()
        XCTAssertEqual(table.numberOfRows, 1)

        searchField.stringValue = "Gamma"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(searchChanges, ["Gamma"])
        XCTAssertEqual(table.numberOfRows, 1)
    }

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
        XCTAssertEqual(metadataLabel.stringValue, "Fresh | Snapshot | References")
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
        XCTAssertEqual(metadataLabel.stringValue, "Fresh | Snapshot | Document Symbols")
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
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.problemsPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter problems...")
        XCTAssertEqual(table.numberOfRows, 2)

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
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.workspaceProblemsPanelScrollView, in: root))
        XCTAssertEqual(searchField.placeholderString, "Filter workspace problems...")
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "warning"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)

        XCTAssertTrue(controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(openedDiagnostics, [diagnostics[1]])
        XCTAssertTrue(controller.isVisible)
    }

    func testCompletionPopupExposesStableIdentifiers() throws {
        let items = AttoLspCompletionParser.items(
            fromCompletionResultJSON: #"{"items":[{"label":"print","kind":3,"detail":"fn"}]}"#
        )
        XCTAssertFalse(items.isEmpty)

        let controller = AttoCompletionListController()
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let window = NSWindow(
            contentRect: hostView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.hide()
            window.close()
        }

        window.contentView = hostView
        window.makeKeyAndOrderFront(nil)
        controller.show(
            items: items,
            relativeTo: hostView,
            anchorRect: NSRect(x: 20, y: 300, width: 10, height: 18)
        ) { _, _ in }

        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, AttoAccessibilityID.completionPanel)
        let root = try XCTUnwrap(panel.contentView)
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.completionRoot, in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.completionTable, in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.completionScrollView, in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.completionPreview, in: root))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.completionPreviewScrollView, in: root))
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL
        )
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for child in root.subviews {
            if let found = findView(identifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    private func findMenuItem(commandID: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? String == commandID {
                return item
            }
            if let submenu = item.submenu, let found = findMenuItem(commandID: commandID, in: submenu) {
                return found
            }
        }
        return nil
    }

    private func findMenuItem(identifier: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.identifier?.rawValue == identifier {
                return item
            }
            if let submenu = item.submenu, let found = findMenuItem(identifier: identifier, in: submenu) {
                return found
            }
        }
        return nil
    }
}
