import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoFindInFilesWorkspaceSearchProviderTests: XCTestCase {
    func testWorkspaceProviderFailureDoesNotFallBackToLocalFileScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoFindInFilesProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("fallback.txt")
        try "needle should not be found by fallback\n".write(to: file, atomically: true, encoding: .utf8)

        let vc = AttoFindInFilesViewController(rootURL: root)
        vc.workspaceFilesProvider = { [file] }
        vc.workspaceFilesSearchProvider = { _, _, _, _ in
            .failed("core workspace search failed")
        }

        vc._performSearchForTesting(query: "needle", scope: .workspace)

        XCTAssertEqual(vc._searchResultsForTesting(), [])
        XCTAssertEqual(
            vc._statusTextForTesting(),
            "Workspace search failed: core workspace search failed"
        )
    }

    func testUnavailableWorkspaceProviderFallsBackToLocalFileScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoFindInFilesProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("fallback.txt")
        try "prefix needle suffix\n".write(to: file, atomically: true, encoding: .utf8)

        let vc = AttoFindInFilesViewController(rootURL: root)
        vc.workspaceFilesProvider = { [file] }
        vc.workspaceFilesSearchProvider = { _, _, _, _ in .unavailable }

        vc._performSearchForTesting(query: "needle", scope: .workspace)
        waitForSearchStatus("1 results", in: vc)

        XCTAssertEqual(vc._searchResultsForTesting(), [
            AttoFindInFilesViewController.SearchResult(
                url: file.standardizedFileURL,
                line1: 1,
                column1: 8,
                lineText: "prefix needle suffix"
            ),
        ])
    }

    private func waitForSearchStatus(
        _ expected: String,
        in vc: AttoFindInFilesViewController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<100 {
            if vc._statusTextForTesting() == expected {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("expected status \(expected), got \(vc._statusTextForTesting())", file: file, line: line)
    }
}
