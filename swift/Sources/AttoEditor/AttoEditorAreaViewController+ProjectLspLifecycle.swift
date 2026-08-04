import AppKit
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Event Projection

    func drainCoreProjectLspLifecycleEvents(_ coreDocuments: MultiDocumentEditorUI) throws {
        let snapshot = try coreDocuments.projectLspLifecycleEvents(after: coreProjectLspLifecycleEventCursor)
        coreProjectLspLifecycleEventCursor = snapshot.latestSequence
        projectLspLifecycleEventStore.record(contentsOf: snapshot.events)
    }

    static func projectLspLifecycleEventTitle(_ event: EcuProjectLspLifecycleEvent) -> String {
        let scope = projectLspEventScope(
            tabId: event.tabId,
            viewIndex: Int(event.activeViewIndex)
        )
        let server = event.serverKey.isEmpty ? event.command : event.serverKey
        let sequence = event.sequence > 0 ? " #\(event.sequence)" : ""
        var title = "Lifecycle\(sequence) [\(scope)] \(event.operation) \(event.status) \(server)"

        var details: [String] = []
        if event.languageId.isEmpty == false {
            details.append("language \(event.languageId)")
        }
        if event.trigger.isEmpty == false {
            details.append("trigger \(event.trigger)")
        }
        if let attemptId = event.attemptId {
            details.append("attempt #\(attemptId)")
        }
        details.append("session \(projectLspSessionPolicyDescription(event.sessionPolicy))")
        details.append("recovery \(projectLspRecoveryPolicyDescription(event.recoveryPolicy))")
        if let error = compactProjectLspPanelText(event.errorMessage) {
            details.append(error)
        }
        if details.isEmpty == false {
            title += " - \(details.joined(separator: "; "))"
        }
        return title
    }

    // MARK: - Execution

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
                tab.languageFallbackReasons = lspSupport.fallbackReasons
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
        guard let coreDocuments else {
            NSLog("AttoEditor: project LSP start requires a core start plan")
            return []
        }

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
            return []
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
        let action = AttoProjectLspLifecycleAction.start(
            tab: target.candidate.tab,
            documentURL: target.candidate.fileURL,
            config: target.candidate.config,
            trigger: "auto_start",
            planEntry: target.planEntry,
            fallbackWorkspaceRoots: projectLspWorkspaceRootURIs(),
            fallbackRecoveryPolicy: projectLspRecoveryPolicy(for: target.candidate.config)
        )
        return recordProjectLspLifecycleAction(
            action,
            status: status,
            errorMessage: errorMessage,
            attemptId: attemptId
        )
    }

    @discardableResult
    private func recordProjectLspLifecycleAction(
        _ action: AttoProjectLspLifecycleAction,
        status: String,
        errorMessage: String? = nil,
        attemptId: UInt64? = nil
    ) -> UInt64? {
        guard let coreDocuments,
              let outcome = action.outcome(
                  status: status,
                  attemptId: attemptId,
                  errorMessage: errorMessage
              )
        else {
            return nil
        }

        do {
            try coreDocuments.recordProjectLspStartOutcome(outcome)
            if let recordedAttemptId = outcome.attemptId {
                return recordedAttemptId
            }
            if Self.isProjectLspRequestedStatus(status) {
                return try? coreDocuments.projectLspLifecycleEventsLatestSequence()
            }
        } catch {
            NSLog(
                "AttoEditor: failed to record project LSP %@ outcome: %@",
                action.operation,
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
        attemptId: UInt64? = nil,
        planEntry: EcuProjectLspRestartPlanEntry? = nil
    ) -> UInt64? {
        let action = AttoProjectLspLifecycleAction.restart(
            tab: tab,
            documentURL: documentURL,
            config: config,
            trigger: trigger,
            planEntry: planEntry,
            fallbackWorkspaceRoots: projectLspWorkspaceRootURIs(),
            fallbackRecoveryPolicy: projectLspRecoveryPolicy(for: config)
        )
        return recordProjectLspLifecycleAction(
            action,
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
        attemptId: UInt64? = nil,
        planEntry: EcuProjectLspStopPlanEntry? = nil
    ) -> UInt64? {
        let action = AttoProjectLspLifecycleAction.stop(
            tab: tab,
            documentURL: documentURL,
            config: config,
            trigger: trigger,
            planEntry: planEntry,
            fallbackWorkspaceRoots: projectLspWorkspaceRootURIs(),
            fallbackRecoveryPolicy: projectLspRecoveryPolicy(for: config)
        )
        return recordProjectLspLifecycleAction(
            action,
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
        let stopPlanEntry: EcuProjectLspStopPlanEntry?
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
            stopPlanEntry = planDecision.planEntry
            shutdownAttemptId = recordProjectLspStopOutcome(
                for: tab,
                documentURL: documentURL,
                config: config,
                trigger: "manual_shutdown",
                status: "requested",
                planEntry: stopPlanEntry
            )
        } else {
            stopPlanEntry = nil
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
                        attemptId: shutdownAttemptId,
                        planEntry: stopPlanEntry
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
                    attemptId: shutdownAttemptId,
                    planEntry: stopPlanEntry
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
                    attemptId: shutdownAttemptId,
                    planEntry: stopPlanEntry
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
            status: "requested",
            planEntry: planDecision.planEntry
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
                attemptId: restartAttemptId,
                planEntry: planDecision.planEntry
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
                attemptId: restartAttemptId,
                planEntry: planDecision.planEntry
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
        tab.languageFallbackReasons = lspSupport.fallbackReasons
        tab.lspServerConfig = config
        tab.suppressesAutomaticLspStart = false
        syncProjectLspServerConfigsToCore()
        applyLanguageConfiguration(for: tab)
        tab.editCore.editorView.kickProcessingPoll()
        tab.editCore.editorView.needsDisplay = true
    }
}
