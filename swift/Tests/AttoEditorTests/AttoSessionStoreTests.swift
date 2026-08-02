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
        let tab = try XCTUnwrap(snapshot.windows.first?.tabs.first)

        XCTAssertEqual(tab.paneCount, 2)
        XCTAssertEqual(tab.activePaneIndex, 1)
        XCTAssertNil(tab.paneLayout)
    }
}
