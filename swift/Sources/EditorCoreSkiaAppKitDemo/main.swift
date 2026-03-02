import AppKit
import EditorCoreAppKit
import EditorCoreUIFFI
import Foundation

private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
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
            // - 中文输入（marked text / commit text）
            // - Cmd-Z / Cmd-Shift-Z（undo/redo）
            //
            // TODO：
            // - StyleId -> Theme 映射（高亮/折叠/诊断渲染）
            // - GPU 后端（Metal）与增量重绘
            """

            let editorView = try EditorCoreSkiaView(library: library, initialText: initialText, viewportWidthCells: 120)

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

