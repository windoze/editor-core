import AppKit
import Foundation

@MainActor
final class AttoSettingsSchemaPageViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let setting = NSUserInterfaceItemIdentifier("setting")
        static let effective = NSUserInterfaceItemIdentifier("effective")
        static let source = NSUserInterfaceItemIdentifier("source")
        static let override = NSUserInterfaceItemIdentifier("override")
        static let validation = NSUserInterfaceItemIdentifier("validation")
    }

    private let schema: AttoConfigurationSettingsSchemaDescriptor
    private let settingsStore: AttoConfigurationSettingsStore
    private let workspaceRootURLProvider: @MainActor () -> URL?
    private let runtimeSettingsProvider: @MainActor () -> AttoConfigurationSettings?
    private let baseSnapshotProvider: @MainActor (URL?) -> AttoConfigurationSnapshot

    private let stack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let reloadButton = NSButton(title: "Reload", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    private var rows: [AttoSettingsSchemaRow] = []

    init(
        schema: AttoConfigurationSettingsSchemaDescriptor = AttoConfigurationSettingsSchema.current,
        settingsStore: AttoConfigurationSettingsStore = AttoConfigurationSettingsStore(),
        workspaceRootURLProvider: @escaping @MainActor () -> URL? = { nil },
        runtimeSettingsProvider: @escaping @MainActor () -> AttoConfigurationSettings? = { nil },
        baseSnapshotProvider: @escaping @MainActor (URL?) -> AttoConfigurationSnapshot = {
            AttoPreferences.shared.effectiveConfigurationSnapshot(workspaceRootURL: $0)
        }
    ) {
        self.schema = schema
        self.settingsStore = settingsStore
        self.workspaceRootURLProvider = workspaceRootURLProvider
        self.runtimeSettingsProvider = runtimeSettingsProvider
        self.baseSnapshotProvider = baseSnapshotProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHeader()
        configureTable()
        configureLayout()
        reloadRows()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .attoPreferencesDidChange,
            object: nil
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadRows()
    }

    func reloadRows() {
        let workspaceRootURL = workspaceRootURLProvider()
        var loadErrors: [String] = []
        let userSettings = loadUserSettings(loadErrors: &loadErrors)
        let workspaceSettings = loadWorkspaceSettings(
            workspaceRootURL: workspaceRootURL,
            loadErrors: &loadErrors
        )
        let runtimeSettings = runtimeSettingsProvider()
        let validationIssues = validationIssues(
            userSettings: userSettings,
            workspaceSettings: workspaceSettings,
            runtimeSettings: runtimeSettings
        )

        rows = AttoSettingsSchemaRows.make(
            schema: schema,
            baseSnapshot: baseSnapshotProvider(workspaceRootURL),
            userSettings: userSettings,
            workspaceSettings: workspaceSettings,
            runtimeSettings: runtimeSettings,
            validationIssues: validationIssues
        )
        updateStatus(workspaceRootURL: workspaceRootURL, loadErrors: loadErrors)
        tableView.reloadData()
    }

    func rowsForTesting() -> [AttoSettingsSchemaRow] {
        rows
    }

    private func configureHeader() {
        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        reloadButton.target = self
        reloadButton.action = #selector(reloadClicked(_:))
        reloadButton.bezelStyle = .rounded

        let headerRow = NSStackView(views: [title, NSView(), reloadButton])
        headerRow.orientation = .horizontal
        headerRow.spacing = 12
        headerRow.alignment = .centerY
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(statusLabel)
        headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func configureTable() {
        tableView.addTableColumn(makeColumn(identifier: Column.setting, title: "Setting", width: 210))
        tableView.addTableColumn(makeColumn(identifier: Column.effective, title: "Effective", width: 145))
        tableView.addTableColumn(makeColumn(identifier: Column.source, title: "Source", width: 95))
        tableView.addTableColumn(makeColumn(identifier: Column.override, title: "Override", width: 230))
        tableView.addTableColumn(makeColumn(identifier: Column.validation, title: "Validation", width: 250))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 54
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
    }

    private func configureLayout() {
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(scrollView)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makeColumn(
        identifier: NSUserInterfaceItemIdentifier,
        title: String,
        width: CGFloat
    ) -> NSTableColumn {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = 70
        return column
    }

    private func loadUserSettings(loadErrors: inout [String]) -> AttoConfigurationSettings? {
        do {
            return try settingsStore.loadUserSettings()
        } catch {
            loadErrors.append("User settings failed to load")
            NSLog(
                "AttoEditor: failed to load user settings %@ for schema settings page: %@",
                settingsStore.userSettingsURL.path,
                String(describing: error)
            )
            return nil
        }
    }

    private func loadWorkspaceSettings(
        workspaceRootURL: URL?,
        loadErrors: inout [String]
    ) -> AttoConfigurationSettings? {
        guard let workspaceRootURL else { return nil }
        do {
            return try settingsStore.loadWorkspaceSettings(workspaceRootURL: workspaceRootURL)
        } catch {
            loadErrors.append("Workspace settings failed to load")
            NSLog(
                "AttoEditor: failed to load workspace settings %@ for schema settings page: %@",
                AttoConfigurationSettingsStore.workspaceSettingsURL(forWorkspaceRootURL: workspaceRootURL).path,
                String(describing: error)
            )
            return nil
        }
    }

    private func validationIssues(
        userSettings: AttoConfigurationSettings?,
        workspaceSettings: AttoConfigurationSettings?,
        runtimeSettings: AttoConfigurationSettings?
    ) -> [AttoConfigurationSettingsValidationIssue] {
        var issues: [AttoConfigurationSettingsValidationIssue] = []
        if let userSettings {
            issues.append(contentsOf: schema.validate(userSettings, scope: .user).issues)
        }
        if let workspaceSettings {
            issues.append(contentsOf: schema.validate(workspaceSettings, scope: .workspace).issues)
        }
        if let runtimeSettings {
            issues.append(contentsOf: schema.validate(runtimeSettings, scope: .runtime).issues)
        }
        return issues
    }

    private func updateStatus(
        workspaceRootURL: URL?,
        loadErrors: [String]
    ) {
        let workspaceText = workspaceRootURL?.path ?? "None"
        let base = "Workspace: \(workspaceText)"
        statusLabel.stringValue = loadErrors.isEmpty
            ? base
            : "\(base) - \(loadErrors.joined(separator: "; "))"
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard (0..<rows.count).contains(row),
              let tableColumn
        else {
            return nil
        }

        let row = rows[row]
        let identifier = NSUserInterfaceItemIdentifier("AttoSettingsSchemaCell-\(tableColumn.identifier.rawValue)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: identifier)
        configureCell(cell, row: row, columnIdentifier: tableColumn.identifier)
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView(frame: .zero)
        cell.identifier = identifier

        let textField = NSTextField(wrappingLabelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 3
        textField.allowsDefaultTighteningForTruncation = true
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.topAnchor.constraint(greaterThanOrEqualTo: cell.topAnchor, constant: 4),
            textField.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func configureCell(
        _ cell: NSTableCellView,
        row: AttoSettingsSchemaRow,
        columnIdentifier: NSUserInterfaceItemIdentifier
    ) {
        guard let textField = cell.textField else { return }
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = .labelColor

        switch columnIdentifier {
        case Column.setting:
            textField.stringValue = "\(row.title)\n\(row.keyPath)"
            textField.textColor = .labelColor
        case Column.effective:
            textField.stringValue = row.effectiveValue
        case Column.source:
            textField.stringValue = row.source
        case Column.override:
            textField.stringValue = row.overrideValue
            textField.textColor = row.overrideValue == "None" ? .secondaryLabelColor : .labelColor
        case Column.validation:
            textField.stringValue = row.validationError.isEmpty ? "None" : row.validationError
            textField.textColor = row.validationError.isEmpty ? .secondaryLabelColor : .systemRed
        default:
            textField.stringValue = ""
        }
    }

    @objc private func reloadClicked(_ sender: NSButton) {
        reloadRows()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadRows()
    }
}
