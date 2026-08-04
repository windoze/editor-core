import AppKit
import Foundation

@MainActor
final class AttoLspWorkbenchDockView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    typealias Item = AttoLspWorkbenchPanelController.Item

    private var items: [Item] = []
    private var filteredItems: [Item] = []
    private var selectedItemID: String?
    private let onOpen: (Item) -> Void
    private let onOpenHistory: (Item) -> Void
    private let onClose: () -> Void
    private let searchField = NSSearchField(frame: .zero)
    private let metadataLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let closeButton = NSButton(frame: .zero)

    init(
        onOpen: @escaping (Item) -> Void,
        onOpenHistory: @escaping (Item) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        self.onOpen = onOpen
        self.onOpenHistory = onOpenHistory
        self.onClose = onClose
        super.init(frame: .zero)
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var currentItems: [Item] {
        items
    }

    var isVisible: Bool {
        isHidden == false && superview != nil
    }

    var rowCount: Int {
        filteredItems.count
    }

    var selectedItem: Item? {
        let row = tableView.selectedRow
        if row >= 0, row < filteredItems.count {
            return filteredItems[row]
        }
        guard let selectedItemID else { return nil }
        return filteredItems.first { $0.id == selectedItemID }
    }

    @discardableResult
    func selectItem(id: String) -> Bool {
        guard let index = filteredItems.firstIndex(where: { $0.id == id }) else {
            return false
        }
        selectedItemID = id
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        return true
    }

    func update(items: [Item]) {
        self.items = items
        applyFilter()
        metadataLabel.stringValue = AttoLspWorkbenchPanelController.metadataSummary(for: items)
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    private func buildView() {
        identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDock)
        wantsLayer = true
        layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        layer?.borderColor = NSColor(attoHex: 0x3C3C3C).cgColor
        layer?.borderWidth = 1

        searchField.placeholderString = "Filter LSP workbench..."
        searchField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockSearchField)
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        closeButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockCloseButton)
        closeButton.bezelStyle = .texturedRounded
        closeButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            closeButton.image = image
            closeButton.imageScaling = .scaleProportionallyDown
        } else {
            closeButton.title = "x"
        }
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        metadataLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockMetadataLabel)
        metadataLabel.font = NSFont.systemFont(ofSize: 11)
        metadataLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lspWorkbenchDock"))
        column.title = "LSP Workbench"
        column.width = 760
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
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockTable)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockScrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(closeButton)
        addSubview(metadataLabel)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),

            metadataLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            metadataLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            metadataLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 5),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: metadataLabel.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
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
        restoreSelection()
    }

    private func restoreSelection() {
        if let selectedItemID,
           let selectedIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID }) {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        } else if let first = filteredItems.first {
            selectedItemID = first.id
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            selectedItemID = nil
            tableView.deselectAll(nil)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count else { return nil }
        let item = filteredItems[row]

        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockRow)

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockRowTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = item.isEnabled ? NSColor(attoHex: 0xD4D4D4) : NSColor(attoHex: 0x858585)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: item.detail)
        detailLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockRowDetail)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusText = item.isPinned ? "Pinned | \(item.status)" : item.status
        let statusLabel = NSTextField(labelWithString: statusText)
        statusLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.lspWorkbenchDockRowStatus)
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
            titleLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 5),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            statusLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])

        return cell
    }

    @objc private func closeClicked(_ sender: Any?) {
        onClose()
    }

    @objc private func doubleClicked(_ sender: Any?) {
        openSelectedItem()
    }

    private func openSelectedItem() {
        guard let item = selectedItem, item.isEnabled else { return }
        onOpen(item)
    }

    private func openSelectedItemHistory() {
        guard let item = selectedItem, item.historyCount > 0 else { return }
        onOpenHistory(item)
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            onClose()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(delta: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(delta: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelectedItem()
            return true
        case #selector(NSResponder.moveRight(_:)):
            openSelectedItemHistory()
            return true
        default:
            return false
        }
    }

    private func moveSelection(delta: Int) {
        guard filteredItems.isEmpty == false else {
            selectedItemID = nil
            tableView.deselectAll(nil)
            return
        }
        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + delta, 0), filteredItems.count - 1)
        selectedItemID = filteredItems[next].id
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
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
