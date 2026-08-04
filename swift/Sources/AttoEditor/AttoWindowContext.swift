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
            self?.editorAreaController.findInWorkspaceFiles(
                query: query,
                includeGlobs: includeGlobs,
                excludeGlobs: excludeGlobs,
                options: options
            )
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
        rememberRecentProjectRoot(url)
        fileIndex.setRootURL(url)
        recentFiles = []
        if supportsCoreRecentFiles {
            try? editorAreaController.coreDocuments?.clearRecentFiles()
        }
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
        if supportsCoreRecentFiles {
            try? editorAreaController.coreDocuments?.rememberRecentFileURI(u.absoluteString)
        }
        onSessionStateChanged?()
    }

    func recentFileURLs() -> [URL] {
        if let coreRecentFiles = coreRecentFileURLs() {
            return coreRecentFiles
        }
        return recentFiles
    }

    func recentProjectURLs() -> [URL] {
        coreRecentProjectURLs() ?? []
    }

    func restoreRecentProjectURIs(_ uris: [String], fileManager: FileManager = .default) {
        guard supportsCoreRecentProjects else { return }

        var out: [String] = []
        var seen: Set<String> = []
        for uri in uris {
            let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  url.isFileURL
            else {
                continue
            }

            let standardized = url.standardizedFileURL
            guard Self.directoryExists(at: standardized, fileManager: fileManager) else {
                continue
            }

            let normalized = standardized.absoluteString
            guard seen.contains(normalized) == false else { continue }
            seen.insert(normalized)
            out.append(normalized)
            if out.count >= 20 { break }
        }

        try? editorAreaController.coreDocuments?.restoreRecentProjectURIs(out)
    }

    func workspaceFileEntries() -> [AttoWorkspaceFileIndex.Entry] {
        if let coreIndexEntries = refreshedCoreProjectFileIndexEntries() {
            return coreIndexEntries
        }
        if let coreEntries = coreWorkspaceFileEntries() {
            return coreEntries
        }
        return fileIndex.entries()
    }

    func workspaceFileEntries(matching query: String, maxResults: UInt32 = 200) -> [AttoWorkspaceFileIndex.Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let coreMatches = coreProjectFileIndexEntries(matching: q, maxResults: maxResults) {
            return coreMatches
        }
        let entries = workspaceFileEntries()
        guard q.isEmpty == false else {
            return Array(entries.prefix(Int(maxResults)))
        }
        return entries
            .filter { $0.relativePath.localizedCaseInsensitiveContains(q) }
            .prefix(Int(maxResults))
            .map { $0 }
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
        let workspaceRoot = sessionWorkspaceRootURL()

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
        if supportsCoreRecentFiles {
            try? editorAreaController.coreDocuments?.restoreRecentFileURIs(
                out.map { $0.standardizedFileURL.absoluteString }
            )
        }
        onSessionStateChanged?()
    }

    private var supportsCoreRecentFiles: Bool {
        editorAreaController.coreDocuments?.library.featureFlags.contains(.multiDocumentRecentFiles) ?? false
    }

    private var supportsCoreRecentProjects: Bool {
        editorAreaController.coreDocuments?.library.featureFlags.contains(.multiDocumentRecentProjects) ?? false
    }

    private var supportsCoreProjectFileIndex: Bool {
        editorAreaController.coreDocuments?.library.featureFlags.contains(.multiDocumentProjectFileIndex) ?? false
    }

    private var supportsCoreProjectFileIndexQuery: Bool {
        editorAreaController.coreDocuments?.library.featureFlags.contains(.multiDocumentProjectFileIndexQuery) ?? false
    }

    private var supportsCoreWorkspaceFileList: Bool {
        editorAreaController.coreDocuments?.library.featureFlags.contains(.multiDocumentWorkspaceFileList) ?? false
    }

    private func coreRecentFileURLs() -> [URL]? {
        guard supportsCoreRecentFiles,
              let entries = try? editorAreaController.coreDocuments?.recentFiles()
        else {
            return nil
        }

        return entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
    }

    private func rememberRecentProjectRoot(_ url: URL) {
        guard supportsCoreRecentProjects else { return }
        try? editorAreaController.coreDocuments?.rememberRecentProjectURI(
            url.standardizedFileURL.absoluteString
        )
    }

    private func coreRecentProjectURLs() -> [URL]? {
        guard supportsCoreRecentProjects,
              let entries = try? editorAreaController.coreDocuments?.recentProjects()
        else {
            return nil
        }

        return entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
    }

    private func refreshCoreProjectFileIndex() {
        guard supportsCoreProjectFileIndex,
              let coreDocuments = editorAreaController.coreDocuments
        else {
            return
        }

        _ = try? coreDocuments.refreshProjectFileIndexEnvelope().projectFileIndexSnapshot()
    }

    private func refreshedCoreProjectFileIndexEntries() -> [AttoWorkspaceFileIndex.Entry]? {
        guard supportsCoreProjectFileIndex,
              let snapshot = try? editorAreaController.coreDocuments?
                  .refreshProjectFileIndexEnvelope()
                  .projectFileIndexSnapshot()
        else {
            return nil
        }

        return workspaceFileEntries(from: snapshot.files)
    }

    private func coreProjectFileIndexEntries(
        matching query: String,
        maxResults: UInt32
    ) -> [AttoWorkspaceFileIndex.Entry]? {
        guard supportsCoreProjectFileIndexQuery,
              let coreDocuments = editorAreaController.coreDocuments
        else {
            return nil
        }

        _ = try? coreDocuments.refreshProjectFileIndexEnvelope().projectFileIndexSnapshot()
        guard let results = try? coreDocuments
            .queryProjectFileIndexEnvelope(query: query, maxResults: maxResults)
            .projectFileIndexQueryResults()
        else {
            return nil
        }
        return workspaceFileEntries(from: results)
    }

    private func coreWorkspaceFileEntries() -> [AttoWorkspaceFileIndex.Entry]? {
        guard supportsCoreWorkspaceFileList,
              let entries = try? editorAreaController.coreDocuments?
                  .listWorkspaceFilesEnvelope()
                  .workspaceFileEntries()
        else {
            return nil
        }

        return workspaceFileEntries(from: entries)
    }

    private func workspaceFileEntries(from entries: [EcuWorkspaceFileEntry]) -> [AttoWorkspaceFileIndex.Entry] {
        entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return AttoWorkspaceFileIndex.Entry(
                url: url.standardizedFileURL,
                relativePath: entry.relativePath
            )
        }
    }

    private func workspaceFileEntries(from entries: [EcuProjectFileIndexQueryResult]) -> [AttoWorkspaceFileIndex.Entry] {
        entries.compactMap { entry in
            guard let url = URL(string: entry.uri), url.isFileURL else { return nil }
            return AttoWorkspaceFileIndex.Entry(
                url: url.standardizedFileURL,
                relativePath: entry.relativePath
            )
        }
    }

    private func sessionWorkspaceRootURL() -> URL {
        if let coreRoot = coreWorkspaceRootURL() {
            return coreRoot
        }
        return workspaceRootURL.standardizedFileURL
    }

    private func coreWorkspaceRootURL() -> URL? {
        guard let roots = try? editorAreaController.coreDocuments?.snapshot().workspaceRoots else {
            return nil
        }

        for root in roots {
            guard let url = URL(string: root), url.isFileURL else { continue }
            return url.standardizedFileURL
        }
        return nil
    }

    private static func directoryExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
