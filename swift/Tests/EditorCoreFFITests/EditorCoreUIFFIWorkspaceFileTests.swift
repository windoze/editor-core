import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testMultiDocumentWorkspaceFileSearchUsesWorkspaceRootsAndGlobs() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("src/lib.rs")
        let notesURL = root.appendingPathComponent("notes.txt")
        try "fn main() {\n    let needle = 1;\n}\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "needle in notes\n".write(to: notesURL, atomically: true, encoding: .utf8)

        try multi.setWorkspaceRoots([root.standardizedFileURL.absoluteString])

        let results = try multi.searchWorkspaceFiles(
            query: "needle",
            options: EcuSearchOptions(caseSensitive: false),
            includeGlobs: ["*.rs"],
            excludeGlobs: [],
            maxResults: 10
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].path, sourceURL.standardizedFileURL.path)
        XCTAssertEqual(results[0].relativePath, "src/lib.rs")
        XCTAssertEqual(results[0].line1, 2)
        XCTAssertEqual(results[0].column1, 9)
        XCTAssertEqual(results[0].lineText, "let needle = 1;")
        XCTAssertEqual(results[0].matchStart, 8)
        XCTAssertEqual(results[0].matchEnd, 14)

        let envelope = try multi.searchWorkspaceFilesEnvelope(
            query: "needle",
            options: EcuSearchOptions(caseSensitive: false),
            includeGlobs: ["*.rs"],
            excludeGlobs: [],
            maxResults: 10
        )
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.statusKind, .success)
        guard case .object(let value)? = envelope.value,
              case .array(let envelopeResults)? = value["results"]
        else {
            XCTFail("expected workspace file search result envelope")
            return
        }
        XCTAssertEqual(envelopeResults.count, 1)
    }

    func testMultiDocumentWorkspaceFileListUsesWorkspaceRootsAndGlobs() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("target", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("src/lib.rs")
        let swiftURL = root.appendingPathComponent("src/App.swift")
        let readmeURL = root.appendingPathComponent("README.md")
        try "pub fn demo() {}\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "let value = 1\n".write(to: swiftURL, atomically: true, encoding: .utf8)
        try "# docs\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try "ignored\n".write(to: root.appendingPathComponent("target/generated.rs"), atomically: true, encoding: .utf8)

        try multi.setWorkspaceRoots([root.standardizedFileURL.absoluteString])

        let files = try multi.listWorkspaceFiles(
            includeGlobs: ["src/**"],
            excludeGlobs: ["*.swift"],
            maxResults: 10
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, sourceURL.standardizedFileURL.path)
        XCTAssertEqual(files[0].relativePath, "src/lib.rs")
        XCTAssertEqual(URL(string: files[0].uri)?.isFileURL, true)

        let limited = try multi.listWorkspaceFiles(maxResults: 1)
        XCTAssertEqual(limited.count, 1)
        XCTAssertEqual(limited[0].relativePath, "README.md")
    }

    func testMultiDocumentProjectFileIndexRefreshesWorkspaceFiles() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-project-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("src/lib.rs")
        let secondURL = root.appendingPathComponent("src/main.rs")
        let coreModelURL = root.appendingPathComponent("src/core_model.rs")
        try "pub fn demo() {}\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "pub fn core() {}\n".write(to: coreModelURL, atomically: true, encoding: .utf8)

        try multi.setWorkspaceRoots([root.standardizedFileURL.absoluteString])
        let initial = try multi.projectFileIndexSnapshot()
        XCTAssertFalse(initial.isBuilt)
        XCTAssertTrue(initial.files.isEmpty)
        XCTAssertTrue(try multi.queryProjectFileIndex(query: "cm").isEmpty)

        let refreshed = try multi.refreshProjectFileIndex(maxResults: 10)
        XCTAssertTrue(refreshed.isBuilt)
        XCTAssertEqual(refreshed.maxResults, 10)
        XCTAssertEqual(refreshed.files.map(\.relativePath), ["src/core_model.rs", "src/lib.rs"])
        let queryMatches = try multi.queryProjectFileIndex(query: "cm")
        XCTAssertEqual(queryMatches.map(\.relativePath), ["src/core_model.rs"])
        XCTAssertGreaterThan(try XCTUnwrap(queryMatches.first?.score), 0)

        try "fn main() {}\n".write(to: secondURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(
            try multi.projectFileIndexSnapshot().files.map(\.relativePath),
            ["src/core_model.rs", "src/lib.rs"]
        )
        XCTAssertEqual(
            try multi.refreshProjectFileIndex(maxResults: 10).files.map(\.relativePath),
            ["src/core_model.rs", "src/lib.rs", "src/main.rs"]
        )

        try multi.clearProjectFileIndex()
        let cleared = try multi.projectFileIndexSnapshot()
        XCTAssertFalse(cleared.isBuilt)
        XCTAssertTrue(cleared.files.isEmpty)
    }

    func testMultiDocumentWorkspaceFileReplacementBuildsWorkspaceEdit() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-replace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("src/lib.rs")
        let notesURL = root.appendingPathComponent("notes.txt")
        try "👋 alpha1\nalpha2\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "alpha3\n".write(to: notesURL, atomically: true, encoding: .utf8)

        try multi.setWorkspaceRoots([root.standardizedFileURL.absoluteString])

        let workspaceEdit = try multi.workspaceFileReplacementWorkspaceEditJSON(
            query: #"alpha(\d)"#,
            replacement: "beta$1",
            options: EcuSearchOptions(caseSensitive: true, regex: true),
            includeGlobs: ["*.rs"],
            excludeGlobs: [],
            applyMode: "atomic",
            maxResults: 10
        )
        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(preview.applied)
        XCTAssertEqual(preview.documents.count, 1)
        XCTAssertEqual(preview.documents[0].editCount, 2)

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 2)
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "👋 beta1\nbeta2\n")
        XCTAssertEqual(try String(contentsOf: notesURL, encoding: .utf8), "alpha3\n")

        let undone = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertTrue(undone.undone)
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "👋 alpha1\nalpha2\n")
    }
}
