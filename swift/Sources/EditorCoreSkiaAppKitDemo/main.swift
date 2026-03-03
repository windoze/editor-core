import AppKit
import EditorCoreAppKit
import EditorCoreUIFFI
import Foundation

private enum DemoBuildSupport {
    static func ensureEditorCoreUIFFIBuiltIfUsingRepoCheckout() throws {
        // If the user explicitly points to a dylib, don't second-guess them.
        if ProcessInfo.processInfo.environment["EDITOR_CORE_UI_FFI_DYLIB_PATH"] != nil {
            return
        }
        // Allow skipping for debugging.
        if ProcessInfo.processInfo.environment["EDITOR_CORE_UI_FFI_SKIP_CARGO_BUILD"] == "1" {
            return
        }
        guard let repoRoot = locateRepoRoot() else {
            // Probably running from an installed build; nothing to do.
            return
        }

        try requireCargo()

        let build = try runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["cargo", "build", "-p", "editor-core-ui-ffi"],
            currentDirectory: repoRoot
        )
        guard build.exitCode == 0 else {
            throw NSError(
                domain: "EditorCoreSkiaAppKitDemo",
                code: Int(build.exitCode),
                userInfo: [
                    NSLocalizedDescriptionKey: "cargo build -p editor-core-ui-ffi 失败",
                    NSLocalizedFailureReasonErrorKey: "\(build.stderr)\n\(build.stdout)",
                ]
            )
        }
    }

    private static func locateRepoRoot() -> String? {
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

    private static func requireCargo() throws {
        let result = try runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["which", "cargo"],
            currentDirectory: FileManager.default.currentDirectoryPath
        )
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "EditorCoreSkiaAppKitDemo",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "cargo 不可用，无法构建 editor-core-ui-ffi。"]
            )
        }
    }

    private static func runProcess(
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
}

private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try DemoBuildSupport.ensureEditorCoreUIFFIBuiltIfUsingRepoCheckout()
            let library = try EditorCoreUIFFILibrary()

            let initialText = """
            // EditorCoreSkiaAppKitDemo
            //
            // 这是一个自绘版 demo：
            // - Rust: editor-core + editor-core-ui + Skia（输出 RGBA buffer）
            // - Swift/AppKit: NSView + NSTextInputClient（IME）+ 把 RGBA 贴到屏幕
            //
            // 支持：
            // - 输入/删除/选区（鼠标拖拽）
            // - 多光标：Cmd+Click
            // - 矩形选择：Option+Drag
            // - Shift+方向键扩选
            // - gutter（行号 + 折叠标记），点击 gutter 折叠/展开
            // - 中文输入（marked text / commit text）
            // - Cmd-Z / Cmd-Shift-Z（undo/redo）
            //
            // TODO：
            // - 更完整的主题系统（StyleId -> Theme 映射）
            // - GPU 后端（Metal）与增量重绘
            //
            // 下面是一段 Rust 代码（用于 Tree-sitter folds 演示，需 host 启用 Tree-sitter）：
            fn main() {
              if true {
                println!("hello");
              }
            }
            """

            let editorView = try EditorCoreSkiaView(library: library, initialText: initialText, viewportWidthCells: 120)
            // Demo: enable Tree-sitter (Rust) for highlighting + folding regions.
            try editorView.editor.treeSitterRustEnableDefault()

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "EditorCoreSkiaAppKitDemo"

            let container = NSView(frame: .zero)
            container.translatesAutoresizingMaskIntoConstraints = false
            editorView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(editorView)
            NSLayoutConstraint.activate([
                editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                editorView.topAnchor.constraint(equalTo: container.topAnchor),
                editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            window.contentView = container
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editorView)

            NSApp.activate(ignoringOtherApps: true)
            self.window = window
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "无法加载 editor-core-ui-ffi 动态库"
            alert.informativeText = """
            错误：
            \(error)

            解决方法（在仓库根目录）：
              cargo build -p editor-core-ui-ffi

            或设置环境变量：
              EDITOR_CORE_UI_FFI_DYLIB_PATH=/path/to/libeditor_core_ui_ffi.dylib
            """
            _ = alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct EditorCoreSkiaAppKitDemoMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = DemoAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
