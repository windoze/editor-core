@testable import AttoEditor
import Foundation
import XCTest

final class AttoDocumentLoadPolicyTests: XCTestCase {
    func testLoadsValidUtf8WithoutDisablingLanguageProcessing() throws {
        let url = try makeTempFile(data: Data("let value = 1\n".utf8))

        let result = try AttoDocumentLoadPolicy.loadText(from: url, largeFileByteLimit: 1024)

        XCTAssertEqual(result.text, "let value = 1\n")
        XCTAssertNil(result.languageProcessingDisabledReason)
        XCTAssertTrue(result.fallbackReasons.isEmpty)
        XCTAssertFalse(result.disablesLanguageProcessing)
    }

    func testLargeFileDisablesLanguageProcessing() throws {
        let url = try makeTempFile(data: Data("abcdef".utf8))

        let result = try AttoDocumentLoadPolicy.loadText(from: url, largeFileByteLimit: 4)

        XCTAssertEqual(result.text, "abcdef")
        XCTAssertEqual(result.languageProcessingDisabledReason, "large file 6 bytes")
        XCTAssertEqual(result.fallbackReasons, [
            "Large file (6 bytes) opened with language services disabled.",
        ])
        XCTAssertTrue(result.disablesLanguageProcessing)
    }

    func testBinaryContentDisablesLanguageProcessing() throws {
        let url = try makeTempFile(data: Data([0x66, 0x00, 0x6F]))

        let result = try AttoDocumentLoadPolicy.loadText(from: url, largeFileByteLimit: 1024)

        XCTAssertEqual(result.text, "f\u{0}o")
        XCTAssertEqual(result.languageProcessingDisabledReason, "binary content")
        XCTAssertEqual(result.fallbackReasons, [
            "Binary content detected; language services disabled.",
        ])
    }

    func testInvalidUtf8UsesReplacementCharactersAndDisablesLanguageProcessing() throws {
        let url = try makeTempFile(data: Data([0x66, 0x80, 0x6F]))

        let result = try AttoDocumentLoadPolicy.loadText(from: url, largeFileByteLimit: 1024)

        XCTAssertEqual(result.text, "f\u{FFFD}o")
        XCTAssertEqual(result.languageProcessingDisabledReason, "invalid UTF-8")
        XCTAssertEqual(result.fallbackReasons, [
            "Invalid UTF-8 detected; opened with replacement characters and language services disabled.",
        ])
    }

    private func makeTempFile(data: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoDocumentLoadPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let url = root.appendingPathComponent("document.txt")
        try data.write(to: url)
        return url
    }
}
