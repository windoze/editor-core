import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Status bar

    var activeTab: AttoEditorTab? {
        if let coreActiveTab = coreProjectedActiveTab() {
            return coreActiveTab
        }
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    func updateWindowTitle() {
        guard let win = view.window else { return }
        guard let tab = activeTab else {
            win.title = "AttoEditor"
            return
        }

        let name = projectedFileURL(for: tab).lastPathComponent
        if refreshTabDirtyState(tab) {
            win.title = "AttoEditor — ● \(name)"
        } else {
            win.title = "AttoEditor — \(name)"
        }
    }

    func handleTabDidMutateDocumentText(tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.semanticTokensData = []
        tab.semanticTokensResultId = nil
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
        let currentText = try? tab.editCore.editor.text()
        syncCoreTabText(tab, markSaved: tab.isDirty == false)
        if let currentText {
            notifyLspDocumentChangedForOpenSessions(
                tab,
                documentURL: projectedFileURL(for: tab),
                text: currentText
            )
        }
        if didUnpreview {
            pinCoreTabIfPreview(tab)
        }

        refreshTabBar()
        updateWindowTitle()
        if didUnpreview {
            notifySessionStateChanged()
        }

        handleTabDidChangeSelection(tabID: tabID, causedByTextMutation: true)
    }

    func handleTabDidChangeSelection(tabID: UUID, causedByTextMutation: Bool) {
        guard let session = linkedEditingSession, session.tabID == tabID else { return }
        guard selectedTabID == tabID,
              let tab = tabs.first(where: { $0.id == tabID })
        else {
            linkedEditingSession = nil
            return
        }

        if causedByTextMutation {
            guard let selections = try? tab.editCore.editor.selections(),
                  selections.ranges.count == session.selectionCount,
                  selections.ranges.count > 1
            else {
                linkedEditingSession = nil
                return
            }
            linkedEditingSession = LinkedEditingSession(tabID: tabID, selectionCount: selections.ranges.count)
        } else {
            linkedEditingSession = nil
        }
    }

    func attachStatusObserver(to editorView: EditorCoreSkiaView) {
        activeViewportObserver = editorView.addViewportStateObserver { [weak self] in
            self?.updateStatusBar()
        }
    }

    func updateAlwaysPollProcessingForSelectedTab() {
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

    func updateStatusBar() {
        drainProjectLspPanelLifecycleEvents()

        guard let tab = activeTab else {
            derivedStateStore.clearActive()
            problemsPanelController?.update(problems: [])
            clearDiagnosticMarkers()
            statusBarView.update(
                leftText: transientStatusText,
                languageSourceText: nil,
                languageSourceTooltip: nil,
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
        let editorText = try? editor.text()
        if let editorText {
            markActiveDiagnosticsStaleIfNeeded(for: tab, text: editorText)
        }
        derivedStateStore.refreshActive(editor: editor)
        clearActiveDiagnosticsStaleIfDiagnosticsChanged(
            for: tab,
            diagnostics: derivedStateStore.active.diagnostics.diagnostics
        )
        let diagnosticsSnapshot = unifiedDiagnosticsSnapshot(
            for: tab,
            text: editorText,
            includeActiveDiagnostics: true
        )
        recordActiveDiagnosticsLifecycle(diagnosticsSnapshot, for: tab)
        updateProblemsPanelIfVisible(snapshot: diagnosticsSnapshot)
        updateVisibleLspWorkbenchPanel()
        updateDiagnosticMarkers(for: tab, projections: diagnosticsSnapshot.markerProjections)

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

        let documentURL = projectedFileURL(for: tab)

        let fileSizeText: String? = {
            do {
                let values = try documentURL.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize else { return nil }
                return AttoFormat.byteCount(Int64(size))
            } catch {
                return nil
            }
        }()

        let lspIsEnabled = (try? editor.lspIsEnabled()) == true
        let activeLspStatus: EcuLspStatusSnapshot? = {
            guard lspIsEnabled else {
                return derivedStateStore.activeLspStatus
            }
            return derivedStateStore.activeLspStatus ?? (try? editor.lspStatusSnapshot())
        }()

        let lspText: String? = {
            // Keep the status bar clean unless LSP is likely relevant.
            //
            // - Historically, AttoEditor only auto-enabled LSP for Rust.
            // - With configurable LSPs, show LSP status when it is enabled (any language), or for Rust files.
            let isRustFile = (documentURL.pathExtension.lowercased() == "rs")
            guard isRustFile || lspIsEnabled else { return nil }

            do {
                let status = try activeLspStatus ?? editor.lspStatusSnapshot()
                let display = AttoLspStatusFormatter.display(status: status, fallbackEnabled: lspIsEnabled)
                if let detail = display.failureDetail {
                    presentLspFailureDetailIfNeeded(detail, editorView: tab.editCore.editorView)
                } else {
                    lastPresentedLspFailureDetail = nil
                }
                return display.text
            } catch {
                // Best-effort: never break status bar rendering because of FFI errors.
                return lspIsEnabled ? "LSP: on" : "LSP: off"
            }
        }()

        let languageSourceIndicator = AttoLanguageSourceIndicator(
            source: tab.languageSupportSource,
            languageId: tab.syntaxLanguageId,
            lspCapabilities: activeLspStatus?.capabilities,
            fallbackReasons: tab.languageFallbackReasons
        )
        statusBarView.update(
            leftText: transientStatusText ?? statusBarLeftText(for: tab, diagnostics: diagnosticsSnapshot),
            languageSourceText: languageSourceIndicator.statusText,
            languageSourceTooltip: languageSourceIndicator.tooltipText,
            languageId: tab.syntaxLanguageId,
            languageIsEnabled: tab.languageProcessingDisabledReason == nil,
            lspText: lspText,
            positionText: "Ln \(line1), Col \(col1)",
            selectionText: selectionText,
            fileSizeText: fileSizeText
        )
    }

    func clearDiagnosticMarkers() {
        for tab in tabs {
            for pane in tab.panes {
                pane.minimapDiagnosticMarkers = []
                pane.gutterDiagnosticMarkers = []
            }
        }
    }

    func updateDiagnosticMarkers(for tab: AttoEditorTab, includeActiveDiagnostics: Bool) {
        let projections = unifiedDiagnosticsSnapshot(
            for: tab,
            includeActiveDiagnostics: includeActiveDiagnostics
        ).markerProjections
        updateDiagnosticMarkers(for: tab, projections: projections)
    }

    func updateDiagnosticMarkers(
        for tab: AttoEditorTab,
        projections: [AttoDiagnosticMarkerProjection]
    ) {
        let minimapMarkers = projections.map {
            EditorCoreSkiaMinimapMarker(
                logicalLine: $0.logicalLine,
                kind: minimapMarkerKind(for: $0.severity)
            )
        }
        let gutterMarkers = projections.map {
            EditorCoreSkiaGutterDiagnosticMarker(
                logicalLine: $0.logicalLine,
                charOffset: $0.charOffset,
                kind: gutterMarkerKind(for: $0.severity)
            )
        }

        for pane in tab.panes {
            pane.minimapDiagnosticMarkers = minimapMarkers
            pane.gutterDiagnosticMarkers = gutterMarkers
        }
    }

    func updateProblemsPanelIfVisible(snapshot: AttoUnifiedDiagnosticsSnapshot) {
        guard problemsPanelController?.isVisible == true else { return }
        problemsPanelController?.update(problems: snapshot.problems)
    }

    func unifiedDiagnosticsSnapshot(
        for tab: AttoEditorTab,
        text: String? = nil,
        includeActiveDiagnostics: Bool
    ) -> AttoUnifiedDiagnosticsSnapshot {
        guard let text = text ?? (try? tab.editCore.editor.text()) else { return .empty }
        return AttoDiagnosticsModel.snapshot(
            activeDiagnostics: derivedStateStore.active.diagnostics.diagnostics,
            includeActiveDiagnostics: includeActiveDiagnostics,
            workspaceDiagnostics: workspaceProblemsStore.diagnostics,
            workspaceMarkers: workspaceProblemsStore.diagnosticMarkerProjections(),
            tabURL: projectedFileURL(for: tab),
            text: text,
            logicalPositionForOffset: { offset in
                try? tab.editCore.editor.charOffsetToLogicalPosition(offset: offset)
            }
        )
    }

    func statusBarLeftText(
        for tab: AttoEditorTab,
        diagnostics: AttoUnifiedDiagnosticsSnapshot
    ) -> String? {
        let parts = [
            diagnostics.problemsStatusText,
            derivedStateStore.active.foldedStatusText,
            derivedStateStore.active.codeLensStatusText,
        ].compactMap { $0 }
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " | ")
    }

    func markActiveDiagnosticsStaleIfNeeded(for tab: AttoEditorTab, text: String) {
        let fingerprint = DiagnosticsTextFingerprint(text)
        if let previous = activeDiagnosticsTextFingerprintsByTabID[tab.id], previous != fingerprint {
            activeDiagnosticsStaleReasonsByTabID[tab.id] = .documentEdited
            markCurrentLspResultPanelsStale(reason: "document edited")
        }
        activeDiagnosticsTextFingerprintsByTabID[tab.id] = fingerprint
    }

    func markCurrentLspResultPanelsStale(reason: String) {
        let state = AttoLspResultLifecycleState.stale(reason: reason)
        var didUpdate = false
        if let entry = lspLocationResultStore.updateCurrentState(state) {
            lspLocationPanelController?.update(entry: entry)
            didUpdate = true
        }
        if let entry = lspSymbolResultStore.updateCurrentState(state) {
            lspSymbolPanelController?.update(entry: entry)
            didUpdate = true
        }
        let updatedEvents = lspResultEventStream.updateLatestStates(
            families: [
                "code_lens",
                "inlay_hints",
                "document_links",
                "document_colors",
                "hierarchy",
            ],
            state: state,
            ownerMatches: { [weak self] owner in
                self?.lspResultOwnerMatchesActiveDocument(owner) ?? false
            }
        )
        didUpdate = didUpdate || updatedEvents.isEmpty == false
        if didUpdate {
            updateVisibleLspWorkbenchPanel()
        }
    }

    func markCurrentLspLocationResultError(_ message: AttoLspResultFeedback.Message) {
        if let entry = lspLocationResultStore.updateCurrentState(.error(message: message.statusText)) {
            lspLocationPanelController?.update(entry: entry)
            updateVisibleLspWorkbenchPanel()
        }
    }

    func markCurrentLspSymbolResultError(_ message: AttoLspResultFeedback.Message) {
        if let entry = lspSymbolResultStore.updateCurrentState(.error(message: message.statusText)) {
            lspSymbolPanelController?.update(entry: entry)
            updateVisibleLspWorkbenchPanel()
        }
    }

    @discardableResult
    func markCurrentLspEventResultError(
        family: String,
        message: AttoLspResultFeedback.Message
    ) -> Bool {
        let updated = lspResultEventStream.updateLatestStates(
            families: [family],
            state: .error(message: message.statusText),
            ownerMatches: { [weak self] owner in
                self?.lspResultOwnerMatchesActiveDocument(owner) ?? false
            }
        )
        guard updated.isEmpty == false else { return false }
        updateVisibleLspWorkbenchPanel()
        return true
    }

    func drainProjectLspPanelLifecycleEvents() {
        guard let coreDocuments else { return }

        do {
            let requestSnapshot = try coreDocuments.lspRequestEvents(after: coreLspRequestEventCursor)
            coreLspRequestEventCursor = requestSnapshot.latestSequence
            for event in requestSnapshot.events {
                recordProjectLspPanelError(
                    source: .request,
                    sourceSequence: event.sequence,
                    tabId: event.tabId,
                    viewIndex: event.viewIndex,
                    viewId: event.viewId,
                    family: event.family,
                    title: event.title,
                    slot: event.slot,
                    method: event.method,
                    requestId: event.requestId,
                    status: event.status,
                    errorMessage: event.errorMessage
                )
            }

            let resultSnapshot = try coreDocuments.lspResultEvents(after: coreLspResultEventCursor)
            coreLspResultEventCursor = resultSnapshot.latestSequence
            for event in resultSnapshot.events {
                recordProjectLspPanelError(
                    source: .result,
                    sourceSequence: event.sequence,
                    tabId: event.tabId,
                    viewIndex: event.viewIndex,
                    viewId: event.viewId,
                    family: event.family,
                    title: event.title,
                    slot: event.slot,
                    method: event.method,
                    requestId: event.requestId,
                    status: event.status,
                    errorMessage: event.errorMessage
                )
            }

            let stateSnapshot = try coreDocuments.stateEvents(after: coreLspStateEventCursor)
            coreLspStateEventCursor = stateSnapshot.latestSequence
            for event in stateSnapshot.events where event.kindValue == .lspStatusChanged {
                recordProjectLspProcessHealth(
                    sourceSequence: event.sequence,
                    tabId: event.tabId,
                    viewIndex: event.viewIndex,
                    viewId: event.viewId,
                    status: event.stateEvent.lspStatus
                )
                recordProjectLspStatusFailure(
                    sourceSequence: event.sequence,
                    tabId: event.tabId,
                    viewIndex: event.viewIndex,
                    viewId: event.viewId,
                    status: event.stateEvent.lspStatus
                )
            }

            try drainCoreProjectLspLifecycleEvents(coreDocuments)
        } catch {
            NSLog("AttoEditor: project LSP panel lifecycle event drain failed: %@", String(describing: error))
        }
    }

    @discardableResult
    func showProjectLspStatusEventsPanel() -> Bool {
        drainProjectLspPanelLifecycleEvents()

        let events = Array(projectLspPanelErrorEventStore.events.reversed())
        let lifecycleEvents = Array(projectLspLifecycleEventStore.events.reversed())
        guard events.isEmpty == false || lifecycleEvents.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return false
        }

        let commands = events.enumerated().map { idx, event in
            AttoCommandPaletteCommand(
                id: "lsp.project_status_event.\(idx)",
                title: Self.projectLspStatusEventTitle(event)
            ) {}
        } + lifecycleEvents.enumerated().map { idx, event in
            AttoCommandPaletteCommand(
                id: "lsp.project_lifecycle_event.\(idx)",
                title: Self.projectLspLifecycleEventTitle(event)
            ) {}
        }
        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.ProjectStatusEvents",
            commandsProvider: { commands }
        )
        projectLspStatusEventsController = controller
        controller.show(relativeTo: window, placeholder: "Filter LSP status events...")
        return true
    }

    @discardableResult
    func showProjectLspProcessHealthPanel() -> Bool {
        drainProjectLspPanelLifecycleEvents()

        let commands: [AttoCommandPaletteCommand]
        let events = Array(projectLspProcessHealthEventStore.events.reversed())
        if events.isEmpty == false {
            commands = events.enumerated().map { idx, event in
                AttoCommandPaletteCommand(
                    id: "lsp.project_process_health.\(idx)",
                    title: Self.projectLspProcessHealthEventTitle(event)
                ) {}
            }
        } else {
            let persistedEntries = Array(projectLspProcessHealthLogStore.loadRecent(
                workspaceRootURL: workspaceRootURL,
                limit: Self.maxLspResultEventHistoryEntries
            ).reversed())
            guard persistedEntries.isEmpty == false else {
                NSSound.beep()
                return false
            }
            commands = persistedEntries.enumerated().map { idx, entry in
                AttoCommandPaletteCommand(
                    id: "lsp.project_process_health_log.\(idx)",
                    title: Self.projectLspProcessHealthLogEntryTitle(entry)
                ) {}
            }
        }
        guard commands.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return false
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.ProjectProcessHealth",
            commandsProvider: { commands }
        )
        projectLspProcessHealthController = controller
        controller.show(relativeTo: window, placeholder: "Filter LSP process health...")
        return true
    }

    @discardableResult
    func showProjectLspProcessHealthLogPanel() -> Bool {
        drainProjectLspPanelLifecycleEvents()

        let initialEntries = projectLspProcessHealthLogStore.queryRecent(
            workspaceRootURL: workspaceRootURL,
            query: "",
            limit: Self.maxLspResultEventHistoryEntries
        )
        guard initialEntries.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return false
        }

        var query = ""
        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.ProjectProcessHealthLog",
            filtersCommands: false,
            searchTextDidChange: { [weak self] text in
                query = text
                self?.projectLspProcessHealthLogController?.reloadCommands()
            },
            commandsProvider: { [weak self] in
                self?.projectLspProcessHealthLogCommands(query: query) ?? []
            }
        )
        projectLspProcessHealthLogController = controller
        controller.show(relativeTo: window, placeholder: "Filter LSP process health log...")
        return true
    }

    private func projectLspProcessHealthLogCommands(query: String) -> [AttoCommandPaletteCommand] {
        let entries = Array(projectLspProcessHealthLogStore.queryRecent(
            workspaceRootURL: workspaceRootURL,
            query: query,
            limit: Self.maxLspResultEventHistoryEntries
        ).reversed())

        return entries.enumerated().map { idx, entry in
            AttoCommandPaletteCommand(
                id: "lsp.project_process_health_log_entry.\(idx)",
                title: Self.projectLspProcessHealthLogEntryTitle(entry)
            ) {}
        }
    }

    @discardableResult
    func showProjectLspDashboardPanel() -> Bool {
        drainProjectLspPanelLifecycleEvents()

        let commands = projectLspDashboardCommands()
        guard commands.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return false
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.ProjectDashboard",
            commandsProvider: { commands }
        )
        projectLspDashboardController = controller
        controller.show(relativeTo: window, placeholder: "Filter LSP project health...")
        return true
    }

    @discardableResult
    func _runProjectLspDashboardCommandForTesting(id: String) -> Bool {
        guard let command = projectLspDashboardCommands().first(where: { $0.id == id }) else {
            return false
        }
        command.run()
        return true
    }

    private func projectLspDashboardCommands() -> [AttoCommandPaletteCommand] {
        var commands: [AttoCommandPaletteCommand] = []

        let statusEvents = Array(projectLspPanelErrorEventStore.events.reversed())
        let lifecycleEvents = Array(projectLspLifecycleEventStore.events.reversed())
        let healthEvents = Array(projectLspProcessHealthEventStore.events.reversed())
        let persistedEntries = Array(projectLspProcessHealthLogStore.queryRecent(
            workspaceRootURL: workspaceRootURL,
            query: "",
            limit: Self.maxLspResultEventHistoryEntries
        ).reversed())
        let activeRecoveryCount = projectLspAutoRestartStatesByTabID.values.filter { $0.attempts > 0 }.count

        guard statusEvents.isEmpty == false
            || lifecycleEvents.isEmpty == false
            || healthEvents.isEmpty == false
            || persistedEntries.isEmpty == false
            || activeRecoveryCount > 0
        else {
            return []
        }

        commands.append(AttoCommandPaletteCommand(
            id: "lsp.project_dashboard.summary",
            title: projectLspDashboardSummaryTitle(
                statusFailureCount: statusEvents.count,
                lifecycleEventCount: lifecycleEvents.count,
                lifecycleAttemptCount: Self.projectLspLifecycleAttemptCount(lifecycleEvents),
                healthEventCount: healthEvents.count,
                persistedLogCount: persistedEntries.count
            )
        ) {})

        commands.append(AttoCommandPaletteCommand(
            id: "lsp.project_dashboard.recovery_policy",
            title: projectLspDashboardRecoveryPolicyTitle()
        ) {})

        commands.append(contentsOf: projectLspDashboardRecoveryActionCommands())

        if let trendTitle = Self.projectLspDashboardTrendTitle(persistedEntries: persistedEntries) {
            commands.append(AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.trend",
                title: trendTitle
            ) {})
        }

        let serverGroups = projectLspDashboardServerGroups(
            healthEvents: healthEvents,
            persistedEntries: persistedEntries,
            lifecycleEvents: lifecycleEvents
        )

        commands.append(contentsOf: serverGroups.enumerated().map { idx, group in
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.server_group.\(idx)",
                title: Self.projectLspDashboardServerGroupTitle(group)
            ) {}
        })

        commands.append(contentsOf: serverGroups.enumerated().flatMap { idx, group in
            projectLspDashboardServerRecoveryActionCommands(group: group, index: idx)
        })

        commands.append(contentsOf: statusEvents.enumerated().map { idx, event in
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.status.\(idx)",
                title: "Status - \(Self.projectLspStatusEventTitle(event))"
            ) {}
        })

        commands.append(contentsOf: lifecycleEvents.enumerated().map { idx, event in
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.lifecycle.\(idx)",
                title: "Lifecycle - \(Self.projectLspLifecycleEventTitle(event))"
            ) {}
        })

        if healthEvents.isEmpty == false {
            commands.append(contentsOf: healthEvents.enumerated().map { idx, event in
                AttoCommandPaletteCommand(
                    id: "lsp.project_dashboard.health.\(idx)",
                    title: "Health - \(Self.projectLspProcessHealthEventTitle(event))"
                ) {}
            })
        } else {
            commands.append(contentsOf: persistedEntries.enumerated().map { idx, entry in
                AttoCommandPaletteCommand(
                    id: "lsp.project_dashboard.health_log.\(idx)",
                    title: "Log - \(Self.projectLspProcessHealthLogEntryTitle(entry))"
                ) {}
            })
        }

        return commands
    }

    private func projectLspDashboardSummaryTitle(
        statusFailureCount: Int,
        lifecycleEventCount: Int,
        lifecycleAttemptCount: Int,
        healthEventCount: Int,
        persistedLogCount: Int
    ) -> String {
        let recovery = projectLspAutoRestartStatesByTabID.values
            .filter { $0.attempts > 0 }
            .map(\.attempts)
        let retrySummary: String
        if recovery.isEmpty {
            retrySummary = "recovery idle"
        } else {
            retrySummary = "recovery retries \(recovery.reduce(0, +)) across \(recovery.count) tab(s)"
        }
        return "Summary - status failures \(statusFailureCount), lifecycle events \(lifecycleEventCount), lifecycle attempts \(lifecycleAttemptCount), health events \(healthEventCount), persisted logs \(persistedLogCount), \(retrySummary)"
    }

    private static func projectLspLifecycleAttemptCount(_ events: [EcuProjectLspLifecycleEvent]) -> Int {
        Set(events.compactMap(\.attemptId)).count
    }

    private func projectLspDashboardRecoveryPolicyTitle() -> String {
        let enabled = preferences.effectiveLspAutoRestartEnabled
        let enabledText = enabled ? "auto-restart on" : "auto-restart off"
        let maxAttempts = preferences.effectiveLspAutoRestartMaxAttempts
        let baseDelay = preferences.effectiveLspAutoRestartBaseDelaySeconds
        return "Recovery Policy - \(enabledText), max attempts \(maxAttempts), base delay \(Self.formatProjectLspDashboardSeconds(baseDelay))"
    }

    private func projectLspDashboardRecoveryActionCommands() -> [AttoCommandPaletteCommand] {
        let currentlyEnabled = preferences.effectiveLspAutoRestartEnabled
        let verb = currentlyEnabled ? "Disable" : "Enable"
        let maxAttempts = preferences.effectiveLspAutoRestartMaxAttempts
        let increasedMaxAttempts = min(maxAttempts + 1, 10)
        let decreasedMaxAttempts = max(maxAttempts - 1, 0)
        let baseDelay = preferences.effectiveLspAutoRestartBaseDelaySeconds
        let increasedBaseDelay = min(baseDelay + 1.0, 3_600.0)
        let decreasedBaseDelay = max(baseDelay - 1.0, 0.0)

        return [
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.toggle_auto_restart",
                title: "Recovery Action - \(verb) auto-restart"
            ) { [weak self] in
                guard let self else { return }
                let enabled = self.preferences.effectiveLspAutoRestartEnabled == false
                self.preferences.setLspAutoRestartEnabled(enabled)
                self.setTransientStatusText("LSP auto-restart \(enabled ? "enabled" : "disabled")")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.increase_auto_restart_max_attempts",
                title: "Recovery Action - Increase max attempts to \(increasedMaxAttempts)",
                isEnabled: maxAttempts < 10
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartMaxAttempts(increasedMaxAttempts)
                self.setTransientStatusText("LSP auto-restart max attempts \(increasedMaxAttempts)")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.decrease_auto_restart_max_attempts",
                title: "Recovery Action - Decrease max attempts to \(decreasedMaxAttempts)",
                isEnabled: maxAttempts > 0
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartMaxAttempts(decreasedMaxAttempts)
                self.setTransientStatusText("LSP auto-restart max attempts \(decreasedMaxAttempts)")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.increase_auto_restart_base_delay",
                title: "Recovery Action - Increase base delay to \(Self.formatProjectLspDashboardSeconds(increasedBaseDelay))",
                isEnabled: baseDelay < 3_600.0
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartBaseDelaySeconds(increasedBaseDelay)
                self.setTransientStatusText("LSP auto-restart base delay \(Self.formatProjectLspDashboardSeconds(increasedBaseDelay))")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.decrease_auto_restart_base_delay",
                title: "Recovery Action - Decrease base delay to \(Self.formatProjectLspDashboardSeconds(decreasedBaseDelay))",
                isEnabled: baseDelay > 0.0
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartBaseDelaySeconds(decreasedBaseDelay)
                self.setTransientStatusText("LSP auto-restart base delay \(Self.formatProjectLspDashboardSeconds(decreasedBaseDelay))")
            },
        ]
    }

    private static func projectLspDashboardTrendTitle(
        persistedEntries: [AttoProjectLspProcessHealthLogEntry]
    ) -> String? {
        guard let newest = persistedEntries.map(\.recordedAt).max() else {
            return nil
        }

        let oneHour = projectLspDashboardTrendWindow(
            persistedEntries,
            since: newest.addingTimeInterval(-60 * 60)
        )
        let oneDay = projectLspDashboardTrendWindow(
            persistedEntries,
            since: newest.addingTimeInterval(-24 * 60 * 60)
        )
        return "Trend - persisted logs last 1h \(oneHour.total) failed \(oneHour.failed), last 24h \(oneDay.total) failed \(oneDay.failed)"
    }

    private static func projectLspDashboardTrendWindow(
        _ entries: [AttoProjectLspProcessHealthLogEntry],
        since cutoff: Date
    ) -> (total: Int, failed: Int) {
        let windowEntries = entries.filter { $0.recordedAt >= cutoff }
        let failed = windowEntries.filter { entry in
            entry.availability == "failed" || entry.state == "failed"
        }.count
        return (windowEntries.count, failed)
    }

    private func projectLspDashboardServerGroups(
        healthEvents: [AttoProjectLspProcessHealthEvent],
        persistedEntries: [AttoProjectLspProcessHealthLogEntry],
        lifecycleEvents: [EcuProjectLspLifecycleEvent]
    ) -> [ProjectLspDashboardServerGroup] {
        var groups: [String: ProjectLspDashboardServerGroup] = [:]

        for event in healthEvents {
            let identity = Self.projectLspDashboardServerIdentity(
                serverName: event.serverName,
                serverCommand: event.serverCommand
            )
            var group = groups[identity.key] ?? ProjectLspDashboardServerGroup(identity: identity)
            group.recordHealth(
                availability: event.availability,
                state: event.state,
                processState: event.process.state.rawValue,
                sequence: event.sequence
            )
            groups[identity.key] = group
        }

        for entry in persistedEntries {
            let identity = Self.projectLspDashboardServerIdentity(
                serverName: entry.serverName,
                serverCommand: entry.serverCommand
            )
            var group = groups[identity.key] ?? ProjectLspDashboardServerGroup(identity: identity)
            group.recordPersistedLog(
                availability: entry.availability,
                state: entry.state,
                processState: entry.process.state,
                sequence: entry.sequence
            )
            groups[identity.key] = group
        }

        for event in lifecycleEvents {
            let identity = Self.projectLspDashboardServerIdentity(
                serverName: event.serverKey,
                serverCommand: event.command
            )
            var group = groups[identity.key] ?? ProjectLspDashboardServerGroup(identity: identity)
            group.recordLifecycle(
                status: event.status,
                sequence: event.sequence,
                recoveryPolicy: event.recoveryPolicy
            )
            groups[identity.key] = group
        }

        return groups.values.map { group in
            var group = group
            group.recoveryDisabled = preferences.isLspAutoRestartDisabledForServer(
                serverName: group.serverName,
                serverCommand: group.serverCommand
            )
            group.recoveryMaxAttempts = preferences.effectiveLspAutoRestartMaxAttempts(
                serverName: group.serverName,
                serverCommand: group.serverCommand
            )
            group.recoveryBaseDelaySeconds = preferences.effectiveLspAutoRestartBaseDelaySeconds(
                serverName: group.serverName,
                serverCommand: group.serverCommand
            )
            group.recoveryHasOverride = preferences.hasLspAutoRestartPolicyOverrideForServer(
                serverName: group.serverName,
                serverCommand: group.serverCommand
            )
            return group
        }.sorted { lhs, rhs in
            if lhs.latestSequence != rhs.latestSequence {
                return lhs.latestSequence > rhs.latestSequence
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private struct ProjectLspDashboardServerGroup {
        let displayName: String
        let serverName: String?
        let serverCommand: String?
        var healthEventCount: Int = 0
        var healthFailedCount: Int = 0
        var persistedLogCount: Int = 0
        var persistedFailedCount: Int = 0
        var lifecycleEventCount: Int = 0
        var lifecycleFailedCount: Int = 0
        var latestRecoveryPolicy: EcuProjectLspRecoveryPolicy?
        var latestLifecycleSequence: UInt64 = 0
        var latestProcessState: String?
        var latestSequence: UInt64 = 0
        var recoveryDisabled: Bool = false
        var recoveryMaxAttempts: Int = 0
        var recoveryBaseDelaySeconds: Double = 0.0
        var recoveryHasOverride: Bool = false

        init(identity: ProjectLspDashboardServerIdentity) {
            self.displayName = identity.displayName
            self.serverName = identity.serverName
            self.serverCommand = identity.serverCommand
        }

        mutating func recordHealth(availability: String, state: String, processState: String, sequence: UInt64) {
            healthEventCount += 1
            if Self.isFailed(availability: availability, state: state) {
                healthFailedCount += 1
            }
            recordLatest(processState: processState, sequence: sequence)
        }

        mutating func recordLifecycle(
            status: String,
            sequence: UInt64,
            recoveryPolicy: EcuProjectLspRecoveryPolicy
        ) {
            lifecycleEventCount += 1
            if status == "failed" {
                lifecycleFailedCount += 1
            }
            if sequence >= latestLifecycleSequence {
                latestLifecycleSequence = sequence
                latestRecoveryPolicy = recoveryPolicy
            }
            latestSequence = max(latestSequence, sequence)
        }

        mutating func recordPersistedLog(availability: String, state: String, processState: String, sequence: UInt64) {
            persistedLogCount += 1
            if Self.isFailed(availability: availability, state: state) {
                persistedFailedCount += 1
            }
            recordLatest(processState: processState, sequence: sequence)
        }

        private mutating func recordLatest(processState: String, sequence: UInt64) {
            if sequence >= latestSequence {
                latestSequence = sequence
                latestProcessState = processState
            }
        }

        private static func isFailed(availability: String, state: String) -> Bool {
            availability == "failed" || state == "failed"
        }
    }

    private static func projectLspDashboardServerIdentity(
        serverName: String?,
        serverCommand: String?
    ) -> ProjectLspDashboardServerIdentity {
        let compactServerName = compactProjectLspPanelText(serverName)
        let compactServerCommand = compactProjectLspPanelText(serverCommand)
        let displayName = compactServerName
            ?? compactServerCommand
            ?? "LSP"
        return ProjectLspDashboardServerIdentity(
            key: displayName.lowercased(),
            displayName: displayName,
            serverName: compactServerName ?? (compactServerCommand == nil ? displayName : nil),
            serverCommand: compactServerCommand
        )
    }

    private struct ProjectLspDashboardServerIdentity {
        let key: String
        let displayName: String
        let serverName: String?
        let serverCommand: String?
    }

    private static func projectLspDashboardServerGroupTitle(_ group: ProjectLspDashboardServerGroup) -> String {
        let latestProcess = group.latestProcessState.map { ", latest process \($0)" } ?? ""
        let recovery = group.recoveryDisabled ? "recovery disabled" : "recovery enabled"
        let baseDelay = formatProjectLspDashboardSeconds(group.recoveryBaseDelaySeconds)
        let policySource = group.recoveryHasOverride ? "custom policy" : "global policy"
        let lifecycle = group.lifecycleEventCount > 0
            ? ", lifecycle events \(group.lifecycleEventCount) failed \(group.lifecycleFailedCount)"
            : ""
        let corePolicy = group.latestRecoveryPolicy.map {
            ", core policy \(projectLspRecoveryPolicyDescription($0))"
        } ?? ""
        return "Server - \(group.displayName): health events \(group.healthEventCount) failed \(group.healthFailedCount), persisted logs \(group.persistedLogCount) failed \(group.persistedFailedCount)\(lifecycle), \(recovery), max attempts \(group.recoveryMaxAttempts), base delay \(baseDelay), \(policySource)\(corePolicy)\(latestProcess)"
    }

    private func projectLspDashboardServerRecoveryActionCommands(
        group: ProjectLspDashboardServerGroup,
        index: Int
    ) -> [AttoCommandPaletteCommand] {
        let verb = group.recoveryDisabled ? "Enable" : "Disable"
        let increasedMaxAttempts = min(group.recoveryMaxAttempts + 1, 10)
        let decreasedMaxAttempts = max(group.recoveryMaxAttempts - 1, 0)
        let increasedBaseDelay = min(group.recoveryBaseDelaySeconds + 1.0, 3_600.0)
        let decreasedBaseDelay = max(group.recoveryBaseDelaySeconds - 1.0, 0.0)

        return [
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.server_recovery.\(index)",
                title: "Recovery Action - \(verb) auto-restart for \(group.displayName)"
            ) { [weak self] in
                guard let self else { return }
                let disabled = group.recoveryDisabled == false
                self.preferences.setLspAutoRestartDisabled(
                    disabled,
                    forServerName: group.serverName,
                    serverCommand: group.serverCommand
                )
                self.setTransientStatusText("LSP auto-restart \(disabled ? "disabled" : "enabled") for \(group.displayName)")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.server_recovery.reset_policy.\(index)",
                title: "Recovery Action - Reset recovery policy for \(group.displayName) to global",
                isEnabled: group.recoveryHasOverride
            ) { [weak self] in
                guard let self else { return }
                self.preferences.resetLspAutoRestartPolicy(
                    forServerName: group.serverName,
                    serverCommand: group.serverCommand
                )
                self.setTransientStatusText("LSP auto-restart policy reset for \(group.displayName)")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.server_recovery.increase_max_attempts.\(index)",
                title: "Recovery Action - Increase max attempts for \(group.displayName) to \(increasedMaxAttempts)",
                isEnabled: group.recoveryMaxAttempts < 10
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartMaxAttempts(
                    increasedMaxAttempts,
                    forServerName: group.serverName,
                    serverCommand: group.serverCommand
                )
                self.setTransientStatusText("LSP auto-restart max attempts \(increasedMaxAttempts) for \(group.displayName)")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.server_recovery.decrease_max_attempts.\(index)",
                title: "Recovery Action - Decrease max attempts for \(group.displayName) to \(decreasedMaxAttempts)",
                isEnabled: group.recoveryMaxAttempts > 0
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartMaxAttempts(
                    decreasedMaxAttempts,
                    forServerName: group.serverName,
                    serverCommand: group.serverCommand
                )
                self.setTransientStatusText("LSP auto-restart max attempts \(decreasedMaxAttempts) for \(group.displayName)")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.server_recovery.increase_base_delay.\(index)",
                title: "Recovery Action - Increase base delay for \(group.displayName) to \(Self.formatProjectLspDashboardSeconds(increasedBaseDelay))",
                isEnabled: group.recoveryBaseDelaySeconds < 3_600.0
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartBaseDelaySeconds(
                    increasedBaseDelay,
                    forServerName: group.serverName,
                    serverCommand: group.serverCommand
                )
                self.setTransientStatusText("LSP auto-restart base delay \(Self.formatProjectLspDashboardSeconds(increasedBaseDelay)) for \(group.displayName)")
            },
            AttoCommandPaletteCommand(
                id: "lsp.project_dashboard.server_recovery.decrease_base_delay.\(index)",
                title: "Recovery Action - Decrease base delay for \(group.displayName) to \(Self.formatProjectLspDashboardSeconds(decreasedBaseDelay))",
                isEnabled: group.recoveryBaseDelaySeconds > 0.0
            ) { [weak self] in
                guard let self else { return }
                self.preferences.setLspAutoRestartBaseDelaySeconds(
                    decreasedBaseDelay,
                    forServerName: group.serverName,
                    serverCommand: group.serverCommand
                )
                self.setTransientStatusText("LSP auto-restart base delay \(Self.formatProjectLspDashboardSeconds(decreasedBaseDelay)) for \(group.displayName)")
            },
        ]
    }

    private static func formatProjectLspDashboardSeconds(_ seconds: Double) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))s"
        }
        return "\(seconds)s"
    }

    @discardableResult
    func clearProjectLspProcessHealthLog(
        confirmBeforeClearing: Bool = true,
        confirmationProvider: (() -> Bool)? = nil
    ) -> Bool {
        guard projectLspProcessHealthLogStore.loadRecent(
            workspaceRootURL: workspaceRootURL,
            limit: 1
        ).isEmpty == false else {
            NSSound.beep()
            return false
        }
        if confirmBeforeClearing {
            let confirmed = confirmationProvider?() ?? Self.confirmProjectLspProcessHealthLogClear()
            guard confirmed else {
                return false
            }
        }

        do {
            let removed = try projectLspProcessHealthLogStore.clear(workspaceRootURL: workspaceRootURL)
            if removed == 0 {
                NSSound.beep()
                return false
            }
            projectLspProcessHealthLogController?.hide()
            projectLspProcessHealthLogController = nil
            return true
        } catch {
            NSLog("AttoEditor: failed to clear project LSP process health log: %@", String(describing: error))
            NSSound.beep()
            return false
        }
    }

    private static func confirmProjectLspProcessHealthLogClear() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear Project LSP Process Health Log?"
        alert.informativeText = "This removes persisted process health log entries for the current workspace. Other workspace logs are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @discardableResult
    func exportProjectLspProcessHealthLog() -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Export process health log entries for the current workspace."
        panel.directoryURL = workspaceRootURL
        panel.nameFieldStringValue = Self.projectLspProcessHealthLogExportFileName(workspaceRootURL: workspaceRootURL)

        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else {
            return false
        }
        return exportProjectLspProcessHealthLog(to: url)
    }

    @discardableResult
    func exportProjectLspProcessHealthLog(to destinationURL: URL) -> Bool {
        do {
            let exportedCount = try projectLspProcessHealthLogStore.exportJSONL(
                workspaceRootURL: workspaceRootURL,
                to: destinationURL.standardizedFileURL
            )
            if exportedCount == 0 {
                NSSound.beep()
                return false
            }
            return true
        } catch {
            NSLog("AttoEditor: failed to export project LSP process health log: %@", String(describing: error))
            NSSound.beep()
            return false
        }
    }

    static func projectLspStatusEventTitle(_ event: AttoProjectLspPanelErrorEvent) -> String {
        let source = event.source.rawValue.capitalized
        let scope = projectLspEventScope(tabId: event.tabId, viewIndex: event.viewIndex)
        let sourceSequence = event.sourceSequence > 0 ? " #\(event.sourceSequence)" : ""
        return "\(source)\(sourceSequence) [\(scope)] \(event.message)"
    }

    static func projectLspProcessHealthEventTitle(_ event: AttoProjectLspProcessHealthEvent) -> String {
        projectLspProcessHealthTitle(
            sourceSequence: event.sourceSequence,
            tabId: event.tabId,
            viewIndex: event.viewIndex,
            serverName: event.serverName,
            serverCommand: event.serverCommand,
            availability: event.availability,
            state: event.state,
            detail: event.detail,
            processState: event.process.state.rawValue,
            pid: event.process.pid,
            exitCode: event.process.exitCode,
            signal: event.process.signal,
            stderrTail: event.process.stderrTail
        )
    }

    static func projectLspProcessHealthLogEntryTitle(_ entry: AttoProjectLspProcessHealthLogEntry) -> String {
        projectLspProcessHealthTitle(
            sourceSequence: entry.sourceSequence,
            tabId: entry.tabId,
            viewIndex: entry.viewIndex,
            serverName: entry.serverName,
            serverCommand: entry.serverCommand,
            availability: entry.availability,
            state: entry.state,
            detail: entry.detail,
            processState: entry.process.state,
            pid: entry.process.pid,
            exitCode: entry.process.exitCode,
            signal: entry.process.signal,
            stderrTail: entry.process.stderrTail
        )
    }

    static func projectLspProcessHealthTitle(
        sourceSequence: UInt64,
        tabId: UInt64?,
        viewIndex: Int?,
        serverName: String?,
        serverCommand: String?,
        availability: String,
        state: String,
        detail: String?,
        processState: String,
        pid: UInt32?,
        exitCode: Int32?,
        signal: Int32?,
        stderrTail: String?
    ) -> String {
        let scope = projectLspEventScope(tabId: tabId, viewIndex: viewIndex)
        let sourceSequenceLabel = sourceSequence > 0 ? " #\(sourceSequence)" : ""
        let server = serverName ?? serverCommand ?? "LSP"
        var processParts = [processState]
        if let pid {
            processParts.append("pid \(pid)")
        }
        if let exitCode {
            processParts.append("exit \(exitCode)")
        }
        if let signal {
            processParts.append("signal \(signal)")
        }

        var detailParts: [String] = []
        if let detail = compactProjectLspPanelText(detail) {
            detailParts.append(detail)
        }
        if let stderr = compactProjectLspPanelText(stderrTail),
           detailParts.contains(where: { $0.contains(stderr) }) == false {
            detailParts.append("stderr: \(stderr)")
        }

        let processSummary = processParts.joined(separator: " ")
        var title = "Health\(sourceSequenceLabel) [\(scope)] \(server) \(availability)/\(state), process \(processSummary)"
        if detailParts.isEmpty == false {
            title += " - \(detailParts.joined(separator: "; "))"
        }
        return title
    }

    static func projectLspEventScope(tabId: UInt64?, viewIndex: Int?) -> String {
        if let tabId {
            if let viewIndex {
                return "tab \(tabId), view \(viewIndex + 1)"
            }
            return "tab \(tabId)"
        }
        return "project"
    }

    static func compactProjectLspPanelText(_ text: String?) -> String? {
        let compacted = text?
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let compacted, compacted.isEmpty == false else {
            return nil
        }
        return compacted
    }

    private static func projectLspProcessHealthLogExportFileName(workspaceRootURL: URL) -> String {
        let rawName = workspaceRootURL.lastPathComponent.isEmpty ? "workspace" : workspaceRootURL.lastPathComponent
        let safeName = rawName
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "atto-lsp-process-health-\(safeName).jsonl"
    }

    @discardableResult
    func recordProjectLspStatusFailure(
        sourceSequence: UInt64,
        tabId: UInt64?,
        viewIndex: Int?,
        viewId: UInt64?,
        status: EcuLspStatusSnapshot?
    ) -> AttoProjectLspPanelErrorEvent? {
        guard let status,
              status.availability == .failed || status.state == .failed
        else {
            return nil
        }

        let display = AttoLspStatusFormatter.display(status: status, fallbackEnabled: false)
        let message = Self.projectLspPanelErrorMessage(
            title: display.text,
            status: status.state.rawValue,
            errorMessage: Self.projectLspStatusFailureDetail(status: status, display: display)
        )
        return projectLspPanelErrorEventStore.record(
            source: .status,
            sourceSequence: sourceSequence,
            tabId: tabId,
            viewIndex: viewIndex,
            viewId: viewId,
            family: "lsp",
            title: display.text,
            slot: "lsp_status",
            method: "lsp/status",
            requestId: 0,
            status: status.state.rawValue,
            message: message
        )
    }

    @discardableResult
    func recordProjectLspProcessHealth(
        sourceSequence: UInt64,
        tabId: UInt64?,
        viewIndex: Int?,
        viewId: UInt64?,
        status: EcuLspStatusSnapshot?
    ) -> AttoProjectLspProcessHealthEvent? {
        guard let status, let process = status.process else {
            return nil
        }

        let display = AttoLspStatusFormatter.display(status: status, fallbackEnabled: false)
        let detail = Self.projectLspStatusFailureDetail(status: status, display: display)
            ?? display.failureDetail
            ?? status.detail

        let event = projectLspProcessHealthEventStore.record(
            sourceSequence: sourceSequence,
            tabId: tabId,
            viewIndex: viewIndex,
            viewId: viewId,
            serverName: status.server?.name,
            serverCommand: status.server?.command,
            availability: status.availability.rawValue,
            state: status.state.rawValue,
            detail: detail,
            process: process
        )
        do {
            try projectLspProcessHealthLogStore.append(
                event: event,
                workspaceRootURL: workspaceRootURL
            )
        } catch {
            NSLog("AttoEditor: failed to persist project LSP process health event: %@", String(describing: error))
        }
        attemptProjectLspAutoRestart(tabId: tabId, status: status)
        return event
    }

    @discardableResult
    func recordProjectLspPanelError(
        source: AttoProjectLspPanelErrorEvent.Source,
        sourceSequence: UInt64,
        tabId: UInt64?,
        viewIndex: Int?,
        viewId: UInt64?,
        family: String,
        title: String,
        slot: String,
        method: String,
        requestId: UInt64,
        status: String,
        errorMessage: String?
    ) -> AttoProjectLspPanelErrorEvent? {
        guard Self.isProjectLspPanelErrorStatus(status),
              let panelFamily = Self.projectLspPanelFamily(family: family, slot: slot)
        else {
            return nil
        }

        let message = Self.projectLspPanelErrorMessage(title: title, status: status, errorMessage: errorMessage)
        let event = projectLspPanelErrorEventStore.record(
            source: source,
            sourceSequence: sourceSequence,
            tabId: tabId,
            viewIndex: viewIndex,
            viewId: viewId,
            family: family,
            title: title,
            slot: slot,
            method: method,
            requestId: requestId,
            status: status,
            message: message
        )

        switch panelFamily {
        case .locations:
            if let entry = lspLocationResultStore.updateCurrentState(.error(message: message)) {
                lspLocationPanelController?.update(entry: entry)
            }
        case .symbols:
            if let entry = lspSymbolResultStore.updateCurrentState(.error(message: message)) {
                lspSymbolPanelController?.update(entry: entry)
            }
        }

        return event
    }

    static func projectLspStatusFailureDetail(
        status: EcuLspStatusSnapshot,
        display: AttoLspStatusFormatter.Display
    ) -> String? {
        var parts: [String] = []
        if let detail = (display.failureDetail ?? status.detail)?.trimmingCharacters(in: .whitespacesAndNewlines),
           detail.isEmpty == false
        {
            parts.append(detail)
        }
        if let stderrTail = status.process?.stderrTail?.trimmingCharacters(in: .whitespacesAndNewlines),
           stderrTail.isEmpty == false
        {
            parts.append("stderr:\n\(stderrTail)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func isProjectLspPanelErrorStatus(_ status: String) -> Bool {
        switch EcuLspRequestStatus(rawValue: status) {
        case .error, .timeout:
            return true
        case .pending, .success, .empty, .stale, .mismatched, .canceled, .unknown(_):
            return EcuLspResultStatus(rawValue: status) == .error
        }
    }

    static func projectLspPanelFamily(family: String, slot: String) -> ProjectLspPanelFamily? {
        if family == "locations" {
            return .locations
        }
        if family == "symbols" {
            return .symbols
        }

        switch slot {
        case "definition",
             "declaration",
             "type_definition",
             "implementation",
             "references":
            return .locations
        case "document_symbols",
             "workspace_symbols":
            return .symbols
        default:
            return nil
        }
    }

    static func projectLspPanelErrorMessage(
        title: String,
        status: String,
        errorMessage: String?
    ) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = trimmedTitle.isEmpty ? "LSP request" : trimmedTitle
        if let errorMessage {
            let trimmedMessage = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMessage.isEmpty == false {
                return "\(fallbackTitle): \(trimmedMessage)"
            }
        }
        return "\(fallbackTitle): \(status)"
    }

    func clearActiveDiagnosticsStaleIfDiagnosticsChanged(
        for tab: AttoEditorTab,
        diagnostics: [EcuDiagnostic]
    ) {
        if let previous = activeDiagnosticsBaselinesByTabID[tab.id], previous != diagnostics {
            activeDiagnosticsStaleReasonsByTabID.removeValue(forKey: tab.id)
        }
        activeDiagnosticsBaselinesByTabID[tab.id] = diagnostics
    }

    func clearDiagnosticsLifecycleState(forTabID tabID: UUID) {
        activeDiagnosticsTextFingerprintsByTabID.removeValue(forKey: tabID)
        activeDiagnosticsBaselinesByTabID.removeValue(forKey: tabID)
        activeDiagnosticsStaleReasonsByTabID.removeValue(forKey: tabID)
    }

    func recordLspResultLifecycleEvent<Snapshot>(
        _ entry: AttoLspResultLifecycleEntry<Snapshot>,
        payload: AttoLspResultLifecycleEvent.Payload
    ) {
        lspResultEventStream.record(
            family: entry.family,
            title: entry.title,
            recordedAt: entry.recordedAt,
            sourceSequence: entry.sequence,
            owner: entry.owner,
            payload: payload
        )
    }

    func recordActiveDiagnosticsLifecycle(
        _ snapshot: AttoUnifiedDiagnosticsSnapshot,
        for tab: AttoEditorTab
    ) {
        let documentURL = projectedFileURL(for: tab)
        let lifecycleSnapshot = AttoDiagnosticsLifecycleSnapshot(
            scope: .activeTab(tabID: tab.id, fileURL: documentURL.standardizedFileURL),
            problems: snapshot.problems,
            markerProjections: snapshot.markerProjections,
            statusText: snapshot.problemsStatusText,
            staleReason: activeDiagnosticsStaleReasonsByTabID[tab.id]
        )
        guard let entry = diagnosticsLifecycleStore.recordIfChanged(
            lifecycleSnapshot,
            family: "diagnostics.active",
            title: documentURL.lastPathComponent,
            owner: lspDocumentResultOwner(for: tab)
        ) else { return }
        recordLspResultLifecycleEvent(
            entry,
            payload: .diagnostics(
                scope: lifecycleSnapshot.scope,
                problemCount: lifecycleSnapshot.problems.count,
                markerCount: lifecycleSnapshot.markerProjections.count,
                isStale: lifecycleSnapshot.isStale,
                staleReason: lifecycleSnapshot.staleReason
            )
        )
    }

    func recordWorkspaceDiagnosticsLifecycle(
        problems: [AttoUnifiedDiagnosticProblem]
    ) {
        let statusText: String? = {
            let count = problems.count
            guard count > 0 else { return nil }
            return count == 1 ? "Problems: 1" : "Problems: \(count)"
        }()
        let lifecycleSnapshot = AttoDiagnosticsLifecycleSnapshot(
            scope: .workspace,
            problems: problems,
            markerProjections: [],
            statusText: statusText,
            staleReason: workspaceDiagnosticsStaleReason
        )
        guard let entry = diagnosticsLifecycleStore.recordIfChanged(
            lifecycleSnapshot,
            family: "diagnostics.workspace",
            title: "Workspace Problems",
            owner: lspWorkspaceResultOwner()
        ) else { return }
        recordLspResultLifecycleEvent(
            entry,
            payload: .diagnostics(
                scope: lifecycleSnapshot.scope,
                problemCount: lifecycleSnapshot.problems.count,
                markerCount: lifecycleSnapshot.markerProjections.count,
                isStale: lifecycleSnapshot.isStale,
                staleReason: lifecycleSnapshot.staleReason
            )
        )
    }

    func diagnosticsLifecycleEvents(
        after sequence: UInt64
    ) -> [AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>] {
        diagnosticsLifecycleStore.entries(after: sequence)
    }

    func updateWorkspaceDiagnosticMarkersForOpenTabs() {
        for tab in tabs {
            updateDiagnosticMarkers(for: tab, includeActiveDiagnostics: tab.id == activeTab?.id)
        }
    }

    func minimapMarkerKind(for severity: EcuDiagnosticSeverity?) -> EditorCoreSkiaMinimapMarker.Kind {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information:
            return .information
        case .hint, .none:
            return .hint
        }
    }

    func gutterMarkerKind(for severity: EcuDiagnosticSeverity?) -> EditorCoreSkiaGutterDiagnosticMarker.Kind {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information:
            return .information
        case .hint, .none:
            return .hint
        }
    }

    func setTransientStatusText(_ text: String?) {
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = normalized?.isEmpty == false ? normalized : nil
        guard transientStatusText != next else { return }
        transientStatusText = next
        updateStatusBar()
    }

    func setSyntaxLanguageForActiveTab(languageId: String?) {
        guard let tab = activeTab else {
            NSSound.beep()
            return
        }

        // "Plain Text" => disable all syntax engines.
        if languageId == nil {
            stopLspSessionForLanguageChange(tab)
            tab.editCore.editor.treeSitterDisable()
            tab.editCore.editor.sublimeDisable()
            tab.lspServerConfig = nil
            tab.suppressesAutomaticLspStart = true
            syncProjectLspServerConfigsToCore()
            tab.syntaxLanguageId = nil
            tab.languageSupportSource = .plainText
            tab.languageFallbackReasons = []
            syncCoreTabLanguageId(nil, for: tab)
            applyDocumentLanguageConfiguration(for: tab)
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

        if let reason = tab.languageProcessingDisabledReason {
            setTransientStatusText("Language mode unavailable: \(reason)")
            NSSound.beep()
            return
        }

        // Force Tree-sitter with an explicit language id.
        loadTreeSitterRegistryCacheIfNeeded()
        if let registryJSON = treeSitterRegistryJSON {
            // Best-effort (each editor view owns its own registry state).
            try? tab.editCore.editor.treeSitterSetRegistryJSON(registryJSON)
        }

        stopLspSessionForLanguageChange(tab)
        tab.editCore.editor.sublimeDisable()
        tab.lspServerConfig = nil
        tab.suppressesAutomaticLspStart = true
        syncProjectLspServerConfigsToCore()

        do {
            try tab.editCore.editor.treeSitterEnableLanguage(lang)
            tab.syntaxLanguageId = lang
            tab.languageSupportSource = .treeSitter
            tab.languageFallbackReasons = []
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

    func stopLspSessionForLanguageChange(_ tab: AttoEditorTab) {
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else { return }
        let documentURL = projectedFileURL(for: tab)
        let config = tab.lspServerConfig
        let stopPlanEntry = config.flatMap { config in
            projectLspStopPlanDecision(
                for: tab,
                documentURL: documentURL,
                config: config
            ).planEntry
        }
        let stopAttemptId: UInt64? = {
            guard let config else { return nil }
            return recordProjectLspStopOutcome(
                for: tab,
                documentURL: documentURL,
                config: config,
                trigger: "language_change",
                status: "requested",
                planEntry: stopPlanEntry
            )
        }()
        tab.editCore.editor.lspDisable()
        if let config {
            recordProjectLspStopOutcome(
                for: tab,
                documentURL: documentURL,
                config: config,
                trigger: "language_change",
                status: "stopped",
                attemptId: stopAttemptId,
                planEntry: stopPlanEntry
            )
        }
    }

    // MARK: - Navigation

    func navigate(tab: AttoEditorTab, to location: AttoCommandLine.FileLocation) {
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

    static func parseGoToLineTarget(_ raw: String) -> GoToLineTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let parts = trimmed
            .split(omittingEmptySubsequences: false) { ch in ch == ":" || ch == "," }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 1 || parts.count == 2 else { return nil }
        guard let line1 = Int(parts[0]), line1 > 0 else { return nil }

        let column1: Int
        if parts.count == 2 {
            guard let parsedColumn = Int(parts[1]), parsedColumn > 0 else { return nil }
            column1 = parsedColumn
        } else {
            column1 = 1
        }

        return GoToLineTarget(line1: line1, column1: column1)
    }

    @discardableResult
    func goToLineInActiveTab(input: String) -> Bool {
        guard let target = Self.parseGoToLineTarget(input) else {
            NSSound.beep()
            return false
        }
        return goToLineInActiveTab(line1: target.line1, column1: target.column1)
    }

    @discardableResult
    func goToLineInActiveTab(line1: Int, column1: Int = 1) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let line0 = UInt32(clamping: max(1, line1) - 1)
        let column0 = UInt32(clamping: max(1, column1) - 1)
        do {
            _ = try tab.editCore.editor.moveTo(line: line0, column: column0)
            try? tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.layoutSubtreeIfNeeded()
            tab.editCore.editorView.needsDisplay = true
            tab.editCore.needsDisplay = true
            handleTabDidChangeSelection(tabID: tab.id, causedByTextMutation: false)
            updateStatusBar()
            tab.editCore.focusEditor()
            return true
        } catch {
            NSSound.beep()
            NSLog("AttoEditor: go to line failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func promptGoToLineInActiveTab(initialInput: String = "") -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initialInput
        field.placeholderString = "Line or line:column"
        field.selectText(nil)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter a 1-based line number, optionally followed by :column."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        return goToLineInActiveTab(input: field.stringValue)
    }

    static func charOffsetForLineColumn1(text: String, line1: Int, column1: Int) -> UInt32 {
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
}
