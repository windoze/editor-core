import EditorCoreUI
import EditorCoreUIFFI
import XCTest

final class EditorCoreLSPStatusSnapshotTests: XCTestCase {
    func testDecodesReadyStatusWithCapabilities() throws {
        let status = try decode("""
        {
          "availability": "enabled",
          "state": "ready",
          "server": {
            "name": "rust-analyzer",
            "version": "1.0",
            "command": "rust-analyzer",
            "args": ["--stdio"]
          },
          "process": {
            "pid": 4242,
            "state": "running",
            "exit_code": null,
            "signal": null
          },
          "activity": null,
          "detail": null,
          "workspace_folders": [
            { "uri": "file:///tmp/editor-core", "name": "editor-core" },
            { "uri": "file:///tmp/fixtures", "name": "fixtures" }
          ],
          "capabilities": {
            "semantic_tokens": true,
            "semantic_tokens_delta": false,
            "completion_item_resolve": true,
            "completion": {
              "supported": true,
              "trigger_characters": [".", ":"],
              "all_commit_characters": [";", ")"]
            },
            "folding_ranges": true,
            "on_type_formatting": true,
            "signature_help": {
              "supported": true,
              "trigger_characters": ["("],
              "retrigger_characters": [","]
            }
          }
        }
        """)

        XCTAssertEqual(status.availability, .enabled)
        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.server?.name, "rust-analyzer")
        XCTAssertEqual(status.server?.args, ["--stdio"])
        XCTAssertEqual(status.process?.pid, 4242)
        XCTAssertEqual(status.process?.state, .running)
        XCTAssertNil(status.process?.exitCode)
        XCTAssertNil(status.process?.signal)
        XCTAssertNil(status.activity)
        XCTAssertEqual(status.workspaceFolders, [
            EcuLspWorkspaceFolder(uri: "file:///tmp/editor-core", name: "editor-core"),
            EcuLspWorkspaceFolder(uri: "file:///tmp/fixtures", name: "fixtures"),
        ])
        XCTAssertEqual(status.capabilities?.semanticTokens, true)
        XCTAssertEqual(status.capabilities?.completion.triggerCharacters, [".", ":"])
        XCTAssertEqual(status.capabilities?.completion.allCommitCharacters, [";", ")"])
        XCTAssertEqual(status.capabilities?.signatureHelp.triggerCharacters, ["("])
        XCTAssertEqual(status.capabilities?.signatureHelp.retriggerCharacters, [","])
    }

    func testDecodesFailedStatusWithMinimalServer() throws {
        let status = try decode("""
        {
          "availability": "failed",
          "state": "failed",
          "server": { "command": "fake-lsp" },
          "process": { "pid": 123, "state": "exited", "exit_code": 7, "signal": null },
          "activity": { "title": "Indexing", "message": "Crates", "percentage": 42 },
          "detail": "server exited",
          "capabilities": null
        }
        """)

        XCTAssertEqual(status.availability, .failed)
        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(status.server?.command, "fake-lsp")
        XCTAssertEqual(status.server?.args, [])
        XCTAssertEqual(status.process, EcuLspProcessStatus(pid: 123, state: .exited, exitCode: 7))
        XCTAssertEqual(status.activity?.title, "Indexing")
        XCTAssertEqual(status.activity?.message, "Crates")
        XCTAssertEqual(status.activity?.percentage, 42)
        XCTAssertEqual(status.detail, "server exited")
        XCTAssertNil(status.capabilities)
    }

    func testPreservesUnknownAvailabilityAndState() throws {
        let status = try decode(#"{ "availability": "warming", "state": "restarting" }"#)

        XCTAssertEqual(status.availability, .unknown("warming"))
        XCTAssertEqual(status.availability.rawValue, "warming")
        XCTAssertEqual(status.state, .unknown("restarting"))
        XCTAssertEqual(status.state.rawValue, "restarting")
        XCTAssertNil(status.server)
        XCTAssertNil(status.process)
        XCTAssertEqual(status.workspaceFolders, [])
        XCTAssertNil(status.capabilities)
    }

    func testEditorUIStatusSnapshotReportsDisabledWhenLspIsOff() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let editor = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        let status = try editor.lspStatusSnapshot()

        XCTAssertEqual(status.availability, .disabled)
        XCTAssertEqual(status.state, .disabled)
        XCTAssertNil(status.detail)
        XCTAssertNil(status.process)
        XCTAssertEqual(status.workspaceFolders, [])
    }

    private func decode(_ json: String) throws -> EcuLspStatusSnapshot {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(EcuLspStatusSnapshot.self, from: data)
    }
}
