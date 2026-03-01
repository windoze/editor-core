#if canImport(AppKit)
import AppKit
import XCTest
@testable import EditorComponentKit

@MainActor
final class EditorRenderingPipelineTests: XCTestCase {
    func testReloadAppliesStylesInlaysDiagnosticsAndMinimap() {
        let styleID: UInt32 = 42
        let config = EditorComponentConfiguration(
            features: .init(showsMinimap: true),
            visualStyle: .init(
                stylePalette: .init(styles: [
                    styleID: EditorStyleAttributes(
                        foreground: EditorRGBAColor(red: 1, green: 0, blue: 0)
                    )
                ])
            )
        )
        let engine = MockEditorEngine(
            text: "func main() {\n    return 1\n}\n",
            styleSpanData: [EditorStyleSpan(startOffset: 0, endOffset: 4, styleID: styleID)],
            inlayData: [EditorInlay(offset: 4, text: ": Int", placement: .after)],
            foldRegionData: [EditorFoldRegion(startLine: 0, endLine: 2, isCollapsed: false)],
            diagnosticsData: .init(items: [
                .init(
                    startOffset: 5,
                    endOffset: 9,
                    severity: "warning",
                    message: "demo warning"
                )
            ])
        )

        let component = EditorComponentView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 640),
            configuration: config
        )
        component.engine = engine
        component.layoutSubtreeIfNeeded()

        XCTAssertEqual(component.currentDisplayedText, engine.text)
        XCTAssertEqual(component.textViewForTesting.debugInlayCount, 1)
        XCTAssertEqual(component.textViewForTesting.debugFoldRegionCount, 1)
        XCTAssertEqual(component.foldRegionsForTesting.count, 1)
        XCTAssertGreaterThan(component.minimapSnapshotForTesting.lines.count, 0)
        XCTAssertNotNil(component.visibleMinimapRangeForTesting)

        let styleAttrs = component.textViewForTesting.debugTemporaryAttributes(atUTF16Offset: 1)
        XCTAssertNotNil(styleAttrs[.foregroundColor])

        let diagnosticAttrs = component.textViewForTesting.debugTemporaryAttributes(atUTF16Offset: 6)
        XCTAssertNotNil(diagnosticAttrs[.underlineStyle])
    }

    func testToggleFoldDispatchesFoldThenUnfold() {
        let engine = MockEditorEngine(
            text: "if a {\n  if b {\n    c\n  }\n}\n",
            foldRegionData: [EditorFoldRegion(startLine: 0, endLine: 4, isCollapsed: false)]
        )
        let component = EditorComponentView(
            frame: NSRect(x: 0, y: 0, width: 700, height: 500)
        )
        component.engine = engine

        component.toggleFold(startLine: 0)
        XCTAssertEqual(engine.foldRegionData.first?.isCollapsed, true)

        component.toggleFold(startLine: 0)
        XCTAssertEqual(engine.foldRegionData.first?.isCollapsed, false)
    }
}
#endif
