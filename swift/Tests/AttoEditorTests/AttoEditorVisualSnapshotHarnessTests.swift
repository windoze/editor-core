import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorVisualSnapshotHarnessTests: XCTestCase {
    func testSnapshotHarnessCapturesEditorChromeAndWritesPngArtifact() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("snapshot.txt")
        try "alpha\nbeta\ngamma\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: tempDir
        )
        let window = attachToWindow(vc, size: NSSize(width: 640, height: 420))
        defer { window.close() }

        XCTAssertTrue(vc.openFile(url: fileURL, mode: .pinned, location: nil))
        vc.showFindBar()
        vc.view.layoutSubtreeIfNeeded()

        let snapshot = try AttoVisualSnapshot.capture(view: vc.view, scale: 1)
        XCTAssertEqual(snapshot.width, 640)
        XCTAssertEqual(snapshot.height, 420)
        XCTAssertGreaterThan(snapshot.rgba.count, 640 * 420 * 3)

        let artifactURL = tempDir.appendingPathComponent("editor-chrome.png")
        try snapshot.writePNG(to: artifactURL)
        let png = try Data(contentsOf: artifactURL)
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        let comparison = try AttoVisualSnapshotHarness.compare(
            actual: snapshot,
            expected: snapshot,
            artifactDirectory: tempDir,
            name: "matching-editor-chrome"
        )
        XCTAssertTrue(comparison.passed)
        XCTAssertEqual(comparison.differentPixels, 0)
    }

    func testSnapshotHarnessWritesDiffArtifactsForMismatches() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expected = AttoVisualSnapshot(
            width: 2,
            height: 2,
            rgba: [
                0, 0, 0, 255,
                10, 10, 10, 255,
                20, 20, 20, 255,
                30, 30, 30, 255,
            ]
        )
        let actual = AttoVisualSnapshot(
            width: 2,
            height: 2,
            rgba: [
                0, 0, 0, 255,
                10, 10, 10, 255,
                255, 0, 0, 255,
                30, 30, 30, 255,
            ]
        )

        let comparison = try AttoVisualSnapshotHarness.compare(
            actual: actual,
            expected: expected,
            artifactDirectory: tempDir,
            name: "intentional-mismatch",
            perChannelTolerance: 0,
            maxDifferentPixelRatio: 0
        )

        XCTAssertFalse(comparison.passed)
        XCTAssertEqual(comparison.differentPixels, 1)
        XCTAssertEqual(comparison.totalPixels, 4)
        XCTAssertEqual(comparison.maxChannelDelta, 235)

        for suffix in ["actual", "expected", "diff"] {
            let url = tempDir.appendingPathComponent("intentional-mismatch-\(suffix).png")
            let data = try Data(contentsOf: url)
            XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "\(url.path) is not a PNG")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorVisualSnapshotHarnessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func attachToWindow(
        _ vc: AttoEditorAreaViewController,
        size: NSSize
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.setContentSize(size)
        vc.view.frame = NSRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }
}

private struct AttoVisualSnapshot: Equatable {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    @MainActor
    static func capture(view: NSView, scale: CGFloat = 1) throws -> Self {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let pixelWidth = max(1, Int((bounds.width * scale).rounded()))
        let pixelHeight = max(1, Int((bounds.height * scale).rounded()))

        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw AttoVisualSnapshotError.captureFailed("failed to create bitmap image rep")
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)

        var rgba = [UInt8]()
        rgba.reserveCapacity(pixelWidth * pixelHeight * 4)
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let sampleX = min(rep.pixelsWide - 1, max(0, x * rep.pixelsWide / pixelWidth))
                let sampleY = min(rep.pixelsHigh - 1, max(0, y * rep.pixelsHigh / pixelHeight))
                let color = (rep.colorAt(x: sampleX, y: sampleY) ?? .clear)
                    .usingColorSpace(.deviceRGB) ?? .clear
                rgba.append(UInt8(clamping: Int((color.redComponent * 255).rounded())))
                rgba.append(UInt8(clamping: Int((color.greenComponent * 255).rounded())))
                rgba.append(UInt8(clamping: Int((color.blueComponent * 255).rounded())))
                rgba.append(UInt8(clamping: Int((color.alphaComponent * 255).rounded())))
            }
        }

        return Self(width: pixelWidth, height: pixelHeight, rgba: rgba)
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
}

private struct AttoVisualSnapshotComparison: Equatable {
    let passed: Bool
    let differentPixels: Int
    let totalPixels: Int
    let maxChannelDelta: Int
    let differentPixelRatio: Double
}

private enum AttoVisualSnapshotHarness {
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

private enum AttoVisualSnapshotError: Error, CustomStringConvertible {
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
