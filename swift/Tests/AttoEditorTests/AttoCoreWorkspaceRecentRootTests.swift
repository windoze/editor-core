@testable import AttoEditor
import Foundation
import XCTest

@MainActor
final class AttoCoreWorkspaceRecentRootTests: XCTestCase {
    func testWindowSessionSnapshotUsesCoreWorkspaceRootURIWhenAvailable() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceRecentRootTests-\(UUID().uuidString)", isDirectory: true)
        let alternateRoot = tempDir.appendingPathComponent("core-root", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: alternateRoot, withIntermediateDirectories: true)
        defer {
            delegate._closeWindowsForTesting()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        let coreDocuments = try XCTUnwrap(ctx.editorAreaController.coreDocuments)
        try coreDocuments.setWorkspaceRoots([alternateRoot.standardizedFileURL.absoluteString])

        let snapshot = ctx.makeSessionSnapshot()
        XCTAssertEqual(snapshot.workspaceRootPath, alternateRoot.standardizedFileURL.path)
        XCTAssertEqual(snapshot.workspaceRootURI, alternateRoot.standardizedFileURL.absoluteString)
        XCTAssertEqual(snapshot.validatedWorkspaceRootURL()?.standardizedFileURL, alternateRoot.standardizedFileURL)
    }

    func testWindowRecentFilesUseCoreMultiDocumentStoreForSessionSnapshot() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceRecentRootTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            delegate._closeWindowsForTesting()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        let coreDocuments = try XCTUnwrap(ctx.editorAreaController.coreDocuments)

        ctx.rememberRecentFile(firstURL)
        ctx.rememberRecentFile(secondURL)
        ctx.rememberRecentFile(firstURL)

        XCTAssertEqual(try coreDocuments.recentFiles().map(\.uri), [
            firstURL.standardizedFileURL.absoluteString,
            secondURL.standardizedFileURL.absoluteString,
        ])
        XCTAssertEqual(ctx.makeSessionSnapshot().recentFilePaths, [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path,
        ])

        try coreDocuments.restoreRecentFileURIs([secondURL.standardizedFileURL.absoluteString])
        XCTAssertEqual(ctx.recentFileURLs(), [secondURL.standardizedFileURL])
        XCTAssertEqual(ctx.makeSessionSnapshot().recentFilePaths, [secondURL.standardizedFileURL.path])

        ctx.restoreRecentFiles(filePaths: [
            firstURL.path,
            secondURL.path,
            firstURL.path,
            tempDir.appendingPathComponent("missing.txt").path,
        ])
        XCTAssertEqual(try coreDocuments.recentFiles().map(\.uri), [
            firstURL.standardizedFileURL.absoluteString,
            secondURL.standardizedFileURL.absoluteString,
        ])
    }

    func testWindowWorkspaceRootsUseCoreRecentProjectsStore() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoCoreWorkspaceRecentRootTests-\(UUID().uuidString)", isDirectory: true)
        let firstRootURL = tempDir.appendingPathComponent("first", isDirectory: true)
        let secondRootURL = tempDir.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRootURL, withIntermediateDirectories: true)
        defer {
            delegate._closeWindowsForTesting()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let ctx = delegate._createWindowForTesting(workspaceRootURL: firstRootURL)
        let coreDocuments = try XCTUnwrap(ctx.editorAreaController.coreDocuments)

        XCTAssertEqual(try coreDocuments.recentProjects().map(\.uri), [
            firstRootURL.standardizedFileURL.absoluteString,
        ])
        XCTAssertEqual(ctx.recentProjectURLs(), [firstRootURL.standardizedFileURL])

        ctx.setWorkspaceRootURL(secondRootURL)
        XCTAssertEqual(try coreDocuments.recentProjects().map(\.uri), [
            secondRootURL.standardizedFileURL.absoluteString,
            firstRootURL.standardizedFileURL.absoluteString,
        ])
        XCTAssertEqual(ctx.recentProjectURLs(), [
            secondRootURL.standardizedFileURL,
            firstRootURL.standardizedFileURL,
        ])

        ctx.setWorkspaceRootURL(firstRootURL)
        XCTAssertEqual(try coreDocuments.recentProjects().map(\.uri), [
            firstRootURL.standardizedFileURL.absoluteString,
            secondRootURL.standardizedFileURL.absoluteString,
        ])

        let snapshot = try XCTUnwrap(delegate._makeSessionSnapshotForTesting())
        XCTAssertEqual(snapshot.recentProjectURIs, [
            firstRootURL.standardizedFileURL.absoluteString,
            secondRootURL.standardizedFileURL.absoluteString,
        ])

        ctx.restoreRecentProjectURIs([
            secondRootURL.standardizedFileURL.absoluteString,
            firstRootURL.standardizedFileURL.absoluteString,
            secondRootURL.standardizedFileURL.absoluteString,
            tempDir.appendingPathComponent("missing", isDirectory: true).standardizedFileURL.absoluteString,
            "not-a-uri",
        ])
        XCTAssertEqual(try coreDocuments.recentProjects().map(\.uri), [
            secondRootURL.standardizedFileURL.absoluteString,
            firstRootURL.standardizedFileURL.absoluteString,
        ])

        let recentProjectCommands = delegate._recentProjectCommandsForTesting()
        XCTAssertEqual(recentProjectCommands.count, 2)
        XCTAssertTrue(recentProjectCommands[0].id.hasPrefix("file.open_recent_project:"))
        XCTAssertTrue(recentProjectCommands[0].title.contains(secondRootURL.lastPathComponent))
        XCTAssertTrue(recentProjectCommands[1].title.contains(firstRootURL.lastPathComponent))

        recentProjectCommands[0].run()
        XCTAssertEqual(delegate._workspaceRootURLsForTesting().last, secondRootURL.standardizedFileURL)
    }
}
