import AppKit
import Foundation

@MainActor
final class AttoWorkspaceEditPreviewPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var preview: AttoWorkspaceEditPreview?
    private var sections: [AttoWorkspaceEditPreview.Section] = []
    private var decision: AttoWorkspaceEditPreviewDecision = .cancel
    private var panel: NSPanel?
    private let summaryLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let tableScrollView = NSScrollView(frame: .zero)
    private let detailTextView = NSTextView(frame: .zero)
    private let detailScrollView = NSScrollView(frame: .zero)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let saveConflictButton = NSButton(title: "Save Conflict", target: nil, action: nil)
    private let discardConflictButton = NSButton(title: "Discard Conflict", target: nil, action: nil)
    private let saveAndRetryButton = NSButton(title: "Save & Retry", target: nil, action: nil)
    private let discardAndRetryButton = NSButton(title: "Discard & Retry", target: nil, action: nil)
    private let openConflictButton = NSButton(title: "Open Conflict", target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)

    @discardableResult
    func runModal(
        relativeTo parentWindow: NSWindow?,
        preview: AttoWorkspaceEditPreview
    ) -> AttoWorkspaceEditPreviewDecision {
        self.preview = preview
        sections = preview.panelSections
        decision = .cancel

        let panel = buildPanel()
        self.panel = panel
        position(panel: panel, relativeTo: parentWindow)
        if let parentWindow {
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        applySelection(row: 0)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
        self.panel = nil
        return decision
    }

    @discardableResult
    func showForTesting(
        relativeTo parentWindow: NSWindow?,
        preview: AttoWorkspaceEditPreview
    ) -> NSPanel {
        self.preview = preview
        sections = preview.panelSections
        decision = .cancel

        let panel = buildPanel()
        self.panel = panel
        position(panel: panel, relativeTo: parentWindow)
        if let parentWindow {
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        applySelection(row: 0)
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    func closeForTesting() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
        self.panel = nil
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Workspace Edit Preview"
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewPanel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewRoot)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        summaryLabel.stringValue = preview?.displayText.components(separatedBy: "\n\n").first ?? ""
        summaryLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewSummary)
        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = NSColor(attoHex: 0xD4D4D4)
        summaryLabel.maximumNumberOfLines = 3
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        configureDetailTextView()
        configureButtons()

        root.addSubview(summaryLabel)
        root.addSubview(tableScrollView)
        root.addSubview(detailScrollView)
        root.addSubview(saveConflictButton)
        root.addSubview(discardConflictButton)
        root.addSubview(saveAndRetryButton)
        root.addSubview(discardAndRetryButton)
        root.addSubview(openConflictButton)
        root.addSubview(cancelButton)
        root.addSubview(applyButton)

        NSLayoutConstraint.activate([
            summaryLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            summaryLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            summaryLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

            tableScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            tableScrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
            tableScrollView.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -12),
            tableScrollView.widthAnchor.constraint(equalToConstant: 280),

            detailScrollView.leadingAnchor.constraint(equalTo: tableScrollView.trailingAnchor, constant: 10),
            detailScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            detailScrollView.topAnchor.constraint(equalTo: tableScrollView.topAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: tableScrollView.bottomAnchor),

            applyButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            applyButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            applyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),

            cancelButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),

            openConflictButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            openConflictButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            openConflictButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),

            discardAndRetryButton.trailingAnchor.constraint(equalTo: openConflictButton.leadingAnchor, constant: -8),
            discardAndRetryButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            discardAndRetryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 126),

            saveAndRetryButton.trailingAnchor.constraint(equalTo: discardAndRetryButton.leadingAnchor, constant: -8),
            saveAndRetryButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            saveAndRetryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),

            discardConflictButton.trailingAnchor.constraint(equalTo: saveAndRetryButton.leadingAnchor, constant: -8),
            discardConflictButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            discardConflictButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 126),

            saveConflictButton.trailingAnchor.constraint(equalTo: discardConflictButton.leadingAnchor, constant: -8),
            saveConflictButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            saveConflictButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
        ])

        return panel
    }

    private func configureTable() {
        if tableView.tableColumns.isEmpty {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("workspace-edit-preview"))
            column.title = "Changes"
            column.width = 260
            tableView.addTableColumn(column)
        }
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 44
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewTable)

        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.drawsBackground = false
        tableScrollView.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditPreviewTableScrollView
        )
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureDetailTextView() {
        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.drawsBackground = false
        detailTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailTextView.textColor = NSColor(attoHex: 0xD4D4D4)
        detailTextView.textContainerInset = NSSize(width: 10, height: 10)
        detailTextView.textContainer?.lineFragmentPadding = 0
        detailTextView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewDetail)

        detailScrollView.documentView = detailTextView
        detailScrollView.hasVerticalScroller = true
        detailScrollView.hasHorizontalScroller = true
        detailScrollView.drawsBackground = false
        detailScrollView.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditPreviewDetailScrollView
        )
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureButtons() {
        saveConflictButton.target = self
        saveConflictButton.action = #selector(saveConflictClicked(_:))
        saveConflictButton.bezelStyle = .rounded
        saveConflictButton.isHidden = preview?.firstSaveableConflictTargetURI == nil
        saveConflictButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditPreviewSaveConflictButton
        )
        saveConflictButton.translatesAutoresizingMaskIntoConstraints = false

        discardConflictButton.target = self
        discardConflictButton.action = #selector(discardConflictClicked(_:))
        discardConflictButton.bezelStyle = .rounded
        discardConflictButton.isHidden = preview?.firstDiscardableConflictTargetURI == nil
        discardConflictButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditPreviewDiscardConflictButton
        )
        discardConflictButton.translatesAutoresizingMaskIntoConstraints = false

        saveAndRetryButton.target = self
        saveAndRetryButton.action = #selector(saveAndRetryClicked(_:))
        saveAndRetryButton.bezelStyle = .rounded
        saveAndRetryButton.isHidden = preview?.firstSaveableConflictTargetURI == nil
        saveAndRetryButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditPreviewSaveAndRetryButton
        )
        saveAndRetryButton.translatesAutoresizingMaskIntoConstraints = false

        discardAndRetryButton.target = self
        discardAndRetryButton.action = #selector(discardAndRetryClicked(_:))
        discardAndRetryButton.bezelStyle = .rounded
        discardAndRetryButton.isHidden = preview?.firstDiscardableConflictTargetURI == nil
        discardAndRetryButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditPreviewDiscardAndRetryButton
        )
        discardAndRetryButton.translatesAutoresizingMaskIntoConstraints = false

        openConflictButton.target = self
        openConflictButton.action = #selector(openConflictClicked(_:))
        openConflictButton.bezelStyle = .rounded
        openConflictButton.isHidden = preview?.conflicts.isEmpty ?? true
        openConflictButton.identifier = NSUserInterfaceItemIdentifier(
            AttoAccessibilityID.workspaceEditPreviewOpenConflictButton
        )
        openConflictButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked(_:))
        cancelButton.bezelStyle = .rounded
        cancelButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewCancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        applyButton.title = preview?.applyButtonTitle ?? "Apply"
        applyButton.isEnabled = preview?.canApply ?? true
        applyButton.target = self
        applyButton.action = #selector(applyClicked(_:))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewApplyButton)
        applyButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func position(panel: NSPanel, relativeTo parentWindow: NSWindow?) {
        guard let screen = parentWindow?.screen ?? NSScreen.main else { return }
        let width = max(panel.frame.width, 1040)
        let height = max(panel.frame.height, 560)
        let frame = parentWindow?.frame ?? screen.visibleFrame
        var x = frame.midX - width / 2
        var y = frame.midY - height / 2
        let visible = screen.visibleFrame
        x = max(visible.minX + 20, min(x, visible.maxX - width - 20))
        y = max(visible.minY + 20, min(y, visible.maxY - height - 20))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func applySelection(row: Int) {
        guard sections.indices.contains(row) else {
            detailTextView.string = preview?.displayText ?? ""
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateDetail(row: row)
        updateConflictActionButtons()
    }

    private func updateDetail(row: Int) {
        guard sections.indices.contains(row) else {
            detailTextView.string = preview?.displayText ?? ""
            return
        }
        detailTextView.string = sections[row].detailText
    }

    private func updateConflictActionButtons() {
        if saveConflictButton.isHidden == false {
            saveConflictButton.isEnabled = selectedSaveableConflictTargetURI() != nil
        }
        if discardConflictButton.isHidden == false {
            discardConflictButton.isEnabled = selectedDiscardableConflictTargetURI() != nil
        }
        if saveAndRetryButton.isHidden == false {
            saveAndRetryButton.isEnabled = selectedSaveableConflictTargetURI() != nil
        }
        if discardAndRetryButton.isHidden == false {
            discardAndRetryButton.isEnabled = selectedDiscardableConflictTargetURI() != nil
        }
        guard openConflictButton.isHidden == false else { return }
        openConflictButton.isEnabled = selectedConflictTargetURI() != nil
    }

    private func selectedConflictTargetURI() -> String? {
        let row = tableView.selectedRow
        let section = sections.indices.contains(row) ? sections[row] : nil
        return preview?.conflictTargetURI(for: section)
    }

    private func selectedSaveableConflictTargetURI() -> String? {
        let row = tableView.selectedRow
        let section = sections.indices.contains(row) ? sections[row] : nil
        return preview?.saveableConflictTargetURI(for: section)
    }

    private func selectedDiscardableConflictTargetURI() -> String? {
        let row = tableView.selectedRow
        let section = sections.indices.contains(row) ? sections[row] : nil
        return preview?.discardableConflictTargetURI(for: section)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard sections.indices.contains(row) else { return nil }
        let section = sections[row]
        let id = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewRow)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.workspaceEditPreviewRowTitle)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor(attoHex: 0xD4D4D4)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = "\(section.title)\n\(section.subtitle)"

        if cell.textField == nil {
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        updateDetail(row: row)
        updateConflictActionButtons()
    }

    func windowWillClose(_ notification: Notification) {
        decision = .cancel
        NSApp.stopModal()
    }

    @objc private func applyClicked(_ sender: Any?) {
        decision = .apply
        NSApp.stopModal()
    }

    @objc private func openConflictClicked(_ sender: Any?) {
        guard let uri = selectedConflictTargetURI() else {
            NSSound.beep()
            return
        }
        decision = .openConflict(uri)
        NSApp.stopModal()
    }

    @objc private func saveConflictClicked(_ sender: Any?) {
        guard let uri = selectedSaveableConflictTargetURI() else {
            NSSound.beep()
            return
        }
        decision = .saveConflict(uri)
        NSApp.stopModal()
    }

    @objc private func saveAndRetryClicked(_ sender: Any?) {
        guard let uri = selectedSaveableConflictTargetURI() else {
            NSSound.beep()
            return
        }
        decision = .saveAndRetry(uri)
        NSApp.stopModal()
    }

    @objc private func discardConflictClicked(_ sender: Any?) {
        guard let uri = selectedDiscardableConflictTargetURI() else {
            NSSound.beep()
            return
        }
        decision = .discardConflict(uri)
        NSApp.stopModal()
    }

    @objc private func discardAndRetryClicked(_ sender: Any?) {
        guard let uri = selectedDiscardableConflictTargetURI() else {
            NSSound.beep()
            return
        }
        decision = .discardAndRetry(uri)
        NSApp.stopModal()
    }

    @objc private func cancelClicked(_ sender: Any?) {
        decision = .cancel
        NSApp.stopModal()
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
