import AppKit

enum EditorCoreCoordinateMapping {
    /// Convert a window coordinate (points, origin bottom-left) into the view's backing pixel
    /// coordinate space (origin top-left, y grows downward).
    ///
    /// Why this exists:
    /// - `NSEvent.locationInWindow` 是 window 坐标（points，原点在左下）。
    /// - Swift/AppKit 侧事件命中需要对齐到 Rust 的坐标系：像素（backing px）+ 左上原点（y 向下）。
    ///
    /// 实现选择：
    /// - 这里优先使用 `view.convert(..., from: nil)` + `view.convertToBacking(...)`，
    ///   保证事件坐标与我们计算 viewport（同样基于 view 的 `convertToBacking`）落在同一套坐标系里。
    /// - 在某些缩放模式下，`NSWindow.convertPointToBacking` 与 view 的 backing 映射可能不一致，
    ///   导致“选区/光标移动速度不对”之类的比例问题。
    @MainActor
    static func windowPointToViewBackingPx(windowPoint: NSPoint, view: NSView) -> (xPx: Float, yPx: Float) {
        let viewPoint = view.convert(windowPoint, from: nil)
        let backingPoint = view.convertToBacking(viewPoint)
        return (Float(backingPoint.x), Float(backingPoint.y))
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
