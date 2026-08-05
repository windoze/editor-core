import AppKit
import AttoEditorSupport
import EditorCoreUI
import Foundation

extension AttoEditorAreaViewController {
    struct SyntaxSupportConfiguration {
        let syntaxLanguageId: String?
        let lspServerConfig: AttoLspServerLaunchConfig?
        let source: AttoLanguageSupportSource
        let fallbackReasons: [String]
    }

    // MARK: - Content

    func showEmptyState() {
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        applyEditorBackground(theme)
        contentHostView.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: contentHostView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentHostView.centerYAnchor),
        ])
    }

    func showTabContent(_ tab: AttoEditorTab) {
        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        applyEditorBackground(configuredThemeForApplying(tab))
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
        try configureEditorChrome(editCore, configurationSnapshot: configurationSnapshot)
    }

    func configureEditorChrome(
        _ editCore: EditCoreUI,
        configurationSnapshot snapshot: AttoConfigurationSnapshot
    ) throws {
        // 保持至少 6 个 cell 的 gutter（折叠标记 + 行号），但仍允许在超大文件时自动扩展。
        editCore.editorView.minimumGutterWidthCells = 6
        try editCore.editor.setWhitespaceRenderMode(.selection)
        try editCore.editor.setIndentGuidesEnabled(true)
        try editCore.editor.setFontFamiliesCSV(configuredFontFamiliesCSVForApplying(snapshot))
        try editCore.editor.setFontLigaturesEnabled(configuredLigaturesEnabledForApplying(snapshot))
        try editCore.editor.setFontFeatureMap(configuredFontFeatureMapForApplying(snapshot))
        editCore.editorView.fontSizePoints = CGFloat(configuredFontSizePointsForApplying(snapshot))
        try editCore.applyTheme(configuredThemeForApplying(snapshot))
        _ = try editCore.editor.setWrapMode(configuredWrapModeForApplying(snapshot))
        _ = try editCore.editor.setWrapIndent(configuredWrapIndentForApplying(snapshot))
        try editCore.editor.setAutoPairsEnabled(configuredAutoPairsEnabledForApplying(snapshot))
        try editCore.editor.setLspOnTypeFormattingEnabled(configuredFormatOnTypeEnabledForApplying(snapshot))
        try applyWordBoundaryConfiguration(to: editCore.editor, configurationSnapshot: snapshot)
        try editCore.editor.setBracketMatchHighlightsEnabled(true)
    }

    func applyLanguageConfiguration(for tab: AttoEditorTab) {
        syncCoreTabLanguageId(tab)
        applyDocumentLanguageConfiguration(for: tab)
    }

    func applyDocumentLanguageConfiguration(for tab: AttoEditorTab) {
        let fileURL = projectedFileURL(for: tab)
        for editCore in tab.panes {
            applyLanguageConfiguration(fileURL: fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: editCore)
        }
    }

    func syncCoreTabLanguageId(_ tab: AttoEditorTab) {
        let fileURL = projectedFileURL(for: tab)
        let languageId = AttoLanguageConfiguration.languageKey(
            fileURL: fileURL,
            syntaxLanguageId: tab.syntaxLanguageId
        )
        syncCoreTabLanguageId(languageId.isEmpty ? nil : languageId, for: tab)
    }

    func syncCoreTabLanguageId(_ languageId: String?, for tab: AttoEditorTab) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else { return }

        let normalized = languageId?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try coreDocuments.setTabLanguageId(
                normalized?.isEmpty == false ? normalized : nil,
                tabId: coreTabID
            )
        } catch {
            NSLog("AttoEditor: core multi-document setTabLanguageId failed: %@", String(describing: error))
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

    func applyDocumentLoadPolicyResult(
        _ loadResult: AttoDocumentLoadResult,
        to tab: AttoEditorTab,
        documentURL: URL
    ) {
        let wasLanguageProcessingDisabled = tab.languageProcessingDisabledReason != nil
        tab.languageProcessingDisabledReason = loadResult.languageProcessingDisabledReason

        if loadResult.disablesLanguageProcessing {
            stopLspSessionForLanguageChange(tab)
            for editCore in tab.panes {
                editCore.editor.treeSitterDisable()
                editCore.editor.sublimeDisable()
            }
            tab.lspServerConfig = nil
            tab.suppressesAutomaticLspStart = true
            tab.syntaxLanguageId = nil
            tab.languageSupportSource = .plainText
            tab.languageFallbackReasons = loadResult.fallbackReasons
            syncCoreTabLanguageId(nil, for: tab)
            syncProjectLspServerConfigsToCore()
            return
        }

        guard wasLanguageProcessingDisabled else { return }

        let syntaxSupport = configureSyntaxSupport(for: documentURL, editCore: tab.editCore)
        tab.syntaxLanguageId = syntaxSupport.syntaxLanguageId
        tab.languageSupportSource = syntaxSupport.source
        tab.languageFallbackReasons = syntaxSupport.fallbackReasons
        tab.lspServerConfig = syntaxSupport.lspServerConfig
        tab.suppressesAutomaticLspStart = false
        syncCoreTabLanguageId(tab)
        syncProjectLspServerConfigsToCore()
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
        isUntitled: Bool = false,
        initialTextOverride: String? = nil
    ) throws -> AttoEditorTab {
        let loadResult: AttoDocumentLoadResult
        if let initialTextOverride {
            loadResult = AttoDocumentLoadPolicy.overriddenText(initialTextOverride)
        } else if isUntitled {
            loadResult = AttoDocumentLoadPolicy.overriddenText("")
        } else {
            loadResult = try AttoDocumentLoadPolicy.loadText(
                from: url,
                largeFileByteLimit: documentLoadLargeFileByteLimit
            )
        }
        let initialText = loadResult.text

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
        let syntaxSupport = loadResult.disablesLanguageProcessing
            ? SyntaxSupportConfiguration(
                syntaxLanguageId: nil,
                lspServerConfig: nil,
                source: .plainText,
                fallbackReasons: loadResult.fallbackReasons
            )
            : configureSyntaxSupport(for: url, editCore: editCore)
        let documentConfiguration = documentConfigurationSnapshot(
            for: url,
            syntaxLanguageId: syntaxSupport.syntaxLanguageId
        )
        try configureEditorChrome(editCore, configurationSnapshot: documentConfiguration)
        applyLanguageConfiguration(fileURL: url, syntaxLanguageId: syntaxSupport.syntaxLanguageId, to: editCore)

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
            syntaxLanguageId: syntaxSupport.syntaxLanguageId,
            languageSupportSource: syntaxSupport.source,
            languageFallbackReasons: syntaxSupport.fallbackReasons,
            languageProcessingDisabledReason: loadResult.languageProcessingDisabledReason,
            editCore: editCore
        )
        tab.lspServerConfig = syntaxSupport.lspServerConfig
        tab.suppressesAutomaticLspStart = loadResult.disablesLanguageProcessing
        syncCoreTabLanguageId(tab)
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

        if let existingTab = projectedTab(forFileURL: url), existingTab.id != tab.id {
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
        if saveTab(tab, documentURL: url) {
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

    func configureSyntaxSupport(for url: URL, editCore: EditCoreUI) -> SyntaxSupportConfiguration {
        // Start from a clean slate (best-effort). This avoids stacking style layers when a host
        // switches engines (e.g. LSP becomes available later).
        editCore.editor.lspDisable()
        editCore.editor.treeSitterDisable()
        editCore.editor.sublimeDisable()

        // 1) LSP (configurable by extension).
        let env = lspEnvironmentProvider()
        let disableLSP = isLspDisabled(environment: env)
        var fallbackReasons: [String] = []

        if disableLSP == false {
            if let config = lspLaunchConfig(for: url, environment: env) {
                do {
                    let lspSupport = try enableLspSupport(for: url, editCore: editCore, config: config)
                    return SyntaxSupportConfiguration(
                        syntaxLanguageId: lspSupport.languageId,
                        lspServerConfig: config,
                        source: lspSupport.source,
                        fallbackReasons: lspSupport.fallbackReasons
                    )
                } catch {
                    fallbackReasons.append("LSP server could not start; trying syntax-only fallback.")
                    NSLog("AttoEditor: LSP enable failed for %@: %@", url.path, String(describing: error))
                }
            } else {
                let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let target = ext.isEmpty ? "this file" : ".\(ext)"
                fallbackReasons.append("No LSP server is configured for \(target).")
            }
        } else {
            fallbackReasons.append("LSP is disabled by environment.")
        }

        // 2) Tree-sitter.
        do {
            try editCore.editor.treeSitterEnableForPath(url.path)
            editCore.editor.sublimeDisable()
            // Kick a short poll window so the initial Tree-sitter parse applies even without edits.
            editCore.editorView.kickProcessingPoll()
            return SyntaxSupportConfiguration(
                syntaxLanguageId: inferredTreeSitterLanguageId(for: url),
                lspServerConfig: nil,
                source: .treeSitter,
                fallbackReasons: fallbackReasons
            )
        } catch {
            fallbackReasons.append("Tree-sitter parser is unavailable; trying Sublime syntax fallback.")
            NSLog("AttoEditor: Tree-sitter enable failed for %@: %@", url.path, String(describing: error))
        }

        // 3) Sublime `.sublime-syntax` (optional fallback).
        guard let syntaxPath = AttoSublimeSyntax.findSyntaxPath(
            for: url,
            workspaceRootURL: workspaceRootURL
        ) else {
            fallbackReasons.append("No Sublime syntax fallback was found.")
            NSLog("AttoEditor: no Sublime syntax found for %@ (ext=%@)", url.path, url.pathExtension)
            return SyntaxSupportConfiguration(
                syntaxLanguageId: nil,
                lspServerConfig: nil,
                source: .plainText,
                fallbackReasons: fallbackReasons
            )
        }

        do {
            try editCore.editor.sublimeSetSyntaxPath(syntaxPath)
            editCore.editor.treeSitterDisable()
            editCore.editorView.needsDisplay = true
            return SyntaxSupportConfiguration(
                syntaxLanguageId: nil,
                lspServerConfig: nil,
                source: .sublimeSyntax,
                fallbackReasons: fallbackReasons
            )
        } catch {
            fallbackReasons.append("Sublime syntax fallback failed.")
            NSLog(
                "AttoEditor: Sublime syntax enable failed (path=%@) for %@: %@",
                syntaxPath,
                url.path,
                String(describing: error)
            )
            return SyntaxSupportConfiguration(
                syntaxLanguageId: nil,
                lspServerConfig: nil,
                source: .plainText,
                fallbackReasons: fallbackReasons
            )
        }
    }

}
