import AppKit
import Foundation

@MainActor
final class AttoFileExplorerViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onOpenFile: ((URL) -> Void)?
    var onPreviewFile: ((URL) -> Void)?

    private var rootURL: URL
    private var rootNode: AttoFileNode

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let headerLabel = NSTextField(labelWithString: "EXPLORER")

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.rootNode = AttoFileNode(url: rootURL, isRoot: true)
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
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.backgroundColor = NSColor(attoHex: 0x252526)
        outlineView.selectionHighlightStyle = .regular
        outlineView.focusRingType = .none
        outlineView.doubleAction = #selector(doubleClicked(_:))
        outlineView.target = self

        scrollView.documentView = outlineView
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
        outlineView.expandItem(rootNode)
    }

    func setRootURL(_ url: URL) {
        rootURL = url
        rootNode = AttoFileNode(url: url, isRoot: true)
        reload()
        outlineView.expandItem(rootNode)
    }

    func revealFile(_ url: URL) {
        // MVP: best-effort reveal only if it is under the current root.
        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        guard targetPath.hasPrefix(rootPath) else { return }

        // Build the path components from root to target.
        let rel = targetPath.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard rel.isEmpty == false else { return }
        let parts = rel.split(separator: "/").map(String.init)

        var node: AttoFileNode = rootNode
        outlineView.expandItem(node)
        for (idx, name) in parts.enumerated() {
            guard node.isDirectory else { break }
            let children = node.children()
            guard let next = children.first(where: { $0.url.lastPathComponent == name }) else { break }
            node = next
            outlineView.expandItem(node)
            if idx == parts.count - 1 {
                outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: node)), byExtendingSelection: false)
                outlineView.scrollRowToVisible(outlineView.row(forItem: node))
            }
        }
    }

    private func reload() {
        outlineView.reloadData()
    }

    // MARK: - Actions

    func _handleDoubleClick(item: Any) {
        guard let node = item as? AttoFileNode else { return }

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
            return
        }

        onOpenFile?(node.url)
    }

    @objc private func doubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) else { return }
        _handleDoubleClick(item: item)
    }

    // MARK: - OutlineView data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? AttoFileNode else {
            return 1 // root item
        }
        return node.children().count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? AttoFileNode else { return false }
        return node.isDirectory
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? AttoFileNode else {
            return rootNode
        }
        return node.children()[index]
    }

    // MARK: - OutlineView delegate

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? AttoFileNode else { return }
        guard item.isDirectory == false else { return }
        onPreviewFile?(item.url)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? AttoFileNode else { return nil }

        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.font = NSFont.systemFont(ofSize: 12)
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

        imageView.image = node.icon()
        imageView.imageScaling = .scaleProportionallyDown

        textField.stringValue = node.displayName
        cell.toolTip = node.url.path

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
}

private final class AttoFileNode: NSObject {
    let url: URL
    let isRoot: Bool
    let isDirectory: Bool

    private var cachedChildren: [AttoFileNode]?

    init(url: URL, isRoot: Bool = false) {
        self.url = url
        self.isRoot = isRoot
        self.isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        super.init()
    }

    var displayName: String {
        if isRoot {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return url.lastPathComponent
    }

    func icon() -> NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    func children() -> [AttoFileNode] {
        guard isDirectory else { return [] }
        if let cachedChildren { return cachedChildren }

        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
        ]

        let urls = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: options
        )) ?? []

        let filtered = urls.filter { child in
            // MVP: hide some noisy build folders.
            let name = child.lastPathComponent
            if name == ".git" || name == "target" || name == ".build" { return false }
            return true
        }

        let nodes = filtered.map { AttoFileNode(url: $0) }
        let sorted = nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        cachedChildren = sorted
        return sorted
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
