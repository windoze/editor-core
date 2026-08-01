@testable import AttoEditor
import XCTest

final class AttoLspCodeActionContextTests: XCTestCase {
    func testCodeActionContextIncludesDiagnosticsIntersectingCaret() throws {
        let diagnosticsJSON = """
        {
          "diagnostics": [
            {
              "range": { "start": 4, "end": 6 },
              "severity": "warning",
              "code": "unused",
              "source": "unit-test",
              "message": "emoji is unused",
              "related_information_json": "[{\\"message\\":\\"related\\"}]",
              "data_json": "{\\"fix_id\\":7}"
            },
            {
              "range": { "start": 10, "end": 14 },
              "severity": "error",
              "message": "outside selection"
            }
          ]
        }
        """

        let context = try object(
            AttoLspCodeActionContext.contextJSON(
                diagnosticsJSON: diagnosticsJSON,
                documentText: "let 😀x\nnext\n",
                selectionStart: 5,
                selectionEnd: 5
            )
        )
        let diagnostics = try XCTUnwrap(context["diagnostics"] as? [[String: Any]])
        XCTAssertEqual(diagnostics.count, 1)

        let first = diagnostics[0]
        XCTAssertEqual(first["severity"] as? Int, 2)
        XCTAssertEqual(first["code"] as? String, "unused")
        XCTAssertEqual(first["source"] as? String, "unit-test")
        XCTAssertEqual(first["message"] as? String, "emoji is unused")

        let range = try XCTUnwrap(first["range"] as? [String: Any])
        let start = try XCTUnwrap(range["start"] as? [String: Any])
        let end = try XCTUnwrap(range["end"] as? [String: Any])
        XCTAssertEqual(start["line"] as? Int, 0)
        XCTAssertEqual(start["character"] as? Int, 4)
        XCTAssertEqual(end["line"] as? Int, 0)
        XCTAssertEqual(end["character"] as? Int, 7)

        let related = try XCTUnwrap(first["relatedInformation"] as? [[String: Any]])
        XCTAssertEqual(related.first?["message"] as? String, "related")
        let data = try XCTUnwrap(first["data"] as? [String: Any])
        XCTAssertEqual(data["fix_id"] as? Int, 7)
    }

    func testCodeActionContextFiltersDiagnosticsOutsideSelection() throws {
        let diagnosticsJSON = """
        {
          "diagnostics": [
            {
              "range": { "start": 8, "end": 12 },
              "severity": 1,
              "message": "outside selection"
            }
          ]
        }
        """

        let context = try object(
            AttoLspCodeActionContext.contextJSON(
                diagnosticsJSON: diagnosticsJSON,
                documentText: "let value\n",
                selectionStart: 0,
                selectionEnd: 3
            )
        )
        let diagnostics = try XCTUnwrap(context["diagnostics"] as? [[String: Any]])
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testCodeActionContextFallsBackToEmptyDiagnosticsForInvalidSnapshot() throws {
        let context = try object(
            AttoLspCodeActionContext.contextJSON(
                diagnosticsJSON: "not json",
                documentText: "",
                selectionStart: 0,
                selectionEnd: 0
            )
        )
        let diagnostics = try XCTUnwrap(context["diagnostics"] as? [[String: Any]])
        XCTAssertTrue(diagnostics.isEmpty)
    }

    private func object(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        )
    }
}
