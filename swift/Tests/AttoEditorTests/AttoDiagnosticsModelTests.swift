import EditorCoreUIFFI
@testable import AttoEditor
import XCTest

final class AttoDiagnosticsModelTests: XCTestCase {
    func testMarkerSnapshotMergesActiveAndWorkspaceDiagnostics() throws {
        let tabURL = URL(fileURLWithPath: "/project/main.swift")
        let text = "first\nab😀cd\nthird\n"
        let snapshot = AttoDiagnosticsModel.markerSnapshot(
            activeDiagnostics: [
                EcuDiagnostic(
                    range: EcuOffsetRange(start: 0, end: 5),
                    severity: .warning,
                    code: nil,
                    source: nil,
                    message: "active warning",
                    relatedInformationJSON: nil,
                    dataJSON: nil
                ),
                EcuDiagnostic(
                    range: EcuOffsetRange(start: 0, end: 5),
                    severity: .warning,
                    code: nil,
                    source: nil,
                    message: "duplicate active warning",
                    relatedInformationJSON: nil,
                    dataJSON: nil
                ),
            ],
            includeActiveDiagnostics: true,
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
    }

    func testMarkerSnapshotCanExcludeActiveDiagnostics() throws {
        let tabURL = URL(fileURLWithPath: "/project/main.swift")
        let text = "abc\n"
        let snapshot = AttoDiagnosticsModel.markerSnapshot(
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
