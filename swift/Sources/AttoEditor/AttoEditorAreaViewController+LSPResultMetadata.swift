import Foundation

extension AttoEditorAreaViewController {
    func lspResultEventPanelMetadata(
        countText: String,
        family: String
    ) -> String? {
        guard let event = lspResultEventStream.events.reversed().first(where: {
            $0.family == family && lspResultOwnerMatchesActiveDocument($0.owner)
        }) else {
            return nil
        }
        return AttoLspResultMetadataText.event(event, countText: countText)
    }

    func lspResultEventPanelMetadata(
        countText: String,
        eventSequence: UInt64
    ) -> String? {
        guard let event = lspResultEvent(sequence: eventSequence) else {
            return nil
        }
        return AttoLspResultMetadataText.event(event, countText: countText)
    }

    func lspDiagnosticsPanelMetadata(
        countText: String,
        family: String
    ) -> String? {
        guard let entry = diagnosticsLifecycleStore.historyEntries.reversed().first(where: {
            $0.family == family && lspDiagnosticsResultOwnerMatchesCurrentScope($0)
        }) else {
            return nil
        }
        let stateText = entry.snapshot.staleReason.map(AttoLspResultMetadataText.diagnosticsStaleText)
            ?? entry.state.displayText
        return AttoLspResultMetadataText.entry(entry, countText: countText, stateText: stateText)
    }

    private func lspDiagnosticsResultOwnerMatchesCurrentScope(
        _ entry: AttoLspResultLifecycleEntry<AttoDiagnosticsLifecycleSnapshot>
    ) -> Bool {
        switch entry.snapshot.scope {
        case .activeTab:
            return lspResultOwnerMatchesActiveDocument(entry.owner)
        case .workspace:
            return lspResultOwnerMatchesWorkspace(entry.owner)
        }
    }

    func lspResultEvent(sequence: UInt64) -> AttoLspResultLifecycleEvent? {
        lspResultEventStream.events.first { $0.sequence == sequence }
            ?? lspResultEventStream.pinnedEventsByFamily.values.first { $0.sequence == sequence }
    }
}
