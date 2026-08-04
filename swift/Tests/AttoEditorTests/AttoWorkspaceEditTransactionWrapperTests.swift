import EditorCoreUIFFI
@testable import AttoEditor
import XCTest

@MainActor
final class AttoWorkspaceEditTransactionWrapperTests: XCTestCase {
    func testSwiftWrapperDecodesAtomicConflictAndEvents() throws {
        let coreDocuments = try MultiDocumentEditorUI(library: EditorCoreUIFFILibrary())
        let appTabID = try coreDocuments.openTab(text: "alpha\n")
        let dirtyTabID = try coreDocuments.openTab(text: "dirty\n")
        try coreDocuments.setTabDocumentURI("file:///project/App.swift", tabId: appTabID)
        try coreDocuments.setTabDocumentURI("file:///project/Dirty.swift", tabId: dirtyTabID)
        try coreDocuments.replaceTabText(tabId: dirtyTabID, text: "dirty changed\n")

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "file:///project/App.swift",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 5 }
                    },
                    "newText": "App"
                  }
                ]
              },
              {
                "kind": "delete",
                "uri": "file:///project/Dirty.swift"
              }
            ]
          }
        }
        """

        let result = try coreDocuments.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(result.applied)
        XCTAssertEqual(result.mode, "apply")
        XCTAssertEqual(result.applyMode, "atomic")
        XCTAssertEqual(result.appliedEditCount, 0)

        let conflict = try XCTUnwrap(result.conflicts.first)
        XCTAssertEqual(conflict.uri, "file:///project/Dirty.swift")
        XCTAssertEqual(conflict.kind, "dirty_document")
        XCTAssertEqual(conflict.severity, "error")
        XCTAssertEqual(conflict.applyImpact, "blocks_atomic_apply")
        XCTAssertEqual(conflict.resolution, "save_or_discard")
        XCTAssertEqual(conflict.reason, "resource_operation_dirty_target")
        XCTAssertEqual(conflict.operation, "delete")

        let events = try coreDocuments.workspaceEditTransactionEvents()
        XCTAssertEqual(events.latestSequence, 1)
        let event = try XCTUnwrap(events.events.first)
        XCTAssertEqual(event.sequence, 1)
        XCTAssertEqual(event.operation, "apply")
        XCTAssertEqual(event.workspaceEditJSON, workspaceEdit)
        XCTAssertEqual(event.result.conflicts.first, conflict)
    }

    func testSwiftWrapperDecodesWorkspaceEditTransactionEnvelopeErrors() throws {
        let coreDocuments = try MultiDocumentEditorUI(library: EditorCoreUIFFILibrary())

        let envelope = try coreDocuments.workspaceEditTransactionEnvelope(
            operationRawValue: "future_operation",
            workspaceEditJSON: #"{"changes":{}}"#
        )

        XCTAssertFalse(envelope.ok)
        XCTAssertEqual(envelope.operation, "future_operation")
        XCTAssertEqual(envelope.operationKind, .unknown("future_operation"))
        XCTAssertEqual(envelope.statusKind, .error)
        XCTAssertEqual(envelope.value, .null)
        XCTAssertEqual(envelope.error?.code, "invalid_argument")
        XCTAssertEqual(envelope.error?.status, .invalidArgument)
        XCTAssertTrue(envelope.error?.message.contains("unknown workspace edit transaction operation") == true)
    }

    func testRequestRetryInvalidationReasonMatrixFeedsHistoryActionState() throws {
        let cases: [(AttoWorkspaceEditRequestRetryDescriptor.InvalidationReason, String)] = [
            (.sourceTabClosed, "source tab closed"),
            (.documentURIUnavailable, "document URI unavailable"),
            (.workspaceRootUnavailable, "workspace root unavailable"),
            (.lspUnavailable, "LSP unavailable"),
            (.requestParametersUnavailable, "request parameters unavailable"),
            (.requestClosureUnavailable, "retry closure unavailable"),
            (.serverCapabilityChanged, "server capability changed"),
            (.expired, "request expired"),
        ]

        for (reason, reasonText) in cases {
            let descriptor = AttoWorkspaceEditRequestRetryDescriptor
                .unknown(label: "Rename: symbol")
                .invalidated(reason)
            let item = historyItem(requestRetryDescriptor: descriptor)
            let state = AttoWorkspaceEditConflictActionState.history(for: item, hasUndoLatest: false)

            XCTAssertEqual(descriptor.invalidationReasonText, reasonText, reason.rawValue)
            XCTAssertFalse(descriptor.canRerun, reason.rawValue)
            XCTAssertEqual(state.saveAndResolve.title, "Save & Rerun", reason.rawValue)
            XCTAssertFalse(state.saveAndResolve.isEnabled, reason.rawValue)
            XCTAssertEqual(
                state.saveAndResolve.toolTip,
                "Cannot rerun Rename: symbol: \(reasonText)",
                reason.rawValue
            )
            XCTAssertFalse(state.rerunRequest.isEnabled, reason.rawValue)
            XCTAssertEqual(
                state.rerunRequest.toolTip,
                "Cannot rerun Rename: symbol: \(reasonText)",
                reason.rawValue
            )
        }
    }

    private func historyItem(
        requestRetryDescriptor: AttoWorkspaceEditRequestRetryDescriptor
    ) -> AttoWorkspaceEditHistoryPanelController.Item {
        AttoWorkspaceEditHistoryPanelController.Item(
            sequence: 1,
            operation: "apply",
            title: "#1 Apply WorkspaceEdit",
            detail: "1 conflict",
            status: "Rejected",
            conflictCount: 1,
            firstConflictURI: "file:///project/Dirty.swift",
            firstSaveableConflictURI: "file:///project/Dirty.swift",
            firstDiscardableConflictURI: "file:///project/Dirty.swift",
            workspaceEditJSON: #"{"changes":{}}"#,
            requestRetryLabel: requestRetryDescriptor.label,
            requestRetryDescriptor: requestRetryDescriptor,
            requestRetryUnavailableReason: requestRetryDescriptor.invalidationReasonText,
            canUndoLatest: false
        )
    }
}
