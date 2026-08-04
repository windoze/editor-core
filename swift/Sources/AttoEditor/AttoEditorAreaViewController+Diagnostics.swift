import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - Problems quick panel

    @discardableResult
    func showProblemsInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let problems = unifiedDiagnosticsSnapshot(for: tab, includeActiveDiagnostics: true).problems
        guard problems.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            navigateToDiagnosticProblem(problems[0], in: tab)
            return true
        }

        let commands = problems.enumerated().map { idx, problem in
            AttoCommandPaletteCommand(
                id: "lsp.problem.\(idx)",
                title: displayTitle(for: problem, in: tab)
            ) { [weak self] in
                guard let self, let current = self.activeTab, current.id == tab.id else { return }
                self.navigateToDiagnosticProblem(problem, in: current)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.Problems",
            commandsProvider: { commands }
        )
        problemsResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter problems...")
        return true
    }

    @discardableResult
    func showProblemsPanelInActiveTab() -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        problemsResultsController?.hide()
        problemsResultsController = nil

        derivedStateStore.refreshActive(editor: tab.editCore.editor)
        let problems = unifiedDiagnosticsSnapshot(for: tab, includeActiveDiagnostics: true).problems

        guard let window = view.window else {
            if let first = problems.first {
                navigateToDiagnosticProblem(first, in: tab)
                return true
            }
            NSSound.beep()
            return false
        }

        let controller = problemsPanelController ?? AttoProblemsPanelController(
            titleForProblem: { [weak self] problem in
                guard let self, let tab = self.activeTab else { return problem.message }
                return self.displayTitle(for: problem, in: tab)
            },
            onOpen: { [weak self] problem in
                guard let self, let tab = self.activeTab else { return }
                self.navigateToDiagnosticProblem(problem, in: tab)
            }
        )
        problemsPanelController = controller
        let countText = AttoLspResultMetadataText.count(problems.count, singular: "problem", plural: "problems")
        return controller.show(
            relativeTo: window,
            problems: problems,
            metadataText: lspDiagnosticsPanelMetadata(countText: countText, family: "diagnostics.active")
        )
    }

    @discardableResult
    func showDiagnosticsLifecycleEntryPanel(
        _ entry: AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>
    ) -> Bool {
        let problems = entry.snapshot.problems
        guard problems.isEmpty == false else {
            NSSound.beep()
            return false
        }

        diagnosticsLifecycleStore.makeCurrent(entry)
        updateVisibleLspWorkbenchPanel()
        updateVisibleLspWorkbenchHistoryPanel()

        guard let window = view.window else {
            navigateToDiagnosticLifecycleProblem(problems[0], snapshot: entry.snapshot)
            return true
        }

        switch entry.snapshot.scope {
        case .activeTab:
            let controller = problemsPanelController ?? AttoProblemsPanelController(
                titleForProblem: { [weak self] problem in
                    guard let self, let tab = self.activeTab else { return problem.message }
                    return self.displayTitle(for: problem, in: tab)
                },
                onOpen: { [weak self] problem in
                    self?.navigateToDiagnosticLifecycleProblem(problem, snapshot: entry.snapshot)
                }
            )
            problemsPanelController = controller
            let countText = AttoLspResultMetadataText.count(problems.count, singular: "problem", plural: "problems")
            return controller.show(
                relativeTo: window,
                problems: problems,
                title: entry.title.isEmpty ? "Problems" : entry.title,
                placeholder: "Filter problems history...",
                metadataText: AttoLspResultMetadataText.entry(
                    entry,
                    countText: countText,
                    stateText: diagnosticsLifecycleDisplayStateText(for: entry)
                )
            )

        case .workspace:
            let controller = workspaceProblemsPanelController ?? AttoProblemsPanelController(
                titleForProblem: { [weak self] problem in
                    guard let self else { return problem.message }
                    return self.displayTitle(for: problem)
                },
                onOpen: { [weak self] problem in
                    self?.navigateToDiagnosticLifecycleProblem(problem, snapshot: entry.snapshot)
                },
                accessibilityIDs: .workspaceProblems
            )
            workspaceProblemsPanelController = controller
            let countText = AttoLspResultMetadataText.count(problems.count, singular: "problem", plural: "problems")
            return controller.show(
                relativeTo: window,
                problems: problems,
                title: entry.title.isEmpty ? "Workspace Problems" : entry.title,
                placeholder: "Filter workspace problems history...",
                metadataText: AttoLspResultMetadataText.entry(
                    entry,
                    countText: countText,
                    stateText: diagnosticsLifecycleDisplayStateText(for: entry)
                )
            )
        }
    }

    func displayTitle(for diagnostic: EcuDiagnostic, in tab: AttoEditorTab) -> String {
        let documentURL = projectedFileURL(for: tab)
        let location: String = {
            do {
                let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: diagnostic.range.start)
                return "\(documentURL.lastPathComponent):\(pos.line + 1):\(pos.column + 1)"
            } catch {
                return documentURL.lastPathComponent
            }
        }()

        let severity = diagnostic.severity.map { "[\($0.rawValue)] " } ?? ""
        let source = diagnostic.source.map { " (\($0))" } ?? ""
        return "\(severity)\(diagnostic.message)\(source) — \(location)"
    }

    func displayTitle(for problem: AttoUnifiedDiagnosticProblem, in tab: AttoEditorTab) -> String {
        switch problem.target {
        case let .active(diagnostic):
            return displayTitle(for: diagnostic, in: tab)
        case let .workspace(diagnostic):
            return displayTitle(for: diagnostic)
        }
    }

    func navigateToDiagnosticProblem(_ problem: AttoUnifiedDiagnosticProblem, in tab: AttoEditorTab) {
        switch problem.target {
        case let .active(diagnostic):
            navigateToDiagnostic(diagnostic, in: tab)
        case let .workspace(diagnostic):
            navigateToLspTarget(diagnostic.target)
        }
    }

    func navigateToDiagnosticProblem(_ problem: AttoUnifiedDiagnosticProblem) {
        switch problem.target {
        case let .active(diagnostic):
            guard let tab = activeTab else {
                NSSound.beep()
                return
            }
            navigateToDiagnostic(diagnostic, in: tab)
        case let .workspace(diagnostic):
            navigateToLspTarget(diagnostic.target)
        }
    }

    func navigateToDiagnosticLifecycleProblem(
        _ problem: AttoUnifiedDiagnosticProblem,
        snapshot: AttoDiagnosticsLifecycleSnapshot
    ) {
        switch problem.target {
        case let .active(diagnostic):
            if case let .activeTab(tabID, _) = snapshot.scope,
               let tab = tabs.first(where: { $0.id == tabID }) {
                if selectedTabID != tab.id {
                    selectTab(id: tab.id)
                }
                navigateToDiagnostic(diagnostic, in: tab)
                return
            }
            navigateToDiagnosticProblem(problem)

        case .workspace:
            navigateToDiagnosticProblem(problem)
        }
    }

    func navigateToDiagnostic(_ diagnostic: EcuDiagnostic, in tab: AttoEditorTab) {
        do {
            tab.editCore.layoutSubtreeIfNeeded()
            let start = min(diagnostic.range.start, diagnostic.range.end)
            let end = max(diagnostic.range.start, diagnostic.range.end)
            let selectionEnd = start == end ? start : end
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: start, end: selectionEnd)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Workspace diagnostics quick panel

    @discardableResult
    func showWorkspaceDiagnosticsInActiveTab(showFeedback: Bool = true) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            return failDiagnosticsLifecycleResult(
                family: "diagnostics.workspace",
                message: AttoLspResultFeedback.unavailable(.workspaceDiagnostics),
                showFeedback: showFeedback,
                editorView: tab.editCore.editorView
            )
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        cancelWorkspaceDiagnosticsUI()

        do {
            _ = try tab.editCore.editor.lspRequestWorkspaceDiagnostic(
                previousResultIdsJSON: workspaceProblemsStore.previousResultIdsJSON()
            )
        } catch {
            return failDiagnosticsLifecycleResult(
                family: "diagnostics.workspace",
                message: AttoLspResultFeedback.requestFailed(
                    .workspaceDiagnostics,
                    errorDescription: error.localizedDescription
                ),
                showFeedback: showFeedback,
                editorView: tab.editCore.editorView
            )
        }

        workspaceDiagnosticsContext = WorkspaceDiagnosticsRequestContext(tabID: tab.id, showFeedback: showFeedback)
        workspaceDiagnosticsStaleReason = .workspaceRefreshRequested
        recordWorkspaceDiagnosticsLifecycle(problems: workspaceDiagnosticProblems())
        updateWorkspaceProblemsPanelIfVisible()
        updateVisibleLspWorkbenchPanel()
        startWorkspaceDiagnosticsPollTimer(tabID: tab.id, editorView: tab.editCore.editorView)
        return true
    }

    @discardableResult
    func showWorkspaceDiagnosticsResultJSONInActiveTab(_ json: String, showFeedback: Bool = false) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let snapshot = workspaceProblemsStore.apply(resultJSON: json)
        return showWorkspaceDiagnosticsSnapshotInActiveTab(
            snapshot,
            tab: tab,
            showFeedback: showFeedback
        )
    }

    @discardableResult
    func showWorkspaceDiagnosticsResultInActiveTab(
        _ result: EcuLspWorkspaceDiagnosticResult,
        showFeedback: Bool = false
    ) -> Bool {
        guard let tab = activeTab else {
            NSSound.beep()
            return false
        }

        let snapshot = workspaceProblemsStore.apply(result: result)
        return showWorkspaceDiagnosticsSnapshotInActiveTab(
            snapshot,
            tab: tab,
            showFeedback: showFeedback
        )
    }

    @discardableResult
    func showWorkspaceDiagnosticsSnapshotInActiveTab(
        _ snapshot: AttoWorkspaceProblemsSnapshot,
        tab: AttoEditorTab,
        showFeedback: Bool
    ) -> Bool {
        workspaceDiagnosticsStaleReason = nil
        recordWorkspaceDiagnosticsLifecycle(
            problems: AttoDiagnosticsModel.workspaceProblems(snapshot.diagnostics)
        )
        updateWorkspaceDiagnosticMarkersForOpenTabs()
        updateWorkspaceProblemsPanelIfVisible()
        updateStatusBar()
        guard snapshot.diagnostics.isEmpty == false else {
            if showFeedback {
                presentLspResultFeedback(AttoLspResultFeedback.empty(.workspaceDiagnostics), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        showWorkspaceDiagnosticResults(snapshot.diagnostics)
        return true
    }

    func startWorkspaceDiagnosticsPollTimer(tabID: UUID, editorView: EditorCoreSkiaView) {
        workspaceDiagnosticsPollTimer?.cancel()

        var remainingTicks = 80 // ~4s at 50ms; workspace diagnostics can fan out across files.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.workspaceDiagnosticsContext, ctx.tabID == tabID else {
                self.cancelWorkspaceDiagnosticsUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                self.failDiagnosticsLifecycleResult(
                    family: "diagnostics.workspace",
                    message: AttoLspResultFeedback.timeout(.workspaceDiagnostics),
                    showFeedback: showFeedback,
                    editorView: editorView,
                    cancel: self.cancelWorkspaceDiagnosticsUI
                )
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelWorkspaceDiagnosticsUI()
                return
            }

            let result: EcuLspWorkspaceDiagnosticResult?
            do {
                result = try tab.editCore.editor.lspTakeLastWorkspaceDiagnosticResult()
            } catch {
                let showFeedback = ctx.showFeedback
                self.failDiagnosticsLifecycleResult(
                    family: "diagnostics.workspace",
                    message: AttoLspResultFeedback.failed(
                        .workspaceDiagnostics,
                        errorDescription: error.localizedDescription
                    ),
                    showFeedback: showFeedback,
                    editorView: editorView,
                    cancel: self.cancelWorkspaceDiagnosticsUI
                )
                return
            }
            guard let result else { return }

            let showFeedback = ctx.showFeedback
            self.workspaceDiagnosticsPollTimer?.cancel()
            self.workspaceDiagnosticsPollTimer = nil
            self.workspaceDiagnosticsContext = nil
            _ = self.showWorkspaceDiagnosticsResultInActiveTab(result, showFeedback: showFeedback)
            timer.cancel()
        }

        workspaceDiagnosticsPollTimer = timer
        timer.resume()
    }

    func showWorkspaceDiagnosticResults(_ diagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic]) {
        guard diagnostics.isEmpty == false else {
            NSSound.beep()
            return
        }

        guard let window = view.window else {
            navigateToLspTarget(diagnostics[0].target)
            return
        }

        let commands = diagnostics.enumerated().map { idx, diagnostic in
            AttoCommandPaletteCommand(
                id: "lsp.workspace_diagnostic.\(idx)",
                title: displayTitle(for: diagnostic)
            ) { [weak self] in
                self?.navigateToLspTarget(diagnostic.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.WorkspaceDiagnostics",
            commandsProvider: { commands }
        )
        workspaceDiagnosticsResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter workspace diagnostics...")
    }

    @discardableResult
    func showWorkspaceProblemsPanelInActiveTab() -> Bool {
        guard activeTab != nil else {
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelDefinitionUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelSignatureHelpUI()
        cancelCompletionUI()
        cancelRenameUI()
        cancelCodeActionUI()
        workspaceDiagnosticsResultsController?.hide()
        workspaceDiagnosticsResultsController = nil

        let problems = workspaceDiagnosticProblems()
        guard let window = view.window else {
            if let first = problems.first {
                navigateToDiagnosticProblem(first)
                return true
            }
            NSSound.beep()
            return false
        }

        let controller = workspaceProblemsPanelController ?? AttoProblemsPanelController(
            titleForProblem: { [weak self] problem in
                guard let self else { return problem.message }
                return self.displayTitle(for: problem)
            },
            onOpen: { [weak self] problem in
                self?.navigateToDiagnosticProblem(problem)
            },
            accessibilityIDs: .workspaceProblems
        )
        workspaceProblemsPanelController = controller
        let countText = AttoLspResultMetadataText.count(problems.count, singular: "problem", plural: "problems")
        return controller.show(
            relativeTo: window,
            problems: problems,
            title: "Workspace Problems",
            placeholder: "Filter workspace problems...",
            metadataText: lspDiagnosticsPanelMetadata(countText: countText, family: "diagnostics.workspace")
        )
    }

    func updateWorkspaceProblemsPanelIfVisible() {
        guard workspaceProblemsPanelController?.isVisible == true else { return }
        let problems = workspaceDiagnosticProblems()
        let countText = AttoLspResultMetadataText.count(problems.count, singular: "problem", plural: "problems")
        workspaceProblemsPanelController?.update(
            problems: problems,
            title: "Workspace Problems",
            placeholder: "Filter workspace problems...",
            metadataText: lspDiagnosticsPanelMetadata(countText: countText, family: "diagnostics.workspace")
        )
    }

    func workspaceDiagnosticProblems() -> [AttoUnifiedDiagnosticProblem] {
        AttoDiagnosticsModel.workspaceProblems(workspaceProblemsStore.diagnostics)
    }

    func displayTitle(for diagnostic: AttoLspWorkspaceDiagnosticsParser.Diagnostic) -> String {
        let severity = diagnostic.severityLabel.map { "[\($0)] " } ?? ""
        let code = diagnostic.code.map { " [\($0)]" } ?? ""
        let source = diagnostic.source.map { " (\($0))" } ?? ""
        let location = displayTitle(for: diagnostic.target)
        return "\(severity)\(diagnostic.message)\(code)\(source) — \(location)"
    }

    func displayTitle(for problem: AttoUnifiedDiagnosticProblem) -> String {
        switch problem.target {
        case let .active(diagnostic):
            guard let tab = activeTab else { return diagnostic.message }
            return displayTitle(for: diagnostic, in: tab)
        case let .workspace(diagnostic):
            return displayTitle(for: diagnostic)
        }
    }
}
