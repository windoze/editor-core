import Foundation

#if canImport(Darwin)
import Darwin
#endif

package enum AttoIPC {
    // 内部启动参数：CLI 用它来启动 GUI/Server 进程。
    package static let internalServerFlag = "--atto-editor-internal-server"
    package static let internalNoDefaultWindowFlag = "--atto-editor-internal-no-default-window"

    package static func socketPath() -> String {
        // Unix domain socket 路径长度有限（通常 104/108 bytes）。放到 /tmp 并带上 uid，避免冲突。
        "/tmp/codes.unwritten.attoeditor.\(getuid()).sock"
    }

    package static func spoolDirPath() -> String {
        "/tmp/codes.unwritten.attoeditor.\(getuid()).spool"
    }

    /// 防止 socket 写入触发 SIGPIPE 导致进程被杀（表现为 exit code 141）。
    /// 这在 `--wait`/IPC 场景下属于“正常可恢复错误”，不应让 CLI 或主进程直接崩溃。
    package static func ignoreSIGPIPE() {
#if canImport(Darwin)
        _ = signal(SIGPIPE, SIG_IGN)
#endif
    }
}

package struct AttoIpcFileRequest: Codable, Equatable {
    package var path: String
    package var line1: Int?
    package var column1: Int?

    package init(path: String, line1: Int?, column1: Int?) {
        self.path = path
        self.line1 = line1
        self.column1 = column1
    }
}

package struct AttoIpcOpenRequest: Codable, Equatable {
    package var requestID: String
    package var newWindow: Bool
    package var wait: Bool
    package var directories: [String]
    package var files: [AttoIpcFileRequest]

    package init(
        requestID: String,
        newWindow: Bool,
        wait: Bool,
        directories: [String],
        files: [AttoIpcFileRequest]
    ) {
        self.requestID = requestID
        self.newWindow = newWindow
        self.wait = wait
        self.directories = directories
        self.files = files
    }
}

package struct AttoIpcResponse: Codable, Equatable {
    package enum Kind: String, Codable {
        case ack
        case done
    }

    package var kind: Kind
    package var requestID: String
    package var ok: Bool
    package var errors: [String]
    package var pendingFileCount: Int

    package init(kind: Kind, requestID: String, ok: Bool, errors: [String], pendingFileCount: Int) {
        self.kind = kind
        self.requestID = requestID
        self.ok = ok
        self.errors = errors
        self.pendingFileCount = pendingFileCount
    }
}

/// `--wait` 需要跟踪“这次请求打开/聚焦的文件实例”，不能用纯 URL：
/// - `--new-window` 会刻意打开重复文件（不同窗口）
/// - 其它窗口里同一路径的 tab 不应影响当前 CLI 的 wait 生命周期
package struct AttoIpcWaitToken: Hashable, Sendable {
    package var windowID: UUID
    package var standardizedPath: String

    package init(windowID: UUID, fileURL: URL) {
        self.windowID = windowID
        self.standardizedPath = fileURL.standardizedFileURL.path
    }
}

package struct AttoIpcOpenResult: Equatable {
    package var pendingTokens: [AttoIpcWaitToken]
    package var errors: [String]

    package init(pendingTokens: [AttoIpcWaitToken], errors: [String]) {
        self.pendingTokens = pendingTokens
        self.errors = errors
    }

    package static var empty: AttoIpcOpenResult { .init(pendingTokens: [], errors: []) }
}

// MARK: - Client

package enum AttoIpcClient {
    package static func sendOpenRequest(
        _ request: AttoIpcOpenRequest,
        executablePath: String,
        connectTimeoutMs: Int = 8000
    ) -> Int32 {
        let socketPath = AttoIPC.socketPath()

        if let fd = connect(socketPath: socketPath) {
            guard writeJSONLine(fd: fd, encodable: request) else {
                close(fd)
                return 1
            }
            if request.wait {
                let code = waitForDone(fd: fd, requestID: request.requestID)
                close(fd)
                return code
            }
            close(fd)
            return 0
        }

        // 没有 server（或临时不可达）。
        // - 非 wait：走 “spool 文件” 方式投递请求，CLI 立刻退出；
        // - wait：需要一个长连接来等待 done，所以必须拉起 server 并连接。
        if request.wait == false {
            do {
                try enqueueSpoolRequest(request)
                try launchDetachedServer(executablePath: executablePath)
                return 0
            } catch {
                fputs("AttoEditor: failed to enqueue request: \(error)\n", stderr)
                return 1
            }
        }

        // wait：启动一个 detached server，然后重试连接发送请求。
        do {
            try launchDetachedServer(executablePath: executablePath)
        } catch {
            fputs("AttoEditor: failed to launch server: \(error)\n", stderr)
            return 1
        }

        let deadline = Date().addingTimeInterval(Double(connectTimeoutMs) / 1000.0)
        var fd: Int32?
        while Date() < deadline {
            if let c = connect(socketPath: socketPath) {
                fd = c
                break
            }
            usleep(50_000) // 50ms
        }

        guard let fd else {
            fputs("AttoEditor: server not responding\n", stderr)
            return 1
        }

        guard writeJSONLine(fd: fd, encodable: request) else {
            close(fd)
            return 1
        }
        if request.wait {
            let code = waitForDone(fd: fd, requestID: request.requestID)
            close(fd)
            return code
        }
        close(fd)
        return 0
    }

    private static func launchDetachedServer(executablePath: String) throws {
        // 用 Process 启动同一个可执行文件，并加内部 flag 进入 GUI/server 模式。
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = [AttoIPC.internalServerFlag, AttoIPC.internalNoDefaultWindowFlag]
        proc.standardInput = FileHandle.nullDevice
        // detached 进程不应把日志写回到 CLI 的 stdout/stderr（否则会污染 CLI 输出）。
        // 主进程会在启动后自行把 stdout/stderr 重定向到 log 文件（见 AttoLogging）。
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        // 标记为 detached：主进程将强制把日志写入文件，忽略 `ATTOEDITOR_LOG_STDIO=1`。
        var env = ProcessInfo.processInfo.environment
        env[AttoLogging.envDetached] = "1"
        proc.environment = env
        try proc.run()
    }

    private static func enqueueSpoolRequest(_ request: AttoIpcOpenRequest) throws {
        let dirPath = AttoIPC.spoolDirPath()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: dirPath, isDirectory: true),
            withIntermediateDirectories: true
        )

        let fileName = "req-\(request.requestID).json"
        let url = URL(fileURLWithPath: dirPath, isDirectory: true).appendingPathComponent(fileName)
        let data = try JSONEncoder().encode(request)
        try data.write(to: url, options: [.atomic])
    }

    private static func waitForDone(fd: Int32, requestID: String) -> Int32 {
        var exitCode: Int32 = 0
        var printedErrors = false
        while true {
            guard let line = readLine(fd: fd) else { return 1 }
            guard let data = line.data(using: .utf8) else { continue }
            guard let resp = try? JSONDecoder().decode(AttoIpcResponse.self, from: data) else { continue }
            if resp.requestID != requestID { continue }

            if printedErrors == false {
                printedErrors = true
                for e in resp.errors {
                    fputs("AttoEditor: \(e)\n", stderr)
                }
            }

            if resp.kind == .done {
                if resp.ok == false || resp.errors.isEmpty == false {
                    exitCode = 1
                }
                return exitCode
            }
        }
    }

    static func connect(socketPath: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        // Avoid SIGPIPE on write() to a dead peer.
#if canImport(Darwin)
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
#endif

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let utf8 = socketPath.utf8CString
        guard utf8.count < maxLen else {
            close(fd)
            return nil
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            raw.initialize(repeating: 0, count: maxLen)
            for (i, c) in utf8.enumerated() {
                raw[i] = c
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)

        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(fd, saPtr, len)
            }
        }

        guard rc == 0 else {
            close(fd)
            return nil
        }

        return fd
    }
}

// MARK: - Server

package final class AttoIpcServer {
    package struct StartResult {
        package var isPrimaryInstance: Bool

        package init(isPrimaryInstance: Bool) {
            self.isPrimaryInstance = isPrimaryInstance
        }
    }

    private struct WaitSession {
        var requestID: String
        var fd: Int32
        var pending: Set<AttoIpcWaitToken>
        var errors: [String]
    }

    private let socketPath: String
    private let onOpenRequest: @MainActor (AttoIpcOpenRequest) -> AttoIpcOpenResult

    private let acceptQueue = DispatchQueue(label: "codes.unwritten.attoeditor.ipc.accept")
    private let sessionsQueue = DispatchQueue(label: "codes.unwritten.attoeditor.ipc.sessions")

    private var listenerFD: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var sessions: [String: WaitSession] = [:]

    private var spoolFD: Int32 = -1
    private var spoolSource: DispatchSourceFileSystemObject?

    package init(
        socketPath: String = AttoIPC.socketPath(),
        onOpenRequest: @escaping @MainActor (AttoIpcOpenRequest) -> AttoIpcOpenResult
    ) {
        self.socketPath = socketPath
        self.onOpenRequest = onOpenRequest
    }

    package func start() -> StartResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .init(isPrimaryInstance: true) }

        // 允许快速重启（避免 TIME_WAIT 影响）。
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        func makeAddr() -> sockaddr_un? {
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
            let utf8 = socketPath.utf8CString
            guard utf8.count < maxLen else { return nil }
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                raw.initialize(repeating: 0, count: maxLen)
                for (i, c) in utf8.enumerated() {
                    raw[i] = c
                }
            }
            return addr
        }

        guard var addr = makeAddr() else {
            close(fd)
            return .init(isPrimaryInstance: true)
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)

        var bindRC: Int32 = -1
        withUnsafePointer(to: &addr) { ptr in
            bindRC = ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.bind(fd, saPtr, len)
            }
        }

        if bindRC != 0 {
            // 可能已有实例在监听，也可能是上次 crash 留下的 socket 文件。
            if errno == EADDRINUSE {
                if let probe = AttoIpcClient.connect(socketPath: socketPath) {
                    close(probe)
                    close(fd)
                    return .init(isPrimaryInstance: false)
                }

                // stale socket：清理后重试一次。
                _ = unlink(socketPath)
                if var addr2 = makeAddr() {
                    withUnsafePointer(to: &addr2) { ptr in
                        bindRC = ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                            Darwin.bind(fd, saPtr, len)
                        }
                    }
                }
            }
        }

        guard bindRC == 0 else {
            close(fd)
            return .init(isPrimaryInstance: true)
        }

        guard listen(fd, 64) == 0 else {
            close(fd)
            return .init(isPrimaryInstance: true)
        }

        // acceptLoop 依赖非阻塞 accept 以避免事件回调里卡住。
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        listenerFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptLoop()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenerFD >= 0 {
                close(self.listenerFD)
                self.listenerFD = -1
            }
            _ = unlink(self.socketPath)
        }
        listenerSource = source
        source.resume()

        startSpoolWatcher()

        return .init(isPrimaryInstance: true)
    }

    package func stop() {
        // 进程退出时，尽量让所有 `--wait` 的 CLI 正常返回（把“app 退出”视作文件关闭）。
        let toClose: [WaitSession] = sessionsQueue.sync {
            let out = Array(sessions.values)
            sessions.removeAll()
            return out
        }
        for s in toClose {
            sendDoneAndClose(session: s)
        }

        listenerSource?.cancel()
        listenerSource = nil

        spoolSource?.cancel()
        spoolSource = nil
    }

    /// 当某个“文件实例”（某个窗口里的某个路径）关闭时调用。
    package func notifyFileInstanceClosed(windowID: UUID, url: URL) {
        let token = AttoIpcWaitToken(windowID: windowID, fileURL: url)
        // `--wait` 场景更关注“可靠性”而不是吞吐量：
        // - sync 可以减少 “最后一个窗口关闭导致 app 退出” 时的竞态（done 来不及发）
        // - 每次写入的数据非常小（JSON 一行），阻塞风险可接受
        let finished: [WaitSession] = sessionsQueue.sync { [weak self] in
            guard let self else { return [] }

            var out: [WaitSession] = []
            for (id, var s) in self.sessions {
                if s.pending.contains(token) {
                    s.pending.remove(token)
                    self.sessions[id] = s
                }
                if s.pending.isEmpty {
                    out.append(s)
                }
            }

            for s in out {
                self.sessions.removeValue(forKey: s.requestID)
            }
            return out
        }

        for s in finished {
            sendDoneAndClose(session: s)
        }
    }

    private func acceptLoop() {
        while true {
            var addr = sockaddr()
            var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = Darwin.accept(listenerFD, &addr, &len)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                break
            }

#if canImport(Darwin)
            // listenerFD 被设置为 O_NONBLOCK 以便 acceptLoop 不阻塞在事件回调里；
            // 但 macOS 上 accept() 返回的 client socket 可能继承 O_NONBLOCK，
            // 这会导致我们在 handleClient 里第一次 read() 立刻拿到 EAGAIN，
            // 从而误判 “对端没发数据” 并提前 close，造成 `--wait`/open 请求丢失。
            //
            // 这里显式把 clientFD 设回 blocking。
            let fl = fcntl(clientFD, F_GETFL, 0)
            if fl >= 0 {
                _ = fcntl(clientFD, F_SETFL, fl & ~O_NONBLOCK)
            }

            // Avoid server crash on write() if client disappears early.
            var yes: Int32 = 1
            _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
#endif

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        guard let line = readLine(fd: fd) else {
            close(fd)
            return
        }
        guard let data = line.data(using: .utf8) else {
            close(fd)
            return
        }
        guard let req = try? JSONDecoder().decode(AttoIpcOpenRequest.self, from: data) else {
            close(fd)
            return
        }

        NSLog(
            "AttoEditor: ipc open request (id=%@ wait=%d newWindow=%d dirs=%d files=%d)",
            req.requestID,
            req.wait ? 1 : 0,
            req.newWindow ? 1 : 0,
            req.directories.count,
            req.files.count
        )

        // 同步切到主线程执行 UI 操作，确保 request handler 的行为与 AppKit 一致。
        let handler = onOpenRequest
        let result: AttoIpcOpenResult = runOnMainSync {
            handler(req)
        }

        let pendingSet = Set(result.pendingTokens)

        if result.errors.isEmpty == false {
            NSLog("AttoEditor: ipc open request errors (id=%@): %@", req.requestID, result.errors.joined(separator: " | "))
        }
        NSLog(
            "AttoEditor: ipc open request handled (id=%@ pending=%d)",
            req.requestID,
            pendingSet.count
        )

        let ack = AttoIpcResponse(
            kind: .ack,
            requestID: req.requestID,
            ok: result.errors.isEmpty,
            errors: result.errors,
            pendingFileCount: pendingSet.count
        )

        if req.wait == false {
            _ = writeJSONLine(fd: fd, encodable: ack)
            close(fd)
            return
        }

        if pendingSet.isEmpty {
            _ = writeJSONLine(fd: fd, encodable: ack)
            let done = AttoIpcResponse(
                kind: .done,
                requestID: req.requestID,
                ok: result.errors.isEmpty,
                errors: result.errors,
                pendingFileCount: 0
            )
            _ = writeJSONLine(fd: fd, encodable: done)
            close(fd)
            return
        }

        // `--wait` 语义必须无竞态：先注册 session，再发 ack。
        sessionsQueue.sync { [weak self] in
            guard let self else { return }
            self.sessions[req.requestID] = WaitSession(
                requestID: req.requestID,
                fd: fd,
                pending: pendingSet,
                errors: result.errors
            )
        }
        _ = writeJSONLine(fd: fd, encodable: ack)
    }

    private func sendDoneAndClose(session: WaitSession) {
        let done = AttoIpcResponse(
            kind: .done,
            requestID: session.requestID,
            ok: session.errors.isEmpty,
            errors: session.errors,
            pendingFileCount: 0
        )
        _ = writeJSONLine(fd: session.fd, encodable: done)
        close(session.fd)
    }

    // MARK: - Spool (fire-and-forget CLI requests)

    private func startSpoolWatcher() {
        let dirPath = AttoIPC.spoolDirPath()
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: dirPath, isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        // 先处理一次，避免 “CLI 先落盘、server 后启动” 的竞态丢请求。
        processSpool()

        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }
        spoolFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: acceptQueue
        )
        source.setEventHandler { [weak self] in
            self?.processSpool()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.spoolFD >= 0 {
                close(self.spoolFD)
                self.spoolFD = -1
            }
        }
        spoolSource = source
        source.resume()
    }

    private func processSpool() {
        let dirURL = URL(fileURLWithPath: AttoIPC.spoolDirPath(), isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil
        ) else { return }

        let handler = onOpenRequest

        for url in items {
            guard url.lastPathComponent.hasPrefix("req-"), url.pathExtension.lowercased() == "json" else { continue }
            guard let data = try? Data(contentsOf: url) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard let req = try? JSONDecoder().decode(AttoIpcOpenRequest.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }

            _ = runOnMainSync {
                handler(req)
            }

            try? FileManager.default.removeItem(at: url)
        }
    }
}

// DispatchQueue 的 block 参数在 Swift 6 下是 `@Sendable`，这里的 server 仅在内部队列里自管理状态；
// 用 `@unchecked Sendable` 避免无意义的并发诊断噪音。
extension AttoIpcServer: @unchecked Sendable {}

// MARK: - Low-level IO

private func writeJSONLine<T: Encodable>(fd: Int32, encodable: T) -> Bool {
    guard let data = try? JSONEncoder().encode(encodable) else { return false }
    var out = data
    out.append(0x0A) // '\n'
    return writeAll(fd: fd, data: out)
}

private func writeAll(fd: Int32, data: Data) -> Bool {
    var offset = 0
    return data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return false }
        while offset < data.count {
            let ptr = base.advanced(by: offset)
            let n = Darwin.write(fd, ptr, data.count - offset)
            if n > 0 {
                offset += n
                continue
            }
            if n == 0 { return false }
            if errno == EINTR { continue }
            return false
        }
        return true
    }
}

private func readLine(fd: Int32, maxBytes: Int = 1_000_000) -> String? {
    // 注意：不能用“大块 read + 找 '\n' 后直接 return”的方式，
    // 因为同一个 read() 可能读到多行数据（例如 ack+done），后续内容会被丢掉，
    // 导致 `--wait` 永远等不到 done 或异常退出。
    //
    // 这里用 byte-wise read，确保不会 over-read。
    var bytes: [UInt8] = []
    bytes.reserveCapacity(min(256, maxBytes))

    var sawNewline = false

    while bytes.count < maxBytes {
        var c: UInt8 = 0
        let n = Darwin.read(fd, &c, 1)
        if n == 1 {
            if c == 0x0A {
                sawNewline = true
                break
            }
            bytes.append(c)
            continue
        }
        if n == 0 {
            break
        }
        if errno == EINTR {
            continue
        }
        return nil
    }

    if bytes.isEmpty {
        return sawNewline ? "" : nil
    }

    return String(bytes: bytes, encoding: .utf8)
}

private func runOnMainSync<T: Sendable>(_ operation: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { operation() }
    }
    return DispatchQueue.main.sync {
        MainActor.assumeIsolated { operation() }
    }
}
