@testable import AttoEditor
import EditorCoreUIFFI
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
            Applied 2 edits across 1 document.

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
            Workspace edit was not applied.
            No edits were applied.

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

    func testWorkspaceEditPreviewSummarizesResourceOperations() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": true,
          "applied_uris": [
            "file:///project/main.swift",
            "file:///project/created.swift"
          ],
          "applied_edit_count": 2,
          "applied_resource_operation_count": 1,
          "skipped_uris": [],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 2,
              "is_open": true
            }
          ]
        }
        """)

        let preview = AttoWorkspaceEditPreview(result: result)

        XCTAssertTrue(preview.requiresConfirmation)
        XCTAssertEqual(
            preview.displayText,
            """
            Workspace edit preview.
            Will apply 2 edits and 1 resource operation across 2 documents.

            Will affect:
            - created.swift (resource operation)
            - main.swift (2 edits, open)
            """
        )
    }

    func testWorkspaceEditPreviewUsesCoreResourceOperationSummary() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": false,
          "applied_edit_count": 0,
          "applied_resource_operation_count": 0,
          "resource_operations": [
            {
              "kind": "create",
              "uri": "file:///project/created.swift",
              "old_uri": null,
              "new_uri": null,
              "affected_uris": ["file:///project/created.swift"],
              "supported": true,
              "applied": false
            }
          ],
          "skipped_uris": [],
          "documents": []
        }
        """)

        let preview = AttoWorkspaceEditPreview(result: result)

        XCTAssertTrue(preview.requiresConfirmation)
        XCTAssertEqual(preview.appliedResourceOperationCount, 1)
        XCTAssertEqual(preview.appliedURIs, ["file:///project/created.swift"])
        XCTAssertEqual(
            preview.displayText,
            """
            Workspace edit preview.
            Will apply 0 edits and 1 resource operation across 1 document.

            Will affect:
            - created.swift (resource operation)
            """
        )
    }

    func testWorkspaceEditPreviewDoesNotConfirmSingleOpenDocumentEdit() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": true,
          "applied_uris": ["file:///project/main.swift"],
          "applied_edit_count": 1,
          "applied_resource_operation_count": 0,
          "skipped_uris": [],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 1,
              "is_open": true
            }
          ]
        }
        """)

        let preview = AttoWorkspaceEditPreview(result: result)

        XCTAssertFalse(preview.requiresConfirmation)
    }

    func testWorkspaceEditPreviewListsSkippedDetails() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": true,
          "applied_uris": ["file:///project/main.swift"],
          "applied_edit_count": 1,
          "applied_resource_operation_count": 0,
          "skipped_uris": ["file:///project/dirty.swift"],
          "skipped_details": [
            {
              "uri": "file:///project/dirty.swift",
              "reason": "dirty_document",
              "operation": "delete",
              "message": "open tab is dirty"
            }
          ],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 1,
              "is_open": true
            },
            {
              "uri": "file:///project/dirty.swift",
              "edit_count": 0,
              "is_open": true
            }
          ]
        }
        """)

        let preview = AttoWorkspaceEditPreview(result: result)

        XCTAssertTrue(preview.requiresConfirmation)
        XCTAssertEqual(
            preview.displayText,
            """
            Workspace edit preview.
            Will apply 1 edit across 2 documents.

            Will affect:
            - main.swift (1 edit, open)

            Not applicable:
            - dirty.swift [delete: dirty_document]
            """
        )
    }

    func testWorkspaceEditPreviewListsTypedConflicts() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": true,
          "applied_uris": ["file:///project/main.swift"],
          "applied_edit_count": 1,
          "applied_resource_operation_count": 0,
          "dirty_document_uris": ["file:///project/dirty.swift"],
          "conflicts": [
            {
              "uri": "file:///project/dirty.swift",
              "kind": "dirty_document",
              "severity": "warning",
              "apply_impact": "skips_change",
              "resolution": "save_or_discard",
              "reason": "resource_operation_dirty_target",
              "operation": "delete",
              "message": "delete targets a modified open tab"
            }
          ],
          "skipped_uris": ["file:///project/dirty.swift"],
          "skipped_details": [
            {
              "uri": "file:///project/dirty.swift",
              "reason": "resource_operation_dirty_target",
              "operation": "delete",
              "message": "delete targets a modified open tab"
            }
          ],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 1,
              "is_open": true
            },
            {
              "uri": "file:///project/dirty.swift",
              "edit_count": 0,
              "is_open": true,
              "is_dirty": true
            }
          ]
        }
        """)
        let workspaceEdit = try XCTUnwrap(AttoWorkspaceEditParser.parse("""
        {
          "changes": {
            "file:///project/main.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "main"
              }
            ]
          }
        }
        """))

        let preview = AttoWorkspaceEditPreview(result: result, parsedWorkspaceEdit: workspaceEdit)

        XCTAssertTrue(preview.requiresConfirmation)
        XCTAssertEqual(preview.applyButtonTitle, "Apply Non-Conflicting Changes")
        XCTAssertEqual(preview.conflictGroups.count, 1)
        XCTAssertEqual(preview.conflictGroups[0].kind, "dirty_document")
        XCTAssertEqual(preview.conflictGroups[0].operation, "delete")
        XCTAssertEqual(
            preview.displayText,
            """
            Workspace edit preview.
            Will apply 1 edit across 2 documents.
            1 conflict will be skipped; non-conflicting changes remain applicable.

            Will affect:
            - main.swift (1 edit, open)

            Conflicts:
            - Dirty document delete: 1 conflict
              - dirty.swift [resource_operation_dirty_target]
            """
        )

        let sections = AttoWorkspaceEditPreviewDetailBuilder.sections(
            preview: preview,
            workspaceEdit: workspaceEdit
        ) { uri in
            uri == "file:///project/main.swift" ? "alpha\n" : nil
        }

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[1].title, "dirty.swift")
        XCTAssertEqual(sections[1].subtitle, "Dirty document: delete: resource_operation_dirty_target")
        XCTAssertEqual(preview.firstConflictTargetURI, "file:///project/dirty.swift")
        XCTAssertEqual(preview.conflictTargetURI(for: sections[1]), "file:///project/dirty.swift")
        XCTAssertTrue(sections[1].detailText.contains("Category: Dirty document"))
        XCTAssertTrue(sections[1].detailText.contains("Severity: warning"))
        XCTAssertTrue(sections[1].detailText.contains("Apply impact: Skipped change"))
        XCTAssertTrue(sections[1].detailText.contains("Kind: dirty_document"))
        XCTAssertTrue(sections[1].detailText.contains("Message: delete targets a modified open tab"))
        XCTAssertTrue(sections[1].detailText.contains("Suggested action: Save or discard the open tab changes"))
    }

    func testWorkspaceEditPreviewGroupsMultipleConflictKinds() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "apply_mode": "partial",
          "applied": true,
          "applied_uris": ["file:///project/main.swift"],
          "applied_edit_count": 1,
          "applied_resource_operation_count": 0,
          "conflicts": [
            {
              "uri": "file:///project/second.swift",
              "kind": "version",
              "severity": "warning",
              "apply_impact": "skips_change",
              "resolution": "refresh_request",
              "reason": "version_mismatch",
              "operation": "text_edit",
              "message": "document version changed"
            },
            {
              "uri": "file:///project/dirty.swift",
              "kind": "dirty_document",
              "severity": "warning",
              "apply_impact": "skips_change",
              "resolution": "save_or_discard",
              "reason": "resource_operation_dirty_target",
              "operation": "delete",
              "message": "delete targets a modified open tab"
            },
            {
              "uri": "file:///project/third.swift",
              "kind": "version",
              "severity": "warning",
              "apply_impact": "skips_change",
              "resolution": "refresh_request",
              "reason": "version_mismatch",
              "operation": "text_edit",
              "message": "document version changed"
            }
          ],
          "skipped_uris": [
            "file:///project/dirty.swift",
            "file:///project/second.swift",
            "file:///project/third.swift"
          ],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 1,
              "is_open": true
            }
          ]
        }
        """)

        let preview = AttoWorkspaceEditPreview(result: result)

        XCTAssertEqual(preview.applyButtonTitle, "Apply Non-Conflicting Changes")
        XCTAssertEqual(preview.conflictGroups.count, 2)
        XCTAssertEqual(preview.conflictGroups[0].kind, "dirty_document")
        XCTAssertEqual(preview.conflictGroups[0].conflicts.map(\.uri), ["file:///project/dirty.swift"])
        XCTAssertEqual(preview.conflictGroups[1].kind, "version")
        XCTAssertEqual(preview.conflictGroups[1].conflicts.map(\.uri), [
            "file:///project/second.swift",
            "file:///project/third.swift",
        ])
        XCTAssertTrue(preview.displayText.contains("3 conflicts will be skipped; non-conflicting changes remain applicable."))
        XCTAssertTrue(preview.displayText.contains("- Dirty document delete: 1 conflict"))
        XCTAssertTrue(preview.displayText.contains("- Version mismatch text edit: 2 conflicts"))
        XCTAssertTrue(preview.displayText.contains("  - second.swift [version_mismatch]"))
        XCTAssertTrue(preview.displayText.contains("  - third.swift [version_mismatch]"))
    }

    func testWorkspaceEditPreviewBlocksAtomicApplyForBlockingConflicts() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "apply_mode": "atomic",
          "applied": false,
          "applied_uris": [],
          "applied_edit_count": 0,
          "applied_resource_operation_count": 0,
          "conflicts": [
            {
              "uri": "file:///project/dirty.swift",
              "kind": "dirty_document",
              "severity": "error",
              "apply_impact": "blocks_atomic_apply",
              "resolution": "save_or_discard",
              "reason": "resource_operation_dirty_target",
              "operation": "delete",
              "message": "delete targets a modified open tab"
            }
          ],
          "skipped_uris": ["file:///project/dirty.swift"],
          "documents": [
            {
              "uri": "file:///project/dirty.swift",
              "edit_count": 0,
              "is_open": true,
              "is_dirty": true
            }
          ]
        }
        """)

        let preview = AttoWorkspaceEditPreview(result: result)

        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.applyButtonTitle, "Resolve Conflicts First")
        XCTAssertTrue(preview.displayText.contains("1 conflict will block atomic apply until resolved."))
        let sections = AttoWorkspaceEditPreviewDetailBuilder.sections(
            preview: preview,
            workspaceEdit: try XCTUnwrap(AttoWorkspaceEditParser.parse(#"{ "documentChanges": [] }"#))
        ) { _ in nil }
        let conflictSection = try XCTUnwrap(sections.first)
        XCTAssertTrue(conflictSection.detailText.contains("Severity: error"))
        XCTAssertTrue(conflictSection.detailText.contains("Apply impact: Blocks atomic apply"))
    }

    func testWorkspaceEditPreviewDefaultsLegacyConflictFields() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": true,
          "applied_uris": [],
          "applied_edit_count": 0,
          "applied_resource_operation_count": 0,
          "conflicts": [
            {
              "uri": "file:///project/legacy.swift",
              "kind": "version",
              "reason": "version_mismatch",
              "operation": "text_edit",
              "message": "document version changed"
            }
          ],
          "skipped_uris": ["file:///project/legacy.swift"],
          "documents": []
        }
        """)

        let conflict = try XCTUnwrap(result.conflicts.first)
        XCTAssertEqual(conflict.severity, "warning")
        XCTAssertEqual(conflict.applyImpact, "skips_change")
        XCTAssertEqual(conflict.resolution, "inspect")
        let preview = AttoWorkspaceEditPreview(result: result)
        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(preview.applyButtonTitle, "Apply Non-Conflicting Changes")
    }

    func testWorkspaceEditPreviewDetailBuilderBuildsTextDiffSections() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": true,
          "applied_uris": ["file:///project/main.swift"],
          "applied_edit_count": 1,
          "applied_resource_operation_count": 0,
          "skipped_uris": [],
          "documents": [
            {
              "uri": "file:///project/main.swift",
              "edit_count": 1,
              "is_open": true
            }
          ]
        }
        """)
        let workspaceEdit = try XCTUnwrap(AttoWorkspaceEditParser.parse("""
        {
          "changes": {
            "file:///project/main.swift": [
              {
                "range": {
                  "start": { "line": 1, "character": 0 },
                  "end": { "line": 1, "character": 4 }
                },
                "newText": "BETA"
              }
            ]
          }
        }
        """))
        let preview = AttoWorkspaceEditPreview(result: result, parsedWorkspaceEdit: workspaceEdit)

        let sections = AttoWorkspaceEditPreviewDetailBuilder.sections(
            preview: preview,
            workspaceEdit: workspaceEdit
        ) { uri in
            uri == "file:///project/main.swift" ? "alpha\nbeta\ngamma\n" : nil
        }

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "main.swift")
        XCTAssertEqual(sections[0].subtitle, "1 edit, open")
        XCTAssertTrue(sections[0].detailText.contains("--- main.swift"))
        XCTAssertTrue(sections[0].detailText.contains("-beta"))
        XCTAssertTrue(sections[0].detailText.contains("+BETA"))
    }

    func testWorkspaceEditPreviewDetailBuilderBuildsResourceOperationSections() throws {
        let result = try decodeTransactionResult("""
        {
          "mode": "preview",
          "applied": true,
          "applied_uris": [
            "file:///project/old.swift",
            "file:///project/new.swift"
          ],
          "applied_edit_count": 0,
          "applied_resource_operation_count": 1,
          "skipped_uris": [],
          "documents": []
        }
        """)
        let workspaceEdit = try XCTUnwrap(AttoWorkspaceEditParser.parse("""
        {
          "documentChanges": [
            {
              "kind": "rename",
              "oldUri": "file:///project/old.swift",
              "newUri": "file:///project/new.swift",
              "options": {
                "overwrite": true,
                "ignoreIfExists": false
              }
            }
          ]
        }
        """))
        let preview = AttoWorkspaceEditPreview(result: result, parsedWorkspaceEdit: workspaceEdit)

        let sections = AttoWorkspaceEditPreviewDetailBuilder.sections(
            preview: preview,
            workspaceEdit: workspaceEdit
        ) { _ in nil }

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "old.swift -> new.swift")
        XCTAssertEqual(sections[0].subtitle, "rename file")
        XCTAssertTrue(sections[0].detailText.contains("Rename file"))
        XCTAssertTrue(sections[0].detailText.contains("overwrite: true"))
    }

    private func decodeTransactionResult(_ json: String) throws -> EcuWorkspaceEditTransactionResult {
        try JSONDecoder().decode(EcuWorkspaceEditTransactionResult.self, from: Data(json.utf8))
    }
}
