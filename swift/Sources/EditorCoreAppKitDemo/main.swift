import AppKit
import EditorCoreAppKit
import EditorCoreFFI
import Foundation

private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let library = try EditorCoreFFILibrary()

            let initialText = """
            // EditorCoreAppKitDemo
            //
            // 这是一个最小 AppKit demo：
            // - NSTextView 负责绘制与输入
            // - 输入会被拦截并转成 editor-core 的 edit/replace 命令
            // - editor-core 是真值，变更后回写 NSTextView.string
            //
            // 支持：
            // - 输入/删除/粘贴/选区替换
            // - Cmd-Z / Cmd-Shift-Z（undo/redo，走 editor-core）
            //
            // TODO：
            // - 使用 editor-core 的 viewport blob 做高性能渲染
            // - 同步 cursor/selection 到 editor-core（用于多光标/更准确的 undo selection）
            // - 高亮/折叠（Sublime/Tree-sitter/LSP）
            """

            let editor = try EditorCoreTextView(library: library, initialText: initialText, viewportWidth: 120)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "EditorCoreAppKitDemo"

            let container = NSView(frame: .zero)
            container.translatesAutoresizingMaskIntoConstraints = false
            editor.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(editor)
            NSLayoutConstraint.activate([
                editor.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                editor.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                editor.topAnchor.constraint(equalTo: container.topAnchor),
                editor.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            window.contentView = container
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor.textView)

            NSApp.activate(ignoringOtherApps: true)
            self.window = window
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "无法加载 editor-core-ffi 动态库"
            alert.informativeText = """
            错误：
            \(error)

            解决方法（在仓库根目录）：
              cargo build -p editor-core-ffi

            或设置环境变量：
              EDITOR_CORE_FFI_DYLIB_PATH=/path/to/libeditor_core_ffi.dylib
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
struct EditorCoreAppKitDemoMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = DemoAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
