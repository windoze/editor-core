import Foundation

/// AttoEditor 命令行参数解析（用于启动时决定打开哪些窗口/文件）。
///
/// 约定：
/// - 支持 `-n/--new-window`：文件参数总是在新窗口打开（目录参数本来就总是新窗口）。
/// - 支持 `-w/--wait`：当通过命令行打开的文件全部关闭后，应用自动退出。
/// - 支持 `-h/--help`：打印用法说明并退出。
/// - 支持 `--`：之后的参数一律按路径处理（不再解析成 option）。
/// - 支持文件定位：`/path/to/file:<line>[:<column>]`（line/column 为 1-based）。
package enum AttoCommandLine {
    /// `atto -h/--help` 输出的用法说明。
    package static let usageText = """
    Usage: atto [options] [file[:line[:column]] | directory ...]

    Options:
      -n, --new-window   文件总是在新窗口打开（目录参数本来就会打开新窗口）
      -w, --wait         等待：当本次打开的文件全部关闭后退出（退出码反映打开结果）
      -h, --help         显示本说明并退出
      --                 之后的参数一律按路径处理（不再解析成 option）

    Examples:
      atto file.txt
      atto file.txt:10:5
      atto -n a.txt b.txt
      atto -w note.md
      atto -- -name-starting-with-dash.txt
    """

    package struct FileLocation: Equatable {
        package let line1: Int
        package let column1: Int?

        package init(line1: Int, column1: Int?) {
            self.line1 = line1
            self.column1 = column1
        }
    }

    package struct FileOpenRequest: Equatable {
        package let url: URL
        package let location: FileLocation?

        package init(url: URL, location: FileLocation?) {
            self.url = url
            self.location = location
        }
    }

    package struct Parsed: Equatable {
        package var newWindow: Bool = false
        package var wait: Bool = false
        package var helpRequested: Bool = false
        package var directories: [URL] = []
        package var files: [FileOpenRequest] = []

        package init(
            newWindow: Bool = false,
            wait: Bool = false,
            helpRequested: Bool = false,
            directories: [URL] = [],
            files: [FileOpenRequest] = []
        ) {
            self.newWindow = newWindow
            self.wait = wait
            self.helpRequested = helpRequested
            self.directories = directories
            self.files = files
        }
    }

    package static func parse(
        arguments: [String],
        fileManager: FileManager = .default,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> Parsed {
        var out = Parsed()

        // argv[0] 是可执行文件路径；对业务无意义。
        let args = Array(arguments.dropFirst())

        var treatRemainingAsPaths = false
        for raw in args {
            if treatRemainingAsPaths == false {
                if raw == "--" {
                    treatRemainingAsPaths = true
                    continue
                }
                if raw == "-n" || raw == "--new-window" {
                    out.newWindow = true
                    continue
                }
                if raw == "-w" || raw == "--wait" {
                    out.wait = true
                    continue
                }
                if raw == "-h" || raw == "--help" {
                    out.helpRequested = true
                    continue
                }
            }

            let (pathPart, location) = parsePathAndLocation(raw)
            let url = normalizePathToFileURL(pathPart, currentDirectoryURL: currentDirectoryURL)

            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                out.directories.append(url.standardizedFileURL)
            } else {
                out.files.append(.init(url: url.standardizedFileURL, location: location))
            }
        }

        return out
    }

    // MARK: - Parsing helpers

    private static func normalizePathToFileURL(_ path: String, currentDirectoryURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: path, relativeTo: currentDirectoryURL).standardizedFileURL
    }

    /// 将 `path[:line[:column]]` 解析成 `(path, location)`。
    private static func parsePathAndLocation(_ raw: String) -> (path: String, location: FileLocation?) {
        // 从末尾向前尝试提取 `:<digits>` 段。最多提取 2 段（line/column）。
        var comps = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard comps.count >= 2 else { return (raw, nil) }

        func parsePositiveInt(_ s: String) -> Int? {
            guard s.isEmpty == false else { return nil }
            guard let v = Int(s), v > 0 else { return nil }
            return v
        }

        var column1: Int?
        var line1: Int?

        if let last = comps.last, let v = parsePositiveInt(last) {
            // 先当作 `line`（只有一个数字时）。
            line1 = v
            comps.removeLast()

            // 再尝试提取第二个数字（作为 `line`，原来的变成 column）。
            if let secondLast = comps.last, let v2 = parsePositiveInt(secondLast) {
                column1 = line1
                line1 = v2
                comps.removeLast()
            }
        }

        guard let line1 else { return (raw, nil) }
        let path = comps.joined(separator: ":")
        if path.isEmpty {
            return (raw, nil)
        }
        return (path, FileLocation(line1: line1, column1: column1))
    }
}
