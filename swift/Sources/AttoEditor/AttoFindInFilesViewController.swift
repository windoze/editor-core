import AppKit
import AttoEditorSupport
import Foundation

@MainActor
final class AttoFindInFilesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate {
    enum Scope: Int {
        case openedFiles = 0
        case workspace = 1
    }

    struct SearchResult: Hashable, Sendable {
        let url: URL
        let line1: Int
        let column1: Int
        let lineText: String
    }

    var onOpenResult: ((URL, AttoCommandLine.FileLocation) -> Void)?
    var openedFilesProvider: (() -> [URL])?
    var workspaceFilesProvider: (() -> [URL])?

    private var rootURL: URL

    private var results: [SearchResult] = []
    private var lastSearchToken: UInt64 = 0
    private var searchDebounceWorkItem: DispatchWorkItem?

    private let headerLabel = NSTextField(labelWithString: "FIND IN FILES")
    private let queryField = NSSearchField(frame: .zero)
    private let scopeControl = NSSegmentedControl(labels: ["Opened", "Folder"], trackingMode: .selectOne, target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView()

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
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

        queryField.placeholderString = "Search"
        queryField.controlSize = .small
        queryField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        queryField.focusRingType = .none
        queryField.delegate = self
        queryField.translatesAutoresizingMaskIntoConstraints = false

        scopeControl.controlSize = .small
        scopeControl.selectedSegment = Scope.openedFiles.rawValue
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged(_:))
        scopeControl.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = NSColor(attoHex: 0xB5B5B5)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.stringValue = "Type to search…"

        let controlsRow = NSStackView(views: [queryField, scopeControl])
        controlsRow.orientation = .horizontal
        controlsRow.alignment = .centerY
        controlsRow.spacing = 8
        controlsRow.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(resultDoubleClicked(_:))
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerLabel)
        view.addSubview(controlsRow)
        view.addSubview(statusLabel)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),

            controlsRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            controlsRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            controlsRow.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            statusLabel.topAnchor.constraint(equalTo: controlsRow.bottomAnchor, constant: 6),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func setRootURL(_ url: URL) {
        rootURL = url.standardizedFileURL
        // Results are likely irrelevant after changing root.
        clearResults()
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(queryField)
    }

    // MARK: - Actions

    @objc private func scopeChanged(_ sender: Any?) {
        scheduleSearch()
    }

    @objc private func resultDoubleClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, row < results.count else { return }
        open(result: results[row])
    }

    // MARK: - Searching

    func controlTextDidChange(_ obj: Notification) {
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performSearch()
        }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func performSearch() {
        let rawQuery = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawQuery.isEmpty {
            clearResults()
            statusLabel.stringValue = "Type to search…"
            return
        }

        let scope = Scope(rawValue: scopeControl.selectedSegment) ?? .openedFiles

        let files: [URL] = {
            switch scope {
            case .openedFiles:
                return openedFilesProvider?() ?? []
            case .workspace:
                return workspaceFilesProvider?() ?? []
            }
        }()

        let token = lastSearchToken &+ 1
        lastSearchToken = token
        statusLabel.stringValue = "Searching…"

        DispatchQueue.global(qos: .userInitiated).async { [rawQuery, token] in
            let found = Self.search(query: rawQuery, inFiles: files)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.lastSearchToken == token else { return }
                self.results = found
                self.tableView.reloadData()
                self.statusLabel.stringValue = "\(found.count) results"
            }
        }
    }

    private func clearResults() {
        results = []
        tableView.reloadData()
    }

    private func open(result: SearchResult) {
        let loc = AttoCommandLine.FileLocation(line1: max(1, result.line1), column1: max(1, result.column1))
        onOpenResult?(result.url, loc)
    }

    nonisolated private static func search(query: String, inFiles files: [URL]) -> [SearchResult] {
        var out: [SearchResult] = []
        out.reserveCapacity(128)

        // MVP: cap results to keep the UI responsive.
        let maxResults = 2000

        let q = query
        let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        for url in files {
            if out.count >= maxResults { break }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, lineSub) in lines.enumerated() {
                if out.count >= maxResults { break }

                let line = String(lineSub)
                guard let range = line.range(of: q, options: compareOptions) else { continue }

                let col1 = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let preview = trimmed.count > 240 ? String(trimmed.prefix(240)) + "…" : trimmed
                out.append(
                    SearchResult(
                        url: url.standardizedFileURL,
                        line1: idx + 1,
                        column1: col1,
                        lineText: preview
                    )
                )
            }
        }

        // Stable order: file path, then line.
        out.sort { a, b in
            if a.url.path != b.url.path { return a.url.path < b.url.path }
            if a.line1 != b.line1 { return a.line1 < b.line1 }
            return a.column1 < b.column1
        }

        return out
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < results.count else { return nil }
        let r = results[row]

        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        textField.textColor = NSColor(attoHex: 0xCCCCCC)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.translatesAutoresizingMaskIntoConstraints = false

        if cell.textField == nil {
            cell.textField = textField
            cell.addSubview(textField)
        }

        let path = relativePathForDisplay(r.url, rootURL: rootURL)
        textField.stringValue = "\(path):\(r.line1)  \(r.lineText)"
        cell.toolTip = "\(r.url.path):\(r.line1)"

        if cell.constraints.isEmpty {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            ])
        }

        return cell
    }

    private func relativePathForDisplay(_ url: URL, rootURL: URL) -> String {
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
