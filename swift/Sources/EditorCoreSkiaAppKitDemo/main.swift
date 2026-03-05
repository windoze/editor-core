import AppKit
import EditorCoreAppKit
import EditorCoreUIFFI
import Foundation

@MainActor
private final class DemoSearchPanelController: NSObject, NSTextFieldDelegate, NSSearchFieldDelegate {
    private unowned let editorView: EditorCoreSkiaView
    private let searchField: NSSearchField
    private let replaceField: NSTextField
    private let matchCountLabel: NSTextField
    private let caseSensitiveButton: NSButton
    private let wholeWordButton: NSButton
    private let regexButton: NSButton

    init(
        editorView: EditorCoreSkiaView,
        searchField: NSSearchField,
        replaceField: NSTextField,
        matchCountLabel: NSTextField,
        caseSensitiveButton: NSButton,
        wholeWordButton: NSButton,
        regexButton: NSButton
    ) {
        self.editorView = editorView
        self.searchField = searchField
        self.replaceField = replaceField
        self.matchCountLabel = matchCountLabel
        self.caseSensitiveButton = caseSensitiveButton
        self.wholeWordButton = wholeWordButton
        self.regexButton = regexButton
        super.init()

        searchField.delegate = self
        replaceField.delegate = self
    }

    private func currentOptions() -> EcuSearchOptions {
        EcuSearchOptions(
            caseSensitive: caseSensitiveButton.state == .on,
            wholeWord: wholeWordButton.state == .on,
            regex: regexButton.state == .on
        )
    }

    private func setMatchCountLabel(_ count: UInt32) {
        matchCountLabel.stringValue = "\(count) matches"
    }

    private func refreshSearchHighlights() {
        do {
            let query = searchField.stringValue
            if query.isEmpty {
                try editorView.editor.clearSearchQuery()
                setMatchCountLabel(0)
            } else {
                let count = try editorView.editor.setSearchQuery(query, options: currentOptions())
                setMatchCountLabel(count)
            }
            editorView.needsDisplay = true
        } catch {
            NSSound.beep()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshSearchHighlights()
    }

    @objc func optionChanged(_ sender: Any) {
        refreshSearchHighlights()
    }

    @objc func clearClicked(_ sender: Any) {
        searchField.stringValue = ""
        refreshSearchHighlights()
    }

    @objc func findNextClicked(_ sender: Any) {
        do {
            let query = searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try editorView.editor.findNext(query, options: currentOptions())
            if ok == false { NSSound.beep() }
            editorView.needsDisplay = true
        } catch {
            NSSound.beep()
        }
    }

    @objc func findPrevClicked(_ sender: Any) {
        do {
            let query = searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let ok = try editorView.editor.findPrev(query, options: currentOptions())
            if ok == false { NSSound.beep() }
            editorView.needsDisplay = true
        } catch {
            NSSound.beep()
        }
    }

    @objc func replaceCurrentClicked(_ sender: Any) {
        do {
            let query = searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = replaceField.stringValue
            _ = try editorView.editor.replaceCurrent(query: query, replacement: replacement, options: currentOptions())
            refreshSearchHighlights()
        } catch {
            NSSound.beep()
        }
    }

    @objc func replaceAllClicked(_ sender: Any) {
        do {
            let query = searchField.stringValue
            guard query.isEmpty == false else {
                NSSound.beep()
                return
            }
            let replacement = replaceField.stringValue
            _ = try editorView.editor.replaceAll(query: query, replacement: replacement, options: currentOptions())
            refreshSearchHighlights()
        } catch {
            NSSound.beep()
        }
    }
}

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
    private var searchPanelController: DemoSearchPanelController?

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
            // - 双击拖拽：按 word 扩展选区
            // - 三击拖拽：按 line 扩展选区
            // - Shift+方向键扩选
            // - gutter（行号 + 折叠标记），点击 gutter 折叠/展开
            // - 中文输入（marked text / commit text）
            // - Cmd-Z / Cmd-Shift-Z（undo/redo）
            // - 搜索/替换：窗口顶部（match highlights overlay）
            // - Cmd+Click 打开 DocumentLink（演示链接：https://example.com）
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

            let fontFamiliesCSV = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_FONT_FAMILIES"]
            let editorView = try EditorCoreSkiaView(
                library: library,
                initialText: initialText,
                viewportWidthCells: 120,
                fontFamiliesCSV: fontFamiliesCSV
            )
            if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_ENABLE_LIGATURES"] == "1" {
                try editorView.editor.setFontLigaturesEnabled(true)
            }
            // Demo: enable Tree-sitter (Rust) for highlighting + folding regions.
            try editorView.editor.treeSitterRustEnableDefault()

            // Demo: style colors for reserved overlay IDs.
            // - LSP document links underline: 0x0800_0003
            // - Search match highlights: 0x0800_0004
            try editorView.editor.setStyleColors([
                EcuStyleColors(styleId: 0x0800_0003, foreground: EcuRgba8(r: 0x00, g: 0x66, b: 0xCC, a: 0xFF)),
                EcuStyleColors(styleId: 0x0800_0004, background: EcuRgba8(r: 0xFF, g: 0xF3, b: 0xB0, a: 0xFF)),
            ])

            // Demo: inject a single LSP DocumentLink so Cmd+Click can open it.
            // We compute the UTF-16 range programmatically to avoid off-by-one mistakes.
            do {
                let urlText = "https://example.com"
                if let link = DemoLspJSON.makeSingleDocumentLinkJSON(text: initialText, target: urlText) {
                    try editorView.editor.lspApplyDocumentLinksJSON(link)
                }
            }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "EditorCoreSkiaAppKitDemo"

            let searchField = NSSearchField(frame: .zero)
            searchField.placeholderString = "Find"
            searchField.controlSize = .small
            searchField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            searchField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([searchField.widthAnchor.constraint(equalToConstant: 220)])

            let replaceField = NSTextField(frame: .zero)
            replaceField.placeholderString = "Replace"
            replaceField.controlSize = .small
            replaceField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            replaceField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([replaceField.widthAnchor.constraint(equalToConstant: 180)])

            let caseSensitive = NSButton(checkboxWithTitle: "Aa", target: nil, action: nil)
            caseSensitive.state = .on
            caseSensitive.setButtonType(.switch)
            let wholeWord = NSButton(checkboxWithTitle: "Word", target: nil, action: nil)
            wholeWord.setButtonType(.switch)
            let regex = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
            regex.setButtonType(.switch)

            let matchCountLabel = NSTextField(labelWithString: "0 matches")
            matchCountLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

            let findPrev = NSButton(title: "Prev", target: nil, action: nil)
            findPrev.bezelStyle = .rounded
            let findNext = NSButton(title: "Next", target: nil, action: nil)
            findNext.bezelStyle = .rounded
            let clear = NSButton(title: "Clear", target: nil, action: nil)
            clear.bezelStyle = .rounded

            let replaceCurrent = NSButton(title: "Replace", target: nil, action: nil)
            replaceCurrent.bezelStyle = .rounded
            let replaceAll = NSButton(title: "Replace All", target: nil, action: nil)
            replaceAll.bezelStyle = .rounded

            let searchRow = NSStackView(views: [
                NSTextField(labelWithString: "Find:"),
                searchField,
                caseSensitive,
                wholeWord,
                regex,
                matchCountLabel,
                findPrev,
                findNext,
                clear,
            ])
            searchRow.orientation = .horizontal
            searchRow.alignment = .centerY
            searchRow.spacing = 8
            searchRow.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

            let replaceRow = NSStackView(views: [
                NSTextField(labelWithString: "Replace:"),
                replaceField,
                replaceCurrent,
                replaceAll,
            ])
            replaceRow.orientation = .horizontal
            replaceRow.alignment = .centerY
            replaceRow.spacing = 8

            let toolbar = NSStackView(views: [searchRow, replaceRow])
            toolbar.orientation = .vertical
            toolbar.alignment = .leading
            toolbar.spacing = 6
            toolbar.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView(frame: .zero)
            container.translatesAutoresizingMaskIntoConstraints = false
            editorView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(toolbar)
            container.addSubview(editorView)
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                toolbar.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),

                editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                editorView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
                editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            let searchController = DemoSearchPanelController(
                editorView: editorView,
                searchField: searchField,
                replaceField: replaceField,
                matchCountLabel: matchCountLabel,
                caseSensitiveButton: caseSensitive,
                wholeWordButton: wholeWord,
                regexButton: regex
            )
            caseSensitive.target = searchController
            caseSensitive.action = #selector(DemoSearchPanelController.optionChanged(_:))
            wholeWord.target = searchController
            wholeWord.action = #selector(DemoSearchPanelController.optionChanged(_:))
            regex.target = searchController
            regex.action = #selector(DemoSearchPanelController.optionChanged(_:))
            clear.target = searchController
            clear.action = #selector(DemoSearchPanelController.clearClicked(_:))
            findNext.target = searchController
            findNext.action = #selector(DemoSearchPanelController.findNextClicked(_:))
            findPrev.target = searchController
            findPrev.action = #selector(DemoSearchPanelController.findPrevClicked(_:))
            replaceCurrent.target = searchController
            replaceCurrent.action = #selector(DemoSearchPanelController.replaceCurrentClicked(_:))
            replaceAll.target = searchController
            replaceAll.action = #selector(DemoSearchPanelController.replaceAllClicked(_:))

            // Demo: prefill a query so match highlights are visible immediately.
            searchField.stringValue = "println"
            searchController.optionChanged(self)
            self.searchPanelController = searchController

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

private enum DemoLspJSON {
    /// Build a JSON array with a single `DocumentLink` for the first occurrence of `target` in `text`.
    ///
    /// The range is reported in UTF-16 code units (LSP style).
    static func makeSingleDocumentLinkJSON(text: String, target: String) -> String? {
        let ns = text as NSString
        let range = ns.range(of: target)
        guard range.location != NSNotFound, range.length > 0 else { return nil }

        let prefix = ns.substring(to: range.location)
        let lines = prefix.components(separatedBy: "\n")
        let line = max(0, lines.count - 1)
        let colStart = lines.last?.utf16.count ?? 0
        let colEnd = colStart + range.length

        return """
        [
          {
            "range": {
              "start": { "line": \(line), "character": \(colStart) },
              "end":   { "line": \(line), "character": \(colEnd) }
            },
            "target": "\(target)"
          }
        ]
        """
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
