import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation

@MainActor
private final class DemoSearchPanelController: NSObject, NSTextFieldDelegate, NSSearchFieldDelegate {
    private unowned let editCore: EditCoreUI
    private let searchField: NSSearchField
    private let replaceField: NSTextField
    private let matchCountLabel: NSTextField
    private let caseSensitiveButton: NSButton
    private let wholeWordButton: NSButton
    private let regexButton: NSButton

    init(
        editCore: EditCoreUI,
        searchField: NSSearchField,
        replaceField: NSTextField,
        matchCountLabel: NSTextField,
        caseSensitiveButton: NSButton,
        wholeWordButton: NSButton,
        regexButton: NSButton
    ) {
        self.editCore = editCore
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
                try editCore.editor.clearSearchQuery()
                setMatchCountLabel(0)
            } else {
                let count = try editCore.editor.setSearchQuery(query, options: currentOptions())
                setMatchCountLabel(count)
            }
            editCore.editorView.needsDisplay = true
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
            let ok = try editCore.editor.findNext(query, options: currentOptions())
            if ok == false { NSSound.beep() }
            editCore.editorView.needsDisplay = true
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
            let ok = try editCore.editor.findPrev(query, options: currentOptions())
            if ok == false { NSSound.beep() }
            editCore.editorView.needsDisplay = true
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
            _ = try editCore.editor.replaceCurrent(query: query, replacement: replacement, options: currentOptions())
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
            _ = try editCore.editor.replaceAll(query: query, replacement: replacement, options: currentOptions())
            refreshSearchHighlights()
        } catch {
            NSSound.beep()
        }
    }
}

@MainActor
private final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var searchPanelController: DemoSearchPanelController?
    private weak var editCore: EditCoreUI?

    @objc private func minimapToggled(_ sender: NSButton) {
        editCore?.showsMinimap = sender.state == .on
    }

    @objc private func minimapPlacementChanged(_ sender: NSSegmentedControl) {
        let placement: EditorCoreSkiaMinimapPlacement = sender.selectedSegment == 0 ? .leftOfScrollbar : .rightOfScrollbar
        editCore?.minimapPlacement = placement
    }

    @objc private func caretBlinkToggled(_ sender: NSButton) {
        editCore?.caretBlinkEnabled = sender.state == .on
    }

    @objc private func caretBlinkSpeedChanged(_ sender: NSSlider) {
        editCore?.caretBlinkIntervalSeconds = sender.doubleValue
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let library = EditorCoreUIFFILibrary()

            // Demo: open a real Rust source file from this repo so LSP can provide real semantic
            // tokens / inlay hints / diagnostics.
            let repoRootURL = URL(fileURLWithPath: #file)
                .deletingLastPathComponent() // EditCoreUIDemo
                .deletingLastPathComponent() // Sources
                .deletingLastPathComponent() // swift
                .deletingLastPathComponent() // repo root

            let demoFileURL = repoRootURL.appendingPathComponent("editor-core/crates/tui-editor/src/main.rs")
            let initialText = (try? String(contentsOf: demoFileURL, encoding: .utf8)) ?? """
            // Failed to load demo file:
            // \(demoFileURL.path)
            //
            // Please open `crates/tui-editor/src/main.rs` manually.
            """
            let lspRootURI = repoRootURL.absoluteString
            let lspDocURI = demoFileURL.absoluteString

            let fontFamiliesCSV = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_FONT_FAMILIES"]
            let editCore = try EditCoreUI(
                library: library,
                initialText: initialText,
                viewportWidthCells: 120,
                fontFamiliesCSV: fontFamiliesCSV,
                showsMinimap: true,
                minimapPlacement: .rightOfScrollbar
            )
            self.editCore = editCore
            if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_ENABLE_LIGATURES"] == "1" {
                try editCore.editor.setFontLigaturesEnabled(true)
            }
            // Demo: enable LSP (rust-analyzer) by default; fall back to Tree-sitter if unavailable.
            let disableLSP = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DISABLE_LSP"] == "1"
            var lspEnabled = false
            if disableLSP == false {
                do {
                    let cmd = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_LSP_CMD"] ?? "rust-analyzer"
                    let args = ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_LSP_ARGS"]
                    try editCore.editor.lspEnable(
                        command: cmd,
                        args: args,
                        rootURI: lspRootURI,
                        documentURI: lspDocURI,
                        languageId: "rust"
                    )
                    lspEnabled = true
                    editCore.alwaysPollProcessing = true
                } catch {
                    NSLog("EditCoreUIDemo: failed to enable LSP: %@", String(describing: error))
                    lspEnabled = false
                }
            }

            if lspEnabled == false {
                // Demo: enable Tree-sitter (Rust) for highlighting + folding regions.
                //
                // 性能排查时可通过 `EDITOR_CORE_APPKIT_DISABLE_TREESITTER=1` 关闭，帮助定位“输入变更很慢”是否来自 processor。
                if ProcessInfo.processInfo.environment["EDITOR_CORE_APPKIT_DISABLE_TREESITTER"] != "1" {
                    try editCore.editor.treeSitterRustEnableDefault()
                } else {
                    NSLog("EditCoreUIDemo: Tree-sitter disabled by EDITOR_CORE_APPKIT_DISABLE_TREESITTER=1")
                }
            } else {
                // Avoid mixed highlighting: when LSP is active, Tree-sitter highlighting is not needed.
                editCore.editor.treeSitterDisable()
            }

            // Demo: theme system (StyleId -> colors + text decorations).
            //
            // `demoRustLspDark()` includes:
            // - semantic token colors (LSP)
            // - inlay hint / code lens virtual text styling
            // - diagnostics squiggly underline
            let theme = EditorCoreSkiaTheme.demoRustLspDark()
            try editCore.applyTheme(theme)
            // Demo: show whitespace (selection-only) + indent guides by default for easier theme/renderer validation.
            try editCore.editor.setWhitespaceRenderMode(.selection)
            try editCore.editor.setIndentGuidesEnabled(true)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "EditCoreUIDemo (\(demoFileURL.lastPathComponent))"

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

            let hoverLabel = NSTextField(labelWithString: "Hover: -")
            hoverLabel.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            hoverLabel.lineBreakMode = .byTruncatingMiddle
            hoverLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let minimapToggle = NSButton(checkboxWithTitle: "Minimap", target: nil, action: nil)
            minimapToggle.state = .on
            minimapToggle.setButtonType(.switch)

            let minimapPlacement = NSSegmentedControl(labels: ["Mini L", "Mini R"], trackingMode: .selectOne, target: nil, action: nil)
            minimapPlacement.selectedSegment = 1

            let caretBlinkToggle = NSButton(checkboxWithTitle: "Caret Blink", target: nil, action: nil)
            caretBlinkToggle.state = .on
            caretBlinkToggle.setButtonType(.switch)

            let caretBlinkSpeed = NSSlider(value: 0.55, minValue: 0.15, maxValue: 1.2, target: nil, action: nil)
            caretBlinkSpeed.controlSize = .small
            caretBlinkSpeed.isContinuous = true
            NSLayoutConstraint.activate([caretBlinkSpeed.widthAnchor.constraint(equalToConstant: 120)])

            let caretBlinkSpeedLabel = NSTextField(labelWithString: "Speed")
            caretBlinkSpeedLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

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
                hoverLabel,
                minimapToggle,
                minimapPlacement,
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

            let appearanceRow = NSStackView(views: [
                caretBlinkToggle,
                caretBlinkSpeedLabel,
                caretBlinkSpeed,
            ])
            appearanceRow.orientation = .horizontal
            appearanceRow.alignment = .centerY
            appearanceRow.spacing = 8

            let toolbar = NSStackView(views: [searchRow, replaceRow, appearanceRow])
            toolbar.orientation = .vertical
            toolbar.alignment = .leading
            toolbar.spacing = 6
            toolbar.translatesAutoresizingMaskIntoConstraints = false

            minimapToggle.target = self
            minimapToggle.action = #selector(minimapToggled(_:))
            minimapPlacement.target = self
            minimapPlacement.action = #selector(minimapPlacementChanged(_:))
            caretBlinkToggle.target = self
            caretBlinkToggle.action = #selector(caretBlinkToggled(_:))
            caretBlinkSpeed.target = self
            caretBlinkSpeed.action = #selector(caretBlinkSpeedChanged(_:))

            let container = NSView(frame: .zero)
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(toolbar)
            container.addSubview(editCore)
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                toolbar.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
                toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),

                editCore.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                editCore.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                editCore.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
                editCore.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            let searchController = DemoSearchPanelController(
                editCore: editCore,
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

            // Demo: hover info (line/column + optional document link marker).
            editCore.onHover = { [weak hoverLabel] info in
                let line = Int(info.logicalLine) + 1
                let col = Int(info.logicalColumn) + 1
                let linkMark = info.documentLinkJSON != nil ? " [link]" : ""
                hoverLabel?.stringValue = "Hover: \(line):\(col) off=\(info.charOffset)\(linkMark)"
            }
            editCore.onHoverExit = { [weak hoverLabel] in
                hoverLabel?.stringValue = "Hover: -"
            }

            window.contentView = container
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editCore.editorView)

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

@main
struct EditCoreUIDemoMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = DemoAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
