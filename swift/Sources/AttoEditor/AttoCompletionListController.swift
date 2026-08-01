import AppKit
import Foundation

@MainActor
final class AttoCompletionListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private let tableView = AttoCompletionTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    private var items: [AttoLspCompletionParser.Item] = []
    private var onCommit: ((AttoLspCompletionParser.Item) -> Void)?

    func show(
        items: [AttoLspCompletionParser.Item],
        relativeTo editorView: NSView,
        anchorRect: NSRect,
        onCommit: @escaping (AttoLspCompletionParser.Item) -> Void
    ) {
        guard items.isEmpty == false else {
            hide()
            return
        }
        guard let parentWindow = editorView.window else { return }

        self.items = items
        self.onCommit = onCommit

        if panel == nil {
            panel = buildPanel()
        }

        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)

        guard let panel else { return }
        position(panel: panel, relativeTo: editorView, anchorRect: anchorRect, itemCount: items.count)
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(tableView)
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    private func buildPanel() -> NSPanel {
        let panel = AttoCompletionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.cornerRadius = 6
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        col.width = 420
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.onCommit = { [weak self] in
            self?.commitSelected()
        }
        tableView.onCancel = { [weak self] in
            self?.hide()
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        return panel
    }

    private func position(panel: NSPanel, relativeTo editorView: NSView, anchorRect: NSRect, itemCount: Int) {
        guard let window = editorView.window else { return }
        let screen = window.screen ?? NSScreen.main

        let width: CGFloat = 440
        let height = min(CGFloat(10 * 24 + 10), max(58, CGFloat(min(itemCount, 10)) * 24 + 10))

        let rectInWindow = editorView.convert(anchorRect, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)

        var x = rectInScreen.minX
        var y = rectInScreen.minY - height - 4

        if let visible = screen?.visibleFrame {
            if y < visible.minY + 8 {
                y = rectInScreen.maxY + 4
            }
            x = max(visible.minX + 8, min(x, visible.maxX - width - 8))
            y = max(visible.minY + 8, min(y, visible.maxY - height - 8))
        }

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }

        let id = NSUserInterfaceItemIdentifier("completion-cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor(attoHex: 0xD4D4D4)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        if cell.textField == nil {
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        label.stringValue = AttoLspCompletionParser.displayTitle(for: items[row])
        return cell
    }

    @objc private func doubleClicked(_ sender: Any?) {
        commitSelected()
    }

    private func commitSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        hide()
        onCommit?(item)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

private final class AttoCompletionTableView: NSTableView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommit?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class AttoCompletionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private extension NSColor {
    convenience init(attoHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((attoHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((attoHex >> 8) & 0xFF) / 255.0
        let b = CGFloat(attoHex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
