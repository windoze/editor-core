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

private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var searchPanelController: DemoSearchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let library = EditorCoreUIFFILibrary()

            var initialText = """
            // EditorCoreSkiaAppKitDemo
            //
            // 这是一个自绘版 demo：
            // - Rust: editor-core + editor-core-ui + Skia（Metal/GPU 绘制到 MTLTexture）
            // - Swift/AppKit: MTKView + NSTextInputClient（IME）+ present CAMetalDrawable
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
            // - 增量重绘 / dirty rect（进一步降低每次输入的渲染成本）
            //
            // 下面是一段 Rust 代码（用于 Tree-sitter folds 演示，需 host 启用 Tree-sitter）：
            fn main() {
              if true {
                println!("hello");
              }
            }
            """
            // 让 demo 文档足够长，方便测试滚动条 / 平滑滚动 / “光标移出 viewport 自动滚动”等功能。
            let longLines = (0..<600).map { i -> String in
                // 同时混入 CJK + Emoji，方便验证多字体 fallback 与 grapheme 逻辑。
                //
                // 注意：demo 默认启用 Rust Tree-sitter，如果把大量非 Rust 文本直接塞进文档（不在注释里），
                // parser 需要做大量错误恢复，可能导致“每次输入都很慢”的错觉。
                // 这里把滚动压力测试内容放进 Rust 行注释，既保持可读性，又避免 Tree-sitter 进入 worst-case。
                if i % 40 == 0 {
                    return "// line \(String(format: "%04d", i)): 段落开始（下面有空行）🙂"
                }
                if i % 40 == 1 {
                    return ""
                }
                return "// line \(String(format: "%04d", i)): The quick brown fox jumps over the lazy dog. 你好，世界 😀"
            }
            initialText += "\n\n// --- Scroll Stress Test ---\n"
            initialText += longLines.joined(separator: "\n")
            initialText += "\n"

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
            //
            // 性能排查时可通过 `EDITOR_CORE_APPKIT_DISABLE_TREESITTER=1` 关闭，帮助定位“输入变更很慢”是否来自 processor。
            if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DISABLE_TREESITTER"] != "1" {
                try editorView.editor.treeSitterRustEnableDefault()
            } else {
                NSLog("EditorCoreSkiaAppKitDemo: Tree-sitter disabled by EDITOR_CORE_APPKIT_DISABLE_TREESITTER=1")
            }

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

            let scrollContainer = EditorCoreSkiaScrollContainer(editorView: editorView)

            let container = NSView(frame: .zero)
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(toolbar)
            container.addSubview(scrollContainer)
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                toolbar.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),

                scrollContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scrollContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scrollContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
                scrollContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
            alert.messageText = "初始化 editor-core-ui-ffi 失败"
            alert.informativeText = """
            错误：
            \(error)

            说明：
            - 当前 Swift 包使用静态链接（Rust `staticlib`），不再运行时加载 dylib。
            - 如果你在仓库内开发，请先在仓库根目录执行：
                cargo build -p editor-core-ffi -p editor-core-ui-ffi
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
