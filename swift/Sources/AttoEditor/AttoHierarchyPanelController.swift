import AppKit
import Foundation

@MainActor
final class AttoHierarchyPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    typealias Entry = AttoLspHierarchyParser.Entry

    struct Snapshot: Equatable {
        let title: String
        let entries: [Entry]
    }

    private struct Row {
        let entry: Entry
        let title: String
    }

    private let titleForEntry: (Entry) -> String
    private let onOpen: (Entry) -> Void
    private let onExpand: (Entry) -> Void
    private var snapshot: Snapshot?
    private var rows: [Row] = []
    private var filteredRows: [Row] = []
    private var panel: NSPanel?
    private let searchField = NSSearchField(frame: .zero)
    private let metadataLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    init(
        titleForEntry: @escaping (Entry) -> String,
        onOpen: @escaping (Entry) -> Void,
        onExpand: @escaping (Entry) -> Void = { _ in }
    ) {
        self.titleForEntry = titleForEntry
        self.onOpen = onOpen
        self.onExpand = onExpand
        super.init()
    }

    var currentEntries: [Entry] {
        rows.map(\.entry)
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var rowCount: Int {
        filteredRows.count
    }

    var selectedEntry: Entry? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredRows.count else { return nil }
        return filteredRows[row].entry
    }

    func update(snapshot: Snapshot) {
        self.snapshot = snapshot
        rows = snapshot.entries.map { entry in
            Row(entry: entry, title: titleForEntry(entry))
        }
        applyFilter()
        updateTitle()
    }

    @discardableResult
    func show(relativeTo window: NSWindow, snapshot: Snapshot) -> Bool {
        update(snapshot: snapshot)

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
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 400),
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
        panel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanelRoot)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        searchField.placeholderString = "Filter hierarchy results..."
        searchField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanelSearchField)
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        metadataLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanelMetadataLabel)
        metadataLabel.font = NSFont.systemFont(ofSize: 11)
        metadataLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hierarchy"))
        column.title = "Hierarchy"
        column.width = 740
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.target = self
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanelTable)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanelScrollView)
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
        panel.title = "Hierarchy (\(rows.count))"
        let resultTitle = snapshot?.title ?? "Hierarchy"
        let count = rows.count == 1 ? "1 result" : "\(rows.count) results"
        metadataLabel.stringValue = "\(resultTitle) | \(count)"
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width = max(panel.frame.width, 780)
        let height = max(panel.frame.height, 400)
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
            filteredRows = rows
        } else {
            filteredRows = rows.filter { row in
                row.title.localizedCaseInsensitiveContains(query)
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

        let id = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanelRow)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.hierarchyPanelRowTitle)
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

        label.stringValue = rowModel.title
        return cell
    }

    @objc private func doubleClicked(_ sender: Any?) {
        openSelectedHierarchyEntry()
    }

    private func openSelectedHierarchyEntry() {
        guard let selectedEntry else { return }
        onOpen(selectedEntry)
    }

    private func expandSelectedHierarchyEntry() {
        guard let selectedEntry else { return }
        onExpand(selectedEntry)
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
            openSelectedHierarchyEntry()
            return true
        case #selector(NSResponder.moveRight(_:)):
            expandSelectedHierarchyEntry()
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
