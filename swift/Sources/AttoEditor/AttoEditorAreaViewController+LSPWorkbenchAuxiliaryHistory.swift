import AppKit
import Foundation

extension AttoEditorAreaViewController {
    func restoreLspWorkbenchAuxiliaryHistoryEntry(
        _ entry: AttoLspWorkbenchAuxiliaryHistoryStore.Entry
    ) {
        switch entry.payload {
        case .codeLens(let items):
            let controller = codeLensPanelController ?? makeCodeLensPanelController()
            codeLensPanelController = controller
            controller.update(
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "action",
                    plural: "actions"
                )
            )

        case .inlayHints(let items):
            let controller = inlayHintPanelController ?? makeInlayHintPanelController()
            inlayHintPanelController = controller
            controller.update(
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "hint",
                    plural: "hints"
                )
            )

        case .documentLinks(let items):
            let controller = documentLinkPanelController ?? makeDocumentLinkPanelController()
            documentLinkPanelController = controller
            controller.update(
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "link",
                    plural: "links"
                )
            )

        case .documentColors(let items):
            let controller = documentColorPanelController ?? makeDocumentColorPanelController()
            documentColorPanelController = controller
            controller.update(
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "color",
                    plural: "colors"
                )
            )

        case .hierarchy(let snapshot):
            let controller = hierarchyPanelController ?? makeHierarchyPanelController()
            hierarchyPanelController = controller
            hierarchyPanelSnapshot = snapshot
            controller.update(
                snapshot: snapshot,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: snapshot.entries.count,
                    singular: "result",
                    plural: "results"
                )
            )
        }
    }

    func showLspWorkbenchAuxiliaryHistoryEntry(
        _ entry: AttoLspWorkbenchAuxiliaryHistoryStore.Entry
    ) -> Bool {
        guard let window = view.window else {
            setTransientStatusText("LSP workbench history restored: \(entry.title)")
            return true
        }

        switch entry.payload {
        case .codeLens(let items):
            guard items.isEmpty == false else {
                NSSound.beep()
                return false
            }
            let controller = codeLensPanelController ?? makeCodeLensPanelController()
            codeLensPanelController = controller
            return controller.show(
                relativeTo: window,
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "action",
                    plural: "actions"
                )
            )

        case .inlayHints(let items):
            guard items.isEmpty == false else {
                NSSound.beep()
                return false
            }
            let controller = inlayHintPanelController ?? makeInlayHintPanelController()
            inlayHintPanelController = controller
            return controller.show(
                relativeTo: window,
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "hint",
                    plural: "hints"
                )
            )

        case .documentLinks(let items):
            guard items.isEmpty == false else {
                NSSound.beep()
                return false
            }
            let controller = documentLinkPanelController ?? makeDocumentLinkPanelController()
            documentLinkPanelController = controller
            return controller.show(
                relativeTo: window,
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "link",
                    plural: "links"
                )
            )

        case .documentColors(let items):
            guard items.isEmpty == false else {
                NSSound.beep()
                return false
            }
            let controller = documentColorPanelController ?? makeDocumentColorPanelController()
            documentColorPanelController = controller
            return controller.show(
                relativeTo: window,
                items: items,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: items.count,
                    singular: "color",
                    plural: "colors"
                )
            )

        case .hierarchy(let snapshot):
            guard snapshot.entries.isEmpty == false else {
                NSSound.beep()
                return false
            }
            let controller = hierarchyPanelController ?? makeHierarchyPanelController()
            hierarchyPanelController = controller
            hierarchyPanelSnapshot = snapshot
            return controller.show(
                relativeTo: window,
                snapshot: snapshot,
                metadataText: lspWorkbenchAuxiliaryMetadata(
                    entry,
                    count: snapshot.entries.count,
                    singular: "result",
                    plural: "results"
                )
            )
        }
    }

    private func lspWorkbenchAuxiliaryMetadata(
        _ entry: AttoLspWorkbenchAuxiliaryHistoryStore.Entry,
        count: Int,
        singular: String,
        plural: String
    ) -> String? {
        lspResultEventPanelMetadata(
            countText: AttoLspResultMetadataText.count(count, singular: singular, plural: plural),
            eventSequence: entry.eventSequence
        )
    }
}
