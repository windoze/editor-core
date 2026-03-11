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
    private let sessionManager = AttoSessionManager()

    private var windows: [AttoWindowContext] = []
    private var activeWindowID: UUID?

    var ipcServer: AttoIpcServer?
    var createDefaultWindowOnLaunch: Bool = true

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            .init(title: "Edit: Find") { [weak self] in
                self?.activeWindow()?.editorAreaController.showFindBar()
            },
            .init(title: "Edit: Replace") { [weak self] in
                self?.activeWindow()?.editorAreaController.showReplaceBar()
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
            .init(title: "Search: Find in Files") { [weak self] in
                self?.activeWindow()?.showFindInFilesSidebar()
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
        let ctx = AttoWindowContext(
            library: library,
            theme: theme,
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
