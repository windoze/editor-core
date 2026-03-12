import Foundation
@testable import AttoEditor
import XCTest

final class AttoLspRegistryTests: XCTestCase {
    func testParseServersJSONAcceptsSchemaVersionedExtensionMap() throws {
        let obj: [String: Any] = [
            "schema_version": 1,
            "extension_map": [
                "rs": [
                    "command": "rust-analyzer",
                    "args": "--stdio",
                    "language_id": "rust",
                ],
                ".PY": "pylsp",
                "ts": [
                    "command": "typescript-language-server",
                    "args": "--stdio",
                    "languageId": "typescript",
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        let map = try AttoLspRegistry.parseServersJSON(data)

        XCTAssertEqual(
            map["rs"],
            AttoLspRegistry.ServerConfig(command: "rust-analyzer", args: "--stdio", languageId: "rust")
        )
        XCTAssertEqual(
            map["py"],
            AttoLspRegistry.ServerConfig(command: "pylsp", args: nil, languageId: nil)
        )
        XCTAssertEqual(
            map["ts"],
            AttoLspRegistry.ServerConfig(command: "typescript-language-server", args: "--stdio", languageId: "typescript")
        )
    }

    func testParseServersJSONRejectsUnknownSchemaVersion() throws {
        let obj: [String: Any] = [
            "schema_version": 2,
            "extension_map": [
                "rs": "rust-analyzer",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        let map = try AttoLspRegistry.parseServersJSON(data)
        XCTAssertTrue(map.isEmpty)
    }

    func testParseServersJSONSupportsMinimalTopLevelMap() throws {
        let obj: [String: Any] = [
            "rs": "rust-analyzer",
            "py": [
                "command": "pylsp",
                "language_id": "python",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        let map = try AttoLspRegistry.parseServersJSON(data)

        XCTAssertEqual(
            map["rs"],
            AttoLspRegistry.ServerConfig(command: "rust-analyzer", args: nil, languageId: nil)
        )
        XCTAssertEqual(
            map["py"],
            AttoLspRegistry.ServerConfig(command: "pylsp", args: nil, languageId: "python")
        )
    }

    func testLoadServerMapKeepsFileOnParseError() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("AttoLspRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let serversURL = tempDir.appendingPathComponent("servers.json", isDirectory: false)
        try "{ this is not json".write(to: serversURL, atomically: true, encoding: .utf8)

        let map = AttoLspRegistry.loadServerMap(from: serversURL, fileManager: fm)
        XCTAssertTrue(map.isEmpty)

        XCTAssertTrue(fm.fileExists(atPath: serversURL.path))
    }
}
