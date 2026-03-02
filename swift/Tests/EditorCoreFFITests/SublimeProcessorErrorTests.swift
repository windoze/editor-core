import Foundation
import XCTest
@testable import EditorCoreFFI

final class SublimeProcessorErrorTests: XCTestCase {
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

    private func makeValidProcessor(library: EditorCoreFFILibrary) throws -> SublimeProcessor {
        let yaml = """
        %YAML 1.2
        ---
        name: Demo
        scope: source.demo
        contexts:
          main:
            - match: "\\\\bONE\\\\b"
              scope: keyword.one.demo
        """
        return try SublimeProcessor(library: library, yaml: yaml)
    }

    func testInvalidYAMLConstructorSetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        let invalidYaml = """
        %YAML 1.2
        ---
        name: Demo
        contexts:
          main: [
        """

        assertThrowsAndSetsLastError(library) {
            _ = try SublimeProcessor(library: library, yaml: invalidYaml)
        }
    }

    func testNewFromPathMissingFileSetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        assertThrowsAndSetsLastError(library) {
            _ = try SublimeProcessor(library: library, path: "/__definitely_not_exists__/Nope.sublime-syntax")
        }
    }

    func testLoadSyntaxFromYAMLAndPathErrorCasesSetLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let processor = try makeValidProcessor(library: library)

        let invalidYaml = "contexts: ["
        assertThrowsAndSetsLastError(library) {
            try processor.loadSyntaxFromYAML(invalidYaml)
        }

        assertThrowsAndSetsLastError(library) {
            try processor.loadSyntaxFromPath("/__definitely_not_exists__/Nope.sublime-syntax")
        }
    }

    func testSetActiveSyntaxInvalidReferenceSetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let processor = try makeValidProcessor(library: library)

        assertThrowsAndSetsLastError(library) {
            try processor.setActiveSyntax(reference: "scope:does.not.exist")
        }
    }
}

