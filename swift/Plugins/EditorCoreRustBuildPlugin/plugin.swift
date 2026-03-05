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
        // UI FFI 依赖 Skia（体积大、且 build.rs 可能尝试联网下载 skia-binaries / skia 源码）。
        // SwiftPM plugin sandbox 通常禁止网络访问，因此这里优先复用仓库根目录已构建好的 `.a`，
        // 只做“复制到 plugin output 目录”以满足静态链接。
        //
        // 同时做一个简单的“新鲜度”检查：如果仓库根目录的 `.a` 比相关源码更旧，则直接报错，
        // 避免静默链接到旧 ABI（例如新增了 Metal 渲染 API 却没有符号）。
        let destDir = "\(rustTargetDir)/release"
        let destLib = "\(destDir)/libeditor_core_ui_ffi.a"
        return """
        mkdir -p "\(destDir)"

        src_mtime=0
        src_files=(
          "Cargo.lock"
          "crates/editor-core-ui-ffi/src/lib.rs"
          "crates/editor-core-ui/src/lib.rs"
          "crates/editor-core-render-skia/src/lib.rs"
          "crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h"
        )
        for f in "${src_files[@]}"; do
          if [ -f "$f" ]; then
            t=$(stat -f %m "$f" || echo 0)
            if [ "$t" -gt "$src_mtime" ]; then
              src_mtime="$t"
            fi
          fi
        done

        try_copy() {
          local src="$1"
          if [ -f "$src" ]; then
            lib_mtime=$(stat -f %m "$src" || echo 0)
            if [ "$lib_mtime" -ge "$src_mtime" ]; then
              cp -f "$src" "\(destLib)"
              exit 0
            fi
          fi
        }

        try_copy "target/debug/libeditor_core_ui_ffi.a"
        try_copy "target/release/libeditor_core_ui_ffi.a"

        echo "error: Rust staticlib libeditor_core_ui_ffi.a 不存在或已过期（SwiftPM plugin sandbox 无法联网构建 Skia）。" 1>&2
        echo "请先在仓库根目录执行：cargo build -p editor-core-ui-ffi --release（或 debug），再运行 swift build/test。" 1>&2
        exit 1
        """
    default:
        packages = ["editor-core-ffi", "editor-core-ui-ffi"]
    }

    let flags = packages.flatMap { ["-p", $0] }.joined(separator: " ")
    return "cargo build \(flags) --release --target-dir \"\(rustTargetDir)\""
}
