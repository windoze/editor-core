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

struct AttoUnifiedDiagnosticsSnapshot: Equatable {
    let markerProjections: [AttoDiagnosticMarkerProjection]

    static let empty = AttoUnifiedDiagnosticsSnapshot(markerProjections: [])
}

enum AttoDiagnosticsModel {
    static func markerSnapshot(
        activeDiagnostics: [EcuDiagnostic],
        includeActiveDiagnostics: Bool,
        workspaceMarkers: [AttoWorkspaceDiagnosticMarkerProjection],
        tabURL: URL,
        text: String,
        logicalPositionForOffset: (UInt32) -> (line: UInt32, column: UInt32)?
    ) -> AttoUnifiedDiagnosticsSnapshot {
        var projections: [AttoDiagnosticMarkerProjection] = []

        if includeActiveDiagnostics {
            projections.append(contentsOf: activeDiagnostics.compactMap { diagnostic in
                let offset = min(diagnostic.range.start, diagnostic.range.end)
                guard let position = logicalPositionForOffset(offset) else { return nil }
                return AttoDiagnosticMarkerProjection(
                    logicalLine: position.line,
                    charOffset: offset,
                    severity: diagnostic.severity,
                    source: .active
                )
            })
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

        return AttoUnifiedDiagnosticsSnapshot(
            markerProjections: uniqueMarkerProjections(projections)
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
}
