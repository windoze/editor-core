import AppKit
import Foundation

@MainActor
final class AttoDeletedMacroHistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    struct Item: Equatable {
        let displayIndex: Int
        let title: String
    }

    private let onRestore: (Int) -> Void
    private let onRemove: ([Int]) -> Void
    private let onClear: () -> Void

    private var panel: NSPanel?
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let restoreButton = NSButton(title: "Restore Selected", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove Selected", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear History", target: nil, action: nil)
    private var items: [Item] = []

    init(
        onRestore: @escaping (Int) -> Void,
        onRemove: @escaping ([Int]) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.onRestore = onRestore
        self.onRemove = onRemove
        self.onClear = onClear
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func update(items: [Item]) {
        self.items = items
        panel?.title = "Deleted Macros (\(items.count))"
        tableView.reloadData()
        if items.isEmpty {
            tableView.deselectAll(nil)
        } else {
            let validSelection = IndexSet(tableView.selectedRowIndexes.filter { $0 < items.count })
            if validSelection != tableView.selectedRowIndexes {
                tableView.selectRowIndexes(validSelection, byExtendingSelection: false)
            }
            if tableView.selectedRowIndexes.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
        updateButtonStates()
    }

    @discardableResult
    func show(relativeTo window: NSWindow, items: [Item]) -> Bool {
        if panel == nil {
            panel = buildPanel()
        }

        guard let panel else { return false }
        update(items: items)
        position(panel: panel, relativeTo: window)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(tableView)
        updateButtonStates()
        return true
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
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
        panel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelRoot)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("deletedMacro"))
        column.title = "Deleted Macro"
        column.width = 600
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.allowsMultipleSelection = true
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.target = self
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelTable)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelScrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked(_:))
        restoreButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelRestoreButton)
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        removeButton.target = self
        removeButton.action = #selector(removeClicked(_:))
        removeButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelRemoveButton)
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        clearButton.target = self
        clearButton.action = #selector(clearClicked(_:))
        clearButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelClearButton)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [restoreButton, removeButton, clearButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scrollView)
        root.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),

            buttonRow.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 12),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            buttonRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])

        updateButtonStates()
        return panel
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width = max(panel.frame.width, 640)
        let height = max(panel.frame.height, 360)
        let winFrame = window.frame
        var x = winFrame.midX - width / 2
        var y = winFrame.maxY - height - 120

        let visible = screen.visibleFrame
        x = max(visible.minX + 20, min(x, visible.maxX - width - 20))
        y = max(visible.minY + 20, min(y, visible.maxY - height - 20))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func selectedDisplayIndices() -> [Int] {
        tableView.selectedRowIndexes
            .compactMap { row in
                guard row >= 0, row < items.count else { return nil }
                return items[row].displayIndex
            }
            .sorted()
    }

    private func updateButtonStates() {
        let selectedCount = tableView.selectedRowIndexes.count
        restoreButton.isEnabled = selectedCount == 1
        removeButton.isEnabled = selectedCount > 0
        clearButton.isEnabled = items.isEmpty == false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        let item = items[row]

        let id = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelRow)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.deletedMacroHistoryPanelRowTitle)
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

        label.stringValue = "\(item.displayIndex). \(item.title)"
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }

    @objc private func doubleClicked(_ sender: Any?) {
        restoreClicked(sender)
    }

    @objc private func restoreClicked(_ sender: Any?) {
        let selected = selectedDisplayIndices()
        guard selected.count == 1, let index = selected.first else {
            NSSound.beep()
            return
        }
        onRestore(index)
    }

    @objc private func removeClicked(_ sender: Any?) {
        let selected = selectedDisplayIndices()
        guard selected.isEmpty == false else {
            NSSound.beep()
            return
        }
        onRemove(selected)
    }

    @objc private func clearClicked(_ sender: Any?) {
        guard items.isEmpty == false else {
            NSSound.beep()
            return
        }
        onClear()
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
