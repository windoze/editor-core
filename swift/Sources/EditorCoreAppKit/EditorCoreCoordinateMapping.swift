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
    /// - 在 macOS “缩放显示 / Retina” 等组合下，`convertToBacking(point)` 在某些层级/配置里可能出现
    ///   point/size 映射不一致（表现为 X 方向比例不对、Y 方向命中异常）。
    /// - 为了让输入坐标与 viewport（我们用 `convertToBacking(size)` 计算）严格一致，这里使用：
    ///   - window points → view top-left local points（手算）
    ///   - 再用 `convertToBacking(size)` 推导出 `sx/sy`（像素/点），把 local points 乘回去
    ///   这样可以避免依赖 `convertToBacking(point)` 的实现细节。
    @MainActor
    static func windowPointToViewBackingPx(windowPoint: NSPoint, view: NSView) -> (xPx: Float, yPx: Float) {
        let bounds = view.bounds
        let wPt = bounds.size.width
        let hPt = bounds.size.height

        guard wPt > 0, hPt > 0 else {
            return (0, 0)
        }

        // 求出 view 的 top-left 在 window points 坐标系下的位置（window 坐标原点在左下）。
        //
        // 注意：不要假设 view.isFlipped 一定会影响到所有坐标换算；取 (0,0) 与 (0,h) 两个点，
        // 选 y 更大的那个作为 top-left（因为 window y 向上）。
        let p0 = view.convert(NSPoint(x: 0, y: 0), to: nil)
        let p1 = view.convert(NSPoint(x: 0, y: hPt), to: nil)
        let topLeftInWindow = (p0.y >= p1.y) ? p0 : p1

        let xLocalPt = windowPoint.x - topLeftInWindow.x
        let yLocalPt = topLeftInWindow.y - windowPoint.y

        // 用 size 的 backing 换算推导像素/点比例，保证和 viewport 计算一致。
        let backingSize = view.convertToBacking(bounds.size)
        let sx = backingSize.width / wPt
        let sy = backingSize.height / hPt

        let xPx = xLocalPt * sx
        let yPx = yLocalPt * sy
        return (Float(xPx), Float(yPx))
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
