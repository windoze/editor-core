import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// AttoEditor 文件日志（主进程/GUI/server）。
///
/// 目标：
/// - detached 启动时不把日志泄露到 CLI 的 stdout/stderr
/// - 主进程把 stdout/stderr 重定向到 `~/Library/Logs/AttoEditor/AttoEditor.log`
/// - 支持简单的 log rotation（按大小）
enum AttoLogging {
    static let envLogFile = "ATTOEDITOR_LOG_FILE"
    static let envLogStdio = "ATTOEDITOR_LOG_STDIO"
    static let envDetached = "ATTOEDITOR_DETACHED"

    // Rotation policy: 5MB * 5 份备份（.1 ~ .5）
    private static let maxBytes: Int64 = 5 * 1024 * 1024
    private static let maxRotations: Int = 5

    /// 在 GUI/server 模式尽早调用（在任何 NSLog/print 之前）。
    ///
    /// - 如果是 detached（`ATTOEDITOR_DETACHED=1`）：强制写文件，不允许输出到当前 console。
    /// - 否则：当 `ATTOEDITOR_LOG_STDIO=1` 时不重定向，便于手动调试；但仍会确保日志目录存在。
    static func installIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        let isDetached = (env[envDetached] == "1")
        let wantsStdio = (env[envLogStdio] == "1")

        // detached 时禁止把日志输出到 CLI console。
        let shouldRedirectToFile = (isDetached || wantsStdio == false)

        let logURL = resolveLogURL(environment: env)
        do {
            try ensureLogDirectoryExists(for: logURL)
            try rotateIfNeeded(logURL: logURL)
        } catch {
            // 不能使用 NSLog（可能还没重定向）；直接写 stderr。
            fputs("AttoEditor: failed to init log file: \(error)\n", stderr)
            return
        }

        if shouldRedirectToFile == false {
            return
        }

        do {
            let fd = try openLogFDForAppend(logURL: logURL)
            redirectStdIO(to: fd)
            // dup2 后可以关掉原 fd，stdout/stderr 会继续指向目标文件。
            close(fd)
            writeBanner(logURL: logURL, isDetached: isDetached)
        } catch {
            fputs("AttoEditor: failed to redirect logs: \(error)\n", stderr)
        }
    }

    // MARK: - Paths

    private static func resolveLogURL(environment env: [String: String]) -> URL {
        if let p = env[envLogFile]?.trimmingCharacters(in: .whitespacesAndNewlines), p.isEmpty == false {
            return URL(fileURLWithPath: p)
        }

        if let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            return lib
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("AttoEditor", isDirectory: true)
                .appendingPathComponent("AttoEditor.log", isDirectory: false)
        }

        // 理论上不会走到这里，兜底到 /tmp。
        return URL(fileURLWithPath: "/tmp/attoeditor.\(getuid()).log")
    }

    private static func ensureLogDirectoryExists(for logURL: URL) throws {
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    // MARK: - Rotation

    private static func rotateIfNeeded(logURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: logURL.path) else { return }

        let attrs = try fm.attributesOfItem(atPath: logURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= maxBytes else { return }

        func rotatedURL(_ idx: Int) -> URL {
            URL(fileURLWithPath: logURL.path + ".\(idx)")
        }

        // 删除最老的
        let oldest = rotatedURL(maxRotations)
        if fm.fileExists(atPath: oldest.path) {
            try? fm.removeItem(at: oldest)
        }

        // 依次后移：.4 -> .5, ... .1 -> .2
        if maxRotations >= 2 {
            for i in stride(from: maxRotations - 1, through: 1, by: -1) {
                let src = rotatedURL(i)
                let dst = rotatedURL(i + 1)
                if fm.fileExists(atPath: src.path) {
                    try? fm.removeItem(at: dst)
                    try fm.moveItem(at: src, to: dst)
                }
            }
        }

        // 当前 -> .1
        let first = rotatedURL(1)
        try? fm.removeItem(at: first)
        try fm.moveItem(at: logURL, to: first)

        // 创建新空文件
        _ = fm.createFile(atPath: logURL.path, contents: nil)
    }

    // MARK: - Redirect

    private static func openLogFDForAppend(logURL: URL) throws -> Int32 {
        let path = logURL.path
        // open() 需要 C string
        let fd = path.withCString { cstr in
            open(cstr, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        }
        if fd < 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return fd
    }

    private static func redirectStdIO(to fd: Int32) {
        _ = dup2(fd, STDOUT_FILENO)
        _ = dup2(fd, STDERR_FILENO)

        // stdout 在文件时默认全缓冲；改为行缓冲更像 “tail -f”。
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
    }

    private static func writeBanner(logURL: URL, isDetached: Bool) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("----- AttoEditor log started \(ts) pid=\(pid) detached=\(isDetached) path=\(logURL.path)\n", stderr)
    }
}

