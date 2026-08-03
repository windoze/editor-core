import AppKit
import EditorCoreUIFFI
import Foundation

extension AttoEditorAreaViewController {
    @discardableResult
    func showWorkspaceEditHistoryPanel() -> Bool {
        guard let window = view.window else {
            NSSound.beep()
            return false
        }

        if workspaceEditHistoryPanelController == nil {
            workspaceEditHistoryPanelController = AttoWorkspaceEditHistoryPanelController { [weak self] in
                guard let self else { return }
                _ = self.undoLastCoreWorkspaceEditTransaction()
                self.refreshWorkspaceEditHistoryPanelIfVisible()
            }
        }

        guard let workspaceEditHistoryPanelController else { return false }
        return workspaceEditHistoryPanelController.show(
            relativeTo: window,
            items: workspaceEditHistoryItems()
        )
    }

    func refreshWorkspaceEditHistoryPanelIfVisible() {
        guard workspaceEditHistoryPanelController?.isVisible == true else { return }
        workspaceEditHistoryPanelController?.update(items: workspaceEditHistoryItems())
    }

    func workspaceEditHistoryItems() -> [AttoWorkspaceEditHistoryPanelController.Item] {
        guard let coreDocuments else { return [] }
        do {
            let snapshot = try coreDocuments.workspaceEditTransactionEvents()
            return AttoWorkspaceEditHistoryFormatter.items(
                from: snapshot,
                consumedUndoSequence: workspaceEditConsumedUndoSequence
            )
        } catch {
            NSLog("AttoEditor: failed to load WorkspaceEdit transaction history: %@", String(describing: error))
            return []
        }
    }
}
