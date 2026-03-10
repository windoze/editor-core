import Foundation
@testable import AttoEditor
import XCTest

final class AttoTreeSitterRegistryTests: XCTestCase {
    func testBuildRegistryJSONPicksUpSingleWasmFileAndDefaultExtensionMapping() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("AttoTreeSitterRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let treesitterRoot = tempDir.appendingPathComponent("treesitter", isDirectory: true)
        try fm.createDirectory(at: treesitterRoot, withIntermediateDirectories: true)

        let ruskDir = treesitterRoot.appendingPathComponent("rusk", isDirectory: true)
        try fm.createDirectory(at: ruskDir, withIntermediateDirectories: true)

        // Non-conventional but common naming (e.g. copied from other toolchains).
        let wasmURL = ruskDir.appendingPathComponent("rusk.wasm", isDirectory: false)
        fm.createFile(atPath: wasmURL.path, contents: Data())

        let highlightsURL = ruskDir.appendingPathComponent("highlights.scm", isDirectory: false)
        try "\n".write(to: highlightsURL, atomically: true, encoding: .utf8)

        let foldsURL = ruskDir.appendingPathComponent("folds.scm", isDirectory: false)
        try "\n".write(to: foldsURL, atomically: true, encoding: .utf8)

        let json = try AttoTreeSitterRegistry.buildRegistryJSON(treesitterRoot: treesitterRoot, fileManager: fm)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])

        XCTAssertEqual(obj["schema_version"] as? Int, 1)
        XCTAssertEqual(obj["root_dir"] as? String, treesitterRoot.path)

        let extMap = try XCTUnwrap(obj["extension_map"] as? [String: String])
        XCTAssertEqual(extMap["rusk"], "rusk")

        let languages = try XCTUnwrap(obj["languages"] as? [String: Any])
        let rusk = try XCTUnwrap(languages["rusk"] as? [String: String])
        XCTAssertEqual(rusk["wasm"], "rusk/rusk.wasm")
        XCTAssertEqual(rusk["highlights"], "rusk/highlights.scm")
        XCTAssertEqual(rusk["folds"], "rusk/folds.scm")
    }

    func testBuildRegistryJSONPrefersUserRegistryJSONWhenSchemaVersioned() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("AttoTreeSitterRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let treesitterRoot = tempDir.appendingPathComponent("treesitter", isDirectory: true)
        try fm.createDirectory(at: treesitterRoot, withIntermediateDirectories: true)

        let registryURL = treesitterRoot.appendingPathComponent("registry.json", isDirectory: false)
        let registryObj: [String: Any] = [
            "schema_version": 1,
            "root_dir": "/tmp/SHOULD_BE_OVERWRITTEN",
            "extension_map": ["rusk": "rusk"],
            "languages": [
                "rusk": [
                    "wasm": "rusk/rusk.wasm",
                    "highlights": "rusk/highlights.scm",
                ],
            ],
        ]
        let registryData = try JSONSerialization.data(withJSONObject: registryObj, options: [])
        fm.createFile(atPath: registryURL.path, contents: registryData)

        let json = try AttoTreeSitterRegistry.buildRegistryJSON(treesitterRoot: treesitterRoot, fileManager: fm)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])

        // Ensures we rewrote `root_dir` to match the actual on-disk root.
        XCTAssertEqual(obj["schema_version"] as? Int, 1)
        XCTAssertEqual(obj["root_dir"] as? String, treesitterRoot.path)

        let extMap = try XCTUnwrap(obj["extension_map"] as? [String: String])
        XCTAssertEqual(extMap["rusk"], "rusk")

        let languages = try XCTUnwrap(obj["languages"] as? [String: Any])
        let rusk = try XCTUnwrap(languages["rusk"] as? [String: String])
        XCTAssertEqual(rusk["wasm"], "rusk/rusk.wasm")
        XCTAssertEqual(rusk["highlights"], "rusk/highlights.scm")
    }
}

