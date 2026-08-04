import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    private typealias ProjectedWorkspaceTab = (tab: AttoEditorTab, fileURL: URL)

    private struct ProjectLspStartCandidate {
        let coreTabID: UInt64?
        let tab: AttoEditorTab
        let fileURL: URL
        let config: AttoLspServerLaunchConfig
    }

    private struct ProjectLspStartTarget {
        let candidate: ProjectLspStartCandidate
        let planEntry: EcuProjectLspStartPlanEntry?
        let rootURI: String?
    }

    struct SyntaxSupportConfiguration {
        let syntaxLanguageId: String?
        let lspServerConfig: AttoLspServerLaunchConfig?
        let source: AttoLanguageSupportSource
    }

    struct LspSupportConfiguration {
        let languageId: String
        let source: AttoLanguageSupportSource
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
        let initialText = initialTextOverride ?? ((try? String(contentsOf: url, encoding: .utf8)) ?? "")

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
        let syntaxSupport = configureSyntaxSupport(for: url, editCore: editCore)
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
            editCore: editCore
        )
        tab.lspServerConfig = syntaxSupport.lspServerConfig
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

        if disableLSP == false {
            if let config = lspLaunchConfig(for: url, environment: env) {
                do {
                    let lspSupport = try enableLspSupport(for: url, editCore: editCore, config: config)
                    return SyntaxSupportConfiguration(
                        syntaxLanguageId: lspSupport.languageId,
                        lspServerConfig: config,
                        source: lspSupport.source
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
                lspServerConfig: nil,
                source: .treeSitter
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
            return SyntaxSupportConfiguration(syntaxLanguageId: nil, lspServerConfig: nil, source: .plainText)
        }

        do {
            try editCore.editor.sublimeSetSyntaxPath(syntaxPath)
            editCore.editor.treeSitterDisable()
            editCore.editorView.needsDisplay = true
            return SyntaxSupportConfiguration(syntaxLanguageId: nil, lspServerConfig: nil, source: .sublimeSyntax)
        } catch {
            NSLog(
                "AttoEditor: Sublime syntax enable failed (path=%@) for %@: %@",
                syntaxPath,
                url.path,
                String(describing: error)
            )
            return SyntaxSupportConfiguration(syntaxLanguageId: nil, lspServerConfig: nil, source: .plainText)
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

    func syncProjectLspServerConfigsToCore() {
        guard let coreDocuments else { return }

        do {
            try coreDocuments.setProjectLspServers(projectLspServerConfigsForOpenTabs())
        } catch {
            NSLog("AttoEditor: failed to sync project LSP server configs: %@", String(describing: error))
        }
    }

    private func projectLspServerConfigsForOpenTabs(
        additionalLaunchConfigsByTab: [ObjectIdentifier: AttoLspServerLaunchConfig] = [:]
    ) -> [EcuProjectLspServerConfig] {
        let workspaceRootURIs = projectLspWorkspaceRootURIs()
        var configsByKey: [String: EcuProjectLspServerConfig] = [:]
        var orderedKeys: [String] = []

        for projected in coreProjectedTabsForWorkspaceLifecycle() {
            let tabKey = ObjectIdentifier(projected.tab)
            guard let launchConfig = projected.tab.lspServerConfig ?? additionalLaunchConfigsByTab[tabKey] else {
                continue
            }

            let key = Self.projectLspServerConfigKey(for: launchConfig)
            guard key.isEmpty == false else { continue }

            let autoStart = projected.tab.suppressesAutomaticLspStart == false
            if let existing = configsByKey[key] {
                var workspaceRoots = existing.workspaceRoots
                for rootURI in workspaceRootURIs where workspaceRoots.contains(rootURI) == false {
                    workspaceRoots.append(rootURI)
                }
                configsByKey[key] = EcuProjectLspServerConfig(
                    key: existing.key,
                    command: existing.command,
                    args: existing.args,
                    languageId: existing.languageId,
                    workspaceRoots: workspaceRoots,
                    autoStart: existing.autoStart || autoStart
                )
                continue
            }

            orderedKeys.append(key)
            configsByKey[key] = EcuProjectLspServerConfig(
                key: key,
                command: launchConfig.command,
                args: Self.projectLspServerConfigArgs(from: launchConfig.args),
                languageId: launchConfig.languageId,
                workspaceRoots: workspaceRootURIs,
                autoStart: autoStart
            )
        }

        return orderedKeys.compactMap { configsByKey[$0] }
    }

    private func projectLspWorkspaceRootURIs() -> [String] {
        if let coreRoots = try? coreDocuments?.snapshot().workspaceRoots {
            let normalizedRoots = Self.uniqueProjectLspWorkspaceRootURIs(coreRoots)
            if normalizedRoots.isEmpty == false {
                return normalizedRoots
            }
        }

        return [workspaceRootURL.standardizedFileURL.absoluteString]
    }

    private static func uniqueProjectLspWorkspaceRootURIs(_ roots: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for root in roots {
            let normalized = root.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, seen.insert(normalized).inserted else {
                continue
            }
            ordered.append(normalized)
        }
        return ordered
    }

    static func projectLspServerConfigKey(for config: AttoLspServerLaunchConfig) -> String {
        ([config.languageId, config.command] + projectLspServerConfigArgs(from: config.args))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: ":")
            .lowercased()
    }

    private static func projectLspServerConfigArgs(from args: String?) -> [String] {
        guard let args else { return [] }
        return args.split { $0.isWhitespace }.map(String.init)
    }

    @discardableResult
    func enableLspSupport(
        for url: URL,
        editCore: EditCoreUI,
        config: AttoLspServerLaunchConfig,
        rootURI: String? = nil
    ) throws -> LspSupportConfiguration {
        try editCore.editor.lspEnable(
            command: config.command,
            args: config.args,
            rootURI: rootURI ?? workspaceRootURL.standardizedFileURL.absoluteString,
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
            return LspSupportConfiguration(languageId: config.languageId, source: .lspSemantic)
        } else {
            var enabledTreeSitterFallback = false
            do {
                try editCore.editor.treeSitterEnableForPath(url.path)
                editCore.editorView.kickProcessingPoll()
                enabledTreeSitterFallback = true
            } catch {
                NSLog(
                    "AttoEditor: Tree-sitter enable failed for %@ (fallback after LSP without semantic tokens): %@",
                    url.path,
                    String(describing: error)
                )
            }
            editCore.editor.sublimeDisable()
            return LspSupportConfiguration(
                languageId: config.languageId,
                source: enabledTreeSitterFallback ? .lspTreeSitter : .lspServices
            )
        }
    }

    @discardableResult
    func startProjectLspServersForOpenTabs() -> Int {
        let env = lspEnvironmentProvider()
        defer { syncProjectLspServerConfigsToCore() }
        guard isLspDisabled(environment: env) == false else { return 0 }

        let projectedTabs = coreProjectedTabsForWorkspaceLifecycle()
        let candidates = projectLspStartCandidates(
            for: projectedTabs,
            environment: env
        )
        let startTargets = projectLspStartTargets(for: candidates)
        var startedCount = 0
        var attemptedTabIDs: Set<UInt64> = []

        for target in startTargets {
            let tab = target.candidate.tab
            if let coreTabID = target.candidate.coreTabID,
               attemptedTabIDs.insert(coreTabID).inserted == false
            {
                continue
            }
            guard (try? tab.editCore.editor.lspIsEnabled()) != true else { continue }

            let documentURL = target.candidate.fileURL
            let config = target.candidate.config
            let startAttemptId = recordProjectLspStartOutcome(for: target, status: "requested")

            do {
                let lspSupport = try enableLspSupport(
                    for: documentURL,
                    editCore: tab.editCore,
                    config: config,
                    rootURI: target.rootURI
                )
                tab.syntaxLanguageId = lspSupport.languageId
                tab.languageSupportSource = lspSupport.source
                tab.lspServerConfig = config
                tab.suppressesAutomaticLspStart = false
                applyLanguageConfiguration(for: tab)
                tab.editCore.editorView.kickProcessingPoll()
                tab.editCore.editorView.needsDisplay = true
                recordProjectLspStartOutcome(for: target, status: "started", attemptId: startAttemptId)
                startedCount += 1
            } catch {
                recordProjectLspStartOutcome(
                    for: target,
                    status: "failed",
                    errorMessage: String(describing: error),
                    attemptId: startAttemptId
                )
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

    private func projectLspStartCandidates(
        for projectedTabs: [ProjectedWorkspaceTab],
        environment env: [String: String]
    ) -> [ProjectLspStartCandidate] {
        projectedTabs.compactMap { projected in
            let tab = projected.tab
            guard tab.suppressesAutomaticLspStart == false else { return nil }
            guard (try? tab.editCore.editor.lspIsEnabled()) != true else { return nil }
            let config = tab.lspServerConfig ?? lspLaunchConfig(for: projected.fileURL, environment: env)
            guard let config else { return nil }
            return ProjectLspStartCandidate(
                coreTabID: tab.coreTabID,
                tab: tab,
                fileURL: projected.fileURL,
                config: config
            )
        }
    }

    private func projectLspStartTargets(
        for candidates: [ProjectLspStartCandidate]
    ) -> [ProjectLspStartTarget] {
        guard candidates.isEmpty == false else { return [] }
        let fallbackTargets = candidates.map {
            ProjectLspStartTarget(candidate: $0, planEntry: nil, rootURI: nil)
        }
        guard let coreDocuments else { return fallbackTargets }

        let additionalConfigs = Dictionary(
            uniqueKeysWithValues: candidates.map { (ObjectIdentifier($0.tab), $0.config) }
        )

        do {
            try coreDocuments.setProjectLspServers(
                projectLspServerConfigsForOpenTabs(additionalLaunchConfigsByTab: additionalConfigs)
            )
            let plan = try coreDocuments.projectLspStartPlan()
            var candidatesByTabID: [UInt64: ProjectLspStartCandidate] = [:]
            for candidate in candidates {
                guard let coreTabID = candidate.coreTabID else { continue }
                candidatesByTabID[coreTabID] = candidate
            }

            return plan.compactMap { entry in
                guard let candidate = candidatesByTabID[entry.tabId],
                      Self.projectLspStartPlanEntry(entry, matches: candidate.config),
                      Self.projectLspStartPlanEntry(entry, matchesDocumentURL: candidate.fileURL)
                else {
                    return nil
                }
                return ProjectLspStartTarget(
                    candidate: candidate,
                    planEntry: entry,
                    rootURI: Self.projectLspStartPlanRootURI(entry)
                )
            }
        } catch {
            NSLog("AttoEditor: failed to build project LSP start plan: %@", String(describing: error))
            return fallbackTargets
        }
    }

    private static func projectLspStartPlanEntry(
        _ entry: EcuProjectLspStartPlanEntry,
        matches config: AttoLspServerLaunchConfig
    ) -> Bool {
        entry.serverKey.lowercased() == projectLspServerConfigKey(for: config)
    }

    private static func projectLspStartPlanEntry(
        _ entry: EcuProjectLspStartPlanEntry,
        matchesDocumentURL documentURL: URL
    ) -> Bool {
        entry.documentURI == documentURL.standardizedFileURL.absoluteString
    }

    private static func projectLspStartPlanRootURI(_ entry: EcuProjectLspStartPlanEntry) -> String? {
        entry.workspaceRoots.first { root in
            root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    @discardableResult
    private func recordProjectLspStartOutcome(
        for target: ProjectLspStartTarget,
        status: String,
        errorMessage: String? = nil,
        attemptId: UInt64? = nil
    ) -> UInt64? {
        guard let coreDocuments,
              let coreTabID = target.candidate.coreTabID
        else {
            return nil
        }

        let planEntry = target.planEntry
        let outcome = EcuProjectLspStartOutcome(
            tabId: coreTabID,
            activeViewIndex: planEntry?.activeViewIndex ?? 0,
            documentURI: planEntry?.documentURI ?? target.candidate.fileURL.standardizedFileURL.absoluteString,
            languageId: planEntry?.languageId ?? target.candidate.config.languageId,
            serverKey: planEntry?.serverKey ?? Self.projectLspServerConfigKey(for: target.candidate.config),
            command: planEntry?.command ?? target.candidate.config.command,
            args: planEntry?.args ?? Self.projectLspServerConfigArgs(from: target.candidate.config.args),
            workspaceRoots: planEntry?.workspaceRoots ?? [],
            trigger: "auto_start",
            status: status,
            attemptId: attemptId,
            errorMessage: errorMessage
        )

        do {
            try coreDocuments.recordProjectLspStartOutcome(outcome)
            if let attemptId {
                return attemptId
            }
            if Self.isProjectLspRequestedStatus(status) {
                return try? coreDocuments.projectLspLifecycleEventsLatestSequence()
            }
        } catch {
            NSLog("AttoEditor: failed to record project LSP start outcome: %@", String(describing: error))
        }
        return nil
    }

    @discardableResult
    private func recordProjectLspLifecycleOutcome(
        for tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        operation: String,
        trigger: String,
        status: String,
        errorMessage: String? = nil,
        attemptId: UInt64? = nil
    ) -> UInt64? {
        guard let coreDocuments,
              let coreTabID = tab.coreTabID
        else {
            return nil
        }

        let outcome = EcuProjectLspStartOutcome(
            tabId: coreTabID,
            activeViewIndex: UInt32(clamping: tab.activePaneIndex),
            operation: operation,
            documentURI: documentURL.standardizedFileURL.absoluteString,
            languageId: config.languageId,
            serverKey: Self.projectLspServerConfigKey(for: config),
            command: config.command,
            args: Self.projectLspServerConfigArgs(from: config.args),
            workspaceRoots: projectLspWorkspaceRootURIs(),
            trigger: trigger,
            status: status,
            attemptId: attemptId,
            errorMessage: errorMessage
        )

        do {
            try coreDocuments.recordProjectLspStartOutcome(outcome)
            if let attemptId {
                return attemptId
            }
            if Self.isProjectLspRequestedStatus(status) {
                return try? coreDocuments.projectLspLifecycleEventsLatestSequence()
            }
        } catch {
            NSLog(
                "AttoEditor: failed to record project LSP %@ outcome: %@",
                operation,
                String(describing: error)
            )
        }
        return nil
    }

    private static func isProjectLspRequestedStatus(_ status: String) -> Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "requested"
    }

    @discardableResult
    func recordProjectLspRestartOutcome(
        for tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        trigger: String,
        status: String,
        errorMessage: String? = nil,
        attemptId: UInt64? = nil
    ) -> UInt64? {
        recordProjectLspLifecycleOutcome(
            for: tab,
            documentURL: documentURL,
            config: config,
            operation: "restart",
            trigger: trigger,
            status: status,
            errorMessage: errorMessage,
            attemptId: attemptId
        )
    }

    @discardableResult
    func recordProjectLspStopOutcome(
        for tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        trigger: String,
        status: String,
        errorMessage: String? = nil,
        attemptId: UInt64? = nil
    ) -> UInt64? {
        recordProjectLspLifecycleOutcome(
            for: tab,
            documentURL: documentURL,
            config: config,
            operation: "stop",
            trigger: trigger,
            status: status,
            errorMessage: errorMessage,
            attemptId: attemptId
        )
    }

    @discardableResult
    func shutdownLspServerInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let documentURL = projectedFileURL(for: tab)
        let config = tab.lspServerConfig
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            NSSound.beep()
            presentLspResultFeedback(
                AttoLspResultFeedback.unavailable(
                    .serverShutdown,
                    reason: "No LSP server is running for this document."
                ),
                in: tab.editCore.editorView
            )
            return false
        }

        let shutdownAttemptId: UInt64?
        if let config {
            let planDecision = projectLspStopPlanDecision(
                for: tab,
                documentURL: documentURL,
                config: config
            )
            guard planDecision.allowed else {
                recordProjectLspStopOutcome(
                    for: tab,
                    documentURL: documentURL,
                    config: config,
                    trigger: "manual_shutdown",
                    status: "skipped",
                    errorMessage: "No project LSP stop plan matches this document."
                )
                NSSound.beep()
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(
                        .serverShutdown,
                        reason: "No project LSP stop plan matches this document."
                    ),
                    in: tab.editCore.editorView
                )
                return false
            }
            shutdownAttemptId = recordProjectLspStopOutcome(
                for: tab,
                documentURL: documentURL,
                config: config,
                trigger: "manual_shutdown",
                status: "requested"
            )
        } else {
            shutdownAttemptId = nil
        }

        do {
            let didShutdown = try tab.editCore.editor.lspShutdown()
            guard didShutdown else {
                if let config {
                    recordProjectLspStopOutcome(
                        for: tab,
                        documentURL: documentURL,
                        config: config,
                        trigger: "manual_shutdown",
                        status: "failed",
                        errorMessage: "No running LSP server was available to shut down.",
                        attemptId: shutdownAttemptId
                    )
                }
                NSSound.beep()
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(
                        .serverShutdown,
                        reason: "No LSP server is running for this document."
                    ),
                    in: tab.editCore.editorView
                )
                return false
            }

            if let config {
                recordProjectLspStopOutcome(
                    for: tab,
                    documentURL: documentURL,
                    config: config,
                    trigger: "manual_shutdown",
                    status: "stopped",
                    attemptId: shutdownAttemptId
                )
            }
            markLspServerShutdown(for: tab)
            syncProjectLspServerConfigsToCore()
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            tab.editCore.editorView.needsDisplay = true
            setTransientStatusText("LSP server shut down")
            return true
        } catch {
            if let config {
                recordProjectLspStopOutcome(
                    for: tab,
                    documentURL: documentURL,
                    config: config,
                    trigger: "manual_shutdown",
                    status: "failed",
                    errorMessage: String(describing: error),
                    attemptId: shutdownAttemptId
                )
            }
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            NSSound.beep()
            presentLspResultFeedback(
                AttoLspResultFeedback.failed(
                    .serverShutdown,
                    errorDescription: String(describing: error)
                ),
                in: tab.editCore.editorView
            )
            return false
        }
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
        let planDecision = projectLspRestartPlanDecision(
            for: tab,
            documentURL: documentURL,
            config: config
        )
        guard planDecision.allowed else {
            recordProjectLspRestartOutcome(
                for: tab,
                documentURL: documentURL,
                config: config,
                trigger: "manual_restart",
                status: "skipped",
                errorMessage: "No project LSP restart plan matches this document."
            )
            NSSound.beep()
            presentLspResultFeedback(
                AttoLspResultFeedback.unavailable(
                    .serverRestart,
                    reason: "No project LSP restart plan matches this document."
                ),
                in: tab.editCore.editorView
            )
            return false
        }
        let restartAttemptId = recordProjectLspRestartOutcome(
            for: tab,
            documentURL: documentURL,
            config: config,
            trigger: "manual_restart",
            status: "requested"
        )

        do {
            try restartLspServer(
                for: tab,
                documentURL: documentURL,
                config: config,
                rootURI: projectLspRestartPlanRootURI(planDecision.planEntry)
            )
            recordProjectLspRestartOutcome(
                for: tab,
                documentURL: documentURL,
                config: config,
                trigger: "manual_restart",
                status: "started",
                attemptId: restartAttemptId
            )
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            setTransientStatusText("LSP server restarted")
            return true
        } catch {
            tab.lspServerConfig = config
            syncProjectLspServerConfigsToCore()
            recordProjectLspRestartOutcome(
                for: tab,
                documentURL: documentURL,
                config: config,
                trigger: "manual_restart",
                status: "failed",
                errorMessage: String(describing: error),
                attemptId: restartAttemptId
            )
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
        let planDecision = projectLspRestartPlanDecision(
            for: target.tab,
            documentURL: target.fileURL,
            config: config
        )
        guard planDecision.allowed else {
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
        let restartAttemptId = recordProjectLspRestartOutcome(
            for: target.tab,
            documentURL: target.fileURL,
            config: config,
            trigger: "auto_restart",
            status: "requested"
        )
        do {
            try restartLspServer(
                for: target.tab,
                documentURL: target.fileURL,
                config: config,
                rootURI: projectLspRestartPlanRootURI(planDecision.planEntry)
            )
            recordProjectLspRestartOutcome(
                for: target.tab,
                documentURL: target.fileURL,
                config: config,
                trigger: "auto_restart",
                status: "started",
                attemptId: restartAttemptId
            )
            updateAlwaysPollProcessingForSelectedTab()
            updateStatusBar()
            setTransientStatusText("LSP server auto-restarted")
            return true
        } catch {
            target.tab.lspServerConfig = config
            syncProjectLspServerConfigsToCore()
            recordProjectLspRestartOutcome(
                for: target.tab,
                documentURL: target.fileURL,
                config: config,
                trigger: "auto_restart",
                status: "failed",
                errorMessage: String(describing: error),
                attemptId: restartAttemptId
            )
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

    func restartLspServer(
        for tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig,
        rootURI: String? = nil
    ) throws {
        tab.editCore.editor.lspDisable()
        let lspSupport = try enableLspSupport(
            for: documentURL,
            editCore: tab.editCore,
            config: config,
            rootURI: rootURI
        )
        tab.syntaxLanguageId = lspSupport.languageId
        tab.languageSupportSource = lspSupport.source
        tab.lspServerConfig = config
        tab.suppressesAutomaticLspStart = false
        syncProjectLspServerConfigsToCore()
        applyLanguageConfiguration(for: tab)
        tab.editCore.editorView.kickProcessingPoll()
        tab.editCore.editorView.needsDisplay = true
    }
}
