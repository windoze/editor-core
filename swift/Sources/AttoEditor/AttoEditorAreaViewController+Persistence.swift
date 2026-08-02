import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    struct SyntaxSupportConfiguration {
        let syntaxLanguageId: String?
        let lspServerConfig: AttoLspServerLaunchConfig?
    }

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
        let fileURL = projectedFileURL(for: tab)
        for editCore in tab.panes {
            applyLanguageConfiguration(fileURL: fileURL, syntaxLanguageId: tab.syntaxLanguageId, to: editCore)
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
        let syntaxSupport = configureSyntaxSupport(for: url, editCore: editCore)
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
            editCore: editCore
        )
        tab.lspServerConfig = syntaxSupport.lspServerConfig
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

    func configureSyntaxSupport(for url: URL, editCore: EditCoreUI) -> SyntaxSupportConfiguration {
        // Start from a clean slate (best-effort). This avoids stacking style layers when a host
        // switches engines (e.g. LSP becomes available later).
        editCore.editor.lspDisable()
        editCore.editor.treeSitterDisable()
        editCore.editor.sublimeDisable()

        // 1) LSP (configurable by extension).
        let env = lspEnvironmentProvider()
        let disableLSP = isLspDisabled(environment: env)

        if disableLSP == false {
            if let config = lspLaunchConfig(for: url, environment: env) {
                do {
                    let languageId = try enableLspSupport(for: url, editCore: editCore, config: config)
                    return SyntaxSupportConfiguration(
                        syntaxLanguageId: languageId,
                        lspServerConfig: config
                    )
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
            return SyntaxSupportConfiguration(
                syntaxLanguageId: inferredTreeSitterLanguageId(for: url),
                lspServerConfig: nil
            )
        } catch {
            NSLog("AttoEditor: Tree-sitter enable failed for %@: %@", url.path, String(describing: error))
        }

        // 3) Sublime `.sublime-syntax` (optional fallback).
        guard let syntaxPath = AttoSublimeSyntax.findSyntaxPath(
            for: url,
            workspaceRootURL: workspaceRootURL
        ) else {
            NSLog("AttoEditor: no Sublime syntax found for %@ (ext=%@)", url.path, url.pathExtension)
            return SyntaxSupportConfiguration(syntaxLanguageId: nil, lspServerConfig: nil)
        }

        do {
            try editCore.editor.sublimeSetSyntaxPath(syntaxPath)
            editCore.editor.treeSitterDisable()
            editCore.editorView.needsDisplay = true
            return SyntaxSupportConfiguration(syntaxLanguageId: nil, lspServerConfig: nil)
        } catch {
            NSLog(
                "AttoEditor: Sublime syntax enable failed (path=%@) for %@: %@",
                syntaxPath,
                url.path,
                String(describing: error)
            )
            return SyntaxSupportConfiguration(syntaxLanguageId: nil, lspServerConfig: nil)
        }
    }

    func lspLaunchConfig(
        for url: URL,
        environment env: [String: String] = ProcessInfo.processInfo.environment
    ) -> AttoLspServerLaunchConfig? {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let configured = AttoLspRegistry.loadServerMap()[ext]

        let command: String? = {
            if let configured { return configured.command }

            if ext == "rs" {
                return env["ATTO_EDITOR_LSP_CMD"]
                    ?? env["EDITOR_CORE_APPKIT_LSP_CMD"]
                    ?? "rust-analyzer"
            }

            return nil
        }()

        let args: String? = {
            if let configured { return configured.args }

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

        guard let command, let languageId, languageId.isEmpty == false else {
            return nil
        }

        return AttoLspServerLaunchConfig(
            command: command,
            args: args,
            languageId: languageId
        )
    }

    func isLspDisabled(environment env: [String: String]) -> Bool {
        env["ATTO_EDITOR_DISABLE_LSP"] == "1"
            || env["EDITOR_CORE_APPKIT_DISABLE_LSP"] == "1"
    }

    @discardableResult
    func enableLspSupport(
        for url: URL,
        editCore: EditCoreUI,
        config: AttoLspServerLaunchConfig
    ) throws -> String {
        try editCore.editor.lspEnable(
            command: config.command,
            args: config.args,
            rootURI: workspaceRootURL.standardizedFileURL.absoluteString,
            documentURI: url.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )

        let supportsSemanticTokens: Bool = {
            guard let status = try? editCore.editor.lspStatusSnapshot() else { return false }
            return status.capabilities?.semanticTokens == true
        }()

        if supportsSemanticTokens {
            editCore.editor.treeSitterDisable()
            editCore.editor.sublimeDisable()
        } else {
            do {
                try editCore.editor.treeSitterEnableForPath(url.path)
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

        return config.languageId
    }

    @discardableResult
    func startProjectLspServersForOpenTabs() -> Int {
        let env = lspEnvironmentProvider()
        guard isLspDisabled(environment: env) == false else { return 0 }

        var startedCount = 0

        for projected in coreProjectedTabsForWorkspaceLifecycle() {
            let tab = projected.tab
            guard tab.suppressesAutomaticLspStart == false else { continue }
            guard (try? tab.editCore.editor.lspIsEnabled()) != true else { continue }

            let documentURL = projected.fileURL
            guard let config = tab.lspServerConfig ?? lspLaunchConfig(for: documentURL, environment: env) else {
                continue
            }

            do {
                let languageId = try enableLspSupport(
                    for: documentURL,
                    editCore: tab.editCore,
                    config: config
                )
                tab.syntaxLanguageId = languageId
                tab.lspServerConfig = config
                tab.suppressesAutomaticLspStart = false
                applyLanguageConfiguration(for: tab)
                tab.editCore.editorView.kickProcessingPoll()
                tab.editCore.editorView.needsDisplay = true
                startedCount += 1
            } catch {
                NSLog(
                    "AttoEditor: project LSP auto-start failed for %@: %@",
                    documentURL.path,
                    String(describing: error)
                )
            }
        }

        if startedCount > 0 {
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
        }

        return startedCount
    }

    @discardableResult
    func restartLspServerInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        guard let config = tab.lspServerConfig else {
            NSSound.beep()
            presentLspResultFeedback(
                AttoLspResultFeedback.unavailable(
                    .serverRestart,
                    reason: "No LSP server is configured for this document."
                ),
                in: tab.editCore.editorView
            )
            return false
        }

        let documentURL = projectedFileURL(for: tab)

        do {
            try restartLspServer(for: tab, documentURL: documentURL, config: config)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            setTransientStatusText("LSP server restarted")
            return true
        } catch {
            tab.lspServerConfig = config
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            NSSound.beep()
            presentLspResultFeedback(
                AttoLspResultFeedback.failed(
                    .serverRestart,
                    errorDescription: String(describing: error)
                ),
                in: tab.editCore.editorView
            )
            return false
        }
    }

    @discardableResult
    func restartProjectLspServers() -> Bool {
        let projectedTabs = coreProjectedTabsForWorkspaceLifecycle()
        let restartTargets = projectedTabs.compactMap {
            projected -> (tab: AttoEditorTab, fileURL: URL, config: AttoLspServerLaunchConfig)? in
            guard let config = projected.tab.lspServerConfig else {
                return nil
            }
            return (
                tab: projected.tab,
                fileURL: projected.fileURL,
                config: config
            )
        }

        guard restartTargets.isEmpty == false else {
            NSSound.beep()
            if let tab = activeTab {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(
                        .serverRestart,
                        reason: "No open document has a configured LSP server."
                    ),
                    in: tab.editCore.editorView
                )
            }
            return false
        }

        var restartedCount = 0
        var failures: [String] = []

        for target in restartTargets {
            do {
                try restartLspServer(
                    for: target.tab,
                    documentURL: target.fileURL,
                    config: target.config
                )
                restartedCount += 1
            } catch {
                target.tab.lspServerConfig = target.config
                failures.append("\(target.fileURL.lastPathComponent): \(error)")
            }
        }

        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()

        if failures.isEmpty {
            let noun = restartedCount == 1 ? "server" : "servers"
            setTransientStatusText("LSP \(noun) restarted: \(restartedCount)")
            return restartedCount > 0
        }

        NSSound.beep()
        let detail = "Restarted \(restartedCount) of \(restartTargets.count) LSP servers.\n"
            + failures.joined(separator: "\n")
        if let tab = activeTab {
            presentLspResultFeedback(
                AttoLspResultFeedback.failed(.serverRestart, errorDescription: detail),
                in: tab.editCore.editorView
            )
        } else {
            setTransientStatusText("LSP server restart: failed")
        }
        return false
    }

    @discardableResult
    func attemptProjectLspAutoRestart(tabId: UInt64?, status: EcuLspStatusSnapshot?) -> Bool {
        guard let tabId, let status, let process = status.process else {
            return false
        }

        if process.state == .running,
           status.availability != .failed,
           status.state != .failed
        {
            projectLspAutoRestartStatesByTabID.removeValue(forKey: tabId)
            return false
        }

        let now = projectLspAutoRestartNowProvider()
        let currentState = projectLspAutoRestartStatesByTabID[tabId]
        let maxAttempts = preferences.effectiveLspAutoRestartMaxAttempts(
            serverName: status.server?.name,
            serverCommand: status.server?.command
        )
        let baseDelaySeconds = preferences.effectiveLspAutoRestartBaseDelaySeconds(
            serverName: status.server?.name,
            serverCommand: status.server?.command
        )
        guard process.state == .exited,
              status.availability == .failed || status.state == .failed,
              preferences.effectiveLspAutoRestartEnabled,
              preferences.isLspAutoRestartDisabledForServer(
                  serverName: status.server?.name,
                  serverCommand: status.server?.command
              ) == false,
              maxAttempts > 0,
              (currentState?.attempts ?? 0) < maxAttempts,
              currentState.map({ now >= $0.nextAllowedAt }) ?? true
        else {
            return false
        }

        guard let target = coreProjectedTabsForWorkspaceLifecycle().first(where: { $0.tab.coreTabID == tabId }),
              let config = target.tab.lspServerConfig
        else {
            return false
        }

        let attempts = (currentState?.attempts ?? 0) + 1
        projectLspAutoRestartStatesByTabID[tabId] = ProjectLspAutoRestartState(
            attempts: attempts,
            nextAllowedAt: now.addingTimeInterval(Self.projectLspAutoRestartDelay(
                forAttempt: attempts,
                baseDelaySeconds: baseDelaySeconds
            ))
        )
        do {
            try restartLspServer(for: target.tab, documentURL: target.fileURL, config: config)
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            setTransientStatusText("LSP server auto-restarted")
            return true
        } catch {
            target.tab.lspServerConfig = config
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            NSLog(
                "AttoEditor: project LSP auto-restart failed for %@: %@",
                target.fileURL.path,
                String(describing: error)
            )
            return false
        }
    }

    private static func projectLspAutoRestartDelay(forAttempt attempt: Int, baseDelaySeconds: TimeInterval) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        return baseDelaySeconds * pow(2, Double(exponent))
    }

    private func restartLspServer(
        for tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig
    ) throws {
        tab.editCore.editor.lspDisable()
        let languageId = try enableLspSupport(
            for: documentURL,
            editCore: tab.editCore,
            config: config
        )
        tab.syntaxLanguageId = languageId
        tab.lspServerConfig = config
        tab.suppressesAutomaticLspStart = false
        applyLanguageConfiguration(for: tab)
        tab.editCore.editorView.kickProcessingPoll()
        tab.editCore.editorView.needsDisplay = true
    }
}
