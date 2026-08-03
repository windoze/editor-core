import AppKit
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoWorkspaceEditHistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    struct Item: Equatable {
        let sequence: UInt64
        let operation: String
        let title: String
        let detail: String
        let status: String
        let canUndoLatest: Bool
    }

    private var items: [Item] = []
    private var filteredItems: [Item] = []
    private var panel: NSPanel?
    private let onUndoLatest: () -> Void
    private let searchField = NSSearchField(frame: .zero)
    private let metadataLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let undoButton = NSButton(title: "Undo Latest", target: nil, action: nil)

    init(onUndoLatest: @escaping () -> Void) {
        self.onUndoLatest = onUndoLatest
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
        updateTitleAndMetadata()
        updateButtonState()
    }

    @discardableResult
    func show(relativeTo window: NSWindow, items: [Item]) -> Bool {
        update(items: items)

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

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 420),
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
        panel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelRoot)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        searchField.placeholderString = "Filter WorkspaceEdit history..."
        searchField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelSearchField)
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        metadataLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelMetadataLabel)
        metadataLabel.font = NSFont.systemFont(ofSize: 11)
        metadataLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("workspaceEditHistory"))
        column.title = "WorkspaceEdit History"
        column.width = 740
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 48
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelTable)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelScrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        undoButton.target = self
        undoButton.action = #selector(undoLatestClicked(_:))
        undoButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelUndoButton)
        undoButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(searchField)
        root.addSubview(metadataLabel)
        root.addSubview(scrollView)
        root.addSubview(undoButton)

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
            scrollView.bottomAnchor.constraint(equalTo: undoButton.topAnchor, constant: -10),

            undoButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            undoButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            undoButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])

        updateTitleAndMetadata()
        updateButtonState()
        return panel
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width = max(panel.frame.width, 780)
        let height = max(panel.frame.height, 420)
        let winFrame = window.frame
        var x = winFrame.maxX - width - 56
        var y = winFrame.maxY - height - 132

        let visible = screen.visibleFrame
        x = max(visible.minX + 20, min(x, visible.maxX - width - 20))
        y = max(visible.minY + 20, min(y, visible.maxY - height - 20))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func updateTitleAndMetadata() {
        panel?.title = "WorkspaceEdit History (\(items.count))"
        let appliedCount = items.filter { $0.status == "Applied" }.count
        let partialCount = items.filter { $0.status == "Partial" }.count
        let rejectedCount = items.filter { $0.status == "Rejected" }.count
        metadataLabel.stringValue = "\(appliedCount) applied | \(partialCount) partial | \(rejectedCount) rejected"
    }

    private func updateButtonState() {
        undoButton.isEnabled = items.contains { $0.canUndoLatest }
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
        if filteredItems.isEmpty {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count else { return nil }
        let item = filteredItems[row]

        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelRow)

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelRowTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(attoHex: 0xD4D4D4)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: item.detail)
        detailLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelRowDetail)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = NSColor(attoHex: 0xA6A6A6)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: item.status)
        statusLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelRowStatus)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.alignment = .right
        statusLabel.textColor = statusColor(for: item.status)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(titleLabel)
        cell.addSubview(detailLabel)
        cell.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            statusLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])

        return cell
    }

    private func statusColor(for status: String) -> NSColor {
        switch status {
        case "Applied":
            return NSColor(attoHex: 0x8CDCFE)
        case "Partial":
            return NSColor(attoHex: 0xDCDCAA)
        case "Rejected":
            return NSColor(attoHex: 0xF48771)
        default:
            return NSColor(attoHex: 0xA6A6A6)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    @objc private func undoLatestClicked(_ sender: Any?) {
        onUndoLatest()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as AnyObject? === panel {
            panel?.parent?.removeChildWindow(panel!)
        }
    }
}

enum AttoWorkspaceEditHistoryFormatter {
    @MainActor
    static func items(
        from snapshot: EcuWorkspaceEditTransactionEventsSnapshot,
        consumedUndoSequence: UInt64? = nil
    ) -> [AttoWorkspaceEditHistoryPanelController.Item] {
        let latestUndoableSequence = snapshot.events.last { event in
            event.operation == "apply" && event.result.applied
        }?.sequence
        return snapshot.events.reversed().map { event in
            let result = event.result
            let editCount = result.appliedEditCount
            let resourceCount = result.appliedResourceOperationCount
            return AttoWorkspaceEditHistoryPanelController.Item(
                sequence: event.sequence,
                operation: event.operation,
                title: "#\(event.sequence) \(operationTitle(event.operation)) WorkspaceEdit",
                detail: "\(editCount) text edits, \(resourceCount) resource ops | \(uriSummary(for: result))",
                status: status(for: result),
                canUndoLatest: event.sequence == latestUndoableSequence
                    && event.sequence != consumedUndoSequence
            )
        }
    }

    private static func operationTitle(_ operation: String) -> String {
        guard operation.isEmpty == false else { return "Transaction" }
        return operation.prefix(1).uppercased() + operation.dropFirst()
    }

    private static func status(for result: EcuWorkspaceEditTransactionResult) -> String {
        if result.applied {
            return result.skippedURIs.isEmpty ? "Applied" : "Partial"
        }
        return "Rejected"
    }

    private static func uriSummary(for result: EcuWorkspaceEditTransactionResult) -> String {
        let uris = uniqueURIs(
            result.appliedURIs
                + result.skippedURIs
                + result.dirtyDocumentURIs
                + result.documents.map(\.uri)
        )
        guard uris.isEmpty == false else { return "No document URI" }
        let names = uris.prefix(3).map(displayName(for:))
        let suffix = uris.count > 3 ? " +\(uris.count - 3)" : ""
        return names.joined(separator: ", ") + suffix
    }

    private static func uniqueURIs(_ uris: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for uri in uris where seen.insert(uri).inserted {
            result.append(uri)
        }
        return result
    }

    private static func displayName(for uri: String) -> String {
        guard let url = URL(string: uri), url.isFileURL else { return uri }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
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
