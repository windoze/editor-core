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

        let envelope = try multi.searchWorkspaceFilesEnvelope(
            query: "needle",
            options: EcuSearchOptions(caseSensitive: false),
            includeGlobs: ["*.rs"],
            excludeGlobs: [],
            maxResults: 10
        )
        let results = try envelope.workspaceFileSearchResults()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].path, sourceURL.standardizedFileURL.path)
        XCTAssertEqual(results[0].relativePath, "src/lib.rs")
        XCTAssertEqual(results[0].line1, 2)
        XCTAssertEqual(results[0].column1, 9)
        XCTAssertEqual(results[0].lineText, "let needle = 1;")
        XCTAssertEqual(results[0].matchStart, 8)
        XCTAssertEqual(results[0].matchEnd, 14)

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

    func testMultiDocumentWorkspaceFileScanOptionsExposeSummary() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try "ignored.txt\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "needle ignored\n".write(to: root.appendingPathComponent("ignored.txt"), atomically: true, encoding: .utf8)
        try "needle a1\nneedle a2\n".write(to: root.appendingPathComponent("src/a.txt"), atomically: true, encoding: .utf8)
        try "needle b\n".write(to: root.appendingPathComponent("src/b.txt"), atomically: true, encoding: .utf8)
        try Data([0x6E, 0x65, 0x65, 0x64, 0x6C, 0x65, 0x00]).write(to: root.appendingPathComponent("binary.bin"))
        try "needle \(String(repeating: "x", count: 256))\n".write(
            to: root.appendingPathComponent("large.txt"),
            atomically: true,
            encoding: .utf8
        )

        try multi.setWorkspaceRoots([root.standardizedFileURL.absoluteString])

        let scanOptions = EcuWorkspaceFileScanOptions(
            includeGlobs: ["*.txt", "*.bin"],
            maxResults: 1,
            offset: 1,
            maxFileSizeBytes: 128
        )
        let searchResponse = try multi
            .searchWorkspaceFilesEnvelope(
                query: "needle",
                options: EcuSearchOptions(caseSensitive: false),
                scanOptions: scanOptions
            )
            .workspaceFileSearchResponse()

        XCTAssertEqual(searchResponse.results.map(\.relativePath), ["src/a.txt"])
        XCTAssertEqual(searchResponse.results.map(\.line1), [2])
        XCTAssertEqual(searchResponse.scan.offset, 1)
        XCTAssertEqual(searchResponse.scan.returnedResults, 1)
        XCTAssertEqual(searchResponse.scan.matchedResults, 3)
        XCTAssertEqual(searchResponse.scan.nextOffset, 2)
        XCTAssertTrue(searchResponse.scan.truncated)
        XCTAssertEqual(searchResponse.scan.skippedBinaryFiles, 1)
        XCTAssertEqual(searchResponse.scan.skippedLargeFiles, 1)
        XCTAssertTrue(searchResponse.scan.ignoreFilesEnabled)

        let cancelledList = try multi
            .listWorkspaceFilesEnvelope(
                scanOptions: EcuWorkspaceFileScanOptions(maxResults: 10, cancelAfterFiles: 1)
            )
            .workspaceFileListResponse()
        XCTAssertEqual(cancelledList.files.count, 1)
        XCTAssertEqual(cancelledList.scan.visitedFiles, 1)
        XCTAssertTrue(cancelledList.scan.cancelled)
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

        let listEnvelope = try multi.listWorkspaceFilesEnvelope(
            includeGlobs: ["src/**"],
            excludeGlobs: ["*.swift"],
            maxResults: 10
        )
        let files = try listEnvelope.workspaceFileEntries()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, sourceURL.standardizedFileURL.path)
        XCTAssertEqual(files[0].relativePath, "src/lib.rs")
        XCTAssertEqual(URL(string: files[0].uri)?.isFileURL, true)

        XCTAssertTrue(listEnvelope.ok)
        XCTAssertEqual(listEnvelope.statusKind, .success)
        guard case .object(let listValue)? = listEnvelope.value,
              case .array(let envelopeFiles)? = listValue["files"]
        else {
            XCTFail("expected workspace file list envelope")
            return
        }
        XCTAssertEqual(envelopeFiles.count, 1)

        let limited = try multi.listWorkspaceFilesEnvelope(maxResults: 1).workspaceFileEntries()
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
        let initialEnvelope = try multi.projectFileIndexSnapshotEnvelope()
        let initial = try initialEnvelope.projectFileIndexSnapshot()
        XCTAssertFalse(initial.isBuilt)
        XCTAssertTrue(initial.files.isEmpty)
        XCTAssertTrue(try multi.queryProjectFileIndexEnvelope(query: "cm").projectFileIndexQueryResults().isEmpty)
        XCTAssertTrue(initialEnvelope.ok)
        guard case .object(let initialValue)? = initialEnvelope.value,
              initialValue["is_built"] == .bool(false)
        else {
            XCTFail("expected initial project file index snapshot envelope")
            return
        }

        let refreshedEnvelope = try multi.refreshProjectFileIndexEnvelope(maxResults: 10)
        let refreshed = try refreshedEnvelope.projectFileIndexSnapshot()
        XCTAssertTrue(refreshed.isBuilt)
        XCTAssertEqual(refreshed.maxResults, 10)
        XCTAssertEqual(refreshed.files.map(\.relativePath), ["src/core_model.rs", "src/lib.rs"])
        XCTAssertTrue(refreshedEnvelope.ok)
        guard case .object(let refreshedValue)? = refreshedEnvelope.value,
              case .array(let refreshedFiles)? = refreshedValue["files"]
        else {
            XCTFail("expected refreshed project file index envelope")
            return
        }
        XCTAssertEqual(refreshedFiles.count, 2)
        let queryEnvelope = try multi.queryProjectFileIndexEnvelope(query: "cm")
        let queryMatches = try queryEnvelope.projectFileIndexQueryResults()
        XCTAssertEqual(queryMatches.map(\.relativePath), ["src/core_model.rs"])
        XCTAssertGreaterThan(try XCTUnwrap(queryMatches.first?.score), 0)
        XCTAssertTrue(queryEnvelope.ok)
        guard case .object(let queryValue)? = queryEnvelope.value,
              case .array(let envelopeMatches)? = queryValue["results"]
        else {
            XCTFail("expected project file index query envelope")
            return
        }
        XCTAssertEqual(envelopeMatches.count, 1)

        try "fn main() {}\n".write(to: secondURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(
            try multi.projectFileIndexSnapshotEnvelope().projectFileIndexSnapshot().files.map(\.relativePath),
            ["src/core_model.rs", "src/lib.rs"]
        )
        XCTAssertEqual(
            try multi.refreshProjectFileIndexEnvelope(maxResults: 10).projectFileIndexSnapshot().files.map(\.relativePath),
            ["src/core_model.rs", "src/lib.rs", "src/main.rs"]
        )

        try multi.clearProjectFileIndex()
        let cleared = try multi.projectFileIndexSnapshotEnvelope().projectFileIndexSnapshot()
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

        let replacementEnvelope = try multi.workspaceFileReplacementWorkspaceEditEnvelope(
            query: #"alpha(\d)"#,
            replacement: "beta$1",
            options: EcuSearchOptions(caseSensitive: true, regex: true),
            includeGlobs: ["*.rs"],
            excludeGlobs: [],
            applyMode: "atomic",
            maxResults: 10
        )
        let workspaceEdit = try replacementEnvelope.workspaceFileReplacementWorkspaceEditPayloadJSON()
        XCTAssertTrue(replacementEnvelope.ok)
        XCTAssertEqual(replacementEnvelope.statusKind, .success)
        guard case .object(let workspaceEditValue)? = replacementEnvelope.value else {
            XCTFail("expected workspace replacement envelope value object")
            return
        }
        guard case .object(let editPayload)? = workspaceEditValue["workspaceEdit"] else {
            XCTFail("expected workspace replacement envelope workspaceEdit object")
            return
        }
        XCTAssertTrue(editPayload["changes"] != nil || editPayload["documentChanges"] != nil)

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
