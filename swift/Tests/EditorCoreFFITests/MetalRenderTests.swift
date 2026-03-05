import EditorCoreUIFFI
import Metal
import XCTest

final class MetalRenderTests: XCTestCase {
    func testMetalRenderFillsBackgroundInBGRA() throws {
        let library = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let editor = try EditorUI(library: library, initialText: "", viewportWidthCells: 80)

        // Use a non-trivial background color so we can verify channel order (BGRA8).
        let bg = EcuRgba8(r: 0x10, g: 0x20, b: 0x30, a: 0xFF)
        try editor.setTheme(
            EcuTheme(
                background: bg,
                foreground: bg,
                selectionBackground: bg,
                caret: bg
            )
        )
        try editor.setGutterWidthCells(0)
        try editor.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)

        let width: Int = 32
        let height: Int = 32
        try editor.setViewportPx(widthPx: UInt32(width), heightPx: UInt32(height), scale: 1.0)

        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device 不可用")
            return
        }
        guard let queue = device.makeCommandQueue() else {
            XCTFail("Metal command queue 不可用")
            return
        }

        try editor.enableMetal(device: device, commandQueue: queue)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget]
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else {
            XCTFail("创建 MTLTexture 失败")
            return
        }

        try editor.renderMetal(into: texture)

        // Important: Skia submits its own command buffer on the provided queue. To make the test
        // deterministic, we enqueue an empty command buffer on the same queue and wait for it.
        if let fence = queue.makeCommandBuffer() {
            fence.commit()
            fence.waitUntilCompleted()
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        // BGRA8Unorm memory order: [B, G, R, A].
        let expected: [UInt8] = [bg.b, bg.g, bg.r, bg.a]
        for p in stride(from: 0, to: bytes.count, by: 4) {
            XCTAssertEqual(Array(bytes[p..<(p + 4)]), expected)
        }
    }
}

