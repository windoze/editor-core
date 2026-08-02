import Foundation

struct AttoWorkspaceProblemsSnapshot: Equatable {
    let documents: [AttoLspWorkspaceDiagnosticsParser.DocumentReport]
    let diagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic]

    static let empty = AttoWorkspaceProblemsSnapshot(documents: [], diagnostics: [])

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
}

final class AttoWorkspaceProblemsStore {
    private var documentsByURI: [String: AttoLspWorkspaceDiagnosticsParser.DocumentReport] = [:]
    private var documentOrder: [String] = []

    var snapshot: AttoWorkspaceProblemsSnapshot {
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
        snapshot.previousResultIdsJSON()
    }

    func clear() {
        documentsByURI.removeAll()
        documentOrder.removeAll()
    }

    @discardableResult
    func apply(_ result: AttoLspWorkspaceDiagnosticsParser.ParseResult) -> AttoWorkspaceProblemsSnapshot {
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
        return snapshot
    }

    private func remember(uri: String) {
        guard documentOrder.contains(uri) == false else { return }
        documentOrder.append(uri)
    }
}
