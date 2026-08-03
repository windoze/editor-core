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

    func updateVisibleLspWorkbenchPanel() {
        guard lspWorkbenchPanelController?.isVisible == true else { return }
        lspWorkbenchPanelController?.update(items: lspWorkbenchItems())
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
        let locationEntry = lspLocationResultStore.currentEntry
        let symbolEntry = lspWorkbenchSymbolEntry()
        let locationCount = locationEntry?.snapshot.items.count ?? 0
        let symbolCount = symbolEntry?.snapshot.symbols.count ?? 0
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
        let documentColorCount = lastDocumentColorItems.count
        let documentColorStatus = lspWorkbenchDocumentColorStatus(count: documentColorCount)
        let hierarchyCount = hierarchyPanelSnapshot?.entries.count ?? 0

        return [
            .init(
                id: LspWorkbenchItemID.activeProblems,
                title: "Problems",
                detail: "Active document diagnostics and workspace markers for the selected tab",
                status: activeProblemsStatus,
                isEnabled: hasActiveTab
            ),
            .init(
                id: LspWorkbenchItemID.workspaceProblems,
                title: "Workspace Problems",
                detail: "Workspace diagnostics projected across open and indexed documents",
                status: workspaceProblemsStatus,
                isEnabled: hasActiveTab
            ),
            .init(
                id: LspWorkbenchItemID.locations,
                title: "Locations",
                detail: "Latest definition, implementation, type definition, declaration, or references result",
                status: locationStatus,
                isEnabled: locationCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.symbols,
                title: "Symbols",
                detail: "Latest document or workspace symbol result",
                status: symbolStatus,
                isEnabled: symbolCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.workspaceOutline,
                title: "Workspace Outline",
                detail: "Opened-document outline projected through the core workspace model",
                status: outlineStatus,
                isEnabled: outlineCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.codeLens,
                title: "Code Lens",
                detail: "Active document code lens actions from derived decorations",
                status: codeLensCount == 1 ? "1 action" : "\(codeLensCount) actions",
                isEnabled: codeLensCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.inlayHints,
                title: "Inlay Hints",
                detail: "Active document inlay hints from derived decorations",
                status: inlayHintCount == 1 ? "1 hint" : "\(inlayHintCount) hints",
                isEnabled: inlayHintCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.documentLinks,
                title: "Document Links",
                detail: "Active document links from derived decorations",
                status: documentLinkCount == 1 ? "1 link" : "\(documentLinkCount) links",
                isEnabled: documentLinkCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.documentColors,
                title: "Document Colors",
                detail: "Document colors and color presentations for the active tab",
                status: documentColorStatus,
                isEnabled: hasActiveTab
            ),
            .init(
                id: LspWorkbenchItemID.hierarchy,
                title: "Hierarchy",
                detail: "Latest call or type hierarchy children result",
                status: hierarchyCount == 1 ? "1 result" : "\(hierarchyCount) results",
                isEnabled: hierarchyCount > 0
            ),
        ]
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
        guard let event = lspWorkbenchResultEvent(family: "document_colors") else {
            return "\(count) cached"
        }
        return lspWorkbenchResultEventStatus(countText: countText, event: event)
    }

    private func lspWorkbenchResultEvent(family: String) -> AttoLspResultLifecycleEvent? {
        lspResultEventStream.events.reversed().first { $0.family == family }
    }

    private func lspWorkbenchResultEventStatus(
        countText: String,
        event: AttoLspResultLifecycleEvent
    ) -> String {
        var parts = [
            countText,
            "Fresh",
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

    private func makeLspWorkbenchPanelController() -> AttoLspWorkbenchPanelController {
        AttoLspWorkbenchPanelController { [weak self] item in
            self?.openLspWorkbenchItem(item)
        }
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
