import Foundation

extension AttoEditorAreaViewController {
    func lspResultEventPanelMetadata(
        countText: String,
        family: String
    ) -> String? {
        guard let event = lspResultEventStream.events.reversed().first(where: { $0.family == family }) else {
            return nil
        }
        return AttoLspResultMetadataText.event(event, countText: countText)
    }

    func lspResultEventPanelMetadata(
        countText: String,
        eventSequence: UInt64
    ) -> String? {
        guard let event = lspResultEventStream.events.first(where: { $0.sequence == eventSequence }) else {
            return nil
        }
        return AttoLspResultMetadataText.event(event, countText: countText)
    }

    func lspDiagnosticsPanelMetadata(
        countText: String,
        family: String
    ) -> String? {
        guard let entry = diagnosticsLifecycleStore.historyEntries.reversed().first(where: { $0.family == family }) else {
            return nil
        }
        let stateText = entry.snapshot.staleReason.map(AttoLspResultMetadataText.diagnosticsStaleText)
            ?? entry.state.displayText
        return AttoLspResultMetadataText.entry(entry, countText: countText, stateText: stateText)
    }
}
