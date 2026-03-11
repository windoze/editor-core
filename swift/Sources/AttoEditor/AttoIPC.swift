import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum AttoIPC {
    // 内部启动参数：CLI 用它来启动 GUI/Server 进程。
    static let internalServerFlag = "--atto-editor-internal-server"
    static let internalNoDefaultWindowFlag = "--atto-editor-internal-no-default-window"

    static func socketPath() -> String {
        // Unix domain socket 路径长度有限（通常 104/108 bytes）。放到 /tmp 并带上 uid，避免冲突。
        "/tmp/codes.unwritten.attoeditor.\(getuid()).sock"
    }

    static func spoolDirPath() -> String {
        "/tmp/codes.unwritten.attoeditor.\(getuid()).spool"
    }
}

struct AttoIpcFileRequest: Codable, Equatable {
    var path: String
    var line1: Int?
    var column1: Int?
}

struct AttoIpcOpenRequest: Codable, Equatable {
    var requestID: String
    var newWindow: Bool
    var wait: Bool
    var directories: [String]
    var files: [AttoIpcFileRequest]
}

struct AttoIpcResponse: Codable, Equatable {
    enum Kind: String, Codable {
        case ack
        case done
    }

    var kind: Kind
    var requestID: String
    var ok: Bool
    var errors: [String]
    var pendingFileCount: Int
}

struct AttoIpcOpenResult: Equatable {
    var pendingFiles: [URL]
    var errors: [String]

    static var empty: AttoIpcOpenResult { .init(pendingFiles: [], errors: []) }
}

// MARK: - Client

enum AttoIpcClient {
    static func sendOpenRequest(
        _ request: AttoIpcOpenRequest,
        executablePath: String,
        connectTimeoutMs: Int = 1500
    ) -> Int32 {
        let socketPath = AttoIPC.socketPath()

        if let fd = connect(socketPath: socketPath) {
            _ = writeJSONLine(fd: fd, encodable: request)
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

        _ = writeJSONLine(fd: fd, encodable: request)
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
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
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

final class AttoIpcServer {
    struct StartResult {
        var isPrimaryInstance: Bool
    }

    private struct WaitSession {
        var requestID: String
        var fd: Int32
        var pending: Set<URL>
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

    init(
        socketPath: String = AttoIPC.socketPath(),
        onOpenRequest: @escaping @MainActor (AttoIpcOpenRequest) -> AttoIpcOpenResult
    ) {
        self.socketPath = socketPath
        self.onOpenRequest = onOpenRequest
    }

    func start() -> StartResult {
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

    func stop() {
        listenerSource?.cancel()
        listenerSource = nil

        spoolSource?.cancel()
        spoolSource = nil
    }

    /// 当某个文件在“所有窗口里都不再打开”时调用（由 AppDelegate 负责判断）。
    func notifyFileFullyClosed(_ url: URL) {
        let u = url.standardizedFileURL
        sessionsQueue.async { [weak self] in
            guard let self else { return }

            var finished: [WaitSession] = []
            for (id, var s) in self.sessions {
                if s.pending.contains(u) {
                    s.pending.remove(u)
                    self.sessions[id] = s
                }
                if s.pending.isEmpty {
                    finished.append(s)
                }
            }

            for s in finished {
                self.sessions.removeValue(forKey: s.requestID)
                self.sendDoneAndClose(session: s)
            }
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

        // 同步切到主线程执行 UI 操作，确保 request handler 的行为与 AppKit 一致。
        let handler = onOpenRequest
        let result: AttoIpcOpenResult = runOnMainSync {
            handler(req)
        }

        let pendingSet = Set(result.pendingFiles.map(\.standardizedFileURL))

        let ack = AttoIpcResponse(
            kind: .ack,
            requestID: req.requestID,
            ok: result.errors.isEmpty,
            errors: result.errors,
            pendingFileCount: pendingSet.count
        )
        _ = writeJSONLine(fd: fd, encodable: ack)

        if req.wait == false {
            close(fd)
            return
        }

        if pendingSet.isEmpty {
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

        sessionsQueue.async { [weak self] in
            guard let self else {
                close(fd)
                return
            }
            self.sessions[req.requestID] = WaitSession(
                requestID: req.requestID,
                fd: fd,
                pending: pendingSet,
                errors: result.errors
            )
        }
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
    var buf = [UInt8](repeating: 0, count: 4096)
    var data = Data()
    while data.count < maxBytes {
        let n = Darwin.read(fd, &buf, buf.count)
        if n > 0 {
            data.append(buf, count: n)
            if let idx = data.firstIndex(of: 0x0A) {
                let line = data.prefix(upTo: idx)
                return String(data: line, encoding: .utf8)
            }
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
    if data.isEmpty { return nil }
    return String(data: data, encoding: .utf8)
}

private func runOnMainSync<T: Sendable>(_ operation: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { operation() }
    }
    return DispatchQueue.main.sync {
        MainActor.assumeIsolated { operation() }
    }
}
