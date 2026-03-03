import AppKit

enum EditorCoreCoordinateMapping {
    /// Convert a window coordinate (points, origin bottom-left) into the view's backing pixel
    /// coordinate space (origin top-left, y grows downward).
    ///
    /// Why this exists:
    /// - `NSEvent.locationInWindow` is always in window points (bottom-left origin).
    /// - The Rust rendering/hit-test APIs in `editor-core-ui` operate in pixels with a top-left origin.
    /// - Under某些 macOS 缩放/HiDPI 组合里，直接 `view.convertToBacking(view.convert(...))` 会出现点击位置与光标不一致；
    ///   这里统一走 `window.convertToBacking` 的“窗口 backing 坐标”，再用 view 的 top-left 做相对差值，
    ///   使输入与渲染始终对齐在同一套 backing 像素坐标系中。
    @MainActor
    static func windowPointToViewBackingPx(windowPoint: NSPoint, view: NSView) -> (xPx: Float, yPx: Float) {
        guard let window = view.window else {
            let p = view.convert(windowPoint, from: nil)
            let bp = view.convertToBacking(p)
            return (Float(bp.x), Float(bp.y))
        }

        let pWindowBacking = window.convertPointToBacking(windowPoint)

        // For a flipped view, `.zero` is the top-left corner in view coordinates.
        let viewTopLeftInWindowPoints = view.convert(NSPoint(x: 0, y: 0), to: nil)
        let viewTopLeftInWindowBacking = window.convertPointToBacking(viewTopLeftInWindowPoints)

        // Window backing space is still bottom-left origin; we convert it to a top-left origin
        // local to the view by subtracting from the view's top-left.
        let x = pWindowBacking.x - viewTopLeftInWindowBacking.x
        let y = viewTopLeftInWindowBacking.y - pWindowBacking.y
        return (Float(x), Float(y))
    }

    @MainActor
    static func viewPointToViewBackingPx(viewPoint: NSPoint, view: NSView) -> (xPx: Float, yPx: Float) {
        let windowPoint = view.convert(viewPoint, to: nil)
        return windowPointToViewBackingPx(windowPoint: windowPoint, view: view)
    }

    // MARK: - Pure helpers (testable without AppKit backing-scale dependencies)

    static func windowBackingToViewBackingPx(
        windowBackingPoint: NSPoint,
        viewTopLeftInWindowBacking: NSPoint
    ) -> NSPoint {
        NSPoint(
            x: windowBackingPoint.x - viewTopLeftInWindowBacking.x,
            y: viewTopLeftInWindowBacking.y - windowBackingPoint.y
        )
    }
}
