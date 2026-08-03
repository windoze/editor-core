@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspDocumentLinkParserTests: XCTestCase {
    func testParserProjectsDocumentLinkDecorations() throws {
        let linkJSON = """
        {
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 4 }
          },
          "target": "https://example.com/docs",
          "tooltip": "Open docs"
        }
        """
        let snapshot = EcuDecorationsSnapshot(layers: [
            EcuDecorationLayerSnapshot(layer: 1, decorations: [
                EcuDecoration(
                    range: EcuOffsetRange(start: 0, end: 4),
                    placement: .after,
                    kind: .object(["kind": .string("document_link")]),
                    text: nil,
                    styles: [],
                    tooltip: "Open docs",
                    dataJSON: linkJSON
                ),
                EcuDecoration(
                    range: EcuOffsetRange(start: 8, end: 8),
                    placement: .after,
                    kind: .object(["kind": .string("inlay_hint")]),
                    text: ": Int",
                    styles: [],
                    tooltip: nil,
                    dataJSON: "{}"
                ),
            ]),
        ])

        let items = AttoLspDocumentLinkParser.items(fromDecorationsSnapshot: snapshot)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "https://example.com/docs")
        XCTAssertEqual(items[0].target, "https://example.com/docs")
        XCTAssertEqual(items[0].tooltip, "Open docs")
        XCTAssertEqual(items[0].range, EcuOffsetRange(start: 0, end: 4))
        XCTAssertEqual(items[0].linkJSON, linkJSON)
    }
}
