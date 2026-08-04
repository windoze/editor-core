import AppKit
import Foundation

@MainActor
final class AttoSettingsValidationPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    struct Item: Equatable {
        let id: String
        let sourceURL: URL
        let keyPath: String
        let message: String
        let severity: AttoConfigurationSettingsValidationSeverity
        let scope: AttoConfigurationSettingsScope
        let sourceLocation: AttoConfigurationSettingsJSONSourceLocation?

        var title: String {
            keyPath
        }

        var detail: String {
            message
        }

        var status: String {
            var parts = [severity.rawValue, scope.rawValue]
            if let sourceLocation {
                parts.append(sourceLocation.displayText)
            }
            return parts.joined(separator: " | ")
        }
    }

    private var panelTitle = "Settings Validation"
    private var items: [Item] = []
    private var filteredItems: [Item] = []
    private var selectedItemID: String?
    private var panel: NSPanel?
    private let onOpen: (Item) -> Void
    private let searchField = NSSearchField(frame: .zero)
    private let metadataLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    init(onOpen: @escaping (Item) -> Void = { _ in }) {
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

    static func items(
        for report: AttoConfigurationSettingsFileValidationReport,
        displayName: String
    ) -> [Item] {
        report.result.issues.enumerated().map { index, issue in
            Item(
                id: "\(displayName):\(index):\(issue.keyPath)",
                sourceURL: report.url,
                keyPath: issue.keyPath,
                message: issue.message,
                severity: issue.severity,
                scope: issue.scope,
                sourceLocation: report.location(for: issue)
            )
        }
    }

    static func metadataSummary(for items: [Item]) -> String {
        let errorCount = items.filter { $0.severity == .error }.count
        let warningCount = items.filter { $0.severity == .warning }.count
        var parts = [
            "\(items.count) \(items.count == 1 ? "issue" : "issues")",
            "\(errorCount) \(errorCount == 1 ? "error" : "errors")",
        ]
        if warningCount > 0 {
            parts.append("\(warningCount) \(warningCount == 1 ? "warning" : "warnings")")
        }
        return parts.joined(separator: " | ")
    }

    func update(title: String, items: [Item]) {
        self.panelTitle = title
        self.items = items
        applyFilter()
        updateTitleAndMetadata()
    }

    @discardableResult
    func show(relativeTo window: NSWindow, title: String, items: [Item]) -> Bool {
        update(title: title, items: items)

        if panel == nil {
            panel = buildPanel()
        }

        guard let panel else { return false }
        updateTitleAndMetadata()
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

    func close() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.delegate = nil
        panel.close()
        self.panel = nil
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 760, height: 320)
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelRoot)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        searchField.placeholderString = "Filter settings validation issues..."
        searchField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelSearchField)
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        metadataLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelMetadataLabel)
        metadataLabel.font = NSFont.systemFont(ofSize: 11)
        metadataLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settingsValidation"))
        column.title = "Settings Validation"
        column.width = 840
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 48
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.target = self
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelTable)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelScrollView)
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

        updateTitleAndMetadata()
        return panel
    }

    private func updateTitleAndMetadata() {
        panel?.title = "\(panelTitle) (\(items.count))"
        metadataLabel.stringValue = Self.metadataSummary(for: items)
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width = max(panel.frame.width, 880)
        let height = max(panel.frame.height, 420)
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
                item.keyPath.localizedCaseInsensitiveContains(query)
                    || item.message.localizedCaseInsensitiveContains(query)
                    || item.status.localizedCaseInsensitiveContains(query)
            }
        }
        tableView.reloadData()
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
        cell.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelRow)

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelRowTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(attoHex: 0xD4D4D4)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: item.detail)
        detailLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelRowDetail)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: item.status)
        statusLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.settingsValidationPanelRowStatus)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.alignment = .right
        statusLabel.textColor = item.severity == .error ? NSColor(attoHex: 0xF48771) : NSColor(attoHex: 0xDCDCAA)
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
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        return cell
    }

    @objc private func doubleClicked(_ sender: Any?) {
        _ = openSelectedItem()
    }

    @discardableResult
    func openSelectedItem() -> Bool {
        guard let item = selectedItem else { return false }
        guard item.sourceLocation != nil else { return false }
        onOpen(item)
        return true
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
            guard filteredItems.isEmpty == false else {
                selectedItemID = nil
                tableView.deselectAll(nil)
                return true
            }
            let current = max(tableView.selectedRow, 0)
            let next = min(current + 1, filteredItems.count - 1)
            selectedItemID = filteredItems[next].id
            tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tableView.scrollRowToVisible(next)
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard filteredItems.isEmpty == false else {
                selectedItemID = nil
                tableView.deselectAll(nil)
                return true
            }
            let current = max(tableView.selectedRow, 0)
            let previous = max(current - 1, 0)
            selectedItemID = filteredItems[previous].id
            tableView.selectRowIndexes(IndexSet(integer: previous), byExtendingSelection: false)
            tableView.scrollRowToVisible(previous)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            _ = openSelectedItem()
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
