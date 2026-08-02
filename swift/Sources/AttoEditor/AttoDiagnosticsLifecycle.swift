import Foundation

struct AttoDiagnosticsLifecycleSnapshot: Equatable {
    enum Scope: Equatable {
        case activeTab(tabID: UUID, fileURL: URL)
        case workspace
    }

    let scope: Scope
    let problems: [AttoUnifiedDiagnosticProblem]
    let markerProjections: [AttoDiagnosticMarkerProjection]
    let statusText: String?
}
