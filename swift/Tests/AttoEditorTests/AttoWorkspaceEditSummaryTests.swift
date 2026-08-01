@testable import AttoEditor
import XCTest

final class AttoWorkspaceEditSummaryTests: XCTestCase {
    func testPartialWorkspaceEditSummaryListsSkippedDocuments() throws {
        let result = AttoWorkspaceEditApplyResult(json: """
        {
          "applied": true,
          "applied_uri": "file:///project/main.swift",
          "applied_edit_count": 2,
          "skipped_uris": ["file:///project/other.swift"],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 2,
              "has_overlapping_edits": false
            },
            {
              "uri": "file:///project/other.swift",
              "edit_count": 1,
              "has_overlapping_edits": true
            }
          ]
        }
        """)

        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.appliedURI, "file:///project/main.swift")
        XCTAssertEqual(result.appliedEditCount, 2)
        XCTAssertEqual(result.skippedURIs, ["file:///project/other.swift"])
        XCTAssertEqual(
            AttoWorkspaceEditApplyResult.displayText(for: result),
            """
            Workspace edit partially applied.
            Applied 2 edits to the active document.

            Not applied:
            - other.swift (1 edit) [overlapping edits]
            """
        )
    }

    func testWorkspaceEditSummaryForOtherDocumentsOnly() throws {
        let result = AttoWorkspaceEditApplyResult(json: """
        {
          "applied": false,
          "applied_uri": "file:///project/main.swift",
          "applied_edit_count": 0,
          "skipped_uris": ["file:///project/rename.swift"],
          "documents": [
            {
              "uri": "file:///project/rename.swift",
              "edit_count": 3,
              "has_overlapping_edits": false
            }
          ]
        }
        """)

        XCTAssertFalse(result.applied)
        XCTAssertEqual(
            AttoWorkspaceEditApplyResult.displayText(for: result),
            """
            Workspace edit targets other documents.
            No edits were applied to the active document.

            Affected documents:
            - rename.swift (3 edits)
            """
        )
    }

    func testWorkspaceEditSummaryIsNilWhenNothingWasSkipped() throws {
        let result = AttoWorkspaceEditApplyResult(json: """
        {
          "applied": true,
          "applied_uri": "file:///project/main.swift",
          "applied_edit_count": 1,
          "skipped_uris": [],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 1,
              "has_overlapping_edits": false
            }
          ]
        }
        """)

        XCTAssertNil(AttoWorkspaceEditApplyResult.displayText(for: result))
    }
}
