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
        let locationCount = lspLocationResultStore.currentEntry?.snapshot.items.count ?? 0
        let symbolCount = lspSymbolResultStore.currentEntry?.snapshot.symbols.count ?? 0
        let outlineCount = workspaceOutlineSymbolSnapshot().symbols.count
        let decorations = activeTab.map { tab -> EcuDecorationsSnapshot in
            derivedStateStore.refreshActive(editor: tab.editCore.editor)
            return derivedStateStore.active.decorations
        }
        let codeLensCount = decorations.map { AttoLspCodeLensParser.items(fromDecorationsSnapshot: $0).count } ?? 0
        let inlayHintCount = decorations.map { AttoLspInlayHintParser.items(fromDecorationsSnapshot: $0).count } ?? 0
        let documentLinkCount = decorations.map { AttoLspDocumentLinkParser.items(fromDecorationsSnapshot: $0).count } ?? 0
        let documentColorCount = lastDocumentColorItems.count
        let hierarchyCount = hierarchyPanelSnapshot?.entries.count ?? 0

        return [
            .init(
                id: LspWorkbenchItemID.activeProblems,
                title: "Problems",
                detail: "Active document diagnostics and workspace markers for the selected tab",
                status: activeProblemsCount == 1 ? "1 problem" : "\(activeProblemsCount) problems",
                isEnabled: hasActiveTab
            ),
            .init(
                id: LspWorkbenchItemID.workspaceProblems,
                title: "Workspace Problems",
                detail: "Workspace diagnostics projected across open and indexed documents",
                status: workspaceProblemsCount == 1 ? "1 problem" : "\(workspaceProblemsCount) problems",
                isEnabled: hasActiveTab
            ),
            .init(
                id: LspWorkbenchItemID.locations,
                title: "Locations",
                detail: "Latest definition, implementation, type definition, declaration, or references result",
                status: locationCount == 1 ? "1 location" : "\(locationCount) locations",
                isEnabled: locationCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.symbols,
                title: "Symbols",
                detail: "Latest document or workspace symbol result",
                status: symbolCount == 1 ? "1 symbol" : "\(symbolCount) symbols",
                isEnabled: symbolCount > 0
            ),
            .init(
                id: LspWorkbenchItemID.workspaceOutline,
                title: "Workspace Outline",
                detail: "Opened-document outline projected through the core workspace model",
                status: outlineCount == 1 ? "1 symbol" : "\(outlineCount) symbols",
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
                status: documentColorCount > 0 ? "\(documentColorCount) cached" : "request on open",
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
            _ = showLspSymbolPanel()
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
