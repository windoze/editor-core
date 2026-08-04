import AppKit
import EditorCoreUIFFI
import Foundation
import Metal
import MetalKit

extension EditorCoreSkiaView {
    // MARK: - Draw scheduling

    /// Request a redraw for an on-demand `MTKView` (`isPaused = true`, `enableSetNeedsDisplay = true`).
    ///
    /// Why we do this:
    /// - 在某些 macOS/MTKView 组合下，仅设置 `needsDisplay = true` 有时不会触发 `MTKViewDelegate.draw(in:)`，
    ///   导致首次显示为空白。
    /// - `draw()` 可以强制触发一次 Metal draw pass；这里用 main queue coalesce，避免高频事件导致连环 draw。
    func requestRedraw() {
        // 标记脏区：必须调用 super，避免走我们自己的 `setNeedsDisplay` override 形成递归。
        super.setNeedsDisplay(bounds)
        scheduleDrawIfPossible()
    }

    func scheduleDrawIfPossible() {
        // 视图未挂到 window 时，强制 draw() 没意义；等 viewDidMoveToWindow / 下一次事件再 draw。
        guard window != nil else { return }

        guard drawScheduled == false else { return }
        drawScheduled = true
        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
            let delegateDesc = delegate.map { String(describing: type(of: $0)) } ?? "nil"
            NSLog(
                "EditorCoreSkiaView scheduleDraw: delegate=%@ paused=%d setNeeds=%d bounds(points)=%@ drawableSize(px)=%@",
                delegateDesc,
                isPaused ? 1 : 0,
                enableSetNeedsDisplay ? 1 : 0,
                NSStringFromSize(bounds.size),
                NSStringFromSize(drawableSize)
            )
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drawScheduled = false
            if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
                NSLog("EditorCoreSkiaView scheduleDraw: calling draw()")
            }
            // `MTKView.draw()` 在部分系统组合下不会触发 delegate（未知原因）。
            // 这里用 AppKit `displayIfNeeded()` 强制走 `draw(_:)`，而我们的 `draw(_:)` 会做 Metal render。
            self.displayIfNeeded()
        }
    }

    func gutterDiagnosticMarkerLayouts() -> [EditorCoreSkiaGutterDiagnosticMarkerLayout] {
        guard gutterDiagnosticMarkers.isEmpty == false else { return [] }
        guard bounds.width > 0, bounds.height > 0, gutterWidthCells > 0 else { return [] }

        let boundsSize = bounds.size
        let backingSize = convertToBacking(boundsSize)
        guard backingSize.width.isFinite, backingSize.height.isFinite,
              backingSize.width > 0, backingSize.height > 0
        else {
            return []
        }

        let sx = max(1e-6, backingSize.width / max(1e-6, boundsSize.width))
        let sy = max(1e-6, backingSize.height / max(1e-6, boundsSize.height))
        let gutterWidthPx = CGFloat(gutterWidthCells) * CGFloat(cellWidthPx)
        let glyphMarginWidthPx = min(max(CGFloat(cellWidthPx) * 1.5, 5), gutterWidthPx)
        let markerSizePx = max(5, min(CGFloat(lineHeightPx) * 0.52, CGFloat(cellWidthPx) * 0.85))
        let markerWidthPt = markerSizePx / sx
        let markerHeightPt = markerSizePx / sy
        let xPx = CGFloat(paddingPx) + max(0, (glyphMarginWidthPx - markerSizePx) * 0.5)
        let xPt = xPx / sx
        let viewport = try? editor.viewportState()

        return gutterDiagnosticMarkers.compactMap { marker in
            if let viewport, viewport.visibleLines.contains(marker.logicalLine) == false {
                return nil
            }
            guard let point = try? editor.charOffsetToViewPoint(offset: marker.charOffset) else {
                return nil
            }

            let yPx = CGFloat(point.yPx) + max(0, (CGFloat(point.lineHeightPx) - markerSizePx) * 0.5)
            let yPt = yPx / sy
            guard yPt.isFinite, yPt > -markerHeightPt, yPt < bounds.height + markerHeightPt else {
                return nil
            }

            return EditorCoreSkiaGutterDiagnosticMarkerLayout(
                marker: marker,
                rect: CGRect(
                    x: xPt,
                    y: yPt,
                    width: markerWidthPt,
                    height: markerHeightPt
                )
            )
        }
    }

    func renderToCurrentDrawable(debugSource: String) {
        guard let drawable = currentDrawable else {
            if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
                NSLog("EditorCoreSkiaView render(%@): drawable=nil", debugSource)
            }
            return
        }

        if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DEBUG_DRAW"] == "1" {
            let t = drawable.texture
            NSLog(
                "EditorCoreSkiaView render(%@): drawable=ok tex=%dx%d pf=%d usage=0x%X storage=%d",
                debugSource,
                t.width,
                t.height,
                t.pixelFormat.rawValue,
                t.usage.rawValue,
                t.storageMode.rawValue
            )
        }

        let t0 = perfDebugEnabled ? CFAbsoluteTimeGetCurrent() : 0
        do {
            try editor.renderMetal(into: drawable.texture)
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfRenderMetalCount += 1
                perfRenderMetalTotalMs += dtMs
                perfReportIfNeeded()
            }
        } catch {
            if perfDebugEnabled {
                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                perfRenderMetalCount += 1
                perfRenderMetalTotalMs += dtMs
                perfReportIfNeeded()
            }
            NSLog("EditorCoreSkiaView Metal render failed(%@): %@", debugSource, String(describing: error))
            return
        }

        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

        // 关键：在某些系统/驱动组合下，如果用“完全空的 command buffer”去 present，
        // 会出现“present 成功但屏幕仍是空白”的现象（即使 Skia 已经在更早的 command buffer 里写入了 drawable 的 texture）。
        //
        // 这里做一个极轻量的 no-op render pass：
        // - loadAction = .load：不清屏，保留 Skia 画进去的内容
        // - storeAction = .store：保证结果可用于后续 present
        //
        // 这样可以确保 present 所在的 command buffer 明确“使用了”这个 drawable 的 texture。
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if didPresentFirstFrame == false {
            didPresentFirstFrame = true
            enableSetNeedsDisplay = true
            isPaused = true
        }
    }
}
