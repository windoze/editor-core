import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoWindowContext: NSObject, NSWindowDelegate {
    let id: UUID = UUID()

    private(set) var workspaceRootURL: URL
    private(set) var recentFiles: [URL] = []
    private(set) var fileIndex: AttoWorkspaceFileIndex

    let window: NSWindow
    let splitViewController: NSSplitViewController
    let sidebarSplitItem: NSSplitViewItem
    let sidebarController: AttoSidebarViewController
    let fileExplorerController: AttoFileExplorerViewController
    let openedFilesController: AttoOpenedFilesViewController
    let findInFilesController: AttoFindInFilesViewController
    let editorAreaController: AttoEditorAreaViewController

    var onWindowBecameKey: ((AttoWindowContext) -> Void)?
    var onWindowWillClose: ((AttoWindowContext) -> Void)?
    var onSessionStateChanged: (() -> Void)?

    init(
        library: EditorCoreUIFFILibrary,
        theme: EditorCoreSkiaTheme,
        workspaceRootURL: URL,
        contentSize: CGSize
    ) {
        self.workspaceRootURL = workspaceRootURL

        let fileExplorer = AttoFileExplorerViewController(rootURL: workspaceRootURL)
        let openedFiles = AttoOpenedFilesViewController(rootURL: workspaceRootURL)
        let findInFiles = AttoFindInFilesViewController(rootURL: workspaceRootURL)
        let sidebar = AttoSidebarViewController(
            fileExplorerController: fileExplorer,
            openedFilesController: openedFiles,
            findInFilesController: findInFiles
        )
        let editorArea = AttoEditorAreaViewController(
            library: library,
            theme: theme,
            workspaceRootURL: workspaceRootURL
        )

        let splitVC = NSSplitViewController()
        splitVC.splitView.isVertical = true
        splitVC.splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: editorArea)
        contentItem.minimumThickness = 320

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(contentItem)

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

        self.window = win
        self.splitViewController = splitVC
        self.sidebarSplitItem = sidebarItem
        self.sidebarController = sidebar
        self.fileExplorerController = fileExplorer
        self.openedFilesController = openedFiles
        self.findInFilesController = findInFiles
        self.editorAreaController = editorArea

        self.fileIndex = AttoWorkspaceFileIndex(rootURL: workspaceRootURL)

        super.init()
        win.delegate = self

        fileExplorerController.onOpenFile = { [weak self] url in
            guard let self else { return }
            self.rememberRecentFile(url)
            self.editorAreaController.openFile(url: url, mode: .pinned)
            self.fileExplorerController.revealFile(url)
        }
        fileExplorerController.onPreviewFile = { [weak self] url in
            guard let self else { return }
            self.rememberRecentFile(url)
            self.editorAreaController.openFile(url: url, mode: .preview)
        }

        openedFilesController.onSelectFile = { [weak self] url in
            guard let self else { return }
            self.editorAreaController.selectFile(url: url)
            self.fileExplorerController.revealFile(url)
        }

        editorAreaController.onOpenFilesChanged = { [weak self] items, selectedID in
            self?.openedFilesController.updateOpenFiles(items, selectedID: selectedID)
        }

        editorAreaController.onDidSaveFile = { [weak self] url, createdOnDisk in
            guard let self else { return }
            guard createdOnDisk else { return }

            // A brand-new file was materialized by saving an “untitled” buffer.
            // Refresh sidebar + quick-open caches so it becomes discoverable.
            self.fileExplorerController.setRootURL(self.workspaceRootURL)
            self.fileIndex.rebuild()
            self.fileExplorerController.revealFile(url)
            self.rememberRecentFile(url)
        }

        findInFilesController.openedFilesProvider = { [weak self] in
            self?.editorAreaController.openFileURLs() ?? []
        }
        findInFilesController.openedFilesSearchProvider = { [weak self] query in
            self?.editorAreaController.findInOpenTabs(query: query) ?? []
        }
        findInFilesController.workspaceFilesProvider = { [weak self] in
            self?.fileIndex.entries().map(\.url) ?? []
        }
        findInFilesController.onOpenResult = { [weak self] url, loc in
            guard let self else { return }
            self.rememberRecentFile(url)
            _ = self.editorAreaController.openFile(url: url, mode: .pinned, location: loc)
            self.fileExplorerController.revealFile(url)
        }

        setWorkspaceRootURL(workspaceRootURL)
    }

    func show(center: Bool = true) {
        if center {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func setWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
        fileExplorerController.setRootURL(url)
        openedFilesController.setRootURL(url)
        findInFilesController.setRootURL(url)
        editorAreaController.setWorkspaceRootURL(url)
        fileIndex.setRootURL(url)
        recentFiles = []
        window.title = "AttoEditor — \(url.lastPathComponent)"
        onSessionStateChanged?()
    }

    func rememberRecentFile(_ url: URL) {
        let u = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL == u }
        recentFiles.insert(u, at: 0)
        if recentFiles.count > 20 {
            recentFiles.removeLast(recentFiles.count - 20)
        }
        onSessionStateChanged?()
    }

    func relativePathForDisplay(_ url: URL) -> String {
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

    func toggleSidebar() {
        sidebarSplitItem.isCollapsed.toggle()
        onSessionStateChanged?()
    }

    func showFindInFilesSidebar() {
        if sidebarSplitItem.isCollapsed {
            sidebarSplitItem.isCollapsed = false
        }
        sidebarController.selectTab(.findInFiles)
        onSessionStateChanged?()
    }

    // MARK: - Session snapshot

    func makeSessionSnapshot() -> AttoWindowSnapshot {
        let frame = window.frame
        let frameSnap = AttoWindowFrameSnapshot(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.size.width),
            height: Double(frame.size.height)
        )

        let editorSnap = editorAreaController.makeSessionSnapshot()

        return AttoWindowSnapshot(
            workspaceRootPath: workspaceRootURL.standardizedFileURL.path,
            frame: frameSnap,
            sidebarCollapsed: sidebarSplitItem.isCollapsed,
            selectedTabIndex: editorSnap.selectedTabIndex,
            tabs: editorSnap.tabs,
            recentFilePaths: recentFiles.map { $0.standardizedFileURL.path }
        )
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorAreaController.confirmClosingDirtyTabsIfNeeded()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onWindowBecameKey?(self)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowWillClose?(self)
    }

    func windowDidMove(_ notification: Notification) {
        onSessionStateChanged?()
    }

    func windowDidResize(_ notification: Notification) {
        onSessionStateChanged?()
    }

    // MARK: - Session restore helpers

    func restoreRecentFiles(filePaths: [String], fileManager: FileManager = .default) {
        var out: [URL] = []
        var seen: Set<String> = Set()

        for p in filePaths {
            let url = URL(fileURLWithPath: p).standardizedFileURL
            let key = url.path
            if seen.contains(key) { continue }
            seen.insert(key)
            if fileManager.fileExists(atPath: url.path) == false { continue }
            out.append(url)
            if out.count >= 20 { break }
        }

        recentFiles = out
        onSessionStateChanged?()
    }
}
