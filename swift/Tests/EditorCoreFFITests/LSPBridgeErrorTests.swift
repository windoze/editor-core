import Foundation
import XCTest
@testable import EditorCoreFFI

final class LSPBridgeErrorTests: XCTestCase {
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

    func testInvalidUriAndJsonInputsSetLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)
        let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)

        assertThrowsAndSetsLastError(library) {
            _ = try bridge.fileURIToPath("not-a-file-uri")
        }

        assertThrowsAndSetsLastError(library) {
            _ = try bridge.applyTextEditsJSON(state: state, editsJSON: "{this is not json")
        }

        // semantic tokens: JSON 正常但数据长度非法（必须是 5 的倍数）
        assertThrowsAndSetsLastError(library) {
            _ = try bridge.semanticTokensToIntervalsJSON(state: state, dataJSON: "[0,0,1,2]")
        }

        assertThrowsAndSetsLastError(library) {
            _ = try bridge.documentHighlightsToProcessingEditJSON(state: state, resultJSON: "{not json")
        }
        assertThrowsAndSetsLastError(library) {
            _ = try bridge.inlayHintsToProcessingEditJSON(state: state, resultJSON: "{not json")
        }
        assertThrowsAndSetsLastError(library) {
            _ = try bridge.documentLinksToProcessingEditJSON(state: state, resultJSON: "{not json")
        }
        assertThrowsAndSetsLastError(library) {
            _ = try bridge.codeLensToProcessingEditJSON(state: state, resultJSON: "{not json")
        }
        assertThrowsAndSetsLastError(library) {
            _ = try bridge.documentSymbolsToProcessingEditJSON(state: state, resultJSON: "{not json")
        }

        assertThrowsAndSetsLastError(library) {
            _ = try bridge.workspaceSymbolsJSON(resultJSON: "{not json")
        }
        assertThrowsAndSetsLastError(library) {
            _ = try bridge.locationsJSON(resultJSON: "{not json")
        }
    }

    func testInvalidCompletionModeSetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)
        let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)

        let completionItem = #"{"label":"x"}"#

        assertThrowsAndSetsLastError(library) {
            _ = try bridge.completionItemToTextEditsJSON(
                state: state,
                completionItemJSON: completionItem,
                mode: "definitely-not-a-mode",
                fallback: nil
            )
        }

        assertThrowsAndSetsLastError(library) {
            try bridge.applyCompletionItemJSON(
                state: state,
                completionItemJSON: completionItem,
                mode: "definitely-not-a-mode"
            )
        }
    }

    func testInvalidDiagnosticsPayloadSetsLastErrorMessage() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)
        let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)

        // publishDiagnostics 缺少必要字段（uri/diagnostics），应报错
        assertThrowsAndSetsLastError(library) {
            _ = try bridge.diagnosticsToProcessingEditsJSON(state: state, publishDiagnosticsParamsJSON: "{}")
        }
    }
}

