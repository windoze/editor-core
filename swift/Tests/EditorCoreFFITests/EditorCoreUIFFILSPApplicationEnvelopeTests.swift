import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testLspSemanticTokensApplicationEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        let envelope = try ui.lspApplySemanticTokensEnvelope([0, 1, 1, 7, 0])
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.operationKind, .applySemanticTokens)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertEqual(envelope.value?.applied, true)
        XCTAssertEqual(envelope.value?.dataLen, 5)
        guard case .object(let rawValue)? = envelope.rawValue else {
            XCTFail("expected semantic tokens application raw object")
            return
        }
        XCTAssertEqual(rawValue["applied"], .bool(true))
        XCTAssertEqual(rawValue["data_len"], .number(5))
        XCTAssertNil(envelope.error)

        let failure = try ui.lspApplySemanticTokensEnvelope([0])
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .applySemanticTokens)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "internal")
        XCTAssertEqual(failure.error?.status, .internal)
        let message = failure.error?.message.lowercased() ?? ""
        XCTAssertTrue(message.contains("semantic tokens data length"))
        XCTAssertTrue(message.contains("multiple of 5"))
    }

    func testLspSemanticTokensApplicationEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "apply_semantic_tokens",
          "status": "future_status",
          "value": {
            "applied": true,
            "data_len": 10,
            "future": "kept in raw value"
          },
          "error": null,
          "version": 21,
          "future_top_level": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuLspSemanticTokensApplicationEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operationKind, .applySemanticTokens)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.value?.applied, true)
        XCTAssertEqual(success.value?.dataLen, 10)
        guard case .object(let rawValue)? = success.rawValue else {
            XCTFail("expected semantic tokens application raw object")
            return
        }
        XCTAssertEqual(rawValue["data_len"], .number(10))
        XCTAssertEqual(rawValue["future"], .string("kept in raw value"))
        XCTAssertNil(success.error)

        let failureJSON = """
        {
          "ok": false,
          "operation": "apply_semantic_tokens",
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 123456,
            "message": "future failure",
            "metadata": { "retryable": false }
          },
          "version": 22,
          "future_top_level": true
        }
        """
        let failure = try JSONTestHelpers.decode(EcuLspSemanticTokensApplicationEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .applySemanticTokens)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertNil(failure.error?.status)
        XCTAssertEqual(failure.error?.message, "future failure")
    }

    func testLspApplyWorkspaceEditJSONAppliesCurrentDocumentAndReportsSkippedURIs() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        let workspaceEdit = """
        {
          "changes": {
            "file:///test.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "file:///other.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        let result = try JSONTestHelpers.object(
            try ui.lspApplyWorkspaceEditJSON(workspaceEdit, documentURI: "file:///test.rs")
        )

        XCTAssertEqual(try ui.text(), "aBc\n")
        XCTAssertEqual(result["applied"] as? Bool, true)
        XCTAssertEqual(result["applied_uri"] as? String, "file:///test.rs")
        XCTAssertEqual(result["applied_edit_count"] as? Int, 1)
        XCTAssertEqual(result["skipped_uris"] as? [String], ["file:///other.rs"])

        let documents = try XCTUnwrap(result["documents"] as? [[String: Any]])
        XCTAssertEqual(documents.count, 2)
        XCTAssertTrue(documents.contains {
            ($0["uri"] as? String) == "file:///test.rs"
                && ($0["edit_count"] as? Int) == 1
                && ($0["has_overlapping_edits"] as? Bool) == false
        })
    }

    func testLspWorkspaceEditApplicationEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        let workspaceEdit = """
        {
          "changes": {
            "file:///test.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "file:///other.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        let envelope = try ui.lspApplyWorkspaceEditEnvelope(workspaceEdit, documentURI: "file:///test.rs")
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertEqual(envelope.documentURI, "file:///test.rs")
        XCTAssertEqual(envelope.value?.applied, true)
        XCTAssertEqual(envelope.value?.appliedURI, "file:///test.rs")
        XCTAssertEqual(envelope.value?.appliedEditCount, 1)
        XCTAssertEqual(envelope.value?.skippedURIs, ["file:///other.rs"])
        XCTAssertEqual(envelope.value?.documents.count, 2)
        XCTAssertNil(envelope.error)
        guard case .object(let rawValue)? = envelope.rawValue else {
            XCTFail("expected workspace edit application raw object")
            return
        }
        XCTAssertEqual(rawValue["applied_uri"], .string("file:///test.rs"))
        XCTAssertEqual(try ui.text(), "aBc\n")

        let failure = try ui.lspApplyWorkspaceEditEnvelope("{", documentURI: "file:///test.rs")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.documentURI, "file:///test.rs")
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "internal")
        XCTAssertTrue(failure.error?.message.contains("EOF while parsing") ?? false)
    }

    func testLspDerivedStateApplicationEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "fn main() {}\n", viewportWidthCells: 80)

        let diagnostics = """
        {
          "uri": "file:///test.rs",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 3 },
                "end": { "line": 0, "character": 7 }
              },
              "severity": 1,
              "message": "demo"
            }
          ]
        }
        """
        let inlayHints = #"[{"position":{"line":0,"character":3},"label":": i32"}]"#
        let codeLens = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 2 }
            },
            "command": { "title": "run", "command": "demo.run" }
          }
        ]
        """
        let documentLinks = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 2 }
            },
            "target": "file:///target.rs"
          }
        ]
        """
        let documentHighlights = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 3 },
              "end": { "line": 0, "character": 7 }
            },
            "kind": 1
          }
        ]
        """
        let documentSymbols = """
        [
          {
            "name": "main",
            "kind": 12,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 12 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 3 },
              "end": { "line": 0, "character": 7 }
            }
          }
        ]
        """
        let foldingRanges = #"[{"startLine":0,"startCharacter":0,"endLine":0,"endCharacter":12}]"#
        let cases: [(EcuLspDerivedStateApplicationOperation, () throws -> EcuLspDerivedStateApplicationEnvelope)] = [
            (.applyDiagnostics, { try ui.lspApplyDiagnosticsEnvelope(diagnostics) }),
            (.applyInlayHints, { try ui.lspApplyInlayHintsEnvelope(inlayHints) }),
            (.applyCodeLens, { try ui.lspApplyCodeLensEnvelope(codeLens) }),
            (.applyDocumentLinks, { try ui.lspApplyDocumentLinksEnvelope(documentLinks) }),
            (.applyDocumentHighlights, { try ui.lspApplyDocumentHighlightsEnvelope(documentHighlights) }),
            (.applyDocumentSymbols, { try ui.lspApplyDocumentSymbolsEnvelope(documentSymbols) }),
            (.applyFoldingRanges, { try ui.lspApplyFoldingRangesEnvelope(foldingRanges) }),
        ]

        for (operation, apply) in cases {
            let envelope = try apply()
            XCTAssertTrue(envelope.ok, operation.rawValue)
            XCTAssertEqual(envelope.operationKind, operation)
            XCTAssertEqual(envelope.statusKind, .success)
            XCTAssertEqual(envelope.value?.applied, true)
            guard case .object(let rawValue)? = envelope.rawValue else {
                XCTFail("expected raw value object for \(operation.rawValue)")
                return
            }
            XCTAssertEqual(rawValue["applied"], .bool(true))
            XCTAssertNil(envelope.error)
            XCTAssertEqual(envelope.version, lib.abiVersion)
        }

        let failure = try ui.lspApplyInlayHintsEnvelope("{")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .applyInlayHints)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "internal")
        XCTAssertTrue(failure.error?.message.contains("EOF while parsing") ?? false)
    }

    func testLspDerivedStateApplicationEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "future_apply",
          "status": "future_status",
          "value": {
            "applied": true,
            "future": "kept in raw value"
          },
          "error": null,
          "version": 1,
          "future_top_level": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuLspDerivedStateApplicationEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operationKind, .unknown("future_apply"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.value?.applied, true)
        guard case .object(let rawValue)? = success.rawValue else {
            XCTFail("expected raw value object")
            return
        }
        XCTAssertEqual(rawValue["future"], .string("kept in raw value"))
        XCTAssertNil(success.error)

        let failureJSON = """
        {
          "ok": false,
          "operation": "apply_diagnostics",
          "status": "error",
          "value": null,
          "error": {
            "code": "invalid_argument",
            "status": 1,
            "message": "bad input"
          },
          "version": 1
        }
        """
        let failure = try JSONTestHelpers.decode(EcuLspDerivedStateApplicationEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .applyDiagnostics)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertEqual(failure.error?.message, "bad input")
    }

    func testLspWorkspaceEditApplicationEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "document_uri": "file:///future.swift",
          "value": {
            "applied": true,
            "applied_uri": "file:///future.swift",
            "applied_edit_count": 2,
            "skipped_uris": ["file:///other.swift"],
            "documents": [
              {
                "uri": "file:///future.swift",
                "edit_count": 2,
                "has_overlapping_edits": false,
                "futureDocumentField": true
              }
            ],
            "future": true
          },
          "error": null,
          "version": 15,
          "futureTopLevel": true
        }
        """
        let success = try JSONDecoder().decode(
            EcuLspWorkspaceEditApplicationEnvelope.self,
            from: Data(successJSON.utf8)
        )
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.documentURI, "file:///future.swift")
        XCTAssertEqual(success.value?.applied, true)
        XCTAssertEqual(success.value?.appliedURI, "file:///future.swift")
        XCTAssertEqual(success.value?.appliedEditCount, 2)
        XCTAssertEqual(success.value?.skippedURIs, ["file:///other.swift"])
        XCTAssertEqual(success.value?.documents.first?.uri, "file:///future.swift")
        XCTAssertNil(success.error)
        guard case .object(let rawValue)? = success.rawValue else {
            XCTFail("expected future workspace edit application raw object")
            return
        }
        XCTAssertEqual(rawValue["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "document_uri": "file:///future.swift",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 135790,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 16
        }
        """
        let failure = try JSONDecoder().decode(
            EcuLspWorkspaceEditApplicationEnvelope.self,
            from: Data(failureJSON.utf8)
        )
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.documentURI, "file:///future.swift")
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }
}
