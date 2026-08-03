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

        let typedInfo1 = try ws.info()
        XCTAssertEqual(typedInfo1.bufferCount, 1)
        XCTAssertEqual(typedInfo1.viewCount, 1)
        XCTAssertEqual(typedInfo1.isEmpty, false)
        XCTAssertEqual(typedInfo1.activeViewId, viewId)
        XCTAssertEqual(typedInfo1.activeBufferId, bufferId)

        let info1 = try JSONTestHelpers.object(try ws.infoJSON())
        XCTAssertEqual(info1["buffer_count"] as? Int, 1)
        XCTAssertEqual(info1["is_empty"] as? Bool, false)

        let view2 = try ws.createView(bufferId: bufferId, viewportWidth: 10)
        XCTAssertTrue(ws.setActiveView(viewId: view2))

        try ws.setViewportHeight(viewId: viewId, height: 12)
        try ws.setSmoothScrollState(viewId: viewId, topVisualRow: 0, subRowOffset: 0, overscanRows: 2)

        let typedViewport = try ws.viewportState(viewId: viewId)
        XCTAssertEqual(typedViewport.widthCells, 20)
        XCTAssertEqual(typedViewport.heightRows, UInt32(12))
        XCTAssertEqual(typedViewport.scrollTop, 0)
        XCTAssertEqual(typedViewport.subRowOffset, 0)
        XCTAssertEqual(typedViewport.overscanRows, 2)
        XCTAssertEqual(typedViewport.visibleStart, 0)
        XCTAssertEqual(typedViewport.visibleEnd, min(typedViewport.totalVisualLines, UInt32(12)))

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

    func testWorkspaceMinimapEnvelope() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let ws = try Workspace(library: library)
        let opened = try ws.openBuffer(uri: "file:///demo.txt", text: "hello\nworld\n", viewportWidth: 80)

        let envelope = try ws.minimapEnvelope(viewId: opened.viewId, startVisualRow: 0, rowCount: 20)
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertEqual(envelope.surface, "workspace_minimap")
        XCTAssertEqual(envelope.viewId, opened.viewId)
        XCTAssertEqual(envelope.startVisualRow, 0)
        XCTAssertEqual(envelope.count, 20)
        XCTAssertNil(envelope.error)
        XCTAssertEqual(envelope.version, library.abiVersion)
        guard case let .object(value)? = envelope.value else {
            return XCTFail("expected object minimap value")
        }
        XCTAssertNotNil(value["lines"])

        let failure = try ws.minimapEnvelope(viewId: 999_999, startVisualRow: 0, rowCount: 20)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.surface, "workspace_minimap")
        XCTAssertEqual(failure.viewId, 999_999)
        XCTAssertEqual(failure.error?.code, "internal")
        XCTAssertEqual(failure.error?.status, .internal)
        XCTAssertTrue(failure.error?.message.contains("get_minimap_content failed") ?? false)
        XCTAssertEqual(failure.value, .null)
    }

    func testWorkspaceViewportEnvelope() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let ws = try Workspace(library: library)
        let opened = try ws.openBuffer(uri: "file:///demo.txt", text: "hello\nworld\n", viewportWidth: 80)

        let styled = try ws.viewportStyledEnvelope(viewId: opened.viewId, startVisualRow: 0, rowCount: 20)
        XCTAssertTrue(styled.ok)
        XCTAssertEqual(styled.statusKind, .success)
        XCTAssertEqual(styled.surface, "workspace_viewport_styled")
        XCTAssertEqual(styled.viewId, opened.viewId)
        XCTAssertEqual(styled.startVisualRow, 0)
        XCTAssertEqual(styled.count, 20)
        XCTAssertNil(styled.error)
        XCTAssertEqual(styled.version, library.abiVersion)
        guard case let .object(styledValue)? = styled.value else {
            return XCTFail("expected object styled viewport value")
        }
        XCTAssertNotNil(styledValue["lines"])

        let composed = try ws.viewportComposedEnvelope(viewId: opened.viewId, startVisualRow: 0, rowCount: 20)
        XCTAssertTrue(composed.ok)
        XCTAssertEqual(composed.statusKind, .success)
        XCTAssertEqual(composed.surface, "workspace_viewport_composed")
        XCTAssertEqual(composed.viewId, opened.viewId)
        XCTAssertEqual(composed.startVisualRow, 0)
        XCTAssertEqual(composed.count, 20)
        XCTAssertNil(composed.error)
        XCTAssertEqual(composed.version, library.abiVersion)
        guard case let .object(composedValue)? = composed.value else {
            return XCTFail("expected object composed viewport value")
        }
        XCTAssertNotNil(composedValue["lines"])

        let failure = try ws.viewportStyledEnvelope(viewId: 999_999, startVisualRow: 0, rowCount: 20)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.surface, "workspace_viewport_styled")
        XCTAssertEqual(failure.viewId, 999_999)
        XCTAssertEqual(failure.error?.code, "internal")
        XCTAssertEqual(failure.error?.status, .internal)
        XCTAssertTrue(failure.error?.message.contains("get_viewport_content_styled failed") ?? false)
        XCTAssertEqual(failure.value, .null)
    }

    func testWorkspaceQueryEnvelopes() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let ws = try Workspace(library: library)

        let emptyInfo = try ws.infoEnvelope()
        XCTAssertTrue(emptyInfo.ok)
        XCTAssertEqual(emptyInfo.statusKind, .success)
        XCTAssertEqual(emptyInfo.operation, "info")
        XCTAssertEqual(emptyInfo.version, library.abiVersion)
        XCTAssertNil(emptyInfo.error)
        guard case .object(let emptyInfoValue)? = emptyInfo.value else {
            return XCTFail("expected workspace info object")
        }
        XCTAssertEqual(emptyInfoValue["buffer_count"], .number(0))
        XCTAssertEqual(emptyInfoValue["view_count"], .number(0))
        XCTAssertEqual(emptyInfoValue["is_empty"], .bool(true))

        let opened = try ws.openBuffer(uri: "file:///query-envelope.txt", text: "hello\nworld\n", viewportWidth: 80)

        let info = try ws.infoEnvelope()
        XCTAssertTrue(info.ok)
        XCTAssertEqual(info.statusKind, .success)
        XCTAssertEqual(info.operation, "info")
        guard case .object(let infoValue)? = info.value else {
            return XCTFail("expected workspace info object after open")
        }
        XCTAssertEqual(infoValue["buffer_count"], .number(1))
        XCTAssertEqual(infoValue["view_count"], .number(1))
        XCTAssertEqual(infoValue["is_empty"], .bool(false))
        XCTAssertEqual(infoValue["active_buffer_id"], .number(Double(opened.bufferId)))
        XCTAssertEqual(infoValue["active_view_id"], .number(Double(opened.viewId)))

        let bufferText = try ws.bufferTextEnvelope(bufferId: opened.bufferId)
        XCTAssertTrue(bufferText.ok)
        XCTAssertEqual(bufferText.statusKind, .success)
        XCTAssertEqual(bufferText.operation, "buffer_text")
        XCTAssertNil(bufferText.error)
        guard case .object(let bufferTextValue)? = bufferText.value else {
            return XCTFail("expected buffer text object")
        }
        XCTAssertEqual(bufferTextValue["text"], .string("hello\nworld\n"))

        let viewport = try ws.viewportStateEnvelope(viewId: opened.viewId)
        XCTAssertTrue(viewport.ok)
        XCTAssertEqual(viewport.statusKind, .success)
        XCTAssertEqual(viewport.operation, "viewport_state")
        XCTAssertNil(viewport.error)
        guard case .object(let viewportValue)? = viewport.value else {
            return XCTFail("expected viewport state object")
        }
        XCTAssertEqual(viewportValue["width"], .number(80))
        XCTAssertNotNil(viewportValue["total_visual_lines"])

        let missingText = try ws.bufferTextEnvelope(bufferId: 999_999)
        XCTAssertFalse(missingText.ok)
        XCTAssertEqual(missingText.statusKind, .error)
        XCTAssertEqual(missingText.operation, "buffer_text")
        XCTAssertEqual(missingText.value, .null)
        XCTAssertEqual(missingText.error?.code, "not_found")
        XCTAssertEqual(missingText.error?.status, .notFound)
        XCTAssertTrue(missingText.error?.message.contains("buffer_text failed") ?? false)

        let missingViewport = try ws.viewportStateEnvelope(viewId: 999_999)
        XCTAssertFalse(missingViewport.ok)
        XCTAssertEqual(missingViewport.statusKind, .error)
        XCTAssertEqual(missingViewport.operation, "viewport_state")
        XCTAssertEqual(missingViewport.value, .null)
        XCTAssertEqual(missingViewport.error?.code, "not_found")
        XCTAssertEqual(missingViewport.error?.status, .notFound)
        XCTAssertTrue(missingViewport.error?.message.contains("viewport_state_for_view failed") ?? false)
    }
}
