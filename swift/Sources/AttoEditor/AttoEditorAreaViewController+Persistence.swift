import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Content

    func showEmptyState() {
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        contentHostView.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: contentHostView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentHostView.centerYAnchor),
        ])
    }

    func showTabContent(_ tab: AttoEditorTab) {
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

    func configureEditorChrome(_ editCore: EditCoreUI) throws {
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

    func applyLanguageConfiguration(for tab: AttoEditorTab) {
        for editCore in tab.panes {
            applyLanguageConfiguration(fileURL: tab.fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: editCore)
        }
    }

    func applyLanguageConfiguration(fileURL: URL, syntaxLanguageId: String?, to editCore: EditCoreUI) {
        let config = AttoLanguageConfiguration.indentationConfig(fileURL: fileURL, syntaxLanguageId: syntaxLanguageId)
        do {
            _ = try editCore.editor.setIndentationConfig(config)
        } catch {
            NSLog("AttoEditor: setIndentationConfig failed for %@: %@", fileURL.path, String(describing: error))
        }
    }

    func configureEditCoreHooks(_ editCore: EditCoreUI, tabID: UUID) {
        editCore.onDidMutateDocumentText = { [weak self] in
            self?.handleTabDidMutateDocumentText(tabID: tabID)
        }
        editCore.onDidCommitText = { [weak self] text in
            self?.handleCommittedTextForLspTriggers(text, tabID: tabID)
        }
        editCore.onDidChangeSelection = { [weak self] causedByTextMutation in
            self?.handleTabDidChangeSelection(tabID: tabID, causedByTextMutation: causedByTextMutation)
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
        editCore.editorView.onDocumentLinkClick = { [weak self, weak editCore] json in
            guard let editCore else { return false }
            return self?.handleDocumentLinkClick(json: json, tabID: tabID, editorView: editCore.editorView) ?? false
        }
        editCore.editorView.onInlayHintClick = { [weak self, weak editCore] json in
            guard let editCore else { return false }
            return self?.handleInlayHintClick(json: json, tabID: tabID, editorView: editCore.editorView) ?? false
        }
        editCore.editorView.onCodeLensClick = { [weak self] json in
            self?.handleCodeLensClick(json: json, tabID: tabID) ?? false
        }
        editCore.editorView.onCommandHover = { [weak self] _ in
            guard let self else { return false }
            guard activeTab?.id == tabID else { return false }
            guard let tab = activeTab else { return false }
            // Only show Cmd-hover "clickable" affordance when Cmd-click is expected to resolve via LSP.
            return (try? tab.editCore.editor.lspIsEnabled()) == true
        }
    }

    func setActivePane(_ editCore: EditCoreUI, tabID: UUID) {
        guard selectedTabID == tabID else { return }
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        guard let idx = tab.panes.firstIndex(where: { $0 === editCore }) else { return }

        tab.activePaneIndex = idx
        setCoreActiveView(tab)
        attachStatusObserver(to: editCore.editorView)
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()
    }

    // MARK: - Tab creation

    func makeTab(
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
        editCore.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.editorPane(tabId))
        editCore.editorView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.editorView(tabId))
        let coreTabID = openCoreDocumentTab(for: url, initialText: initialText, isPreview: isPreview)
        let tab = AttoEditorTab(
            id: tabId,
            coreTabID: coreTabID,
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
    func saveTabWithSavePanelIfNeeded(_ tab: AttoEditorTab) -> Bool {
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

    func configureSyntaxSupport(for url: URL, editCore: EditCoreUI) -> String? {
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
                        guard let status = try? editCore.editor.lspStatusSnapshot() else { return false }
                        return status.capabilities?.semanticTokens == true
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
}
