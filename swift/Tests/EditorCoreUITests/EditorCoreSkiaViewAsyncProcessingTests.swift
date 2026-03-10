import EditorCoreUI
import EditorCoreUIFFI
import Foundation
import XCTest

@MainActor
final class EditorCoreSkiaViewAsyncProcessingTests: XCTestCase {
    func testAsyncProcessingPollTimerAppliesEdits() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(
            library: lib,
            initialText: "fn main() {\n  let x = 1;\n}\n",
            viewportWidthCells: 80
        )

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // EditorCoreSkiaViewAsyncProcessingTests.swift
            .deletingLastPathComponent() // EditorCoreUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift
        let treesitterRoot = repoRoot.appendingPathComponent(
            "crates/editor-core-treesitter/tests/fixtures/treesitter",
            isDirectory: true
        )
        let registry: [String: Any] = [
            "schema_version": 1,
            "root_dir": treesitterRoot.path,
            "extension_map": ["rs": "rust"],
            "languages": [
                "rust": [
                    "wasm": "rust/language.wasm",
                    "highlights": "rust/highlights.scm",
                    "folds": "rust/folds.scm",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: registry, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            XCTFail("failed to encode registry json")
            return
        }
        try view.editor.treeSitterSetRegistryJSON(json)
        try view.editor.treeSitterEnableLanguage("rust")

        let applied = expectation(description: "applied async processing")
        view.onDidApplyAsyncProcessing = {
            applied.fulfill()
        }

        // Trigger a text mutation so the view starts its polling timer.
        view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))

        wait(for: [applied], timeout: 2.0)
    }
}
