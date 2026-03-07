import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var splitViewController: NSSplitViewController?
    private var sidebarSplitItem: NSSplitViewItem?

    private var fileExplorerController: AttoFileExplorerViewController?
    private var editorAreaController: AttoEditorAreaViewController?
    private var commandPaletteController: AttoCommandPaletteController?
    private var quickOpenController: AttoCommandPaletteController?

    private var workspaceRootURL: URL = AttoAppDelegate.defaultRepoRootURL()
    private var fileIndex: AttoWorkspaceFileIndex?
    private var recentFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let library = EditorCoreUIFFILibrary()
        let theme = EditorCoreSkiaTheme.demoRustLspDark()

        let fileExplorer = AttoFileExplorerViewController(rootURL: workspaceRootURL)
        let editorArea = AttoEditorAreaViewController(
            library: library,
            theme: theme,
            workspaceRootURL: workspaceRootURL
        )

        fileExplorer.onOpenFile = { [weak self, weak editorArea] url in
            self?.rememberRecentFile(url)
            editorArea?.openFile(url: url, mode: .pinned)
        }
        fileExplorer.onPreviewFile = { [weak self, weak editorArea] url in
            self?.rememberRecentFile(url)
            editorArea?.openFile(url: url, mode: .preview)
        }

        let splitVC = NSSplitViewController()
        splitVC.splitView.isVertical = true
        splitVC.splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: fileExplorer)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: editorArea)
        contentItem.minimumThickness = 320

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(contentItem)

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: AttoWindowSizing.preferredContentSize)
        let contentSize = AttoWindowSizing.defaultContentSize(forVisibleFrame: visibleFrame)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "AttoEditor"
        // AttoEditor uses an in-app tab strip; disallow macOS window tabbing UI.
        win.tabbingMode = .disallowed
        win.contentViewController = splitVC
        win.contentMinSize = AttoWindowSizing.minimumContentSize
        win.setContentSize(contentSize)
        win.center()
        win.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)

        window = win
        splitViewController = splitVC
        sidebarSplitItem = sidebarItem
        fileExplorerController = fileExplorer
        editorAreaController = editorArea

        fileIndex = AttoWorkspaceFileIndex(rootURL: workspaceRootURL)

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

        // Demo: open a real Rust file from this repo on first launch (so LSP/theme is visible).
        let initial = workspaceRootURL.appendingPathComponent("crates/tui-editor/src/main.rs")
        if FileManager.default.fileExists(atPath: initial.path) {
            rememberRecentFile(initial)
            editorArea.openFile(url: initial)
            fileExplorer.revealFile(initial)
        }

        // Remove system window-tabbing menu items (e.g. "Show Tab Bar") from standard menus.
        removeSystemWindowTabbingMenuItems()
    }

    // MARK: - Menu actions

    @objc func openFolderMenuClicked(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to open."
        panel.directoryURL = workspaceRootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspaceRoot(url)
    }

    @objc func openFileMenuClicked(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a file to open."
        panel.directoryURL = workspaceRootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberRecentFile(url)
        editorAreaController?.openFile(url: url)
        fileExplorerController?.revealFile(url)
    }

    @objc func closeTabMenuClicked(_ sender: Any?) {
        editorAreaController?.closeActiveTab()
    }

    @objc func saveMenuClicked(_ sender: Any?) {
        editorAreaController?.saveActiveTab()
    }

    @objc func toggleSidebarMenuClicked(_ sender: Any?) {
        toggleSidebar()
    }

    @objc func toggleMinimapMenuClicked(_ sender: Any?) {
        editorAreaController?.toggleMinimapForActiveTab()
    }

    @objc func commandPaletteMenuClicked(_ sender: Any?) {
        showCommandPalette()
    }

    @objc func goToFileMenuClicked(_ sender: Any?) {
        showQuickOpen()
    }

    // MARK: - Command palette integration

    private func showCommandPalette() {
        guard let win = window else { return }
        commandPaletteController?.show(relativeTo: win)
    }

    private func showQuickOpen() {
        guard let win = window else { return }
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
            .init(title: "View: Toggle Sidebar") { [weak self] in
                self?.toggleSidebar()
            },
            .init(title: "View: Toggle Minimap") { [weak self] in
                self?.editorAreaController?.toggleMinimapForActiveTab()
            },
            .init(title: "AttoEditor: Command Palette") { [weak self] in
                self?.showCommandPalette()
            },
            .init(title: "Go: Go to File…") { [weak self] in
                self?.showQuickOpen()
            },
        ]
    }

    private func quickOpenCommands() -> [AttoCommandPaletteCommand] {
        guard let editorAreaController else { return [] }
        guard let fileExplorerController else { return [] }

        let all = fileIndex?.entries() ?? []

        var out: [AttoCommandPaletteCommand] = []
        var seen: Set<URL> = Set()

        for url in recentFiles {
            let u = url.standardizedFileURL
            if seen.contains(u) { continue }
            seen.insert(u)
            let title = relativePathForDisplay(u)
            out.append(.init(title: title) { [weak self] in
                self?.rememberRecentFile(u)
                editorAreaController.openFile(url: u, mode: .pinned)
                fileExplorerController.revealFile(u)
            })
        }

        for entry in all {
            let u = entry.url.standardizedFileURL
            if seen.contains(u) { continue }
            seen.insert(u)
            out.append(.init(title: entry.relativePath) { [weak self] in
                self?.rememberRecentFile(u)
                editorAreaController.openFile(url: u, mode: .pinned)
                fileExplorerController.revealFile(u)
            })
        }

        return out
    }

    private func relativePathForDisplay(_ url: URL) -> String {
        let root = workspaceRootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == root {
            return url.lastPathComponent
        }
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return url.path
    }

    private func rememberRecentFile(_ url: URL) {
        let u = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL == u }
        recentFiles.insert(u, at: 0)
        if recentFiles.count > 20 {
            recentFiles.removeLast(recentFiles.count - 20)
        }
    }

    // MARK: - Workspace root

    private func openWorkspaceRoot(_ url: URL) {
        workspaceRootURL = url
        fileExplorerController?.setRootURL(url)
        editorAreaController?.setWorkspaceRootURL(url)
        fileIndex?.setRootURL(url)
        recentFiles = []
        window?.title = "AttoEditor — \(url.lastPathComponent)"
    }

    private func toggleSidebar() {
        guard let sidebarSplitItem else { return }
        sidebarSplitItem.isCollapsed.toggle()
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
}
