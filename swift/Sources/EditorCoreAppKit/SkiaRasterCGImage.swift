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
}

