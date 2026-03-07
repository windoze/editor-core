import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoEditorAreaViewController: NSViewController {
    enum OpenMode {
        case preview
        case pinned
    }

    private let library: EditorCoreUIFFILibrary
    private let theme: EditorCoreSkiaTheme
    private var workspaceRootURL: URL

    private var tabs: [AttoEditorTab] = []
    private var selectedTabID: UUID?

    private let tabBarView = AttoTabBarView()
    private let contentHostView = NSView(frame: .zero)
    private let statusBarView = AttoStatusBarView()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a file to start editing")

    private var activeViewportObserver: EditorCoreSkiaView.ViewportStateObserverToken?

    init(library: EditorCoreUIFFILibrary, theme: EditorCoreSkiaTheme, workspaceRootURL: URL) {
        self.library = library
        self.theme = theme
        self.workspaceRootURL = workspaceRootURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(attoHex: 0x1E1E1E).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tabBarView.onSelectTab = { [weak self] id in
            self?.selectTab(id: id)
        }
        tabBarView.onCloseTab = { [weak self] id in
            self?.closeTab(id: id)
        }
        tabBarView.translatesAutoresizingMaskIntoConstraints = false

        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.wantsLayer = true
        contentHostView.layer?.backgroundColor = NSColor(attoHex: 0x1E1E1E).cgColor

        emptyStateLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptyStateLabel.textColor = NSColor(attoHex: 0x8A8A8A)
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBarView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBarView)
        view.addSubview(contentHostView)
        view.addSubview(statusBarView)

        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 30),

            statusBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 20),

            contentHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHostView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
        ])

        showEmptyState()
        refreshTabBar()
        updateStatusBar()
    }

    func setWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
    }

    // MARK: - Tabs

    func openFile(url: URL) {
        openFile(url: url, mode: .pinned)
    }

    func openFile(url: URL, mode: OpenMode) {
        if let existing = tabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            if mode == .pinned, existing.isPreview {
                existing.isPreview = false
            }
            selectTab(id: existing.id)
            refreshTabBar()
            updateWindowTitle()
            return
        }

        do {
            switch mode {
            case .preview:
                if let previewIdx = tabs.firstIndex(where: { $0.isPreview }) {
                    // Safety: never discard dirty state; pin the preview tab if it got edited.
                    if tabs[previewIdx].isDirty {
                        tabs[previewIdx].isPreview = false
                    } else {
                        let tab = try makeTab(for: url, isPreview: true)
                        tabs[previewIdx] = tab
                        selectTab(id: tab.id)
                        return
                    }
                }

                let tab = try makeTab(for: url, isPreview: true)
                tabs.append(tab)
                selectTab(id: tab.id)

            case .pinned:
                let tab = try makeTab(for: url, isPreview: false)
                tabs.append(tab)
                selectTab(id: tab.id)
            }
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to open file %@: %@", url.path, String(describing: error))
        }
    }

    func closeActiveTab() {
        guard let selectedTabID else { return }
        closeTab(id: selectedTabID)
    }

    func saveActiveTab() {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let text = try tab.editCore.editor.text()
            try text.write(to: tab.fileURL, atomically: true, encoding: .utf8)
            tab.isDirty = false
            tab.isPreview = false
            refreshTabBar()
            updateWindowTitle()
            updateStatusBar()
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to save file %@: %@", tab.fileURL.path, String(describing: error))
        }
    }

    private func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = (selectedTabID == id)
        tabs.remove(at: idx)

        if wasSelected {
            if let next = tabs.indices.last {
                selectTab(id: tabs[next].id)
            } else {
                selectedTabID = nil
                showEmptyState()
                refreshTabBar()
                updateStatusBar()
            }
        } else {
            refreshTabBar()
        }
    }

    private func selectTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = id

        updateAlwaysPollProcessingForSelectedTab()

        showTabContent(tab)
        refreshTabBar()
        attachStatusObserver(to: tab.editCore.editorView)
        updateStatusBar()
        updateWindowTitle()
        tab.editCore.focusEditor()
    }

    private func refreshTabBar() {
        tabBarView.updateTabs(
            tabs: tabs.map { .init(id: $0.id, title: $0.displayTitle, toolTip: $0.fileURL.path, isPreview: $0.isPreview) },
            selectedID: selectedTabID
        )
    }

    // MARK: - Minimap

    func toggleMinimapForActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.showsMinimap.toggle()
        tab.editCore.needsLayout = true
        tab.editCore.needsDisplay = true
    }

    // MARK: - Status bar

    private var activeTab: AttoEditorTab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    private func updateWindowTitle() {
        guard let win = view.window else { return }
        guard let tab = activeTab else {
            win.title = "AttoEditor"
            return
        }

        let name = tab.fileURL.lastPathComponent
        if tab.isDirty {
            win.title = "AttoEditor — ● \(name)"
        } else {
            win.title = "AttoEditor — \(name)"
        }
    }

    private func handleTabDidMutateDocumentText(tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }

        if tab.isPreview {
            tab.isPreview = false
        }

        if tab.isDirty == false {
            tab.isDirty = true
        }

        refreshTabBar()
        updateWindowTitle()
    }

    private func attachStatusObserver(to editorView: EditorCoreSkiaView) {
        activeViewportObserver = editorView.addViewportStateObserver { [weak self] in
            self?.updateStatusBar()
        }
    }

    private func updateAlwaysPollProcessingForSelectedTab() {
        for tab in tabs {
            tab.editCore.alwaysPollProcessing = false
        }

        guard let tab = activeTab else { return }
        if (try? tab.editCore.editor.lspIsEnabled()) == true {
            tab.editCore.alwaysPollProcessing = true
        }
    }

    private func updateStatusBar() {
        guard let tab = activeTab else {
            statusBarView.update(
                leftText: nil,
                positionText: "Ln -, Col -",
                selectionText: nil,
                fileSizeText: nil
            )
            return
        }

        let editor = tab.editCore.editor

        let (line1, col1): (UInt32, UInt32) = {
            do {
                let offsets = try editor.selectionOffsets()
                let pos = try editor.charOffsetToLogicalPosition(offset: offsets.end)
                return (pos.line + 1, pos.column + 1)
            } catch {
                return (0, 0)
            }
        }()

        let selectionText: String? = {
            do {
                let sel = try editor.selections()
                let totalSelected: UInt64 = sel.ranges.reduce(0) { acc, r in
                    let a = UInt64(r.start)
                    let b = UInt64(r.end)
                    let len = a <= b ? (b - a) : (a - b)
                    return acc + len
                }
                let cursors = sel.ranges.count
                if totalSelected == 0 && cursors <= 1 {
                    return nil
                }
                if totalSelected == 0 {
                    return "\(cursors) cursors"
                }
                if cursors <= 1 {
                    return "Sel \(totalSelected)"
                }
                return "Sel \(totalSelected) (\(cursors) cursors)"
            } catch {
                return nil
            }
        }()

        let fileSizeText: String? = {
            do {
                let values = try tab.fileURL.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize else { return nil }
                return AttoFormat.byteCount(Int64(size))
            } catch {
                return nil
            }
        }()

        statusBarView.update(
            leftText: tab.fileURL.path,
            positionText: "Ln \(line1), Col \(col1)",
            selectionText: selectionText,
            fileSizeText: fileSizeText
        )
    }

    // MARK: - Content

    private func showEmptyState() {
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        contentHostView.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: contentHostView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentHostView.centerYAnchor),
        ])
    }

    private func showTabContent(_ tab: AttoEditorTab) {
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        let container = tab.editCore
        container.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),
        ])
    }

    // MARK: - Tab creation

    private func makeTab(for url: URL, isPreview: Bool) throws -> AttoEditorTab {
        let initialText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let fontFamiliesCSV = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_FONT_FAMILIES"]
            ?? ProcessInfo.processInfo.environment["ATTO_EDITOR_FONT_FAMILIES"]

        let editCore = try EditCoreUI(
            library: library,
            initialText: initialText,
            viewportWidthCells: 120,
            fontFamiliesCSV: fontFamiliesCSV,
            showsMinimap: true,
            minimapPlacement: .rightOfScrollbar
        )

        // VSCode-like defaults.
        try editCore.editor.setGutterWidthCells(6)
        // Visual aids enabled by default in AttoEditor MVP.
        try editCore.editor.setWhitespaceRenderMode(.selection)
        try editCore.editor.setIndentGuidesEnabled(true)
        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_ENABLE_LIGATURES"] == "1"
            || ProcessInfo.processInfo.environment["ATTO_EDITOR_ENABLE_LIGATURES"] == "1"
        {
            try editCore.editor.setFontLigaturesEnabled(true)
        }
        try editCore.applyTheme(theme)

        // LSP for Rust (best-effort).
        if url.pathExtension.lowercased() == "rs" {
            let disableLSP = ProcessInfo.processInfo.environment["ATTO_EDITOR_DISABLE_LSP"] == "1"
                || ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DISABLE_LSP"] == "1"

            if disableLSP == false {
                do {
                    let cmd = ProcessInfo.processInfo.environment["ATTO_EDITOR_LSP_CMD"]
                        ?? ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_LSP_CMD"]
                        ?? "rust-analyzer"
                    let args = ProcessInfo.processInfo.environment["ATTO_EDITOR_LSP_ARGS"]
                        ?? ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_LSP_ARGS"]

                    try editCore.editor.lspEnable(
                        command: cmd,
                        args: args,
                        rootURI: workspaceRootURL.absoluteString,
                        documentURI: url.absoluteString,
                        languageId: "rust"
                    )
                    editCore.editor.treeSitterDisable()
                } catch {
                    // Fall back to Tree-sitter highlighting if LSP is unavailable.
                    try? editCore.editor.treeSitterRustEnableDefault()
                }
            } else {
                try? editCore.editor.treeSitterRustEnableDefault()
            }
        }

        let tabId = UUID()
        let tab = AttoEditorTab(
            id: tabId,
            fileURL: url,
            isPreview: isPreview,
            isDirty: false,
            editCore: editCore
        )
        editCore.onDidMutateDocumentText = { [weak self] in
            self?.handleTabDidMutateDocumentText(tabID: tabId)
        }
        return tab
    }
}

@MainActor
private final class AttoEditorTab {
    let id: UUID
    let fileURL: URL
    var isPreview: Bool
    var isDirty: Bool
    let editCore: EditCoreUI

    var displayTitle: String {
        let name = fileURL.lastPathComponent
        if isDirty {
            return "● \(name)"
        }
        return name
    }

    init(
        id: UUID,
        fileURL: URL,
        isPreview: Bool,
        isDirty: Bool,
        editCore: EditCoreUI
    ) {
        self.id = id
        self.fileURL = fileURL
        self.isPreview = isPreview
        self.isDirty = isDirty
        self.editCore = editCore
    }
}

private extension NSColor {
    convenience init(attoHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((attoHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((attoHex >> 8) & 0xFF) / 255.0
        let b = CGFloat(attoHex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
