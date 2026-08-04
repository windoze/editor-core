import AppKit
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    private typealias ProjectLspRestartCandidate = (
        tab: AttoEditorTab,
        fileURL: URL,
        config: AttoLspServerLaunchConfig,
        coreTabID: UInt64?
    )

    @discardableResult
    func restartProjectLspServers() -> Bool {
        let restartCandidates = coreProjectedTabsForWorkspaceLifecycle().compactMap {
            projected -> ProjectLspRestartCandidate? in
            guard let config = projected.tab.lspServerConfig else {
                return nil
            }
            syncCoreTabLanguageId(config.languageId, for: projected.tab)
            return (
                tab: projected.tab,
                fileURL: projected.fileURL,
                config: config,
                coreTabID: projected.tab.coreTabID
            )
        }
        let restartTargets = projectLspRestartTargets(for: restartCandidates)

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
            let restartAttemptId = recordProjectLspRestartOutcome(
                for: target.candidate.tab,
                documentURL: target.candidate.fileURL,
                config: target.candidate.config,
                trigger: "project_restart",
                status: "requested",
                planEntry: target.planEntry
            )
            do {
                try restartLspServer(
                    for: target.candidate.tab,
                    documentURL: target.candidate.fileURL,
                    config: target.candidate.config,
                    rootURI: projectLspRestartPlanRootURI(target.planEntry)
                )
                recordProjectLspRestartOutcome(
                    for: target.candidate.tab,
                    documentURL: target.candidate.fileURL,
                    config: target.candidate.config,
                    trigger: "project_restart",
                    status: "started",
                    attemptId: restartAttemptId,
                    planEntry: target.planEntry
                )
                restartedCount += 1
            } catch {
                target.candidate.tab.lspServerConfig = target.candidate.config
                recordProjectLspRestartOutcome(
                    for: target.candidate.tab,
                    documentURL: target.candidate.fileURL,
                    config: target.candidate.config,
                    trigger: "project_restart",
                    status: "failed",
                    errorMessage: String(describing: error),
                    attemptId: restartAttemptId,
                    planEntry: target.planEntry
                )
                failures.append("\(target.candidate.fileURL.lastPathComponent): \(error)")
            }
        }
        syncProjectLspServerConfigsToCore()

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

    private func projectLspRestartTargets(
        for candidates: [ProjectLspRestartCandidate]
    ) -> [(candidate: ProjectLspRestartCandidate, planEntry: EcuProjectLspRestartPlanEntry?)] {
        guard candidates.isEmpty == false else { return [] }
        let fallbackTargets = candidates.map { (candidate: $0, planEntry: nil as EcuProjectLspRestartPlanEntry?) }
        guard let coreDocuments else { return fallbackTargets }

        syncProjectLspServerConfigsToCore()
        do {
            let plan = try coreDocuments.projectLspRestartPlan()
            var candidatesByTabID: [UInt64: ProjectLspRestartCandidate] = [:]
            for candidate in candidates {
                guard let coreTabID = candidate.coreTabID else { continue }
                candidatesByTabID[coreTabID] = candidate
            }

            return plan.compactMap { entry in
                guard let candidate = candidatesByTabID[entry.tabId],
                      projectLspRestartPlanEntry(entry, matches: candidate)
                else {
                    return nil
                }
                return (candidate: candidate, planEntry: entry)
            }
        } catch {
            NSLog("AttoEditor: failed to build project LSP restart plan: %@", String(describing: error))
            return fallbackTargets
        }
    }

    func projectLspRestartPlanDecision(
        for tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig
    ) -> (allowed: Bool, planEntry: EcuProjectLspRestartPlanEntry?) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else {
            return (allowed: true, planEntry: nil)
        }

        do {
            let snapshot = try coreDocuments.snapshot()
            guard snapshot.tabs.contains(where: { $0.id == coreTabID }) else {
                return (allowed: false, planEntry: nil)
            }
        } catch {
            NSLog("AttoEditor: failed to inspect core tabs for project LSP restart plan: %@", String(describing: error))
            return (allowed: true, planEntry: nil)
        }

        syncCoreTabLanguageId(config.languageId, for: tab)
        syncProjectLspServerConfigsToCore()
        let candidate: ProjectLspRestartCandidate = (
            tab: tab,
            fileURL: documentURL,
            config: config,
            coreTabID: coreTabID
        )

        do {
            let plan = try coreDocuments.projectLspRestartPlan()
            guard let entry = plan.first(where: { entry in
                entry.tabId == coreTabID && projectLspRestartPlanEntry(entry, matches: candidate)
            }) else {
                return (allowed: false, planEntry: nil)
            }
            return (allowed: true, planEntry: entry)
        } catch {
            NSLog("AttoEditor: failed to build project LSP restart plan: %@", String(describing: error))
            return (allowed: true, planEntry: nil)
        }
    }

    private func projectLspRestartPlanEntry(
        _ entry: EcuProjectLspRestartPlanEntry,
        matches candidate: ProjectLspRestartCandidate
    ) -> Bool {
        entry.documentURI == candidate.fileURL.standardizedFileURL.absoluteString
            && entry.serverKey.lowercased() == Self.projectLspServerConfigKey(for: candidate.config)
    }

    func projectLspRestartPlanRootURI(_ entry: EcuProjectLspRestartPlanEntry?) -> String? {
        entry?.workspaceRoots.first { root in
            root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }
}
