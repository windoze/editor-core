import Foundation
import EditorCoreUIFFI

extension AttoEditorAreaViewController {
    func drainCoreProjectLspLifecycleEvents(_ coreDocuments: MultiDocumentEditorUI) throws {
        let snapshot = try coreDocuments.projectLspLifecycleEvents(after: coreProjectLspLifecycleEventCursor)
        coreProjectLspLifecycleEventCursor = snapshot.latestSequence
        projectLspLifecycleEventStore.record(contentsOf: snapshot.events)
    }

    static func projectLspLifecycleEventTitle(_ event: EcuProjectLspLifecycleEvent) -> String {
        let scope = projectLspEventScope(
            tabId: event.tabId,
            viewIndex: Int(event.activeViewIndex)
        )
        let server = event.serverKey.isEmpty ? event.command : event.serverKey
        let sequence = event.sequence > 0 ? " #\(event.sequence)" : ""
        var title = "Lifecycle\(sequence) [\(scope)] \(event.operation) \(event.status) \(server)"

        var details: [String] = []
        if event.languageId.isEmpty == false {
            details.append("language \(event.languageId)")
        }
        if event.trigger.isEmpty == false {
            details.append("trigger \(event.trigger)")
        }
        if let attemptId = event.attemptId {
            details.append("attempt #\(attemptId)")
        }
        if let error = compactProjectLspPanelText(event.errorMessage) {
            details.append(error)
        }
        if details.isEmpty == false {
            title += " - \(details.joined(separator: "; "))"
        }
        return title
    }
}
