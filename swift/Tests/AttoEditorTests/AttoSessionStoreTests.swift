@testable import AttoEditor
import Foundation
import XCTest

final class AttoSessionStoreTests: XCTestCase {
    func testLoadAcceptsLegacyTabSnapshotWithoutPaneLayout() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionURL = tempDir.appendingPathComponent("session.json")
        let filePath = tempDir.appendingPathComponent("legacy.txt").path
        let json = """
        {
          "activeWindowIndex": 0,
          "savedAt": "2026-08-03T00:00:00Z",
          "schemaVersion": 1,
          "windows": [
            {
              "frame": null,
              "recentFilePaths": [],
              "selectedTabIndex": 0,
              "sidebarCollapsed": false,
              "tabs": [
                {
                  "activePaneIndex": 1,
                  "filePath": "\(filePath)",
                  "isPreview": false,
                  "paneCount": 2,
                  "showsMinimap": true
                }
              ],
              "workspaceRootPath": "\(tempDir.path)"
            }
          ]
        }
        """
        try json.write(to: sessionURL, atomically: true, encoding: .utf8)

        let store = AttoSessionStore(sessionFileURL: sessionURL)
        let snapshot = try XCTUnwrap(store.load())
        let window = try XCTUnwrap(snapshot.windows.first)
        let tab = try XCTUnwrap(window.tabs.first)

        XCTAssertTrue(snapshot.recentProjectURIs.isEmpty)
        XCTAssertNil(window.workspaceRootURI)
        XCTAssertEqual(window.validatedWorkspaceRootURL()?.standardizedFileURL, tempDir.standardizedFileURL)
        XCTAssertEqual(tab.paneCount, 2)
        XCTAssertEqual(tab.activePaneIndex, 1)
        XCTAssertNil(tab.paneLayout)
        XCTAssertNil(tab.isUntitled)
        XCTAssertNil(tab.unsavedText)
    }

    func testWindowSnapshotWorkspaceRootURLPrefersURIOverLegacyPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        let uriRoot = tempDir.appendingPathComponent("uri-root", isDirectory: true)
        let legacyRoot = tempDir.appendingPathComponent("legacy-root", isDirectory: true)
        try FileManager.default.createDirectory(at: uriRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = AttoWindowSnapshot(
            workspaceRootPath: legacyRoot.path,
            workspaceRootURI: uriRoot.standardizedFileURL.absoluteString,
            frame: nil,
            sidebarCollapsed: false,
            selectedTabIndex: nil,
            tabs: [],
            recentFilePaths: []
        )

        XCTAssertEqual(snapshot.validatedWorkspaceRootURL()?.standardizedFileURL, uriRoot.standardizedFileURL)
    }

    func testSessionSnapshotRoundTripsRecentProjectURIs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        let projectRoot = tempDir.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionURL = tempDir.appendingPathComponent("session.json")
        let store = AttoSessionStore(sessionFileURL: sessionURL)
        let snapshot = AttoSessionSnapshot(
            schemaVersion: AttoSessionSnapshot.currentSchemaVersion,
            savedAt: Date(timeIntervalSince1970: 1_785_787_200),
            activeWindowIndex: nil,
            recentProjectURIs: [projectRoot.standardizedFileURL.absoluteString],
            windows: []
        )

        try store.save(snapshot)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.recentProjectURIs, [projectRoot.standardizedFileURL.absoluteString])
    }

    func testSessionSnapshotRoundTripsUntitledTabText() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionURL = tempDir.appendingPathComponent("session.json")
        let untitledURL = tempDir.appendingPathComponent("untitled-1.txt")
        let store = AttoSessionStore(sessionFileURL: sessionURL)
        let snapshot = AttoSessionSnapshot(
            schemaVersion: AttoSessionSnapshot.currentSchemaVersion,
            savedAt: Date(timeIntervalSince1970: 1_785_787_200),
            activeWindowIndex: 0,
            windows: [
                AttoWindowSnapshot(
                    workspaceRootPath: tempDir.path,
                    workspaceRootURI: tempDir.standardizedFileURL.absoluteString,
                    frame: nil,
                    sidebarCollapsed: false,
                    selectedTabIndex: 0,
                    tabs: [
                        AttoTabSnapshot(
                            filePath: untitledURL.path,
                            isPreview: false,
                            showsMinimap: true,
                            paneCount: 1,
                            activePaneIndex: 0,
                            paneLayout: nil,
                            isUntitled: true,
                            unsavedText: "draft text\n"
                        ),
                    ],
                    recentFilePaths: []
                ),
            ]
        )

        try store.save(snapshot)
        let loaded = try XCTUnwrap(store.load())
        let tab = try XCTUnwrap(loaded.windows.first?.tabs.first)
        XCTAssertEqual(tab.isUntitled, true)
        XCTAssertEqual(tab.unsavedText, "draft text\n")
    }
}
