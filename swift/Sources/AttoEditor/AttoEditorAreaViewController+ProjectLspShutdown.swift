import AppKit
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    private typealias ProjectLspShutdownCandidate = (
        tab: AttoEditorTab,
        fileURL: URL,
        config: AttoLspServerLaunchConfig,
        coreTabID: UInt64?
    )

    @discardableResult
    func shutdownProjectLspServers() -> Bool {
        let shutdownCandidates = coreProjectedTabsForWorkspaceLifecycle().compactMap {
            projected -> ProjectLspShutdownCandidate? in
            guard let config = projected.tab.lspServerConfig else {
                return nil
            }
            guard (try? projected.tab.editCore.editor.lspIsEnabled()) == true else {
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
        let shutdownTargets = projectLspShutdownTargets(for: shutdownCandidates)

        guard shutdownTargets.isEmpty == false else {
            NSSound.beep()
            if let tab = activeTab {
                presentLspResultFeedback(
                    AttoLspResultFeedback.unavailable(
                        .serverShutdown,
                        reason: "No open document has a running configured LSP server."
                    ),
                    in: tab.editCore.editorView
                )
            }
            return false
        }

        var shutdownCount = 0
        var failures: [String] = []

        for target in shutdownTargets {
            let shutdownAttemptId = recordProjectLspStopOutcome(
                for: target.tab,
                documentURL: target.fileURL,
                config: target.config,
                trigger: "project_shutdown",
                status: "requested"
            )
            do {
                let didShutdown = try target.tab.editCore.editor.lspShutdown()
                guard didShutdown else {
                    recordProjectLspStopOutcome(
                        for: target.tab,
                        documentURL: target.fileURL,
                        config: target.config,
                        trigger: "project_shutdown",
                        status: "failed",
                        errorMessage: "No running LSP server was available to shut down.",
                        attemptId: shutdownAttemptId
                    )
                    failures.append("\(target.fileURL.lastPathComponent): no running LSP server")
                    continue
                }

                recordProjectLspStopOutcome(
                    for: target.tab,
                    documentURL: target.fileURL,
                    config: target.config,
                    trigger: "project_shutdown",
                    status: "stopped",
                    attemptId: shutdownAttemptId
                )
                markLspServerShutdown(for: target.tab)
                target.tab.editCore.editorView.needsDisplay = true
                shutdownCount += 1
            } catch {
                recordProjectLspStopOutcome(
                    for: target.tab,
                    documentURL: target.fileURL,
                    config: target.config,
                    trigger: "project_shutdown",
                    status: "failed",
                    errorMessage: String(describing: error),
                    attemptId: shutdownAttemptId
                )
                failures.append("\(target.fileURL.lastPathComponent): \(error)")
            }
        }

        syncProjectLspServerConfigsToCore()
        updateAlwaysPollProcessingForSelectedTab()
        updateStatusBar()

        if failures.isEmpty {
            let noun = shutdownCount == 1 ? "server" : "servers"
            setTransientStatusText("LSP \(noun) shut down: \(shutdownCount)")
            return shutdownCount > 0
        }

        NSSound.beep()
        let detail = "Shut down \(shutdownCount) of \(shutdownTargets.count) LSP servers.\n"
            + failures.joined(separator: "\n")
        if let tab = activeTab {
            presentLspResultFeedback(
                AttoLspResultFeedback.failed(.serverShutdown, errorDescription: detail),
                in: tab.editCore.editorView
            )
        } else {
            setTransientStatusText("LSP server shutdown: failed")
        }
        return false
    }

    func markLspServerShutdown(for tab: AttoEditorTab) {
        tab.suppressesAutomaticLspStart = true
        switch tab.languageSupportSource {
        case .lspTreeSitter:
            tab.languageSupportSource = .treeSitter
        case .lspSemantic, .lspServices:
            tab.languageSupportSource = .plainText
        case .plainText, .treeSitter, .sublimeSyntax:
            break
        }
    }

    private func projectLspShutdownTargets(
        for candidates: [ProjectLspShutdownCandidate]
    ) -> [ProjectLspShutdownCandidate] {
        guard candidates.isEmpty == false else { return [] }
        guard let coreDocuments else { return candidates }

        syncProjectLspServerConfigsToCore()
        do {
            let plan = try coreDocuments.projectLspStopPlan()
            var candidatesByTabID: [UInt64: ProjectLspShutdownCandidate] = [:]
            for candidate in candidates {
                guard let coreTabID = candidate.coreTabID else { continue }
                candidatesByTabID[coreTabID] = candidate
            }

            return plan.compactMap { entry in
                guard let candidate = candidatesByTabID[entry.tabId],
                      projectLspStopPlanEntry(entry, matches: candidate)
                else {
                    return nil
                }
                return candidate
            }
        } catch {
            NSLog("AttoEditor: failed to build project LSP stop plan: %@", String(describing: error))
            return candidates
        }
    }

    func projectLspStopPlanDecision(
        for tab: AttoEditorTab,
        documentURL: URL,
        config: AttoLspServerLaunchConfig
    ) -> (allowed: Bool, planEntry: EcuProjectLspStopPlanEntry?) {
        guard let coreDocuments, let coreTabID = tab.coreTabID else {
            return (allowed: true, planEntry: nil)
        }

        do {
            let snapshot = try coreDocuments.snapshot()
            guard snapshot.tabs.contains(where: { $0.id == coreTabID }) else {
                return (allowed: false, planEntry: nil)
            }
        } catch {
            NSLog("AttoEditor: failed to inspect core tabs for project LSP stop plan: %@", String(describing: error))
            return (allowed: true, planEntry: nil)
        }

        syncCoreTabLanguageId(config.languageId, for: tab)
        syncProjectLspServerConfigsToCore()
        let candidate: ProjectLspShutdownCandidate = (
            tab: tab,
            fileURL: documentURL,
            config: config,
            coreTabID: coreTabID
        )

        do {
            let plan = try coreDocuments.projectLspStopPlan()
            guard let entry = plan.first(where: { entry in
                entry.tabId == coreTabID && projectLspStopPlanEntry(entry, matches: candidate)
            }) else {
                return (allowed: false, planEntry: nil)
            }
            return (allowed: true, planEntry: entry)
        } catch {
            NSLog("AttoEditor: failed to build project LSP stop plan: %@", String(describing: error))
            return (allowed: true, planEntry: nil)
        }
    }

    private func projectLspStopPlanEntry(
        _ entry: EcuProjectLspStopPlanEntry,
        matches candidate: ProjectLspShutdownCandidate
    ) -> Bool {
        entry.documentURI == candidate.fileURL.standardizedFileURL.absoluteString
            && entry.serverKey.lowercased() == Self.projectLspServerConfigKey(for: candidate.config)
    }
}
