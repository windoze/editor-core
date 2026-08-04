import AppKit
import EditorCoreUI

extension AttoEditorAreaViewController {
    @discardableResult
    func failLspEventResult(
        family: String,
        message: AttoLspResultFeedback.Message,
        showFeedback: Bool,
        editorView: EditorCoreSkiaView?,
        cancel: (() -> Void)? = nil,
        beep: Bool = true
    ) -> Bool {
        cancel?()
        markCurrentLspEventResultError(family: family, message: message)
        if showFeedback, let editorView {
            presentLspResultFeedback(message, in: editorView)
        }
        if beep {
            NSSound.beep()
        }
        return false
    }

    @discardableResult
    func failDiagnosticsLifecycleResult(
        family: String,
        message: AttoLspResultFeedback.Message,
        showFeedback: Bool,
        editorView: EditorCoreSkiaView?,
        cancel: (() -> Void)? = nil,
        beep: Bool = true
    ) -> Bool {
        cancel?()
        markCurrentDiagnosticsLifecycleError(family: family, message: message)
        if showFeedback, let editorView {
            presentLspResultFeedback(message, in: editorView)
        }
        if beep {
            NSSound.beep()
        }
        return false
    }

    @discardableResult
    func markCurrentDiagnosticsLifecycleError(
        family: String,
        message: AttoLspResultFeedback.Message
    ) -> Bool {
        guard let entry = currentDiagnosticsLifecycleEntry(family: family),
              let updatedEntry = diagnosticsLifecycleStore.updateState(
                for: entry,
                .error(message: message.statusText)
              )
        else {
            return false
        }

        lspResultEventStream.updateLatestStates(
            families: [family],
            state: .error(message: message.statusText),
            ownerMatches: { [weak self] owner in
                self?.diagnosticsLifecycleOwnerMatches(owner, scope: updatedEntry.snapshot.scope) ?? false
            }
        )
        updateVisibleLspWorkbenchPanel()
        updateVisibleLspWorkbenchHistoryPanel()
        return true
    }

    func currentDiagnosticsLifecycleEntry(
        family: String
    ) -> AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>? {
        diagnosticsLifecycleStore.historyEntries.reversed().first {
            $0.family == family && diagnosticsLifecycleEntryMatchesCurrentScope($0)
        }
    }

    func diagnosticsLifecycleEntryMatchesCurrentScope(
        _ entry: AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>
    ) -> Bool {
        diagnosticsLifecycleOwnerMatches(entry.owner, scope: entry.snapshot.scope)
    }

    func diagnosticsLifecycleDisplayStateText(
        for entry: AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>
    ) -> String {
        if case .error = entry.state {
            return entry.state.displayText
        }
        return entry.snapshot.staleReason.map(AttoLspResultMetadataText.diagnosticsStaleText)
            ?? entry.state.displayText
    }

    private func diagnosticsLifecycleOwnerMatches(
        _ owner: AttoLspResultOwner?,
        scope: AttoDiagnosticsLifecycleSnapshot.Scope
    ) -> Bool {
        switch scope {
        case .activeTab:
            return lspResultOwnerMatchesActiveDocument(owner)
        case .workspace:
            return lspResultOwnerMatchesWorkspace(owner)
        }
    }
}
