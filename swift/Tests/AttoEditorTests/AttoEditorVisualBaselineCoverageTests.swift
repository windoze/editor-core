import Foundation
import XCTest

final class AttoEditorVisualBaselineCoverageTests: XCTestCase {
    func testManifestCoversStage14LayoutMatrix() throws {
        let manifest = try Stage14VisualCoverageManifest.load()
        let cases = manifest.cases

        XCTAssertTrue(cases.contains { $0.window.width <= 640 }, "expected a narrow-window visual baseline")
        XCTAssertTrue(cases.contains { $0.splitActiveTabRight }, "expected a multi-pane visual baseline")
        XCTAssertTrue(try cases.contains { try maxFixtureLineCount(for: $0) >= 80 }, "expected a long-file visual baseline")
        XCTAssertTrue(cases.contains { $0.selectionRanges.count >= 2 }, "expected a multi-cursor visual baseline")
        XCTAssertTrue(cases.contains { $0.diagnosticMarkers.isEmpty == false }, "expected a diagnostics visual baseline")
        XCTAssertTrue(cases.contains { $0.collapsedFolds.isEmpty == false }, "expected a folding visual baseline")
        XCTAssertTrue(cases.contains { $0.semanticTokens != nil }, "expected a semantic-overlay visual baseline")
    }

    private func maxFixtureLineCount(for visualCase: Stage14VisualCoverageCase) throws -> Int {
        try visualCase.allFixturePaths.reduce(0) { currentMax, path in
            let fixtureURL = try resourceURL(path: path)
            let text = try String(contentsOf: fixtureURL, encoding: .utf8)
            let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
            return max(currentMax, lineCount)
        }
    }

    private func resourceURL(path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        let fileName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let directory = url.deletingLastPathComponent().relativePath
        let subdirectory = directory == "." ? nil : directory

        if let resource = Bundle.module.url(
            forResource: fileName,
            withExtension: ext,
            subdirectory: subdirectory
        ) {
            return resource
        }
        if let resource = Bundle.module.url(forResource: fileName, withExtension: ext) {
            return resource
        }

        throw Stage14VisualCoverageError.missingResource("missing test resource: \(path)")
    }
}

private struct Stage14VisualCoverageManifest: Decodable {
    let cases: [Stage14VisualCoverageCase]

    static func load() throws -> Self {
        let url = try resourceURL(path: "VisualBaselines/manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private static func resourceURL(path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        let fileName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let directory = url.deletingLastPathComponent().relativePath
        let subdirectory = directory == "." ? nil : directory

        if let resource = Bundle.module.url(
            forResource: fileName,
            withExtension: ext,
            subdirectory: subdirectory
        ) {
            return resource
        }
        if let resource = Bundle.module.url(forResource: fileName, withExtension: ext) {
            return resource
        }

        throw Stage14VisualCoverageError.missingResource("missing test resource: \(path)")
    }
}

private struct Stage14VisualCoverageCase: Decodable {
    let fixture: String
    let additionalFixtures: [String]
    let window: Stage14VisualCoverageWindow
    let splitActiveTabRight: Bool
    let selectionRanges: [Stage14VisualCoveragePresence]
    let collapsedFolds: [Stage14VisualCoveragePresence]
    let semanticTokens: Stage14VisualCoveragePresence?
    let diagnosticMarkers: [Stage14VisualCoveragePresence]

    var allFixturePaths: [String] {
        [fixture] + additionalFixtures
    }

    enum CodingKeys: String, CodingKey {
        case fixture
        case additionalFixtures
        case window
        case splitActiveTabRight
        case selectionRanges
        case collapsedFolds
        case semanticTokens
        case diagnosticMarkers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fixture = try container.decode(String.self, forKey: .fixture)
        additionalFixtures = try container.decodeIfPresent([String].self, forKey: .additionalFixtures) ?? []
        window = try container.decode(Stage14VisualCoverageWindow.self, forKey: .window)
        splitActiveTabRight = try container.decodeIfPresent(Bool.self, forKey: .splitActiveTabRight) ?? false
        selectionRanges = try container.decodeIfPresent(
            [Stage14VisualCoveragePresence].self,
            forKey: .selectionRanges
        ) ?? []
        collapsedFolds = try container.decodeIfPresent(
            [Stage14VisualCoveragePresence].self,
            forKey: .collapsedFolds
        ) ?? []
        semanticTokens = try container.decodeIfPresent(
            Stage14VisualCoveragePresence.self,
            forKey: .semanticTokens
        )
        diagnosticMarkers = try container.decodeIfPresent(
            [Stage14VisualCoveragePresence].self,
            forKey: .diagnosticMarkers
        ) ?? []
    }
}

private struct Stage14VisualCoverageWindow: Decodable {
    let width: Int
}

private struct Stage14VisualCoveragePresence: Decodable {}

private enum Stage14VisualCoverageError: Error, CustomStringConvertible {
    case missingResource(String)

    var description: String {
        switch self {
        case let .missingResource(message):
            return message
        }
    }
}
