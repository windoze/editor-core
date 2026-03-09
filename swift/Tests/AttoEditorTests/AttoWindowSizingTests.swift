import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoWindowSizingTests: XCTestCase {
    func testDefaultContentSizeUsesPreferredOnLargeScreens() {
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let size = AttoWindowSizing.defaultContentSize(forVisibleFrame: visible)
        XCTAssertEqual(size.width, AttoWindowSizing.preferredContentSize.width)
        XCTAssertEqual(size.height, AttoWindowSizing.preferredContentSize.height)
    }

    func testDefaultContentSizeClampsToVisibleFrameOnSmallScreens() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = AttoWindowSizing.defaultContentSize(forVisibleFrame: visible)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }
}

