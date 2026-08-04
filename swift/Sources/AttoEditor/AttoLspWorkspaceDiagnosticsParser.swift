import EditorCoreUIFFI
import Foundation

enum AttoLspWorkspaceDiagnosticsParser {
    struct Diagnostic: Equatable {
        let target: AttoLspDefinitionParser.Target
        let endLine: Int
        let endUTF16Character: Int
        let severity: Int?
        let severityLabel: String?
        let code: String?
        let source: String?
        let message: String
        let resultId: String?
    }

    struct DocumentReport: Equatable {
        let uri: String
        let kind: String
        let resultId: String?
        let diagnostics: [Diagnostic]
    }

    struct ParseResult: Equatable {
        let documents: [DocumentReport]
        let diagnostics: [Diagnostic]

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

    static func parse(_ json: String) -> ParseResult {
        guard let root = jsonRoot(json) else {
            return ParseResult(documents: [], diagnostics: [])
        }

        var documents: [DocumentReport] = []
        appendDocumentReports(from: root, fallbackURI: nil, into: &documents)
        return ParseResult(
            documents: documents,
            diagnostics: documents.flatMap(\.diagnostics)
        )
    }

    static func parse(_ result: EcuLspWorkspaceDiagnosticResult) -> ParseResult {
        let documents = result.items.flatMap { documentReports(from: $0) }
        return ParseResult(
            documents: documents,
            diagnostics: documents.flatMap(\.diagnostics)
        )
    }

    private static func documentReports(
        from item: EcuLspWorkspaceDiagnosticReportItem
    ) -> [DocumentReport] {
        var reports = [
            documentReport(
                uri: item.uri,
                kind: item.kind,
                resultId: item.resultId,
                diagnostics: item.diagnostics
            ),
        ]

        for (relatedURI, relatedReport) in item.relatedDocuments.sorted(by: { $0.key < $1.key }) {
            reports.append(contentsOf: documentReports(
                from: relatedReport,
                fallbackURI: relatedURI
            ))
        }
        return reports
    }

    private static func documentReports(
        from report: EcuLspDiagnosticReport,
        fallbackURI: String
    ) -> [DocumentReport] {
        var reports = [
            documentReport(
                uri: fallbackURI,
                kind: report.kind,
                resultId: report.resultId,
                diagnostics: report.diagnostics
            ),
        ]

        for (relatedURI, relatedReport) in report.relatedDocuments.sorted(by: { $0.key < $1.key }) {
            reports.append(contentsOf: documentReports(
                from: relatedReport,
                fallbackURI: relatedURI
            ))
        }
        return reports
    }

    private static func documentReport(
        uri: String,
        kind: String,
        resultId: String?,
        diagnostics: [EcuLspDiagnostic]
    ) -> DocumentReport {
        DocumentReport(
            uri: uri,
            kind: kind,
            resultId: resultId,
            diagnostics: diagnostics.map { diagnostic(from: $0, uri: uri, resultId: resultId) }
        )
    }

    private static func appendDocumentReports(
        from any: Any,
        fallbackURI: String?,
        into out: inout [DocumentReport]
    ) {
        if any is NSNull { return }

        if let arr = any as? [Any] {
            for item in arr {
                appendDocumentReports(from: item, fallbackURI: fallbackURI, into: &out)
            }
            return
        }

        guard let dict = any as? [String: Any] else { return }

        if let items = dict["items"] as? [Any], dict["kind"] == nil {
            for item in items {
                appendDocumentReports(from: item, fallbackURI: nil, into: &out)
            }
            return
        }

        guard let uri = nonEmptyString(dict["uri"]) ?? fallbackURI else { return }
        let kind = nonEmptyString(dict["kind"]) ?? "full"
        let resultId = nonEmptyString(dict["resultId"])
        let diagnostics = (dict["items"] as? [Any] ?? []).compactMap {
            diagnostic(from: $0, uri: uri, resultId: resultId)
        }
        out.append(DocumentReport(uri: uri, kind: kind, resultId: resultId, diagnostics: diagnostics))

        guard let related = dict["relatedDocuments"] as? [String: Any] else { return }
        for (relatedURI, report) in related.sorted(by: { $0.key < $1.key }) {
            appendDocumentReports(from: report, fallbackURI: relatedURI, into: &out)
        }
    }

    private static func diagnostic(from any: Any, uri: String, resultId: String?) -> Diagnostic? {
        guard let dict = any as? [String: Any] else { return nil }
        guard let range = dict["range"] as? [String: Any],
              let start = range["start"] as? [String: Any],
              let end = range["end"] as? [String: Any],
              let startLine = intValue(start["line"]),
              let startCharacter = intValue(start["character"]),
              let endLine = intValue(end["line"]),
              let endCharacter = intValue(end["character"])
        else {
            return nil
        }

        guard let message = nonEmptyString(dict["message"]) else { return nil }
        let severity = intValue(dict["severity"])

        return Diagnostic(
            target: AttoLspDefinitionParser.Target(
                uri: uri,
                line: startLine,
                utf16Character: startCharacter
            ),
            endLine: endLine,
            endUTF16Character: endCharacter,
            severity: severity,
            severityLabel: severityLabel(severity),
            code: codeString(dict["code"]),
            source: nonEmptyString(dict["source"]),
            message: message,
            resultId: resultId
        )
    }

    private static func diagnostic(
        from diagnostic: EcuLspDiagnostic,
        uri: String,
        resultId: String?
    ) -> Diagnostic {
        Diagnostic(
            target: AttoLspDefinitionParser.Target(
                uri: uri,
                line: Int(diagnostic.range.start.line),
                utf16Character: Int(diagnostic.range.start.utf16Character)
            ),
            endLine: Int(diagnostic.range.end.line),
            endUTF16Character: Int(diagnostic.range.end.utf16Character),
            severity: diagnostic.severity,
            severityLabel: diagnostic.severityLabel,
            code: diagnostic.codeString,
            source: nonEmptyString(diagnostic.source),
            message: diagnostic.message,
            resultId: resultId
        )
    }

    private static func jsonRoot(_ json: String) -> Any? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func nonEmptyString(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : s
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }

    private static func codeString(_ any: Any?) -> String? {
        if let s = nonEmptyString(any) { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func severityLabel(_ value: Int?) -> String? {
        switch value {
        case 1:
            return "error"
        case 2:
            return "warning"
        case 3:
            return "information"
        case 4:
            return "hint"
        default:
            return nil
        }
    }
}
