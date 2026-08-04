import AppKit
import EditorCoreUI
import Foundation

@MainActor
enum AttoVisualSnapshotEditorRasterOverlay {
    static func compositeEditorRasters(
        in rootView: NSView,
        rootSnapshot: AttoVisualSnapshot,
        scale: CGFloat
    ) throws -> AttoVisualSnapshot {
        let overlays = try editorViews(in: rootView).compactMap { editorView in
            try makeOverlay(for: editorView, in: rootView, scale: scale)
        }
        guard overlays.isEmpty == false else { return rootSnapshot }

        var rgba = rootSnapshot.rgba
        for overlay in overlays {
            composite(overlay, into: &rgba, rootWidth: rootSnapshot.width, rootHeight: rootSnapshot.height)
        }
        return AttoVisualSnapshot(width: rootSnapshot.width, height: rootSnapshot.height, rgba: rgba)
    }

    private static func editorViews(in view: NSView) -> [EditorCoreSkiaView] {
        var out: [EditorCoreSkiaView] = []
        if let editorView = view as? EditorCoreSkiaView {
            out.append(editorView)
        }
        for subview in view.subviews {
            out.append(contentsOf: editorViews(in: subview))
        }
        return out
    }

    private static func makeOverlay(
        for editorView: EditorCoreSkiaView,
        in rootView: NSView,
        scale: CGFloat
    ) throws -> RasterOverlay? {
        guard editorView.bounds.width > 0, editorView.bounds.height > 0 else { return nil }

        editorView.layoutSubtreeIfNeeded()
        var rgba: [UInt8] = []
        let renderedCount = try editorView.editor.renderRGBA(into: &rgba)
        guard renderedCount == rgba.count,
              renderedCount >= 4,
              renderedCount % 4 == 0
        else {
            return nil
        }

        let backingSize = editorView.convertToBacking(editorView.bounds.size)
        let sourceWidth = Int(backingSize.width.rounded())
        guard sourceWidth > 0 else { return nil }

        let pixelCount = renderedCount / 4
        guard pixelCount % sourceWidth == 0 else { return nil }
        let sourceHeight = pixelCount / sourceWidth
        guard sourceHeight > 0 else { return nil }

        let rect = editorView.convert(editorView.bounds, to: rootView)
        let destRect = destinationPixelRect(for: rect, in: rootView, scale: scale)
        guard destRect.width > 0, destRect.height > 0 else { return nil }

        return RasterOverlay(
            rgba: rgba,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            backgroundColors: backgroundColors(from: rgba, width: sourceWidth, height: sourceHeight),
            destX: destRect.x,
            destY: destRect.y,
            destWidth: destRect.width,
            destHeight: destRect.height
        )
    }

    private static func destinationPixelRect(
        for rect: NSRect,
        in rootView: NSView,
        scale: CGFloat
    ) -> PixelRect {
        let rootBounds = rootView.bounds
        let x = Int(((rect.minX - rootBounds.minX) * scale).rounded())
        let y: Int
        if rootView.isFlipped {
            y = Int(((rect.minY - rootBounds.minY) * scale).rounded())
        } else {
            y = Int(((rootBounds.maxY - rect.maxY) * scale).rounded())
        }

        return PixelRect(
            x: x,
            y: y,
            width: Int((rect.width * scale).rounded()),
            height: Int((rect.height * scale).rounded())
        )
    }

    private static func composite(
        _ overlay: RasterOverlay,
        into rootRGBA: inout [UInt8],
        rootWidth: Int,
        rootHeight: Int
    ) {
        let startX = max(0, overlay.destX)
        let startY = max(0, overlay.destY)
        let endX = min(rootWidth, overlay.destX + overlay.destWidth)
        let endY = min(rootHeight, overlay.destY + overlay.destHeight)
        guard startX < endX, startY < endY else { return }

        for y in startY..<endY {
            let localY = y - overlay.destY
            let sourceY = min(overlay.sourceHeight - 1, localY * overlay.sourceHeight / overlay.destHeight)
            for x in startX..<endX {
                let localX = x - overlay.destX
                let sourceX = min(overlay.sourceWidth - 1, localX * overlay.sourceWidth / overlay.destWidth)
                let sourceOffset = (sourceY * overlay.sourceWidth + sourceX) * 4
                let destOffset = (y * rootWidth + x) * 4
                if overlay.isBackgroundPixel(at: sourceOffset) {
                    continue
                }
                copyPixel(from: overlay.rgba, sourceOffset: sourceOffset, into: &rootRGBA, destOffset: destOffset)
            }
        }
    }

    private static func backgroundColors(from rgba: [UInt8], width: Int, height: Int) -> Set<RGBAColor> {
        guard width > 0, height > 0 else { return [] }

        let samplePoints = [
            (0, height - 1),
            (max(0, width / 2), height - 1),
            (width - 1, height - 1),
            (width - 1, max(0, height / 2)),
        ]
        return Set(samplePoints.compactMap { x, y in
            let offset = (y * width + x) * 4
            guard offset + 3 < rgba.count else { return nil }
            return RGBAColor(
                r: rgba[offset + 0],
                g: rgba[offset + 1],
                b: rgba[offset + 2],
                a: rgba[offset + 3]
            )
        })
    }

    private static func copyPixel(
        from sourceRGBA: [UInt8],
        sourceOffset: Int,
        into destRGBA: inout [UInt8],
        destOffset: Int
    ) {
        let alpha = sourceRGBA[sourceOffset + 3]
        if alpha == 255 {
            destRGBA[destOffset + 0] = sourceRGBA[sourceOffset + 0]
            destRGBA[destOffset + 1] = sourceRGBA[sourceOffset + 1]
            destRGBA[destOffset + 2] = sourceRGBA[sourceOffset + 2]
            destRGBA[destOffset + 3] = 255
            return
        }
        guard alpha > 0 else { return }

        let sourceAlpha = Double(alpha) / 255.0
        let destAlpha = Double(destRGBA[destOffset + 3]) / 255.0
        let outAlpha = sourceAlpha + destAlpha * (1.0 - sourceAlpha)
        guard outAlpha > 0 else { return }

        for channel in 0..<3 {
            let source = Double(sourceRGBA[sourceOffset + channel]) / 255.0
            let dest = Double(destRGBA[destOffset + channel]) / 255.0
            let out = (source * sourceAlpha + dest * destAlpha * (1.0 - sourceAlpha)) / outAlpha
            destRGBA[destOffset + channel] = UInt8(clamping: Int((out * 255.0).rounded()))
        }
        destRGBA[destOffset + 3] = UInt8(clamping: Int((outAlpha * 255.0).rounded()))
    }
}

private struct RasterOverlay {
    let rgba: [UInt8]
    let sourceWidth: Int
    let sourceHeight: Int
    let backgroundColors: Set<RGBAColor>
    let destX: Int
    let destY: Int
    let destWidth: Int
    let destHeight: Int

    func isBackgroundPixel(at offset: Int) -> Bool {
        guard offset + 3 < rgba.count else { return false }
        return backgroundColors.contains(RGBAColor(
            r: rgba[offset + 0],
            g: rgba[offset + 1],
            b: rgba[offset + 2],
            a: rgba[offset + 3]
        ))
    }
}

private struct PixelRect {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private struct RGBAColor: Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}
