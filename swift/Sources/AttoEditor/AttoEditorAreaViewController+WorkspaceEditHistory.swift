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
                    guard let self else { return false }
                    let undone = self.undoLastCoreWorkspaceEditTransaction()
                    self.refreshWorkspaceEditHistoryPanelIfVisible()
                    return undone
                },
                onReapply: { [weak self] workspaceEditJSON in
                    guard let self else { return false }
                    return self.reapplyWorkspaceEditHistoryTransaction(workspaceEditJSON)
                },
                onRerunRequest: { [weak self] sequence in
                    guard let self else { return false }
                    return self.rerunWorkspaceEditHistoryRequest(sequence)
                },
                onOpenConflict: { [weak self] uri in
                    guard let self else { return false }
                    return self.openWorkspaceEditHistoryConflictTarget(uri)
                },
                onSaveConflict: { [weak self] uri in
                    guard let self else { return false }
                    return self.saveWorkspaceEditHistoryConflictTarget(uri)
                },
                onDiscardConflict: { [weak self] uri in
                    guard let self else { return false }
                    return self.discardWorkspaceEditHistoryConflictTarget(uri)
                },
                onSaveConflictAndReapply: { [weak self] uri, workspaceEditJSON in
                    guard let self else { return false }
                    return self.saveWorkspaceEditHistoryConflictTarget(
                        uri,
                        reapplyWorkspaceEditJSON: workspaceEditJSON
                    )
                },
                onDiscardConflictAndReapply: { [weak self] uri, workspaceEditJSON in
                    guard let self else { return false }
                    return self.discardWorkspaceEditHistoryConflictTarget(
                        uri,
                        reapplyWorkspaceEditJSON: workspaceEditJSON
                    )
                },
                onSaveConflictAndRerunRequest: { [weak self] uri, sequence in
                    guard let self else { return false }
                    return self.saveWorkspaceEditHistoryConflictTarget(
                        uri,
                        rerunRequestSequence: sequence
                    )
                },
                onDiscardConflictAndRerunRequest: { [weak self] uri, sequence in
                    guard let self else { return false }
                    return self.discardWorkspaceEditHistoryConflictTarget(
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
                requestRetryDescriptorsBySequence: workspaceEditRequestRetryDescriptorsBySequence(for: snapshot)
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
            reportWorkspaceEditHistoryRequestRetryUnavailable(sequence)
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
        guard workspaceEditHistoryRequestRetryAvailable(sequence) else { return false }
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
        guard workspaceEditHistoryRequestRetryAvailable(sequence) else { return false }
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
            let snapshot = try coreDocuments.workspaceEditTransactionEvents()
            guard let event = snapshot.events.last else { return }
            let sequence = event.sequence
            guard sequence > 0 else { return }
            workspaceEditRequestRetryOwnersByTransactionSequence[sequence] = owner
            try workspaceEditRequestOwnerStore.append(
                record: AttoWorkspaceEditRequestOwnerRecord(
                    recordedAt: Date(),
                    workspaceRootURI: workspaceRootURL.standardizedFileURL.absoluteString,
                    transactionSequence: sequence,
                    workspaceEditJSON: event.workspaceEditJSON,
                    descriptor: owner.descriptor
                )
            )
            pruneWorkspaceEditRequestRetryOwners(maxCount: 64)
        } catch {
            NSLog(
                "AttoEditor: failed to record WorkspaceEdit request retry owner: %@",
                String(describing: error)
            )
        }
    }

    private func workspaceEditRequestRetryDescriptorsBySequence(
        for snapshot: EcuWorkspaceEditTransactionEventsSnapshot
    ) -> [UInt64: AttoWorkspaceEditRequestRetryDescriptor] {
        var descriptors: [UInt64: AttoWorkspaceEditRequestRetryDescriptor] = [:]
        let eventsBySequence = Dictionary(uniqueKeysWithValues: snapshot.events.map { ($0.sequence, $0) })
        let persistedRecords = workspaceEditRequestOwnerStore.loadRecent(
            workspaceRootURL: workspaceRootURL,
            limit: max(snapshot.events.count, 64)
        )
        for record in persistedRecords {
            guard let event = eventsBySequence[record.transactionSequence],
                  workspaceEditOwnerRecord(record, matches: event)
            else {
                continue
            }
            descriptors[record.transactionSequence] = persistedUnavailableDescriptor(record.descriptor)
        }

        for (sequence, owner) in workspaceEditRequestRetryOwnersByTransactionSequence {
            descriptors[sequence] = owner.descriptor
        }
        return descriptors
    }

    private func workspaceEditRequestRetryDescriptorForHistorySequence(
        _ sequence: UInt64
    ) -> AttoWorkspaceEditRequestRetryDescriptor? {
        guard let coreDocuments,
              let snapshot = try? coreDocuments.workspaceEditTransactionEvents()
        else {
            return nil
        }
        return workspaceEditRequestRetryDescriptorsBySequence(for: snapshot)[sequence]
    }

    private func workspaceEditOwnerRecord(
        _ record: AttoWorkspaceEditRequestOwnerRecord,
        matches event: EcuWorkspaceEditTransactionEvent
    ) -> Bool {
        guard let recordWorkspaceEditJSON = record.workspaceEditJSON else { return true }
        return recordWorkspaceEditJSON == event.workspaceEditJSON
    }

    private func persistedUnavailableDescriptor(
        _ descriptor: AttoWorkspaceEditRequestRetryDescriptor
    ) -> AttoWorkspaceEditRequestRetryDescriptor {
        guard descriptor.invalidationReason == nil else { return descriptor }
        return descriptor.invalidated(.requestClosureUnavailable)
    }

    private func workspaceEditHistoryRequestRetryAvailable(_ sequence: UInt64) -> Bool {
        if let owner = workspaceEditRequestRetryOwnersByTransactionSequence[sequence] {
            guard owner.descriptor.canRerun else {
                setTransientStatusText(owner.descriptor.retryUnavailableStatusText)
                NSSound.beep()
                return false
            }
            return true
        }
        reportWorkspaceEditHistoryRequestRetryUnavailable(sequence)
        return false
    }

    private func reportWorkspaceEditHistoryRequestRetryUnavailable(_ sequence: UInt64) {
        if let descriptor = workspaceEditRequestRetryDescriptorForHistorySequence(sequence) {
            setTransientStatusText(descriptor.retryUnavailableStatusText)
        } else {
            setTransientStatusText("WorkspaceEdit request retry source unavailable")
        }
        NSSound.beep()
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
