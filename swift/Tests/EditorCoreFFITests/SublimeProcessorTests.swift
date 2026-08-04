import Foundation
import XCTest
@testable import EditorCoreFFI

final class SublimeProcessorTests: XCTestCase {
    func testSublimeProcessorProcessApplyScopesAndFoldPreservation() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        let yaml1 = """
        %YAML 1.2
        ---
        name: Demo
        scope: source.demo
        contexts:
          main:
            - match: "\\\\{"
              push: block
            - match: "\\\\bTODO\\\\b"
              scope: keyword.todo.demo
          block:
            - meta_scope: meta.block.demo
            - match: "\\\\}"
              pop: true
            - match: "."
              scope: meta.block.demo
        """

        let state = try EditorState(library: library, initialText: "{\nTODO\n}\n", viewportWidth: 80)
        let processor = try SublimeProcessor(library: library, yaml: yaml1)

        let processed = try JSONTestHelpers.object(try processor.processJSON(state: state))
        let edits = (processed["edits"] as? [Any]) ?? []
        XCTAssertEqual(edits.count, 2)
        let ops = edits.compactMap { ($0 as? [String: Any])?["op"] as? String }
        XCTAssertTrue(ops.contains("replace_style_layer"))
        XCTAssertTrue(ops.contains("replace_folding_regions"))

        let processEnvelope = try processor.processEnvelope(state: state)
        XCTAssertTrue(processEnvelope.ok)
        XCTAssertEqual(processEnvelope.statusKind, .success)
        XCTAssertEqual(processEnvelope.operation, "sublime_process")
        guard case let .object(processValue)? = processEnvelope.value else {
            XCTFail("expected process envelope value object")
            return
        }
        guard case let .array(envelopeEdits)? = processValue["edits"] else {
            XCTFail("expected process envelope edits array")
            return
        }
        XCTAssertEqual(envelopeEdits.count, edits.count)

        try processor.apply(state: state)
        let blob = try state.viewportBlob(startVisualRow: 0, rowCount: 10)
        XCTAssertGreaterThan(blob.styleIds.count, 0)

        let someStyleId = blob.styleIds.first ?? 0
        let scope = try processor.scopeForStyleId(someStyleId)
        XCTAssertTrue(scope.contains("demo"))

        let scopeEnvelope = try processor.scopeForStyleIdEnvelope(someStyleId)
        XCTAssertTrue(scopeEnvelope.ok)
        XCTAssertEqual(scopeEnvelope.operation, "sublime_scope_for_style_id")
        guard case let .object(scopeValue)? = scopeEnvelope.value else {
            XCTFail("expected scope envelope value object")
            return
        }
        guard case let .string(scopeText)? = scopeValue["scope"] else {
            XCTFail("expected scope envelope scope string")
            return
        }
        XCTAssertEqual(scopeText, scope)

        // folding exists
        let full1 = try JSONTestHelpers.object(try state.fullStateJSON())
        let folding1 = (full1["folding"] as? [String: Any]) ?? [:]
        let regions1 = (folding1["regions"] as? [Any]) ?? []
        XCTAssertGreaterThanOrEqual(regions1.count, 1)

        // collapse a known region and verify preserve_collapsed takes effect
        let collapse = """
        {
          "op": "replace_folding_regions",
          "regions": [
            { "start_line": 0, "end_line": 2, "is_collapsed": true, "placeholder": "[...]" }
          ],
          "preserve_collapsed": false
        }
        """
        try state.applyProcessingEditsJSON(collapse)

        try processor.setPreserveCollapsedFolds(true)
        try processor.apply(state: state)

        let full2 = try JSONTestHelpers.object(try state.fullStateJSON())
        let folding2 = (full2["folding"] as? [String: Any]) ?? [:]
        let regions2 = (folding2["regions"] as? [Any]) ?? []
        let collapsedPreserved = regions2.contains { region in
            (region as? [String: Any])?["is_collapsed"] as? Bool == true
        }
        XCTAssertTrue(collapsedPreserved)

        try processor.setPreserveCollapsedFolds(false)
        try processor.apply(state: state)
        let full3 = try JSONTestHelpers.object(try state.fullStateJSON())
        let folding3 = (full3["folding"] as? [String: Any]) ?? [:]
        let regions3 = (folding3["regions"] as? [Any]) ?? []
        let anyCollapsed = regions3.contains { region in
            (region as? [String: Any])?["is_collapsed"] as? Bool == true
        }
        XCTAssertFalse(anyCollapsed)
    }

    func testSublimeSyntaxLoadingByReferenceAndPath() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        let yaml1 = """
        %YAML 1.2
        ---
        name: Demo1
        scope: source.demo1
        contexts:
          main:
            - match: "\\\\bONE\\\\b"
              scope: keyword.one.demo1
        """
        let yaml2 = """
        %YAML 1.2
        ---
        name: Demo2
        scope: source.demo2
        contexts:
          main:
            - match: "\\\\bTWO\\\\b"
              scope: keyword.two.demo2
        """

        let processor = try SublimeProcessor(library: library, yaml: yaml1)
        try processor.loadSyntaxFromYAML(yaml2)
        try processor.setActiveSyntax(reference: "scope:source.demo2")

        let state2 = try EditorState(library: library, initialText: "TWO\n", viewportWidth: 40)
        try processor.apply(state: state2)
        let blob = try state2.viewportBlob(startVisualRow: 0, rowCount: 5)
        XCTAssertGreaterThan(blob.styleIds.count, 0)

        // test add_search_path + load_from_path + Packages/... reference
        let temp = try EditorCoreFFITestSupport.shared.makeTempDir(prefix: "sublime")
        let packagesDir = temp.appendingPathComponent("Packages/Demo", isDirectory: true)
        try FileManager.default.createDirectory(at: packagesDir, withIntermediateDirectories: true)
        let syntaxPath = packagesDir.appendingPathComponent("Demo.sublime-syntax")
        try yaml1.write(to: syntaxPath, atomically: true, encoding: .utf8)

        try processor.addSearchPath(temp.path)
        try processor.loadSyntaxFromPath(syntaxPath.path)
        try processor.setActiveSyntax(reference: "Packages/Demo/Demo.sublime-syntax")

        // new_from_path constructor smoke
        _ = try SublimeProcessor(library: library, path: syntaxPath.path)
    }

    func testProcessorResultEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "future_processor_operation",
          "status": "future_status",
          "value": {
            "edits": [],
            "future": "kept in raw value"
          },
          "error": null,
          "version": 17,
          "future_top_level": true
        }
        """
        let success = try JSONTestHelpers.decode(EcfProcessorResultEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operation, "future_processor_operation")
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.version, 17)
        guard case .object(let rawValue)? = success.value else {
            XCTFail("expected processor result value object")
            return
        }
        XCTAssertEqual(rawValue["future"], .string("kept in raw value"))
        XCTAssertNil(success.error)

        let failureJSON = """
        {
          "ok": false,
          "operation": "sublime_process",
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 123456,
            "message": "future processor failure",
            "metadata": { "retryable": false }
          },
          "version": 18,
          "future_top_level": true
        }
        """
        let failure = try JSONTestHelpers.decode(EcfProcessorResultEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operation, "sublime_process")
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertNil(failure.error?.status)
        XCTAssertEqual(failure.error?.message, "future processor failure")
    }

    func testOfficialMarkdownSublimeSyntaxLoadsAndHighlightsCodeFences() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        let testFile = URL(fileURLWithPath: #filePath)
        let swiftRoot = testFile
            .deletingLastPathComponent() // EditorCoreFFITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift
        let repoRoot = swiftRoot.deletingLastPathComponent()
        let syntaxPath = repoRoot
            .appendingPathComponent("crates/editor-core-sublime/tests/fixtures/Markdown.sublime-syntax")

        XCTAssertTrue(FileManager.default.fileExists(atPath: syntaxPath.path))

        let processor = try SublimeProcessor(library: library, path: syntaxPath.path)

        let markdown = """
        # Title

        ```rust
        fn main() {}
        ````

        Paragraph after.
        """

        let state = try EditorState(library: library, initialText: markdown, viewportWidth: 80)
        try processor.apply(state: state)

        let blob = try state.viewportBlob(startVisualRow: 0, rowCount: 40)
        XCTAssertGreaterThan(blob.styleIds.count, 0)
    }
}
