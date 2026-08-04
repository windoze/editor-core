import Foundation

enum AttoLspResultMetadataText {
    static func count(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    static func activeTab(countText: String) -> String {
        "Active Tab | \(countText)"
    }

    static func entry<Snapshot>(
        _ entry: AttoLspResultLifecycleEntry<Snapshot>,
        countText: String? = nil,
        stateText: String? = nil
    ) -> String {
        result(
            countText: countText,
            stateText: stateText ?? entry.state.displayText,
            sequence: entry.sequence,
            family: entry.family,
            title: entry.title
        )
    }

    static func event(
        _ event: AttoLspResultLifecycleEvent,
        countText: String? = nil
    ) -> String {
        result(
            countText: countText,
            stateText: event.state.displayText,
            sequence: event.sequence,
            family: event.family,
            title: event.title
        )
    }

    static func result(
        countText: String? = nil,
        stateText: String,
        sequence: UInt64,
        family: String,
        title: String
    ) -> String {
        var parts: [String] = []
        if let countText, countText.isEmpty == false {
            parts.append(countText)
        }
        parts.append(stateText)
        parts.append(sequence == 0 ? "Snapshot" : "Result #\(sequence)")
        if family.isEmpty == false {
            parts.append(family)
        }
        if title.isEmpty == false {
            parts.append(title)
        }
        return parts.joined(separator: " | ")
    }

    static func diagnosticsStaleText(_ reason: AttoDiagnosticsStaleReason) -> String {
        switch reason {
        case .documentEdited:
            return "Stale: document edited"
        case .workspaceRefreshRequested:
            return "Stale: workspace refresh requested"
        }
    }
}
