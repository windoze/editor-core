import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    private enum LspWorkbenchItemID {
        static let activeProblems = "active_problems"
        static let workspaceProblems = "workspace_problems"
        static let locations = "locations"
        static let symbols = "symbols"
        static let workspaceOutline = "workspace_outline"
        static let codeLens = "code_lens"
        static let inlayHints = "inlay_hints"
        static let documentLinks = "document_links"
        static let documentColors = "document_colors"
        static let hierarchy = "hierarchy"
        static let eventBackedFamilies = [
            codeLens,
            inlayHints,
            documentLinks,
            documentColors,
            hierarchy,
        ]
    }

    @discardableResult
    func showLspWorkbenchPanel() -> Bool {
        guard let window = view.window else {
            NSSound.beep()
            return false
        }

        let controller = lspWorkbenchPanelController ?? makeLspWorkbenchPanelController()
        lspWorkbenchPanelController = controller
        return controller.show(relativeTo: window, items: lspWorkbenchItems())
    }

    @discardableResult
    func showLspWorkbenchDock() -> Bool {
        _ = view
        guard let dockView = lspWorkbenchDockView else {
            NSSound.beep()
            return false
        }

        dockView.update(items: lspWorkbenchItems())
        dockView.isHidden = false
        contentHostBottomToStatusConstraint?.isActive = false
        contentHostBottomToWorkbenchDockConstraint?.isActive = true
        view.layoutSubtreeIfNeeded()
        dockView.focusSearchField()
        return true
    }

    func hideLspWorkbenchDock() {
        guard let dockView = lspWorkbenchDockView else { return }
        dockView.isHidden = true
        contentHostBottomToWorkbenchDockConstraint?.isActive = false
        contentHostBottomToStatusConstraint?.isActive = true
        view.layoutSubtreeIfNeeded()
    }

    func updateVisibleLspWorkbenchPanel() {
        if lspWorkbenchPanelController?.isVisible == true {
            lspWorkbenchPanelController?.update(items: lspWorkbenchItems())
        }
        if lspWorkbenchDockView?.isVisible == true {
            lspWorkbenchDockView?.update(items: lspWorkbenchItems())
        }
        updateVisibleLspWorkbenchHistoryPanel()
    }

    func _refreshLspWorkbenchPanelForTesting() {
        let controller = lspWorkbenchPanelController ?? makeLspWorkbenchPanelController()
        lspWorkbenchPanelController = controller
        controller.update(items: lspWorkbenchItems())
    }

    @discardableResult
    func clearLspWorkbenchStaleResults() -> Bool {
        let didUpdate = lspWorkbenchStaleClearableFamilies().reduce(false) { didUpdate, family in
            clearLspWorkbenchStaleResult(family: family, updateStatus: false) || didUpdate
        }

        if didUpdate {
            setTransientStatusText("LSP workbench stale results cleared")
            updateVisibleLspWorkbenchPanel()
        } else {
            setTransientStatusText("LSP workbench stale results: none")
        }
        return didUpdate
    }

    func lspWorkbenchStaleClearableFamilies() -> [String] {
        [
            LspWorkbenchItemID.activeProblems,
            LspWorkbenchItemID.workspaceProblems,
            LspWorkbenchItemID.locations,
            LspWorkbenchItemID.symbols,
            LspWorkbenchItemID.workspaceOutline,
        ] + LspWorkbenchItemID.eventBackedFamilies
    }

    @discardableResult
    func clearSelectedLspWorkbenchStaleResult() -> Bool {
        guard let item = selectedLspWorkbenchItem() else {
            setTransientStatusText("LSP workbench stale clear: no selected family")
            NSSound.beep()
            return false
        }
        return clearLspWorkbenchStaleResult(family: item.id)
    }

    @discardableResult
    func clearLspWorkbenchStaleResult(family: String, updateStatus: Bool = true) -> Bool {
        let didClear: Bool
        switch family {
        case LspWorkbenchItemID.activeProblems:
            didClear = clearActiveDiagnosticsWorkbenchStaleResult()
        case LspWorkbenchItemID.workspaceProblems:
            didClear = clearWorkspaceDiagnosticsWorkbenchStaleResult()
        case LspWorkbenchItemID.locations:
            if let entry = lspLocationResultStore.currentEntry,
               let updated = lspLocationResultStore.clearStaleState(for: entry) {
                lspLocationPanelController?.update(entry: updated)
                didClear = true
            } else {
                didClear = false
            }
        case LspWorkbenchItemID.symbols:
            didClear = clearSymbolWorkbenchStaleResult(lspWorkbenchSymbolEntry())
        case LspWorkbenchItemID.workspaceOutline:
            didClear = clearSymbolWorkbenchStaleResult(lspWorkbenchWorkspaceOutlineEntry())
        default:
            didClear = lspResultEventStream.clearLatestStaleStates(families: [family]).isEmpty == false
        }

        guard updateStatus else { return didClear }
        if didClear {
            setTransientStatusText("LSP workbench stale cleared: \(family)")
            updateVisibleLspWorkbenchPanel()
        } else {
            setTransientStatusText("LSP workbench stale clear: none for \(family)")
        }
        return didClear
    }

    @discardableResult
    private func clearActiveDiagnosticsWorkbenchStaleResult() -> Bool {
        guard let tab = activeTab,
              activeDiagnosticsStaleReasonsByTabID.removeValue(forKey: tab.id) != nil
        else {
            return false
        }
        let snapshot = unifiedDiagnosticsSnapshot(for: tab, includeActiveDiagnostics: true)
        recordActiveDiagnosticsLifecycle(snapshot, for: tab)
        return true
    }

    @discardableResult
    private func clearWorkspaceDiagnosticsWorkbenchStaleResult() -> Bool {
        guard workspaceDiagnosticsStaleReason != nil else { return false }
        workspaceDiagnosticsStaleReason = nil
        recordWorkspaceDiagnosticsLifecycle(problems: workspaceDiagnosticProblems())
        return true
    }

    @discardableResult
    private func clearSymbolWorkbenchStaleResult(
        _ entry: AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>?
    ) -> Bool {
        guard let entry,
              let updated = lspSymbolResultStore.clearStaleState(for: entry)
        else {
            return false
        }
        lspSymbolPanelController?.update(entry: updated)
        return true
    }

    @discardableResult
    func pinCurrentLspWorkbenchResults() -> Bool {
        let didPin = lspWorkbenchPinnableFamilies().reduce(false) { didPin, family in
            pinLspWorkbenchResult(family: family, updateStatus: false) || didPin
        }

        if didPin {
            setTransientStatusText("LSP workbench current results pinned")
            updateVisibleLspWorkbenchPanel()
        } else {
            setTransientStatusText("LSP workbench pin: no results")
        }
        return didPin
    }

    @discardableResult
    func unpinCurrentLspWorkbenchResults() -> Bool {
        let didUnpin = lspWorkbenchPinnableFamilies().reduce(false) { didUnpin, family in
            unpinLspWorkbenchResult(family: family, updateStatus: false) || didUnpin
        }

        if didUnpin {
            setTransientStatusText("LSP workbench current results unpinned")
            updateVisibleLspWorkbenchPanel()
        } else {
            setTransientStatusText("LSP workbench unpin: no pinned results")
        }
        return didUnpin
    }

    func lspWorkbenchPinnableFamilies() -> [String] {
        [
            LspWorkbenchItemID.activeProblems,
            LspWorkbenchItemID.workspaceProblems,
            LspWorkbenchItemID.locations,
            LspWorkbenchItemID.symbols,
            LspWorkbenchItemID.workspaceOutline,
        ] + LspWorkbenchItemID.eventBackedFamilies
    }

    @discardableResult
    func pinSelectedLspWorkbenchResult() -> Bool {
        guard let item = selectedLspWorkbenchItem() else {
            setTransientStatusText("LSP workbench pin: no selected family")
            NSSound.beep()
            return false
        }
        return pinLspWorkbenchResult(family: item.id)
    }

    @discardableResult
    func unpinSelectedLspWorkbenchResult() -> Bool {
        guard let item = selectedLspWorkbenchItem() else {
            setTransientStatusText("LSP workbench unpin: no selected family")
            NSSound.beep()
            return false
        }
        return unpinLspWorkbenchResult(family: item.id)
    }

    @discardableResult
    func pinLspWorkbenchResult(family: String, updateStatus: Bool = true) -> Bool {
        let didPin: Bool
        switch family {
        case LspWorkbenchItemID.activeProblems:
            didPin = pinDiagnosticsWorkbenchResult(family: "diagnostics.active", key: "diagnostics.active")
        case LspWorkbenchItemID.workspaceProblems:
            didPin = pinDiagnosticsWorkbenchResult(family: "diagnostics.workspace", key: "diagnostics.workspace")
        case LspWorkbenchItemID.locations:
            if let entry = lspLocationResultStore.currentEntry {
                lspLocationResultStore.pin(entry, key: LspWorkbenchItemID.locations)
                didPin = true
            } else {
                didPin = false
            }
        case LspWorkbenchItemID.symbols:
            if let entry = lspWorkbenchSymbolEntry() {
                lspSymbolResultStore.pin(entry, key: LspWorkbenchItemID.symbols)
                didPin = true
            } else {
                didPin = false
            }
        case LspWorkbenchItemID.workspaceOutline:
            if let entry = lspWorkbenchWorkspaceOutlineEntry() {
                lspSymbolResultStore.pin(entry, key: LspWorkbenchItemID.workspaceOutline)
                didPin = true
            } else {
                didPin = false
            }
        default:
            if lspResultEventStream.pinLatest(family: family) != nil {
                lspWorkbenchAuxiliaryHistoryStore.pinLatest(family: family)
                didPin = true
            } else {
                didPin = false
            }
        }

        guard updateStatus else { return didPin }
        if didPin {
            setTransientStatusText("LSP workbench result pinned: \(family)")
            updateVisibleLspWorkbenchPanel()
        } else {
            setTransientStatusText("LSP workbench pin: no result for \(family)")
            NSSound.beep()
        }
        return didPin
    }

    @discardableResult
    private func pinDiagnosticsWorkbenchResult(family: String, key: String) -> Bool {
        guard let entry = lspWorkbenchDiagnosticsEntry(family: family) else {
            return false
        }
        diagnosticsLifecycleStore.pin(entry, key: key)
        return true
    }

    @discardableResult
    func unpinLspWorkbenchResult(family: String, updateStatus: Bool = true) -> Bool {
        let didUnpin: Bool
        switch family {
        case LspWorkbenchItemID.activeProblems:
            didUnpin = diagnosticsLifecycleStore.unpin(key: "diagnostics.active") != nil
        case LspWorkbenchItemID.workspaceProblems:
            didUnpin = diagnosticsLifecycleStore.unpin(key: "diagnostics.workspace") != nil
        case LspWorkbenchItemID.locations:
            didUnpin = lspLocationResultStore.unpin(key: LspWorkbenchItemID.locations) != nil
        case LspWorkbenchItemID.symbols:
            didUnpin = lspSymbolResultStore.unpin(key: LspWorkbenchItemID.symbols) != nil
        case LspWorkbenchItemID.workspaceOutline:
            didUnpin = lspSymbolResultStore.unpin(key: LspWorkbenchItemID.workspaceOutline) != nil
        default:
            let didUnpinEvent = lspResultEventStream.unpin(family: family) != nil
            let didUnpinSnapshot = lspWorkbenchAuxiliaryHistoryStore.unpin(family: family) != nil
            didUnpin = didUnpinEvent || didUnpinSnapshot
        }

        guard updateStatus else { return didUnpin }
        if didUnpin {
            setTransientStatusText("LSP workbench result unpinned: \(family)")
            updateVisibleLspWorkbenchPanel()
        } else {
            setTransientStatusText("LSP workbench unpin: no pinned result for \(family)")
        }
        return didUnpin
    }

    @discardableResult
    func jumpToFirstLspWorkbenchResult() -> Bool {
        guard let target = lspWorkbenchFirstJumpTarget() else {
            setTransientStatusText("LSP workbench jump: no target")
            NSSound.beep()
            return false
        }
        navigateToLspTarget(target)
        return true
    }

    func lspWorkbenchFirstJumpTarget() -> AttoLspDefinitionParser.Target? {
        for family in [
            LspWorkbenchItemID.locations,
            LspWorkbenchItemID.symbols,
            LspWorkbenchItemID.workspaceOutline,
            LspWorkbenchItemID.hierarchy,
        ] {
            if let target = lspWorkbenchJumpTarget(family: family) {
                return target
            }
        }
        return nil
    }

    func lspWorkbenchJumpTarget(family: String) -> AttoLspDefinitionParser.Target? {
        switch family {
        case LspWorkbenchItemID.locations:
            return lspLocationResultStore.currentEntry?.snapshot.items.first?.target
        case LspWorkbenchItemID.symbols:
            return lspWorkbenchSymbolEntry()?.snapshot.symbols.first?.target
        case LspWorkbenchItemID.workspaceOutline:
            return lspWorkbenchWorkspaceOutlineEntry()?.snapshot.symbols.first?.target
        case LspWorkbenchItemID.hierarchy:
            return hierarchyPanelSnapshot?.entries.first?.target
        default:
            return nil
        }
    }

    @discardableResult
    func refreshSelectedLspWorkbenchResult() -> Bool {
        guard let item = selectedLspWorkbenchItem() else {
            setTransientStatusText("LSP workbench refresh: no selected family")
            NSSound.beep()
            return false
        }
        return refreshLspWorkbenchResult(family: item.id)
    }

    @discardableResult
    func refreshLspWorkbenchResult(family: String) -> Bool {
        guard lspWorkbenchCanRefresh(family: family) else {
            setTransientStatusText("LSP workbench refresh: \(family) cannot be refreshed")
            NSSound.beep()
            return false
        }

        switch family {
        case LspWorkbenchItemID.workspaceProblems:
            return showWorkspaceDiagnosticsInActiveTab()
        case LspWorkbenchItemID.codeLens:
            return refreshCodeLensInActiveTab()
        case LspWorkbenchItemID.inlayHints:
            return refreshInlayHintsInActiveTab()
        case LspWorkbenchItemID.documentLinks:
            return refreshDocumentLinksInActiveTab()
        case LspWorkbenchItemID.documentColors:
            return refreshDocumentColorsInActiveTab()
        case LspWorkbenchItemID.hierarchy:
            return refreshHierarchyPanelInActiveTab()
        default:
            return false
        }
    }

    func lspWorkbenchCanRefresh(family: String) -> Bool {
        switch family {
        case LspWorkbenchItemID.workspaceProblems,
             LspWorkbenchItemID.codeLens,
             LspWorkbenchItemID.inlayHints,
             LspWorkbenchItemID.documentLinks,
             LspWorkbenchItemID.documentColors,
             LspWorkbenchItemID.hierarchy:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func jumpToSelectedLspWorkbenchResult() -> Bool {
        guard let item = selectedLspWorkbenchItem() else {
            setTransientStatusText("LSP workbench jump: no selected family")
            NSSound.beep()
            return false
        }
        guard let target = lspWorkbenchJumpTarget(family: item.id) else {
            setTransientStatusText("LSP workbench jump: no target for \(item.id)")
            NSSound.beep()
            return false
        }
        navigateToLspTarget(target)
        return true
    }

    @discardableResult
    func showSelectedLspWorkbenchHistory() -> Bool {
        guard let item = selectedLspWorkbenchItem() else {
            setTransientStatusText("LSP workbench history: no selected family")
            NSSound.beep()
            return false
        }
        return showLspWorkbenchHistoryPanel(family: item.id)
    }

    func lspWorkbenchItems() -> [AttoLspWorkbenchPanelController.Item] {
        let hasActiveTab = activeTab != nil
        let activeProblemsCount = activeTab.map { tab in
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            return unifiedDiagnosticsSnapshot(for: tab, includeActiveDiagnostics: true).problems.count
        } ?? 0
        let workspaceProblemsCount = hasActiveTab ? workspaceDiagnosticProblems().count : 0
        let activeDiagnosticsEntry = lspWorkbenchDiagnosticsEntry(family: "diagnostics.active")
        let workspaceDiagnosticsEntry = lspWorkbenchDiagnosticsEntry(family: "diagnostics.workspace")
        let activeProblemsStatus = lspWorkbenchDiagnosticsStatus(
            countText: activeProblemsCount == 1 ? "1 problem" : "\(activeProblemsCount) problems",
            entry: activeDiagnosticsEntry
        )
        let workspaceProblemsStatus = lspWorkbenchDiagnosticsStatus(
            countText: workspaceProblemsCount == 1 ? "1 problem" : "\(workspaceProblemsCount) problems",
            entry: workspaceDiagnosticsEntry
        )
        let activeDiagnosticsHistoryCount = lspWorkbenchDiagnosticsHistoryCount(family: "diagnostics.active")
        let workspaceDiagnosticsHistoryCount = lspWorkbenchDiagnosticsHistoryCount(family: "diagnostics.workspace")
        let locationEntry = lspLocationResultStore.currentEntry
        let symbolEntry = lspWorkbenchSymbolEntry()
        let locationCount = locationEntry?.snapshot.items.count ?? 0
        let symbolCount = symbolEntry?.snapshot.symbols.count ?? 0
        let symbolHistoryCount = lspSymbolResultStore.historyEntries.filter {
            isWorkspaceOutlineEntry($0) == false
        }.count
        let locationStatus = lspWorkbenchLifecycleStatus(
            countText: locationCount == 1 ? "1 location" : "\(locationCount) locations",
            entry: locationEntry
        )
        let symbolStatus = lspWorkbenchLifecycleStatus(
            countText: symbolCount == 1 ? "1 symbol" : "\(symbolCount) symbols",
            entry: symbolEntry
        )
        let outlineEntry = lspWorkbenchWorkspaceOutlineEntry()
        let outlineCount = workspaceOutlineSymbolSnapshot().symbols.count
        let outlineHistoryCount = lspSymbolResultStore.historyEntries.filter(isWorkspaceOutlineEntry).count
        let outlineStatus = lspWorkbenchLifecycleStatus(
            countText: outlineCount == 1 ? "1 symbol" : "\(outlineCount) symbols",
            entry: outlineEntry
        )
        let decorations = activeTab.map { tab -> EcuDecorationsSnapshot in
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            return derivedStateStore.active.decorations
        }
        let codeLensCount = decorations.map { AttoLspCodeLensParser.items(fromDecorationsSnapshot: $0).count } ?? 0
        let inlayHintCount = decorations.map { AttoLspInlayHintParser.items(fromDecorationsSnapshot: $0).count } ?? 0
        let documentLinkCount = decorations.map { AttoLspDocumentLinkParser.items(fromDecorationsSnapshot: $0).count } ?? 0
        let codeLensStatus = lspWorkbenchResultEventStatus(
            countText: codeLensCount == 1 ? "1 action" : "\(codeLensCount) actions",
            family: "code_lens"
        ) ?? (codeLensCount == 1 ? "1 action" : "\(codeLensCount) actions")
        let inlayHintStatus = lspWorkbenchResultEventStatus(
            countText: inlayHintCount == 1 ? "1 hint" : "\(inlayHintCount) hints",
            family: "inlay_hints"
        ) ?? (inlayHintCount == 1 ? "1 hint" : "\(inlayHintCount) hints")
        let documentLinkStatus = lspWorkbenchResultEventStatus(
            countText: documentLinkCount == 1 ? "1 link" : "\(documentLinkCount) links",
            family: "document_links"
        ) ?? (documentLinkCount == 1 ? "1 link" : "\(documentLinkCount) links")
        let documentColorCount = lastDocumentColorItems.count
        let documentColorStatus = lspWorkbenchDocumentColorStatus(count: documentColorCount)
        let hierarchyCount = hierarchyPanelSnapshot?.entries.count ?? 0
        let hierarchyStatus = lspWorkbenchResultEventStatus(
            countText: hierarchyCount == 1 ? "1 result" : "\(hierarchyCount) results",
            family: "hierarchy"
        ) ?? (hierarchyCount == 1 ? "1 result" : "\(hierarchyCount) results")

        return [
            .init(
                id: LspWorkbenchItemID.activeProblems,
                title: "Problems",
                detail: "Active document diagnostics and workspace markers for the selected tab",
                status: activeProblemsStatus,
                isEnabled: hasActiveTab,
                lifecycleState: lspWorkbenchDiagnosticsItemState(activeDiagnosticsEntry),
                isPinned: lspWorkbenchPinnedEntry(
                    diagnosticsLifecycleStore.pinnedEntriesByKey["diagnostics.active"],
                    matches: activeDiagnosticsEntry
                ),
                historyCount: activeDiagnosticsHistoryCount
            ),
            .init(
                id: LspWorkbenchItemID.workspaceProblems,
                title: "Workspace Problems",
                detail: "Workspace diagnostics projected across open and indexed documents",
                status: workspaceProblemsStatus,
                isEnabled: hasActiveTab,
                lifecycleState: lspWorkbenchDiagnosticsItemState(workspaceDiagnosticsEntry),
                isPinned: lspWorkbenchPinnedEntry(
                    diagnosticsLifecycleStore.pinnedEntriesByKey["diagnostics.workspace"],
                    matches: workspaceDiagnosticsEntry
                ),
                historyCount: workspaceDiagnosticsHistoryCount
            ),
            .init(
                id: LspWorkbenchItemID.locations,
                title: "Locations",
                detail: "Latest definition, implementation, type definition, declaration, or references result",
                status: locationStatus,
                isEnabled: locationCount > 0,
                lifecycleState: lspWorkbenchItemState(locationEntry?.state),
                isPinned: lspWorkbenchPinnedEntry(
                    lspLocationResultStore.pinnedEntriesByKey[LspWorkbenchItemID.locations],
                    matches: locationEntry
                ),
                historyCount: lspLocationResultStore.historyEntries.count,
                jumpTargetCount: locationCount
            ),
            .init(
                id: LspWorkbenchItemID.symbols,
                title: "Symbols",
                detail: "Latest document or workspace symbol result",
                status: symbolStatus,
                isEnabled: symbolCount > 0,
                lifecycleState: lspWorkbenchItemState(symbolEntry?.state),
                isPinned: lspWorkbenchPinnedEntry(
                    lspSymbolResultStore.pinnedEntriesByKey[LspWorkbenchItemID.symbols],
                    matches: symbolEntry
                ),
                historyCount: symbolHistoryCount,
                jumpTargetCount: symbolCount
            ),
            .init(
                id: LspWorkbenchItemID.workspaceOutline,
                title: "Workspace Outline",
                detail: "Opened-document outline projected through the core workspace model",
                status: outlineStatus,
                isEnabled: outlineCount > 0,
                lifecycleState: lspWorkbenchItemState(outlineEntry?.state),
                isPinned: lspWorkbenchPinnedEntry(
                    lspSymbolResultStore.pinnedEntriesByKey[LspWorkbenchItemID.workspaceOutline],
                    matches: outlineEntry
                ),
                historyCount: outlineHistoryCount,
                jumpTargetCount: outlineCount
            ),
            .init(
                id: LspWorkbenchItemID.codeLens,
                title: "Code Lens",
                detail: "Active document code lens actions from derived decorations",
                status: codeLensStatus,
                isEnabled: codeLensCount > 0,
                lifecycleState: lspWorkbenchResultEventState(family: "code_lens"),
                isPinned: lspWorkbenchResultEventIsPinned(family: "code_lens"),
                historyCount: lspWorkbenchResultEventHistoryCount(family: "code_lens")
            ),
            .init(
                id: LspWorkbenchItemID.inlayHints,
                title: "Inlay Hints",
                detail: "Active document inlay hints from derived decorations",
                status: inlayHintStatus,
                isEnabled: inlayHintCount > 0,
                lifecycleState: lspWorkbenchResultEventState(family: "inlay_hints"),
                isPinned: lspWorkbenchResultEventIsPinned(family: "inlay_hints"),
                historyCount: lspWorkbenchResultEventHistoryCount(family: "inlay_hints")
            ),
            .init(
                id: LspWorkbenchItemID.documentLinks,
                title: "Document Links",
                detail: "Active document links from derived decorations",
                status: documentLinkStatus,
                isEnabled: documentLinkCount > 0,
                lifecycleState: lspWorkbenchResultEventState(family: "document_links"),
                isPinned: lspWorkbenchResultEventIsPinned(family: "document_links"),
                historyCount: lspWorkbenchResultEventHistoryCount(family: "document_links")
            ),
            .init(
                id: LspWorkbenchItemID.documentColors,
                title: "Document Colors",
                detail: "Document colors and color presentations for the active tab",
                status: documentColorStatus,
                isEnabled: hasActiveTab,
                lifecycleState: lspWorkbenchResultEventState(family: "document_colors"),
                isPinned: lspWorkbenchResultEventIsPinned(family: "document_colors"),
                historyCount: lspWorkbenchResultEventHistoryCount(family: "document_colors")
            ),
            .init(
                id: LspWorkbenchItemID.hierarchy,
                title: "Hierarchy",
                detail: "Latest call or type hierarchy children result",
                status: hierarchyStatus,
                isEnabled: hierarchyCount > 0,
                lifecycleState: lspWorkbenchResultEventState(family: "hierarchy"),
                isPinned: lspWorkbenchResultEventIsPinned(family: "hierarchy"),
                historyCount: lspWorkbenchResultEventHistoryCount(family: "hierarchy"),
                jumpTargetCount: hierarchyCount
            ),
        ]
    }

    private func lspWorkbenchPinnedEntry<Snapshot>(
        _ pinnedEntry: AttoLspResultLifecycleEntry<Snapshot>?,
        matches entry: AttoLspResultLifecycleEntry<Snapshot>?
    ) -> Bool {
        guard let pinnedEntry, let entry else { return false }
        return pinnedEntry.sequence == entry.sequence && pinnedEntry.family == entry.family
    }

    private func lspWorkbenchItemState(
        _ state: AttoLspResultLifecycleState?
    ) -> AttoLspWorkbenchPanelController.ItemLifecycleState {
        guard let state else { return .unknown }
        switch state {
        case .fresh:
            return .fresh
        case .stale:
            return .stale
        case .error:
            return .error
        }
    }

    private func lspWorkbenchDiagnosticsItemState(
        _ entry: AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>?
    ) -> AttoLspWorkbenchPanelController.ItemLifecycleState {
        guard let entry else { return .unknown }
        if entry.snapshot.staleReason != nil {
            return .stale
        }
        return lspWorkbenchItemState(entry.state)
    }

    private func lspWorkbenchResultEventState(
        family: String
    ) -> AttoLspWorkbenchPanelController.ItemLifecycleState {
        lspWorkbenchItemState(lspWorkbenchResultEvent(family: family)?.state)
    }

    private func lspWorkbenchDiagnosticsHistoryCount(family: String) -> Int {
        diagnosticsLifecycleStore.historyEntries.filter { $0.family == family }.count
    }

    private func lspWorkbenchResultEventHistoryCount(family: String) -> Int {
        lspResultEventStream.events.filter { $0.family == family }.count
    }

    private func lspWorkbenchLifecycleStatus<Snapshot>(
        countText: String,
        entry: AttoLspResultLifecycleEntry<Snapshot>?
    ) -> String {
        guard let entry else { return countText }
        var parts = [
            countText,
            entry.state.displayText,
            "Result #\(entry.sequence)",
            entry.family,
        ]
        if entry.title.isEmpty == false {
            parts.append(entry.title)
        }
        return parts.joined(separator: " | ")
    }

    private func lspWorkbenchDocumentColorStatus(count: Int) -> String {
        guard count > 0 else { return "request on open" }
        let countText = count == 1 ? "1 color" : "\(count) colors"
        return lspWorkbenchResultEventStatus(countText: countText, family: "document_colors") ?? "\(count) cached"
    }

    private func lspWorkbenchResultEvent(family: String) -> AttoLspResultLifecycleEvent? {
        lspResultEventStream.events.reversed().first { $0.family == family }
    }

    private func lspWorkbenchResultEventIsPinned(family: String) -> Bool {
        guard let event = lspWorkbenchResultEvent(family: family),
              let pinnedEvent = lspResultEventStream.pinnedEventsByFamily[family]
        else { return false }
        return pinnedEvent.sequence == event.sequence
    }

    private func lspWorkbenchResultEventStatus(
        countText: String,
        family: String
    ) -> String? {
        guard let event = lspWorkbenchResultEvent(family: family) else { return nil }
        return lspWorkbenchResultEventStatus(countText: countText, event: event)
    }

    private func lspWorkbenchResultEventStatus(
        countText: String,
        event: AttoLspResultLifecycleEvent
    ) -> String {
        var parts = [
            countText,
            event.state.displayText,
            "Result #\(event.sequence)",
            event.family,
        ]
        if event.title.isEmpty == false {
            parts.append(event.title)
        }
        return parts.joined(separator: " | ")
    }

    private func lspWorkbenchSymbolEntry() -> AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>? {
        if let currentEntry = lspSymbolResultStore.currentEntry,
           isWorkspaceOutlineEntry(currentEntry) == false {
            return currentEntry
        }
        return lspSymbolResultStore.historyEntries.reversed().first {
            isWorkspaceOutlineEntry($0) == false
        }
    }

    private func lspWorkbenchWorkspaceOutlineEntry() -> AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>? {
        if let currentEntry = lspSymbolResultStore.currentEntry,
           isWorkspaceOutlineEntry(currentEntry) {
            return currentEntry
        }
        return lspSymbolResultStore.historyEntries.reversed().first(where: isWorkspaceOutlineEntry)
    }

    private func isWorkspaceOutlineEntry(
        _ entry: AttoLspResultLifecycleEntry<LspSymbolResultSnapshot>
    ) -> Bool {
        entry.snapshot.title == "Workspace Outline" || entry.title.hasPrefix("Workspace Outline")
    }

    private func lspWorkbenchDiagnosticsEntry(
        family: String
    ) -> AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>? {
        diagnosticsLifecycleStore.historyEntries.reversed().first { $0.family == family }
    }

    private func lspWorkbenchDiagnosticsStatus(
        countText: String,
        entry: AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>?
    ) -> String {
        guard let entry else { return countText }
        let stateText = entry.snapshot.staleReason.map(lspWorkbenchDiagnosticsStaleText) ?? entry.state.displayText
        var parts = [
            countText,
            stateText,
            "Result #\(entry.sequence)",
            entry.family,
        ]
        if entry.title.isEmpty == false {
            parts.append(entry.title)
        }
        return parts.joined(separator: " | ")
    }

    private func lspWorkbenchDiagnosticsStaleText(_ reason: AttoDiagnosticsStaleReason) -> String {
        switch reason {
        case .documentEdited:
            return "Stale: document edited"
        case .workspaceRefreshRequested:
            return "Stale: workspace refresh requested"
        }
    }

    func makeLspWorkbenchDockView() -> AttoLspWorkbenchDockView {
        AttoLspWorkbenchDockView(
            onOpen: { [weak self] item in
                self?.openLspWorkbenchItem(item)
            },
            onOpenHistory: { [weak self] item in
                self?.showLspWorkbenchHistoryPanel(family: item.id)
            },
            onClose: { [weak self] in
                self?.hideLspWorkbenchDock()
            }
        )
    }

    private func makeLspWorkbenchPanelController() -> AttoLspWorkbenchPanelController {
        AttoLspWorkbenchPanelController(
            onOpen: { [weak self] item in
                self?.openLspWorkbenchItem(item)
            },
            onOpenHistory: { [weak self] item in
                self?.showLspWorkbenchHistoryPanel(family: item.id)
            }
        )
    }

    private func selectedLspWorkbenchItem() -> AttoLspWorkbenchPanelController.Item? {
        if lspWorkbenchDockView?.isVisible == true,
           let item = lspWorkbenchDockView?.selectedItem {
            return item
        }
        if let item = lspWorkbenchPanelController?.selectedItem {
            return item
        }
        return nil
    }

    private func openLspWorkbenchItem(_ item: AttoLspWorkbenchPanelController.Item) {
        switch item.id {
        case LspWorkbenchItemID.activeProblems:
            _ = showProblemsPanelInActiveTab()
        case LspWorkbenchItemID.workspaceProblems:
            _ = showWorkspaceProblemsPanelInActiveTab()
        case LspWorkbenchItemID.locations:
            _ = showLspLocationPanel()
        case LspWorkbenchItemID.symbols:
            if let entry = lspWorkbenchSymbolEntry() {
                _ = openLspSymbolEntry(entry)
            } else {
                NSSound.beep()
            }
        case LspWorkbenchItemID.workspaceOutline:
            _ = showWorkspaceOutlinePanel()
        case LspWorkbenchItemID.codeLens:
            _ = showCodeLensPanelInActiveTab()
        case LspWorkbenchItemID.inlayHints:
            _ = showInlayHintsPanelInActiveTab()
        case LspWorkbenchItemID.documentLinks:
            _ = showDocumentLinksPanelInActiveTab()
        case LspWorkbenchItemID.documentColors:
            _ = showDocumentColorsPanelInActiveTab()
        case LspWorkbenchItemID.hierarchy:
            _ = showHierarchyPanelInActiveTab()
        default:
            NSSound.beep()
        }
    }
}
