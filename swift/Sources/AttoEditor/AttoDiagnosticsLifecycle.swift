import Foundation

enum AttoDiagnosticsStaleReason: String, Equatable {
    case documentEdited = "document_edited"
    case workspaceRefreshRequested = "workspace_refresh_requested"
}

struct AttoDiagnosticsLifecycleSnapshot: Equatable {
    enum Scope: Equatable {
        case activeTab(tabID: UUID, fileURL: URL)
        case workspace
    }

    let scope: Scope
    let problems: [AttoUnifiedDiagnosticProblem]
    let markerProjections: [AttoDiagnosticMarkerProjection]
    let statusText: String?
    let staleReason: AttoDiagnosticsStaleReason?

    var isStale: Bool {
        staleReason != nil
    }
}
