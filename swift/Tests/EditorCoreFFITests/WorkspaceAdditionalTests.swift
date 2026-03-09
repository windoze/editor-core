import Foundation
import XCTest
@testable import EditorCoreFFI

final class WorkspaceAdditionalTests: XCTestCase {
    private func decodeResult(_ json: String) throws -> CommandResultJSON {
        try JSONTestHelpers.decode(CommandResultJSON.self, from: json)
    }

    func testWorkspaceExecuteJSONSupportsCursorViewAndStyleOps() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let ws = try Workspace(library: library)
        let opened = try ws.openBuffer(uri: "file:///ws.json", text: "abcd\nefgh\n", viewportWidth: 4)

        // cursor move
        let r1 = try decodeResult(try ws.executeJSON(viewId: opened.viewId, commandJSON: #"{"kind":"cursor","op":"move_to","line":1,"column":2}"#))
        XCTAssertEqual(r1.kind, "success")

        // view get_viewport => viewport result
        let r2 = try decodeResult(try ws.executeJSON(viewId: opened.viewId, commandJSON: #"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#))
        XCTAssertEqual(r2.kind, "viewport")
        XCTAssertGreaterThan(r2.viewport?.actualLineCount ?? 0, 0)

        // style add/remove affects viewport blob styles
        let r3 = try decodeResult(
            try ws.executeJSON(viewId: opened.viewId, commandJSON: #"{"kind":"style","op":"add_style","start":0,"end":1,"style_id":321}"#)
        )
        XCTAssertEqual(r3.kind, "success")
        XCTAssertTrue(try ws.viewportBlob(viewId: opened.viewId, startVisualRow: 0, rowCount: 10).styleIds.contains(321))

        let r4 = try decodeResult(
            try ws.executeJSON(viewId: opened.viewId, commandJSON: #"{"kind":"style","op":"remove_style","start":0,"end":1,"style_id":321}"#)
        )
        XCTAssertEqual(r4.kind, "success")
        XCTAssertFalse(try ws.viewportBlob(viewId: opened.viewId, startVisualRow: 0, rowCount: 10).styleIds.contains(321))

        // folding via style command
        _ = try decodeResult(try ws.executeJSON(viewId: opened.viewId, commandJSON: #"{"kind":"style","op":"fold","start_line":0,"end_line":1}"#))
        let styled = try JSONTestHelpers.object(try ws.viewportStyledJSON(viewId: opened.viewId, startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(styled["lines"])

        // basic edit through JSON
        _ = try decodeResult(try ws.executeJSON(viewId: opened.viewId, commandJSON: #"{"kind":"edit","op":"insert_text","text":"Z"}"#))
        let bufText = try JSONTestHelpers.object(try ws.bufferTextJSON(bufferId: opened.bufferId))
        XCTAssertTrue((bufText["text"] as? String)?.contains("Z") ?? false)
    }

    func testWorkspaceErrorsAndNotFoundReturnValues() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let ws = try Workspace(library: library)

        // close_* on unknown ids should return false (not crash)
        XCTAssertFalse(ws.closeView(viewId: 999_999))
        XCTAssertFalse(ws.closeBuffer(bufferId: 999_999))

        // set_active_view on unknown id should return false
        XCTAssertFalse(ws.setActiveView(viewId: 999_999))

        // execute_json on unknown view id should fail and set last_error_message
        do {
            _ = try ws.executeJSON(viewId: 999_999, commandJSON: #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#)
            XCTFail("期望抛错，但实际未抛错")
        } catch {
            XCTAssertFalse(library.lastErrorMessage().isEmpty)
        }
    }
}

