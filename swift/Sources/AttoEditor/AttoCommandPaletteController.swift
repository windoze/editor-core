import AppKit
import Foundation

struct AttoCommandPaletteCommand {
    let title: String
    let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.title = title
        self.run = run
    }
}

@MainActor
final class AttoCommandPaletteController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let commandsProvider: () -> [AttoCommandPaletteCommand]

    private var panel: NSPanel?
    private let searchField = NSSearchField(frame: .zero)
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    private var allCommands: [AttoCommandPaletteCommand] = []
    private var filteredCommands: [AttoCommandPaletteCommand] = []

    init(commandsProvider: @escaping () -> [AttoCommandPaletteCommand]) {
        self.commandsProvider = commandsProvider
        super.init()
    }

    func show(relativeTo window: NSWindow, placeholder: String = "Type a command…") {
        if panel == nil {
            panel = buildPanel()
        }

        searchField.placeholderString = placeholder
        searchField.stringValue = ""

        allCommands = commandsProvider()
        applyFilter()

        guard let panel else { return }
        position(panel: panel, relativeTo: window)

        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    // MARK: - Panel

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.cornerRadius = 8
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        searchField.placeholderString = "Type a command…"
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        col.title = "Command"
        col.width = 600
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(searchField)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])

        return panel
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width: CGFloat = 640
        let height: CGFloat = 360

        let winFrame = window.frame
        var x = winFrame.midX - width / 2
        var y = winFrame.maxY - height - 120

        // Clamp to visible frame.
        let visible = screen.visibleFrame
        x = max(visible.minX + 20, min(x, visible.maxX - width - 20))
        y = max(visible.minY + 20, min(y, visible.maxY - height - 20))

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: - Filtering

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            filteredCommands = allCommands
        } else {
            let scored = allCommands.compactMap { cmd -> (AttoCommandPaletteCommand, Int)? in
                guard let score = AttoFuzzy.score(candidate: cmd.title, query: q) else { return nil }
                return (cmd, score)
            }
            filteredCommands = scored
                .sorted { a, b in
                    if a.1 == b.1 {
                        return a.0.title.localizedCaseInsensitiveCompare(b.0.title) == .orderedAscending
                    }
                    return a.1 > b.1
                }
                .map(\.0)
        }
        tableView.reloadData()

        if filteredCommands.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - TableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredCommands.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredCommands.count else { return nil }
        let cmd = filteredCommands[row]

        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor(attoHex: 0xD4D4D4)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        if cell.textField == nil {
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        label.stringValue = cmd.title
        return cell
    }

    @objc private func doubleClicked(_ sender: Any?) {
        runSelectedCommand()
    }

    private func runSelectedCommand() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredCommands.count else { return }
        let cmd = filteredCommands[row]
        hide()
        cmd.run()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        case #selector(NSResponder.moveDown(_:)):
            let next = min(tableView.selectedRow + 1, filteredCommands.count - 1)
            if next >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                tableView.scrollRowToVisible(next)
            }
            return true
        case #selector(NSResponder.moveUp(_:)):
            let prev = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            tableView.scrollRowToVisible(prev)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            runSelectedCommand()
            return true
        default:
            return false
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // VSCode-like: dismiss palette when focus leaves it.
        hide()
    }
}

private enum AttoFuzzy {
    /// Returns a score when `query` matches `candidate` as a subsequence (case-insensitive).
    ///
    /// Higher is better.
    static func score(candidate: String, query: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return 0 }

        let cChars = Array(candidate.lowercased())
        let qChars = Array(q.lowercased())

        var score = 0
        var cIndex = 0
        var consecutive = 0
        var firstMatch: Int?

        func isBoundary(_ ch: Character) -> Bool {
            ch == "/" || ch == "\\" || ch == "_" || ch == "-" || ch == " " || ch == "."
        }

        for qc in qChars {
            while cIndex < cChars.count, cChars[cIndex] != qc {
                cIndex += 1
                consecutive = 0
            }
            if cIndex >= cChars.count {
                return nil
            }

            if firstMatch == nil {
                firstMatch = cIndex
            }

            score += 10
            score += consecutive * 6
            if cIndex == 0 || isBoundary(cChars[cIndex - 1]) {
                score += 4
            }

            consecutive += 1
            cIndex += 1
        }

        if let firstMatch {
            score -= min(firstMatch, 20)
        }
        return score
    }
}

private extension NSColor {
    convenience init(attoHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((attoHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((attoHex >> 8) & 0xFF) / 255.0
        let b = CGFloat(attoHex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
