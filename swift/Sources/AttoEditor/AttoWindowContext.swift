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
    let fileExplorerController: AttoFileExplorerViewController
    let editorAreaController: AttoEditorAreaViewController

    var onWindowBecameKey: ((AttoWindowContext) -> Void)?
    var onWindowWillClose: ((AttoWindowContext) -> Void)?

    init(
        library: EditorCoreUIFFILibrary,
        theme: EditorCoreSkiaTheme,
        workspaceRootURL: URL,
        contentSize: CGSize
    ) {
        self.workspaceRootURL = workspaceRootURL

        let fileExplorer = AttoFileExplorerViewController(rootURL: workspaceRootURL)
        let editorArea = AttoEditorAreaViewController(
            library: library,
            theme: theme,
            workspaceRootURL: workspaceRootURL
        )

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
        self.fileExplorerController = fileExplorer
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

        setWorkspaceRootURL(workspaceRootURL)
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func setWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
        fileExplorerController.setRootURL(url)
        editorAreaController.setWorkspaceRootURL(url)
        fileIndex.setRootURL(url)
        recentFiles = []
        window.title = "AttoEditor — \(url.lastPathComponent)"
    }

    func rememberRecentFile(_ url: URL) {
        let u = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL == u }
        recentFiles.insert(u, at: 0)
        if recentFiles.count > 20 {
            recentFiles.removeLast(recentFiles.count - 20)
        }
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
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        onWindowBecameKey?(self)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowWillClose?(self)
    }
}
