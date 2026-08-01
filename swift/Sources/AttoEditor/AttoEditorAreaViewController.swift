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

    private struct DefinitionRequestContext {
        let tabID: UUID
        let logicalLine: UInt32
        let logicalColumn: UInt32
        let kind: LspLocationRequestKind
    }

    private var hoverContext: HoverRequestContext?
    private var hoverDebounceWorkItem: DispatchWorkItem?
    private var hoverPollTimer: DispatchSourceTimer?
    private var hoverPopover: NSPopover?
    private var hoverPopoverLabel: NSTextField?

    private var definitionContext: DefinitionRequestContext?
    private var definitionPollTimer: DispatchSourceTimer?
    private var lspLocationResultsController: AttoCommandPaletteController?

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
        let prefs = AttoPreferences.shared
        let fontFamiliesCSV = prefs.fontFamiliesCSVForApplying()
        let ligaturesEnabled = prefs.effectiveLigaturesEnabled
        let fontSizePoints = prefs.effectiveFontSizePoints

        for tab in tabs {
            // Font families: empty CSV means "reset to default" (Skia renderer falls back).
            do {
                try tab.editCore.editor.setFontFamiliesCSV(fontFamiliesCSV)
            } catch {
                NSLog("AttoEditor: setFontFamiliesCSV failed: %@", String(describing: error))
            }

            do {
                try tab.editCore.editor.setFontLigaturesEnabled(ligaturesEnabled)
            } catch {
                NSLog("AttoEditor: setFontLigaturesEnabled failed: %@", String(describing: error))
            }

            tab.editCore.editorView.fontSizePoints = CGFloat(fontSizePoints)
            tab.editCore.editorView.needsDisplay = true
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
            do {
                try tab.editCore.applyTheme(theme)
            } catch {
                NSLog("AttoEditor: applyTheme failed: %@", String(describing: error))
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
        cancelDefinitionUI()

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
        tab.editCore.showsMinimap.toggle()
        tab.editCore.needsLayout = true
        tab.editCore.needsDisplay = true
        notifySessionStateChanged()
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
                "line": Self.lineCommentToken(for: tab),
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

    func formatDocumentWithLspInActiveTab() {
        guard let tab = activeTab else { return }
        tab.editCore.editorView.formatDocumentWithLSP()
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

    private static func lineCommentToken(for tab: AttoEditorTab) -> String {
        let language = tab.syntaxLanguageId?.lowercased()
        let ext = tab.fileURL.pathExtension.lowercased()
        switch language ?? ext {
        case "python", "py", "ruby", "rb", "shell", "bash", "sh", "zsh", "toml", "yaml", "yml", "make":
            return "#"
        case "lua":
            return "--"
        case "sql":
            return "--"
        case "lisp", "clojure", "clj", "scheme", "scm":
            return ";"
        default:
            return "//"
        }
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

        // VSCode-like defaults.
        // 保持至少 6 个 cell 的 gutter（折叠标记 + 行号），但仍允许在超大文件时自动扩展。
        editCore.editorView.minimumGutterWidthCells = 6
        // Visual aids enabled by default in AttoEditor MVP.
        try editCore.editor.setWhitespaceRenderMode(.selection)
        try editCore.editor.setIndentGuidesEnabled(true)
        try editCore.editor.setFontLigaturesEnabled(prefs.effectiveLigaturesEnabled)
        editCore.editorView.fontSizePoints = CGFloat(prefs.effectiveFontSizePoints)
        try editCore.applyTheme(theme)
        // Enable baseline editor UX by default.
        try editCore.editor.setAutoPairsEnabled(true)
        try editCore.editor.setBracketMatchHighlightsEnabled(true)

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
        editCore.onDidMutateDocumentText = { [weak self] in
            self?.handleTabDidMutateDocumentText(tabID: tabId)
        }
        editCore.onDidApplyAsyncProcessing = { [weak self] in
            guard let self else { return }
            // Async processing updates (LSP diagnostics/semantic tokens, etc.) can change status
            // bar info even without any user input.
            guard self.activeTab?.id == tabId else { return }
            self.updateStatusBar()
        }
        editCore.onHover = { [weak self] info in
            self?.handleHover(info: info, tabID: tabId)
        }
        editCore.onHoverExit = { [weak self] in
            self?.handleHoverExit(tabID: tabId)
        }
        editCore.editorView.onCommandClick = { [weak self] ctx in
            self?.handleCommandClick(ctx: ctx, tabID: tabId) ?? false
        }
        editCore.editorView.onCommandHover = { [weak self] _ in
            guard let self else { return false }
            guard activeTab?.id == tabId else { return false }
            guard let tab = activeTab else { return false }
            // Only show Cmd-hover "clickable" affordance when Cmd-click is expected to resolve via LSP.
            return (try? tab.editCore.editor.lspIsEnabled()) == true
        }
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

@MainActor
private final class AttoEditorTab {
    let id: UUID
    var fileURL: URL
    var isUntitled: Bool
    var isPreview: Bool
    var isDirty: Bool
    var syntaxLanguageId: String?
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
