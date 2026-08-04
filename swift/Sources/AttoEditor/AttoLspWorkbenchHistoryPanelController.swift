import AppKit
import Foundation

@MainActor
final class AttoLspWorkbenchHistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    struct Item: Equatable {
        let id: String
        let family: String
        let resultSequence: UInt64
        let title: String
        let detail: String
        let status: String
        let recordedAt: Date
        let isPinned: Bool
    }

    private struct Row {
        let item: Item
        let title: String
        let detail: String
    }

    private var items: [Item] = []
    private var rows: [Row] = []
    private var filteredRows: [Row] = []
    private var panel: NSPanel?
    private let onOpen: (Item) -> Void
    private let searchField = NSSearchField(frame: .zero)
    private let metadataLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    init(onOpen: @escaping (Item) -> Void) {
        self.onOpen = onOpen
        super.init()
    }

    var currentItems: [Item] {
        items
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var rowCount: Int {
        filteredRows.count
    }

    static func metadataSummary(for items: [Item]) -> String {
        let familyCount = Set(items.map(\.family)).count
        let pinnedCount = items.filter(\.isPinned).count
        var parts = [
            "\(items.count) history \(items.count == 1 ? "entry" : "entries")",
            "\(familyCount) result \(familyCount == 1 ? "family" : "families")",
        ]
        if pinnedCount > 0 {
            parts.append("\(pinnedCount) pinned")
        }
        return parts.joined(separator: " | ")
    }

    func update(items: [Item]) {
        self.items = items
        rows = items.map { item in
            Row(item: item, title: item.title, detail: "\(item.family) | \(item.detail)")
        }
        applyFilter()
        updateTitle()
    }

    @discardableResult
    func show(relativeTo window: NSWindow, items: [Item]) -> Bool {
        update(items: items)

        if panel == nil {
            panel = buildPanel()
        }

        guard let panel else { return false }
        updateTitle()
        applyFilter()
        position(panel: panel, relativeTo: window)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        return true
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelRoot)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        searchField.placeholderString = "Filter LSP workbench history..."
        searchField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelSearchField)
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        metadataLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelMetadataLabel)
        metadataLabel.font = NSFont.systemFont(ofSize: 11)
        metadataLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lspWorkbenchHistory"))
        column.title = "LSP Workbench History"
        column.width = 820
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 40
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.target = self
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelTable)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelScrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(searchField)
        root.addSubview(metadataLabel)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

            metadataLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            metadataLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            metadataLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: metadataLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])

        updateTitle()
        return panel
    }

    private func updateTitle() {
        panel?.title = "LSP Workbench History (\(items.count))"
        metadataLabel.stringValue = Self.metadataSummary(for: items)
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width = max(panel.frame.width, 860)
        let height = max(panel.frame.height, 460)
        let winFrame = window.frame
        var x = winFrame.maxX - width - 36
        var y = winFrame.maxY - height - 108

        let visible = screen.visibleFrame
        x = max(visible.minX + 20, min(x, visible.maxX - width - 20))
        y = max(visible.minY + 20, min(y, visible.maxY - height - 20))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredRows = rows
        } else {
            filteredRows = rows.filter { row in
                row.title.localizedCaseInsensitiveContains(query)
                    || row.detail.localizedCaseInsensitiveContains(query)
                    || row.item.status.localizedCaseInsensitiveContains(query)
            }
        }
        tableView.reloadData()
        if filteredRows.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredRows.count else { return nil }
        let rowModel = filteredRows[row]

        let id = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelRow)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let stack = cell.subviews.first as? NSStackView ?? NSStackView()
        if stack.superview == nil {
            stack.orientation = .vertical
            stack.spacing = 2
            stack.edgeInsets = NSEdgeInsets(top: 3, left: 12, bottom: 3, right: 12)
            stack.translatesAutoresizingMaskIntoConstraints = false

            let title = NSTextField(labelWithString: "")
            title.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelRowTitle)
            title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            title.textColor = NSColor(attoHex: 0xF0F0F0)
            title.lineBreakMode = .byTruncatingTail

            let detail = NSTextField(labelWithString: "")
            detail.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelRowDetail)
            detail.font = NSFont.systemFont(ofSize: 11)
            detail.textColor = NSColor(attoHex: 0xA6A6A6)
            detail.lineBreakMode = .byTruncatingTail

            let status = NSTextField(labelWithString: "")
            status.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchHistoryPanelRowStatus)
            status.font = NSFont.systemFont(ofSize: 11)
            status.textColor = NSColor(attoHex: 0xC8C8C8)
            status.lineBreakMode = .byTruncatingTail

            stack.addArrangedSubview(title)
            stack.addArrangedSubview(detail)
            stack.addArrangedSubview(status)
            cell.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                stack.topAnchor.constraint(equalTo: cell.topAnchor),
                stack.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
            ])
        }

        let labels = stack.arrangedSubviews.compactMap { $0 as? NSTextField }
        labels.first?.stringValue = rowModel.title
        if labels.count > 1 {
            labels[1].stringValue = rowModel.detail
        }
        if labels.count > 2 {
            labels[2].stringValue = rowModel.item.isPinned ? "Pinned | \(rowModel.item.status)" : rowModel.item.status
        }
        return cell
    }

    @objc private func doubleClicked(_ sender: Any?) {
        openSelectedHistoryItem()
    }

    private func openSelectedHistoryItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredRows.count else { return }
        onOpen(filteredRows[row].item)
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        case #selector(NSResponder.moveDown(_:)):
            let next = min(tableView.selectedRow + 1, filteredRows.count - 1)
            if next >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                tableView.scrollRowToVisible(next)
            }
            return true
        case #selector(NSResponder.moveUp(_:)):
            let previous = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: previous), byExtendingSelection: false)
            tableView.scrollRowToVisible(previous)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelectedHistoryItem()
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        hide()
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
