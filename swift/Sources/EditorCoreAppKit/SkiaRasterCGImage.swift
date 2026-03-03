import CoreGraphics
import Foundation

enum SkiaRasterCGImage {
    static let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    static let bitmapInfo: CGBitmapInfo = CGBitmapInfo.byteOrder32Big.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )

    /// Create a `CGImage` that *views* a caller-owned RGBA8888 premultiplied buffer.
    ///
    /// Important:
    /// - `rgbaBytes` must stay alive for as long as the returned `CGImage` is used.
    /// - The buffer is interpreted as top-to-bottom rows (row 0 is the top row).
    static func makeCGImageRGBA8888Premul(
        widthPx: Int,
        heightPx: Int,
        rgbaBytes: UnsafeRawPointer,
        byteCount: Int
    ) -> CGImage? {
        guard widthPx > 0, heightPx > 0 else { return nil }
        let bytesPerRow = widthPx * 4
        guard byteCount >= bytesPerRow * heightPx else { return nil }

        let data = NSData(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: rgbaBytes),
            length: bytesPerRow * heightPx,
            freeWhenDone: false
        )
        guard let provider = CGDataProvider(data: data) else { return nil }

        return CGImage(
            width: widthPx,
            height: heightPx,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Draw a `CGImage` into a destination rect, handling flipped (top-left origin) view coords.
    ///
    /// Notes:
    /// - In a flipped `NSView`, the `CGContext` is typically flipped as well, and drawing a `CGImage`
    ///   naively can end up vertically inverted. This helper applies the standard flip transform
    ///   so that the raster buffer (top row first) appears upright.
    static func drawCGImage(
        _ image: CGImage,
        in ctx: CGContext,
        dstRect: CGRect,
        viewIsFlipped: Bool
    ) {
        if viewIsFlipped {
            ctx.saveGState()
            ctx.translateBy(x: dstRect.minX, y: dstRect.minY + dstRect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: dstRect.width, height: dstRect.height))
            ctx.restoreGState()
        } else {
            ctx.draw(image, in: dstRect)
        }
    }

    /// Convert a view's logical bounds (points) into the destination rect in the current context's
    /// user space, so that an RGBA buffer sized using `viewScaleFactor` draws 1:1 without implicit
    /// downsampling when the context is already in backing pixels.
    static func destinationRectInCurrentContext(
        viewBounds: CGRect,
        viewScaleFactor: CGFloat,
        ctx: CGContext
    ) -> CGRect {
        let sx = abs(ctx.ctm.a)
        let sy = abs(ctx.ctm.d)

        // If the context is already in points, `sx/sy` should be close to `viewScaleFactor`.
        // If the context is in pixels, `sx/sy` will be ~1.0.
        let rx = sx > 0 ? (viewScaleFactor / sx) : viewScaleFactor
        let ry = sy > 0 ? (viewScaleFactor / sy) : viewScaleFactor

        return CGRect(
            x: viewBounds.origin.x * rx,
            y: viewBounds.origin.y * ry,
            width: viewBounds.size.width * rx,
            height: viewBounds.size.height * ry
        )
    }
}
