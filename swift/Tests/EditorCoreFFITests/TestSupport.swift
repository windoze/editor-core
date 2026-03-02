import Foundation
import XCTest
@testable import EditorCoreFFI

final class EditorCoreFFITestSupport: @unchecked Sendable {
    static let shared = EditorCoreFFITestSupport()

    private let lock = NSRecursiveLock()
    private var cachedRepoRoot: String?
    private var cachedLibraryPath: String?
    private var didBuildFFI: Bool = false

    func repoRoot() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cachedRepoRoot {
            return cachedRepoRoot
        }

        guard let root = locateRepoRoot() else {
            throw XCTSkip("无法定位仓库根目录：找不到 crates/editor-core-ffi/Cargo.toml")
        }
        cachedRepoRoot = root
        return root
    }

    func libraryPath() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cachedLibraryPath {
            return cachedLibraryPath
        }

        let root = try repoRoot()
        try requireCargo()

        if !didBuildFFI {
            try buildEditorCoreFFI(repoRoot: root)
            didBuildFFI = true
        }

        let path = (root as NSString).appendingPathComponent("target/debug/\(libraryFileName())")
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("已构建但未找到 dylib：\(path)")
        }

        cachedLibraryPath = path
        return path
    }

    func loadLibrary() throws -> EditorCoreFFILibrary {
        let path = try libraryPath()
        return try EditorCoreFFILibrary(path: path)
    }

    func makeTempDir(prefix: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private

    private func locateRepoRoot() -> String? {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<20 {
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

    private func requireCargo() throws {
        let result = try runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["which", "cargo"],
            currentDirectory: FileManager.default.currentDirectoryPath
        )
        guard result.exitCode == 0 else {
            throw XCTSkip("cargo 不可用，跳过 editor-core-ffi 集成测试。")
        }
    }

    private func buildEditorCoreFFI(repoRoot: String) throws {
        let build = try runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["cargo", "build", "-p", "editor-core-ffi"],
            currentDirectory: repoRoot
        )
        guard build.exitCode == 0 else {
            throw XCTSkip("cargo build -p editor-core-ffi 失败：\n\(build.stderr)\n\(build.stdout)")
        }
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

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
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

enum JSONTestHelpers {
    static func object(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            XCTFail("期望 JSON object，但实际是：\(type(of: obj))")
            return [:]
        }
        return dict
    }

    static func array(_ json: String) throws -> [Any] {
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let arr = obj as? [Any] else {
            XCTFail("期望 JSON array，但实际是：\(type(of: obj))")
            return []
        }
        return arr
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    static func stringify(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

enum FFITestHelpers {
    static func assertLastErrorSet(
        _ library: EditorCoreFFILibrary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let message = library.lastErrorMessage().trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(message.isEmpty, file: file, line: line)
        XCTAssertNotEqual(message, "no error", file: file, line: line)
    }
}

extension ViewportBlob {
    func stylesForCell(at index: Int) -> [UInt32] {
        guard index >= 0 && index < cells.count else {
            return []
        }
        let cell = cells[index]
        let start = Int(cell.styleStartIndex)
        let count = Int(cell.styleCount)
        guard count > 0 else {
            return []
        }
        guard start >= 0, start + count <= styleIds.count else {
            return []
        }
        return Array(styleIds[start..<(start + count)])
    }
}
