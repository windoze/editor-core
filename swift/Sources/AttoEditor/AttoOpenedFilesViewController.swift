import AppKit
import Foundation

@MainActor
final class AttoOpenedFilesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectFile: ((URL) -> Void)?

    private var rootURL: URL
    private var items: [AttoEditorAreaViewController.OpenFileItem] = []
    private var selectedID: UUID?
    private var isProgrammaticSelection: Bool = false

    private let headerLabel = NSTextField(labelWithString: "OPEN EDITORS")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView()

    init(rootURL: URL) {
        self.rootURL = rootURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(attoHex: 0x252526).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = NSColor(attoHex: 0xBBBBBB)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerLabel)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        reload()
    }

    func setRootURL(_ url: URL) {
        rootURL = url.standardizedFileURL
        reload()
    }

    func updateOpenFiles(_ items: [AttoEditorAreaViewController.OpenFileItem], selectedID: UUID?) {
        self.items = items
        self.selectedID = selectedID
        reload()
        syncSelection()
    }

    private func reload() {
        tableView.reloadData()
    }

    private func syncSelection() {
        guard let selectedID else {
            isProgrammaticSelection = true
            tableView.deselectAll(nil)
            isProgrammaticSelection = false
            return
        }

        guard let idx = items.firstIndex(where: { $0.id == selectedID }) else {
            isProgrammaticSelection = true
            tableView.deselectAll(nil)
            isProgrammaticSelection = false
            return
        }

        isProgrammaticSelection = true
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        tableView.scrollRowToVisible(idx)
        isProgrammaticSelection = false
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    // MARK: - NSTableViewDelegate

    func tableViewSelectionDidChange(_ notification: Notification) {
        if isProgrammaticSelection { return }
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        onSelectFile?(items[row].url)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        let item = items[row]

        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        textField.textColor = NSColor(attoHex: 0xCCCCCC)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.translatesAutoresizingMaskIntoConstraints = false

        let imageView = cell.imageView ?? NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false

        if cell.textField == nil {
            cell.textField = textField
            cell.addSubview(textField)
        }
        if cell.imageView == nil {
            cell.imageView = imageView
            cell.addSubview(imageView)
        }

        imageView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        imageView.imageScaling = .scaleProportionallyDown

        let displayPath = relativePathForDisplay(item.url)
        if item.isDirty {
            textField.stringValue = "● \(displayPath)"
        } else {
            textField.stringValue = displayPath
        }
        cell.toolTip = item.url.path

        if cell.constraints.isEmpty {
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            ])
        }

        return cell
    }

    private func relativePathForDisplay(_ url: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == root {
            return url.lastPathComponent
        }
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
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

