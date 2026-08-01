import AppKit
import Foundation

@MainActor
final class AttoCompletionListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private let tableView = AttoCompletionTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let previewScrollView = NSScrollView(frame: .zero)
    private let previewTextView = NSTextView(frame: .zero)

    private var items: [AttoLspCompletionParser.Item] = []
    private var visibleItems: [AttoLspCompletionParser.Item] = []
    private var onCommit: ((AttoLspCompletionParser.Item, String?) -> Void)?
    var onTextInput: ((String) -> Bool)?
    var onDeleteBackward: (() -> Bool)?
    var onDismiss: (() -> Void)?

    func show(
        items: [AttoLspCompletionParser.Item],
        relativeTo editorView: NSView,
        anchorRect: NSRect,
        onCommit: @escaping (AttoLspCompletionParser.Item, String?) -> Void
    ) {
        guard items.isEmpty == false else {
            hide()
            return
        }
        guard let parentWindow = editorView.window else { return }

        self.items = items
        self.visibleItems = items
        self.onCommit = onCommit

        if panel == nil {
            panel = buildPanel()
        }

        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
        updatePreviewForSelectedRow()

        guard let panel else { return }
        position(panel: panel, relativeTo: editorView, anchorRect: anchorRect, itemCount: items.count)
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(tableView)
    }

    @discardableResult
    func updateFilter(prefix: String, relativeTo editorView: NSView, anchorRect: NSRect) -> Bool {
        let filtered = AttoLspCompletionParser.filteredItems(items, prefix: prefix)
        guard filtered.isEmpty == false else {
            hide()
            return false
        }

        visibleItems = filtered
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
        updatePreviewForSelectedRow()

        if let panel {
            position(panel: panel, relativeTo: editorView, anchorRect: anchorRect, itemCount: filtered.count)
        }
        return true
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
        previewTextView.string = ""
        onDismiss?()
    }

    private func buildPanel() -> NSPanel {
        let panel = AttoCompletionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 240),
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
        col.width = 388
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
            _ = self?.commitSelected()
        }
        tableView.onCommitCharacter = { [weak self] character in
            self?.commitSelected(commitCharacter: character) ?? false
        }
        tableView.onTextInput = { [weak self] text in
            self?.onTextInput?(text) ?? false
        }
        tableView.onDeleteBackward = { [weak self] in
            self?.onDeleteBackward?() ?? false
        }
        tableView.onCancel = { [weak self] in
            self?.hide()
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.drawsBackground = false
        previewTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        previewTextView.textColor = NSColor(attoHex: 0xD4D4D4)
        previewTextView.textContainerInset = NSSize(width: 8, height: 8)
        previewTextView.textContainer?.lineFragmentPadding = 0
        previewTextView.isVerticallyResizable = true
        previewTextView.isHorizontallyResizable = false
        previewTextView.autoresizingMask = [.width]
        previewTextView.textContainer?.widthTracksTextView = true
        previewTextView.textContainer?.containerSize = NSSize(
            width: 260,
            height: CGFloat.greatestFiniteMagnitude
        )

        previewScrollView.documentView = previewTextView
        previewScrollView.hasVerticalScroller = true
        previewScrollView.drawsBackground = false
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scrollView)
        root.addSubview(separator)
        root.addSubview(previewScrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: 400),

            separator.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            separator.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            separator.widthAnchor.constraint(equalToConstant: 1),

            previewScrollView.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            previewScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            previewScrollView.topAnchor.constraint(equalTo: root.topAnchor),
            previewScrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        return panel
    }

    private func position(panel: NSPanel, relativeTo editorView: NSView, anchorRect: NSRect, itemCount: Int) {
        guard let window = editorView.window else { return }
        let screen = window.screen ?? NSScreen.main

        let width: CGFloat = 680
        let height = min(CGFloat(12 * 24 + 10), max(96, CGFloat(min(itemCount, 12)) * 24 + 10))

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
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < visibleItems.count else { return nil }

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

        label.stringValue = AttoLspCompletionParser.displayTitle(for: visibleItems[row])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreviewForSelectedRow()
    }

    @objc private func doubleClicked(_ sender: Any?) {
        commitSelected()
    }

    @discardableResult
    private func commitSelected(commitCharacter: String? = nil) -> Bool {
        let row = tableView.selectedRow
        guard row >= 0, row < visibleItems.count else { return false }
        let item = visibleItems[row]
        if let commitCharacter,
           AttoLspCompletionParser.isCommitCharacter(commitCharacter, for: item) == false
        {
            return false
        }

        hide()
        onCommit?(item, commitCharacter)
        return true
    }

    private func updatePreviewForSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0, row < visibleItems.count else {
            previewTextView.string = ""
            return
        }
        previewTextView.string = AttoLspCompletionParser.previewText(for: visibleItems[row]) ?? visibleItems[row].label
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

private final class AttoCompletionTableView: NSTableView {
    var onCommit: (() -> Void)?
    var onCommitCharacter: ((String) -> Bool)?
    var onTextInput: ((String) -> Bool)?
    var onDeleteBackward: (() -> Bool)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommit?()
        case 51:
            if onDeleteBackward?() == true {
                return
            }
            super.keyDown(with: event)
        case 53:
            onCancel?()
        default:
            let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
            if event.modifierFlags.intersection(disallowedModifiers).isEmpty,
               let characters = event.characters,
               onCommitCharacter?(characters) == true
            {
                return
            }
            if event.modifierFlags.intersection(disallowedModifiers).isEmpty,
               let characters = event.characters,
               Self.isPlainTextInput(characters),
               onTextInput?(characters) == true
            {
                return
            }
            super.keyDown(with: event)
        }
    }

    private static func isPlainTextInput(_ text: String) -> Bool {
        guard text.isEmpty == false else { return false }
        for scalar in text.unicodeScalars
            where CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
        {
            return false
        }
        return true
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
