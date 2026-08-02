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

final class AttoWorkspaceProblemsStore {
    private let coreDocuments: MultiDocumentEditorUI?
    private var documentsByURI: [String: AttoLspWorkspaceDiagnosticsParser.DocumentReport] = [:]
    private var documentOrder: [String] = []

    init(coreDocuments: MultiDocumentEditorUI? = nil) {
        self.coreDocuments = coreDocuments
    }

    var snapshot: AttoWorkspaceProblemsSnapshot {
        if let coreSnapshot = try? coreDocuments?.workspaceDiagnosticsSnapshot() {
            return AttoWorkspaceProblemsSnapshot(coreSnapshot: coreSnapshot)
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

    func clear() {
        try? coreDocuments?.clearWorkspaceDiagnostics()
        documentsByURI.removeAll()
        documentOrder.removeAll()
    }

    @discardableResult
    func apply(resultJSON json: String) -> AttoWorkspaceProblemsSnapshot {
        let result = AttoLspWorkspaceDiagnosticsParser.parse(json)
        if let coreSnapshot = try? coreDocuments?.applyWorkspaceDiagnosticsJSON(json) {
            applyToFallback(result)
            return AttoWorkspaceProblemsSnapshot(coreSnapshot: coreSnapshot)
        }
        return apply(result)
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
}
