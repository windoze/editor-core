import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var commandPaletteController: AttoCommandPaletteController?
    private var quickOpenController: AttoCommandPaletteController?
    private var preferencesWindowController: AttoPreferencesWindowController?

    private let library = EditorCoreUIFFILibrary()
    private let sessionManager = AttoSessionManager()

    private var windows: [AttoWindowContext] = []
    private var activeWindowID: UUID?
    private var keyBindings: [String: AttoKeyBinding]

    var ipcServer: AttoIpcServer?
    var createDefaultWindowOnLaunch: Bool = true

    override init() {
        self.keyBindings = AttoKeymap.resolvedBindings()
        super.init()
    }

    init(keyBindings: [String: AttoKeyBinding]) {
        self.keyBindings = keyBindings
        super.init()
    }

    private struct StaticEditorJSONCommand {
        let id: String
        let title: String
        let commandJSON: String
    }

    private enum CommandAvailabilityRequirement {
        case none
        case activeWindow
        case activeEditor
        case multiplePanes

        var requiresEditor: Bool {
            switch self {
            case .activeEditor, .multiplePanes:
                return true
            case .none, .activeWindow:
                return false
            }
        }
    }

    private struct CommandMetadata {
        let group: String
        let requirement: CommandAvailabilityRequirement
    }

    private static let staticEditorJSONCommands: [StaticEditorJSONCommand] = [
        .init(id: "editor.duplicate_lines", title: "Edit: Duplicate Line", commandJSON: #"{"kind":"edit","op":"duplicate_lines"}"#),
        .init(id: "editor.delete_lines", title: "Edit: Delete Line", commandJSON: #"{"kind":"edit","op":"delete_lines"}"#),
        .init(id: "editor.move_lines_up", title: "Edit: Move Line Up", commandJSON: #"{"kind":"edit","op":"move_lines_up"}"#),
        .init(id: "editor.move_lines_down", title: "Edit: Move Line Down", commandJSON: #"{"kind":"edit","op":"move_lines_down"}"#),
        .init(id: "editor.join_lines", title: "Edit: Join Lines", commandJSON: #"{"kind":"edit","op":"join_lines"}"#),
        .init(id: "editor.split_line", title: "Edit: Split Line", commandJSON: #"{"kind":"edit","op":"split_line"}"#),
        .init(id: "editor.indent", title: "Edit: Indent", commandJSON: #"{"kind":"edit","op":"indent"}"#),
        .init(id: "editor.outdent", title: "Edit: Outdent", commandJSON: #"{"kind":"edit","op":"outdent"}"#),
        .init(id: "editor.delete_to_prev_tab_stop", title: "Edit: Delete to Previous Tab Stop", commandJSON: #"{"kind":"edit","op":"delete_to_prev_tab_stop"}"#),
        .init(id: "editor.snippet_next_placeholder", title: "Edit: Snippet Next Placeholder", commandJSON: #"{"kind":"cursor","op":"snippet_next_placeholder"}"#),
        .init(id: "editor.snippet_prev_placeholder", title: "Edit: Snippet Previous Placeholder", commandJSON: #"{"kind":"cursor","op":"snippet_prev_placeholder"}"#),
        .init(id: "editor.add_next_occurrence", title: "Edit: Add Next Occurrence", commandJSON: #"{"kind":"cursor","op":"add_next_occurrence"}"#),
        .init(id: "editor.add_all_occurrences", title: "Edit: Add All Occurrences", commandJSON: #"{"kind":"cursor","op":"add_all_occurrences"}"#),
        .init(id: "editor.select_word", title: "Edit: Select Word", commandJSON: #"{"kind":"cursor","op":"select_word"}"#),
        .init(id: "editor.select_line", title: "Edit: Select Line", commandJSON: #"{"kind":"cursor","op":"select_line"}"#),
        .init(id: "editor.expand_selection", title: "Edit: Expand Selection", commandJSON: #"{"kind":"cursor","op":"expand_selection"}"#),
        .init(id: "editor.add_cursor_above", title: "Edit: Add Cursor Above", commandJSON: #"{"kind":"cursor","op":"add_cursor_above"}"#),
        .init(id: "editor.add_cursor_below", title: "Edit: Add Cursor Below", commandJSON: #"{"kind":"cursor","op":"add_cursor_below"}"#),
        .init(id: "view.wrap.none", title: "View: Word Wrap Off", commandJSON: #"{"kind":"view","op":"set_wrap_mode","mode":"none"}"#),
        .init(id: "view.wrap.char", title: "View: Word Wrap by Character", commandJSON: #"{"kind":"view","op":"set_wrap_mode","mode":"char"}"#),
        .init(id: "view.wrap.word", title: "View: Word Wrap by Word", commandJSON: #"{"kind":"view","op":"set_wrap_mode","mode":"word"}"#),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .attoPreferencesDidChange,
            object: nil
        )

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        let windowsWereEmptyAtLaunch = windows.isEmpty
        var didRestoreSession = false

        if createDefaultWindowOnLaunch {
            if windowsWereEmptyAtLaunch {
                didRestoreSession = restoreSessionIfEligible(contentSize: contentSize)
                if didRestoreSession == false {
                    _ = createWindow(workspaceRootURL: AttoAppDelegate.defaultRepoRootURL(), contentSize: contentSize)
                }
            }

            if windows.isEmpty == false {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }

        commandPaletteController = AttoCommandPaletteController(
            commandsProvider: { [weak self] in
                self?.defaultCommands() ?? []
            }
        )

        quickOpenController = AttoCommandPaletteController(
            commandsProvider: { [weak self] in
                self?.quickOpenCommands() ?? []
            }
        )

        // Demo: 仅在开发态启动 GUI 时打开一个真实 Rust 文件，确保 LSP/theme 可见。
        //
        // 规则：
        // - `.app` bundle 启动：不做 demo 行为（避免对最终用户造成困扰）
        // - session restore 成功：不做 demo 行为
        // - IPC spool 已经创建了窗口：不做 demo 行为
        let isBundledApp = (Bundle.main.bundleURL.pathExtension == "app")
        if createDefaultWindowOnLaunch,
           isBundledApp == false,
           windowsWereEmptyAtLaunch,
           didRestoreSession == false,
           let first = windows.first
        {
            let initial = first.workspaceRootURL.appendingPathComponent("crates/tui-editor/src/main.rs")
            if FileManager.default.fileExists(atPath: initial.path) {
                first.rememberRecentFile(initial)
                first.editorAreaController.openFile(url: initial)
                first.fileExplorerController.revealFile(initial)
            }
        }

        if windows.isEmpty == false {
            scheduleSessionSave(reason: "did_finish_launching")
        }

        // Remove system window-tabbing menu items (e.g. "Show Tab Bar") from standard menus.
        removeSystemWindowTabbingMenuItems()

        // Ensure preferences are applied (also covers env-var fallbacks).
        applyEditorPreferencesToAllWindows()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if windows.isEmpty == false {
            sessionManager.saveNow(reason: "will_terminate", capture: { [weak self] in
                self?.makeSessionSnapshot()
            })
        }
        ipcServer?.stop()
    }

    // MARK: - Menu actions

    @objc func openFolderMenuClicked(_ sender: Any?) {
        let defaultDir = activeWindow()?.workspaceRootURL ?? AttoAppDelegate.defaultRepoRootURL()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to open."
        panel.directoryURL = defaultDir

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)
        let ctx = createWindow(workspaceRootURL: url.standardizedFileURL, contentSize: contentSize)
        focusWindow(ctx)
    }

    @objc func openFileMenuClicked(_ sender: Any?) {
        guard let ctx = ensureActiveWindowForMenuActions() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a file to open."
        panel.directoryURL = ctx.workspaceRootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        ctx.rememberRecentFile(url)
        ctx.editorAreaController.openFile(url: url)
        ctx.fileExplorerController.revealFile(url)
    }

    @objc func newFileMenuClicked(_ sender: Any?) {
        guard let ctx = ensureActiveWindowForMenuActions() else { return }

        let fm = FileManager.default
        let dir = ctx.workspaceRootURL.standardizedFileURL

        var n = 1
        var url: URL
        while true {
            url = dir.appendingPathComponent("untitled-\(n).txt", isDirectory: false)
            // “New File” should not touch disk; it only creates a new in-memory buffer.
            // Still, we want a stable, human-friendly display name, so we generate a file URL
            // under the workspace root and keep it unique across BOTH:
            // 1) existing files on disk, and
            // 2) currently opened (possibly unsaved) tabs.
            if fm.fileExists(atPath: url.path) == false, ctx.editorAreaController.containsFile(url: url) == false {
                break
            }
            n += 1
            if n > 9_999 {
                NSSound.beep()
                NSLog("AttoEditor: new file name search exhausted under %@", dir.path)
                return
            }
        }

        _ = ctx.editorAreaController.openFile(url: url, mode: .pinned, isUntitled: true)
    }

    private func ensureActiveWindowForMenuActions() -> AttoWindowContext? {
        if let ctx = activeWindow() { return ctx }

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        let ctx = createWindow(workspaceRootURL: AttoAppDelegate.defaultRepoRootURL(), contentSize: contentSize)
        focusWindow(ctx)
        return ctx
    }

    @objc func closeTabMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.closeActiveTab()
    }

    @objc func saveMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.saveActiveTab()
    }

    @objc func toggleSidebarMenuClicked(_ sender: Any?) {
        activeWindow()?.toggleSidebar()
    }

    @objc func toggleMinimapMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.toggleMinimapForActiveTab()
    }

    @objc func commandPaletteMenuClicked(_ sender: Any?) {
        showCommandPalette()
    }

    @objc func goToFileMenuClicked(_ sender: Any?) {
        showQuickOpen()
    }

    @objc func findMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.showFindBar()
    }

    @objc func replaceMenuClicked(_ sender: Any?) {
        activeWindow()?.editorAreaController.showReplaceBar()
    }

    @objc func findInFilesMenuClicked(_ sender: Any?) {
        activeWindow()?.showFindInFilesSidebar()
    }

    @objc func preferencesMenuClicked(_ sender: Any?) {
        showPreferencesWindow()
    }

    @objc func commandMenuItemClicked(_ sender: Any?) {
        let commandID: String?
        if let item = sender as? NSMenuItem {
            commandID = item.representedObject as? String
        } else {
            commandID = sender as? String
        }

        guard let commandID else {
            NSSound.beep()
            return
        }
        executeCommand(id: commandID)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let commandID = menuItem.representedObject as? String else { return true }
        return commandIsEnabled(commandID: commandID)
    }

    // MARK: - Command palette integration

    private func showCommandPalette() {
        guard let win = activeWindow()?.window else { return }
        commandPaletteController?.show(relativeTo: win)
    }

    private func showQuickOpen() {
        guard let win = activeWindow()?.window else { return }
        quickOpenController?.show(relativeTo: win, placeholder: "Type a file name to open…")
    }

    private func defaultCommands() -> [AttoCommandPaletteCommand] {
        var commands: [AttoCommandPaletteCommand] = [
            .init(id: "file.new", title: "File: New File") { [weak self] in
                self?.newFileMenuClicked(nil)
            },
            .init(id: "file.open_folder", title: "File: Open Folder…") { [weak self] in
                self?.openFolderMenuClicked(nil)
            },
            .init(id: "file.open_file", title: "File: Open File…") { [weak self] in
                self?.openFileMenuClicked(nil)
            },
            .init(id: "file.save", title: "File: Save") { [weak self] in
                self?.saveMenuClicked(nil)
            },
            .init(id: "file.close_tab", title: "File: Close Tab") { [weak self] in
                self?.closeTabMenuClicked(nil)
            },
            .init(id: "editor.format_document", title: "Edit: Format Document") { [weak self] in
                self?.activeWindow()?.editorAreaController.formatDocumentWithLspInActiveTab()
            },
            .init(id: "editor.format_selection", title: "Edit: Format Selection") { [weak self] in
                self?.activeWindow()?.editorAreaController.formatSelectionWithLspInActiveTab()
            },
            .init(id: "editor.find", title: "Edit: Find") { [weak self] in
                self?.activeWindow()?.editorAreaController.showFindBar()
            },
            .init(id: "editor.replace", title: "Edit: Replace") { [weak self] in
                self?.activeWindow()?.editorAreaController.showReplaceBar()
            },
            .init(id: "view.toggle_sidebar", title: "View: Toggle Sidebar") { [weak self] in
                self?.activeWindow()?.toggleSidebar()
            },
            .init(id: "view.toggle_minimap", title: "View: Toggle Minimap") { [weak self] in
                self?.activeWindow()?.editorAreaController.toggleMinimapForActiveTab()
            },
            .init(id: "view.split_right", title: "View: Split Right") { [weak self] in
                self?.activeWindow()?.editorAreaController.splitActiveTabRight()
            },
            .init(id: "view.focus_next_pane", title: "View: Focus Next Pane") { [weak self] in
                self?.activeWindow()?.editorAreaController.focusNextPaneInActiveTab()
            },
            .init(id: "view.focus_previous_pane", title: "View: Focus Previous Pane") { [weak self] in
                self?.activeWindow()?.editorAreaController.focusPreviousPaneInActiveTab()
            },
            .init(id: "view.close_pane", title: "View: Close Pane") { [weak self] in
                self?.activeWindow()?.editorAreaController.closeActivePane()
            },
            .init(id: "workbench.command_palette", title: "AttoEditor: Command Palette") { [weak self] in
                self?.showCommandPalette()
            },
            .init(id: "go.file", title: "Go: Go to File…") { [weak self] in
                self?.showQuickOpen()
            },
            .init(id: "search.find_in_files", title: "Search: Find in Files") { [weak self] in
                self?.activeWindow()?.showFindInFilesSidebar()
            },
            .init(id: "workbench.preferences", title: "AttoEditor: Preferences…") { [weak self] in
                self?.showPreferencesWindow()
            },
            .init(id: "go.back", title: "Go: Back") { [weak self] in
                self?.activeWindow()?.editorAreaController.jumpBackInActiveTab()
            },
            .init(id: "go.forward", title: "Go: Forward") { [weak self] in
                self?.activeWindow()?.editorAreaController.jumpForwardInActiveTab()
            },
            .init(id: "go.matching_bracket", title: "Go: Go to Matching Bracket") { [weak self] in
                self?.activeWindow()?.editorAreaController.moveToMatchingBracketInActiveTab()
            },
            .init(id: "lsp.go_to_definition", title: "LSP: Go to Definition") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToDefinitionInActiveTab()
            },
            .init(id: "lsp.go_to_declaration", title: "LSP: Go to Declaration") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToDeclarationInActiveTab()
            },
            .init(id: "lsp.go_to_type_definition", title: "LSP: Go to Type Definition") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToTypeDefinitionInActiveTab()
            },
            .init(id: "lsp.go_to_implementation", title: "LSP: Go to Implementation") { [weak self] in
                self?.activeWindow()?.editorAreaController.goToImplementationInActiveTab()
            },
            .init(id: "lsp.find_references", title: "LSP: Find References") { [weak self] in
                self?.activeWindow()?.editorAreaController.findReferencesInActiveTab()
            },
            .init(id: "lsp.rename", title: "LSP: Rename Symbol") { [weak self] in
                self?.activeWindow()?.editorAreaController.promptRenameSymbolInActiveTab()
            },
            .init(id: "lsp.code_actions", title: "LSP: Code Actions") { [weak self] in
                self?.activeWindow()?.editorAreaController.showCodeActionsInActiveTab()
            },
            .init(id: "lsp.quick_fix", title: "LSP: Quick Fixes") { [weak self] in
                self?.activeWindow()?.editorAreaController.showQuickFixesInActiveTab()
            },
            .init(id: "lsp.refactor", title: "LSP: Refactor Actions") { [weak self] in
                self?.activeWindow()?.editorAreaController.showRefactorActionsInActiveTab()
            },
            .init(id: "lsp.source_actions", title: "LSP: Source Actions") { [weak self] in
                self?.activeWindow()?.editorAreaController.showSourceActionsInActiveTab()
            },
            .init(id: "lsp.organize_imports", title: "LSP: Organize Imports") { [weak self] in
                self?.activeWindow()?.editorAreaController.organizeImportsInActiveTab()
            },
            .init(id: "lsp.fix_all", title: "LSP: Fix All") { [weak self] in
                self?.activeWindow()?.editorAreaController.fixAllInActiveTab()
            },
            .init(id: "lsp.problems", title: "LSP: Problems") { [weak self] in
                self?.activeWindow()?.editorAreaController.showProblemsInActiveTab()
            },
            .init(id: "lsp.document_symbols", title: "LSP: Document Symbols") { [weak self] in
                self?.activeWindow()?.editorAreaController.showDocumentSymbolsInActiveTab()
            },
            .init(id: "lsp.workspace_symbols", title: "LSP: Workspace Symbols") { [weak self] in
                self?.activeWindow()?.editorAreaController.showWorkspaceSymbolsInActiveTab()
            },
            .init(id: "lsp.completion", title: "LSP: Completion") { [weak self] in
                self?.activeWindow()?.editorAreaController.showCompletionsInActiveTab()
            },
            .init(id: "lsp.signature_help", title: "LSP: Signature Help") { [weak self] in
                self?.activeWindow()?.editorAreaController.showSignatureHelpInActiveTab()
            },
        ]

        commands.append(contentsOf: editorCommandPaletteCommands())
        return commands.map(commandWithCurrentContext(_:))
    }

    func _defaultCommandsForTesting() -> [AttoCommandPaletteCommand] {
        defaultCommands()
    }

    func _keyBindingForTesting(commandID: String) -> AttoKeyBinding? {
        keyBinding(forCommandID: commandID)
    }

    func _commandIsEnabledForTesting(commandID: String) -> Bool {
        commandIsEnabled(commandID: commandID)
    }

    func _createWindowForTesting(workspaceRootURL: URL) -> AttoWindowContext {
        createWindow(
            workspaceRootURL: workspaceRootURL,
            contentSize: AttoWindowSizing.preferredContentSize,
            centerOnShow: false
        )
    }

    @discardableResult
    func executeCommand(id commandID: String) -> Bool {
        guard let command = defaultCommands().first(where: { $0.id == commandID }) else {
            NSSound.beep()
            NSLog("AttoEditor: unknown command id %@", commandID)
            return false
        }
        guard command.isEnabled else {
            NSSound.beep()
            return false
        }
        command.run()
        return true
    }

    func keyBinding(forCommandID commandID: String) -> AttoKeyBinding? {
        keyBindings[commandID]
    }

    private func editorCommandPaletteCommands() -> [AttoCommandPaletteCommand] {
        var commands = Self.staticEditorJSONCommands.map { spec in
            AttoCommandPaletteCommand(id: spec.id, title: spec.title) { [weak self] in
                self?.activeWindow()?.editorAreaController.executeActiveEditorCommandJSON(spec.commandJSON)
            }
        }

        commands.append(contentsOf: [
            .init(id: "editor.toggle_line_comment", title: "Edit: Toggle Line Comment") { [weak self] in
                self?.activeWindow()?.editorAreaController.toggleLineCommentInActiveTab()
            },
            .init(id: "editor.fold_selection", title: "Edit: Fold Selection") { [weak self] in
                self?.activeWindow()?.editorAreaController.foldSelectionInActiveTab()
            },
            .init(id: "editor.unfold", title: "Edit: Unfold at Cursor") { [weak self] in
                self?.activeWindow()?.editorAreaController.unfoldAtCursorInActiveTab()
            },
            .init(id: "editor.unfold_all", title: "Edit: Unfold All") { [weak self] in
                self?.activeWindow()?.editorAreaController.unfoldAllInActiveTab()
            },
        ])

        return commands
    }

    private func commandWithCurrentContext(_ command: AttoCommandPaletteCommand) -> AttoCommandPaletteCommand {
        let metadata = commandMetadata(commandID: command.id, title: command.title)
        return AttoCommandPaletteCommand(
            id: command.id,
            title: command.title,
            group: metadata.group,
            isEnabled: commandIsEnabled(requirement: metadata.requirement),
            requiresEditor: metadata.requirement.requiresEditor,
            run: command.run
        )
    }

    private func commandIsEnabled(commandID: String) -> Bool {
        commandIsEnabled(requirement: commandMetadata(commandID: commandID, title: commandID).requirement)
    }

    private func commandIsEnabled(requirement: CommandAvailabilityRequirement) -> Bool {
        switch requirement {
        case .none:
            return true
        case .activeWindow:
            return activeWindow() != nil
        case .activeEditor:
            return activeWindow()?.editorAreaController.hasActiveEditorForCommands == true
        case .multiplePanes:
            return activeWindow()?.editorAreaController.hasMultiplePanesForCommands == true
        }
    }

    private func commandMetadata(commandID: String, title: String) -> CommandMetadata {
        let group: String = {
            if let prefix = title.split(separator: ":", maxSplits: 1).first,
               prefix.isEmpty == false,
               prefix.count < title.count
            {
                return String(prefix)
            }

            if commandID.hasPrefix("file.") { return "File" }
            if commandID.hasPrefix("editor.") { return "Edit" }
            if commandID.hasPrefix("view.") { return "View" }
            if commandID.hasPrefix("go.") { return "Go" }
            if commandID.hasPrefix("search.") { return "Search" }
            if commandID.hasPrefix("lsp.") { return "LSP" }
            if commandID.hasPrefix("workbench.") { return "AttoEditor" }
            return "General"
        }()

        let requirement: CommandAvailabilityRequirement = {
            switch commandID {
            case "file.open_folder", "file.open_file", "file.new", "workbench.command_palette", "workbench.preferences":
                return .none
            case "go.file", "search.find_in_files", "view.toggle_sidebar":
                return .activeWindow
            case "view.focus_next_pane", "view.focus_previous_pane", "view.close_pane":
                return .multiplePanes
            default:
                if commandID == "file.save" || commandID == "file.close_tab" {
                    return .activeEditor
                }
                if commandID.hasPrefix("editor.")
                    || commandID.hasPrefix("lsp.")
                    || commandID.hasPrefix("view.wrap.")
                    || commandID == "view.toggle_minimap"
                    || commandID == "view.split_right"
                    || commandID == "go.back"
                    || commandID == "go.forward"
                    || commandID == "go.matching_bracket"
                {
                    return .activeEditor
                }
                return .none
            }
        }()

        return CommandMetadata(group: group, requirement: requirement)
    }

    // MARK: - Preferences

    @objc private func preferencesDidChange(_ notification: Notification) {
        applyEditorPreferencesToAllWindows()
    }

    private func showPreferencesWindow() {
        if preferencesWindowController == nil {
            preferencesWindowController = AttoPreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func applyEditorPreferencesToAllWindows() {
        let registry = AttoThemeManager.loadRegistry()
        let effectiveThemeName = AttoPreferences.shared.effectiveThemeName
        let resolved = AttoThemeManager.resolveSkiaTheme(themeName: effectiveThemeName, registry: registry)

        for ctx in windows {
            ctx.editorAreaController.applyTheme(resolved.theme)
            ctx.editorAreaController.applyEditorPreferences()
        }
    }

    private func quickOpenCommands() -> [AttoCommandPaletteCommand] {
        guard let ctx = activeWindow() else { return [] }
        let editorAreaController = ctx.editorAreaController
        let fileExplorerController = ctx.fileExplorerController
        let all = ctx.fileIndex.entries()

        var out: [AttoCommandPaletteCommand] = []
        var seen: Set<URL> = Set()

        for url in ctx.recentFiles {
            let u = url.standardizedFileURL
            if seen.contains(u) { continue }
            seen.insert(u)
            let title = ctx.relativePathForDisplay(u)
            out.append(.init(title: title) { [weak self] in
                self?.activeWindow()?.rememberRecentFile(u)
                editorAreaController.openFile(url: u, mode: .pinned)
                fileExplorerController.revealFile(u)
            })
        }

        for entry in all {
            let u = entry.url.standardizedFileURL
            if seen.contains(u) { continue }
            seen.insert(u)
            out.append(.init(title: entry.relativePath) { [weak self] in
                self?.activeWindow()?.rememberRecentFile(u)
                editorAreaController.openFile(url: u, mode: .pinned)
                fileExplorerController.revealFile(u)
            })
        }

        return out
    }

    // MARK: - macOS window tabbing (disable + hide menu items)

    private func removeSystemWindowTabbingMenuItems() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }

        let actionNamesToRemove: Set<String> = [
            "toggleTabBar:",
            "showTabBar:",
            "showAllTabs:",
            "selectNextTab:",
            "selectPreviousTab:",
            "moveTabToNewWindow:",
            "mergeAllWindows:",
        ]

        let titlesToRemove: Set<String> = [
            "Show Tab Bar",
            "Hide Tab Bar",
            "Show All Tabs",
        ]

        func strip(menu: NSMenu) {
            // Iterate backwards so removal doesn't invalidate indices.
            for item in menu.items.reversed() {
                if titlesToRemove.contains(item.title) {
                    menu.removeItem(item)
                    continue
                }
                if let action = item.action {
                    let name = NSStringFromSelector(action)
                    if actionNamesToRemove.contains(name) {
                        menu.removeItem(item)
                        continue
                    }
                }
                if let sub = item.submenu {
                    strip(menu: sub)
                }
            }
        }

        strip(menu: mainMenu)
    }

    // MARK: - Helpers

    private static func defaultRepoRootURL() -> URL {
        // Finder 双击启动 `.app` 时，进程 cwd 往往是 `/`，用它作为默认 workspace root 很奇怪。
        // 这里把 bundle 启动的默认目录设为用户 Home。
        if Bundle.main.bundleURL.pathExtension == "app" {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        // 开发态：尝试从源码路径推导 repo root（只在本仓库内构建/运行时成立）。
        let candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AttoEditor
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // swift
            .deletingLastPathComponent() // repo root
            .standardizedFileURL

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate
        }

        // 兜底：如果 binary 被移动（例如打包后的裸可执行文件），则用 cwd；若 cwd 不存在则用 Home。
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL
        if FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDir), isDir.boolValue {
            return cwd
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Session (restore/save)

    private func makeSessionSnapshot() -> AttoSessionSnapshot? {
        guard windows.isEmpty == false else { return nil }

        let activeIndex: Int? = {
            guard let id = activeWindowID else { return nil }
            return windows.firstIndex(where: { $0.id == id })
        }()

        let windowSnaps = windows.map { $0.makeSessionSnapshot() }
        return AttoSessionSnapshot(
            schemaVersion: AttoSessionSnapshot.currentSchemaVersion,
            savedAt: Date(),
            activeWindowIndex: activeIndex,
            windows: windowSnaps
        )
    }

    private func scheduleSessionSave(reason: String) {
        sessionManager.scheduleSave(reason: reason, capture: { [weak self] in
            self?.makeSessionSnapshot()
        })
    }

    private func restoreSessionIfEligible(contentSize: CGSize) -> Bool {
        // 仅 `.app` bundle 启动时恢复；CLI 冷启动不恢复。
        let args = ProcessInfo.processInfo.arguments
        guard let snapshot = sessionManager.loadSnapshotForRestore(arguments: args) else { return false }
        guard snapshot.windows.isEmpty == false else { return false }

        sessionManager.beginRestoring()
        defer {
            sessionManager.endRestoring(capture: { [weak self] in
                self?.makeSessionSnapshot()
            })
        }

        let fm = FileManager.default

        func validatedWorkspaceRoot(_ path: String) -> URL? {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url
        }

        func rectIfVisible(_ frame: AttoWindowFrameSnapshot?) -> CGRect? {
            guard let frame else { return nil }
            let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            guard rect.width >= 200, rect.height >= 200 else { return nil }
            let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
            return visible ? rect : nil
        }

        for win in snapshot.windows {
            let root = validatedWorkspaceRoot(win.workspaceRootPath) ?? fm.homeDirectoryForCurrentUser
            let frameRect = rectIfVisible(win.frame)
            let ctx = createWindow(
                workspaceRootURL: root,
                contentSize: contentSize,
                initialFrame: frameRect,
                centerOnShow: (frameRect == nil)
            )

            ctx.sidebarSplitItem.isCollapsed = win.sidebarCollapsed
            ctx.restoreRecentFiles(filePaths: win.recentFilePaths)
            ctx.editorAreaController.restoreSession(
                tabs: win.tabs,
                selectedTabIndex: win.selectedTabIndex
            )
        }

        if windows.isEmpty {
            return false
        }

        if let idx = snapshot.activeWindowIndex, (0..<windows.count).contains(idx) {
            focusWindow(windows[idx])
        } else if let first = windows.first {
            focusWindow(first)
        }

        // restore 结束后写回一次“清理后的快照”（比如跳过了不存在的文件）。
        scheduleSessionSave(reason: "restore_completed")

        return true
    }

    // MARK: - Windows

    private func createWindow(
        workspaceRootURL: URL,
        contentSize: CGSize,
        initialFrame: CGRect? = nil,
        centerOnShow: Bool = true
    ) -> AttoWindowContext {
        let referenceWindow: NSWindow? = activeWindow()?.window ?? windows.last?.window

        let registry = AttoThemeManager.loadRegistry()
        let effectiveThemeName = AttoPreferences.shared.effectiveThemeName
        let resolved = AttoThemeManager.resolveSkiaTheme(themeName: effectiveThemeName, registry: registry)

        let ctx = AttoWindowContext(
            library: library,
            theme: resolved.theme,
            workspaceRootURL: workspaceRootURL,
            contentSize: contentSize
        )

        let windowID = ctx.id
        ctx.editorAreaController.onDidCloseFile = { [weak self] url in
            self?.ipcServer?.notifyFileInstanceClosed(windowID: windowID, url: url)
        }

        ctx.onWindowBecameKey = { [weak self] ctx in
            guard let self else { return }
            self.activeWindowID = ctx.id
            self.scheduleSessionSave(reason: "window_became_key")
        }
        ctx.onWindowWillClose = { [weak self] ctx in
            guard let self else { return }

            // 先保存一次“仍包含该窗口”的 session，避免关闭最后一个窗口导致 session 变空而丢失状态。
            self.sessionManager.saveNow(reason: "window_will_close", capture: { [weak self] in
                self?.makeSessionSnapshot()
            })

            self.windows.removeAll { $0.id == ctx.id }
            if self.activeWindowID == ctx.id {
                self.activeWindowID = self.windows.first?.id
            }
            self.handleWindowWillCloseForWait(ctx)

            // 再保存一次“移除该窗口后的 session”（如果没有窗口则跳过写盘）。
            self.scheduleSessionSave(reason: "window_closed")
        }

        ctx.onSessionStateChanged = { [weak self] in
            self?.scheduleSessionSave(reason: "window_state_changed")
        }
        ctx.editorAreaController.onSessionStateChanged = { [weak self] in
            self?.scheduleSessionSave(reason: "tabs_changed")
        }

        windows.append(ctx)
        if activeWindowID == nil {
            activeWindowID = ctx.id
        }

        var resolvedInitialFrame = initialFrame
        var resolvedCenterOnShow = centerOnShow

        // 默认行为（center）会导致新窗口与现有窗口完全重叠。
        // 这里做一个“级联/cascade”定位：
        // - 若已有窗口且未最大化：新窗口在现有窗口的基础上偏移一小段距离；
        // - 若现有窗口是最大化：允许新窗口与其相同位置（甚至相同大小）。
        if resolvedInitialFrame == nil, resolvedCenterOnShow, let referenceWindow, windows.count >= 2 {
            if let autoFrame = Self.autoPlacedFrameForNewWindow(referenceWindow: referenceWindow) {
                resolvedInitialFrame = autoFrame
                resolvedCenterOnShow = false
            }
        }

        if let resolvedInitialFrame {
            ctx.window.setFrame(resolvedInitialFrame, display: false)
        }

        ctx.show(center: resolvedCenterOnShow)
        return ctx
    }

    private static func autoPlacedFrameForNewWindow(referenceWindow: NSWindow) -> CGRect? {
        let refFrame = referenceWindow.frame
        guard let screen = referenceWindow.screen ?? NSScreen.main else { return nil }
        let visible = screen.visibleFrame

        if isWindowEffectivelyMaximized(referenceWindow) {
            return refFrame
        }

        let delta: CGFloat = 24

        // 新窗口默认继承参考窗口的大小（比“总是默认 size”更符合直觉）。
        var size = refFrame.size
        size.width = min(size.width, visible.width)
        size.height = min(size.height, visible.height)

        func clamp(_ origin: CGPoint) -> CGPoint {
            let maxX = visible.maxX - size.width
            let maxY = visible.maxY - size.height

            var x = origin.x
            var y = origin.y

            if maxX < visible.minX {
                x = visible.minX
            } else {
                x = min(max(x, visible.minX), maxX)
            }

            if maxY < visible.minY {
                y = visible.minY
            } else {
                y = min(max(y, visible.minY), maxY)
            }

            return CGPoint(x: x, y: y)
        }

        func approxEqual(_ a: CGFloat, _ b: CGFloat) -> Bool {
            abs(a - b) <= 0.5
        }

        var origin = clamp(CGPoint(x: refFrame.origin.x + delta, y: refFrame.origin.y - delta))
        var out = CGRect(origin: origin, size: size)

        // 尽量避免“偏移后又被 clamp 回原地”导致仍然重叠。
        if approxEqual(out.origin.x, refFrame.origin.x), approxEqual(out.origin.y, refFrame.origin.y) {
            origin = clamp(CGPoint(x: refFrame.origin.x - delta, y: refFrame.origin.y + delta))
            out = CGRect(origin: origin, size: size)
        }
        if approxEqual(out.origin.x, refFrame.origin.x), approxEqual(out.origin.y, refFrame.origin.y) {
            origin = clamp(CGPoint(x: refFrame.origin.x + 1, y: refFrame.origin.y - 1))
            out = CGRect(origin: origin, size: size)
        }

        return out
    }

    private static func isWindowEffectivelyMaximized(_ window: NSWindow) -> Bool {
        if window.styleMask.contains(.fullScreen) {
            return true
        }
        if window.isZoomed {
            return true
        }
        guard let screen = window.screen else { return false }

        let f = window.frame
        let v = screen.visibleFrame
        let eps: CGFloat = 2.0

        return abs(f.origin.x - v.origin.x) <= eps
            && abs(f.origin.y - v.origin.y) <= eps
            && abs(f.size.width - v.size.width) <= eps
            && abs(f.size.height - v.size.height) <= eps
    }

    private func activeWindow() -> AttoWindowContext? {
        if let id = activeWindowID, let ctx = windows.first(where: { $0.id == id }) {
            return ctx
        }
        return windows.first
    }

    private func findWindow(containingFile url: URL) -> AttoWindowContext? {
        windows.first { $0.editorAreaController.containsFile(url: url) }
    }

    private func focusWindow(_ ctx: AttoWindowContext) {
        activeWindowID = ctx.id
        ctx.window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - IPC open handling

    func handleOpenRequest(_ req: AttoIpcOpenRequest) -> AttoIpcOpenResult {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        // 仅激活：用于 `atto`（无参数）或将现有实例置前。
        if req.directories.isEmpty, req.files.isEmpty {
            if windows.isEmpty {
                _ = createWindow(workspaceRootURL: AttoAppDelegate.defaultRepoRootURL(), contentSize: contentSize)
            }
            if let win = activeWindow() {
                focusWindow(win)
            }
            return .empty
        }

        var errors: [String] = []
        var pendingTokens: [AttoIpcWaitToken] = []

        // 目录：总是新窗口（支持多个目录 => 多个窗口）。并记录这次请求创建的“first window”。
        var dirWindows: [AttoWindowContext] = []
        for dirPath in req.directories {
            let url = URL(fileURLWithPath: dirPath).standardizedFileURL
            let ctx = createWindow(workspaceRootURL: url, contentSize: contentSize)
            dirWindows.append(ctx)
        }
        let firstDirWindow: AttoWindowContext? = dirWindows.first

        func locFrom(_ f: AttoIpcFileRequest) -> AttoCommandLine.FileLocation? {
            guard let line1 = f.line1 else { return nil }
            return .init(line1: max(1, line1), column1: f.column1)
        }

        func openFileInWindow(_ url: URL, loc: AttoCommandLine.FileLocation?, window: AttoWindowContext) {
            focusWindow(window)
            window.rememberRecentFile(url)
            let ok = window.editorAreaController.openFile(url: url, mode: .pinned, location: loc)
            if ok {
                pendingTokens.append(.init(windowID: window.id, fileURL: url))
                window.fileExplorerController.revealFile(url)
            } else {
                errors.append("failed to open file: \(url.path)")
            }
        }

        func openFileInNewWindow(_ url: URL, loc: AttoCommandLine.FileLocation?) {
            let root = url.deletingLastPathComponent()
            let ctx = createWindow(workspaceRootURL: root, contentSize: contentSize)
            openFileInWindow(url, loc: loc, window: ctx)
        }

        // 仅目录：打开完窗口后，把第一个目录窗口置前。
        if req.files.isEmpty, let firstDirWindow {
            focusWindow(firstDirWindow)
            return .init(pendingTokens: [], errors: [])
        }

        // `-n/--new-window`：文件总是新窗口打开（每个 file arg 一次）。
        if req.newWindow {
            for f in req.files {
                let url = URL(fileURLWithPath: f.path).standardizedFileURL
                openFileInNewWindow(url, loc: locFrom(f))
            }
            return .init(pendingTokens: pendingTokens, errors: errors)
        }

        // Special-case：同时指定了目录和文件。
        //
        // 规则：
        // - 目录：每个目录一个新窗口（已在上面创建）
        // - 文件：如果“first window”里已经打开该文件，则复用 first window；否则每个文件新窗口
        if req.directories.isEmpty == false, req.files.isEmpty == false {
            for f in req.files {
                let url = URL(fileURLWithPath: f.path).standardizedFileURL
                let loc = locFrom(f)
                if let firstDirWindow, firstDirWindow.editorAreaController.containsFile(url: url) {
                    openFileInWindow(url, loc: loc, window: firstDirWindow)
                } else {
                    openFileInNewWindow(url, loc: loc)
                }
            }
            return .init(pendingTokens: pendingTokens, errors: errors)
        }

        // 常规：只有文件参数（或只有目录参数已被上面提前 return）。
        // 文件：若已在某个窗口打开，则复用该窗口；否则新开窗口。
        for f in req.files {
            let url = URL(fileURLWithPath: f.path).standardizedFileURL
            let loc = locFrom(f)
            if let existing = findWindow(containingFile: url) {
                openFileInWindow(url, loc: loc, window: existing)
            } else {
                openFileInNewWindow(url, loc: loc)
            }
        }

        return .init(pendingTokens: pendingTokens, errors: errors)
    }

    // MARK: - Wait notifications (IPC)

    private func handleWindowWillCloseForWait(_ ctx: AttoWindowContext) {
        let windowID = ctx.id
        for url in ctx.editorAreaController.openFileURLs() {
            ipcServer?.notifyFileInstanceClosed(windowID: windowID, url: url)
        }
    }
}
