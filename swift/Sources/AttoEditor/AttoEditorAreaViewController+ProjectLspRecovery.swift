import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
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
        guard process.state == .exited,
              status.availability == .failed || status.state == .failed
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

        let policy = projectLspRecoveryPolicy(
            status: status,
            config: config,
            planEntry: planDecision.planEntry
        )
        let maxAttempts = Int(policy.maxAttempts)
        let baseDelaySeconds = Self.projectLspRecoveryBaseDelaySeconds(policy.baseDelayMillis)
        guard policy.enabled,
              maxAttempts > 0,
              (currentState?.attempts ?? 0) < maxAttempts,
              currentState.map({ now >= $0.nextAllowedAt }) ?? true
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
        let restartAttemptId = recordProjectLspRestartOutcome(
            for: target.tab,
            documentURL: target.fileURL,
            config: config,
            trigger: "auto_restart",
            status: "requested",
            planEntry: planDecision.planEntry
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
                attemptId: restartAttemptId,
                planEntry: planDecision.planEntry
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
                attemptId: restartAttemptId,
                planEntry: planDecision.planEntry
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

    private func projectLspRecoveryPolicy(
        status: EcuLspStatusSnapshot,
        config: AttoLspServerLaunchConfig,
        planEntry: EcuProjectLspRestartPlanEntry?
    ) -> EcuProjectLspRecoveryPolicy {
        let planPolicy = planEntry?.recoveryPolicy ?? projectLspRecoveryPolicy(for: config)
        guard preferences.hasLspAutoRestartPolicyOverrideForServer(
            serverName: status.server?.name,
            serverCommand: nil
        ) else {
            return planPolicy
        }

        return projectLspRecoveryPolicy(
            serverName: status.server?.name,
            serverCommand: status.server?.command ?? config.command
        )
    }

    private static func projectLspAutoRestartDelay(
        forAttempt attempt: Int,
        baseDelaySeconds: TimeInterval
    ) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        return baseDelaySeconds * pow(2, Double(exponent))
    }
}
