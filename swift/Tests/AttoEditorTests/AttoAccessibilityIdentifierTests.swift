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
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.statusBarLanguageSourceLabel, in: vc.view))
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
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesReplacementField, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesReplaceAllButton, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesCaseSensitiveButton, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesWholeWordButton, in: sidebar.view))
        XCTAssertNotNil(findView(identifier: AttoAccessibilityID.findInFilesRegexButton, in: sidebar.view))
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

    func testCommandPaletteShowsCommandGroupsAndFiltersByMetadata() throws {
        let prefix = "AttoEditor.GroupedPalette"
        let controller = AttoCommandPaletteController(
            accessibilityPrefix: prefix,
            showsCommandGroups: true
        ) {
            [
                AttoCommandPaletteCommand(
                    id: "editor.duplicate_lines",
                    title: "Duplicate Line",
                    group: "Edit"
                ) {},
                AttoCommandPaletteCommand(
                    id: "lsp.rename",
                    title: "Rename Symbol",
                    group: "LSP"
                ) {},
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
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: prefix), in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.commandPaletteTable(prefix: prefix), in: root) as? NSTableView
        )

        XCTAssertEqual(table.numberOfRows, 2)
        let firstCell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(firstCell.textField?.stringValue, "Edit - Duplicate Line")

        searchField.stringValue = "LSP"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)
        let groupCell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(groupCell.textField?.stringValue, "LSP - Rename Symbol")

        searchField.stringValue = "duplicate_lines"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        XCTAssertEqual(table.numberOfRows, 1)
        let idCell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(idCell.textField?.stringValue, "Edit - Duplicate Line")
    }

    func testCommandPalettePromptsForParameterizedCommands() throws {
        let prefix = "AttoEditor.ArgumentPalette"
        let schema = AttoCommandSchema(
            parameters: [
                AttoCommandParameterSchema(
                    name: "snippet",
                    title: "Snippet",
                    kind: .string,
                    isRequired: true,
                    allowsEmptyString: false
                ),
            ]
        )

        var promptedCommandID: String?
        var receivedArguments: AttoCommandArguments?
        let controller = AttoCommandPaletteController(
            accessibilityPrefix: prefix,
            argumentProvider: { command in
                promptedCommandID = command.id
                XCTAssertEqual(command.initialArguments, ["snippet": .string("old$0")])
                return ["snippet": .string("new$0")]
            }
        ) {
            [
                AttoCommandPaletteCommand(
                    id: "editor.apply_snippet",
                    title: "Apply Snippet",
                    schema: schema,
                    promptsForArguments: true,
                    initialArguments: ["snippet": .string("old$0")]
                ) { arguments in
                    receivedArguments = arguments
                },
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
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: prefix), in: root) as? NSSearchField
        )

        XCTAssertTrue(
            controller.control(searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        )
        XCTAssertEqual(promptedCommandID, "editor.apply_snippet")
        XCTAssertEqual(receivedArguments, ["snippet": .string("new$0")])
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

    func findView(identifier: String, in root: NSView) -> NSView? {
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
