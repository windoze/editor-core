import AppKit
import AttoEditorSupport
import Foundation

@MainActor
final class AttoFindInFilesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate {
    enum Scope: Int, Equatable {
        case openedFiles = 0
        case workspace = 1

        init(configurationValue value: String?) {
            let normalized = (value ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")

            switch normalized {
            case "folder", "folders", "workspace", "workspace_files":
                self = .workspace
            case "open", "opened", "open_files", "opened_files", "tabs", "open_tabs":
                self = .openedFiles
            default:
                self = .openedFiles
            }
        }

        var configurationValue: String {
            switch self {
            case .openedFiles:
                return "opened_files"
            case .workspace:
                return "workspace"
            }
        }
    }

    struct SearchResult: Hashable, Sendable {
        let url: URL
        let line1: Int
        let column1: Int
        let lineText: String
    }

    struct SearchOptions: Hashable, Sendable {
        var caseSensitive: Bool
        var wholeWord: Bool
        var regex: Bool

        static let `default` = SearchOptions(caseSensitive: false, wholeWord: false, regex: false)
    }

    enum WorkspaceSearchProviderResult {
        case results([SearchResult])
        case unavailable
        case failed(String)
    }

    var onOpenResult: ((URL, AttoCommandLine.FileLocation) -> Void)?
    var openedFilesSearchProvider: ((String, SearchOptions) -> [SearchResult])?
    var workspaceFilesSearchProvider: ((String, [String], [String], SearchOptions) -> WorkspaceSearchProviderResult)?
    var workspaceFilesReplaceProvider: ((String, String, [String], [String], SearchOptions) -> Bool)? {
        didSet {
            updateReplaceControls()
        }
    }
    var openedFilesProvider: (() -> [URL])?
    var workspaceFilesProvider: (() -> [URL])?

    private var rootURL: URL

    private var results: [SearchResult] = []
    private var lastSearchToken: UInt64 = 0
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var defaultScope: Scope = .openedFiles
    private var workspaceSearchIncludeGlobs: [String] = []
    private var workspaceSearchExcludeGlobs: [String] = []
    private var workspaceReplacementEnabled = false
    private var defaultSearchOptions: SearchOptions = .default

    private let headerLabel = NSTextField(labelWithString: "FIND IN FILES")
    private let queryField = NSSearchField(frame: .zero)
    private let replacementField = NSTextField(frame: .zero)
    private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)
    private let caseSensitiveButton = NSButton(checkboxWithTitle: "Aa", target: nil, action: nil)
    private let wholeWordButton = NSButton(checkboxWithTitle: "Word", target: nil, action: nil)
    private let regexButton = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
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
        view.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFiles)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(attoHex: 0x252526).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = NSColor(attoHex: 0xBBBBBB)
        headerLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesHeader)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        queryField.placeholderString = "Search"
        queryField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesQueryField)
        queryField.controlSize = .small
        queryField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        queryField.focusRingType = .none
        queryField.delegate = self
        queryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        queryField.translatesAutoresizingMaskIntoConstraints = false

        replacementField.placeholderString = "Replace"
        replacementField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesReplacementField)
        replacementField.controlSize = .small
        replacementField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        replacementField.focusRingType = .none
        replacementField.delegate = self
        replacementField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            replacementField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        replaceAllButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesReplaceAllButton)
        replaceAllButton.controlSize = .small
        replaceAllButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAllClicked(_:))
        replaceAllButton.translatesAutoresizingMaskIntoConstraints = false

        for button in [caseSensitiveButton, wholeWordButton, regexButton] {
            button.setButtonType(.switch)
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.action = #selector(searchOptionsChanged(_:))
        }
        caseSensitiveButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesCaseSensitiveButton)
        wholeWordButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesWholeWordButton)
        regexButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesRegexButton)
        applySearchOptionsToButtons(defaultSearchOptions)

        scopeControl.controlSize = .small
        scopeControl.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesScopeControl)
        scopeControl.selectedSegment = defaultScope.rawValue
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged(_:))
        scopeControl.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = NSColor(attoHex: 0xB5B5B5)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesStatusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.stringValue = "Type to search…"

        let queryScopeRow = NSStackView(views: [
            queryField,
            scopeControl,
        ])
        queryScopeRow.orientation = .horizontal
        queryScopeRow.alignment = .centerY
        queryScopeRow.spacing = 8

        let optionsRow = NSStackView(views: [
            caseSensitiveButton,
            wholeWordButton,
            regexButton,
        ])
        optionsRow.orientation = .horizontal
        optionsRow.alignment = .centerY
        optionsRow.spacing = 8

        let controlsColumn = NSStackView(views: [queryScopeRow, optionsRow])
        controlsColumn.orientation = .vertical
        controlsColumn.alignment = .width
        controlsColumn.spacing = 4
        controlsColumn.translatesAutoresizingMaskIntoConstraints = false

        let replaceRow = NSStackView(views: [replacementField, replaceAllButton])
        replaceRow.orientation = .horizontal
        replaceRow.alignment = .centerY
        replaceRow.spacing = 8
        replaceRow.translatesAutoresizingMaskIntoConstraints = false

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
        tableView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesTable)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesScrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerLabel)
        view.addSubview(controlsColumn)
        view.addSubview(replaceRow)
        view.addSubview(statusLabel)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),

            controlsColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            controlsColumn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            controlsColumn.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),

            replaceRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            replaceRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            replaceRow.topAnchor.constraint(equalTo: controlsColumn.bottomAnchor, constant: 6),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            statusLabel.topAnchor.constraint(equalTo: replaceRow.bottomAnchor, constant: 6),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateReplaceControls()
    }

    func setRootURL(_ url: URL) {
        rootURL = url.standardizedFileURL
        // Results are likely irrelevant after changing root.
        clearResults()
    }

    func setDefaultScope(_ scope: Scope) {
        defaultScope = scope
        guard isViewLoaded else { return }

        let previousScope = selectedScope()
        scopeControl.selectedSegment = scope.rawValue
        if previousScope != scope {
            scheduleSearch()
        }
    }

    func setDefaultScope(configurationValue value: String) {
        setDefaultScope(Scope(configurationValue: value))
    }

    func setWorkspaceSearchGlobs(include: [String], exclude: [String]) {
        let normalizedInclude = AttoFindInFilesSearchEngine.normalizedGlobPatterns(include)
        let normalizedExclude = AttoFindInFilesSearchEngine.normalizedGlobPatterns(exclude)
        guard normalizedInclude != workspaceSearchIncludeGlobs
            || normalizedExclude != workspaceSearchExcludeGlobs
        else {
            return
        }

        workspaceSearchIncludeGlobs = normalizedInclude
        workspaceSearchExcludeGlobs = normalizedExclude
        if isViewLoaded, selectedScope() == .workspace {
            scheduleSearch()
        }
    }

    func setWorkspaceReplacementEnabled(_ enabled: Bool) {
        workspaceReplacementEnabled = enabled
        updateReplaceControls()
    }

    func setSearchOptions(_ options: SearchOptions) {
        defaultSearchOptions = options
        guard isViewLoaded else { return }
        applySearchOptionsToButtons(options)
        scheduleSearch()
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(queryField)
    }

    func _selectedScopeForTesting() -> Scope {
        selectedScope()
    }

    func _filteredWorkspaceFileURLsForTesting(_ files: [URL]) -> [URL] {
        filteredWorkspaceFiles(files)
    }

    func _setSearchOptionsForTesting(_ options: SearchOptions) {
        _ = view
        applySearchOptionsToButtons(options)
    }

    func _searchOptionsForTesting() -> SearchOptions {
        _ = view
        return currentSearchOptions()
    }

    func _performSearchForTesting(query: String, scope: Scope) {
        _ = view
        scopeControl.selectedSegment = scope.rawValue
        queryField.stringValue = query
        performSearch()
    }

    func _searchResultsForTesting() -> [SearchResult] {
        results
    }

    func _statusTextForTesting() -> String {
        _ = view
        return statusLabel.stringValue
    }

    func _replaceWorkspaceMatchesForTesting(
        query: String,
        replacement: String,
        scope: Scope = .workspace
    ) -> Bool {
        _ = view
        scopeControl.selectedSegment = scope.rawValue
        queryField.stringValue = query
        replacementField.stringValue = replacement
        updateReplaceControls()
        return performReplaceAll()
    }

    func _replaceAllButtonIsEnabledForTesting(
        query: String,
        replacement: String = "",
        scope: Scope = .workspace
    ) -> Bool {
        _ = view
        scopeControl.selectedSegment = scope.rawValue
        queryField.stringValue = query
        replacementField.stringValue = replacement
        updateReplaceControls()
        return replaceAllButton.isEnabled
    }

    // MARK: - Actions

    @objc private func scopeChanged(_ sender: Any?) {
        updateReplaceControls()
        scheduleSearch()
    }

    @objc private func resultDoubleClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, row < results.count else { return }
        open(result: results[row])
    }

    @objc private func replaceAllClicked(_ sender: Any?) {
        _ = performReplaceAll()
    }

    @objc private func searchOptionsChanged(_ sender: Any?) {
        scheduleSearch()
    }

    // MARK: - Searching

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === replacementField {
            updateReplaceControls()
            return
        }
        updateReplaceControls()
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
            updateReplaceControls()
            return
        }

        let scope = selectedScope()

        if scope == .openedFiles, let openedFilesSearchProvider {
            let token = lastSearchToken &+ 1
            lastSearchToken = token
            statusLabel.stringValue = "Searching…"
            let found = openedFilesSearchProvider(rawQuery, currentSearchOptions())
            guard lastSearchToken == token else { return }
            results = found
            tableView.reloadData()
            statusLabel.stringValue = "\(found.count) results"
            updateReplaceControls()
            return
        }

        if scope == .workspace, let workspaceFilesSearchProvider {
            let token = lastSearchToken &+ 1
            lastSearchToken = token
            statusLabel.stringValue = "Searching…"
            let providerResult = workspaceFilesSearchProvider(
                rawQuery,
                workspaceSearchIncludeGlobs,
                workspaceSearchExcludeGlobs,
                currentSearchOptions()
            )
            switch providerResult {
            case .results(let found):
                guard lastSearchToken == token else { return }
                results = found
                tableView.reloadData()
                statusLabel.stringValue = "\(found.count) results"
                updateReplaceControls()
                return
            case .unavailable:
                break
            case .failed(let reason):
                guard lastSearchToken == token else { return }
                results = []
                tableView.reloadData()
                let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                statusLabel.stringValue = trimmed.isEmpty
                    ? "Workspace search failed"
                    : "Workspace search failed: \(trimmed)"
                updateReplaceControls()
                return
            }
        }

        let files: [URL] = {
            switch scope {
            case .openedFiles:
                return openedFilesProvider?() ?? []
            case .workspace:
                return filteredWorkspaceFiles(workspaceFilesProvider?() ?? [])
            }
        }()

        let token = lastSearchToken &+ 1
        lastSearchToken = token
        statusLabel.stringValue = "Searching…"

        let options = currentSearchOptions()
        DispatchQueue.global(qos: .userInitiated).async { [rawQuery, token, files, options] in
            let found = AttoFindInFilesSearchEngine.search(query: rawQuery, options: options, inFiles: files)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.lastSearchToken == token else { return }
                self.results = found
                self.tableView.reloadData()
                self.statusLabel.stringValue = "\(found.count) results"
                self.updateReplaceControls()
            }
        }
    }

    private func clearResults() {
        results = []
        tableView.reloadData()
    }

    private func selectedScope() -> Scope {
        Scope(rawValue: scopeControl.selectedSegment) ?? defaultScope
    }

    private func currentSearchOptions() -> SearchOptions {
        SearchOptions(
            caseSensitive: caseSensitiveButton.state == .on,
            wholeWord: wholeWordButton.state == .on,
            regex: regexButton.state == .on
        )
    }

    private func applySearchOptionsToButtons(_ options: SearchOptions) {
        guard isViewLoaded else { return }
        caseSensitiveButton.state = options.caseSensitive ? .on : .off
        wholeWordButton.state = options.wholeWord ? .on : .off
        regexButton.state = options.regex ? .on : .off
        updateReplaceControls()
    }

    private func updateReplaceControls() {
        guard isViewLoaded else { return }
        let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        replaceAllButton.isEnabled = workspaceReplacementEnabled
            && selectedScope() == .workspace
            && query.isEmpty == false
            && workspaceFilesReplaceProvider != nil
    }

    @discardableResult
    private func performReplaceAll() -> Bool {
        let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            statusLabel.stringValue = "Type to search…"
            updateReplaceControls()
            NSSound.beep()
            return false
        }
        guard selectedScope() == .workspace else {
            statusLabel.stringValue = "Replace is available for Folder scope"
            updateReplaceControls()
            NSSound.beep()
            return false
        }
        guard workspaceReplacementEnabled, let workspaceFilesReplaceProvider else {
            statusLabel.stringValue = "Replace is unavailable"
            updateReplaceControls()
            NSSound.beep()
            return false
        }

        statusLabel.stringValue = "Replacing…"
        let applied = workspaceFilesReplaceProvider(
            query,
            replacementField.stringValue,
            workspaceSearchIncludeGlobs,
            workspaceSearchExcludeGlobs,
            currentSearchOptions()
        )
        if applied {
            statusLabel.stringValue = "Replacement applied"
        } else {
            statusLabel.stringValue = "Replacement not applied"
            NSSound.beep()
        }
        updateReplaceControls()
        return applied
    }

    private func filteredWorkspaceFiles(_ files: [URL]) -> [URL] {
        AttoFindInFilesSearchEngine.filteredWorkspaceFiles(
            files,
            rootURL: rootURL,
            includeGlobs: workspaceSearchIncludeGlobs,
            excludeGlobs: workspaceSearchExcludeGlobs
        )
    }

    private func open(result: SearchResult) {
        let loc = AttoCommandLine.FileLocation(line1: max(1, result.line1), column1: max(1, result.column1))
        onOpenResult?(result.url, loc)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < results.count else { return nil }
        let r = results[row]

        let id = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesRow)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findInFilesRowTitle)
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
