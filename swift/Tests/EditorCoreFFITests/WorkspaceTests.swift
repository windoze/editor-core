import Foundation
import XCTest
@testable import EditorCoreFFI

final class WorkspaceTests: XCTestCase {
    func testWorkspaceLifecycleViewportAndEdits() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let ws = try Workspace(library: library)

        let opened = try ws.openBuffer(uri: "file:///demo.txt", text: "hi\nsecond\n", viewportWidth: 20)
        let bufferId = opened.bufferId
        let viewId = opened.viewId

        let info1 = try JSONTestHelpers.object(try ws.infoJSON())
        XCTAssertEqual(info1["buffer_count"] as? Int, 1)
        XCTAssertEqual(info1["is_empty"] as? Bool, false)

        let view2 = try ws.createView(bufferId: bufferId, viewportWidth: 10)
        XCTAssertTrue(ws.setActiveView(viewId: view2))

        try ws.setViewportHeight(viewId: viewId, height: 12)
        try ws.setSmoothScrollState(viewId: viewId, topVisualRow: 0, subRowOffset: 0, overscanRows: 2)

        // typed operations
        try ws.moveTo(viewId: viewId, line: 0, column: 2)
        try ws.insertText(viewId: viewId, "!")

        // JSON command bridge
        _ = try ws.executeJSON(viewId: viewId, commandJSON: #"{"kind":"edit","op":"insert_text","text":"X"}"#)

        let bufferText = try JSONTestHelpers.object(try ws.bufferTextJSON(bufferId: bufferId))
        let text = bufferText["text"] as? String
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("hi!X") ?? false)

        // workspace viewport state + snapshot JSON
        let viewportState = try JSONTestHelpers.object(try ws.viewportStateJSON(viewId: viewId))
        XCTAssertNotNil(viewportState["width"])
        XCTAssertNotNil(viewportState["height"])
        XCTAssertNotNil(viewportState["total_visual_lines"])

        let styled = try JSONTestHelpers.object(try ws.viewportStyledJSON(viewId: viewId, startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(styled["lines"])
        let minimap = try JSONTestHelpers.object(try ws.minimapJSON(viewId: viewId, startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(minimap["lines"])
        let composed = try JSONTestHelpers.object(try ws.viewportComposedJSON(viewId: viewId, startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(composed["lines"])

        // search
        let search = try JSONTestHelpers.object(try ws.searchAllOpenBuffersJSON(query: "second"))
        let results = (search["results"] as? [Any]) ?? []
        XCTAssertEqual(results.count, 1)

        // apply text edits (char-offset based)
        let editsJSON = """
        [
          {
            "buffer_id": \(bufferId),
            "edits": [
              { "start": 0, "end": 2, "text": "hello" }
            ]
          }
        ]
        """
        _ = try ws.applyTextEditsJSON(editsJSON)

        let bufferText2 = try JSONTestHelpers.object(try ws.bufferTextJSON(bufferId: bufferId))
        let text2 = bufferText2["text"] as? String
        XCTAssertTrue(text2?.hasPrefix("hello") ?? false)

        // apply processing edits to buffer and observe viewport blob styles
        let styleEdits = """
        [
          {
            "op": "replace_style_layer",
            "layer": 55555,
            "intervals": [
              { "start": 0, "end": 5, "style_id": 77 }
            ]
          }
        ]
        """
        try ws.applyProcessingEditsJSON(bufferId: bufferId, editsJSON: styleEdits)
        let blob = try ws.viewportBlob(viewId: viewId, startVisualRow: 0, rowCount: 10)
        XCTAssertTrue(blob.styleIds.contains(77))

        XCTAssertTrue(ws.closeView(viewId: view2))
        XCTAssertTrue(ws.closeBuffer(bufferId: bufferId))

        let info2 = try JSONTestHelpers.object(try ws.infoJSON())
        XCTAssertEqual(info2["buffer_count"] as? Int, 0)
        XCTAssertEqual(info2["is_empty"] as? Bool, true)
    }
}

