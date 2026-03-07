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
    /// - 为了让输入坐标与 viewport（我们用 `convertToBacking(size)` 计算）严格一致：
    ///   - 用 `view.convert(windowPoint, from: nil)` 得到 view-local points（会正确处理 bounds/frame/flip/transform）
    ///   - 再用 `convertToBacking(bounds.size)` 推导出 `sx/sy`（像素/点），把 view-local points 乘回去
    ///   这样避免依赖 `convertToBacking(point)` 的实现细节，同时也避免手算 top-left 时丢失 view 的 bounds 变换。
    @MainActor
    static func windowPointToViewBackingPx(windowPoint: NSPoint, view: NSView) -> (xPx: Float, yPx: Float) {
        let bounds = view.bounds
        let wPt = bounds.size.width
        let hPt = bounds.size.height
        guard wPt > 0, hPt > 0 else { return (0, 0) }

        let viewPoint = view.convert(windowPoint, from: nil)

        // 用 size 的 backing 换算推导像素/点比例，保证和 viewport 计算一致。
        let backingSize = view.convertToBacking(bounds.size)
        let sx = backingSize.width / wPt
        let sy = backingSize.height / hPt

        return (Float(viewPoint.x * sx), Float(viewPoint.y * sy))
    }

    @MainActor
    static func viewPointToViewBackingPx(viewPoint: NSPoint, view: NSView) -> (xPx: Float, yPx: Float) {
        let bounds = view.bounds
        let wPt = bounds.size.width
        let hPt = bounds.size.height
        guard wPt > 0, hPt > 0 else { return (0, 0) }

        let backingSize = view.convertToBacking(bounds.size)
        let sx = backingSize.width / wPt
        let sy = backingSize.height / hPt

        return (Float(viewPoint.x * sx), Float(viewPoint.y * sy))
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
