import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoAppDelegate: NSObject, NSApplicationDelegate {
    private var commandPaletteController: AttoCommandPaletteController?
    private var quickOpenController: AttoCommandPaletteController?

    private let library = EditorCoreUIFFILibrary()
    private let theme = EditorCoreSkiaTheme.demoRustLspDark()

    private var windows: [AttoWindowContext] = []
    private var activeWindowID: UUID?

    var ipcServer: AttoIpcServer?
    var createDefaultWindowOnLaunch: Bool = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        if createDefaultWindowOnLaunch {
            _ = createWindow(workspaceRootURL: AttoAppDelegate.defaultRepoRootURL(), contentSize: contentSize)
            NSApplication.shared.activate(ignoringOtherApps: true)
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

        // Demo: 仅在“手动启动 GUI”时打开一个真实 Rust 文件，确保 LSP/theme 可见。
        if createDefaultWindowOnLaunch, let first = windows.first {
            let initial = first.workspaceRootURL.appendingPathComponent("crates/tui-editor/src/main.rs")
            if FileManager.default.fileExists(atPath: initial.path) {
                first.rememberRecentFile(initial)
                first.editorAreaController.openFile(url: initial)
                first.fileExplorerController.revealFile(initial)
            }
        }

        // Remove system window-tabbing menu items (e.g. "Show Tab Bar") from standard menus.
        removeSystemWindowTabbingMenuItems()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer?.stop()
    }

    // MARK: - Menu actions

    @objc func openFolderMenuClicked(_ sender: Any?) {
        guard let ctx = activeWindow() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to open."
        panel.directoryURL = ctx.workspaceRootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        ctx.setWorkspaceRootURL(url)
    }

    @objc func openFileMenuClicked(_ sender: Any?) {
        guard let ctx = activeWindow() else { return }
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
        [
            .init(title: "File: Open Folder…") { [weak self] in
                self?.openFolderMenuClicked(nil)
            },
            .init(title: "File: Open File…") { [weak self] in
                self?.openFileMenuClicked(nil)
            },
            .init(title: "File: Save") { [weak self] in
                self?.saveMenuClicked(nil)
            },
            .init(title: "Edit: Format Document") { [weak self] in
                self?.activeWindow()?.editorAreaController.formatDocumentWithLspInActiveTab()
            },
            .init(title: "View: Toggle Sidebar") { [weak self] in
                self?.activeWindow()?.toggleSidebar()
            },
            .init(title: "View: Toggle Minimap") { [weak self] in
                self?.activeWindow()?.editorAreaController.toggleMinimapForActiveTab()
            },
            .init(title: "AttoEditor: Command Palette") { [weak self] in
                self?.showCommandPalette()
            },
            .init(title: "Go: Go to File…") { [weak self] in
                self?.showQuickOpen()
            },
            .init(title: "Go: Back") { [weak self] in
                self?.activeWindow()?.editorAreaController.jumpBackInActiveTab()
            },
            .init(title: "Go: Forward") { [weak self] in
                self?.activeWindow()?.editorAreaController.jumpForwardInActiveTab()
            },
            .init(title: "Go: Go to Matching Bracket") { [weak self] in
                self?.activeWindow()?.editorAreaController.moveToMatchingBracketInActiveTab()
            },
        ]
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
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // AttoEditor
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // swift
            .deletingLastPathComponent() // repo root
    }

    // MARK: - Windows

    private func createWindow(workspaceRootURL: URL, contentSize: CGSize) -> AttoWindowContext {
        let ctx = AttoWindowContext(
            library: library,
            theme: theme,
            workspaceRootURL: workspaceRootURL,
            contentSize: contentSize
        )

        ctx.editorAreaController.onDidCloseFile = { [weak self] url in
            self?.handleFileClosedByUser(url)
        }

        ctx.onWindowBecameKey = { [weak self] ctx in
            self?.activeWindowID = ctx.id
        }
        ctx.onWindowWillClose = { [weak self] ctx in
            self?.windows.removeAll { $0.id == ctx.id }
            if self?.activeWindowID == ctx.id {
                self?.activeWindowID = self?.windows.first?.id
            }
            self?.handleWindowWillCloseForWait(ctx)
        }

        windows.append(ctx)
        if activeWindowID == nil {
            activeWindowID = ctx.id
        }
        ctx.show()
        return ctx
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

        // 目录：总是新窗口（支持多个目录 => 多个窗口）。
        for dirPath in req.directories {
            let url = URL(fileURLWithPath: dirPath).standardizedFileURL
            _ = createWindow(workspaceRootURL: url, contentSize: contentSize)
        }

        var errors: [String] = []
        var pendingFiles: [URL] = []

        // 文件：默认“已打开则复用窗口，否则新窗口”。`-n/--new-window` 强制新窗口打开。
        if req.newWindow, req.files.isEmpty == false {
            let root = URL(fileURLWithPath: req.files[0].path).standardizedFileURL.deletingLastPathComponent()
            let ctx = createWindow(workspaceRootURL: root, contentSize: contentSize)
            focusWindow(ctx)

            for f in req.files {
                let url = URL(fileURLWithPath: f.path).standardizedFileURL
                ctx.rememberRecentFile(url)
                let loc: AttoCommandLine.FileLocation? = {
                    guard let line1 = f.line1 else { return nil }
                    return .init(line1: max(1, line1), column1: f.column1)
                }()
                let ok = ctx.editorAreaController.openFile(url: url, mode: .pinned, location: loc)
                if ok {
                    pendingFiles.append(url)
                    ctx.fileExplorerController.revealFile(url)
                } else {
                    errors.append("failed to open file: \(url.path)")
                }
            }

            return .init(pendingFiles: pendingFiles, errors: errors)
        }

        for f in req.files {
            let url = URL(fileURLWithPath: f.path).standardizedFileURL
            let loc: AttoCommandLine.FileLocation? = {
                guard let line1 = f.line1 else { return nil }
                return .init(line1: max(1, line1), column1: f.column1)
            }()

            if let existing = findWindow(containingFile: url) {
                focusWindow(existing)
                existing.rememberRecentFile(url)
                let ok = existing.editorAreaController.openFile(url: url, mode: .pinned, location: loc)
                if ok {
                    pendingFiles.append(url)
                    existing.fileExplorerController.revealFile(url)
                } else {
                    errors.append("failed to open file: \(url.path)")
                }
                continue
            }

            // 不在任何窗口里：按规范新开一个窗口。
            let root = url.deletingLastPathComponent()
            let ctx = createWindow(workspaceRootURL: root, contentSize: contentSize)
            focusWindow(ctx)
            ctx.rememberRecentFile(url)
            let ok = ctx.editorAreaController.openFile(url: url, mode: .pinned, location: loc)
            if ok {
                pendingFiles.append(url)
                ctx.fileExplorerController.revealFile(url)
            } else {
                errors.append("failed to open file: \(url.path)")
            }
        }

        return .init(pendingFiles: pendingFiles, errors: errors)
    }

    // MARK: - Wait notifications (IPC)

    private func isFileOpenAnywhere(_ url: URL, excluding excludedID: UUID? = nil) -> Bool {
        let u = url.standardizedFileURL
        for w in windows {
            if let excludedID, w.id == excludedID { continue }
            if w.editorAreaController.containsFile(url: u) {
                return true
            }
        }
        return false
    }

    private func handleFileClosedByUser(_ url: URL) {
        let u = url.standardizedFileURL
        if isFileOpenAnywhere(u) {
            return
        }
        ipcServer?.notifyFileFullyClosed(u)
    }

    private func handleWindowWillCloseForWait(_ ctx: AttoWindowContext) {
        for url in ctx.editorAreaController.openFileURLs() {
            let u = url.standardizedFileURL
            if isFileOpenAnywhere(u, excluding: ctx.id) == false {
                ipcServer?.notifyFileFullyClosed(u)
            }
        }
    }
}
