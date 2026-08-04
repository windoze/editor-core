import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testMultiDocumentSnapshotEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let tab = try multi.openTab(text: "alpha\n", viewportWidthCells: 80)
        try multi.setTabTitle("Alpha", tabId: tab)
        try multi.setTabDocumentURI("file:///project/Alpha.swift", tabId: tab)
        try multi.setTabLanguageId("swift", tabId: tab)

        let envelope = try multi.snapshotEnvelope()
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let tabs)? = value["tabs"],
              case .object(let firstTab)? = tabs.first
        else {
            XCTFail("expected multi-document snapshot object")
            return
        }
        XCTAssertEqual(value["active_tab_id"], .number(Double(tab)))
        XCTAssertEqual(value["workspace_roots"], .array([]))
        XCTAssertEqual(firstTab["id"], .number(Double(tab)))
        XCTAssertEqual(firstTab["title"], .string("Alpha"))
        XCTAssertEqual(firstTab["document_uri"], .string("file:///project/Alpha.swift"))
        XCTAssertEqual(firstTab["language_id"], .string("swift"))
        XCTAssertEqual(firstTab["is_active"], .bool(true))
        XCTAssertEqual(firstTab["is_modified"], .bool(false))
        XCTAssertEqual(firstTab["view_count"], .number(1))
    }

    func testMultiDocumentSnapshotEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "tabs": [],
            "future": true
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuMultiDocumentSnapshotEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future multi-document snapshot value")
            return
        }
        XCTAssertEqual(value["tabs"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuMultiDocumentSnapshotEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceRootsChangeEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let envelope = try multi.setWorkspaceRootsReturningChangeEnvelope([
            "file:///project/Alpha",
            "file:///project/Beta",
        ])
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let added)? = value["added"],
              case .object(let firstAdded)? = added.first
        else {
            XCTFail("expected workspace roots change object")
            return
        }
        XCTAssertEqual(firstAdded["uri"], .string("file:///project/Alpha"))
        XCTAssertEqual(firstAdded["name"], .string("Alpha"))
        XCTAssertEqual(value["removed"], .array([]))

        let replacement = try multi.setWorkspaceRootsReturningChangeEnvelope(["file:///project/Beta"])
        guard case .object(let replacementValue)? = replacement.value,
              case .array(let removed)? = replacementValue["removed"],
              case .object(let firstRemoved)? = removed.first
        else {
            XCTFail("expected workspace roots replacement object")
            return
        }
        XCTAssertEqual(replacementValue["added"], .array([]))
        XCTAssertEqual(firstRemoved["uri"], .string("file:///project/Alpha"))
        XCTAssertEqual(firstRemoved["name"], .string("Alpha"))
    }

    func testWorkspaceRootsChangeEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "added": [],
            "removed": [],
            "future": true
          },
          "error": null,
          "version": 11,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceRootsChangeEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future workspace roots change value")
            return
        }
        XCTAssertEqual(value["added"], .array([]))
        XCTAssertEqual(value["removed"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 1000001,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 12
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceRootsChangeEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testProjectLspServersEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        try multi.setProjectLspServers([
            EcuProjectLspServerConfig(
                key: " Rust ",
                command: " /bin/rust-analyzer ",
                args: [" ", "--stdio "],
                languageId: " rust ",
                languageName: " Rust Language ",
                serverCapabilities: .object([
                    "semantic_tokens": .bool(true),
                    "completion": .object(["supported": .bool(true)]),
                ]),
                sharedSession: true,
                workspaceRoots: ["file:///workspace", " file:///workspace ", "file:///other"],
                workspaceFolders: [
                    EcuProjectLspWorkspaceFolder(
                        uri: " file:///workspace ",
                        name: " Workspace ",
                        rootAlias: " main "
                    ),
                ],
                autoStart: true
            ),
            EcuProjectLspServerConfig(
                key: "",
                command: "/bin/sourcekit-lsp",
                languageId: "swift",
                sharedSession: false,
                autoStart: false
            ),
        ])

        let envelope = try multi.projectLspServersEnvelope()
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .array(let servers)? = envelope.value,
              case .object(let first)? = servers.first,
              case .object(let second)? = servers.dropFirst().first
        else {
            XCTFail("expected project LSP server config array")
            return
        }
        XCTAssertEqual(first["key"], .string("rust"))
        XCTAssertEqual(first["command"], .string("/bin/rust-analyzer"))
        XCTAssertEqual(first["args"], .array([.string("--stdio")]))
        XCTAssertEqual(first["language_id"], .string("rust"))
        XCTAssertEqual(first["language_name"], .string("Rust Language"))
        XCTAssertEqual(first["server_capabilities"], .object([
            "completion": .object(["supported": .bool(true)]),
            "semantic_tokens": .bool(true),
        ]))
        XCTAssertEqual(first["shared_session"], .bool(true))
        XCTAssertEqual(first["workspace_roots"], .array([.string("file:///other"), .string("file:///workspace")]))
        XCTAssertEqual(first["workspace_folders"], .array([
            .object([
                "uri": .string("file:///other"),
                "name": .string("other"),
            ]),
            .object([
                "uri": .string("file:///workspace"),
                "name": .string("Workspace"),
                "root_alias": .string("main"),
            ]),
        ]))
        XCTAssertEqual(first["auto_start"], .bool(true))
        XCTAssertEqual(second["key"], .string("swift"))
        XCTAssertEqual(second["command"], .string("/bin/sourcekit-lsp"))
        XCTAssertEqual(second["args"], .array([]))
        XCTAssertEqual(second["language_id"], .string("swift"))
        XCTAssertEqual(second["language_name"], .string("swift"))
        XCTAssertEqual(second["server_capabilities"], .object([:]))
        XCTAssertEqual(second["shared_session"], .bool(false))
        XCTAssertEqual(second["workspace_roots"], .array([]))
        XCTAssertEqual(second["workspace_folders"], .array([]))
        XCTAssertEqual(second["auto_start"], .bool(false))
    }

    func testProjectLspServersEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": [
            {
              "key": "future",
              "command": "future-lsp",
              "futureConfigField": true
            }
          ],
          "error": null,
          "version": 13,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuProjectLspServersEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .array(let value)? = success.value,
              case .object(let first)? = value.first
        else {
            XCTFail("expected future project LSP config array")
            return
        }
        XCTAssertEqual(first["key"], .string("future"))
        XCTAssertEqual(first["futureConfigField"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 1000002,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 14
        }
        """
        let failure = try JSONTestHelpers.decode(EcuProjectLspServersEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testProjectLspLifecycleEnvelopeReportsPlansEventsAndErrors() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let tab = try multi.openTab(text: "fn main() {}\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/main.rs", tabId: tab)
        try multi.setTabLanguageId("rust", tabId: tab)
        try multi.setWorkspaceRoots(["file:///project"])
        try multi.setProjectLspServers([
            EcuProjectLspServerConfig(
                key: "rust",
                command: "/bin/rust-analyzer",
                args: ["--stdio"],
                languageId: "rust"
            ),
        ])

        let start = try multi.projectLspStartPlanEnvelope()
        XCTAssertTrue(start.ok)
        XCTAssertEqual(start.operationKind, .startPlan)
        XCTAssertEqual(start.statusKind, .success)
        XCTAssertEqual(start.version, lib.abiVersion)
        XCTAssertNil(start.error)
        guard case .array(let startPlan)? = start.value,
              case .object(let firstStart)? = startPlan.first
        else {
            XCTFail("expected project LSP start plan array")
            return
        }
        XCTAssertEqual(firstStart["tab_id"], .number(Double(tab)))
        XCTAssertEqual(firstStart["attempt_id"], .number(1))
        XCTAssertEqual(firstStart["document_uri"], .string("file:///project/main.rs"))
        XCTAssertEqual(firstStart["server_key"], .string("rust"))
        XCTAssertEqual(firstStart["language_name"], .string("rust"))
        XCTAssertEqual(firstStart["server_capabilities"], .object([:]))
        XCTAssertEqual(firstStart["shared_session"], .bool(true))

        let stop = try multi.projectLspStopPlanEnvelope()
        XCTAssertTrue(stop.ok)
        XCTAssertEqual(stop.operationKind, .stopPlan)
        guard case .array(let stopPlan)? = stop.value,
              case .object(let firstStop)? = stopPlan.first
        else {
            XCTFail("expected project LSP stop plan array")
            return
        }
        XCTAssertEqual(firstStop["server_key"], .string("rust"))
        XCTAssertEqual(firstStop["attempt_id"], .number(1))
        XCTAssertEqual(firstStop["language_name"], .string("rust"))
        XCTAssertEqual(firstStop["server_capabilities"], .object([:]))
        XCTAssertEqual(firstStop["shared_session"], .bool(true))

        let restart = try multi.projectLspRestartPlanEnvelope()
        XCTAssertTrue(restart.ok)
        XCTAssertEqual(restart.operationKind, .restartPlan)
        guard case .array(let restartPlan)? = restart.value,
              case .object(let firstRestart)? = restartPlan.first
        else {
            XCTFail("expected project LSP restart plan array")
            return
        }
        XCTAssertEqual(firstRestart["server_key"], .string("rust"))
        XCTAssertEqual(firstRestart["attempt_id"], .number(1))
        XCTAssertEqual(firstRestart["language_name"], .string("rust"))
        XCTAssertEqual(firstRestart["server_capabilities"], .object([:]))
        XCTAssertEqual(firstRestart["shared_session"], .bool(true))

        try multi.recordProjectLspStartOutcome(EcuProjectLspStartOutcome(
            tabId: tab,
            documentURI: "file:///project/main.rs",
            languageId: "rust",
            serverCapabilities: .object(["hover": .bool(true)]),
            sharedSession: false,
            serverKey: "rust",
            command: "/bin/rust-analyzer",
            args: ["--stdio"],
            workspaceRoots: ["file:///project"],
            status: "started"
        ))
        let events = try multi.projectLspLifecycleEventsEnvelope()
        XCTAssertTrue(events.ok)
        XCTAssertEqual(events.operationKind, .lifecycleEvents)
        guard case .object(let eventSnapshot)? = events.value,
              case .number(let latestSequence)? = eventSnapshot["latest_sequence"],
              case .array(let eventValues)? = eventSnapshot["events"],
              case .object(let firstEvent)? = eventValues.first
        else {
            XCTFail("expected project LSP lifecycle events snapshot")
            return
        }
        XCTAssertEqual(latestSequence, 1)
        XCTAssertEqual(firstEvent["operation"], .string("start"))
        XCTAssertEqual(firstEvent["language_name"], .string("rust"))
        XCTAssertEqual(firstEvent["server_capabilities"], .object(["hover": .bool(true)]))
        XCTAssertEqual(firstEvent["shared_session"], .bool(false))
        XCTAssertEqual(firstEvent["status"], .string("started"))

        let failure = try multi.projectLspLifecycleEnvelope(operationRawValue: "future_operation")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .unknown("future_operation"))
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "invalid_argument")
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertTrue(failure.error?.message.contains("unknown project LSP lifecycle operation") ?? false)
    }

    func testProjectLspLifecycleEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "future_operation",
          "status": "future_status",
          "value": {
            "items": [],
            "future": true
          },
          "error": null,
          "version": 15,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuProjectLspLifecycleEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operationKind, .unknown("future_operation"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future project LSP lifecycle value")
            return
        }
        XCTAssertEqual(value["items"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "operation": null,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 1000002,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 16
        }
        """
        let failure = try JSONTestHelpers.decode(EcuProjectLspLifecycleEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertNil(failure.operationKind)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testMultiDocumentSearchEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let alpha = try multi.openTab(text: "alpha world", viewportWidthCells: 80)
        let beta = try multi.openTab(text: "beta world", viewportWidthCells: 80)

        let envelope = try multi.searchAllTabsEnvelope(query: "world")
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let results)? = value["results"],
              case .object(let first)? = results.first,
              case .object(let second)? = results.dropFirst().first,
              case .array(let firstMatches)? = first["matches"],
              case .object(let firstMatch)? = firstMatches.first
        else {
            XCTFail("expected multi-document search result object")
            return
        }
        XCTAssertEqual(first["tab_id"], .number(Double(alpha)))
        XCTAssertEqual(firstMatch["start"], .number(6))
        XCTAssertEqual(firstMatch["end"], .number(11))
        XCTAssertEqual(second["tab_id"], .number(Double(beta)))
    }

    func testMultiDocumentSearchEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "results": [],
            "future": true
          },
          "error": null,
          "version": 9,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuMultiDocumentSearchEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future multi-document search value")
            return
        }
        XCTAssertEqual(value["results"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 999999,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 10
        }
        """
        let failure = try JSONTestHelpers.decode(EcuMultiDocumentSearchEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceOutlineSnapshotEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let tab = try multi.openTab(text: "struct Beta {}\n", viewportWidthCells: 80)
        try multi.setTabTitle("Beta", tabId: tab)
        try multi.setTabDocumentURI("file:///project/Beta.swift", tabId: tab)
        try multi.applyTabDocumentSymbolsJSON(tabId: tab, resultJSON: """
        [
          {
            "name": "Beta",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 14 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 11 }
            }
          }
        ]
        """)

        let envelope = try multi.workspaceOutlineSnapshotEnvelope()
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let documents)? = value["documents"],
              case .object(let document)? = documents.first,
              case .array(let symbols)? = document["symbols"],
              case .object(let symbol)? = symbols.first
        else {
            XCTFail("expected workspace outline snapshot object")
            return
        }
        XCTAssertEqual(document["tab_id"], .number(Double(tab)))
        XCTAssertEqual(document["title"], .string("Beta"))
        XCTAssertEqual(document["document_uri"], .string("file:///project/Beta.swift"))
        XCTAssertEqual(document["symbol_count"], .number(1))
        XCTAssertEqual(symbol["name"], .string("Beta"))
    }

    func testWorkspaceOutlineSnapshotEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "documents": [],
            "future": true
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceOutlineSnapshotEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future workspace outline value")
            return
        }
        XCTAssertEqual(value["documents"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceOutlineSnapshotEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceEditTransactionEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let tab = try multi.openTab(text: "hello\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/App.swift", tabId: tab)

        let workspaceEdit = """
        {
          "changes": {
            "file:///project/App.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 5 }
                },
                "newText": "Hello"
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransactionEnvelope(workspaceEdit)
        XCTAssertTrue(preview.ok)
        XCTAssertEqual(preview.version, lib.abiVersion)
        XCTAssertEqual(preview.operation, "preview")
        XCTAssertEqual(preview.operationKind, .preview)
        XCTAssertEqual(preview.statusKind, .success)
        XCTAssertNil(preview.error)
        guard case .object(let previewValue)? = preview.value else {
            XCTFail("expected WorkspaceEdit transaction result object")
            return
        }
        XCTAssertEqual(previewValue["mode"], .string("preview"))
        XCTAssertEqual(previewValue["applied"], .bool(false))

        let undo = try multi.undoLastWorkspaceEditTransactionEnvelope()
        XCTAssertTrue(undo.ok)
        XCTAssertEqual(undo.operationKind, .undo)
        guard case .object(let undoValue)? = undo.value else {
            XCTFail("expected WorkspaceEdit undo result object")
            return
        }
        XCTAssertEqual(undoValue["undone"], .bool(false))

        let apply = try multi.applyWorkspaceEditTransactionEnvelope(workspaceEdit)
        XCTAssertTrue(apply.ok)
        XCTAssertEqual(apply.operationKind, .apply)
        XCTAssertEqual(try multi.tabText(tabId: tab), "Hello\n")

        let appliedUndo = try multi.undoLastWorkspaceEditTransactionEnvelope()
        XCTAssertTrue(appliedUndo.ok)
        XCTAssertEqual(appliedUndo.operationKind, .undo)
        XCTAssertEqual(try multi.tabText(tabId: tab), "hello\n")

        let redo = try multi.redoLastWorkspaceEditTransactionEnvelope()
        XCTAssertTrue(redo.ok)
        XCTAssertEqual(redo.operationKind, .redo)
        guard case .object(let redoValue)? = redo.value else {
            XCTFail("expected WorkspaceEdit redo result object")
            return
        }
        XCTAssertEqual(redoValue["mode"], .string("redo"))
        XCTAssertEqual(redoValue["applied"], .bool(true))
        XCTAssertEqual(try multi.tabText(tabId: tab), "Hello\n")

        let failure = try multi.workspaceEditTransactionEnvelope(
            operationRawValue: "future_operation",
            workspaceEditJSON: workspaceEdit
        )
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .unknown("future_operation"))
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "invalid_argument")
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertTrue(failure.error?.message.contains("unknown workspace edit transaction operation") ?? false)
    }

    func testWorkspaceEditTransactionEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "future_operation",
          "status": "future_status",
          "value": {
            "mode": "future_mode",
            "items": [1, "x"]
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceEditTransactionEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operationKind, .unknown("future_operation"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future WorkspaceEdit transaction value")
            return
        }
        XCTAssertEqual(value["mode"], .string("future_mode"))
        XCTAssertEqual(value["items"], .array([.number(1), .string("x")]))

        let failureJSON = """
        {
          "ok": false,
          "operation": "apply",
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceEditTransactionEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .apply)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceDiagnosticsEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let diagnosticsJSON = """
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 3 }
                  },
                  "severity": 1,
                  "message": "first problem"
                }
              ]
            }
          ]
        }
        """

        let apply = try multi.applyWorkspaceDiagnosticsEnvelope(diagnosticsJSON)
        XCTAssertTrue(apply.ok)
        XCTAssertEqual(apply.version, lib.abiVersion)
        XCTAssertEqual(apply.operation, "apply")
        XCTAssertEqual(apply.operationKind, .apply)
        XCTAssertEqual(apply.statusKind, .success)
        XCTAssertNil(apply.error)
        guard case .object(let applyValue)? = apply.value,
              case .array(let diagnostics)? = applyValue["diagnostics"],
              case .object(let firstDiagnostic)? = diagnostics.first
        else {
            XCTFail("expected workspace diagnostics snapshot object")
            return
        }
        XCTAssertEqual(firstDiagnostic["message"], .string("first problem"))
        XCTAssertEqual(firstDiagnostic["severity_label"], .string("error"))

        let markers = try multi.workspaceDiagnosticMarkersEnvelope()
        XCTAssertTrue(markers.ok)
        XCTAssertEqual(markers.operationKind, .markers)
        guard case .object(let markersValue)? = markers.value,
              case .array(let markerItems)? = markersValue["markers"],
              case .object(let firstMarker)? = markerItems.first
        else {
            XCTFail("expected workspace diagnostic markers object")
            return
        }
        XCTAssertEqual(firstMarker["uri"], .string("file:///project/a.swift"))
        XCTAssertEqual(firstMarker["line"], .number(0))
        XCTAssertEqual(firstMarker["severity_label"], .string("error"))

        let previous = try multi.workspaceDiagnosticsPreviousResultIdsEnvelope()
        XCTAssertTrue(previous.ok)
        XCTAssertEqual(previous.operationKind, .previousResultIds)
        guard case .array(let previousItems)? = previous.value,
              case .object(let previousItem)? = previousItems.first
        else {
            XCTFail("expected workspace diagnostics previous-result-id array")
            return
        }
        XCTAssertEqual(previousItem["uri"], .string("file:///project/a.swift"))
        XCTAssertEqual(previousItem["value"], .string("a-1"))

        let snapshot = try multi.workspaceDiagnosticsSnapshotEnvelope()
        XCTAssertTrue(snapshot.ok)
        XCTAssertEqual(snapshot.operationKind, .snapshot)
        guard case .object(let snapshotValue)? = snapshot.value,
              case .array(let documents)? = snapshotValue["documents"],
              case .object(let firstDocument)? = documents.first
        else {
            XCTFail("expected workspace diagnostics snapshot documents")
            return
        }
        XCTAssertEqual(firstDocument["uri"], .string("file:///project/a.swift"))

        let failure = try multi.workspaceDiagnosticsEnvelope(operationRawValue: "future_operation")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .unknown("future_operation"))
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "invalid_argument")
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertTrue(failure.error?.message.contains("unknown workspace diagnostics operation") ?? false)
    }

    func testWorkspaceDiagnosticsEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "future_operation",
          "status": "future_status",
          "value": {
            "documents": [],
            "future": true
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceDiagnosticsEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operationKind, .unknown("future_operation"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future workspace diagnostics value")
            return
        }
        XCTAssertEqual(value["documents"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "operation": "apply",
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceDiagnosticsEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .apply)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }
}
