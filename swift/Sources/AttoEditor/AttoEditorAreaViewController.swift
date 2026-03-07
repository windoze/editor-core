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

    private struct HoverRequestContext {
        let tabID: UUID
        let info: EditorCoreSkiaHoverInfo
    }

    private struct DefinitionRequestContext {
        let tabID: UUID
        let logicalLine: UInt32
        let logicalColumn: UInt32
    }

    private var hoverContext: HoverRequestContext?
    private var hoverDebounceWorkItem: DispatchWorkItem?
    private var hoverPollTimer: DispatchSourceTimer?
    private var hoverPopover: NSPopover?
    private var hoverPopoverLabel: NSTextField?

    private var definitionContext: DefinitionRequestContext?
    private var definitionPollTimer: DispatchSourceTimer?

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
        tabBarView.onDoubleClickTab = { [weak self] id in
            self?.pinTabIfPreview(id: id)
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
            try tab.editCore.editor.markSaved()
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
        cancelHoverUI()
        cancelDefinitionUI()

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

    private func pinTabIfPreview(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard tab.isPreview else { return }
        tab.isPreview = false
        refreshTabBar()
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

        tab.isDirty = (try? tab.editCore.editor.isModified()) ?? true

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
        editCore.onHover = { [weak self] info in
            self?.handleHover(info: info, tabID: tabId)
        }
        editCore.onHoverExit = { [weak self] in
            self?.handleHoverExit(tabID: tabId)
        }
        editCore.editorView.onCommandClick = { [weak self] ctx in
            self?.handleCommandClick(ctx: ctx, tabID: tabId) ?? false
        }
        return tab
    }

    // MARK: - LSP go to definition (Cmd-click)

    private func handleCommandClick(ctx: EditorCoreSkiaContextMenuContext, tabID: UUID) -> Bool {
        guard activeTab?.id == tabID else { return false }
        guard let tab = activeTab else { return false }

        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            return false
        }

        cancelHoverUI()

        definitionContext = DefinitionRequestContext(tabID: tabID, logicalLine: ctx.logicalLine, logicalColumn: ctx.logicalColumn)
        definitionPollTimer?.cancel()

        do {
            _ = try tab.editCore.editor.lspRequestDefinition(
                logicalLine: ctx.logicalLine,
                logicalColumn: ctx.logicalColumn
            )
        } catch {
            cancelDefinitionUI()
            return false
        }

        startDefinitionPollTimer(tabID: tabID)
        return true
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
                json = try tab.editCore.editor.lspTakeLastDefinitionResultJSON()
            } catch {
                return
            }
            guard let json else { return }

            self.cancelDefinitionUI()
            self.navigateToDefinitionResultJSON(json)
            timer.cancel()
        }

        definitionPollTimer = timer
        timer.resume()
    }

    private func navigateToDefinitionResultJSON(_ json: String) {
        guard let target = AttoLspDefinitionParser.firstTarget(fromDefinitionResultJSON: json) else {
            NSSound.beep()
            return
        }
        guard let url = URL(string: target.uri), url.isFileURL else {
            NSSound.beep()
            return
        }

        openFile(url: url, mode: .preview)

        guard let tab = activeTab, tab.fileURL.standardizedFileURL == url.standardizedFileURL else {
            return
        }

        do {
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
