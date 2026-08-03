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
