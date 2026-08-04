import EditorCoreUIFFI
import Foundation

struct AttoWorkspaceProblemsSnapshot: Equatable {
    let documents: [AttoLspWorkspaceDiagnosticsParser.DocumentReport]
    let diagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic]

    static let empty = AttoWorkspaceProblemsSnapshot(documents: [], diagnostics: [])

    init(documents: [AttoLspWorkspaceDiagnosticsParser.DocumentReport], diagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic]) {
        self.documents = documents
        self.diagnostics = diagnostics
    }

    init(coreSnapshot: EcuWorkspaceDiagnosticsSnapshot) {
        let documents = coreSnapshot.documents.map { report in
            AttoLspWorkspaceDiagnosticsParser.DocumentReport(
                uri: report.uri,
                kind: report.kind,
                resultId: report.resultId,
                diagnostics: report.diagnostics.map(Self.diagnostic(from:))
            )
        }
        self.init(
            documents: documents,
            diagnostics: coreSnapshot.diagnostics.map(Self.diagnostic(from:))
        )
    }

    func previousResultIdsJSON() -> String {
        let values = documents.compactMap { report -> [String: String]? in
            guard let resultId = report.resultId else { return nil }
            return ["uri": report.uri, "value": resultId]
        }
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    private static func diagnostic(
        from diagnostic: EcuWorkspaceDiagnostic
    ) -> AttoLspWorkspaceDiagnosticsParser.Diagnostic {
        AttoLspWorkspaceDiagnosticsParser.Diagnostic(
            target: AttoLspDefinitionParser.Target(
                uri: diagnostic.target.uri,
                line: Int(diagnostic.target.line),
                utf16Character: Int(diagnostic.target.utf16Character)
            ),
            endLine: Int(diagnostic.endLine),
            endUTF16Character: Int(diagnostic.endUTF16Character),
            severity: diagnostic.severity.map(Int.init),
            severityLabel: diagnostic.severityLabel,
            code: diagnostic.code,
            source: diagnostic.source,
            message: diagnostic.message,
            resultId: diagnostic.resultId
        )
    }
}

struct AttoWorkspaceDiagnosticMarkerProjection: Equatable {
    let uri: String
    let line: Int
    let utf16Character: Int
    let severity: EcuDiagnosticSeverity?
}

final class AttoWorkspaceProblemsStore {
    private let coreDocuments: MultiDocumentEditorUI?
    private var documentsByURI: [String: AttoLspWorkspaceDiagnosticsParser.DocumentReport] = [:]
    private var documentOrder: [String] = []
    private(set) var lastWorkspaceDiagnosticsEventSequence: UInt64 = 0
    private(set) var lastWorkspaceDiagnosticsEvents: [EcuWorkspaceDiagnosticsEvent] = []
    private(set) var coreSnapshotRefreshCount = 0
    private(set) var coreMarkerRefreshCount = 0
    private var cachedCoreSnapshot: AttoWorkspaceProblemsSnapshot?
    private var cachedCoreMarkerProjections: [AttoWorkspaceDiagnosticMarkerProjection]?

    init(coreDocuments: MultiDocumentEditorUI? = nil) {
        self.coreDocuments = coreDocuments
    }

    var snapshot: AttoWorkspaceProblemsSnapshot {
        if let snapshot = refreshCoreSnapshotIfNeeded() {
            return snapshot
        }

        let documents = documentOrder.compactMap { documentsByURI[$0] }
        return AttoWorkspaceProblemsSnapshot(
            documents: documents,
            diagnostics: documents.flatMap(\.diagnostics)
        )
    }

    var diagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic] {
        snapshot.diagnostics
    }

    func previousResultIdsJSON() -> String {
        if let json = try? coreDocuments?.workspaceDiagnosticsPreviousResultIdsJSON() {
            return json
        }
        return snapshot.previousResultIdsJSON()
    }

    func diagnosticMarkerProjections() -> [AttoWorkspaceDiagnosticMarkerProjection] {
        if let projections = refreshCoreMarkerProjectionsIfNeeded() {
            return projections
        }

        return diagnostics.map { diagnostic in
            AttoWorkspaceDiagnosticMarkerProjection(
                uri: diagnostic.target.uri,
                line: diagnostic.target.line,
                utf16Character: diagnostic.target.utf16Character,
                severity: Self.severity(forWorkspaceDiagnostic: diagnostic.severity)
            )
        }
    }

    func clear() {
        if let coreDocuments {
            try? coreDocuments.clearWorkspaceDiagnostics()
            cachedCoreSnapshot = .empty
            cachedCoreMarkerProjections = []
            coreSnapshotRefreshCount += 1
            coreMarkerRefreshCount += 1
            syncWorkspaceDiagnosticsEventCursor()
        }
        documentsByURI.removeAll()
        documentOrder.removeAll()
    }

    @discardableResult
    func apply(resultJSON json: String) -> AttoWorkspaceProblemsSnapshot {
        let result = AttoLspWorkspaceDiagnosticsParser.parse(json)
        if let coreSnapshot = try? coreDocuments?.applyWorkspaceDiagnosticsJSON(json) {
            applyToFallback(result)
            let snapshot = AttoWorkspaceProblemsSnapshot(coreSnapshot: coreSnapshot)
            cachedCoreSnapshot = snapshot
            cachedCoreMarkerProjections = nil
            coreSnapshotRefreshCount += 1
            syncWorkspaceDiagnosticsEventCursor()
            return snapshot
        }
        return apply(result)
    }

    @discardableResult
    func apply(result: EcuLspWorkspaceDiagnosticResult) -> AttoWorkspaceProblemsSnapshot {
        let parsed = AttoLspWorkspaceDiagnosticsParser.parse(result)
        if let json = result.rawJSONString,
           let coreSnapshot = try? coreDocuments?.applyWorkspaceDiagnosticsJSON(json) {
            applyToFallback(parsed)
            let snapshot = AttoWorkspaceProblemsSnapshot(coreSnapshot: coreSnapshot)
            cachedCoreSnapshot = snapshot
            cachedCoreMarkerProjections = nil
            coreSnapshotRefreshCount += 1
            syncWorkspaceDiagnosticsEventCursor()
            return snapshot
        }
        return apply(parsed)
    }

    @discardableResult
    func apply(_ result: AttoLspWorkspaceDiagnosticsParser.ParseResult) -> AttoWorkspaceProblemsSnapshot {
        applyToFallback(result)
        return snapshot
    }

    private func applyToFallback(_ result: AttoLspWorkspaceDiagnosticsParser.ParseResult) {
        for report in result.documents {
            remember(uri: report.uri)
            if report.kind.lowercased() == "unchanged", let existing = documentsByURI[report.uri] {
                documentsByURI[report.uri] = AttoLspWorkspaceDiagnosticsParser.DocumentReport(
                    uri: existing.uri,
                    kind: report.kind,
                    resultId: report.resultId ?? existing.resultId,
                    diagnostics: existing.diagnostics
                )
            } else {
                documentsByURI[report.uri] = report
            }
        }
    }

    private func remember(uri: String) {
        guard documentOrder.contains(uri) == false else { return }
        documentOrder.append(uri)
    }

    private func refreshCoreSnapshotIfNeeded() -> AttoWorkspaceProblemsSnapshot? {
        guard let coreDocuments else { return nil }
        do {
            try drainWorkspaceDiagnosticsEvents(from: coreDocuments)
            if cachedCoreSnapshot == nil {
                let snapshot = AttoWorkspaceProblemsSnapshot(
                    coreSnapshot: try coreDocuments.workspaceDiagnosticsSnapshot()
                )
                cachedCoreSnapshot = snapshot
                coreSnapshotRefreshCount += 1
            }
            return cachedCoreSnapshot
        } catch {
            guard let coreSnapshot = try? coreDocuments.workspaceDiagnosticsSnapshot() else {
                return nil
            }
            let snapshot = AttoWorkspaceProblemsSnapshot(coreSnapshot: coreSnapshot)
            cachedCoreSnapshot = snapshot
            coreSnapshotRefreshCount += 1
            lastWorkspaceDiagnosticsEvents = []
            return snapshot
        }
    }

    private func refreshCoreMarkerProjectionsIfNeeded() -> [AttoWorkspaceDiagnosticMarkerProjection]? {
        guard let coreDocuments else { return nil }
        do {
            try drainWorkspaceDiagnosticsEvents(from: coreDocuments)
            if cachedCoreMarkerProjections == nil {
                cachedCoreMarkerProjections = try coreDocuments
                    .workspaceDiagnosticMarkersSnapshot()
                    .markers
                    .map(Self.markerProjection(from:))
                coreMarkerRefreshCount += 1
            }
            return cachedCoreMarkerProjections
        } catch {
            guard let markers = try? coreDocuments.workspaceDiagnosticMarkersSnapshot().markers else {
                return nil
            }
            let projections = markers.map(Self.markerProjection(from:))
            cachedCoreMarkerProjections = projections
            coreMarkerRefreshCount += 1
            lastWorkspaceDiagnosticsEvents = []
            return projections
        }
    }

    private func drainWorkspaceDiagnosticsEvents(from coreDocuments: MultiDocumentEditorUI) throws {
        let events = try coreDocuments.workspaceDiagnosticsEvents(after: lastWorkspaceDiagnosticsEventSequence)
        lastWorkspaceDiagnosticsEventSequence = events.latestSequence
        lastWorkspaceDiagnosticsEvents = events.events
        guard events.events.isEmpty == false else { return }
        cachedCoreSnapshot = nil
        cachedCoreMarkerProjections = nil
    }

    private func syncWorkspaceDiagnosticsEventCursor() {
        guard let coreDocuments else { return }
        lastWorkspaceDiagnosticsEventSequence =
            (try? coreDocuments.workspaceDiagnosticsLatestEventSequence())
            ?? lastWorkspaceDiagnosticsEventSequence
        lastWorkspaceDiagnosticsEvents = []
    }

    private static func markerProjection(
        from marker: EcuWorkspaceDiagnosticMarker
    ) -> AttoWorkspaceDiagnosticMarkerProjection {
        AttoWorkspaceDiagnosticMarkerProjection(
            uri: marker.uri,
            line: Int(marker.line),
            utf16Character: Int(marker.utf16Character),
            severity: severity(forWorkspaceDiagnostic: marker.severity)
        )
    }

    private static func severity(forWorkspaceDiagnostic severity: UInt32?) -> EcuDiagnosticSeverity? {
        switch severity {
        case 1:
            return .error
        case 2:
            return .warning
        case 3:
            return .information
        case 4:
            return .hint
        default:
            return nil
        }
    }

    private static func severity(forWorkspaceDiagnostic severity: Int?) -> EcuDiagnosticSeverity? {
        guard let severity, severity >= 0 else { return nil }
        return Self.severity(forWorkspaceDiagnostic: UInt32(severity))
    }
}
