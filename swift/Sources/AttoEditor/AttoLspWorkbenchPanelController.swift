import AppKit
import Foundation

@MainActor
final class AttoLspWorkbenchPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    struct Item: Equatable {
        let id: String
        let title: String
        let detail: String
        let status: String
        let isEnabled: Bool
    }

    private var items: [Item] = []
    private var filteredItems: [Item] = []
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
        filteredItems.count
    }

    func update(items: [Item]) {
        self.items = items
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 440),
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
        panel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelRoot)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        searchField.placeholderString = "Filter LSP workbench panels..."
        searchField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelSearchField)
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        metadataLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelMetadataLabel)
        metadataLabel.font = NSFont.systemFont(ofSize: 11)
        metadataLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lspWorkbench"))
        column.title = "LSP Workbench"
        column.width = 780
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 44
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.target = self
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelTable)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelScrollView)
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
        guard let panel else { return }
        panel.title = "LSP Workbench (\(items.count))"
        let enabledCount = items.filter(\.isEnabled).count
        metadataLabel.stringValue = "\(enabledCount) available | \(items.count) result families"
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width = max(panel.frame.width, 820)
        let height = max(panel.frame.height, 440)
        let winFrame = window.frame
        var x = winFrame.maxX - width - 44
        var y = winFrame.maxY - height - 120

        let visible = screen.visibleFrame
        x = max(visible.minX + 20, min(x, visible.maxX - width - 20))
        y = max(visible.minY + 20, min(y, visible.maxY - height - 20))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.title.localizedCaseInsensitiveContains(query)
                    || item.detail.localizedCaseInsensitiveContains(query)
                    || item.status.localizedCaseInsensitiveContains(query)
            }
        }
        tableView.reloadData()
        if filteredItems.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count else { return nil }
        let item = filteredItems[row]

        let id = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelRow)
        let cell = NSTableCellView()
        cell.identifier = id

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelRowTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = item.isEnabled ? NSColor(attoHex: 0xD4D4D4) : NSColor(attoHex: 0x858585)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: item.detail)
        detailLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelRowDetail)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: item.status)
        statusLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchPanelRowStatus)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.alignment = .right
        statusLabel.textColor = item.isEnabled ? NSColor(attoHex: 0x8CDCFE) : NSColor(attoHex: 0x858585)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(titleLabel)
        cell.addSubview(detailLabel)
        cell.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            statusLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])

        return cell
    }

    @objc private func doubleClicked(_ sender: Any?) {
        openSelectedItem()
    }

    private func openSelectedItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return }
        let item = filteredItems[row]
        guard item.isEnabled else { return }
        onOpen(item)
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
            let next = min(tableView.selectedRow + 1, filteredItems.count - 1)
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
            openSelectedItem()
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
