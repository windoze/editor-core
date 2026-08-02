import EditorCoreUIFFI
import Foundation

struct AttoDiagnosticMarkerProjection: Equatable {
    enum Source: String, Equatable {
        case active
        case workspace
    }

    let logicalLine: UInt32
    let charOffset: UInt32
    let severity: EcuDiagnosticSeverity?
    let source: Source
}

struct AttoUnifiedDiagnosticProblem: Equatable {
    let logicalLine: UInt32
    let column: UInt32
    let severity: EcuDiagnosticSeverity?
    let message: String
    let source: AttoDiagnosticMarkerProjection.Source
}

struct AttoUnifiedDiagnosticsSnapshot: Equatable {
    let markerProjections: [AttoDiagnosticMarkerProjection]
    let problems: [AttoUnifiedDiagnosticProblem]

    static let empty = AttoUnifiedDiagnosticsSnapshot(markerProjections: [], problems: [])

    var problemsStatusText: String? {
        let count = problems.count
        guard count > 0 else { return nil }
        return count == 1 ? "Problems: 1" : "Problems: \(count)"
    }
}

enum AttoDiagnosticsModel {
    static func snapshot(
        activeDiagnostics: [EcuDiagnostic],
        includeActiveDiagnostics: Bool,
        workspaceDiagnostics: [AttoLspWorkspaceDiagnosticsParser.Diagnostic],
        workspaceMarkers: [AttoWorkspaceDiagnosticMarkerProjection],
        tabURL: URL,
        text: String,
        logicalPositionForOffset: (UInt32) -> (line: UInt32, column: UInt32)?
    ) -> AttoUnifiedDiagnosticsSnapshot {
        var projections: [AttoDiagnosticMarkerProjection] = []
        var problems: [AttoUnifiedDiagnosticProblem] = []

        if includeActiveDiagnostics {
            for diagnostic in activeDiagnostics {
                let offset = min(diagnostic.range.start, diagnostic.range.end)
                guard let position = logicalPositionForOffset(offset) else { continue }
                projections.append(AttoDiagnosticMarkerProjection(
                    logicalLine: position.line,
                    charOffset: offset,
                    severity: diagnostic.severity,
                    source: .active
                ))
                problems.append(AttoUnifiedDiagnosticProblem(
                    logicalLine: position.line,
                    column: position.column,
                    severity: diagnostic.severity,
                    message: diagnostic.message,
                    source: .active
                ))
            }
        }

        let tabURL = tabURL.standardizedFileURL
        projections.append(contentsOf: workspaceMarkers.compactMap { marker in
            guard let url = URL(string: marker.uri), url.isFileURL else { return nil }
            guard url.standardizedFileURL == tabURL else { return nil }

            let offset = AttoLspDefinitionParser.charOffsetForLspPosition(
                inText: text,
                line: marker.line,
                utf16Character: marker.utf16Character
            )
            guard let position = logicalPositionForOffset(offset) else { return nil }
            return AttoDiagnosticMarkerProjection(
                logicalLine: position.line,
                charOffset: offset,
                severity: marker.severity,
                source: .workspace
            )
        })
        problems.append(contentsOf: workspaceDiagnostics.compactMap { diagnostic in
            guard let url = URL(string: diagnostic.target.uri), url.isFileURL else { return nil }
            guard url.standardizedFileURL == tabURL else { return nil }
            return AttoUnifiedDiagnosticProblem(
                logicalLine: UInt32(clamping: diagnostic.target.line),
                column: UInt32(clamping: diagnostic.target.utf16Character),
                severity: diagnostic.severity.flatMap(Self.severity(forWorkspaceDiagnostic:)),
                message: diagnostic.message,
                source: .workspace
            )
        })

        return AttoUnifiedDiagnosticsSnapshot(
            markerProjections: uniqueMarkerProjections(projections),
            problems: uniqueProblems(problems)
        )
    }

    private static func uniqueMarkerProjections(
        _ projections: [AttoDiagnosticMarkerProjection]
    ) -> [AttoDiagnosticMarkerProjection] {
        var out: [AttoDiagnosticMarkerProjection] = []
        var seen = Set<MarkerIdentity>()
        for projection in projections {
            let identity = MarkerIdentity(projection)
            guard seen.insert(identity).inserted else { continue }
            out.append(projection)
        }
        return out
    }

    private struct MarkerIdentity: Hashable {
        let logicalLine: UInt32
        let charOffset: UInt32
        let severity: EcuDiagnosticSeverity?

        init(_ projection: AttoDiagnosticMarkerProjection) {
            self.logicalLine = projection.logicalLine
            self.charOffset = projection.charOffset
            self.severity = projection.severity
        }
    }

    private static func uniqueProblems(
        _ problems: [AttoUnifiedDiagnosticProblem]
    ) -> [AttoUnifiedDiagnosticProblem] {
        var out: [AttoUnifiedDiagnosticProblem] = []
        var seen = Set<ProblemIdentity>()
        for problem in problems {
            let identity = ProblemIdentity(problem)
            guard seen.insert(identity).inserted else { continue }
            out.append(problem)
        }
        return out
    }

    private struct ProblemIdentity: Hashable {
        let logicalLine: UInt32
        let column: UInt32
        let severity: EcuDiagnosticSeverity?
        let message: String

        init(_ problem: AttoUnifiedDiagnosticProblem) {
            self.logicalLine = problem.logicalLine
            self.column = problem.column
            self.severity = problem.severity
            self.message = problem.message
        }
    }

    private static func severity(forWorkspaceDiagnostic severity: Int) -> EcuDiagnosticSeverity? {
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
}
