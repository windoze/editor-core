#if canImport(AppKit)
import AppKit
import XCTest
@testable import EditorComponentKit

@MainActor
final class EditorComponentFeatureTests: XCTestCase {
    func testFeatureFlagsToggleChromeVisibility() {
        var configuration = EditorComponentConfiguration()
        configuration.features = .init(
            showsGutter: false,
            showsLineNumbers: false,
            showsMinimap: false,
            showsIndentGuides: true,
            showsStructureGuides: true
        )

        let component = EditorComponentView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 640),
            configuration: configuration
        )
        component.layoutSubtreeIfNeeded()

        XCTAssertFalse(component.isGutterVisibleForTesting)
        XCTAssertFalse(component.isMinimapVisibleForTesting)
        XCTAssertFalse(component.showsLineNumbersForTesting)

        component.configuration.features.showsGutter = true
        component.configuration.features.showsLineNumbers = true
        component.configuration.features.showsMinimap = true
        component.layoutSubtreeIfNeeded()

        XCTAssertTrue(component.isGutterVisibleForTesting)
        XCTAssertTrue(component.isMinimapVisibleForTesting)
        XCTAssertTrue(component.showsLineNumbersForTesting)
    }

    func testToggleFoldIgnoresUnknownStartLine() {
        let engine = MockEditorEngine(
            text: "a\nb\nc\n",
            foldRegionData: [EditorFoldRegion(startLine: 0, endLine: 2, isCollapsed: false)]
        )
        let component = EditorComponentView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        component.engine = engine

        component.toggleFold(startLine: 99)

        XCTAssertEqual(engine.foldRegionData.count, 1)
        XCTAssertEqual(engine.foldRegionData[0].isCollapsed, false)
    }
}
#endif
