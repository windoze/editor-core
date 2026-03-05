import Foundation
import PackagePlugin

@main
struct EditorCoreRustBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        // Swift package 位于仓库的 `swift/` 子目录；Rust workspace root 在其父目录。
        let packageDir = context.package.directory
        let repoRoot = packageDir.removingLastComponent()

        // Cargo 会在 target-dir 同级创建临时目录（后缀随机）做原子替换。
        // SwiftPM plugin sandbox 默认只允许写入 `context.pluginWorkDirectory`，
        // 因此必须把 target-dir 放在该目录内部，避免触发 “Operation not permitted”。
        let rustTargetDir = context.pluginWorkDirectory.appending("cargo-target")

        let script = """
        set -euo pipefail
        cd "\(repoRoot.string)"

        # 避免出现 “object file was built for newer 'macOS' version ...” 的链接警告。
        export MACOSX_DEPLOYMENT_TARGET=13.0

        \(cargoBuildCommand(targetName: target.name, rustTargetDir: rustTargetDir.string))
        """

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cargoBin = "\(home)/.cargo/bin"
        // SwiftPM 的 plugin sandbox 里环境变量可能很“干净”，这里手动补齐常见 PATH。
        let path = [
            cargoBin,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")

        return [
            .prebuildCommand(
                displayName: "Build Rust static libraries (editor-core-ffi, editor-core-ui-ffi)",
                executable: Path("/bin/bash"),
                arguments: ["-c", script],
                environment: [
                    "HOME": home,
                    "PATH": path,
                ],
                // 这里的输出目录只用于满足 SwiftPM 的 prebuildCommand 约定；
                // Rust staticlib 实际落在 `context.pluginWorkDirectory/cargo-target/`（便于 sandbox 写入）。
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}

private func cargoBuildCommand(targetName: String, rustTargetDir: String) -> String {
    // 只在需要时才构建 UI 侧 FFI（它会触发 skia-bindings 的下载/构建逻辑）。
    let packages: [String]
    switch targetName {
    case "CEditorCoreFFI":
        packages = ["editor-core-ffi"]
    case "CEditorCoreUIFFI":
        // 优先复用仓库根目录已有的产物（通常 Rust 开发时已经构建过），避免在 SwiftPM plugin sandbox 内触发 Skia 下载。
        //
        // 产物会被拷贝到 plugin output 目录（`rustTargetDir/release/`），以便 `Package.swift` 静态链接。
        let destDir = "\(rustTargetDir)/release"
        let destLib = "\(destDir)/libeditor_core_ui_ffi.a"
        return """
        mkdir -p "\(destDir)"

        if [ -f "target/debug/libeditor_core_ui_ffi.a" ]; then
          cp -f "target/debug/libeditor_core_ui_ffi.a" "\(destLib)"
          exit 0
        fi
        if [ -f "target/release/libeditor_core_ui_ffi.a" ]; then
          cp -f "target/release/libeditor_core_ui_ffi.a" "\(destLib)"
          exit 0
        fi

        cargo build -p editor-core-ui-ffi --release --target-dir "\(rustTargetDir)"
        """
    default:
        packages = ["editor-core-ffi", "editor-core-ui-ffi"]
    }

    let flags = packages.flatMap { ["-p", $0] }.joined(separator: " ")
    return "cargo build \(flags) --release --target-dir \"\(rustTargetDir)\""
}
