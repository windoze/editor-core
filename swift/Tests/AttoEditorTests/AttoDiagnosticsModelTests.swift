import EditorCoreUIFFI
@testable import AttoEditor
import XCTest

final class AttoDiagnosticsModelTests: XCTestCase {
    func testMarkerSnapshotMergesActiveAndWorkspaceDiagnostics() throws {
        let tabURL = URL(fileURLWithPath: "/project/main.swift")
        let text = "first\nab😀cd\nthird\n"
        let activeWarning = EcuDiagnostic(
            range: EcuOffsetRange(start: 0, end: 5),
            severity: .warning,
            code: nil,
            source: nil,
            message: "active warning",
            relatedInformationJSON: nil,
            dataJSON: nil
        )
        let workspaceError = Self.workspaceDiagnostic(
            uri: tabURL.absoluteString,
            line: 1,
            utf16Character: 4,
            severity: 1,
            message: "workspace error"
        )
        let snapshot = AttoDiagnosticsModel.snapshot(
            activeDiagnostics: [
                activeWarning,
                activeWarning,
            ],
            includeActiveDiagnostics: true,
            workspaceDiagnostics: [
                workspaceError,
                Self.workspaceDiagnostic(
                    uri: URL(fileURLWithPath: "/project/other.swift").absoluteString,
                    line: 0,
                    utf16Character: 0,
                    severity: 4,
                    message: "other file hint"
                ),
            ],
            workspaceMarkers: [
                AttoWorkspaceDiagnosticMarkerProjection(
                    uri: tabURL.absoluteString,
                    line: 1,
                    utf16Character: 4,
                    severity: .error
                ),
                AttoWorkspaceDiagnosticMarkerProjection(
                    uri: URL(fileURLWithPath: "/project/other.swift").absoluteString,
                    line: 0,
                    utf16Character: 0,
                    severity: .hint
                ),
            ],
            tabURL: tabURL,
            text: text,
            logicalPositionForOffset: Self.logicalPosition(in: text)
        )

        XCTAssertEqual(
            snapshot.markerProjections,
            [
                AttoDiagnosticMarkerProjection(
                    logicalLine: 0,
                    charOffset: 0,
                    severity: .warning,
                    source: .active
                ),
                AttoDiagnosticMarkerProjection(
                    logicalLine: 1,
                    charOffset: 9,
                    severity: .error,
                    source: .workspace
                ),
            ]
        )
        XCTAssertEqual(
            snapshot.problems,
            [
                AttoUnifiedDiagnosticProblem(
                    logicalLine: 0,
                    column: 0,
                    severity: .warning,
                    code: nil,
                    diagnosticSource: nil,
                    message: "active warning",
                    source: .active,
                    target: .active(activeWarning)
                ),
                AttoUnifiedDiagnosticProblem(
                    logicalLine: 1,
                    column: 4,
                    severity: .error,
                    code: nil,
                    diagnosticSource: nil,
                    message: "workspace error",
                    source: .workspace,
                    target: .workspace(workspaceError)
                ),
            ]
        )
        XCTAssertEqual(snapshot.problemsStatusText, "Problems: 2")
    }

    func testMarkerSnapshotCanExcludeActiveDiagnostics() throws {
        let tabURL = URL(fileURLWithPath: "/project/main.swift")
        let text = "abc\n"
        let snapshot = AttoDiagnosticsModel.snapshot(
            activeDiagnostics: [
                EcuDiagnostic(
                    range: EcuOffsetRange(start: 0, end: 1),
                    severity: .error,
                    code: nil,
                    source: nil,
                    message: "active problem",
                    relatedInformationJSON: nil,
                    dataJSON: nil
                ),
            ],
            includeActiveDiagnostics: false,
            workspaceDiagnostics: [
                Self.workspaceDiagnostic(
                    uri: tabURL.absoluteString,
                    line: 0,
                    utf16Character: 1,
                    severity: 4,
                    message: "workspace hint"
                ),
            ],
            workspaceMarkers: [
                AttoWorkspaceDiagnosticMarkerProjection(
                    uri: tabURL.absoluteString,
                    line: 0,
                    utf16Character: 1,
                    severity: .hint
                ),
            ],
            tabURL: tabURL,
            text: text,
            logicalPositionForOffset: Self.logicalPosition(in: text)
        )

        XCTAssertEqual(
            snapshot.markerProjections,
            [
                AttoDiagnosticMarkerProjection(
                    logicalLine: 0,
                    charOffset: 1,
                    severity: .hint,
                    source: .workspace
                ),
            ]
        )
        XCTAssertEqual(snapshot.problemsStatusText, "Problems: 1")
    }

    func testWorkspaceProblemsPreserveWorkspaceTargetsAcrossFiles() throws {
        let diagnosticA = Self.workspaceDiagnostic(
            uri: URL(fileURLWithPath: "/project/a.swift").absoluteString,
            line: 0,
            utf16Character: 1,
            severity: 1,
            message: "same message"
        )
        let diagnosticB = Self.workspaceDiagnostic(
            uri: URL(fileURLWithPath: "/project/b.swift").absoluteString,
            line: 0,
            utf16Character: 1,
            severity: 1,
            message: "same message"
        )

        let problems = AttoDiagnosticsModel.workspaceProblems([
            diagnosticA,
            diagnosticB,
            diagnosticA,
        ])

        XCTAssertEqual(
            problems,
            [
                AttoUnifiedDiagnosticProblem(
                    logicalLine: 0,
                    column: 1,
                    severity: .error,
                    code: nil,
                    diagnosticSource: nil,
                    message: "same message",
                    source: .workspace,
                    target: .workspace(diagnosticA)
                ),
                AttoUnifiedDiagnosticProblem(
                    logicalLine: 0,
                    column: 1,
                    severity: .error,
                    code: nil,
                    diagnosticSource: nil,
                    message: "same message",
                    source: .workspace,
                    target: .workspace(diagnosticB)
                ),
            ]
        )
    }

    private static func workspaceDiagnostic(
        uri: String,
        line: Int,
        utf16Character: Int,
        severity: Int,
        message: String
    ) -> AttoLspWorkspaceDiagnosticsParser.Diagnostic {
        AttoLspWorkspaceDiagnosticsParser.Diagnostic(
            target: AttoLspDefinitionParser.Target(
                uri: uri,
                line: line,
                utf16Character: utf16Character
            ),
            endLine: line,
            endUTF16Character: utf16Character + 1,
            severity: severity,
            severityLabel: nil,
            code: nil,
            source: nil,
            message: message,
            resultId: nil
        )
    }

    private static func logicalPosition(in text: String) -> (UInt32) -> (line: UInt32, column: UInt32)? {
        { offset in
            let scalars = Array(text.unicodeScalars)
            guard offset <= scalars.count else { return nil }
            var line: UInt32 = 0
            var column: UInt32 = 0
            for scalar in scalars.prefix(Int(offset)) {
                if scalar.value == 10 {
                    line += 1
                    column = 0
                } else {
                    column += 1
                }
            }
            return (line, column)
        }
    }
}
