import AppKit
import Foundation

private enum AttoPreferencesPage: Int, CaseIterable {
    case editor

    var title: String {
        switch self {
        case .editor:
            return "Editor"
        }
    }

    var systemSymbolName: String {
        switch self {
        case .editor:
            return "textformat"
        }
    }
}

@MainActor
final class AttoPreferencesWindowController: NSWindowController {
    private let splitViewController = NSSplitViewController()
    private let sidebarViewController = AttoPreferencesSidebarViewController(pages: AttoPreferencesPage.allCases)
    private let contentHostViewController = AttoPreferencesContentHostViewController()

    private var cachedPages: [AttoPreferencesPage: NSViewController] = [:]

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Preferences"
        win.isReleasedWhenClosed = false
        super.init(window: win)

        setupWindowContents()
        showPage(.editor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindowContents() {
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = false

        let contentItem = NSSplitViewItem(viewController: contentHostViewController)
        contentItem.minimumThickness = 360

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)

        window?.contentViewController = splitViewController

        sidebarViewController.onSelectPage = { [weak self] page in
            self?.showPage(page)
        }
    }

    private func showPage(_ page: AttoPreferencesPage) {
        let vc: NSViewController = cachedPages[page] ?? {
            let created: NSViewController
            switch page {
            case .editor:
                created = AttoPreferencesEditorPageViewController()
            }
            cachedPages[page] = created
            return created
        }()

        contentHostViewController.setContentViewController(vc)
        sidebarViewController.selectPage(page)
    }
}

// MARK: - Sidebar

@MainActor
private final class AttoPreferencesSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let pages: [AttoPreferencesPage]

    var onSelectPage: ((AttoPreferencesPage) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))

    private var selectedPage: AttoPreferencesPage?

    init(pages: [AttoPreferencesPage]) {
        self.pages = pages
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.style = .sourceList
        tableView.rowSizeStyle = .medium
        tableView.focusRingType = .none
        tableView.backgroundColor = .clear

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if let first = pages.first {
            selectPage(first)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        pages.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard (0..<pages.count).contains(row) else { return nil }
        let page = pages[row]

        let id = NSUserInterfaceItemIdentifier("AttoPreferencesSidebarCell")
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            reused.textField?.stringValue = page.title
            reused.imageView?.image = NSImage(systemSymbolName: page.systemSymbolName, accessibilityDescription: page.title)
            return reused
        }

        let cell = NSTableCellView(frame: .zero)
        cell.identifier = id

        let iconView = NSImageView(frame: .zero)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.image = NSImage(systemSymbolName: page.systemSymbolName, accessibilityDescription: page.title)

        let titleField = NSTextField(labelWithString: page.title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail

        cell.addSubview(iconView)
        cell.addSubview(titleField)
        cell.imageView = iconView
        cell.textField = titleField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            titleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard (0..<pages.count).contains(row) else { return }
        let page = pages[row]
        selectedPage = page
        onSelectPage?(page)
    }

    func selectPage(_ page: AttoPreferencesPage) {
        selectedPage = page
        if let idx = pages.firstIndex(of: page) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        }
    }
}

// MARK: - Content host

@MainActor
private final class AttoPreferencesContentHostViewController: NSViewController {
    private var current: NSViewController?

    override func loadView() {
        view = NSView(frame: .zero)
    }

    func setContentViewController(_ vc: NSViewController) {
        if let current {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: view.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        current = vc
    }
}

// MARK: - Editor page

@MainActor
private final class AttoPreferencesEditorPageViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {
    private let prefs = AttoPreferences.shared

    private let scrollView = NSScrollView()
    private let stack = NSStackView()

    private let fontFacesTextView = NSTextView(frame: .zero)
    private let fontFacesHelpLabel = NSTextField(labelWithString: "One family per line. Top to bottom is the fallback order.")
    private let fontFacesResetButton = NSButton(title: "Use System Default", target: nil, action: nil)

    private let fontSizeField = NSTextField(string: "")
    private let fontSizeStepper = NSStepper(frame: .zero)

    private let ligaturesCheckbox = NSButton(checkboxWithTitle: "Enable ligatures", target: nil, action: nil)

    private var isUpdatingFromModel: Bool = false
    private var forceReloadFontFacesTextView: Bool = false

    private func isEditingFontFacesTextView() -> Bool {
        guard let win = view.window else { return false }
        return win.firstResponder === fontFacesTextView
    }

    override func loadView() {
        view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true

        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Section title
        let title = NSTextField(labelWithString: "Editor")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(title)

        // Font faces
        let fontFacesLabel = NSTextField(labelWithString: "Font faces")
        fontFacesLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(fontFacesLabel)

        fontFacesHelpLabel.textColor = .secondaryLabelColor
        fontFacesHelpLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        fontFacesHelpLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(fontFacesHelpLabel)

        fontFacesTextView.isRichText = false
        fontFacesTextView.isAutomaticQuoteSubstitutionEnabled = false
        fontFacesTextView.isAutomaticDataDetectionEnabled = false
        fontFacesTextView.isAutomaticLinkDetectionEnabled = false
        fontFacesTextView.isAutomaticTextReplacementEnabled = false
        fontFacesTextView.allowsUndo = true
        fontFacesTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        fontFacesTextView.delegate = self

        scrollView.documentView = fontFacesTextView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true

        let fontFacesContainer = NSView(frame: .zero)
        fontFacesContainer.translatesAutoresizingMaskIntoConstraints = false
        fontFacesContainer.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: fontFacesContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: fontFacesContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: fontFacesContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: fontFacesContainer.bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 120),
        ])
        stack.addArrangedSubview(fontFacesContainer)
        fontFacesContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

        fontFacesResetButton.target = self
        fontFacesResetButton.action = #selector(fontFacesResetClicked(_:))
        fontFacesResetButton.bezelStyle = .rounded
        stack.addArrangedSubview(fontFacesResetButton)

        // Font size
        let fontSizeLabel = NSTextField(labelWithString: "Font size")
        fontSizeLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(fontSizeLabel)

        fontSizeField.delegate = self
        fontSizeField.alignment = .right
        fontSizeField.font = NSFont.systemFont(ofSize: 13)
        fontSizeField.translatesAutoresizingMaskIntoConstraints = false
        fontSizeField.widthAnchor.constraint(equalToConstant: 64).isActive = true

        fontSizeStepper.minValue = 6
        fontSizeStepper.maxValue = 72
        fontSizeStepper.increment = 1
        fontSizeStepper.translatesAutoresizingMaskIntoConstraints = false
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged(_:))

        let fontSizeRow = NSStackView(views: [fontSizeField, fontSizeStepper])
        fontSizeRow.orientation = .horizontal
        fontSizeRow.spacing = 8
        fontSizeRow.alignment = .centerY
        stack.addArrangedSubview(fontSizeRow)

        // Ligatures
        ligaturesCheckbox.target = self
        ligaturesCheckbox.action = #selector(ligaturesToggled(_:))
        stack.addArrangedSubview(ligaturesCheckbox)

        // Layout
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
        ])

        reloadFromModel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .attoPreferencesDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func reloadFromModel() {
        isUpdatingFromModel = true
        defer { isUpdatingFromModel = false }

        // Avoid clobbering the user's selection/caret while they type: reloading `string`
        // resets selection (often to EOF) and makes `Enter` look broken because the model
        // serialization does not preserve trailing blank lines.
        if isEditingFontFacesTextView() == false || forceReloadFontFacesTextView {
            fontFacesTextView.string = prefs.fontFacesMultilineTextForUI()
        }

        let size = prefs.effectiveFontSizePoints
        fontSizeField.stringValue = String(Int(size.rounded()))
        fontSizeStepper.doubleValue = size

        ligaturesCheckbox.state = prefs.effectiveLigaturesEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadFromModel()
    }

    @objc private func fontFacesResetClicked(_ sender: Any?) {
        forceReloadFontFacesTextView = true
        defer { forceReloadFontFacesTextView = false }
        prefs.setFontFaces([])
    }

    @objc private func fontSizeStepperChanged(_ sender: Any?) {
        let v = fontSizeStepper.doubleValue
        prefs.setFontSizePoints(v)
    }

    @objc private func ligaturesToggled(_ sender: Any?) {
        prefs.setLigaturesEnabled(ligaturesCheckbox.state == .on)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard isUpdatingFromModel == false else { return }
        guard notification.object as? NSTextView === fontFacesTextView else { return }
        let faces = AttoPreferences.parseMultilineFontFaces(fontFacesTextView.string)
        prefs.setFontFaces(faces)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        guard field === fontSizeField else { return }

        let v = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? prefs.effectiveFontSizePoints
        prefs.setFontSizePoints(v)
    }
}
