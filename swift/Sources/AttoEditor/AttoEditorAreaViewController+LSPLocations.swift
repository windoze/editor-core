import AppKit
import AttoEditorSupport
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    // MARK: - LSP location requests

    func handleCommandClick(ctx: EditorCoreSkiaContextMenuContext, tabID: UUID) -> Bool {
        guard activeTab?.id == tabID else { return false }
        return requestLspLocation(
            tabID: tabID,
            logicalLine: ctx.logicalLine,
            logicalColumn: ctx.logicalColumn,
            kind: .definition,
            showFeedback: false
        )
    }

    @discardableResult
    func goToDefinitionInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .definition)
    }

    @discardableResult
    func goToDeclarationInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .declaration)
    }

    @discardableResult
    func goToTypeDefinitionInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .typeDefinition)
    }

    @discardableResult
    func goToImplementationInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .implementation)
    }

    @discardableResult
    func findReferencesInActiveTab() -> Bool {
        requestLspLocationAtPrimaryCaret(kind: .references)
    }

    func requestLspLocationAtPrimaryCaret(kind: LspLocationRequestKind) -> Bool {
        guard let tab = activeTab else { return false }
        do {
            let offsets = try tab.editCore.editor.selectionOffsets()
            let pos = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
            return requestLspLocation(
                tabID: tab.id,
                logicalLine: pos.line,
                logicalColumn: pos.column,
                kind: kind,
                showFeedback: true
            )
        } catch {
            NSSound.beep()
            return false
        }
    }

    func requestLspLocation(
        tabID: UUID,
        logicalLine: UInt32,
        logicalColumn: UInt32,
        kind: LspLocationRequestKind,
        showFeedback: Bool
    ) -> Bool {
        guard activeTab?.id == tabID else { return false }
        guard let tab = activeTab else { return false }
        guard (try? tab.editCore.editor.lspIsEnabled()) == true else {
            if showFeedback {
                let message = AttoLspResultFeedback.unavailable(kind.feedbackFeature)
                markCurrentLspLocationResultError(message)
                presentLspResultFeedback(message, in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        cancelHoverUI()
        cancelSymbolUI()
        cancelHierarchyUI()
        cancelRenameUI()
        cancelCodeActionUI()

        definitionContext = DefinitionRequestContext(
            tabID: tabID,
            logicalLine: logicalLine,
            logicalColumn: logicalColumn,
            kind: kind,
            showFeedback: showFeedback
        )
        definitionPollTimer?.cancel()

        do {
            try requestLspLocation(kind: kind, editor: tab.editCore.editor, line: logicalLine, column: logicalColumn)
        } catch {
            cancelDefinitionUI()
            if showFeedback {
                let message = AttoLspResultFeedback.requestFailed(
                    kind.feedbackFeature,
                    errorDescription: error.localizedDescription
                )
                markCurrentLspLocationResultError(message)
                presentLspResultFeedback(message, in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        startDefinitionPollTimer(tabID: tabID)
        return true
    }

    func requestLspLocation(kind: LspLocationRequestKind, editor: EditorUI, line: UInt32, column: UInt32) throws {
        switch kind {
        case .definition:
            _ = try editor.lspRequestDefinition(logicalLine: line, logicalColumn: column)
        case .declaration:
            _ = try editor.lspRequestDeclaration(logicalLine: line, logicalColumn: column)
        case .typeDefinition:
            _ = try editor.lspRequestTypeDefinition(logicalLine: line, logicalColumn: column)
        case .implementation:
            _ = try editor.lspRequestImplementation(logicalLine: line, logicalColumn: column)
        case .references:
            _ = try editor.lspRequestReferences(logicalLine: line, logicalColumn: column, includeDeclaration: true)
        }
    }

    func startDefinitionPollTimer(tabID: UUID) {
        definitionPollTimer?.cancel()

        var remainingTicks = 40 // ~2s at 50ms
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let ctx = self.definitionContext, ctx.tabID == tabID else {
                self.cancelDefinitionUI()
                return
            }

            if remainingTicks <= 0 {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                let editorView = self.activeTab?.editCore.editorView
                self.cancelDefinitionUI()
                if showFeedback, let editorView {
                    let message = AttoLspResultFeedback.timeout(feature)
                    self.markCurrentLspLocationResultError(message)
                    self.presentLspResultFeedback(message, in: editorView)
                }
                return
            }
            remainingTicks -= 1

            guard let tab = self.activeTab, tab.id == tabID else {
                self.cancelDefinitionUI()
                return
            }

            let result: EcuLspLocationResult?
            do {
                result = try self.takeLspLocationResult(kind: ctx.kind, editor: tab.editCore.editor)
            } catch {
                let showFeedback = ctx.showFeedback
                let feature = ctx.kind.feedbackFeature
                self.cancelDefinitionUI()
                if showFeedback {
                    let message = AttoLspResultFeedback.failed(feature, errorDescription: error.localizedDescription)
                    self.markCurrentLspLocationResultError(message)
                    self.presentLspResultFeedback(message, in: tab.editCore.editorView)
                }
                timer.cancel()
                return
            }
            guard let result else { return }

            self.cancelDefinitionUI()
            _ = self.showLspLocationResultInActiveTab(result, kind: ctx.kind, showFeedback: ctx.showFeedback)
            timer.cancel()
        }

        definitionPollTimer = timer
        timer.resume()
    }

    func takeLspLocationResult(kind: LspLocationRequestKind, editor: EditorUI) throws -> EcuLspLocationResult? {
        switch kind {
        case .definition:
            try editor.lspTakeLastDefinitionResult()
        case .declaration:
            try editor.lspTakeLastDeclarationResult()
        case .typeDefinition:
            try editor.lspTakeLastTypeDefinitionResult()
        case .implementation:
            try editor.lspTakeLastImplementationResult()
        case .references:
            try editor.lspTakeLastReferencesResult()
        }
    }

    @discardableResult
    func showLspLocationResultJSONInActiveTab(_ json: String, kind: LspLocationRequestKind) -> Bool {
        let targets = AttoLspDefinitionParser.targets(fromLocationResultJSON: json)
        return showLspLocationTargetsInActiveTab(targets, kind: kind, showFeedback: true)
    }

    @discardableResult
    func showLspLocationResultInActiveTab(_ result: EcuLspLocationResult, kind: LspLocationRequestKind) -> Bool {
        showLspLocationResultInActiveTab(result, kind: kind, showFeedback: true)
    }

    @discardableResult
    func showLspLocationResultInActiveTab(
        _ result: EcuLspLocationResult,
        kind: LspLocationRequestKind,
        showFeedback: Bool
    ) -> Bool {
        let targets = AttoLspDefinitionParser.targets(fromLocationResult: result)
        return showLspLocationTargetsInActiveTab(targets, kind: kind, showFeedback: showFeedback)
    }

    @discardableResult
    func showLspLocationTargetsInActiveTab(
        _ targets: [AttoLspDefinitionParser.Target],
        kind: LspLocationRequestKind,
        showFeedback: Bool
    ) -> Bool {
        guard targets.isEmpty == false else {
            if showFeedback, let tab = activeTab {
                presentLspResultFeedback(AttoLspResultFeedback.empty(kind.feedbackFeature), in: tab.editCore.editorView)
            }
            NSSound.beep()
            return false
        }

        let items = AttoLspDefinitionParser.locationItems(for: targets, workspaceRootURL: workspaceRootURL)
        let snapshot = LspLocationResultSnapshot(kind: kind, items: items)
        recordLspLocationResultSnapshot(snapshot)

        if items.count > 1 {
            showLspLocationResults(snapshot)
            return true
        }

        navigateToLspTarget(items[0].target)
        return true
    }

    @discardableResult
    func showLastLspLocationResults() -> Bool {
        guard let entry = lspLocationResultStore.currentEntry, entry.snapshot.items.isEmpty == false else {
            NSSound.beep()
            return false
        }
        let snapshot = entry.snapshot

        if snapshot.items.count > 1 {
            showLspLocationResults(snapshot)
        } else {
            navigateToLspTarget(snapshot.items[0].target)
        }
        return true
    }

    @discardableResult
    func showLspLocationHistory() -> Bool {
        guard lspLocationResultStore.historyEntries.isEmpty == false else {
            NSSound.beep()
            return false
        }

        guard let window = view.window else {
            guard let entry = lspLocationResultStore.historyEntries.last else { return false }
            return openLspLocationEntry(entry)
        }

        let entries = Array(lspLocationResultStore.historyEntries.reversed())
        let commands = entries.enumerated().map { idx, entry in
            AttoCommandPaletteCommand(
                id: "lsp.location_history.\(idx)",
                title: entry.title
            ) { [weak self] in
                _ = self?.openLspLocationEntry(entry)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.LocationHistory",
            commandsProvider: { commands }
        )
        lspLocationResultsController = controller
        controller.show(relativeTo: window, placeholder: "Filter location history...")
        return true
    }

    @discardableResult
    func showLspLocationPanel() -> Bool {
        guard let entry = lspLocationResultStore.currentEntry, entry.snapshot.items.isEmpty == false else {
            NSSound.beep()
            return false
        }
        guard let window = view.window else {
            return openLspLocationEntry(entry)
        }
        let controller = lspLocationPanelController ?? AttoLspLocationPanelController { [weak self] target in
            self?.navigateToLspTarget(target)
        }
        lspLocationPanelController = controller
        return controller.show(relativeTo: window, entry: entry)
    }

    func recordLspLocationResultSnapshot(_ snapshot: LspLocationResultSnapshot) {
        let entry = lspLocationResultStore.record(
            snapshot,
            family: "locations",
            title: locationHistoryTitle(for: snapshot)
        )
        recordLspResultLifecycleEvent(
            entry,
            payload: .locations(kind: snapshot.kind.lifecycleKind, itemCount: snapshot.items.count)
        )
        lspLocationPanelController?.update(entry: entry)
    }

    @discardableResult
    func openLspLocationSnapshot(_ snapshot: LspLocationResultSnapshot) -> Bool {
        lspLocationResultStore.makeCurrent(
            snapshot,
            family: "locations",
            title: locationHistoryTitle(for: snapshot)
        )
        return presentLspLocationSnapshot(snapshot)
    }

    @discardableResult
    func openLspLocationEntry(_ entry: AttoLspResultLifecycleEntry<LspLocationResultSnapshot>) -> Bool {
        lspLocationResultStore.makeCurrent(entry)
        return presentLspLocationSnapshot(entry.snapshot)
    }

    @discardableResult
    func presentLspLocationSnapshot(_ snapshot: LspLocationResultSnapshot) -> Bool {
        if snapshot.items.count > 1 {
            showLspLocationResults(snapshot)
        } else if let first = snapshot.items.first {
            navigateToLspTarget(first.target)
        } else {
            NSSound.beep()
            return false
        }
        return true
    }

    func locationHistoryTitle(for snapshot: LspLocationResultSnapshot) -> String {
        if snapshot.items.count == 1, let first = snapshot.items.first {
            return "\(snapshot.kind.historyTitle): \(first.displayTitle)"
        }
        return "\(snapshot.kind.historyTitle): \(snapshot.items.count) results"
    }

    func showLspLocationResults(_ snapshot: LspLocationResultSnapshot) {
        guard let window = view.window else {
            navigateToLspTarget(snapshot.items[0].target)
            return
        }

        let commands = snapshot.items.enumerated().map { idx, item in
            AttoCommandPaletteCommand(
                id: "lsp.location.\(idx)",
                title: item.displayTitle
            ) { [weak self] in
                self?.navigateToLspTarget(item.target)
            }
        }

        let controller = AttoCommandPaletteController(
            accessibilityPrefix: "AttoEditor.LSP.LocationResults",
            commandsProvider: { commands }
        )
        lspLocationResultsController = controller
        controller.show(relativeTo: window, placeholder: snapshot.kind.resultPlaceholder)
    }

    func displayTitle(for target: AttoLspDefinitionParser.Target) -> String {
        AttoLspDefinitionParser.locationItems(for: [target], workspaceRootURL: workspaceRootURL)
            .first?
            .displayTitle ?? "\(target.uri):\(target.line + 1):\(target.utf16Character + 1)"
    }

    func navigateToLspTarget(_ target: AttoLspDefinitionParser.Target) {
        guard let url = URL(string: target.uri), url.isFileURL else {
            NSSound.beep()
            return
        }

        openFile(url: url, mode: .preview)

        guard let tab = activeTab, projectedFileURL(for: tab) == url.standardizedFileURL else {
            return
        }

        do {
            // Ensure the new editor view has a real viewport height before calling `revealPrimaryCaret`.
            // `EditorUI.revealPrimaryCaret()` is a no-op when viewport height is unknown.
            tab.editCore.layoutSubtreeIfNeeded()
            let text = try tab.editCore.editor.text()
            let offset = AttoLspDefinitionParser.charOffsetForLspPosition(
                inText: text,
                line: target.line,
                utf16Character: target.utf16Character
            )
            try tab.editCore.editor.setSelections([EcuSelectionRange(start: offset, end: offset)], primaryIndex: 0)
            try tab.editCore.editor.revealPrimaryCaret()
            tab.editCore.needsDisplay = true
            updateStatusBar()
        } catch {
            NSSound.beep()
        }
    }
}
