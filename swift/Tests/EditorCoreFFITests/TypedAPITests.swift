import Foundation
import XCTest
@testable import EditorCoreFFI

final class TypedAPITests: XCTestCase {
    func testDocumentStatsAndVersionBump() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let state = try EditorState(library: library, initialText: "hello\nworld", viewportWidth: 80)

        let s1 = try state.documentStats()
        XCTAssertEqual(s1.lineCount, 2)
        XCTAssertEqual(s1.charCount, 11)
        XCTAssertEqual(s1.byteCount, 11)

        try state.moveTo(line: 0, column: 5)
        try state.insertText("!")

        let s2 = try state.documentStats()
        XCTAssertTrue(s2.isModified)
        XCTAssertNotEqual(s2.version, s1.version)
        XCTAssertEqual(try state.text(), "hello!\nworld")
    }

    func testTypedBackspaceAndDeleteForward() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        do {
            let state = try EditorState(library: library, initialText: "ab", viewportWidth: 80)
            try state.moveTo(line: 0, column: 1)
            try state.backspace()
            XCTAssertEqual(try state.text(), "b")
        }

        do {
            let state = try EditorState(library: library, initialText: "ab", viewportWidth: 80)
            try state.moveTo(line: 0, column: 0)
            try state.deleteForward()
            XCTAssertEqual(try state.text(), "b")
        }
    }

    func testWorkspaceTypedBackspace() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let ws = try Workspace(library: library)
        let opened = try ws.openBuffer(uri: nil, text: "ab", viewportWidth: 20)

        try ws.moveTo(viewId: opened.viewId, line: 0, column: 2)
        try ws.backspace(viewId: opened.viewId)

        let textObj = try JSONTestHelpers.object(try ws.bufferTextJSON(bufferId: opened.bufferId))
        XCTAssertEqual(textObj["text"] as? String, "a")
    }

    func testViewportBlobParsingRejectsInvalidData() throws {
        // too small
        XCTAssertThrowsError(try ViewportBlob(data: Data([0x00])))

        // wrong header_size (expects MemoryLayout<ViewportBlobHeader>.size)
        let headerSize = MemoryLayout<ViewportBlobHeader>.size
        XCTAssertThrowsError(try ViewportBlob(data: Data(count: headerSize)))
    }
}

