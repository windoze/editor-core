import EditorCoreUIFFI
import Foundation
import XCTest

final class EditorCoreUIFFITests: XCTestCase {
    @discardableResult
    func assertCommandSuccess(
        _ ui: EditorUI,
        _ commandJSON: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let result = try ui.executeCommandJSON(commandJSON)
        let data = try XCTUnwrap(result.data(using: .utf8), file: file, line: line)
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            file: file,
            line: line
        )
        XCTAssertEqual(obj["kind"] as? String, "success", file: file, line: line)
        return obj
    }

    func waitForAsyncProcessing(_ ui: EditorUI, timeoutSeconds: TimeInterval = 2.0) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while true {
            let r = try ui.pollProcessing()
            if r.pending == false {
                return
            }
            if Date() > deadline {
                XCTFail("timeout waiting for async processing")
                return
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func setTestTreeSitterRegistry(_ ui: EditorUI) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // test source file
            .deletingLastPathComponent() // EditorCoreFFITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift

        let root = repoRoot.appendingPathComponent(
            "crates/editor-core-treesitter/tests/fixtures/treesitter",
            isDirectory: true
        )

        let registry: [String: Any] = [
            "schema_version": 1,
            "root_dir": root.path,
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

        try ui.treeSitterSetRegistryJSON(json)
    }

    func pixel(_ buf: [UInt8], widthPx: UInt32, x: UInt32, y: UInt32) -> [UInt8] {
        let idx = Int((y * widthPx + x) * 4)
        return [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
