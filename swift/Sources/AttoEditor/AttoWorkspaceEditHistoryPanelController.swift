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
        let conflictCount: Int
        let firstConflictURI: String?
        let firstSaveableConflictURI: String?
        let firstDiscardableConflictURI: String?
        let workspaceEditJSON: String?
        let requestRetryLabel: String?
        let requestRetryDescriptor: AttoWorkspaceEditRequestRetryDescriptor?
        let requestRetryUnavailableReason: String?
        let canUndoLatest: Bool

        var canRerunRequest: Bool {
            requestRetryDescriptor?.canRerun == true
        }
    }

    private var items: [Item] = []
    private var filteredItems: [Item] = []
    private var panel: NSPanel?
    private let onUndoLatest: () -> Bool
    private let onReapply: (String) -> Bool
    private let onRerunRequest: (UInt64) -> Bool
    private let onOpenConflict: (String) -> Bool
    private let onSaveConflict: (String) -> Bool
    private let onDiscardConflict: (String) -> Bool
    private let onSaveConflictAndReapply: (String, String) -> Bool
    private let onDiscardConflictAndReapply: (String, String) -> Bool
    private let onSaveConflictAndRerunRequest: (String, UInt64) -> Bool
    private let onDiscardConflictAndRerunRequest: (String, UInt64) -> Bool
    private let searchField = NSSearchField(frame: .zero)
    private let metadataLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let openConflictButton = NSButton(title: "Open Conflict", target: nil, action: nil)
    private let saveConflictButton = NSButton(title: "Save Conflict", target: nil, action: nil)
    private let discardConflictButton = NSButton(title: "Discard Conflict", target: nil, action: nil)
    private let saveAndReapplyButton = NSButton(title: "Save & Reapply", target: nil, action: nil)
    private let discardAndReapplyButton = NSButton(title: "Discard & Reapply", target: nil, action: nil)
    private let rerunRequestButton = NSButton(title: "Rerun Request", target: nil, action: nil)
    private let reapplyButton = NSButton(title: "Reapply", target: nil, action: nil)
    private let undoButton = NSButton(title: "Undo Latest", target: nil, action: nil)

    init(
        onUndoLatest: @escaping () -> Bool,
        onReapply: @escaping (String) -> Bool,
        onRerunRequest: @escaping (UInt64) -> Bool,
        onOpenConflict: @escaping (String) -> Bool,
        onSaveConflict: @escaping (String) -> Bool,
        onDiscardConflict: @escaping (String) -> Bool,
        onSaveConflictAndReapply: @escaping (String, String) -> Bool,
        onDiscardConflictAndReapply: @escaping (String, String) -> Bool,
        onSaveConflictAndRerunRequest: @escaping (String, UInt64) -> Bool,
        onDiscardConflictAndRerunRequest: @escaping (String, UInt64) -> Bool
    ) {
        self.onUndoLatest = onUndoLatest
        self.onReapply = onReapply
        self.onRerunRequest = onRerunRequest
        self.onOpenConflict = onOpenConflict
        self.onSaveConflict = onSaveConflict
        self.onDiscardConflict = onDiscardConflict
        self.onSaveConflictAndReapply = onSaveConflictAndReapply
        self.onDiscardConflictAndReapply = onDiscardConflictAndReapply
        self.onSaveConflictAndRerunRequest = onSaveConflictAndRerunRequest
        self.onDiscardConflictAndRerunRequest = onDiscardConflictAndRerunRequest
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

    func close() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.delegate = nil
        panel.close()
        self.panel = nil
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 420),
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
        panel.minSize = NSSize(width: 1120, height: 360)
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
        column.width = 1080
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

        openConflictButton.target = self
        openConflictButton.action = #selector(openConflictClicked(_:))
        openConflictButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditHistoryPanelOpenConflictButton
        )
        openConflictButton.translatesAutoresizingMaskIntoConstraints = false

        saveConflictButton.target = self
        saveConflictButton.action = #selector(saveConflictClicked(_:))
        saveConflictButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditHistoryPanelSaveConflictButton
        )
        saveConflictButton.translatesAutoresizingMaskIntoConstraints = false

        discardConflictButton.target = self
        discardConflictButton.action = #selector(discardConflictClicked(_:))
        discardConflictButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditHistoryPanelDiscardConflictButton
        )
        discardConflictButton.translatesAutoresizingMaskIntoConstraints = false

        saveAndReapplyButton.target = self
        saveAndReapplyButton.action = #selector(saveAndReapplyClicked(_:))
        saveAndReapplyButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditHistoryPanelSaveAndReapplyButton
        )
        saveAndReapplyButton.translatesAutoresizingMaskIntoConstraints = false

        discardAndReapplyButton.target = self
        discardAndReapplyButton.action = #selector(discardAndReapplyClicked(_:))
        discardAndReapplyButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditHistoryPanelDiscardAndReapplyButton
        )
        discardAndReapplyButton.translatesAutoresizingMaskIntoConstraints = false

        rerunRequestButton.target = self
        rerunRequestButton.action = #selector(rerunRequestClicked(_:))
        rerunRequestButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditHistoryPanelRerunRequestButton
        )
        rerunRequestButton.translatesAutoresizingMaskIntoConstraints = false

        reapplyButton.target = self
        reapplyButton.action = #selector(reapplyClicked(_:))
        reapplyButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelReapplyButton)
        reapplyButton.translatesAutoresizingMaskIntoConstraints = false

        undoButton.target = self
        undoButton.action = #selector(undoLatestClicked(_:))
        undoButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditHistoryPanelUndoButton)
        undoButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(searchField)
        root.addSubview(metadataLabel)
        root.addSubview(scrollView)
        root.addSubview(openConflictButton)
        root.addSubview(saveConflictButton)
        root.addSubview(discardConflictButton)
        root.addSubview(saveAndReapplyButton)
        root.addSubview(discardAndReapplyButton)
        root.addSubview(rerunRequestButton)
        root.addSubview(reapplyButton)
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

            openConflictButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            openConflictButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            openConflictButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            saveConflictButton.leadingAnchor.constraint(equalTo: openConflictButton.trailingAnchor, constant: 8),
            saveConflictButton.bottomAnchor.constraint(equalTo: openConflictButton.bottomAnchor),
            saveConflictButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            discardConflictButton.leadingAnchor.constraint(equalTo: saveConflictButton.trailingAnchor, constant: 8),
            discardConflictButton.bottomAnchor.constraint(equalTo: openConflictButton.bottomAnchor),
            discardConflictButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            saveAndReapplyButton.leadingAnchor.constraint(equalTo: discardConflictButton.trailingAnchor, constant: 8),
            saveAndReapplyButton.bottomAnchor.constraint(equalTo: openConflictButton.bottomAnchor),
            saveAndReapplyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            discardAndReapplyButton.leadingAnchor.constraint(equalTo: saveAndReapplyButton.trailingAnchor, constant: 8),
            discardAndReapplyButton.trailingAnchor.constraint(lessThanOrEqualTo: rerunRequestButton.leadingAnchor, constant: -12),
            discardAndReapplyButton.bottomAnchor.constraint(equalTo: openConflictButton.bottomAnchor),
            discardAndReapplyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            rerunRequestButton.trailingAnchor.constraint(equalTo: reapplyButton.leadingAnchor, constant: -8),
            rerunRequestButton.bottomAnchor.constraint(equalTo: reapplyButton.bottomAnchor),
            rerunRequestButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            reapplyButton.trailingAnchor.constraint(equalTo: undoButton.leadingAnchor, constant: -8),
            reapplyButton.bottomAnchor.constraint(equalTo: undoButton.bottomAnchor),
            reapplyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

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

        let width = max(panel.frame.width, 1120)
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
        let conflictCount = items.reduce(0) { $0 + $1.conflictCount }
        metadataLabel.stringValue =
            "\(appliedCount) applied | \(partialCount) partial | \(rejectedCount) rejected | \(conflictCount) conflicts"
    }

    private func updateButtonState() {
        let state = currentActionState()
        apply(state: state.openConflict, to: openConflictButton)
        apply(state: state.saveConflict, to: saveConflictButton)
        apply(state: state.discardConflict, to: discardConflictButton)
        apply(state: state.saveAndResolve, to: saveAndReapplyButton)
        apply(state: state.discardAndResolve, to: discardAndReapplyButton)
        apply(state: state.rerunRequest, to: rerunRequestButton)
        apply(state: state.reapply, to: reapplyButton)
        apply(state: state.undoLatest, to: undoButton)
    }

    private func apply(state: AttoWorkspaceEditActionButtonState, to button: NSButton) {
        if let title = state.title {
            button.title = title
        }
        button.isEnabled = state.isEnabled
        button.toolTip = state.toolTip
    }

    private func currentActionState() -> AttoWorkspaceEditHistoryActionState {
        AttoWorkspaceEditConflictActionState.history(
            for: selectedItem(),
            hasUndoLatest: items.contains { $0.canUndoLatest }
        )
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
                    || item.firstConflictURI?.localizedCaseInsensitiveContains(query) == true
                    || item.firstSaveableConflictURI?.localizedCaseInsensitiveContains(query) == true
                    || item.firstDiscardableConflictURI?.localizedCaseInsensitiveContains(query) == true
                    || item.requestRetryLabel?.localizedCaseInsensitiveContains(query) == true
                    || item.requestRetryUnavailableReason?.localizedCaseInsensitiveContains(query) == true
                    || item.requestRetryDescriptor?.searchableText.localizedCaseInsensitiveContains(query) == true
            }
        }
        tableView.reloadData()
        if filteredItems.isEmpty {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateButtonState()
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonState()
    }

    private func selectedConflictTargetURI() -> String? {
        selectedItem()?.firstConflictURI
    }

    private func selectedSaveableConflictTargetURI() -> String? {
        selectedItem()?.firstSaveableConflictURI
    }

    private func selectedDiscardableConflictTargetURI() -> String? {
        selectedItem()?.firstDiscardableConflictURI
    }

    private func selectedReapplyWorkspaceEditJSON() -> String? {
        guard let json = selectedItem()?.workspaceEditJSON, json.isEmpty == false else { return nil }
        return json
    }

    private func selectedRerunRequestSequence() -> UInt64? {
        guard let item = selectedItem(),
              item.requestRetryLabel?.isEmpty == false,
              item.canRerunRequest
        else {
            return nil
        }
        return item.sequence
    }

    private func selectedSaveAndReapplyConflictTarget() -> (uri: String, workspaceEditJSON: String)? {
        guard let item = selectedItem(),
              item.status == "Rejected",
              item.requestRetryLabel == nil,
              let uri = item.firstSaveableConflictURI,
              let json = item.workspaceEditJSON,
              json.isEmpty == false
        else {
            return nil
        }
        return (uri: uri, workspaceEditJSON: json)
    }

    private func selectedDiscardAndReapplyConflictTarget() -> (uri: String, workspaceEditJSON: String)? {
        guard let item = selectedItem(),
              item.status == "Rejected",
              item.requestRetryLabel == nil,
              let uri = item.firstDiscardableConflictURI,
              let json = item.workspaceEditJSON,
              json.isEmpty == false
        else {
            return nil
        }
        return (uri: uri, workspaceEditJSON: json)
    }

    private func selectedSaveAndRerunConflictTarget() -> (uri: String, sequence: UInt64)? {
        guard let item = selectedItem(),
              item.status == "Rejected",
              item.requestRetryLabel?.isEmpty == false,
              item.canRerunRequest,
              let uri = item.firstSaveableConflictURI
        else {
            return nil
        }
        return (uri: uri, sequence: item.sequence)
    }

    private func selectedDiscardAndRerunConflictTarget() -> (uri: String, sequence: UInt64)? {
        guard let item = selectedItem(),
              item.status == "Rejected",
              item.requestRetryLabel?.isEmpty == false,
              item.canRerunRequest,
              let uri = item.firstDiscardableConflictURI
        else {
            return nil
        }
        return (uri: uri, sequence: item.sequence)
    }

    private func selectedItem() -> Item? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return nil }
        return filteredItems[row]
    }

    @objc private func openConflictClicked(_ sender: Any?) {
        let state = currentActionState().openConflict
        guard let uri = selectedConflictTargetURI() else {
            reportUnavailableAction(state)
            return
        }
        guard onOpenConflict(uri) else {
            reportFailedAction("Open conflict failed")
            return
        }
    }

    @objc private func saveConflictClicked(_ sender: Any?) {
        let state = currentActionState().saveConflict
        guard let uri = selectedSaveableConflictTargetURI() else {
            reportUnavailableAction(state)
            return
        }
        guard onSaveConflict(uri) else {
            reportFailedAction("Save conflict failed")
            return
        }
    }

    @objc private func discardConflictClicked(_ sender: Any?) {
        let state = currentActionState().discardConflict
        guard let uri = selectedDiscardableConflictTargetURI() else {
            reportUnavailableAction(state)
            return
        }
        guard onDiscardConflict(uri) else {
            reportFailedAction("Discard conflict failed")
            return
        }
    }

    @objc private func saveAndReapplyClicked(_ sender: Any?) {
        if let target = selectedSaveAndRerunConflictTarget() {
            guard onSaveConflictAndRerunRequest(target.uri, target.sequence) else {
                reportFailedAction("Save and rerun failed")
                return
            }
            return
        }
        let state = currentActionState().saveAndResolve
        guard let target = selectedSaveAndReapplyConflictTarget() else {
            reportUnavailableAction(state)
            return
        }
        guard onSaveConflictAndReapply(target.uri, target.workspaceEditJSON) else {
            reportFailedAction("Save and reapply failed")
            return
        }
    }

    @objc private func discardAndReapplyClicked(_ sender: Any?) {
        if let target = selectedDiscardAndRerunConflictTarget() {
            guard onDiscardConflictAndRerunRequest(target.uri, target.sequence) else {
                reportFailedAction("Discard and rerun failed")
                return
            }
            return
        }
        let state = currentActionState().discardAndResolve
        guard let target = selectedDiscardAndReapplyConflictTarget() else {
            reportUnavailableAction(state)
            return
        }
        guard onDiscardConflictAndReapply(target.uri, target.workspaceEditJSON) else {
            reportFailedAction("Discard and reapply failed")
            return
        }
    }

    @objc private func rerunRequestClicked(_ sender: Any?) {
        let state = currentActionState().rerunRequest
        guard let sequence = selectedRerunRequestSequence() else {
            reportUnavailableAction(state)
            return
        }
        guard onRerunRequest(sequence) else {
            reportFailedAction("Rerun request failed")
            return
        }
    }

    @objc private func reapplyClicked(_ sender: Any?) {
        let state = currentActionState().reapply
        guard let workspaceEditJSON = selectedReapplyWorkspaceEditJSON() else {
            reportUnavailableAction(state)
            return
        }
        guard onReapply(workspaceEditJSON) else {
            reportFailedAction("Reapply WorkspaceEdit failed")
            return
        }
    }

    @objc private func undoLatestClicked(_ sender: Any?) {
        let state = currentActionState().undoLatest
        guard onUndoLatest() else {
            reportUnavailableAction(state)
            return
        }
    }

    private func reportUnavailableAction(_ state: AttoWorkspaceEditActionButtonState) {
        metadataLabel.stringValue = AttoWorkspaceEditConflictActionState.unavailableFeedback(for: state)
        NSSound.beep()
    }

    private func reportFailedAction(_ text: String) {
        metadataLabel.stringValue = text
        NSSound.beep()
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel,
              notification.object as AnyObject? === panel
        else { return }
        panel.parent?.removeChildWindow(panel)
    }
}

enum AttoWorkspaceEditHistoryFormatter {
    @MainActor
    static func items(
        from snapshot: EcuWorkspaceEditTransactionEventsSnapshot,
        consumedUndoSequences: Set<UInt64> = [],
        requestRetryDescriptorsBySequence: [UInt64: AttoWorkspaceEditRequestRetryDescriptor] = [:]
    ) -> [AttoWorkspaceEditHistoryPanelController.Item] {
        let latestUndoableSequence = snapshot.events.last { event in
            isUndoableTransactionOperation(event.operation)
                && event.result.applied
                && consumedUndoSequences.contains(event.sequence) == false
        }?.sequence
        return snapshot.events.reversed().map { event in
            let result = event.result
            let editCount = result.appliedEditCount
            let resourceCount = result.appliedResourceOperationCount
            let requestRetryDescriptor = requestRetryDescriptorsBySequence[event.sequence]
            let requestRetryUnavailableReason = requestRetryDescriptor?.invalidationReasonText
            return AttoWorkspaceEditHistoryPanelController.Item(
                sequence: event.sequence,
                operation: event.operation,
                title: "#\(event.sequence) \(operationTitle(event.operation)) WorkspaceEdit",
                detail: detailText(
                    editCount: editCount,
                    resourceCount: resourceCount,
                    result: result,
                    requestRetryDescriptor: requestRetryDescriptor
                ),
                status: status(for: result),
                conflictCount: result.conflicts.count,
                firstConflictURI: result.conflicts.first { $0.uri.isEmpty == false }?.uri,
                firstSaveableConflictURI: firstSaveOrDiscardConflictURI(in: result.conflicts),
                firstDiscardableConflictURI: firstSaveOrDiscardConflictURI(in: result.conflicts),
                workspaceEditJSON: event.workspaceEditJSON,
                requestRetryLabel: requestRetryDescriptor?.label,
                requestRetryDescriptor: requestRetryDescriptor,
                requestRetryUnavailableReason: requestRetryUnavailableReason,
                canUndoLatest: event.sequence == latestUndoableSequence
            )
        }
    }

    private static func operationTitle(_ operation: String) -> String {
        guard operation.isEmpty == false else { return "Transaction" }
        return operation.prefix(1).uppercased() + operation.dropFirst()
    }

    private static func isUndoableTransactionOperation(_ operation: String) -> Bool {
        operation == "apply" || operation == "redo"
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
                + result.conflicts.map(\.uri)
                + result.documents.map(\.uri)
        )
        guard uris.isEmpty == false else { return "No document URI" }
        let names = uris.prefix(3).map(displayName(for:))
        let suffix = uris.count > 3 ? " +\(uris.count - 3)" : ""
        return names.joined(separator: ", ") + suffix
    }

    private static func detailText(
        editCount: Int,
        resourceCount: Int,
        result: EcuWorkspaceEditTransactionResult,
        requestRetryDescriptor: AttoWorkspaceEditRequestRetryDescriptor?
    ) -> String {
        var parts = [
            "\(editCount) text edits, \(resourceCount) resource ops",
        ]
        if result.conflicts.isEmpty == false {
            parts.append(conflictSummary(for: result.conflicts))
        }
        if let requestRetryDescriptor {
            parts.append(requestRetryDescriptor.requestSummaryText)
        }
        parts.append(uriSummary(for: result))
        return parts.joined(separator: " | ")
    }

    private static func conflictSummary(for conflicts: [EcuWorkspaceEditTransactionConflict]) -> String {
        AttoWorkspaceEditConflictActionState.historyConflictSummary(for: conflicts)
    }

    private static func firstSaveOrDiscardConflictURI(
        in conflicts: [EcuWorkspaceEditTransactionConflict]
    ) -> String? {
        conflicts.first { conflict in
            conflict.uri.isEmpty == false && isSaveOrDiscardConflict(conflict)
        }?.uri
    }

    private static func isSaveOrDiscardConflict(_ conflict: EcuWorkspaceEditTransactionConflict) -> Bool {
        conflict.resolution == "save_or_discard" || conflict.kind == "dirty_document"
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
