import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoWindowContext: NSObject, NSWindowDelegate {
    let id: UUID = UUID()

    private(set) var workspaceRootURL: URL
    private let workspaceDataSource: AttoWorkspaceDataSource
    var fileIndex: AttoWorkspaceFileIndex { workspaceDataSource.fileIndex }

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
        configurationSnapshot: AttoConfigurationSnapshot,
        configurationSnapshotProvider: ((URL, AttoConfigurationDocumentContext?) -> AttoConfigurationSnapshot)? = nil,
        themeResolver: ((String) -> EditorCoreSkiaTheme)? = nil,
        contentSize: CGSize
    ) {
        self.workspaceRootURL = workspaceRootURL

        let fileExplorer = AttoFileExplorerViewController(rootURL: workspaceRootURL)
        let openedFiles = AttoOpenedFilesViewController(rootURL: workspaceRootURL)
        let findInFiles = AttoFindInFilesViewController(rootURL: workspaceRootURL)
        findInFiles.setDefaultScope(configurationValue: configurationSnapshot.workspace.findInFilesDefaultScope)
        findInFiles.setWorkspaceSearchGlobs(
            include: configurationSnapshot.workspace.workspaceSearchIncludeGlobs,
            exclude: configurationSnapshot.workspace.workspaceSearchExcludeGlobs
        )
        findInFiles.setSearchOptions(Self.findInFilesSearchOptions(from: configurationSnapshot))
        findInFiles.setWorkspaceReplacementEnabled(
            library.featureFlags.contains(.multiDocumentWorkspaceFileReplacement)
        )
        let sidebar = AttoSidebarViewController(
            fileExplorerController: fileExplorer,
            openedFilesController: openedFiles,
            findInFilesController: findInFiles
        )
        let editorArea = AttoEditorAreaViewController(
            library: library,
            theme: theme,
            workspaceRootURL: workspaceRootURL,
            configurationSnapshot: configurationSnapshot,
            configurationSnapshotProvider: configurationSnapshotProvider,
            themeResolver: themeResolver
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

        self.workspaceDataSource = AttoWorkspaceDataSource(
            rootURL: workspaceRootURL,
            coreDocumentsProvider: { [weak editorArea] in editorArea?.coreDocuments }
        )

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
            self.refreshCoreProjectFileIndex()
            self.fileExplorerController.revealFile(url)
            self.rememberRecentFile(url)
        }

        findInFilesController.openedFilesProvider = { [weak self] in
            self?.editorAreaController.openFileURLs() ?? []
        }
        findInFilesController.openedFilesSearchProvider = { [weak self] query, options in
            self?.editorAreaController.findInOpenTabs(query: query, options: options) ?? []
        }
        findInFilesController.workspaceFilesSearchProvider = { [weak self] query, includeGlobs, excludeGlobs, options in
            guard let self else { return .unavailable }
            guard self.supportsCoreWorkspaceFileSearch else { return .unavailable }
            guard let results = self.editorAreaController.findInWorkspaceFiles(
                query: query,
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs,
                options: options
            ) else {
                return .failed("core workspace search unavailable")
            }
            return .results(results)
        }
        findInFilesController.workspaceFilesReplaceProvider = { [weak self] query, replacement, includeGlobs, excludeGlobs, options in
            self?.editorAreaController.replaceInWorkspaceFiles(
                query: query,
                replacement: replacement,
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs,
                options: options
            ) ?? false
        }
        findInFilesController.workspaceFilesProvider = { [weak self] in
            self?.workspaceFileEntries().map(\.url) ?? []
        }
        findInFilesController.onOpenResult = { [weak self] url, loc in
            guard let self else { return }
            self.rememberRecentFile(url)
            _ = self.editorAreaController.openFile(url: url, mode: .pinned, location: loc)
            self.fileExplorerController.revealFile(url)
        }

        setWorkspaceRootURL(workspaceRootURL)
    }

    func updateConfigurationSnapshot(_ snapshot: AttoConfigurationSnapshot) {
        editorAreaController.updateConfigurationSnapshot(snapshot)
        findInFilesController.setDefaultScope(configurationValue: snapshot.workspace.findInFilesDefaultScope)
        findInFilesController.setWorkspaceSearchGlobs(
            include: snapshot.workspace.workspaceSearchIncludeGlobs,
            exclude: snapshot.workspace.workspaceSearchExcludeGlobs
        )
        findInFilesController.setSearchOptions(Self.findInFilesSearchOptions(from: snapshot))
    }

    private static func findInFilesSearchOptions(
        from snapshot: AttoConfigurationSnapshot
    ) -> AttoFindInFilesViewController.SearchOptions {
        AttoFindInFilesViewController.SearchOptions(
            caseSensitive: snapshot.editor.findCaseSensitive,
            wholeWord: snapshot.editor.findWholeWord,
            regex: snapshot.editor.findRegex
        )
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
        workspaceDataSource.rememberRecentProjectRoot(url)
        workspaceDataSource.setRootURL(url)
        window.title = "AttoEditor — \(url.lastPathComponent)"
        onSessionStateChanged?()
    }

    func rememberRecentFile(_ url: URL) {
        workspaceDataSource.rememberRecentFile(url)
        onSessionStateChanged?()
    }

    func recentFileURLs() -> [URL] {
        workspaceDataSource.recentFileURLs()
    }

    func recentProjectURLs() -> [URL] {
        workspaceDataSource.recentProjectURLs()
    }

    func restoreRecentProjectURIs(_ uris: [String], fileManager: FileManager = .default) {
        workspaceDataSource.restoreRecentProjectURIs(uris, fileManager: fileManager)
    }

    func workspaceFileEntries() -> [AttoWorkspaceFileIndex.Entry] {
        workspaceDataSource.workspaceFileEntries()
    }

    func workspaceFileEntries(matching query: String, maxResults: UInt32 = 200) -> [AttoWorkspaceFileIndex.Entry] {
        workspaceDataSource.workspaceFileEntries(matching: query, maxResults: maxResults)
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
        let workspaceRoot = workspaceDataSource.sessionWorkspaceRootURL(fallback: workspaceRootURL)

        return AttoWindowSnapshot(
            workspaceRootPath: workspaceRoot.path,
            workspaceRootURI: workspaceRoot.absoluteString,
            frame: frameSnap,
            sidebarCollapsed: sidebarSplitItem.isCollapsed,
            selectedTabIndex: editorSnap.selectedTabIndex,
            tabs: editorSnap.tabs,
            recentFilePaths: recentFileURLs().map { $0.standardizedFileURL.path }
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
        editorAreaController.closeWorkspaceEditHistoryPanel()
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
        workspaceDataSource.restoreRecentFiles(filePaths: filePaths, fileManager: fileManager)
        onSessionStateChanged?()
    }

    private func refreshCoreProjectFileIndex() {
        _ = workspaceDataSource.workspaceFileEntries()
    }

    private var supportsCoreWorkspaceFileSearch: Bool {
        editorAreaController.coreDocuments?.library.featureFlags.contains(.multiDocumentWorkspaceFileSearch) ?? false
    }
}
