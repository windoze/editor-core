import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorVisualBaselineManifestTests: XCTestCase {
    func testVisualBaselineManifestDeclaresRunnableFixtures() throws {
        let manifest = try AttoVisualBaselineManifest.load()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertFalse(manifest.cases.isEmpty)
        XCTAssertEqual(Set(manifest.cases.map(\.id)).count, manifest.cases.count)
        XCTAssertEqual(Set(manifest.cases.map(\.artifactName)).count, manifest.cases.count)
        XCTAssertEqual(Set(manifest.cases.map(\.baseline)).count, manifest.cases.count)

        for visualCase in manifest.cases {
            XCTAssertFalse(visualCase.id.isEmpty)
            XCTAssertNotNil(
                visualCase.artifactName.range(
                    of: #"^[a-z0-9][a-z0-9-]*$"#,
                    options: .regularExpression
                )
            )
            XCTAssertGreaterThan(visualCase.window.width, 0)
            XCTAssertGreaterThan(visualCase.window.height, 0)
            XCTAssertGreaterThan(visualCase.scale, 0)
            XCTAssertGreaterThanOrEqual(visualCase.maxDifferentPixelRatio, 0)
            XCTAssertLessThanOrEqual(visualCase.maxDifferentPixelRatio, 1)
            XCTAssertTrue(visualCase.baseline.hasSuffix(".png"))
            XCTAssertTrue(visualCase.showReplaceBar == false || visualCase.showFindBar)

            for fixture in visualCase.allFixturePaths {
                let fixtureURL = try visualCase.fixtureURL(path: fixture)
                XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))
            }
            if let activeFixture = visualCase.activeFixture {
                XCTAssertTrue(visualCase.allFixturePaths.contains(activeFixture))
            }
            _ = try visualCase.makeTheme()
        }
    }

    func testVisualBaselineFixturesCaptureReviewArtifactsAndCanCompareExternalBaselines() throws {
        let manifest = try AttoVisualBaselineManifest.load()
        for visualCase in manifest.cases {
            try runVisualBaselineCase(visualCase)
        }
    }

    private func runVisualBaselineCase(_ visualCase: AttoVisualBaselineCase) throws {
        let tempDir = try makeTemporaryDirectory(caseID: visualCase.id)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let documentURLs = try materializeFixtures(for: visualCase, in: tempDir)
        let primaryDocumentURL = try XCTUnwrap(documentURLs[visualCase.fixture])

        let vc = AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: try visualCase.makeTheme(),
            workspaceRootURL: tempDir
        )
        let window = attachToWindow(vc, size: visualCase.window.nsSize)
        defer { window.close() }

        XCTAssertTrue(
            vc.openFile(url: primaryDocumentURL, mode: AttoEditorAreaViewController.OpenMode.pinned),
            visualCase.id
        )
        for fixture in visualCase.additionalFixtures {
            let url = try XCTUnwrap(documentURLs[fixture])
            XCTAssertTrue(vc.openFile(url: url, mode: AttoEditorAreaViewController.OpenMode.pinned), visualCase.id)
        }
        if let activeFixture = visualCase.activeFixture {
            let url = try XCTUnwrap(documentURLs[activeFixture])
            XCTAssertTrue(vc.openFile(url: url, mode: AttoEditorAreaViewController.OpenMode.pinned), visualCase.id)
        }
        if visualCase.splitActiveTabRight {
            XCTAssertTrue(vc.splitActiveTabRight(), visualCase.id)
        }
        if visualCase.showReplaceBar {
            vc.showReplaceBar()
        } else if visualCase.showFindBar {
            vc.showFindBar()
        }
        vc.view.layoutSubtreeIfNeeded()

        let snapshot = try AttoVisualSnapshot.capture(view: vc.view, scale: CGFloat(visualCase.scale))
        XCTAssertEqual(snapshot.width, visualCase.window.width, visualCase.id)
        XCTAssertEqual(snapshot.height, visualCase.window.height, visualCase.id)

        let artifactDirectory = try visualArtifactDirectory(fallbackRoot: tempDir)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let actualArtifact = artifactDirectory.appendingPathComponent("\(visualCase.artifactName)-actual.png")
        try snapshot.writePNG(to: actualArtifact)
        XCTAssertTrue(try Data(contentsOf: actualArtifact).starts(with: [0x89, 0x50, 0x4E, 0x47]), visualCase.id)

        if let recordRoot = try recordBaselineRootURL() {
            let baselineURL = recordRoot.appendingPathComponent(visualCase.baseline)
            try FileManager.default.createDirectory(
                at: baselineURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try snapshot.writePNG(to: baselineURL)
            XCTAssertTrue(try Data(contentsOf: baselineURL).starts(with: [0x89, 0x50, 0x4E, 0x47]), visualCase.id)
        }

        guard let baselineRoot = externalBaselineRootURL() else {
            return
        }

        let expected = try AttoVisualSnapshot.readPNG(from: baselineRoot.appendingPathComponent(visualCase.baseline))
        let comparison = try AttoVisualSnapshotHarness.compare(
            actual: snapshot,
            expected: expected,
            artifactDirectory: artifactDirectory,
            name: visualCase.artifactName,
            perChannelTolerance: visualCase.perChannelTolerance,
            maxDifferentPixelRatio: visualCase.maxDifferentPixelRatio
        )
        XCTAssertTrue(
            comparison.passed,
            """
            visual baseline mismatch for \(visualCase.id): \
            \(comparison.differentPixels)/\(comparison.totalPixels) pixels differ, \
            max channel delta \(comparison.maxChannelDelta), artifacts: \(artifactDirectory.path)
            """
        )
    }

    private func materializeFixtures(
        for visualCase: AttoVisualBaselineCase,
        in tempDir: URL
    ) throws -> [String: URL] {
        var documentURLs: [String: URL] = [:]
        for fixture in visualCase.allFixturePaths {
            let fixtureURL = try visualCase.fixtureURL(path: fixture)
            let documentURL = tempDir.appendingPathComponent(fixtureURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: documentURL.path) {
                try FileManager.default.removeItem(at: documentURL)
            }
            try FileManager.default.copyItem(at: fixtureURL, to: documentURL)
            documentURLs[fixture] = documentURL
        }
        return documentURLs
    }

    private func makeTemporaryDirectory(caseID: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AttoEditorVisualBaselineManifestTests-\(caseID)-\(UUID().uuidString)",
                isDirectory: true
            )
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

    private func visualArtifactDirectory(fallbackRoot: URL) throws -> URL {
        if let configured = nonEmptyEnvironmentURL("ATTO_VISUAL_ARTIFACT_DIR") {
            return configured
        }
        if let configured = try runtimeConfig()?.artifactRootURL {
            return configured
        }
        return fallbackRoot.appendingPathComponent("visual-artifacts", isDirectory: true)
    }

    private func externalBaselineRootURL() -> URL? {
        nonEmptyEnvironmentURL("ATTO_VISUAL_BASELINE_DIR")
    }

    private func recordBaselineRootURL() throws -> URL? {
        if let configured = nonEmptyEnvironmentURL("ATTO_VISUAL_RECORD_BASELINE_DIR") {
            return configured
        }
        return try runtimeConfig()?.recordBaselineRootURL
    }

    private func nonEmptyEnvironmentURL(_ key: String) -> URL? {
        guard let path = ProcessInfo.processInfo.environment[key], path.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func runtimeConfig() throws -> AttoVisualRuntimeConfig? {
        let explicitConfigURL = ProcessInfo.processInfo.environment["ATTO_VISUAL_BASELINE_CONFIG"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let defaultConfigURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/atto-visual-baseline-record.json")

        for configURL in [explicitConfigURL, defaultConfigURL].compactMap({ $0 }) {
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                continue
            }
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(AttoVisualRuntimeConfig.self, from: data)
        }
        return nil
    }
}

private struct AttoVisualRuntimeConfig: Decodable {
    let recordBaselineRoot: String?
    let artifactRoot: String?

    var recordBaselineRootURL: URL? {
        nonEmptyURL(recordBaselineRoot)
    }

    var artifactRootURL: URL? {
        nonEmptyURL(artifactRoot)
    }

    private func nonEmptyURL(_ path: String?) -> URL? {
        guard let path, path.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

private struct AttoVisualBaselineManifest: Decodable {
    let schemaVersion: Int
    let cases: [AttoVisualBaselineCase]

    static func load() throws -> Self {
        let url = try resourceURL(path: "VisualBaselines/manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

private struct AttoVisualBaselineCase: Decodable, Equatable {
    let id: String
    let description: String
    let fixture: String
    let baseline: String
    let artifactName: String
    let themeName: String
    let window: AttoVisualBaselineWindow
    let scale: Double
    let additionalFixtures: [String]
    let activeFixture: String?
    let showFindBar: Bool
    let showReplaceBar: Bool
    let splitActiveTabRight: Bool
    let perChannelTolerance: UInt8
    let maxDifferentPixelRatio: Double

    var allFixturePaths: [String] {
        [fixture] + additionalFixtures
    }

    func fixtureURL(path: String) throws -> URL {
        try resourceURL(path: path)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case fixture
        case baseline
        case artifactName
        case themeName = "theme"
        case window
        case scale
        case additionalFixtures
        case activeFixture
        case showFindBar
        case showReplaceBar
        case splitActiveTabRight
        case perChannelTolerance
        case maxDifferentPixelRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        fixture = try container.decode(String.self, forKey: .fixture)
        baseline = try container.decode(String.self, forKey: .baseline)
        artifactName = try container.decode(String.self, forKey: .artifactName)
        themeName = try container.decode(String.self, forKey: .themeName)
        window = try container.decode(AttoVisualBaselineWindow.self, forKey: .window)
        scale = try container.decode(Double.self, forKey: .scale)
        additionalFixtures = try container.decodeIfPresent([String].self, forKey: .additionalFixtures) ?? []
        activeFixture = try container.decodeIfPresent(String.self, forKey: .activeFixture)
        showFindBar = try container.decodeIfPresent(Bool.self, forKey: .showFindBar) ?? false
        showReplaceBar = try container.decodeIfPresent(Bool.self, forKey: .showReplaceBar) ?? false
        splitActiveTabRight = try container.decodeIfPresent(Bool.self, forKey: .splitActiveTabRight) ?? false
        perChannelTolerance = try container.decode(UInt8.self, forKey: .perChannelTolerance)
        maxDifferentPixelRatio = try container.decode(Double.self, forKey: .maxDifferentPixelRatio)
    }

    func makeTheme() throws -> EditorCoreSkiaTheme {
        switch themeName {
        case "defaultLight":
            return EditorCoreSkiaTheme.defaultLight()
        case "demoRustLspDark":
            return EditorCoreSkiaTheme.demoRustLspDark()
        default:
            throw AttoVisualBaselineError.invalidManifest("unsupported visual baseline theme: \(themeName)")
        }
    }
}

private struct AttoVisualBaselineWindow: Decodable, Equatable {
    let width: Int
    let height: Int

    var nsSize: NSSize {
        NSSize(width: width, height: height)
    }
}

private enum AttoVisualBaselineError: Error, CustomStringConvertible {
    case invalidManifest(String)
    case missingResource(String)

    var description: String {
        switch self {
        case let .invalidManifest(message),
             let .missingResource(message):
            return message
        }
    }
}

private func resourceURL(path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    let fileName = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
    let directory = url.deletingLastPathComponent().relativePath
    let subdirectory = directory == "." ? nil : directory

    if let resource = Bundle.module.url(
        forResource: fileName,
        withExtension: ext,
        subdirectory: subdirectory
    ) {
        return resource
    }
    if let resource = Bundle.module.url(forResource: fileName, withExtension: ext) {
        return resource
    }

    throw AttoVisualBaselineError.missingResource("missing test resource: \(path)")
}
