import AppKit
import EditorCoreUIFFI
import Foundation

@MainActor
final class AttoProblemsPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    typealias WorkspaceDiagnostic = AttoLspWorkspaceDiagnosticsParser.Diagnostic

    struct AccessibilityIDs {
        let panel: String
        let root: String
        let searchField: String
        let table: String
        let scrollView: String
        let row: String
        let rowTitle: String

        static let activeProblems = AccessibilityIDs(
            panel: AttoAccessibilityID.problemsPanel,
            root: AttoAccessibilityID.problemsPanelRoot,
            searchField: AttoAccessibilityID.problemsPanelSearchField,
            table: AttoAccessibilityID.problemsPanelTable,
            scrollView: AttoAccessibilityID.problemsPanelScrollView,
            row: AttoAccessibilityID.problemsPanelRow,
            rowTitle: AttoAccessibilityID.problemsPanelRowTitle
        )

        static let workspaceProblems = AccessibilityIDs(
            panel: AttoAccessibilityID.workspaceProblemsPanel,
            root: AttoAccessibilityID.workspaceProblemsPanelRoot,
            searchField: AttoAccessibilityID.workspaceProblemsPanelSearchField,
            table: AttoAccessibilityID.workspaceProblemsPanelTable,
            scrollView: AttoAccessibilityID.workspaceProblemsPanelScrollView,
            row: AttoAccessibilityID.workspaceProblemsPanelRow,
            rowTitle: AttoAccessibilityID.workspaceProblemsPanelRowTitle
        )
    }

    private enum Payload {
        case active(EcuDiagnostic)
        case workspace(WorkspaceDiagnostic)
        case unified(AttoUnifiedDiagnosticProblem)
    }

    private struct Row {
        let payload: Payload
        let title: String
        let message: String
        let severity: String?
        let source: String?
        let code: String?
    }

    private let accessibilityIDs: AccessibilityIDs
    private let titleForDiagnostic: ((EcuDiagnostic) -> String)?
    private let onOpenDiagnostic: ((EcuDiagnostic) -> Void)?
    private let titleForWorkspaceDiagnostic: ((WorkspaceDiagnostic) -> String)?
    private let onOpenWorkspaceDiagnostic: ((WorkspaceDiagnostic) -> Void)?
    private let titleForProblem: ((AttoUnifiedDiagnosticProblem) -> String)?
    private let onOpenProblem: ((AttoUnifiedDiagnosticProblem) -> Void)?
    private var diagnostics: [EcuDiagnostic] = []
    private var workspaceDiagnostics: [WorkspaceDiagnostic] = []
    private var problems: [AttoUnifiedDiagnosticProblem] = []
    private var rows: [Row] = []
    private var filteredRows: [Row] = []
    private var title = "Problems"
    private var placeholder = "Filter problems..."
    private var panel: NSPanel?
    private let searchField = NSSearchField(frame: .zero)
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

    init(
        titleForDiagnostic: @escaping (EcuDiagnostic) -> String,
        onOpen: @escaping (EcuDiagnostic) -> Void,
        accessibilityIDs: AccessibilityIDs = .activeProblems
    ) {
        self.accessibilityIDs = accessibilityIDs
        self.titleForDiagnostic = titleForDiagnostic
        self.onOpenDiagnostic = onOpen
        titleForWorkspaceDiagnostic = nil
        onOpenWorkspaceDiagnostic = nil
        titleForProblem = nil
        onOpenProblem = nil
        super.init()
    }

    init(
        titleForWorkspaceDiagnostic: @escaping (WorkspaceDiagnostic) -> String,
        onOpen: @escaping (WorkspaceDiagnostic) -> Void,
        accessibilityIDs: AccessibilityIDs = .workspaceProblems
    ) {
        self.accessibilityIDs = accessibilityIDs
        titleForDiagnostic = nil
        onOpenDiagnostic = nil
        self.titleForWorkspaceDiagnostic = titleForWorkspaceDiagnostic
        self.onOpenWorkspaceDiagnostic = onOpen
        titleForProblem = nil
        onOpenProblem = nil
        super.init()
    }

    init(
        titleForProblem: @escaping (AttoUnifiedDiagnosticProblem) -> String,
        onOpen: @escaping (AttoUnifiedDiagnosticProblem) -> Void,
        accessibilityIDs: AccessibilityIDs = .activeProblems
    ) {
        self.accessibilityIDs = accessibilityIDs
        titleForDiagnostic = nil
        onOpenDiagnostic = nil
        titleForWorkspaceDiagnostic = nil
        onOpenWorkspaceDiagnostic = nil
        self.titleForProblem = titleForProblem
        onOpenProblem = onOpen
        super.init()
    }

    var currentDiagnostics: [EcuDiagnostic] {
        diagnostics
    }

    var currentWorkspaceDiagnostics: [WorkspaceDiagnostic] {
        workspaceDiagnostics
    }

    var currentProblems: [AttoUnifiedDiagnosticProblem] {
        problems
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var rowCount: Int {
        filteredRows.count
    }

    func update(diagnostics: [EcuDiagnostic], title: String = "Problems", placeholder: String = "Filter problems...") {
        self.diagnostics = diagnostics
        workspaceDiagnostics = []
        problems = []
        self.title = title
        self.placeholder = placeholder
        let titleForDiagnostic = titleForDiagnostic ?? { $0.message }
        rows = diagnostics.map { diagnostic in
            Row(
                payload: .active(diagnostic),
                title: titleForDiagnostic(diagnostic),
                message: diagnostic.message,
                severity: diagnostic.severity?.rawValue,
                source: diagnostic.source,
                code: diagnostic.code
            )
        }
        applyFilter()
        updateTitle()
    }

    func update(
        workspaceDiagnostics: [WorkspaceDiagnostic],
        title: String = "Workspace Problems",
        placeholder: String = "Filter workspace problems..."
    ) {
        diagnostics = []
        self.workspaceDiagnostics = workspaceDiagnostics
        problems = []
        self.title = title
        self.placeholder = placeholder
        let titleForWorkspaceDiagnostic = titleForWorkspaceDiagnostic ?? { $0.message }
        rows = workspaceDiagnostics.map { diagnostic in
            Row(
                payload: .workspace(diagnostic),
                title: titleForWorkspaceDiagnostic(diagnostic),
                message: diagnostic.message,
                severity: diagnostic.severityLabel,
                source: diagnostic.source,
                code: diagnostic.code
            )
        }
        applyFilter()
        updateTitle()
    }

    func update(
        problems: [AttoUnifiedDiagnosticProblem],
        title: String = "Problems",
        placeholder: String = "Filter problems..."
    ) {
        diagnostics = []
        workspaceDiagnostics = []
        self.problems = problems
        self.title = title
        self.placeholder = placeholder
        let titleForProblem = titleForProblem ?? { $0.message }
        rows = problems.map { problem in
            Row(
                payload: .unified(problem),
                title: titleForProblem(problem),
                message: problem.message,
                severity: problem.severity?.rawValue,
                source: problem.diagnosticSource,
                code: problem.code
            )
        }
        applyFilter()
        updateTitle()
    }

    @discardableResult
    func show(
        relativeTo window: NSWindow,
        diagnostics: [EcuDiagnostic],
        title: String = "Problems",
        placeholder: String = "Filter problems..."
    ) -> Bool {
        update(diagnostics: diagnostics, title: title, placeholder: placeholder)
        return showUpdatedPanel(relativeTo: window)
    }

    @discardableResult
    func show(
        relativeTo window: NSWindow,
        workspaceDiagnostics: [WorkspaceDiagnostic],
        title: String = "Workspace Problems",
        placeholder: String = "Filter workspace problems..."
    ) -> Bool {
        update(workspaceDiagnostics: workspaceDiagnostics, title: title, placeholder: placeholder)
        return showUpdatedPanel(relativeTo: window)
    }

    @discardableResult
    func show(
        relativeTo window: NSWindow,
        problems: [AttoUnifiedDiagnosticProblem],
        title: String = "Problems",
        placeholder: String = "Filter problems..."
    ) -> Bool {
        update(problems: problems, title: title, placeholder: placeholder)
        return showUpdatedPanel(relativeTo: window)
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    private func showUpdatedPanel(relativeTo window: NSWindow) -> Bool {
        if panel == nil {
            panel = buildPanel()
        }

        guard let panel else { return false }
        updateTitle()
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

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
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
        panel.identifier = NSUserInterfaceItemIdentifier(accessibilityIDs.panel)

        let root = NSView(frame: .zero)
        root.identifier = NSUserInterfaceItemIdentifier(accessibilityIDs.root)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(attoHex: 0x252526, alpha: 0.98).cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        searchField.placeholderString = placeholder
        searchField.identifier = NSUserInterfaceItemIdentifier(accessibilityIDs.searchField)
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.textColor = NSColor(attoHex: 0xFFFFFF)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("problem"))
        column.title = "Problem"
        column.width = 720
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.backgroundColor = NSColor(attoHex: 0x252526)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.doubleAction = #selector(doubleClicked(_:))
        tableView.target = self
        tableView.identifier = NSUserInterfaceItemIdentifier(accessibilityIDs.table)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.identifier = NSUserInterfaceItemIdentifier(accessibilityIDs.scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(searchField)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])

        updateTitle()
        return panel
    }

    private func updateTitle() {
        guard let panel else { return }
        panel.title = "\(title) (\(rows.count))"
        searchField.placeholderString = placeholder
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let width = max(panel.frame.width, 760)
        let height = max(panel.frame.height, 420)
        let winFrame = window.frame
        var x = winFrame.maxX - width - 48
        var y = winFrame.maxY - height - 120

        let visible = screen.visibleFrame
        x = max(visible.minX + 20, min(x, visible.maxX - width - 20))
        y = max(visible.minY + 20, min(y, visible.maxY - height - 20))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredRows = rows
        } else {
            filteredRows = rows.filter { row in
                row.title.localizedCaseInsensitiveContains(query)
                    || row.message.localizedCaseInsensitiveContains(query)
                    || row.severity?.localizedCaseInsensitiveContains(query) == true
                    || row.source?.localizedCaseInsensitiveContains(query) == true
                    || row.code?.localizedCaseInsensitiveContains(query) == true
            }
        }
        tableView.reloadData()
        if filteredRows.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredRows.count else { return nil }
        let item = filteredRows[row]

        let id = NSUserInterfaceItemIdentifier(accessibilityIDs.row)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id

        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.identifier = NSUserInterfaceItemIdentifier(accessibilityIDs.rowTitle)
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

        label.stringValue = item.title
        return cell
    }

    @objc private func doubleClicked(_ sender: Any?) {
        openSelectedProblem()
    }

    private func openSelectedProblem() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredRows.count else { return }
        switch filteredRows[row].payload {
        case let .active(diagnostic):
            onOpenDiagnostic?(diagnostic)
        case let .workspace(diagnostic):
            onOpenWorkspaceDiagnostic?(diagnostic)
        case let .unified(problem):
            onOpenProblem?(problem)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        case #selector(NSResponder.moveDown(_:)):
            let next = min(tableView.selectedRow + 1, filteredRows.count - 1)
            if next >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                tableView.scrollRowToVisible(next)
            }
            return true
        case #selector(NSResponder.moveUp(_:)):
            let previous = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: previous), byExtendingSelection: false)
            tableView.scrollRowToVisible(previous)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelectedProblem()
            return true
        default:
            return false
        }
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
