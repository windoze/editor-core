import Foundation
@testable import AttoEditor
import XCTest

@MainActor
final class AttoConfigurationSettingsJSONLocationTests: XCTestCase {
    func testSettingsJSONLocationIndexMapsSchemaKeyPaths() throws {
        let json = """
        {
          "schema_version": 1,
          "editor": {
            "wrap_mode": "paragraph"
          },
          "language": {
            "lsp_auto_restart": {
              "server_max_attempts": {
                "swift": 99
              }
            }
          },
          "scoped_settings": [
            {
              "selectors": [],
              "editor": {
                "font_size_points": 2
              }
            }
          ]
        }
        """

        let locations = AttoConfigurationSettingsJSONLocationIndex.locations(in: json)

        XCTAssertEqual(
            locations["editor.wrap_mode"],
            try sourceLocation(of: "\"wrap_mode\"", in: json)
        )
        XCTAssertEqual(
            locations["language.lsp_auto_restart.server_max_attempts[swift]"],
            try sourceLocation(of: "\"swift\"", in: json)
        )
        XCTAssertEqual(
            locations["scoped_settings[0].selectors"],
            try sourceLocation(of: "\"selectors\"", in: json)
        )
        XCTAssertEqual(
            locations["scoped_settings[0].editor.font_size_points"],
            try sourceLocation(of: "\"font_size_points\"", in: json)
        )
    }

    func testSettingsFileValidationAttachesIssueLocationsForPanelItems() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoConfigurationSettingsJSONLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let json = """
        {
          "schema_version": 1,
          "editor": {
            "font_size_points": 2,
            "wrap_mode": "paragraph"
          },
          "scoped_settings": [
            {
              "selectors": [],
              "editor": {
                "wrap_mode": "paragraph"
              }
            }
          ]
        }
        """
        try json.write(to: settingsURL, atomically: true, encoding: .utf8)

        let report = try AttoConfigurationSettingsSchema.current.validateSettingsFile(
            at: settingsURL,
            scope: .workspace
        )
        let fontSizeIssue = try XCTUnwrap(report.result.issues.first { $0.keyPath == "editor.font_size_points" })
        let scopedWrapIssue = try XCTUnwrap(
            report.result.issues.first { $0.keyPath == "scoped_settings[0].editor.wrap_mode" }
        )

        XCTAssertEqual(
            report.location(for: fontSizeIssue),
            try sourceLocation(of: "\"font_size_points\"", in: json)
        )
        XCTAssertEqual(
            report.location(for: scopedWrapIssue),
            try sourceLocation(of: "\"wrap_mode\": \"paragraph\"", in: json, occurrence: 2)
        )

        let items = AttoSettingsValidationPanelController.items(
            for: report,
            displayName: "Workspace Settings"
        )
        let fontSizeItem = try XCTUnwrap(items.first { $0.keyPath == "editor.font_size_points" })
        XCTAssertEqual(fontSizeItem.sourceLocation, report.location(for: fontSizeIssue))
        XCTAssertTrue(fontSizeItem.status.contains("workspace"))
        XCTAssertTrue(fontSizeItem.status.contains("line "))
        XCTAssertTrue(fontSizeItem.status.contains("column "))
    }

    private func sourceLocation(
        of needle: String,
        in text: String,
        occurrence: Int = 1
    ) throws -> AttoConfigurationSettingsJSONSourceLocation {
        var searchStart = text.startIndex
        var match: Range<String.Index>?
        for _ in 0..<occurrence {
            match = text.range(of: needle, range: searchStart..<text.endIndex)
            searchStart = match?.upperBound ?? text.endIndex
        }
        let range = try XCTUnwrap(match)
        return location(at: range.lowerBound, in: text)
    }

    private func location(
        at target: String.Index,
        in text: String
    ) -> AttoConfigurationSettingsJSONSourceLocation {
        var line = 1
        var column = 1
        var offset = 0
        var cursor = text.startIndex
        while cursor < target {
            if text[cursor] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            offset += 1
            cursor = text.index(after: cursor)
        }
        return AttoConfigurationSettingsJSONSourceLocation(
            line: line,
            column: column,
            characterOffset: offset
        )
    }
}
