import AppKit
import Foundation

struct AttoVisualSnapshot: Equatable {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    @MainActor
    static func capture(view: NSView, scale: CGFloat = 1, forcedSize: NSSize? = nil) throws -> Self {
        view.layoutSubtreeIfNeeded()
        let bounds: NSRect
        if let forcedSize {
            bounds = NSRect(origin: .zero, size: forcedSize)
            view.bounds = bounds
        } else {
            bounds = view.bounds
        }
        let pixelWidth = max(1, Int((bounds.width * scale).rounded()))
        let pixelHeight = max(1, Int((bounds.height * scale).rounded()))

        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw AttoVisualSnapshotError.captureFailed("failed to create bitmap image rep")
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)

        let snapshot = try Self(rep: rep, width: pixelWidth, height: pixelHeight)
        return try AttoVisualSnapshotEditorRasterOverlay.compositeEditorRasters(
            in: view,
            rootSnapshot: snapshot,
            scale: scale
        )
    }

    static func readPNG(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        guard let rep = NSBitmapImageRep(data: data) else {
            throw AttoVisualSnapshotError.captureFailed("failed to decode PNG at \(url.path)")
        }
        return try Self(pngRep: rep)
    }

    func writePNG(to url: URL) throws {
        let pngData = try makePNGData()
        try pngData.write(to: url, options: .atomic)
    }

    func makePNGData() throws -> Data {
        guard rgba.count == width * height * 4 else {
            throw AttoVisualSnapshotError.invalidBuffer(
                "expected \(width * height * 4) RGBA bytes, got \(rgba.count)"
            )
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaNonpremultiplied],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ),
            let bitmapData = rep.bitmapData
        else {
            throw AttoVisualSnapshotError.captureFailed("failed to create PNG bitmap image rep")
        }

        rgba.withUnsafeBytes { source in
            guard let sourceBaseAddress = source.baseAddress else {
                return
            }
            UnsafeMutableRawPointer(bitmapData).copyMemory(
                from: sourceBaseAddress,
                byteCount: rgba.count
            )
        }

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw AttoVisualSnapshotError.captureFailed("failed to encode PNG")
        }
        return png
    }

    private static func rep(_ rep: NSBitmapImageRep, colorAtX x: Int, y: Int) -> NSColor {
        (rep.colorAt(x: x, y: y) ?? .clear).usingColorSpace(.deviceRGB) ?? .clear
    }

    private static func rawRGBAPixels(from rep: NSBitmapImageRep) -> [UInt8]? {
        guard rep.pixelsWide > 0,
              rep.pixelsHigh > 0,
              rep.bitsPerSample == 8,
              rep.samplesPerPixel == 4,
              rep.bitsPerPixel == 32,
              rep.hasAlpha,
              rep.isPlanar == false,
              rep.bytesPerRow >= rep.pixelsWide * 4,
              let bitmapData = rep.bitmapData
        else {
            return nil
        }

        let format = rep.bitmapFormat
        guard format.contains(.alphaFirst) == false,
              format.contains(.floatingPointSamples) == false,
              format.contains(.sixteenBitLittleEndian) == false,
              format.contains(.sixteenBitBigEndian) == false,
              format.contains(.thirtyTwoBitLittleEndian) == false,
              format.contains(.thirtyTwoBitBigEndian) == false
        else {
            return nil
        }

        var rgba = [UInt8]()
        rgba.reserveCapacity(rep.pixelsWide * rep.pixelsHigh * 4)
        for y in 0..<rep.pixelsHigh {
            let row = bitmapData.advanced(by: y * rep.bytesPerRow)
            for x in 0..<rep.pixelsWide {
                let pixel = row.advanced(by: x * 4)
                rgba.append(pixel[0])
                rgba.append(pixel[1])
                rgba.append(pixel[2])
                rgba.append(pixel[3])
            }
        }
        return rgba
    }

    private init(pngRep rep: NSBitmapImageRep) throws {
        if let rgba = Self.rawRGBAPixels(from: rep) {
            self.init(width: rep.pixelsWide, height: rep.pixelsHigh, rgba: rgba)
            return
        }

        try self.init(rep: rep, width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    private init(rep: NSBitmapImageRep, width: Int, height: Int) throws {
        guard rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            throw AttoVisualSnapshotError.captureFailed("bitmap image rep has no pixels")
        }

        var rgba = [UInt8]()
        rgba.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let sampleX = min(rep.pixelsWide - 1, max(0, x * rep.pixelsWide / width))
                let sampleY = min(rep.pixelsHigh - 1, max(0, y * rep.pixelsHigh / height))
                let color = Self.rep(rep, colorAtX: sampleX, y: sampleY)
                rgba.append(UInt8(clamping: Int((color.redComponent * 255).rounded())))
                rgba.append(UInt8(clamping: Int((color.greenComponent * 255).rounded())))
                rgba.append(UInt8(clamping: Int((color.blueComponent * 255).rounded())))
                rgba.append(UInt8(clamping: Int((color.alphaComponent * 255).rounded())))
            }
        }

        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

struct AttoVisualSnapshotComparison: Equatable {
    let passed: Bool
    let differentPixels: Int
    let totalPixels: Int
    let maxChannelDelta: Int
    let differentPixelRatio: Double
}

enum AttoVisualSnapshotHarness {
    static func compare(
        actual: AttoVisualSnapshot,
        expected: AttoVisualSnapshot,
        artifactDirectory: URL,
        name: String,
        perChannelTolerance: UInt8 = 0,
        maxDifferentPixelRatio: Double = 0
    ) throws -> AttoVisualSnapshotComparison {
        guard actual.width == expected.width, actual.height == expected.height else {
            try writeArtifacts(
                actual: actual,
                expected: expected,
                diff: nil,
                artifactDirectory: artifactDirectory,
                name: name
            )
            throw AttoVisualSnapshotError.sizeMismatch(
                "actual \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)"
            )
        }
        guard actual.rgba.count == expected.rgba.count else {
            throw AttoVisualSnapshotError.invalidBuffer("actual/expected RGBA buffer lengths differ")
        }

        var differentPixels = 0
        var maxChannelDelta = 0
        var diffRgba = [UInt8](repeating: 0, count: actual.rgba.count)
        let tolerance = Int(perChannelTolerance)

        for pixel in 0..<(actual.width * actual.height) {
            let offset = pixel * 4
            var pixelDifferent = false
            for channel in 0..<4 {
                let delta = abs(Int(actual.rgba[offset + channel]) - Int(expected.rgba[offset + channel]))
                maxChannelDelta = max(maxChannelDelta, delta)
                if delta > tolerance {
                    pixelDifferent = true
                }
            }

            if pixelDifferent {
                differentPixels += 1
                diffRgba[offset + 0] = 255
                diffRgba[offset + 1] = 0
                diffRgba[offset + 2] = 0
                diffRgba[offset + 3] = 255
            } else {
                diffRgba[offset + 0] = 0
                diffRgba[offset + 1] = 0
                diffRgba[offset + 2] = 0
                diffRgba[offset + 3] = 255
            }
        }

        let totalPixels = actual.width * actual.height
        let ratio = totalPixels == 0 ? 0 : Double(differentPixels) / Double(totalPixels)
        let passed = ratio <= maxDifferentPixelRatio
        if !passed {
            try writeArtifacts(
                actual: actual,
                expected: expected,
                diff: AttoVisualSnapshot(width: actual.width, height: actual.height, rgba: diffRgba),
                artifactDirectory: artifactDirectory,
                name: name
            )
        }

        return AttoVisualSnapshotComparison(
            passed: passed,
            differentPixels: differentPixels,
            totalPixels: totalPixels,
            maxChannelDelta: maxChannelDelta,
            differentPixelRatio: ratio
        )
    }

    private static func writeArtifacts(
        actual: AttoVisualSnapshot,
        expected: AttoVisualSnapshot,
        diff: AttoVisualSnapshot?,
        artifactDirectory: URL,
        name: String
    ) throws {
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        try actual.writePNG(to: artifactDirectory.appendingPathComponent("\(name)-actual.png"))
        try expected.writePNG(to: artifactDirectory.appendingPathComponent("\(name)-expected.png"))
        if let diff {
            try diff.writePNG(to: artifactDirectory.appendingPathComponent("\(name)-diff.png"))
        }
    }
}

enum AttoVisualSnapshotError: Error, CustomStringConvertible {
    case captureFailed(String)
    case invalidBuffer(String)
    case sizeMismatch(String)

    var description: String {
        switch self {
        case let .captureFailed(message),
             let .invalidBuffer(message),
             let .sizeMismatch(message):
            return message
        }
    }
}
