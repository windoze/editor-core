import Foundation
import XCTest
@testable import EditorComponentKit

final class EditorCoreFFIIntegrationTests: XCTestCase {
    func testEngineExecutesTypedCommandsAndReadsViewportBlob() throws {
        let libraryPath = try requireBuiltLibraryPath()
        let library = try EditorCoreFFILibrary(path: libraryPath)
        let engine = try EditorCoreFFIEngine(
            initialText: "abc\nline2\n",
            viewportWidth: 120,
            library: library
        )

        _ = try engine.execute(.moveTo(.init(line: 0, column: 3)))
        _ = try engine.execute(.insertText("XYZ"))
        _ = try engine.execute(.backspace)

        let text = engine.text
        XCTAssertTrue(text.contains("ab"))
        XCTAssertTrue(text.contains("line2"))

        let state = try engine.documentState()
        XCTAssertEqual(state.lineCount, 3)
        XCTAssertTrue(state.charCount >= 9)

        let snapshot = try engine.styledViewport(.init(startVisualRow: 0, rowCount: 32))
        XCTAssertGreaterThan(snapshot.lines.count, 0)
        XCTAssertGreaterThanOrEqual(snapshot.lines[0].cells.count, 0)

        let minimap = try engine.minimapViewport(.init(startVisualRow: 0, rowCount: 32))
        XCTAssertGreaterThan(minimap.lines.count, 0)
    }

    func testEngineAppliesProcessingEditsAndExposesStylesInlaysFoldsDiagnostics() throws {
        let libraryPath = try requireBuiltLibraryPath()
        let library = try EditorCoreFFILibrary(path: libraryPath)
        let engine = try EditorCoreFFIEngine(
            initialText: "let value = 1\nsecond line\n",
            viewportWidth: 120,
            library: library
        )

        let editsJSON = """
        [
          {
            "op": "replace_style_layer",
            "layer": 131072,
            "intervals": [
              { "start": 0, "end": 3, "style_id": 9 }
            ]
          },
          {
            "op": "replace_folding_regions",
            "regions": [
              {
                "start_line": 0,
                "end_line": 1,
                "is_collapsed": false,
                "placeholder": "[...]"
              }
            ],
            "preserve_collapsed": false
          },
          {
            "op": "replace_decorations",
            "layer": 1,
            "decorations": [
              {
                "range": { "start": 3, "end": 3 },
                "placement": "after",
                "kind": { "kind": "inlay_hint" },
                "text": ": i32",
                "styles": [42]
              }
            ]
          },
          {
            "op": "replace_diagnostics",
            "diagnostics": [
              {
                "range": { "start": 4, "end": 9 },
                "severity": "warning",
                "message": "demo warning"
              }
            ]
          }
        ]
        """

        try engine.applyProcessingEditsJSON(editsJSON)

        let spans = try engine.styleSpans(in: 0..<20)
        XCTAssertTrue(spans.contains { $0.styleID == 9 && $0.startOffset <= 0 && $0.endOffset >= 3 })

        let inlays = try engine.inlays(in: 0..<40)
        XCTAssertTrue(inlays.contains { $0.text.contains(": i32") })

        let folds = try engine.foldRegions()
        XCTAssertEqual(folds.count, 1)
        XCTAssertEqual(folds[0].startLine, 0)
        XCTAssertEqual(folds[0].endLine, 1)

        let diagnostics = try engine.diagnostics()
        XCTAssertEqual(diagnostics.items.count, 1)
        XCTAssertEqual(diagnostics.items[0].severity, "warning")
        XCTAssertEqual(diagnostics.items[0].message, "demo warning")
    }

    func testLSPBridgeRoundTripsPathAndUtf16Offsets() throws {
        let libraryPath = try requireBuiltLibraryPath()
        let library = try EditorCoreFFILibrary(path: libraryPath)
        let bridge = try EditorCoreFFILSPBridge(library: library)

        let path = "/tmp/editor-core ffi.swift"
        let uri = try bridge.pathToFileURI(path)
        XCTAssertTrue(uri.hasPrefix("file://"))
        let roundTrip = try bridge.fileURIToPath(uri)
        XCTAssertEqual(roundTrip, path)

        let encoded = try bridge.percentEncodePath(path)
        XCTAssertTrue(encoded.contains("%20"))
        let decoded = try bridge.percentDecodePath(encoded)
        XCTAssertEqual(decoded, path)

        let text = "a🙂b"
        let utf16 = bridge.charOffsetToUTF16(lineText: text, charOffset: 2)
        XCTAssertEqual(utf16, 3)
        let scalarOffset = bridge.utf16OffsetToCharOffset(lineText: text, utf16Offset: utf16)
        XCTAssertEqual(scalarOffset, 2)
    }

    private func requireBuiltLibraryPath() throws -> String {
        guard let repoRoot = locateRepoRoot() else {
            throw XCTSkip("Could not locate repository root for editor-core-ffi build.")
        }

        guard commandExists("cargo") else {
            throw XCTSkip("cargo is not available; skipping editor-core-ffi integration tests.")
        }

        let build = try runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["cargo", "build", "-p", "editor-core-ffi"],
            currentDirectory: repoRoot
        )
        guard build.exitCode == 0 else {
            throw XCTSkip("cargo build -p editor-core-ffi failed:\n\(build.stderr)\n\(build.stdout)")
        }

        let path = (repoRoot as NSString).appendingPathComponent("target/debug/\(libraryFileName())")
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Built library not found at expected path: \(path)")
        }
        return path
    }

    private func locateRepoRoot() -> String? {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let probe = current.appendingPathComponent("crates/editor-core-ffi/Cargo.toml").path
            if FileManager.default.fileExists(atPath: probe) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }

    private func commandExists(_ command: String) -> Bool {
        let result = try? runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["which", command],
            currentDirectory: FileManager.default.currentDirectoryPath
        )
        return result?.exitCode == 0
    }

    private func runProcess(
        launchPath: String,
        arguments: [String],
        currentDirectory: String
    ) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private func libraryFileName() -> String {
        #if os(macOS)
        return "libeditor_core_ffi.dylib"
        #elseif os(Linux)
        return "libeditor_core_ffi.so"
        #elseif os(Windows)
        return "editor_core_ffi.dll"
        #else
        return "libeditor_core_ffi.dylib"
        #endif
    }
}
