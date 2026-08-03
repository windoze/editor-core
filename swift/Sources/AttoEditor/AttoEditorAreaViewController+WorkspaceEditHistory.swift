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
                consumedUndoSequences: workspaceEditConsumedUndoSequences
            )
        } catch {
            NSLog("AttoEditor: failed to load WorkspaceEdit transaction history: %@", String(describing: error))
            return []
        }
    }

    func latestUndoableWorkspaceEditTransactionSequence() -> UInt64? {
        guard let coreDocuments else { return nil }
        guard let snapshot = try? coreDocuments.workspaceEditTransactionEvents() else { return nil }
        return snapshot.events.last { event in
            event.operation == "apply"
                && event.result.applied
                && workspaceEditConsumedUndoSequences.contains(event.sequence) == false
        }?.sequence
    }
}
