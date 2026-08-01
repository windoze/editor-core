import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorCommandTests: XCTestCase {
    func testDefaultCommandPaletteIncludesCoreEditorCommandIDs() throws {
        let delegate = AttoAppDelegate()
        let ids = Set(delegate._defaultCommandsForTesting().map(\.id))

        XCTAssertTrue(ids.contains("editor.duplicate_lines"))
        XCTAssertTrue(ids.contains("file.close_tab"))
        XCTAssertTrue(ids.contains("editor.delete_lines"))
        XCTAssertTrue(ids.contains("editor.move_lines_up"))
        XCTAssertTrue(ids.contains("editor.move_lines_down"))
        XCTAssertTrue(ids.contains("editor.join_lines"))
        XCTAssertTrue(ids.contains("editor.split_line"))
        XCTAssertTrue(ids.contains("editor.toggle_line_comment"))
        XCTAssertTrue(ids.contains("editor.fold_selection"))
        XCTAssertTrue(ids.contains("editor.unfold"))
        XCTAssertTrue(ids.contains("editor.unfold_all"))
        XCTAssertTrue(ids.contains("view.wrap.word"))
        XCTAssertTrue(ids.contains("view.split_right"))
        XCTAssertTrue(ids.contains("view.focus_next_pane"))
        XCTAssertTrue(ids.contains("view.focus_previous_pane"))
        XCTAssertTrue(ids.contains("view.close_pane"))
        XCTAssertTrue(ids.contains("lsp.go_to_definition"))
        XCTAssertTrue(ids.contains("lsp.go_to_declaration"))
        XCTAssertTrue(ids.contains("lsp.go_to_type_definition"))
        XCTAssertTrue(ids.contains("lsp.go_to_implementation"))
        XCTAssertTrue(ids.contains("lsp.find_references"))
    }

    func testKeymapParsesSublimeStyleBindingsAndOverridesDefaults() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          { "keys": ["cmd+shift+l"], "command": "editor.duplicate_lines" },
          { "key": "super+/", "command": "editor.toggle_line_comment" }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let user = AttoKeymap.loadUserBindings(env: env)
        XCTAssertEqual(user["editor.duplicate_lines"]?.keyEquivalent, "l")
        XCTAssertEqual(
            user["editor.duplicate_lines"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command, .shift]
        )
        XCTAssertEqual(user["editor.toggle_line_comment"]?.keyEquivalent, "/")
        XCTAssertEqual(
            user["editor.toggle_line_comment"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command]
        )

        let resolved = AttoKeymap.resolvedBindings(env: env)
        XCTAssertEqual(resolved["editor.duplicate_lines"]?.keyEquivalent, "l")
        XCTAssertEqual(resolved["file.save"]?.keyEquivalent, "s")
    }

    func testMainMenuItemsUseCommandIDsAndResolvedKeymap() throws {
        let delegate = AttoAppDelegate(
            keyBindings: [
                "editor.duplicate_lines": AttoKeyBinding(keyEquivalent: "l", modifiers: [.command, .shift]),
            ]
        )
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)

        let item = try XCTUnwrap(findMenuItem(commandID: "editor.duplicate_lines", in: menu))
        XCTAssertEqual(item.representedObject as? String, "editor.duplicate_lines")
        XCTAssertEqual(item.identifier?.rawValue, "AttoCommand.editor.duplicate_lines")
        XCTAssertEqual(item.action, #selector(AttoAppDelegate.commandMenuItemClicked(_:)))
        XCTAssertTrue((item.target as AnyObject) === delegate)
        XCTAssertEqual(item.keyEquivalent, "l")
        XCTAssertEqual(
            item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask),
            [.command, .shift]
        )

        XCTAssertNotNil(findMenuItem(commandID: "view.wrap.word", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.split_right", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.focus_next_pane", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.focus_previous_pane", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.close_pane", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.fold_selection", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.go_to_definition", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.find_references", in: menu))
    }

    func testExecuteCommandUsesRegisteredCommandIDs() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        XCTAssertTrue(delegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertFalse(delegate.executeCommand(id: "missing.command"))
    }

    func testActiveEditorCommandJSONMutatesTextAndDirtyState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("a.txt")
        try "a\nb\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"duplicate_lines"}"#))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "a\na\nb\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testToggleLineCommentUsesFileLanguageDefault() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("script.py")
        try "print(1)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "# print(1)\n")
    }

    func testSplitRightCreatesSharedDocumentPane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("split.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertEqual(findSubviews(of: EditorCoreSkiaView.self, in: vc.view).count, 1)
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(editorViews.count, 2)

        try editorViews[1].editor.insertText("!")
        XCTAssertEqual(try editorViews[0].editor.text(), "!abc")
        XCTAssertEqual(try editorViews[1].editor.text(), "!abc")

        let clickPoint = editorViews[0].convert(NSPoint(x: 5, y: 5), to: nil)
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        ) else {
            XCTFail("Unable to construct split pane mouseDown event")
            return
        }
        editorViews[0].mouseDown(with: mouseDown)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"?"}"#))
        XCTAssertEqual(try editorViews[0].editor.text(), "?!abc")
    }

    func testPaneFocusAndCloseCommandsUseActivePane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("panes.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()
        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(editorViews.count, 2)

        XCTAssertTrue(vc.focusPreviousPaneInActiveTab())
        XCTAssertTrue(vc.focusNextPaneInActiveTab())
        XCTAssertTrue(vc.closeActivePane())
        vc.view.layoutSubtreeIfNeeded()

        let remaining = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining[0] === editorViews[0])
        XCTAssertFalse(vc.closeActivePane())
    }

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL
        )
    }

    @discardableResult
    private func attachToWindow(_ vc: AttoEditorAreaViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
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

    private func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var out: [T] = []
        if let v = root as? T {
            out.append(v)
        }
        for child in root.subviews {
            out.append(contentsOf: findSubviews(of: type, in: child))
        }
        return out
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
}
