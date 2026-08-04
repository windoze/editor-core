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
            workspaceEditHistoryPanelController = AttoWorkspaceEditHistoryPanelController(
                onUndoLatest: { [weak self] in
                    guard let self else { return }
                    _ = self.undoLastCoreWorkspaceEditTransaction()
                    self.refreshWorkspaceEditHistoryPanelIfVisible()
                },
                onReapply: { [weak self] workspaceEditJSON in
                    guard let self else { return }
                    _ = self.reapplyWorkspaceEditHistoryTransaction(workspaceEditJSON)
                },
                onRerunRequest: { [weak self] sequence in
                    guard let self else { return }
                    _ = self.rerunWorkspaceEditHistoryRequest(sequence)
                },
                onOpenConflict: { [weak self] uri in
                    guard let self else { return }
                    _ = self.openWorkspaceEditHistoryConflictTarget(uri)
                },
                onSaveConflict: { [weak self] uri in
                    guard let self else { return }
                    _ = self.saveWorkspaceEditHistoryConflictTarget(uri)
                },
                onDiscardConflict: { [weak self] uri in
                    guard let self else { return }
                    _ = self.discardWorkspaceEditHistoryConflictTarget(uri)
                },
                onSaveConflictAndReapply: { [weak self] uri, workspaceEditJSON in
                    guard let self else { return }
                    _ = self.saveWorkspaceEditHistoryConflictTarget(
                        uri,
                        reapplyWorkspaceEditJSON: workspaceEditJSON
                    )
                },
                onDiscardConflictAndReapply: { [weak self] uri, workspaceEditJSON in
                    guard let self else { return }
                    _ = self.discardWorkspaceEditHistoryConflictTarget(
                        uri,
                        reapplyWorkspaceEditJSON: workspaceEditJSON
                    )
                },
                onSaveConflictAndRerunRequest: { [weak self] uri, sequence in
                    guard let self else { return }
                    _ = self.saveWorkspaceEditHistoryConflictTarget(
                        uri,
                        rerunRequestSequence: sequence
                    )
                },
                onDiscardConflictAndRerunRequest: { [weak self] uri, sequence in
                    guard let self else { return }
                    _ = self.discardWorkspaceEditHistoryConflictTarget(
                        uri,
                        rerunRequestSequence: sequence
                    )
                }
            )
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

    func closeWorkspaceEditHistoryPanel() {
        workspaceEditHistoryPanelController?.close()
        workspaceEditHistoryPanelController = nil
        workspaceEditRequestRetryOwnersByTransactionSequence.removeAll()
    }

    func workspaceEditHistoryItems() -> [AttoWorkspaceEditHistoryPanelController.Item] {
        guard let coreDocuments else { return [] }
        do {
            let snapshot = try coreDocuments.workspaceEditTransactionEvents()
            pruneWorkspaceEditRequestRetryOwners(retaining: Set(snapshot.events.map(\.sequence)))
            return AttoWorkspaceEditHistoryFormatter.items(
                from: snapshot,
                consumedUndoSequences: workspaceEditConsumedUndoSequences,
                requestRetryDescriptorsBySequence: workspaceEditRequestRetryDescriptorsBySequence()
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
            (event.operation == "apply" || event.operation == "redo")
                && event.result.applied
                && workspaceEditConsumedUndoSequences.contains(event.sequence) == false
        }?.sequence
    }

    @discardableResult
    func openWorkspaceEditHistoryConflictTarget(_ uri: String) -> Bool {
        guard let editorView = activeTab?.editCore.editorView else {
            NSSound.beep()
            return false
        }
        return openWorkspaceEditConflictTarget(uri, editorView: editorView)
    }

    @discardableResult
    func reapplyWorkspaceEditHistoryTransaction(_ workspaceEditJSON: String) -> Bool {
        let outcome = applyWorkspaceEditJSONToActiveTab(workspaceEditJSON)
        if outcome {
            setTransientStatusText("Reapplied WorkspaceEdit transaction")
            refreshWorkspaceEditHistoryPanelIfVisible()
        }
        return outcome
    }

    @discardableResult
    func rerunWorkspaceEditHistoryRequest(_ sequence: UInt64) -> Bool {
        guard let owner = workspaceEditRequestRetryOwnersByTransactionSequence[sequence] else {
            setTransientStatusText("WorkspaceEdit request retry source unavailable")
            NSSound.beep()
            return false
        }
        let started = rerunWorkspaceEditRequest(owner)
        if started {
            refreshWorkspaceEditHistoryPanelIfVisible()
        }
        return started
    }

    @discardableResult
    func saveWorkspaceEditHistoryConflictTarget(_ uri: String) -> Bool {
        guard let editorView = activeTab?.editCore.editorView else {
            NSSound.beep()
            return false
        }
        let saved = saveWorkspaceEditConflictTarget(uri, editorView: editorView)
        if saved {
            refreshWorkspaceEditHistoryPanelIfVisible()
        }
        return saved
    }

    @discardableResult
    func saveWorkspaceEditHistoryConflictTarget(
        _ uri: String,
        reapplyWorkspaceEditJSON workspaceEditJSON: String
    ) -> Bool {
        guard let editorView = activeTab?.editCore.editorView else {
            NSSound.beep()
            return false
        }
        guard saveWorkspaceEditConflictTarget(uri, editorView: editorView) else { return false }
        let outcome = applyWorkspaceEditJSONToActiveTab(workspaceEditJSON)
        if outcome {
            setTransientStatusText("Saved conflict and reapplied WorkspaceEdit")
            refreshWorkspaceEditHistoryPanelIfVisible()
        }
        return outcome
    }

    @discardableResult
    func saveWorkspaceEditHistoryConflictTarget(
        _ uri: String,
        rerunRequestSequence sequence: UInt64
    ) -> Bool {
        guard let editorView = activeTab?.editCore.editorView else {
            NSSound.beep()
            return false
        }
        guard saveWorkspaceEditConflictTarget(uri, editorView: editorView) else { return false }
        return rerunWorkspaceEditHistoryRequest(sequence)
    }

    @discardableResult
    func discardWorkspaceEditHistoryConflictTarget(_ uri: String) -> Bool {
        guard let editorView = activeTab?.editCore.editorView else {
            NSSound.beep()
            return false
        }
        let discarded = discardWorkspaceEditConflictTarget(uri, editorView: editorView)
        if discarded {
            refreshWorkspaceEditHistoryPanelIfVisible()
        }
        return discarded
    }

    @discardableResult
    func discardWorkspaceEditHistoryConflictTarget(
        _ uri: String,
        reapplyWorkspaceEditJSON workspaceEditJSON: String
    ) -> Bool {
        guard let editorView = activeTab?.editCore.editorView else {
            NSSound.beep()
            return false
        }
        guard discardWorkspaceEditConflictTarget(uri, editorView: editorView) else { return false }
        let outcome = applyWorkspaceEditJSONToActiveTab(workspaceEditJSON)
        if outcome {
            setTransientStatusText("Discarded conflict changes and reapplied WorkspaceEdit")
            refreshWorkspaceEditHistoryPanelIfVisible()
        }
        return outcome
    }

    @discardableResult
    func discardWorkspaceEditHistoryConflictTarget(
        _ uri: String,
        rerunRequestSequence sequence: UInt64
    ) -> Bool {
        guard let editorView = activeTab?.editCore.editorView else {
            NSSound.beep()
            return false
        }
        guard discardWorkspaceEditConflictTarget(uri, editorView: editorView) else { return false }
        return rerunWorkspaceEditHistoryRequest(sequence)
    }

    func recordWorkspaceEditRequestRetryOwner(
        _ owner: AttoWorkspaceEditRequestRetryOwner?,
        forLatestTransactionIn coreDocuments: MultiDocumentEditorUI
    ) {
        guard let owner else { return }
        do {
            let sequence = try coreDocuments.workspaceEditTransactionEventsLatestSequence()
            guard sequence > 0 else { return }
            workspaceEditRequestRetryOwnersByTransactionSequence[sequence] = owner
            pruneWorkspaceEditRequestRetryOwners(maxCount: 64)
        } catch {
            NSLog(
                "AttoEditor: failed to record WorkspaceEdit request retry owner: %@",
                String(describing: error)
            )
        }
    }

    private func workspaceEditRequestRetryDescriptorsBySequence()
        -> [UInt64: AttoWorkspaceEditRequestRetryDescriptor]
    {
        workspaceEditRequestRetryOwnersByTransactionSequence.mapValues(\.descriptor)
    }

    private func pruneWorkspaceEditRequestRetryOwners(retaining validSequences: Set<UInt64>) {
        workspaceEditRequestRetryOwnersByTransactionSequence = workspaceEditRequestRetryOwnersByTransactionSequence
            .filter { validSequences.contains($0.key) }
    }

    private func pruneWorkspaceEditRequestRetryOwners(maxCount: Int) {
        guard workspaceEditRequestRetryOwnersByTransactionSequence.count > maxCount else { return }
        let keepSequences = Set(workspaceEditRequestRetryOwnersByTransactionSequence.keys.sorted().suffix(maxCount))
        pruneWorkspaceEditRequestRetryOwners(retaining: keepSequences)
    }
}
