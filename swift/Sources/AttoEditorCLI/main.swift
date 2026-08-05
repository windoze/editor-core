import AttoEditorSupport
import Foundation
import MachO

private enum AttoEditorCLIMain {
    private static let serverExecutableName = "AttoEditor"

    private static func resolvedSelfExecutablePath() -> String? {
        // 优先从 dyld 获取当前进程真实路径（对 symlink / argv[0] 不可靠场景更稳）。
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }

        var buf = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return nil }

        let bytes = buf.map { UInt8(bitPattern: $0) }
        let nul = bytes.firstIndex(of: 0) ?? bytes.count
        let raw = String(decoding: bytes.prefix(nul), as: UTF8.self)
        // 注意：如果用户在 PATH 里用 symlink 调用（/usr/local/bin/atto -> *.app/.../atto），
        // 这里需要 resolve symlinks，否则无法从 “同目录” 推导出 AttoEditor 可执行文件路径。
        return URL(fileURLWithPath: raw)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private static func resolveServerExecutablePath() -> String? {
        let fm = FileManager.default

        func isExecutable(_ p: String) -> Bool {
            fm.isExecutableFile(atPath: p)
        }

        // 允许通过环境变量覆盖（便于调试 / 非标准安装路径）。
        if let p = ProcessInfo.processInfo.environment["ATTOEDITOR_SERVER_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           p.isEmpty == false
        {
            let path = URL(fileURLWithPath: p)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
            if isExecutable(path) { return path }
        }

        // 1) 运行在 `.app/Contents/MacOS/` 内：直接从 Bundle.main 解析。
        //    这是 “把 CLI 打包进 .app 并 symlink 到 PATH” 的主路径。
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        if bundleURL.pathExtension == "app" {
            let p = bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(serverExecutableName, isDirectory: false)
                .path
            if isExecutable(p) { return p }
        }

        // 2) SwiftPM build 产物目录：同一 bin 目录里通常同时有 `AttoEditor` 与 `atto`。
        if let selfPath = resolvedSelfExecutablePath() {
            let binDir = URL(fileURLWithPath: selfPath).deletingLastPathComponent()
            let p = binDir.appendingPathComponent(serverExecutableName, isDirectory: false).path
            if isExecutable(p) { return p }
        }

        // 3) 常见安装路径兜底（不保证用户一定安装在这里；更推荐 wrapper 来做定位）。
        let candidates = [
            "/Applications/AttoEditor.app/Contents/MacOS/\(serverExecutableName)",
            NSString(string: "~/Applications/AttoEditor.app/Contents/MacOS/\(serverExecutableName)").expandingTildeInPath,
        ]
        for p in candidates {
            let path = URL(fileURLWithPath: p).standardizedFileURL.path
            if isExecutable(path) { return path }
        }

        return nil
    }

    static func run() -> Never {
        AttoIPC.ignoreSIGPIPE()

        let parsed = AttoCommandLine.parse(arguments: ProcessInfo.processInfo.arguments)
        if parsed.helpRequested {
            print(AttoCommandLine.usageText)
            exit(0)
        }

        guard let serverExe = resolveServerExecutablePath() else {
            fputs("atto: 找不到 AttoEditor 可执行文件（用于启动 GUI/server）。\\n", stderr)
            fputs("提示：如果你是通过 symlink 使用，请确保 symlink 指向 AttoEditor.app 内的 `atto`。\\n", stderr)
            fputs("      或设置环境变量：ATTOEDITOR_SERVER_EXECUTABLE=/path/to/AttoEditor\\n", stderr)
            exit(1)
        }

        let requestID = UUID().uuidString

        let req = AttoIpcOpenRequest(
            requestID: requestID,
            newWindow: parsed.newWindow,
            wait: parsed.wait,
            directories: parsed.directories.map(\.path),
            files: parsed.files.map { f in
                AttoIpcFileRequest(
                    path: f.url.path,
                    line1: f.location?.line1,
                    column1: f.location?.column1
                )
            }
        )

        let code = AttoIpcClient.sendOpenRequest(req, executablePath: serverExe)
        exit(code)
    }
}

AttoEditorCLIMain.run()
