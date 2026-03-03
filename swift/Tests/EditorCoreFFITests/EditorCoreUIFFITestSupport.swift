import EditorCoreUIFFI
import Foundation
import XCTest

final class EditorCoreUIFFITestSupport: @unchecked Sendable {
    static let shared = EditorCoreUIFFITestSupport()

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
            throw XCTSkip("无法定位仓库根目录：找不到 crates/editor-core-ui-ffi/Cargo.toml")
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
            try buildEditorCoreUIFFI(repoRoot: root)
            didBuildFFI = true
        }

        let path = (root as NSString).appendingPathComponent("target/debug/\(libraryFileName())")
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("已构建但未找到 dylib：\(path)")
        }

        cachedLibraryPath = path
        return path
    }

    func loadLibrary() throws -> EditorCoreUIFFILibrary {
        let path = try libraryPath()
        return try EditorCoreUIFFILibrary(explicitPath: path)
    }

    // MARK: - Private

    private func locateRepoRoot() -> String? {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<20 {
            let probe = current.appendingPathComponent("crates/editor-core-ui-ffi/Cargo.toml").path
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
            throw XCTSkip("cargo 不可用，跳过 editor-core-ui-ffi 集成测试。")
        }
    }

    private func buildEditorCoreUIFFI(repoRoot: String) throws {
        let build = try runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["cargo", "build", "-p", "editor-core-ui-ffi"],
            currentDirectory: repoRoot
        )
        guard build.exitCode == 0 else {
            throw XCTSkip("cargo build -p editor-core-ui-ffi 失败：\n\(build.stderr)\n\(build.stdout)")
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
        return "libeditor_core_ui_ffi.dylib"
        #elseif os(Linux)
        return "libeditor_core_ui_ffi.so"
        #elseif os(Windows)
        return "editor_core_ui_ffi.dll"
        #else
        return "libeditor_core_ui_ffi.dylib"
        #endif
    }
}

