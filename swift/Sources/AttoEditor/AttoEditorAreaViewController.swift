import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoEditorAreaViewController: NSViewController {
    struct OpenFileItem: Hashable {
        let id: UUID
        let url: URL
        let title: String
        let isDirty: Bool
        let isPreview: Bool
    }

    enum OpenMode {
        case preview
        case pinned
    }

    private let library: EditorCoreUIFFILibrary
    private var theme: EditorCoreSkiaTheme
    private var workspaceRootURL: URL
    private let preferences: AttoPreferences

    private var tabs: [AttoEditorTab] = []
    private var selectedTabID: UUID?

    private let tabBarView = AttoTabBarView()
    private let findReplaceBarView = AttoFindReplaceBarView()
    private var findReplaceBarHeightConstraint: NSLayoutConstraint?
    private let contentHostView = NSView(frame: .zero)
    private let statusBarView = AttoStatusBarView()
    private let emptyStateLabel = NSTextField(labelWithString: "Open a file to start editing")

    private var activeViewportObserver: EditorCoreSkiaView.ViewportStateObserverToken?

    private var didAttemptLoadTreeSitterRegistry: Bool = false
    private var treeSitterRegistryJSON: String?
    private var treeSitterLanguageIDs: [String] = []
    private var treeSitterExtensionMap: [String: String] = [:]

    var onDidCloseFile: ((URL) -> Void)?
    /// (url, createdOnDisk)
    var onDidSaveFile: ((URL, Bool) -> Void)?
    var onOpenFilesChanged: (([OpenFileItem], UUID?) -> Void)?
    var onSessionStateChanged: (() -> Void)?

    private var isRestoringSession: Bool = false

    private struct HoverRequestContext {
        let tabID: UUID
        let info: EditorCoreSkiaHoverInfo
    }

    private enum LspLocationRequestKind {
        case definition
        case declaration
        case typeDefinition
        case implementation
        case references
    }

    private enum LspSymbolRequestKind {
        case document
        case workspace(query: String)
    }

    private struct DefinitionRequestContext {
        let tabID: UUID
        let logicalLine: UInt32
        let logicalColumn: UInt32
        let kind: LspLocationRequestKind
    }

    private struct SymbolRequestContext {
        let tabID: UUID
        let kind: LspSymbolRequestKind
    }

    private struct SignatureHelpRequestContext {
        let tabID: UUID
        let showEmptyResults: Bool
    }

    private struct CompletionRequestContext {
        let tabID: UUID
        let fallbackStart: UInt32
        let fallbackEnd: UInt32
        let beepOnFailure: Bool
    }

    private struct CompletionResolveContext {
        let request: CompletionRequestContext
        let item: AttoLspCompletionParser.Item
        let commitCharacter: String?
    }

    private struct RenameRequestContext {
        let tabID: UUID
        let documentURI: String
    }

    private struct RenamePrepareContext {
        let tabID: UUID
        let fallbackSeed: AttoLspRenameSupport.DialogSeed
    }

    private struct CodeActionRequestContext {
        let tabID: UUID
        let onlyKinds: [String]
    }

    private struct CodeActionResolveContext {
        let tabID: UUID
        let item: AttoLspCodeActionParser.Item
    }

    private var hoverContext: HoverRequestContext?
    private var hoverDebounceWorkItem: DispatchWorkItem?
    private var hoverPollTimer: DispatchSourceTimer?
    private var hoverPopover: NSPopover?
    private var hoverPopoverLabel: NSTextField?
    private var workspaceEditPopover: NSPopover?
    private var workspaceEditPopoverLabel: NSTextField?

    private var definitionContext: DefinitionRequestContext?
    private var definitionPollTimer: DispatchSourceTimer?
    private var lspLocationResultsController: AttoCommandPaletteController?

    private var symbolContext: SymbolRequestContext?
    private var symbolPollTimer: DispatchSourceTimer?
    private var lspSymbolResultsController: AttoCommandPaletteController?

    private var signatureHelpContext: SignatureHelpRequestContext?
    private var signatureHelpPollTimer: DispatchSourceTimer?
    private var signatureHelpPopover: NSPopover?
    private var signatureHelpPopoverLabel: NSTextField?

    private var completionContext: CompletionRequestContext?
    private var completionPollTimer: DispatchSourceTimer?
    private var completionResolveContext: CompletionResolveContext?
    private var completionResolvePollTimer: DispatchSourceTimer?
    private var completionListController: AttoCompletionListController?
    private var completionListContext: CompletionRequestContext?
    private var shouldPreserveCompletionUIForCurrentTextMutation = false

    private var renameContext: RenameRequestContext?
    private var renamePollTimer: DispatchSourceTimer?
    private var renamePrepareContext: RenamePrepareContext?
    private var renamePreparePollTimer: DispatchSourceTimer?

    private var codeActionContext: CodeActionRequestContext?
    private var codeActionPollTimer: DispatchSourceTimer?
    private var codeActionResolveContext: CodeActionResolveContext?
    private var codeActionResolvePollTimer: DispatchSourceTimer?
    private var codeActionResultsController: AttoCommandPaletteController?

    init(
        library: EditorCoreUIFFILibrary,
        theme: EditorCoreSkiaTheme,
        workspaceRootURL: URL,
        preferences: AttoPreferences = .shared
    ) {
        self.library = library
        self.theme = theme
        self.workspaceRootURL = workspaceRootURL
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(ecuRgba8: theme.editorBackground).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tabBarView.onSelectTab = { [weak self] id in
            self?.selectTab(id: id)
        }
        tabBarView.onCloseTab = { [weak self] id in
            self?.closeTab(id: id)
        }
        tabBarView.onDoubleClickTab = { [weak self] id in
            self?.pinTabIfPreview(id: id)
        }
        tabBarView.translatesAutoresizingMaskIntoConstraints = false

        findReplaceBarView.translatesAutoresizingMaskIntoConstraints = false
        findReplaceBarView.isHidden = true
        findReplaceBarView.searchField.delegate = self
        findReplaceBarView.searchField.target = self
        findReplaceBarView.searchField.action = #selector(findNextClicked(_:))
        findReplaceBarView.replaceField.delegate = self

        for b in [findReplaceBarView.caseSensitiveButton, findReplaceBarView.wholeWordButton, findReplaceBarView.regexButton] {
            b.target = self
            b.action = #selector(findOptionsChanged(_:))
        }
        findReplaceBarView.findPrevButton.target = self
        findReplaceBarView.findPrevButton.action = #selector(findPrevClicked(_:))
        findReplaceBarView.findNextButton.target = self
        findReplaceBarView.findNextButton.action = #selector(findNextClicked(_:))
        findReplaceBarView.clearButton.target = self
        findReplaceBarView.clearButton.action = #selector(clearFindClicked(_:))
        findReplaceBarView.replaceCurrentButton.target = self
        findReplaceBarView.replaceCurrentButton.action = #selector(replaceCurrentClicked(_:))
        findReplaceBarView.replaceAllButton.target = self
        findReplaceBarView.replaceAllButton.action = #selector(replaceAllClicked(_:))
        findReplaceBarView.closeButton.target = self
        findReplaceBarView.closeButton.action = #selector(closeFindBarClicked(_:))

        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.wantsLayer = true
        contentHostView.layer?.backgroundColor = NSColor(ecuRgba8: theme.editorBackground).cgColor

        emptyStateLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptyStateLabel.textColor = NSColor(attoHex: 0x8A8A8A)
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.onSelectLanguage = { [weak self] languageId in
            self?.setSyntaxLanguageForActiveTab(languageId: languageId)
        }
        refreshStatusBarLanguageOptions()

        view.addSubview(tabBarView)
        view.addSubview(findReplaceBarView)
        view.addSubview(contentHostView)
        view.addSubview(statusBarView)

        findReplaceBarHeightConstraint = findReplaceBarView.heightAnchor.constraint(equalToConstant: 0)
        findReplaceBarHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 30),

            findReplaceBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            findReplaceBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            findReplaceBarView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),

            statusBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 20),

            contentHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHostView.topAnchor.constraint(equalTo: findReplaceBarView.bottomAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
        ])

        showEmptyState()
        refreshTabBar()
        updateStatusBar()
    }

    private func loadTreeSitterRegistryCacheIfNeeded() {
        guard didAttemptLoadTreeSitterRegistry == false else { return }
        didAttemptLoadTreeSitterRegistry = true

        do {
            let paths = try AttoTreeSitterRegistry.defaultPaths()
            let registryJSON = try AttoTreeSitterRegistry.buildRegistryJSON(treesitterRoot: paths.treesitterRoot)
            treeSitterRegistryJSON = registryJSON

            guard let data = registryJSON.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            else {
                return
            }

            if let extMap = obj["extension_map"] as? [String: String] {
                treeSitterExtensionMap = extMap
            }

            if let languages = obj["languages"] as? [String: Any] {
                treeSitterLanguageIDs = languages.keys.sorted { a, b in
                    a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
            }
        } catch {
            NSLog("AttoEditor: failed to load Tree-sitter registry: %@", String(describing: error))
        }
    }

    private func refreshStatusBarLanguageOptions() {
        loadTreeSitterRegistryCacheIfNeeded()
        var opts: [AttoStatusBarView.LanguageOption] = [
            .init(id: nil, title: "Plain Tex"),
        ]
        for id in treeSitterLanguageIDs {
            opts.append(.init(id: id, title: id))
        }
        statusBarView.setLanguageOptions(opts)
    }

    private func inferredTreeSitterLanguageId(for url: URL) -> String? {
        loadTreeSitterRegistryCacheIfNeeded()
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ext.isEmpty == false else { return nil }
        return treeSitterExtensionMap[ext]
    }

    func setWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
    }

    // MARK: - Preferences (editor rendering)

    func applyEditorPreferences() {
        let fontFamiliesCSV = preferences.fontFamiliesCSVForApplying()
        let ligaturesEnabled = preferences.effectiveLigaturesEnabled
        let autoPairsEnabled = preferences.effectiveAutoPairsEnabled
        let wrapMode = preferences.effectiveWrapMode
        let wrapIndent = preferences.effectiveWrapIndent
        let fontSizePoints = preferences.effectiveFontSizePoints

        for tab in tabs {
            for editCore in tab.panes {
                // Font families: empty CSV means "reset to default" (Skia renderer falls back).
                do {
                    try editCore.editor.setFontFamiliesCSV(fontFamiliesCSV)
                } catch {
                    NSLog("AttoEditor: setFontFamiliesCSV failed: %@", String(describing: error))
                }

                do {
                    try editCore.editor.setFontLigaturesEnabled(ligaturesEnabled)
                } catch {
                    NSLog("AttoEditor: setFontLigaturesEnabled failed: %@", String(describing: error))
                }

                do {
                    try editCore.editor.setAutoPairsEnabled(autoPairsEnabled)
                } catch {
                    NSLog("AttoEditor: setAutoPairsEnabled failed: %@", String(describing: error))
                }

                do {
                    _ = try editCore.editor.setWrapMode(wrapMode)
                } catch {
                    NSLog("AttoEditor: setWrapMode failed: %@", String(describing: error))
                }

                do {
                    _ = try editCore.editor.setWrapIndent(wrapIndent)
                } catch {
                    NSLog("AttoEditor: setWrapIndent failed: %@", String(describing: error))
                }

                editCore.editorView.fontSizePoints = CGFloat(fontSizePoints)
                editCore.editorView.needsDisplay = true
            }
        }
    }

    func applyTheme(_ theme: EditorCoreSkiaTheme) {
        self.theme = theme

        if isViewLoaded {
            let bg = NSColor(ecuRgba8: theme.editorBackground).cgColor
            view.layer?.backgroundColor = bg
            contentHostView.layer?.backgroundColor = bg
        }

        for tab in tabs {
            for editCore in tab.panes {
                do {
                    try editCore.applyTheme(theme)
                } catch {
                    NSLog("AttoEditor: applyTheme failed: %@", String(describing: error))
                }
            }
        }
    }

    // MARK: - Tabs

    func makeSessionSnapshot() -> (tabs: [AttoTabSnapshot], selectedTabIndex: Int?) {
        let selectedIndex: Int? = {
            guard let selectedTabID else { return nil }
            return tabs.firstIndex(where: { $0.id == selectedTabID })
        }()

        let tabSnaps: [AttoTabSnapshot] = tabs.map { tab in
            AttoTabSnapshot(
                filePath: tab.fileURL.standardizedFileURL.path,
                isPreview: tab.isPreview,
                showsMinimap: tab.editCore.showsMinimap
            )
        }

        return (tabs: tabSnaps, selectedTabIndex: selectedIndex)
    }

    func restoreSession(tabs tabSnapshots: [AttoTabSnapshot], selectedTabIndex: Int?) {
        isRestoringSession = true
        defer { isRestoringSession = false }

        cancelHoverUI()
        cancelRenameUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelCodeActionUI()

        tabs = []
        selectedTabID = nil

        var didUsePreview = false
        var newTabs: [AttoEditorTab] = []
        newTabs.reserveCapacity(tabSnapshots.count)

        for snap in tabSnapshots {
            let url = URL(fileURLWithPath: snap.filePath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let wantsPreview = snap.isPreview && (didUsePreview == false)
            if wantsPreview { didUsePreview = true }

            do {
                let tab = try makeTab(
                    for: url,
                    isPreview: wantsPreview,
                    showsMinimap: snap.showsMinimap ?? true
                )
                newTabs.append(tab)
            } catch {
                NSLog("AttoEditor: session restore failed to open file %@: %@", url.path, String(describing: error))
            }
        }

        tabs = newTabs

        if newTabs.isEmpty {
            showEmptyState()
            refreshTabBar()
            updateStatusBar()
            updateWindowTitle()
            onOpenFilesChanged?(openFileItems(), selectedTabID)
            return
        }

        let idx = selectedTabIndex ?? 0
        let safeIdx = (0..<newTabs.count).contains(idx) ? idx : 0
        selectTab(id: newTabs[safeIdx].id)
    }

    private func notifySessionStateChanged() {
        guard isRestoringSession == false else { return }
        onSessionStateChanged?()
    }

    func openFile(url: URL) {
        openFile(url: url, mode: .pinned)
    }

    @discardableResult
    func openFile(url: URL, mode: OpenMode, isUntitled: Bool = false) -> Bool {
        if let existing = tabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            if mode == .pinned, existing.isPreview {
                existing.isPreview = false
            }
            selectTab(id: existing.id)
            refreshTabBar()
            updateWindowTitle()
            notifySessionStateChanged()
            return true
        }

        do {
            switch mode {
            case .preview:
                if let previewIdx = tabs.firstIndex(where: { $0.isPreview }) {
                    // Safety: never discard dirty state; pin the preview tab if it got edited.
                    if tabs[previewIdx].isDirty {
                        tabs[previewIdx].isPreview = false
                    } else {
                        let oldURL = tabs[previewIdx].fileURL
                        let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                        tabs[previewIdx] = tab
                        selectTab(id: tab.id)
                        onDidCloseFile?(oldURL)
                        notifySessionStateChanged()
                        return true
                    }
                }

                let tab = try makeTab(for: url, isPreview: true, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                notifySessionStateChanged()

            case .pinned:
                let tab = try makeTab(for: url, isPreview: false, isUntitled: isUntitled)
                tabs.append(tab)
                selectTab(id: tab.id)
                notifySessionStateChanged()
            }
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to open file %@: %@", url.path, String(describing: error))
            return false
        }
    }

    @discardableResult
    func openFile(url: URL, mode: OpenMode, location: AttoCommandLine.FileLocation?) -> Bool {
        let ok = openFile(url: url, mode: mode)
        guard ok else { return false }
        guard let location else { return true }
        guard let tab = activeTab, tab.fileURL.standardizedFileURL == url.standardizedFileURL else { return true }
        navigate(tab: tab, to: location)
        return true
    }

    func containsFile(url: URL) -> Bool {
        tabs.contains { $0.fileURL.standardizedFileURL == url.standardizedFileURL }
    }

    func openFileURLs() -> [URL] {
        tabs.map(\.fileURL)
    }

    func openFileItems() -> [OpenFileItem] {
        tabs.map { tab in
            OpenFileItem(
                id: tab.id,
                url: tab.fileURL,
                title: tab.displayTitle,
                isDirty: tab.isDirty,
                isPreview: tab.isPreview
            )
        }
    }

    func selectFile(url: URL) {
        guard let tab = tabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) else { return }
        selectTab(id: tab.id)
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
        _ = saveTabWithSavePanelIfNeeded(tab)
    }

    func confirmClosingDirtyTabsIfNeeded() -> Bool {
        let dirtyTabs = tabs.filter { $0.isDirty }
        guard dirtyTabs.isEmpty == false else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "Do you want to save your changes before closing?"
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveAllDirtyTabs()
        case .alertSecondButtonReturn:
            return false
        default:
            return true
        }
    }

    private enum DirtyCloseDecision {
        case save
        case dontSave
        case cancel
    }

    private func confirmCloseDirtyTab(_ tab: AttoEditorTab) -> DirtyCloseDecision {
        let name = tab.fileURL.lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \"\(name)\" before closing?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .cancel
        default:
            return .dontSave
        }
    }

    @discardableResult
    private func saveTab(_ tab: AttoEditorTab) -> Bool {
        let fm = FileManager.default
        let existedOnDiskBeforeSave = fm.fileExists(atPath: tab.fileURL.path)
        do {
            let text = try tab.editCore.editor.text()
            try text.write(to: tab.fileURL, atomically: true, encoding: .utf8)
            try tab.editCore.editor.markSaved()
            tab.isUntitled = false
            tab.isDirty = false
            tab.isPreview = false
            refreshTabBar()
            updateWindowTitle()
            updateStatusBar()
            notifySessionStateChanged()
            onDidSaveFile?(tab.fileURL, existedOnDiskBeforeSave == false)
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: failed to save file %@: %@", tab.fileURL.path, String(describing: error))
            return false
        }
    }

    private func saveAllDirtyTabs() -> Bool {
        for tab in tabs {
            if tab.isDirty {
                if saveTabWithSavePanelIfNeeded(tab) == false {
                    return false
                }
            }
        }
        return true
    }

    private func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[idx]
        if tab.isDirty {
            switch confirmCloseDirtyTab(tab) {
            case .cancel:
                return
            case .save:
                guard saveTabWithSavePanelIfNeeded(tab) else { return }
            case .dontSave:
                break
            }
        }

        let url = tab.fileURL
        let wasSelected = (selectedTabID == id)
        tabs.remove(at: idx)
        onDidCloseFile?(url)
        notifySessionStateChanged()

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
        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelRenameUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelCodeActionUI()

        showTabContent(tab)
        refreshTabBar()
        attachStatusObserver(to: tab.editCore.editorView)
        updateStatusBar()
        updateWindowTitle()
        tab.editCore.focusEditor()

        applyFindStateToActiveTab()
        notifySessionStateChanged()
    }

    private func refreshTabBar() {
        tabBarView.updateTabs(
            tabs: tabs.map { .init(id: $0.id, title: $0.displayTitle, toolTip: $0.fileURL.path, isPreview: $0.isPreview) },
            selectedID: selectedTabID
        )
        onOpenFilesChanged?(openFileItems(), selectedTabID)
    }

    private func pinTabIfPreview(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard tab.isPreview else { return }
        tab.isPreview = false
        refreshTabBar()
        notifySessionStateChanged()
    }

    // MARK: - Minimap

    func toggleMinimapForActiveTab() {
        guard let tab = activeTab else { return }
        let nextValue = tab.editCore.showsMinimap == false
        for editCore in tab.panes {
            editCore.showsMinimap = nextValue
            editCore.needsLayout = true
            editCore.needsDisplay = true
        }
        notifySessionStateChanged()
    }

    // MARK: - Split panes

    @discardableResult
    func splitActiveTabRight() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let editor = try tab.editCore.editor.cloneView(viewportWidthCells: 120)
            let pane = try EditCoreUI(
                editor: editor,
                fontFamiliesCSV: AttoPreferences.shared.fontFamiliesCSVForNewViews(),
                showsMinimap: tab.editCore.showsMinimap,
                minimapPlacement: .rightOfScrollbar
            )

            try configureEditorChrome(pane)
            applyLanguageConfiguration(fileURL: tab.fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: pane)
            configureEditCoreHooks(pane, tabID: tab.id)

            tab.panes.append(pane)
            tab.activePaneIndex = tab.panes.count - 1
            showTabContent(tab)
            attachStatusObserver(to: pane.editorView)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            pane.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: split active tab failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func focusNextPaneInActiveTab() -> Bool {
        focusPaneInActiveTab(delta: 1)
    }

    @discardableResult
    func focusPreviousPaneInActiveTab() -> Bool {
        focusPaneInActiveTab(delta: -1)
    }

    @discardableResult
    func closeActivePane() -> Bool {
        guard let tab = activeTab, tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let idx = max(0, min(tab.activePaneIndex, tab.panes.count - 1))
        let pane = tab.panes.remove(at: idx)
        pane.removeFromSuperview()
        tab.activePaneIndex = min(idx, tab.panes.count - 1)

        let activePane = tab.editCore
        showTabContent(tab)
        attachStatusObserver(to: activePane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        activePane.focusEditor()
        return true
    }

    @discardableResult
    private func focusPaneInActiveTab(delta: Int) -> Bool {
        guard let tab = activeTab, tab.panes.count > 1 else {
            NSSound.beep()
            return false
        }

        let count = tab.panes.count
        let current = max(0, min(tab.activePaneIndex, count - 1))
        let next = (current + delta + count) % count
        tab.activePaneIndex = next

        let activePane = tab.editCore
        attachStatusObserver(to: activePane.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
        activePane.focusEditor()
        return true
    }

    // MARK: - Editor commands

    @discardableResult
    func executeActiveEditorCommandJSON(_ commandJSON: String, treatsAsTextMutation: Bool? = nil) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let isTextMutation = treatsAsTextMutation ?? Self.commandJSONIsTextMutation(commandJSON)

        do {
            _ = try tab.editCore.editor.executeCommandJSON(commandJSON)
            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true

            if isTextMutation {
                handleTabDidMutateDocumentText(tabID: tab.id)
            }

            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func toggleLineCommentInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        return executeActiveEditorCommandObject([
            "kind": "edit",
            "op": "toggle_comment",
            "config": [
                "line": AttoLanguageConfiguration.lineCommentToken(
                    fileURL: tab.fileURL,
                    syntaxLanguageId: tab.syntaxLanguageId
                ),
            ],
        ])
    }

    @discardableResult
    func foldSelectionInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let startOffset = min(offsets.start, offsets.end)
            let endOffset = max(offsets.start, offsets.end)
            let effectiveEndOffset = endOffset > startOffset ? endOffset - 1 : endOffset
            let start = try tab.editCore.editor.charOffsetToLogicalPosition(offset: startOffset)
            let end = try tab.editCore.editor.charOffsetToLogicalPosition(offset: effectiveEndOffset)

            guard end.line > start.line else {
                NSSound.beep()
                return false
            }

            return executeActiveEditorCommandJSON(
                #"{"kind":"style","op":"fold","start_line":\#(start.line),"end_line":\#(end.line)}"#,
                treatsAsTextMutation: false
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func unfoldAtCursorInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return executeActiveEditorCommandJSON(
                #"{"kind":"style","op":"unfold","start_line":\#(pos.line)}"#,
                treatsAsTextMutation: false
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func unfoldAllInActiveTab() -> Bool {
        executeActiveEditorCommandJSON(
            #"{"kind":"style","op":"unfold_all"}"#,
            treatsAsTextMutation: false
        )
    }

    func moveToMatchingBracketInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.moveToMatchingBracket()
    }

    func jumpBackInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.jumpBack()
    }

    func jumpForwardInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.jumpForward()
    }

    @discardableResult
    func formatDocumentWithLspInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        let applied = tab.editCore.editorView.formatDocumentWithLSP()
        if applied {
            updateStatusBar()
        }
        return applied
    }

    @discardableResult
    func formatSelectionWithLspInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let startOffset = min(offsets.start, offsets.end)
            let endOffset = max(offsets.start, offsets.end)
            guard startOffset < endOffset else {
                NSSound.beep()
                return false
            }

            let applied = tab.editCore.editorView.formatRangeWithLSP(
                startOffset: startOffset,
                endOffset: endOffset
            )
            if applied {
                updateStatusBar()
            }
            return applied
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    private func executeActiveEditorCommandObject(_ object: [String: Any], treatsAsTextMutation: Bool? = nil) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [])
            guard let json = String(data: data, encoding: .utf8) else {
                NSSound.beep()
                return false
            }
            return executeActiveEditorCommandJSON(json, treatsAsTextMutation: treatsAsTextMutation)
        } catch {
            NSSound.beep()
            return false
        }
    }

    private static func commandJSONIsTextMutation(_ commandJSON: String) -> Bool {
        guard let data = commandJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              (obj["kind"] as? String) == "edit"
        else {
            return false
        }
        return (obj["op"] as? String) != "end_undo_group"
    }

    // MARK: - Find / Replace

    func showFindBar() {
        if findReplaceBarView.isHidden {
            guard activeTab != nil else {
                NSSound.beep()
                return
            }
            ensureFindReplaceBar(mode: .find)
            return
        }

        if findReplaceBarView.currentMode() == .find {
            hideFindBar()
            return
        }

        ensureFindReplaceBar(mode: .find)
    }

    func showReplaceBar() {
        if findReplaceBarView.isHidden {
            guard activeTab != nil else {
                NSSound.beep()
                return
            }
            ensureFindReplaceBar(mode: .replace)
            return
        }

        if findReplaceBarView.currentMode() == .replace {
            hideFindBar()
            return
        }

        ensureFindReplaceBar(mode: .replace)
    }

    private func ensureFindReplaceBar(mode: AttoFindReplaceBarView.Mode) {
        let wasHidden = findReplaceBarView.isHidden
        let oldMode = findReplaceBarView.currentMode()

        findReplaceBarView.setMode(mode)
        findReplaceBarView.isHidden = false
        findReplaceBarHeightConstraint?.constant = (mode == .find) ? 42 : 76

        view.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(findReplaceBarView.searchField)
        findReplaceBarView.searchField.selectText(nil)

        // Always re-apply highlights on show/switch; `activeTab == nil` is fine (no-op).
        if wasHidden || oldMode != mode {
            applyFindStateToActiveTab()
        } else {
            refreshSearchHighlights()
        }
    }

    func hideFindBar() {
        guard findReplaceBarView.isHidden == false else { return }
        clearSearchHighlightsForAllTabs()
        findReplaceBarView.isHidden = true
        findReplaceBarHeightConstraint?.constant = 0
        activeTab?.editCore.focusEditor()
    }

    private func currentSearchOptions() -> EcuSearchOptions {
        EcuSearchOptions(
            caseSensitive: findReplaceBarView.caseSensitiveButton.state == .on,
            wholeWord: findReplaceBarView.wholeWordButton.state == .on,
            regex: findReplaceBarView.regexButton.state == .on
        )
    }

    private func setMatchCountLabel(_ count: UInt32) {
        findReplaceBarView.matchCountLabel.stringValue = "\(count) matches"
    }

    private func applyFindStateToActiveTab() {
        guard findReplaceBarView.isHidden == false else { return }
        refreshSearchHighlights()
    }

    private func clearSearchHighlightsForAllTabs() {
        for tab in tabs {
            do {
                try tab.editCore.editor.clearSearchQuery()
                tab.editCore.editorView.needsDisplay = true
            } catch {
                // Ignore best-effort cleanup errors.
            }
        }
        setMatchCountLabel(0)
    }

    private func refreshSearchHighlights() {
        guard let tab = activeTab else {
            setMatchCountLabel(0)
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            if query.isEmpty {
                try tab.editCore.editor.clearSearchQuery()
                setMatchCountLabel(0)
            } else {
                let count = try tab.editCore.editor.setSearchQuery(query, options: currentSearchOptions())
                setMatchCountLabel(count)
            }
            tab.editCore.editorView.needsDisplay = true
        } catch {
            NSSound.beep()
        }
    }

    @objc private func findOptionsChanged(_ sender: Any?) {
        refreshSearchHighlights()
    }

    @objc private func clearFindClicked(_ sender: Any?) {
        findReplaceBarView.searchField.stringValue = ""
        refreshSearchHighlights()
        view.window?.makeFirstResponder(findReplaceBarView.searchField)
    }

    @objc private func findNextClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try tab.editCore.editor.findNext(query, options: currentSearchOptions())
            if ok == false { NSSound.beep() }
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func findPrevClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try tab.editCore.editor.findPrev(query, options: currentSearchOptions())
            if ok == false { NSSound.beep() }
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.needsDisplay = true
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func replaceCurrentClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = findReplaceBarView.replaceField.stringValue
            _ = try tab.editCore.editor.replaceCurrent(query: query, replacement: replacement, options: currentSearchOptions())
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            refreshSearchHighlights()
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func replaceAllClicked(_ sender: Any?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        do {
            let query = findReplaceBarView.searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = findReplaceBarView.replaceField.stringValue
            _ = try tab.editCore.editor.replaceAll(query: query, replacement: replacement, options: currentSearchOptions())
            tab.editCore.layoutSubtreeIfNeeded()
            try tab.editCore.editor.revealPrimaryCaret()
            refreshSearchHighlights()
            updateStatusBar()
            view.window?.makeFirstResponder(findReplaceBarView.searchField)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func closeFindBarClicked(_ sender: Any?) {
        hideFindBar()
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
        let preserveCompletionUI = shouldPreserveCompletionUIForCurrentTextMutation
        if selectedTabID == tabID {
            cancelSignatureHelpUI()
            if preserveCompletionUI == false {
                cancelCompletionUI()
            }
        }

        let didUnpreview = tab.isPreview
        if tab.isPreview {
            tab.isPreview = false
        }

        tab.isDirty = (try? tab.editCore.editor.isModified()) ?? true

        refreshTabBar()
        updateWindowTitle()
        if didUnpreview {
            notifySessionStateChanged()
        }
    }

    private func attachStatusObserver(to editorView: EditorCoreSkiaView) {
        activeViewportObserver = editorView.addViewportStateObserver { [weak self] in
            self?.updateStatusBar()
        }
    }

    private func updateAlwaysPollProcessingForSelectedTab() {
        for tab in tabs {
            for editCore in tab.panes {
                editCore.alwaysPollProcessing = false
            }
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
                languageId: nil,
                languageIsEnabled: false,
                lspText: nil,
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
                if cursors <= 1, let primary = sel.ranges.first {
                    let a = primary.start
                    let b = primary.end
                    let start = min(a, b)
                    let end = max(a, b)
                    let len = UInt64(end - start)
                    if len == 0 {
                        return nil
                    }
                    let startPos = try editor.charOffsetToLogicalPosition(offset: start)
                    let endPos = try editor.charOffsetToLogicalPosition(offset: end)
                    return "Sel \(len) (\(startPos.line + 1):\(startPos.column + 1)-\(endPos.line + 1):\(endPos.column + 1))"
                }
                if totalSelected == 0 {
                    return "\(cursors) cursors"
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

        let lspText: String? = {
            // Keep the status bar clean unless LSP is likely relevant.
            //
            // - Historically, AttoEditor only auto-enabled LSP for Rust.
            // - With configurable LSPs, show LSP status when it is enabled (any language), or for Rust files.
            let isRustFile = (tab.fileURL.pathExtension.lowercased() == "rs")
            let isEnabled = (try? editor.lspIsEnabled()) == true
            guard isRustFile || isEnabled else { return nil }

            do {
                let raw = try editor.lspStatusJSON()
                guard let data = raw.data(using: .utf8),
                      let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                else {
                    return (try? editor.lspIsEnabled()) == true ? "LSP: on" : "LSP: off"
                }

                let state = (obj["state"] as? String) ?? "disabled"
                let detail = obj["detail"] as? String

                var name: String? = nil
                if let server = obj["server"] as? [String: Any] {
                    name = server["name"] as? String
                    if name == nil {
                        name = server["command"] as? String
                    }
                }

                var title: String? = nil
                var pct: String? = nil
                if let activity = obj["activity"] as? [String: Any] {
                    title = activity["title"] as? String
                    if let p = activity["percentage"] as? UInt {
                        pct = "\(p)%"
                    } else if let p = activity["percentage"] as? Int {
                        pct = "\(p)%"
                    } else if let p = activity["percentage"] as? Double {
                        pct = "\(Int(p))%"
                    }
                }

                let prefix: String = {
                    if let name, name.isEmpty == false {
                        return "LSP \(name):"
                    }
                    return "LSP:"
                }()

                switch state {
                case "ready":
                    return "\(prefix) Ready"
                case "indexing":
                    let t = (title?.isEmpty == false) ? title! : "Indexing"
                    if let pct { return "\(prefix) \(t) \(pct)" }
                    return "\(prefix) \(t)"
                case "busy":
                    let t = (title?.isEmpty == false) ? title! : "Busy"
                    if let pct { return "\(prefix) \(t) \(pct)" }
                    return "\(prefix) \(t)"
                case "failed":
                    // Keep it short: show the detailed reason in logs only.
                    if let detail, detail.isEmpty == false {
                        NSLog("AttoEditor: LSP status failed: %@", detail)
                    }
                    return "\(prefix) Failed"
                default:
                    return "\(prefix) Off"
                }
            } catch {
                // Best-effort: never break status bar rendering because of FFI errors.
                return (try? editor.lspIsEnabled()) == true ? "LSP: on" : "LSP: off"
            }
        }()

        statusBarView.update(
            leftText: nil,
            languageId: tab.syntaxLanguageId,
            languageIsEnabled: true,
            lspText: lspText,
            positionText: "Ln \(line1), Col \(col1)",
            selectionText: selectionText,
            fileSizeText: fileSizeText
        )
    }

    private func setSyntaxLanguageForActiveTab(languageId: String?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        // "Plain Tex" => disable all syntax engines.
        if languageId == nil {
            tab.editCore.editor.lspDisable()
            tab.editCore.editor.treeSitterDisable()
            tab.editCore.editor.sublimeDisable()
            tab.syntaxLanguageId = nil
            applyLanguageConfiguration(for: tab)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            tab.editCore.editorView.needsDisplay = true
            return
        }

        let lang = (languageId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if lang.isEmpty {
            NSSound.beep()
            return
        }

        // Force Tree-sitter with an explicit language id.
        loadTreeSitterRegistryCacheIfNeeded()
        if let registryJSON = treeSitterRegistryJSON {
            // Best-effort (each editor view owns its own registry state).
            try? tab.editCore.editor.treeSitterSetRegistryJSON(registryJSON)
        }

        tab.editCore.editor.lspDisable()
        tab.editCore.editor.sublimeDisable()

        do {
            try tab.editCore.editor.treeSitterEnableLanguage(lang)
            tab.syntaxLanguageId = lang
            applyLanguageConfiguration(for: tab)
            tab.editCore.editorView.kickProcessingPoll()
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            tab.editCore.editorView.needsDisplay = true
        } catch {
            NSSound.beep()
            NSLog(
                "AttoEditor: failed to set Tree-sitter language %@ for %@: %@",
                lang,
                tab.fileURL.path,
                String(describing: error)
            )
            updateStatusBar()
        }
    }

    // MARK: - Navigation

    private func navigate(tab: AttoEditorTab, to location: AttoCommandLine.FileLocation) {
        let line1 = max(1, location.line1)
        let column1 = max(1, location.column1 ?? 1)

        do {
            tab.editCore.layoutSubtreeIfNeeded()
            let text = try tab.editCore.editor.text()
            let offset = Self.charOffsetForLineColumn1(text: text, line1: line1, column1: column1)
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: offset, end: offset)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }

    private static func charOffsetForLineColumn1(text: String, line1: Int, column1: Int) -> UInt32 {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let targetLineIdx = max(0, line1 - 1)
        if targetLineIdx >= lines.count {
            return UInt32(text.count)
        }

        var offset: Int = 0
        if targetLineIdx > 0 {
            for i in 0..<targetLineIdx {
                offset += lines[i].count
                offset += 1 // '\n'
            }
        }

        let lineText = lines[targetLineIdx]
        let col0 = max(0, min(lineText.count, column1 - 1))
        offset += col0
        return UInt32(max(0, offset))
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
        let container: NSView
        if tab.panes.count == 1 {
            container = tab.editCore
        } else {
            let splitView = NSSplitView(frame: .zero)
            splitView.isVertical = true
            splitView.dividerStyle = .thin
            for pane in tab.panes {
                pane.translatesAutoresizingMaskIntoConstraints = false
                splitView.addArrangedSubview(pane)
            }
            container = splitView
        }

        container.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),
        ])
    }

    private func configureEditorChrome(_ editCore: EditCoreUI) throws {
        // 保持至少 6 个 cell 的 gutter（折叠标记 + 行号），但仍允许在超大文件时自动扩展。
        editCore.editorView.minimumGutterWidthCells = 6
        try editCore.editor.setWhitespaceRenderMode(.selection)
        try editCore.editor.setIndentGuidesEnabled(true)
        try editCore.editor.setFontLigaturesEnabled(preferences.effectiveLigaturesEnabled)
        editCore.editorView.fontSizePoints = CGFloat(preferences.effectiveFontSizePoints)
        try editCore.applyTheme(theme)
        _ = try editCore.editor.setWrapMode(preferences.effectiveWrapMode)
        _ = try editCore.editor.setWrapIndent(preferences.effectiveWrapIndent)
        try editCore.editor.setAutoPairsEnabled(preferences.effectiveAutoPairsEnabled)
        try editCore.editor.setBracketMatchHighlightsEnabled(true)
    }

    private func applyLanguageConfiguration(for tab: AttoEditorTab) {
        for editCore in tab.panes {
            applyLanguageConfiguration(fileURL: tab.fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: editCore)
        }
    }

    private func applyLanguageConfiguration(fileURL: URL, syntaxLanguageId: String?, to editCore: EditCoreUI) {
        let config = AttoLanguageConfiguration.indentationConfig(fileURL: fileURL, syntaxLanguageId: syntaxLanguageId)
        do {
            _ = try editCore.editor.setIndentationConfig(config)
        } catch {
            NSLog("AttoEditor: setIndentationConfig failed for %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func configureEditCoreHooks(_ editCore: EditCoreUI, tabID: UUID) {
        editCore.onDidMutateDocumentText = { [weak self] in
            self?.handleTabDidMutateDocumentText(tabID: tabID)
        }
        editCore.onDidCommitText = { [weak self] text in
            self?.handleCommittedTextForLspTriggers(text, tabID: tabID)
        }
        editCore.onDidApplyAsyncProcessing = { [weak self] in
            guard let self else { return }
            // Async processing updates (LSP diagnostics/semantic tokens, etc.) can change status
            // bar info even without any user input.
            guard self.activeTab?.id == tabID else { return }
            self.updateStatusBar()
        }
        editCore.onHover = { [weak self] info in
            self?.handleHover(info: info, tabID: tabID)
        }
        editCore.onHoverExit = { [weak self] in
            self?.handleHoverExit(tabID: tabID)
        }
        editCore.editorView.onDidBecomeFirstResponder = { [weak self, weak editCore] in
            guard let self, let editCore else { return }
            self.setActivePane(editCore, tabID: tabID)
        }
        editCore.editorView.onCommandClick = { [weak self] ctx in
            self?.handleCommandClick(ctx: ctx, tabID: tabID) ?? false
        }
        editCore.editorView.onCommandHover = { [weak self] _ in
            guard let self else { return false }
            guard activeTab?.id == tabID else { return false }
            guard let tab = activeTab else { return false }
            // Only show Cmd-hover "clickable" affordance when Cmd-click is expected to resolve via LSP.
            return (try? tab.editCore.editor.lspIsEnabled()) == true
        }
    }

    private func setActivePane(_ editCore: EditCoreUI, tabID: UUID) {
        guard selectedTabID == tabID else { return }
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        guard let idx = tab.panes.firstIndex(where: { $0 === editCore }) else { return }

        tab.activePaneIndex = idx
        attachStatusObserver(to: editCore.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
    }

    // MARK: - Tab creation

    private func makeTab(
        for url: URL,
        isPreview: Bool,
        showsMinimap: Bool = true,
        isUntitled: Bool = false
    ) throws -> AttoEditorTab {
        let initialText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let prefs = AttoPreferences.shared
        let fontFamiliesCSV = prefs.fontFamiliesCSVForNewViews()

        let editCore = try EditCoreUI(
            library: library,
            initialText: initialText,
            viewportWidthCells: 120,
            fontFamiliesCSV: fontFamiliesCSV,
            showsMinimap: showsMinimap,
            minimapPlacement: .rightOfScrollbar
        )

        try configureEditorChrome(editCore)

        // Tree-sitter registry (best-effort).
        loadTreeSitterRegistryCacheIfNeeded()
        if let registryJSON = treeSitterRegistryJSON {
            do {
                try editCore.editor.treeSitterSetRegistryJSON(registryJSON)
            } catch {
                NSLog("AttoEditor: Tree-sitter registry init failed: %@", String(describing: error))
            }
        }

        // Syntax support (best-effort): LSP -> Tree-sitter -> Sublime `.sublime-syntax`.
        let syntaxLanguageId = configureSyntaxSupport(for: url, editCore: editCore)
        applyLanguageConfiguration(fileURL: url, syntaxLanguageId: syntaxLanguageId, to: editCore)

        let tabId = UUID()
        let tab = AttoEditorTab(
            id: tabId,
            fileURL: url,
            isUntitled: isUntitled,
            isPreview: isPreview,
            isDirty: false,
            syntaxLanguageId: syntaxLanguageId,
            editCore: editCore
        )
        configureEditCoreHooks(editCore, tabID: tabId)
        return tab
    }

    // MARK: - Saving helpers

    @discardableResult
    private func saveTabWithSavePanelIfNeeded(_ tab: AttoEditorTab) -> Bool {
        guard tab.isUntitled else {
            return saveTab(tab)
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.message = "Choose where to save this file."
        panel.directoryURL = workspaceRootURL

        let defaultName = tab.fileURL.lastPathComponent.isEmpty ? "untitled.txt" : tab.fileURL.lastPathComponent
        panel.nameFieldStringValue = defaultName

        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else {
            return false
        }

        if tabs.contains(where: { $0.id != tab.id && $0.fileURL.standardizedFileURL == url }) {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "This file is already open."
            alert.informativeText = "Please choose a different name or close the other tab first."
            alert.runModal()
            return false
        }

        let oldURL = tab.fileURL
        tab.fileURL = url
        if saveTab(tab) {
            return true
        }

        // Best-effort rollback if the actual write failed.
        tab.fileURL = oldURL
        refreshTabBar()
        updateWindowTitle()
        updateStatusBar()
        notifySessionStateChanged()
        return false
    }

    private func configureSyntaxSupport(for url: URL, editCore: EditCoreUI) -> String? {
        // Start from a clean slate (best-effort). This avoids stacking style layers when a host
        // switches engines (e.g. LSP becomes available later).
        editCore.editor.lspDisable()
        editCore.editor.treeSitterDisable()
        editCore.editor.sublimeDisable()

        // 1) LSP (configurable by extension).
        let env = ProcessInfo.processInfo.environment
        let disableLSP = env["ATTO_EDITOR_DISABLE_LSP"] == "1"
            || env["EDITOR_CORE_APPKIT_DISABLE_LSP"] == "1"

        if disableLSP == false {
            let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let configured = AttoLspRegistry.loadServerMap()[ext]

            let cmd: String? = {
                if let configured { return configured.command }

                // Backwards-compat: preserve Rust env override + default behavior when no config exists.
                if ext == "rs" {
                    return env["ATTO_EDITOR_LSP_CMD"]
                        ?? env["EDITOR_CORE_APPKIT_LSP_CMD"]
                        ?? "rust-analyzer"
                }

                return nil
            }()

            let args: String? = {
                if let configured { return configured.args }

                // Backwards-compat for Rust-only env args.
                if ext == "rs" {
                    return env["ATTO_EDITOR_LSP_ARGS"]
                        ?? env["EDITOR_CORE_APPKIT_LSP_ARGS"]
                }

                return nil
            }()

            let languageId: String? = {
                if let configured, let lang = configured.languageId { return lang }
                if let inferred = inferredTreeSitterLanguageId(for: url) { return inferred }
                return AttoLspLanguageId.guess(forExtension: ext)
            }()

            if let cmd, let languageId, languageId.isEmpty == false {
                do {
                    try editCore.editor.lspEnable(
                        command: cmd,
                        args: args,
                        rootURI: workspaceRootURL.absoluteString,
                        documentURI: url.absoluteString,
                        languageId: languageId
                    )

                    let supportsSemanticTokens: Bool = {
                        guard let statusJSON = try? editCore.editor.lspStatusJSON() else { return false }
                        guard let data = statusJSON.data(using: .utf8) else { return false }
                        guard let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                            return false
                        }
                        guard let capabilities = obj["capabilities"] as? [String: Any] else { return false }
                        if let v = capabilities["semantic_tokens"] as? Bool { return v }
                        if let v = capabilities["semantic_tokens"] as? NSNumber { return v.boolValue }
                        return false
                    }()

                    if supportsSemanticTokens {
                        // Prefer LSP semantic tokens; keep other engines off.
                        editCore.editor.treeSitterDisable()
                        editCore.editor.sublimeDisable()
                    } else {
                        // LSP without semantic tokens: keep Tree-sitter for baseline highlighting.
                        do {
                            try editCore.editor.treeSitterEnableForPath(url.path)
                            // Kick a short poll window so the initial Tree-sitter parse applies even without edits.
                            editCore.editorView.kickProcessingPoll()
                        } catch {
                            NSLog(
                                "AttoEditor: Tree-sitter enable failed for %@ (fallback after LSP without semantic tokens): %@",
                                url.path,
                                String(describing: error)
                            )
                        }
                        editCore.editor.sublimeDisable()
                    }
                    return languageId
                } catch {
                    NSLog("AttoEditor: LSP enable failed for %@: %@", url.path, String(describing: error))
                }
            }
        }

        // 2) Tree-sitter.
        do {
            try editCore.editor.treeSitterEnableForPath(url.path)
            editCore.editor.sublimeDisable()
            // Kick a short poll window so the initial Tree-sitter parse applies even without edits.
            editCore.editorView.kickProcessingPoll()
            return inferredTreeSitterLanguageId(for: url)
        } catch {
            NSLog("AttoEditor: Tree-sitter enable failed for %@: %@", url.path, String(describing: error))
        }

        // 3) Sublime `.sublime-syntax` (optional fallback).
        guard let syntaxPath = AttoSublimeSyntax.findSyntaxPath(
            for: url,
            workspaceRootURL: workspaceRootURL
        ) else {
            NSLog("AttoEditor: no Sublime syntax found for %@ (ext=%@)", url.path, url.pathExtension)
            return nil
        }

        do {
            try editCore.editor.sublimeSetSyntaxPath(syntaxPath)
            editCore.editor.treeSitterDisable()
            editCore.editorView.needsDisplay = true
            return nil
        } catch {
            NSLog(
                "AttoEditor: Sublime syntax enable failed (path=%@) for %@: %@",
                syntaxPath,
                url.path,
                String(describing: error)
            )
            return nil
        }
    }

    // MARK: - LSP location requests

    private func handleCommandClick(ctx: EditorCoreSkiaContextMenuContext, tabID: UUID) -> Bool {
        guard activeTab?.id == tabID else { return false }
        return requestLspLocation(tabID: tabID, logicalLine: ctx.logicalLine, logicalColumn: ctx.logicalColumn, kind: .definition)
    }

    @discardableResult
    func goToDefinitionInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .definition)
    }

    @discardableResult
    func goToDeclarationInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .declaration)
    }

    @discardableResult
    func goToTypeDefinitionInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .typeDefinition)
    }

    @discardableResult
    func goToImplementationInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .implementation)
    }

    @discardableResult
    func findReferencesInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .references)
    }

    private func requestLspLocationAtPrimaryCaret(kind: LspLocationRequestKind) -> Bool {
        guard let tab = activeTab else { return false }
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return requestLspLocation(
                tabID: tab.id,
                logicalLine: pos.line,
                logicalColumn: pos.column,
                kind: kind
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func requestLspLocation(
        tabID: UUID,
        logicalLine: UInt32,
        logicalColumn: UInt32,
        kind: LspLocationRequestKind
    ) -> Bool {
        guard activeTab?.id == tabID else { return false }
        guard let tab = activeTab else { return false }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelRenameUI()
        cancelCodeActionUI()

        definitionContext = DefinitionRequestContext(
            tabID: tabID,
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            kind: kind
        )
        definitionPollTimer?.cancel()

        do {
            try requestLspLocation(kind: kind, editor: tab.editCore.editor, line: logicalLine, column: logicalColumn)
        } catch {
            cancelDefinitionUI()
            NSSound.beep()
            return false
        }

        startDefinitionPollTimer(tabID: tabID)
        return true
    }

    private func requestLspLocation(kind: LspLocationRequestKind, editor: EditorUI, line: UInt32, column: UInt32) throws {
        switch kind {
        case .definition:
            _ = try editor.lspRequestDefinition(logicalLine: line, logicalColumn: column)
        case .declaration:
            _ = try editor.lspRequestDeclaration(logicalLine: line, logicalColumn: column)
        case .typeDefinition:
            _ = try editor.lspRequestTypeDefinition(logicalLine: line, logicalColumn: column)
        case .implementation:
            _ = try editor.lspRequestImplementation(logicalLine: line, logicalColumn: column)
        case .references:
            _ = try editor.lspRequestReferences(logicalLine: line, logicalColumn: column, includeDeclaration: true)
        }
    }

    private func startDefinitionPollTimer(tabID: UUID) {
        definitionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.definitionContext, ctx.tabID == tabID else {
                self.cancelDefinitionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelDefinitionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelDefinitionUI()
                return
            }

            let json: String?
            do {
                json = try self.takeLspLocationResult(kind: ctx.kind, editor: tab.editCore.editor)
            } catch {
                return
            }
            guard let json else { return }

            self.cancelDefinitionUI()
            self.handleLspLocationResultJSON(json, kind: ctx.kind)
            timer.cancel()
        }

        definitionPollTimer = timer
        timer.resume()
    }

    private func takeLspLocationResult(kind: LspLocationRequestKind, editor: EditorUI) throws -> String? {
        switch kind {
        case .definition:
            try editor.lspTakeLastDefinitionResultJSON()
        case .declaration:
            try editor.lspTakeLastDeclarationResultJSON()
        case .typeDefinition:
            try editor.lspTakeLastTypeDefinitionResultJSON()
        case .implementation:
            try editor.lspTakeLastImplementationResultJSON()
        case .references:
            try editor.lspTakeLastReferencesResultJSON()
        }
    }

    private func handleLspLocationResultJSON(_ json: String, kind: LspLocationRequestKind) {
        let targets = AttoLspDefinitionParser.targets(fromLocationResultJSON: json)
        guard targets.isEmpty == false else {
            NSSound.beep()
            return
        }

        if kind == .references, targets.count > 1 {
            showLspLocationResults(targets)
            return
        }

        navigateToLspTarget(targets[0])
    }

    private func showLspLocationResults(_ targets: [AttoLspDefinitionParser.Target]) {
        guard let window = view.window else {
            navigateToLspTarget(targets[0])
            return
        }

        let commands = targets.enumerated().map { idx, target in
            AttoCommandPaletteCommand(
                id: "lsp.location.\(idx)",
                title: displayTitle(for: target)
            ) { [weak self] in
                self?.navigateToLspTarget(target)
            }
        }

        let controller = AttoCommandPaletteController(commandsProvider: { commands })
        lspLocationResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter LSP results...")
    }

    private func displayTitle(for target: AttoLspDefinitionParser.Target) -> String {
        let location = ":\(target.line + 1):\(target.utf16Character + 1)"
        guard let url = URL(string: target.uri), url.isFileURL else {
            return "\(target.uri)\(location)"
        }

        let standardized = url.standardizedFileURL
        let root = workspaceRootURL.standardizedFileURL.path
        let path = standardized.path
        if path.hasPrefix(root + "/") {
            return "\(String(path.dropFirst(root.count + 1)))\(location)"
        }
        return "\(standardized.lastPathComponent)\(location)"
    }

    private func navigateToLspTarget(_ target: AttoLspDefinitionParser.Target) {
        guard let url = URL(string: target.uri), url.isFileURL else {
            NSSound.beep()
            return
        }

        openFile(url: url, mode: .preview)

        guard let tab = activeTab, tab.fileURL.standardizedFileURL == url.standardizedFileURL else {
            return
        }

        do {
            // Ensure the new editor view has a real viewport height before calling `revealPrimaryCaret`.
            // `EditorUI.revealPrimaryCaret()` is a no-op when viewport height is unknown.
            tab.editCore.layoutSubtreeIfNeeded()
            let text = try tab.editCore.editor.text()
            let offset = AttoLspDefinitionParser.charOffsetForLspPosition(
                inText: text,
                line: target.line,
                utf16Character: target.utf16Character
            )
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: offset, end: offset)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - LSP symbols quick panels

    @discardableResult
    func showDocumentSymbolsInActiveTab() -> Bool {
        requestLspSymbols(kind: .document)
    }

    @discardableResult
    func showWorkspaceSymbolsInActiveTab(query: String = "") -> Bool {
        requestLspSymbols(kind: .workspace(query: query))
    }

    private func requestLspSymbols(kind: LspSymbolRequestKind) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelRenameUI()
        cancelCodeActionUI()

        symbolContext = SymbolRequestContext(tabID: tab.id, kind: kind)

        do {
            switch kind {
            case .document:
                _ = try tab.editCore.editor.lspRequestDocumentSymbols()
            case .workspace(let query):
                _ = try tab.editCore.editor.lspRequestWorkspaceSymbols(query: query)
            }
        } catch {
            cancelSymbolUI()
            NSSound.beep()
            return false
        }

        startSymbolPollTimer(tabID: tab.id)
        return true
    }

    private func startSymbolPollTimer(tabID: UUID) {
        symbolPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.symbolContext, ctx.tabID == tabID else {
                self.cancelSymbolUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelSymbolUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSymbolUI()
                return
            }

            let json: String?
            do {
                switch ctx.kind {
                case .document:
                    json = try tab.editCore.editor.lspTakeLastDocumentSymbolsResultJSON()
                case .workspace:
                    json = try tab.editCore.editor.lspTakeLastWorkspaceSymbolsResultJSON()
                }
            } catch {
                return
            }
            guard let json else { return }

            self.cancelSymbolUI()
            self.handleLspSymbolResultJSON(json, kind: ctx.kind, tab: tab)
            timer.cancel()
        }

        symbolPollTimer = timer
        timer.resume()
    }

    private func handleLspSymbolResultJSON(_ json: String, kind: LspSymbolRequestKind, tab: AttoEditorTab) {
        let symbols: [AttoLspSymbolParser.Symbol]
        let placeholder: String

        switch kind {
        case .document:
            try? tab.editCore.editor.lspApplyDocumentSymbolsJSON(json)
            symbols = AttoLspSymbolParser.documentSymbols(
                fromResultJSON: json,
                documentURI: tab.fileURL.absoluteString
            )
            placeholder = "Filter document symbols..."

        case .workspace:
            symbols = AttoLspSymbolParser.workspaceSymbols(fromResultJSON: json)
            placeholder = "Filter workspace symbols..."
        }

        showLspSymbolResults(symbols, placeholder: placeholder)
    }

    private func showLspSymbolResults(_ symbols: [AttoLspSymbolParser.Symbol], placeholder: String) {
        guard symbols.isEmpty == false else {
            NSSound.beep()
            return
        }

        guard let window = view.window else {
            navigateToLspTarget(symbols[0].target)
            return
        }

        let commands = symbols.enumerated().map { idx, symbol in
            AttoCommandPaletteCommand(
                id: "lsp.symbol.\(idx)",
                title: displayTitle(for: symbol)
            ) { [weak self] in
                self?.navigateToLspTarget(symbol.target)
            }
        }

        let controller = AttoCommandPaletteController(commandsProvider: { commands })
        lspSymbolResultsController = controller
        controller.show(relativeTo: window, placeholder: placeholder)
    }

    private func displayTitle(for symbol: AttoLspSymbolParser.Symbol) -> String {
        let indent = String(repeating: "  ", count: symbol.depth)
        let detail = symbol.detail.map { " \($0)" } ?? ""
        let kind = symbol.kindLabel.map { " [\($0)]" } ?? ""
        let container = symbol.containerName.map { " — \($0)" } ?? ""
        let location = displayTitle(for: symbol.target)
        return "\(indent)\(symbol.name)\(detail)\(kind)\(container) — \(location)"
    }

    // MARK: - LSP completion

    @discardableResult
    func showCompletionsInActiveTab() -> Bool {
        showCompletionsInActiveTab(beepOnFailure: true)
    }

    @discardableResult
    private func showCompletionsInActiveTab(beepOnFailure: Bool) -> Bool {
        guard let tab = activeTab else {
            if beepOnFailure { NSSound.beep() }
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if beepOnFailure { NSSound.beep() }
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let text = try tab.editCore.editor.text()
            let fallback: (start: UInt32, end: UInt32) = {
                let start = min(offsets.start, offsets.end)
                let end = max(offsets.start, offsets.end)
                if start != end {
                    return (start, end)
                }
                return AttoLspCompletionParser.identifierFallbackRange(in: text, caretOffset: offsets.end)
            }()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestCompletion(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )

            completionContext = CompletionRequestContext(
                tabID: tab.id,
                fallbackStart: fallback.start,
                fallbackEnd: fallback.end,
                beepOnFailure: beepOnFailure
            )
            startCompletionPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
            return true
        } catch {
            if beepOnFailure { NSSound.beep() }
            return false
        }
    }

    private func startCompletionPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        completionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.completionContext, ctx.tabID == tabID else {
                self.cancelCompletionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCompletionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCompletionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCompletionResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let items = AttoLspCompletionParser.items(fromCompletionResultJSON: json)
            self.completionPollTimer?.cancel()
            self.completionPollTimer = nil
            self.completionContext = nil
            self.showCompletionList(items: items, context: ctx, editorView: editorView)
            timer.cancel()
        }

        completionPollTimer = timer
        timer.resume()
    }

    private func showCompletionList(
        items: [AttoLspCompletionParser.Item],
        context: CompletionRequestContext,
        editorView: EditorCoreSkiaView
    ) {
        guard items.isEmpty == false else {
            cancelCompletionUI()
            if context.beepOnFailure { NSSound.beep() }
            return
        }
        guard editorView.window != nil else { return }

        let controller = AttoCompletionListController()
        completionListController = controller
        completionListContext = context
        controller.onTextInput = { [weak self, weak controller] text in
            guard let self, self.completionListController === controller else { return false }
            return self.handleCompletionFilterTextInput(text, tabID: context.tabID)
        }
        controller.onDeleteBackward = { [weak self, weak controller] in
            guard let self, self.completionListController === controller else { return false }
            return self.handleCompletionFilterDeleteBackward(tabID: context.tabID)
        }
        controller.onDismiss = { [weak self, weak controller] in
            guard let self, self.completionListController === controller else { return }
            self.completionListController = nil
            self.completionListContext = nil
        }
        controller.show(
            items: items,
            relativeTo: editorView,
            anchorRect: caretAnchorRect(in: editorView)
        ) { [weak self] item, commitCharacter in
            self?.applyCompletion(item, context: context, commitCharacter: commitCharacter)
        }
    }

    @discardableResult
    private func handleCompletionFilterTextInput(_ text: String, tabID: UUID) -> Bool {
        guard let tab = activeTab, tab.id == tabID else { return false }
        guard completionListController != nil else { return false }

        shouldPreserveCompletionUIForCurrentTextMutation = true
        defer { shouldPreserveCompletionUIForCurrentTextMutation = false }
        tab.editCore.editorView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        refreshCompletionFilter(tabID: tabID)
        return true
    }

    @discardableResult
    private func handleCompletionFilterDeleteBackward(tabID: UUID) -> Bool {
        guard let tab = activeTab, tab.id == tabID else { return false }
        guard completionListController != nil else { return false }

        shouldPreserveCompletionUIForCurrentTextMutation = true
        defer { shouldPreserveCompletionUIForCurrentTextMutation = false }
        tab.editCore.editorView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        refreshCompletionFilter(tabID: tabID)
        return true
    }

    private func refreshCompletionFilter(tabID: UUID) {
        guard let tab = activeTab, tab.id == tabID,
              let context = completionListContext,
              let controller = completionListController
        else {
            return
        }

        guard let prefix = completionFilterPrefix(context: context, editor: tab.editCore.editor) else {
            cancelCompletionUI()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return
        }

        if controller.updateFilter(
            prefix: prefix,
            relativeTo: tab.editCore.editorView,
            anchorRect: caretAnchorRect(in: tab.editCore.editorView)
        ) == false {
            view.window?.makeFirstResponder(tab.editCore.editorView)
        }
    }

    private func completionFilterPrefix(context: CompletionRequestContext, editor: EditorUI) -> String? {
        guard let offsets = try? editor.selectionOffsets() else { return nil }
        guard offsets.start == offsets.end else { return nil }
        guard offsets.end >= context.fallbackStart else { return nil }
        guard let text = try? editor.text() else { return nil }
        return AttoLspCompletionParser.completionPrefix(
            in: text,
            start: context.fallbackStart,
            caretOffset: offsets.end
        )
    }

    private func applyCompletion(
        _ item: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String? = nil
    ) {
        guard let tab = activeTab, tab.id == context.tabID else { return }

        guard completionItemResolveSupported(for: tab.editCore.editor) else {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
            return
        }

        guard let itemJSON = AttoLspCompletionParser.rawJSON(for: item) else {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
            return
        }

        do {
            _ = try tab.editCore.editor.lspRequestCompletionItemResolve(itemJSON: itemJSON)
            completionResolveContext = CompletionResolveContext(
                request: context,
                item: item,
                commitCharacter: commitCharacter
            )
            completionListController?.hide()
            completionListController = nil
            startCompletionResolvePollTimer(tabID: tab.id)
        } catch {
            _ = applyCompletionItem(item, context: context, commitCharacter: commitCharacter)
        }
    }

    private func completionItemResolveSupported(for editor: EditorUI) -> Bool {
        guard let json = try? editor.lspStatusJSON(),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let capabilities = root["capabilities"] as? [String: Any],
              let value = capabilities["completion_item_resolve"]
        else {
            return true
        }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return true
    }

    private func startCompletionResolvePollTimer(tabID: UUID) {
        completionResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.completionResolveContext, ctx.request.tabID == tabID else {
                self.cancelCompletionUI()
                return
            }

            if remainingTicks <= 0 {
                self.finishCompletionResolve(
                    with: ctx.item,
                    fallback: ctx.item,
                    context: ctx.request,
                    commitCharacter: ctx.commitCharacter,
                    timer: timer
                )
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCompletionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCompletionItemResolveResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let resolved = AttoLspCompletionParser.item(fromCompletionItemJSON: json) ?? ctx.item
            self.finishCompletionResolve(
                with: resolved,
                fallback: ctx.item,
                context: ctx.request,
                commitCharacter: ctx.commitCharacter,
                timer: timer
            )
        }

        completionResolvePollTimer = timer
        timer.resume()
    }

    private func finishCompletionResolve(
        with item: AttoLspCompletionParser.Item,
        fallback: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String?,
        timer: DispatchSourceTimer
    ) {
        completionResolvePollTimer = nil
        completionResolveContext = nil
        timer.cancel()

        if applyCompletionItem(
            item,
            context: context,
            commitCharacter: commitCharacter,
            beepOnFailure: false
        ) == false {
            _ = applyCompletionItem(
                fallback,
                context: context,
                commitCharacter: commitCharacter,
                beepOnFailure: true
            )
        }
    }

    @discardableResult
    private func applyCompletionItem(
        _ item: AttoLspCompletionParser.Item,
        context: CompletionRequestContext,
        commitCharacter: String? = nil,
        beepOnFailure: Bool = true
    ) -> Bool {
        guard let tab = activeTab, tab.id == context.tabID else { return false }

        do {
            let text = try tab.editCore.editor.text()
            guard let plan = AttoLspCompletionParser.applicationPlan(
                for: item,
                documentText: text,
                fallbackStart: context.fallbackStart,
                fallbackEnd: context.fallbackEnd
            ) else {
                if beepOnFailure {
                    NSSound.beep()
                }
                return false
            }

            if plan.isSnippet {
                _ = try tab.editCore.editor.applySnippet(
                    start: plan.start,
                    end: plan.end,
                    snippet: plan.text,
                    additionalEdits: plan.additionalEdits
                )
            } else {
                let edits = [EcuTextEdit(start: plan.start, end: plan.end, text: plan.text)] + plan.additionalEdits
                _ = try tab.editCore.editor.applyTextEdits(edits)
            }
            var didCommitCharacter = false
            if let commitCharacter {
                do {
                    try tab.editCore.editor.commitText(commitCharacter)
                    didCommitCharacter = true
                } catch {
                    if beepOnFailure {
                        NSSound.beep()
                    }
                }
            }

            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            if let commitCharacter, didCommitCharacter {
                handleCommittedTextForLspTriggers(commitCharacter, tabID: tab.id)
            }
            updateStatusBar()
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            if beepOnFailure {
                NSSound.beep()
            }
            return false
        }
    }

    // MARK: - LSP code actions

    @discardableResult
    func showCodeActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: [])
    }

    @discardableResult
    func showQuickFixesInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["quickfix"])
    }

    @discardableResult
    func showRefactorActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["refactor"])
    }

    @discardableResult
    func showSourceActionsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source"])
    }

    @discardableResult
    func organizeImportsInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source.organizeImports"])
    }

    @discardableResult
    func fixAllInActiveTab() -> Bool {
        showCodeActionsInActiveTab(onlyKinds: ["source.fixAll"])
    }

    @discardableResult
    private func showCodeActionsInActiveTab(onlyKinds: [String]) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let start = min(offsets.start, offsets.end)
            let end = max(offsets.start, offsets.end)
            let contextJSON = codeActionContextJSON(
                editor: tab.editCore.editor,
                startOffset: start,
                endOffset: end,
                onlyKinds: onlyKinds
            )
            _ = try tab.editCore.editor.lspRequestCodeAction(
                startOffset: start,
                endOffset: end,
                contextJSON: contextJSON
            )
            codeActionContext = CodeActionRequestContext(tabID: tab.id, onlyKinds: onlyKinds)
            startCodeActionPollTimer(tabID: tab.id)
            return true
        } catch {
            cancelCodeActionUI()
            NSSound.beep()
            return false
        }
    }

    private func codeActionContextJSON(
        editor: EditorUI,
        startOffset: UInt32,
        endOffset: UInt32,
        onlyKinds: [String]
    ) -> String {
        let diagnosticsJSON = (try? editor.diagnosticsJSON()) ?? #"{"diagnostics":[]}"#
        let text = (try? editor.text()) ?? ""
        return AttoLspCodeActionContext.contextJSON(
            diagnosticsJSON: diagnosticsJSON,
            documentText: text,
            selectionStart: startOffset,
            selectionEnd: endOffset,
            onlyKinds: onlyKinds
        )
    }

    private func startCodeActionPollTimer(tabID: UUID) {
        codeActionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.codeActionContext, ctx.tabID == tabID else {
                self.cancelCodeActionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCodeActionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeActionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCodeActionResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let items = AttoLspCodeActionParser.filteredItems(
                AttoLspCodeActionParser.items(fromCodeActionResultJSON: json),
                onlyKinds: ctx.onlyKinds
            )
            self.codeActionPollTimer?.cancel()
            self.codeActionPollTimer = nil
            self.codeActionContext = nil
            self.showCodeActionResults(items)
            timer.cancel()
        }

        codeActionPollTimer = timer
        timer.resume()
    }

    private func showCodeActionResults(_ items: [AttoLspCodeActionParser.Item]) {
        guard items.isEmpty == false else {
            cancelCodeActionUI()
            NSSound.beep()
            return
        }

        guard let window = view.window else {
            _ = applyCodeAction(items[0])
            return
        }

        let commands = items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.code_action.\(idx)",
                title: AttoLspCodeActionParser.displayTitle(for: item)
            ) { [weak self] in
                _ = self?.applyCodeAction(item)
            }
        }

        let controller = AttoCommandPaletteController(commandsProvider: { commands })
        codeActionResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter code actions...")
    }

    @discardableResult
    private func applyCodeAction(_ item: AttoLspCodeActionParser.Item, allowResolve: Bool = true) -> Bool {
        guard item.disabledReason == nil else {
            NSSound.beep()
            return false
        }

        var didApply = false
        if let editJSON = AttoLspCodeActionParser.editJSON(for: item) {
            didApply = applyWorkspaceEditJSONToActiveTab(editJSON) || didApply
        }

        if let command = item.command {
            didApply = requestExecuteCodeActionCommand(command) || didApply
        }

        if didApply {
            return true
        }

        guard allowResolve, item.isLegacyCommand == false else {
            NSSound.beep()
            return false
        }
        return requestCodeActionResolve(item)
    }

    private func requestCodeActionResolve(_ item: AttoLspCodeActionParser.Item) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let actionJSON = AttoLspCodeActionParser.rawJSON(for: item) else {
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestCodeActionResolve(actionJSON: actionJSON)
            codeActionResolveContext = CodeActionResolveContext(tabID: tab.id, item: item)
            codeActionResultsController?.hide()
            codeActionResultsController = nil
            startCodeActionResolvePollTimer(tabID: tab.id)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func startCodeActionResolvePollTimer(tabID: UUID) {
        codeActionResolvePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.codeActionResolveContext, ctx.tabID == tabID else {
                self.cancelCodeActionUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelCodeActionUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelCodeActionUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastCodeActionResolveResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            self.codeActionResolvePollTimer?.cancel()
            self.codeActionResolvePollTimer = nil
            self.codeActionResolveContext = nil
            let resolved = AttoLspCodeActionParser.item(fromCodeActionJSON: json) ?? ctx.item
            _ = self.applyCodeAction(resolved, allowResolve: false)
            timer.cancel()
        }

        codeActionResolvePollTimer = timer
        timer.resume()
    }

    private func requestExecuteCodeActionCommand(_ command: AttoLspCodeActionParser.Command) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard let commandJSON = AttoLspCodeActionParser.commandJSON(for: command) else {
            NSSound.beep()
            return false
        }

        do {
            _ = try tab.editCore.editor.lspRequestExecuteCommand(commandJSON: commandJSON)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    // MARK: - LSP rename

    @discardableResult
    func promptRenameSymbolInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        let fallbackSeed = renameDialogSeedInActiveTab()
        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestPrepareRename(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )
            renamePrepareContext = RenamePrepareContext(tabID: tab.id, fallbackSeed: fallbackSeed)
            startRenamePreparePollTimer(tabID: tab.id)
            return true
        } catch {
            return showRenameDialog(seed: fallbackSeed)
        }
    }

    @discardableResult
    private func showRenameDialog(seed: AttoLspRenameSupport.DialogSeed) -> Bool {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = seed.initialName
        field.placeholderString = seed.placeholder ?? "New symbol name"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rename Symbol"
        alert.informativeText = "Enter the new name for the symbol."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return renameSymbolInActiveTab(to: newName)
    }

    @discardableResult
    func renameSymbolInActiveTab(to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestRename(
                logicalLine: pos.line,
                logicalColumn: pos.column,
                newName: trimmed
            )
            renameContext = RenameRequestContext(tabID: tab.id, documentURI: tab.fileURL.absoluteString)
            startRenamePollTimer(tabID: tab.id)
            return true
        } catch {
            cancelRenameUI()
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    func applyWorkspaceEditJSONToActiveTab(_ workspaceEditJSON: String, documentURI: String? = nil) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        do {
            let targetURI = documentURI ?? tab.fileURL.absoluteString
            let resultJSON = try tab.editCore.editor.lspApplyWorkspaceEditJSON(
                workspaceEditJSON,
                documentURI: targetURI
            )
            let result = AttoWorkspaceEditApplyResult(json: resultJSON)
            guard result.applied else {
                showWorkspaceEditSummaryIfNeeded(result, editorView: tab.editCore.editorView)
                if result.skippedURIs.isEmpty == false {
                    NSLog(
                        "AttoEditor: WorkspaceEdit did not target active document; skipped URIs: %@",
                        result.skippedURIs.joined(separator: ", ")
                    )
                }
                NSSound.beep()
                return false
            }

            if result.skippedURIs.isEmpty == false {
                NSLog(
                    "AttoEditor: WorkspaceEdit applied active document and skipped unsupported cross-file URIs: %@",
                    result.skippedURIs.joined(separator: ", ")
                )
            }

            tab.editCore.layoutSubtreeIfNeeded()
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.editorView.kickProcessingPoll()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidMutateDocumentText(tabID: tab.id)
            updateStatusBar()
            showWorkspaceEditSummaryIfNeeded(result, editorView: tab.editCore.editorView)
            view.window?.makeFirstResponder(tab.editCore.editorView)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func showWorkspaceEditSummaryIfNeeded(
        _ result: AttoWorkspaceEditApplyResult,
        editorView: EditorCoreSkiaView
    ) {
        guard let text = AttoWorkspaceEditApplyResult.displayText(for: result) else { return }
        showWorkspaceEditPopover(text: text, in: editorView)
    }

    private func startRenamePreparePollTimer(tabID: UUID) {
        renamePreparePollTimer?.cancel()

        var remainingTicks = 20 // ~1s at 50ms; fall back to local identifier if no prepare result arrives.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.renamePrepareContext, ctx.tabID == tabID else {
                self.cancelRenamePrepareUI()
                return
            }

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelRenamePrepareUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastPrepareRenameResultJSON()
            } catch {
                return
            }

            if let json {
                self.cancelRenamePrepareUI()
                let seed = self.renameDialogSeedInActiveTab(
                    prepareRenameResultJSON: json,
                    fallback: ctx.fallbackSeed
                )
                _ = self.showRenameDialog(seed: seed)
                timer.cancel()
                return
            }

            if remainingTicks <= 0 {
                self.cancelRenamePrepareUI()
                _ = self.showRenameDialog(seed: ctx.fallbackSeed)
                timer.cancel()
                return
            }
            remainingTicks -= 1
        }

        renamePreparePollTimer = timer
        timer.resume()
    }

    private func startRenamePollTimer(tabID: UUID) {
        renamePollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.renameContext, ctx.tabID == tabID else {
                self.cancelRenameUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelRenameUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelRenameUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastRenameResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            self.renamePollTimer?.cancel()
            self.renamePollTimer = nil
            self.renameContext = nil
            _ = self.applyWorkspaceEditJSONToActiveTab(json, documentURI: ctx.documentURI)
            timer.cancel()
        }

        renamePollTimer = timer
        timer.resume()
    }

    private func renameDialogSeedInActiveTab(
        prepareRenameResultJSON: String? = nil,
        fallback fallbackSeed: AttoLspRenameSupport.DialogSeed? = nil
    ) -> AttoLspRenameSupport.DialogSeed {
        guard let tab = activeTab else {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
        do {
            let selected = try tab.editCore.editor.selectedText()
            let offsets = try tab.editCore.editor.selectionOffsets()
            let text = try tab.editCore.editor.text()
            let fallback = fallbackSeed ?? AttoLspRenameSupport.DialogSeed(
                initialName: AttoLspRenameSupport.candidateName(
                    documentText: text,
                    selectedText: selected,
                    caretOffset: offsets.end
                ),
                placeholder: nil
            )
            return AttoLspRenameSupport.dialogSeed(
                documentText: text,
                selectedText: selected,
                caretOffset: offsets.end,
                prepareRenameResultJSON: prepareRenameResultJSON,
                fallback: fallback
            )
        } catch {
            return fallbackSeed ?? AttoLspRenameSupport.DialogSeed(initialName: "", placeholder: nil)
        }
    }

    // MARK: - LSP signature help

    private func handleCommittedTextForLspTriggers(_ text: String, tabID: UUID) {
        guard let tab = activeTab, tab.id == tabID else { return }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        guard let status = try? tab.editCore.editor.lspStatusJSON() else { return }
        let shouldShowSignatureHelp = AttoLspSignatureHelpTrigger.shouldTrigger(
            committedText: text,
            lspStatusJSON: status
        )

        if AttoLspCompletionTrigger.shouldTrigger(
            committedText: text,
            lspStatusJSON: status
        ), shouldShowSignatureHelp == false {
            _ = showCompletionsInActiveTab(beepOnFailure: false)
        }

        if shouldShowSignatureHelp {
            _ = showSignatureHelpInActiveTab(beepOnFailure: false, showEmptyResults: false)
        }
    }

    @discardableResult
    func showSignatureHelpInActiveTab() -> Bool {
        showSignatureHelpInActiveTab(beepOnFailure: true, showEmptyResults: true)
    }

    @discardableResult
    private func showSignatureHelpInActiveTab(beepOnFailure: Bool, showEmptyResults: Bool) -> Bool {
        guard let tab = activeTab else {
            if beepOnFailure { NSSound.beep() }
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showEmptyResults {
                showSignatureHelpPopover(
                    display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help is unavailable.\nLSP is not enabled for this document."),
                    in: tab.editCore.editorView
                )
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelRenameUI()
        cancelCodeActionUI()

        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            _ = try tab.editCore.editor.lspRequestSignatureHelp(
                logicalLine: pos.line,
                logicalColumn: pos.column
            )
        } catch {
            if showEmptyResults {
                showSignatureHelpPopover(
                    display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help request failed.\n\(error.localizedDescription)"),
                    in: tab.editCore.editorView
                )
            }
            if beepOnFailure { NSSound.beep() }
            return false
        }

        signatureHelpContext = SignatureHelpRequestContext(
            tabID: tab.id,
            showEmptyResults: showEmptyResults
        )
        startSignatureHelpPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    private func startSignatureHelpPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        signatureHelpPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.signatureHelpContext, ctx.tabID == tabID else {
                self.cancelSignatureHelpUI()
                return
            }

            if remainingTicks <= 0 {
                let showEmptyResults = ctx.showEmptyResults
                self.cancelSignatureHelpUI()
                if showEmptyResults {
                    self.showSignatureHelpPopover(
                        display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help timed out."),
                        in: editorView
                    )
                }
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelSignatureHelpUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastSignatureHelpResultJSON()
            } catch {
                let showEmptyResults = ctx.showEmptyResults
                self.cancelSignatureHelpUI()
                if showEmptyResults {
                    self.showSignatureHelpPopover(
                        display: AttoLspSignatureHelpFormatter.messageDisplay("Signature help failed.\n\(error.localizedDescription)"),
                        in: editorView
                    )
                }
                timer.cancel()
                return
            }
            guard let json else { return }

            let display = AttoLspSignatureHelpFormatter.display(fromSignatureHelpResultJSON: json)
                ?? (ctx.showEmptyResults ? AttoLspSignatureHelpFormatter.messageDisplay("No signature help is available here.") : nil)
            self.cancelSignatureHelpUI()
            self.showSignatureHelpPopover(display: display, in: editorView)
            timer.cancel()
        }

        signatureHelpPollTimer = timer
        timer.resume()
    }

    private func showSignatureHelpPopover(display: AttoLspSignatureHelpFormatter.Display?, in editorView: EditorCoreSkiaView) {
        guard let display else {
            cancelSignatureHelpUI()
            return
        }

        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = signatureHelpPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            signatureHelpPopover = p
            signatureHelpPopoverLabel = label
            popover = p
        }

        signatureHelpPopoverLabel?.attributedStringValue = attributedSignatureHelp(display)
        popover.contentSize = preferredHoverPopoverSize(text: display.text, font: signatureHelpPopoverLabel?.font)

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: caretAnchorRect(in: editorView), of: editorView, preferredEdge: .maxY)
    }

    private func attributedSignatureHelp(_ display: AttoLspSignatureHelpFormatter.Display) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let activeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let attributed = NSMutableAttributedString(
            string: display.text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let fullRange = NSRange(location: 0, length: (display.text as NSString).length)
        let highlightColor = NSColor.controlAccentColor.withAlphaComponent(0.24)

        for range in display.activeParameterRanges where NSIntersectionRange(range, fullRange).length == range.length {
            attributed.addAttributes(
                [
                    .font: activeFont,
                    .foregroundColor: NSColor.controlAccentColor,
                    .backgroundColor: highlightColor,
                ],
                range: range
            )
        }
        return attributed
    }

    private func caretAnchorRect(in editorView: EditorCoreSkiaView) -> NSRect {
        do {
            let offsets = try editorView.editor.selectionOffsets()
            let pt = try editorView.editor.charOffsetToViewPoint(offset: offsets.end)

            let boundsSize = editorView.bounds.size
            let backingSize = editorView.convertToBacking(boundsSize)
            let sx = boundsSize.width > 0 ? (backingSize.width / boundsSize.width) : 1
            let sy = boundsSize.height > 0 ? (backingSize.height / boundsSize.height) : 1

            let xPt = CGFloat(pt.xPx) / max(1e-6, sx)
            let yPt = CGFloat(pt.yPx) / max(1e-6, sy)
            let hPt = max(1, CGFloat(pt.lineHeightPx) / max(1e-6, sy))
            return NSRect(x: xPt, y: yPt, width: 1, height: hPt)
        } catch {
            return NSRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    // MARK: - LSP hover tooltip (AttoEditor UX)

    private func handleHover(info: EditorCoreSkiaHoverInfo, tabID: UUID) {
        guard activeTab?.id == tabID else { return }
        guard let tab = activeTab else { return }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            cancelHoverUI()
            return
        }

        hoverContext = HoverRequestContext(tabID: tabID, info: info)
        hoverDebounceWorkItem?.cancel()
        hoverPollTimer?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.requestHoverForCurrentContext()
        }
        hoverDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func handleHoverExit(tabID: UUID) {
        guard hoverContext?.tabID == tabID else { return }
        cancelHoverUI()
    }

    private func requestHoverForCurrentContext() {
        guard let ctx = hoverContext else { return }
        guard activeTab?.id == ctx.tabID else { return }
        guard let tab = activeTab else { return }

        do {
            _ = try tab.editCore.editor.lspRequestHover(
                logicalLine: ctx.info.logicalLine,
                logicalColumn: ctx.info.logicalColumn
            )
        } catch {
            return
        }

        startHoverPollTimer(tabID: ctx.tabID, editorView: tab.editCore.editorView)
    }

    private func startHoverPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        hoverPollTimer?.cancel()

        var remainingTicks = 30 // ~1.5s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self, weak editorView] in
            guard let self, let editorView else { return }
            guard let ctx = self.hoverContext, ctx.tabID == tabID else {
                self.cancelHoverUI()
                return
            }

            if remainingTicks <= 0 {
                self.cancelHoverUI()
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelHoverUI()
                return
            }

            let json: String?
            do {
                json = try tab.editCore.editor.lspTakeLastHoverResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            let text = AttoLspHoverFormatter.displayText(fromHoverResultJSON: json)
            self.showHoverPopover(text: text, at: ctx.info, in: editorView)
            timer.cancel()
        }

        hoverPollTimer = timer
        timer.resume()
    }

    private func showHoverPopover(text: String?, at info: EditorCoreSkiaHoverInfo, in editorView: EditorCoreSkiaView) {
        guard let text else {
            cancelHoverUI()
            return
        }

        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = hoverPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            hoverPopover = p
            hoverPopoverLabel = label
            popover = p
        }

        hoverPopoverLabel?.stringValue = text
        popover.contentSize = preferredHoverPopoverSize(text: text, font: hoverPopoverLabel?.font)

        let rect = NSRect(x: info.viewPoint.x, y: info.viewPoint.y, width: 1, height: 1)
        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: rect, of: editorView, preferredEdge: .maxY)
    }

    private func showWorkspaceEditPopover(text: String, in editorView: EditorCoreSkiaView) {
        guard editorView.window != nil else { return }

        let popover: NSPopover
        if let existing = workspaceEditPopover {
            popover = existing
        } else {
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true

            let vc = NSViewController()
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.labelColor
            label.translatesAutoresizingMaskIntoConstraints = false

            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            ])

            vc.view = effect
            p.contentViewController = vc
            workspaceEditPopover = p
            workspaceEditPopoverLabel = label
            popover = p
        }

        workspaceEditPopoverLabel?.stringValue = text
        popover.contentSize = preferredHoverPopoverSize(text: text, font: workspaceEditPopoverLabel?.font)

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: caretAnchorRect(in: editorView), of: editorView, preferredEdge: .maxY)
    }

    private func preferredHoverPopoverSize(text: String, font: NSFont?) -> NSSize {
        let maxWidth: CGFloat = 420
        let maxHeight: CGFloat = 260
        let padW: CGFloat = 20
        let padH: CGFloat = 16

        let f = font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: max(1, maxWidth - padW), height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let h = min(maxHeight, ceil(bounds.height) + padH)
        return NSSize(width: maxWidth, height: max(44, h))
    }

    private func cancelHoverUI() {
        hoverDebounceWorkItem?.cancel()
        hoverDebounceWorkItem = nil

        hoverPollTimer?.cancel()
        hoverPollTimer = nil

        hoverContext = nil

        hoverPopover?.performClose(nil)
    }

    private func cancelDefinitionUI() {
        definitionPollTimer?.cancel()
        definitionPollTimer = nil
        definitionContext = nil
        lspLocationResultsController?.hide()
        lspLocationResultsController = nil
    }

    private func cancelSymbolUI() {
        symbolPollTimer?.cancel()
        symbolPollTimer = nil
        symbolContext = nil
        lspSymbolResultsController?.hide()
        lspSymbolResultsController = nil
    }

    private func cancelSignatureHelpUI() {
        signatureHelpPollTimer?.cancel()
        signatureHelpPollTimer = nil
        signatureHelpContext = nil
        signatureHelpPopover?.performClose(nil)
    }

    private func cancelCompletionUI() {
        completionPollTimer?.cancel()
        completionPollTimer = nil
        completionContext = nil

        completionResolvePollTimer?.cancel()
        completionResolvePollTimer = nil
        completionResolveContext = nil

        completionListController?.hide()
        completionListController = nil
        completionListContext = nil
    }

    private func cancelRenameUI() {
        cancelRenamePrepareUI()
        renamePollTimer?.cancel()
        renamePollTimer = nil
        renameContext = nil
    }

    private func cancelRenamePrepareUI() {
        renamePreparePollTimer?.cancel()
        renamePreparePollTimer = nil
        renamePrepareContext = nil
    }

    private func cancelCodeActionUI() {
        codeActionPollTimer?.cancel()
        codeActionPollTimer = nil
        codeActionContext = nil

        codeActionResolvePollTimer?.cancel()
        codeActionResolvePollTimer = nil
        codeActionResolveContext = nil

        codeActionResultsController?.hide()
        codeActionResultsController = nil
    }
}

enum AttoLspRenameSupport {
    struct DialogSeed: Equatable {
        let initialName: String
        let placeholder: String?
    }

    static func candidateName(documentText: String, selectedText: String, caretOffset: UInt32) -> String {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selected.isEmpty == false, selected.rangeOfCharacter(from: .newlines) == nil {
            return selected
        }

        let chars = Array(documentText)
        guard chars.isEmpty == false else { return "" }

        let rawIndex = max(0, min(Int(caretOffset), chars.count))
        var probe = rawIndex
        if probe >= chars.count || isIdentifierCharacter(chars[probe]) == false {
            probe = max(0, probe - 1)
        }
        guard probe < chars.count, isIdentifierCharacter(chars[probe]) else {
            return ""
        }

        var start = probe
        while start > 0, isIdentifierCharacter(chars[start - 1]) {
            start -= 1
        }

        var end = probe + 1
        while end < chars.count, isIdentifierCharacter(chars[end]) {
            end += 1
        }

        return String(chars[start..<end])
    }

    static func dialogSeed(
        documentText: String,
        selectedText: String,
        caretOffset: UInt32,
        prepareRenameResultJSON: String?,
        fallback: DialogSeed? = nil
    ) -> DialogSeed {
        let fallback = fallback ?? DialogSeed(
            initialName: candidateName(
                documentText: documentText,
                selectedText: selectedText,
                caretOffset: caretOffset
            ),
            placeholder: nil
        )

        guard let prepareRenameResultJSON,
              let data = prepareRenameResultJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return fallback
        }

        if value is NSNull {
            return fallback
        }

        guard let obj = value as? [String: Any] else {
            return fallback
        }

        if boolValue(obj["defaultBehavior"]) == true {
            return fallback
        }

        if let range = obj["range"] as? [String: Any] {
            let placeholder = stringValue(obj["placeholder"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rangeName = text(inLspRange: range, documentText: documentText)
            let initial = nonEmpty(placeholder) ?? nonEmpty(rangeName) ?? fallback.initialName
            return DialogSeed(initialName: initial, placeholder: nonEmpty(placeholder))
        }

        if isLspRangeObject(obj) {
            let initial = nonEmpty(text(inLspRange: obj, documentText: documentText)) ?? fallback.initialName
            return DialogSeed(initialName: initial, placeholder: fallback.placeholder)
        }

        return fallback
    }

    private static func isIdentifierCharacter(_ ch: Character) -> Bool {
        if ch == "_" { return true }
        return ch.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isLspRangeObject(_ obj: [String: Any]) -> Bool {
        obj["start"] is [String: Any] && obj["end"] is [String: Any]
    }

    private static func text(inLspRange range: [String: Any], documentText: String) -> String? {
        guard let start = range["start"] as? [String: Any],
              let end = range["end"] as? [String: Any]
        else {
            return nil
        }

        let lines = documentText.split(separator: "\n", omittingEmptySubsequences: false)
        guard let startOffset = scalarOffset(forLspPosition: start, lines: lines),
              let endOffset = scalarOffset(forLspPosition: end, lines: lines),
              startOffset <= endOffset,
              endOffset <= documentText.unicodeScalars.count
        else {
            return nil
        }

        let scalars = documentText.unicodeScalars
        let startIndex = scalars.index(scalars.startIndex, offsetBy: startOffset)
        let endIndex = scalars.index(scalars.startIndex, offsetBy: endOffset)
        return String(scalars[startIndex..<endIndex])
    }

    private static func scalarOffset(
        forLspPosition position: [String: Any],
        lines: [String.SubSequence]
    ) -> Int? {
        guard let lineNumber = intValue(position["line"]),
              let utf16Column = intValue(position["character"]),
              lineNumber >= 0,
              utf16Column >= 0,
              lineNumber < lines.count
        else {
            return nil
        }

        let preceding = lines.prefix(lineNumber).reduce(0) { total, line in
            total + line.unicodeScalars.count + 1
        }
        return preceding + scalarOffset(fromUTF16Offset: utf16Column, in: lines[lineNumber])
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func scalarOffset(fromUTF16Offset targetUtf16Offset: Int, in line: String.SubSequence) -> Int {
        let target = max(0, min(targetUtf16Offset, line.utf16.count))
        var scalarCursor = 0
        var utf16Cursor = 0

        for scalar in line.unicodeScalars {
            let unitCount = scalar.value <= 0xFFFF ? 1 : 2
            if utf16Cursor + unitCount > target {
                return scalarCursor
            }
            utf16Cursor += unitCount
            scalarCursor += 1
        }

        return scalarCursor
    }
}

private enum AttoLspLanguageId {
    static func guess(forExtension ext: String) -> String? {
        let k = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard k.isEmpty == false else { return nil }

        switch k {
        case "rs": return "rust"
        case "swift": return "swift"
        case "py": return "python"
        case "js": return "javascript"
        case "jsx": return "javascriptreact"
        case "ts": return "typescript"
        case "tsx": return "typescriptreact"
        case "go": return "go"
        case "c": return "c"
        case "h": return "c"
        case "cpp", "cxx", "cc", "hpp", "hxx", "hh": return "cpp"
        case "m": return "objective-c"
        case "mm": return "objective-cpp"
        case "json": return "json"
        case "toml": return "toml"
        case "yaml", "yml": return "yaml"
        case "md", "markdown": return "markdown"
        default:
            return nil
        }
    }
}

private enum AttoLanguageConfiguration {
    static func indentationConfig(fileURL: URL, syntaxLanguageId: String?) -> EcuIndentationConfig {
        let language = languageKey(fileURL: fileURL, syntaxLanguageId: syntaxLanguageId)
        return EcuIndentationConfig(
            style: indentStyle(for: language),
            indentTriggers: indentTriggers(for: language),
            outdentTriggers: outdentTriggers(for: language)
        )
    }

    static func lineCommentToken(fileURL: URL, syntaxLanguageId: String?) -> String {
        let language = languageKey(fileURL: fileURL, syntaxLanguageId: syntaxLanguageId)
        switch language {
        case "python", "ruby", "shell", "bash", "sh", "zsh", "toml", "yaml", "makefile", "make":
            return "#"
        case "lua", "sql", "haskell":
            return "--"
        case "lisp", "clojure", "scheme":
            return ";"
        default:
            return "//"
        }
    }

    private static func languageKey(fileURL: URL, syntaxLanguageId: String?) -> String {
        if let syntaxLanguageId {
            let language = syntaxLanguageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if language.isEmpty == false {
                return normalizeLanguageAlias(language)
            }
        }

        let ext = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let guessed = AttoLspLanguageId.guess(forExtension: ext) {
            return normalizeLanguageAlias(guessed.lowercased())
        }
        return normalizeLanguageAlias(ext)
    }

    private static func normalizeLanguageAlias(_ raw: String) -> String {
        switch raw {
        case "py":
            return "python"
        case "rb":
            return "ruby"
        case "js":
            return "javascript"
        case "jsx":
            return "javascriptreact"
        case "ts":
            return "typescript"
        case "tsx":
            return "typescriptreact"
        case "yml":
            return "yaml"
        case "sh":
            return "shell"
        case "zsh":
            return "shell"
        case "bash":
            return "shell"
        case "clj":
            return "clojure"
        case "scm":
            return "scheme"
        case "mk", "make":
            return "makefile"
        default:
            return raw
        }
    }

    private static func indentStyle(for language: String) -> EcuIndentStyle {
        switch language {
        case "go", "makefile":
            return .tabs
        case "javascript", "javascriptreact", "typescript", "typescriptreact",
             "json", "jsonc", "yaml", "html", "css", "scss", "sass", "vue":
            return .spaces(width: 2)
        default:
            return .spaces(width: 4)
        }
    }

    private static func indentTriggers(for language: String) -> [String] {
        switch language {
        case "python", "ruby", "yaml":
            return [":"]
        case "toml", "markdown", "makefile":
            return []
        default:
            return ["{", "[", "(", ":"]
        }
    }

    private static func outdentTriggers(for language: String) -> [String] {
        switch language {
        case "python", "ruby", "yaml", "toml", "markdown", "makefile":
            return []
        default:
            return ["}", "]", ")"]
        }
    }
}

@MainActor
private final class AttoEditorTab {
    let id: UUID
    var fileURL: URL
    var isUntitled: Bool
    var isPreview: Bool
    var isDirty: Bool
    var syntaxLanguageId: String?
    var panes: [EditCoreUI]
    var activePaneIndex: Int

    var editCore: EditCoreUI {
        panes[max(0, min(activePaneIndex, panes.count - 1))]
    }

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
        isUntitled: Bool,
        isPreview: Bool,
        isDirty: Bool,
        syntaxLanguageId: String?,
        editCore: EditCoreUI
    ) {
        self.id = id
        self.fileURL = fileURL
        self.isUntitled = isUntitled
        self.isPreview = isPreview
        self.isDirty = isDirty
        self.syntaxLanguageId = syntaxLanguageId
        self.panes = [editCore]
        self.activePaneIndex = 0
    }
}

private extension NSColor {
    convenience init(attoHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((attoHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((attoHex >> 8) & 0xFF) / 255.0
        let b = CGFloat(attoHex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    convenience init(ecuRgba8 c: EcuRgba8) {
        let r = CGFloat(c.r) / 255.0
        let g = CGFloat(c.g) / 255.0
        let b = CGFloat(c.b) / 255.0
        let a = CGFloat(c.a) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension AttoEditorAreaViewController: NSSearchFieldDelegate, NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideFindBar()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field == findReplaceBarView.searchField {
            refreshSearchHighlights()
        }
    }
}
