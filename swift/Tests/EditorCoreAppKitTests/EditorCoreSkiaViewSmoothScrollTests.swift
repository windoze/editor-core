import AppKit
@testable import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewSmoothScrollTests: XCTestCase {
    func testScrollWheelUsesSmoothPixelScrolling() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        // Ensure the document is taller than the viewport so scrolling is not clamped to 0.
        let longText = "a\nb\nc\n" + String(repeating: "x\n", count: 200)
        let view = try EditorCoreSkiaView(library: lib, initialText: longText, viewportWidthCells: 80)

        // Put the view in a real window so backing conversions and lifecycle match the demo.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        let before = try view.editor.charOffsetToViewPoint(offset: 2) // "b"

        // `NSEvent` 没有公开构造 scrollWheel 的 API，因此我们直接调用 view 内部的滚动处理逻辑。
        // deltaYPoints 在 hasPreciseScrollingDeltas == false 时被解释为“行数单位”，这里用 0.5 行模拟半行滚动。
        view.handleScroll(deltaYPoints: -0.5, hasPreciseScrollingDeltas: false)

        let after = try view.editor.charOffsetToViewPoint(offset: 2)
        // Scrolling down moves content up, so the same line should be drawn higher.
        XCTAssertLessThan(after.yPx, before.yPx)

        // Roughly half-line: y should decrease by about 0.5 * lineHeight.
        let dy = before.yPx - after.yPx
        XCTAssertEqual(dy, before.lineHeightPx * 0.5, accuracy: 0.01)
    }
}
