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
        guard let entry = currentDiagnosticsLifecycleEntry(family: family) else {
            return nil
        }
        return AttoLspResultMetadataText.entry(
            entry,
            countText: countText,
            stateText: diagnosticsLifecycleDisplayStateText(for: entry)
        )
    }

    func lspResultEvent(sequence: UInt64) -> AttoLspResultLifecycleEvent? {
        lspResultEventStream.events.first { $0.sequence == sequence }
            ?? lspResultEventStream.pinnedEventsByFamily.values.first { $0.sequence == sequence }
    }
}
