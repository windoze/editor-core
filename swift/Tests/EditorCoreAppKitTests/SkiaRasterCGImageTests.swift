import CoreGraphics
import XCTest

@testable import EditorCoreAppKit

final class SkiaRasterCGImageTests: XCTestCase {
    func test_make_cgimage_and_draw_upright_in_flipped_context_preserves_rgba_and_orientation() throws {
        // 2x2 image (row 0 is top row).
        // Top row:    red, green
        // Bottom row: blue, white
        let width = 2
        let height = 2
        let inputRGBA: [UInt8] = [
            0xFF, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF,
            0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]

        let image: CGImage = inputRGBA.withUnsafeBytes { raw in
            SkiaRasterCGImage.makeCGImageRGBA8888Premul(
                widthPx: width,
                heightPx: height,
                rgbaBytes: raw.baseAddress!,
                byteCount: raw.count
            )!
        }

        var out = Array(repeating: UInt8(0), count: inputRGBA.count)
        let bytesPerRow = width * 4
        let outColorSpace = CGColorSpaceCreateDeviceRGB()
        let outBitmapInfo = SkiaRasterCGImage.bitmapInfo

        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress!,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: outColorSpace,
                bitmapInfo: outBitmapInfo.rawValue
            )!

            // Simulate a flipped NSView coordinate system (top-left origin, y grows downward).
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)

            SkiaRasterCGImage.drawCGImage(
                image,
                in: ctx,
                dstRect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                viewIsFlipped: true
            )
        }

        func pixel(_ buf: [UInt8], x: Int, y: Int) -> [UInt8] {
            let idx = (y * bytesPerRow) + x * 4
            return [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
        }

        XCTAssertEqual(pixel(out, x: 0, y: 0), [0xFF, 0x00, 0x00, 0xFF]) // top-left
        XCTAssertEqual(pixel(out, x: 1, y: 0), [0x00, 0xFF, 0x00, 0xFF]) // top-right
        XCTAssertEqual(pixel(out, x: 0, y: 1), [0x00, 0x00, 0xFF, 0xFF]) // bottom-left
        XCTAssertEqual(pixel(out, x: 1, y: 1), [0xFF, 0xFF, 0xFF, 0xFF]) // bottom-right
    }

    func test_destination_rect_scales_bounds_when_context_is_in_pixels() throws {
        let width = 10
        let height = 10
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = SkiaRasterCGImage.bitmapInfo

        var out = Array(repeating: UInt8(0), count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress!,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )!

            // Default bitmap contexts have ~1.0 scale in user space.
            let viewBounds = CGRect(x: 0, y: 0, width: 5, height: 5)
            let dst1 = SkiaRasterCGImage.destinationRectInCurrentContext(
                viewBounds: viewBounds,
                viewScaleFactor: 2,
                ctx: ctx
            )
            XCTAssertEqual(dst1.size.width, 10)
            XCTAssertEqual(dst1.size.height, 10)

            // Simulate a context already scaled to backing pixels (like a points-based context on Retina).
            ctx.saveGState()
            ctx.scaleBy(x: 2, y: 2)
            let dst2 = SkiaRasterCGImage.destinationRectInCurrentContext(
                viewBounds: viewBounds,
                viewScaleFactor: 2,
                ctx: ctx
            )
            ctx.restoreGState()

            XCTAssertEqual(dst2.size.width, 5)
            XCTAssertEqual(dst2.size.height, 5)
        }
    }
}
