import Foundation
import XCTest
@testable import EditorCoreFFI

final class TreeSitterProcessorErrorTests: XCTestCase {
    private func assertThrowsAndSetsLastError(
        _ library: EditorCoreFFILibrary,
        _ f: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try f()
            XCTFail("期望抛错，但实际未抛错", file: file, line: line)
        } catch {
            FFITestHelpers.assertLastErrorSet(library, file: file, line: line)
        }
    }

    func testInvalidHighlightsQuerySetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        assertThrowsAndSetsLastError(library) {
            _ = try TreeSitterProcessor(
                library: library,
                languageFn: library.treeSitterRustLanguageFn,
                highlightsQuery: "(",
                foldsQuery: nil,
                captureStylesJSON: nil,
                styleLayer: 1,
                preserveCollapsedFolds: false
            )
        }
    }

    func testInvalidFoldsQuerySetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        assertThrowsAndSetsLastError(library) {
            _ = try TreeSitterProcessor(
                library: library,
                languageFn: library.treeSitterRustLanguageFn,
                highlightsQuery: "(identifier) @id",
                foldsQuery: "(",
                captureStylesJSON: nil,
                styleLayer: 1,
                preserveCollapsedFolds: false
            )
        }
    }

    func testInvalidCaptureStylesJSONSetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        assertThrowsAndSetsLastError(library) {
            _ = try TreeSitterProcessor(
                library: library,
                languageFn: library.treeSitterRustLanguageFn,
                highlightsQuery: "(identifier) @id",
                foldsQuery: nil,
                captureStylesJSON: "[]",
                styleLayer: 1,
                preserveCollapsedFolds: false
            )
        }
    }
}

