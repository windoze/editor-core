import AppKit
import EditorCoreUI
import EditorCoreUIFFI
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

    private let pageScrollView = NSScrollView()
    private let stack = NSStackView()

    private let fontFacesScrollView = NSScrollView()
    private let fontFacesTextView = NSTextView(frame: .zero)
    private let fontFacesHelpLabel = NSTextField(labelWithString: "One family per line. Top to bottom is the fallback order.")
    private let fontFacesResetButton = NSButton(title: "Use System Default", target: nil, action: nil)

    private let themePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themeHelpLabel = NSTextField(labelWithString: "Builtin themes ship with the app. Custom themes are loaded from Application Support.")
    private let themeResetButton = NSButton(title: "Use Default Theme", target: nil, action: nil)
    private let themeReloadButton = NSButton(title: "Reload Themes", target: nil, action: nil)
    private let themeOpenFolderButton = NSButton(title: "Open Themes Folder", target: nil, action: nil)

    private var cachedThemeEntries: [EditorCoreThemeRegistry.Entry] = []

    private let fontSizeField = NSTextField(string: "")
    private let fontSizeStepper = NSStepper(frame: .zero)

    private let wrapModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let wrapIndentPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let wrapIndentFixedField = NSTextField(string: "")
    private let wrapIndentFixedStepper = NSStepper(frame: .zero)

    private let ligaturesCheckbox = NSButton(checkboxWithTitle: "Enable ligatures", target: nil, action: nil)
    private let autoPairsCheckbox = NSButton(checkboxWithTitle: "Enable auto pairs", target: nil, action: nil)
    private let findCaseSensitiveCheckbox = NSButton(checkboxWithTitle: "Match case by default", target: nil, action: nil)
    private let findWholeWordCheckbox = NSButton(checkboxWithTitle: "Whole word by default", target: nil, action: nil)
    private let findRegexCheckbox = NSButton(checkboxWithTitle: "Regex by default", target: nil, action: nil)
    private let findInFilesScopePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let workspaceSearchIncludeGlobsScrollView = NSScrollView()
    private let workspaceSearchIncludeGlobsTextView = NSTextView(frame: .zero)
    private let workspaceSearchIncludeGlobsHelpLabel = NSTextField(labelWithString: "One include glob per line. Empty includes all workspace files.")
    private let workspaceSearchExcludeGlobsScrollView = NSScrollView()
    private let workspaceSearchExcludeGlobsTextView = NSTextView(frame: .zero)
    private let workspaceSearchExcludeGlobsHelpLabel = NSTextField(labelWithString: "One exclude glob per line. Excludes win over includes.")
    private let lspAutoRestartCheckbox = NSButton(checkboxWithTitle: "Auto-restart failed LSP servers", target: nil, action: nil)
    private let lspAutoRestartMaxAttemptsField = NSTextField(string: "")
    private let lspAutoRestartMaxAttemptsStepper = NSStepper(frame: .zero)
    private let lspAutoRestartBaseDelayField = NSTextField(string: "")
    private let lspAutoRestartBaseDelayStepper = NSStepper(frame: .zero)

    private var isUpdatingFromModel: Bool = false
    private var forceReloadFontFacesTextView: Bool = false

    private func isEditingTextView(_ textView: NSTextView) -> Bool {
        guard let win = view.window else { return false }
        return win.firstResponder === textView
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

        // Theme
        let themeLabel = NSTextField(labelWithString: "Theme")
        themeLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(themeLabel)

        themeHelpLabel.textColor = .secondaryLabelColor
        themeHelpLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        themeHelpLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(themeHelpLabel)

        themePopUp.translatesAutoresizingMaskIntoConstraints = false
        themePopUp.target = self
        themePopUp.action = #selector(themePopUpChanged(_:))
        themePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        stack.addArrangedSubview(themePopUp)

        themeResetButton.target = self
        themeResetButton.action = #selector(themeResetClicked(_:))
        themeResetButton.bezelStyle = .rounded

        themeReloadButton.target = self
        themeReloadButton.action = #selector(themeReloadClicked(_:))
        themeReloadButton.bezelStyle = .rounded

        themeOpenFolderButton.target = self
        themeOpenFolderButton.action = #selector(themeOpenFolderClicked(_:))
        themeOpenFolderButton.bezelStyle = .rounded

        let themeButtons = NSStackView(views: [themeResetButton, themeReloadButton, themeOpenFolderButton])
        themeButtons.orientation = .horizontal
        themeButtons.spacing = 10
        themeButtons.alignment = .centerY
        stack.addArrangedSubview(themeButtons)

        // Font faces
        let fontFacesLabel = NSTextField(labelWithString: "Font faces")
        fontFacesLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(fontFacesLabel)

        fontFacesHelpLabel.textColor = .secondaryLabelColor
        fontFacesHelpLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        fontFacesHelpLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(fontFacesHelpLabel)

        configurePlainTextView(fontFacesTextView)
        configureTextScrollView(fontFacesScrollView, textView: fontFacesTextView)

        let fontFacesContainer = makeTextViewContainer(scrollView: fontFacesScrollView, height: 120)
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

        // Wrap mode
        let wrapModeLabel = NSTextField(labelWithString: "Word wrap")
        wrapModeLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(wrapModeLabel)

        wrapModePopUp.addItem(withTitle: "Off")
        wrapModePopUp.item(at: 0)?.representedObject = EcuWrapMode.none.rawValue
        wrapModePopUp.addItem(withTitle: "By Character")
        wrapModePopUp.item(at: 1)?.representedObject = EcuWrapMode.char.rawValue
        wrapModePopUp.addItem(withTitle: "By Word")
        wrapModePopUp.item(at: 2)?.representedObject = EcuWrapMode.word.rawValue
        wrapModePopUp.target = self
        wrapModePopUp.action = #selector(wrapModeChanged(_:))
        wrapModePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        stack.addArrangedSubview(wrapModePopUp)

        // Wrap indent
        let wrapIndentLabel = NSTextField(labelWithString: "Wrap indent")
        wrapIndentLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(wrapIndentLabel)

        wrapIndentPopUp.addItem(withTitle: "None")
        wrapIndentPopUp.item(at: 0)?.representedObject = "none"
        wrapIndentPopUp.addItem(withTitle: "Same as Line Indent")
        wrapIndentPopUp.item(at: 1)?.representedObject = "same_as_line_indent"
        wrapIndentPopUp.addItem(withTitle: "Fixed Cells")
        wrapIndentPopUp.item(at: 2)?.representedObject = "fixed_cells"
        wrapIndentPopUp.target = self
        wrapIndentPopUp.action = #selector(wrapIndentModeChanged(_:))
        wrapIndentPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        wrapIndentFixedField.delegate = self
        wrapIndentFixedField.alignment = .right
        wrapIndentFixedField.font = NSFont.systemFont(ofSize: 13)
        wrapIndentFixedField.translatesAutoresizingMaskIntoConstraints = false
        wrapIndentFixedField.widthAnchor.constraint(equalToConstant: 64).isActive = true

        wrapIndentFixedStepper.minValue = 0
        wrapIndentFixedStepper.maxValue = 80
        wrapIndentFixedStepper.increment = 1
        wrapIndentFixedStepper.translatesAutoresizingMaskIntoConstraints = false
        wrapIndentFixedStepper.target = self
        wrapIndentFixedStepper.action = #selector(wrapIndentFixedStepperChanged(_:))

        let wrapIndentRow = NSStackView(views: [wrapIndentPopUp, wrapIndentFixedField, wrapIndentFixedStepper])
        wrapIndentRow.orientation = .horizontal
        wrapIndentRow.spacing = 8
        wrapIndentRow.alignment = .centerY
        stack.addArrangedSubview(wrapIndentRow)

        // Ligatures
        ligaturesCheckbox.target = self
        ligaturesCheckbox.action = #selector(ligaturesToggled(_:))
        stack.addArrangedSubview(ligaturesCheckbox)

        autoPairsCheckbox.target = self
        autoPairsCheckbox.action = #selector(autoPairsToggled(_:))
        stack.addArrangedSubview(autoPairsCheckbox)

        // Search
        let searchLabel = NSTextField(labelWithString: "Search")
        searchLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(searchLabel)

        findCaseSensitiveCheckbox.target = self
        findCaseSensitiveCheckbox.action = #selector(findCaseSensitiveToggled(_:))
        stack.addArrangedSubview(findCaseSensitiveCheckbox)

        findWholeWordCheckbox.target = self
        findWholeWordCheckbox.action = #selector(findWholeWordToggled(_:))
        stack.addArrangedSubview(findWholeWordCheckbox)

        findRegexCheckbox.target = self
        findRegexCheckbox.action = #selector(findRegexToggled(_:))
        stack.addArrangedSubview(findRegexCheckbox)

        let findInFilesScopeLabel = NSTextField(labelWithString: "Find in Files default scope")
        findInFilesScopeLabel.font = NSFont.systemFont(ofSize: 13)
        findInFilesScopePopUp.addItem(withTitle: "Opened Files")
        findInFilesScopePopUp.item(at: 0)?.representedObject = "opened_files"
        findInFilesScopePopUp.addItem(withTitle: "Workspace Folder")
        findInFilesScopePopUp.item(at: 1)?.representedObject = "workspace"
        findInFilesScopePopUp.target = self
        findInFilesScopePopUp.action = #selector(findInFilesScopeChanged(_:))
        findInFilesScopePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        let findInFilesScopeRow = NSStackView(views: [findInFilesScopeLabel, findInFilesScopePopUp])
        findInFilesScopeRow.orientation = .horizontal
        findInFilesScopeRow.spacing = 8
        findInFilesScopeRow.alignment = .centerY
        stack.addArrangedSubview(findInFilesScopeRow)

        let includeGlobsLabel = NSTextField(labelWithString: "Workspace include globs")
        includeGlobsLabel.font = NSFont.systemFont(ofSize: 13)
        stack.addArrangedSubview(includeGlobsLabel)

        workspaceSearchIncludeGlobsHelpLabel.textColor = .secondaryLabelColor
        workspaceSearchIncludeGlobsHelpLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        workspaceSearchIncludeGlobsHelpLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(workspaceSearchIncludeGlobsHelpLabel)

        configurePlainTextView(workspaceSearchIncludeGlobsTextView)
        configureTextScrollView(workspaceSearchIncludeGlobsScrollView, textView: workspaceSearchIncludeGlobsTextView)
        let includeGlobsContainer = makeTextViewContainer(scrollView: workspaceSearchIncludeGlobsScrollView, height: 74)
        stack.addArrangedSubview(includeGlobsContainer)
        includeGlobsContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

        let excludeGlobsLabel = NSTextField(labelWithString: "Workspace exclude globs")
        excludeGlobsLabel.font = NSFont.systemFont(ofSize: 13)
        stack.addArrangedSubview(excludeGlobsLabel)

        workspaceSearchExcludeGlobsHelpLabel.textColor = .secondaryLabelColor
        workspaceSearchExcludeGlobsHelpLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        workspaceSearchExcludeGlobsHelpLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(workspaceSearchExcludeGlobsHelpLabel)

        configurePlainTextView(workspaceSearchExcludeGlobsTextView)
        configureTextScrollView(workspaceSearchExcludeGlobsScrollView, textView: workspaceSearchExcludeGlobsTextView)
        let excludeGlobsContainer = makeTextViewContainer(scrollView: workspaceSearchExcludeGlobsScrollView, height: 74)
        stack.addArrangedSubview(excludeGlobsContainer)
        excludeGlobsContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

        // LSP recovery
        let lspRecoveryLabel = NSTextField(labelWithString: "LSP recovery")
        lspRecoveryLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(lspRecoveryLabel)

        lspAutoRestartCheckbox.target = self
        lspAutoRestartCheckbox.action = #selector(lspAutoRestartToggled(_:))
        stack.addArrangedSubview(lspAutoRestartCheckbox)

        lspAutoRestartMaxAttemptsField.delegate = self
        lspAutoRestartMaxAttemptsField.alignment = .right
        lspAutoRestartMaxAttemptsField.font = NSFont.systemFont(ofSize: 13)
        lspAutoRestartMaxAttemptsField.translatesAutoresizingMaskIntoConstraints = false
        lspAutoRestartMaxAttemptsField.widthAnchor.constraint(equalToConstant: 64).isActive = true

        lspAutoRestartMaxAttemptsStepper.minValue = 0
        lspAutoRestartMaxAttemptsStepper.maxValue = 10
        lspAutoRestartMaxAttemptsStepper.increment = 1
        lspAutoRestartMaxAttemptsStepper.translatesAutoresizingMaskIntoConstraints = false
        lspAutoRestartMaxAttemptsStepper.target = self
        lspAutoRestartMaxAttemptsStepper.action = #selector(lspAutoRestartMaxAttemptsStepperChanged(_:))

        let lspMaxAttemptsLabel = NSTextField(labelWithString: "Max attempts")
        lspMaxAttemptsLabel.font = NSFont.systemFont(ofSize: 13)
        let lspMaxAttemptsRow = NSStackView(views: [
            lspMaxAttemptsLabel,
            lspAutoRestartMaxAttemptsField,
            lspAutoRestartMaxAttemptsStepper,
        ])
        lspMaxAttemptsRow.orientation = .horizontal
        lspMaxAttemptsRow.spacing = 8
        lspMaxAttemptsRow.alignment = .centerY
        stack.addArrangedSubview(lspMaxAttemptsRow)

        lspAutoRestartBaseDelayField.delegate = self
        lspAutoRestartBaseDelayField.alignment = .right
        lspAutoRestartBaseDelayField.font = NSFont.systemFont(ofSize: 13)
        lspAutoRestartBaseDelayField.translatesAutoresizingMaskIntoConstraints = false
        lspAutoRestartBaseDelayField.widthAnchor.constraint(equalToConstant: 64).isActive = true

        lspAutoRestartBaseDelayStepper.minValue = 0
        lspAutoRestartBaseDelayStepper.maxValue = 3_600
        lspAutoRestartBaseDelayStepper.increment = 1
        lspAutoRestartBaseDelayStepper.translatesAutoresizingMaskIntoConstraints = false
        lspAutoRestartBaseDelayStepper.target = self
        lspAutoRestartBaseDelayStepper.action = #selector(lspAutoRestartBaseDelayStepperChanged(_:))

        let lspBaseDelayLabel = NSTextField(labelWithString: "Base delay")
        lspBaseDelayLabel.font = NSFont.systemFont(ofSize: 13)
        let lspBaseDelaySuffix = NSTextField(labelWithString: "seconds")
        lspBaseDelaySuffix.font = NSFont.systemFont(ofSize: 13)
        let lspBaseDelayRow = NSStackView(views: [
            lspBaseDelayLabel,
            lspAutoRestartBaseDelayField,
            lspAutoRestartBaseDelayStepper,
            lspBaseDelaySuffix,
        ])
        lspBaseDelayRow.orientation = .horizontal
        lspBaseDelayRow.spacing = 8
        lspBaseDelayRow.alignment = .centerY
        stack.addArrangedSubview(lspBaseDelayRow)

        // Layout
        let contentView = NSView(frame: .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        pageScrollView.documentView = contentView
        pageScrollView.hasVerticalScroller = true
        pageScrollView.drawsBackground = false
        pageScrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        view.addSubview(pageScrollView)
        NSLayoutConstraint.activate([
            pageScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            pageScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.widthAnchor.constraint(equalTo: pageScrollView.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])

        reloadThemeMenu()
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

    private func configurePlainTextView(_ textView: NSTextView) {
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
    }

    private func configureTextScrollView(_ scrollView: NSScrollView, textView: NSTextView) {
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true
    }

    private func makeTextViewContainer(scrollView: NSScrollView, height: CGFloat) -> NSView {
        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: height),
        ])
        return container
    }

    private func reloadFromModel() {
        isUpdatingFromModel = true
        defer { isUpdatingFromModel = false }

        reloadThemeSelectionFromModel()

        // Avoid clobbering the user's selection/caret while they type: reloading `string`
        // resets selection (often to EOF) and makes `Enter` look broken because the model
        // serialization does not preserve trailing blank lines.
        if isEditingTextView(fontFacesTextView) == false || forceReloadFontFacesTextView {
            fontFacesTextView.string = prefs.fontFacesMultilineTextForUI()
        }
        if isEditingTextView(workspaceSearchIncludeGlobsTextView) == false {
            workspaceSearchIncludeGlobsTextView.string = prefs.workspaceSearchIncludeGlobsTextForUI()
        }
        if isEditingTextView(workspaceSearchExcludeGlobsTextView) == false {
            workspaceSearchExcludeGlobsTextView.string = prefs.workspaceSearchExcludeGlobsTextForUI()
        }

        let size = prefs.effectiveFontSizePoints
        fontSizeField.stringValue = String(Int(size.rounded()))
        fontSizeStepper.doubleValue = size

        ligaturesCheckbox.state = prefs.effectiveLigaturesEnabled ? .on : .off
        autoPairsCheckbox.state = prefs.effectiveAutoPairsEnabled ? .on : .off
        findCaseSensitiveCheckbox.state = prefs.effectiveFindCaseSensitive ? .on : .off
        findWholeWordCheckbox.state = prefs.effectiveFindWholeWord ? .on : .off
        findRegexCheckbox.state = prefs.effectiveFindRegex ? .on : .off
        selectFindInFilesScope(prefs.effectiveFindInFilesDefaultScope)
        let lspAutoRestartEnabled = prefs.effectiveLspAutoRestartEnabled
        lspAutoRestartCheckbox.state = lspAutoRestartEnabled ? .on : .off
        let lspMaxAttempts = prefs.effectiveLspAutoRestartMaxAttempts
        lspAutoRestartMaxAttemptsField.stringValue = String(lspMaxAttempts)
        lspAutoRestartMaxAttemptsStepper.integerValue = lspMaxAttempts
        let lspBaseDelay = prefs.effectiveLspAutoRestartBaseDelaySeconds
        lspAutoRestartBaseDelayField.stringValue = Self.formatLspBaseDelaySeconds(lspBaseDelay)
        lspAutoRestartBaseDelayStepper.doubleValue = lspBaseDelay
        setLspAutoRestartControlsEnabled(lspAutoRestartEnabled)
        selectWrapMode(prefs.effectiveWrapMode)
        selectWrapIndent(prefs.effectiveWrapIndent)
    }

    // MARK: - Actions

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadFromModel()
    }

    @objc private func themePopUpChanged(_ sender: Any?) {
        guard isUpdatingFromModel == false else { return }
        let idx = themePopUp.indexOfSelectedItem
        guard idx >= 0 else { return }
        let name = themePopUp.item(at: idx)?.representedObject as? String
        prefs.setThemeName(name)
    }

    @objc private func themeResetClicked(_ sender: Any?) {
        prefs.setThemeName(nil)
    }

    @objc private func themeReloadClicked(_ sender: Any?) {
        reloadThemeMenu()
    }

    @objc private func themeOpenFolderClicked(_ sender: Any?) {
        let fm = FileManager.default
        let dir = AttoThemeManager.customThemesDirectoryURL(fileManager: fm)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("AttoEditor: failed to create themes directory %@: %@", dir.path, String(describing: error))
        }
        NSWorkspace.shared.open(dir)
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

    @objc private func wrapModeChanged(_ sender: Any?) {
        guard isUpdatingFromModel == false else { return }
        let idx = wrapModePopUp.indexOfSelectedItem
        guard idx >= 0,
              let raw = wrapModePopUp.item(at: idx)?.representedObject as? String,
              let mode = EcuWrapMode(rawValue: raw)
        else { return }
        prefs.setWrapMode(mode)
    }

    @objc private func wrapIndentModeChanged(_ sender: Any?) {
        guard isUpdatingFromModel == false else { return }
        let idx = wrapIndentPopUp.indexOfSelectedItem
        guard idx >= 0,
              let raw = wrapIndentPopUp.item(at: idx)?.representedObject as? String
        else { return }

        switch raw {
        case "none":
            prefs.setWrapIndent(EcuWrapIndent.none)
        case "same_as_line_indent":
            prefs.setWrapIndent(.sameAsLineIndent)
        case "fixed_cells":
            prefs.setWrapIndent(.fixedCells(currentWrapIndentFixedCells()))
        default:
            return
        }
    }

    @objc private func wrapIndentFixedStepperChanged(_ sender: Any?) {
        guard isUpdatingFromModel == false else { return }
        let cells = UInt32(max(0, min(80, wrapIndentFixedStepper.integerValue)))
        prefs.setWrapIndent(.fixedCells(cells))
    }

    @objc private func autoPairsToggled(_ sender: Any?) {
        prefs.setAutoPairsEnabled(autoPairsCheckbox.state == .on)
    }

    @objc private func findCaseSensitiveToggled(_ sender: Any?) {
        prefs.setFindCaseSensitive(findCaseSensitiveCheckbox.state == .on)
    }

    @objc private func findWholeWordToggled(_ sender: Any?) {
        prefs.setFindWholeWord(findWholeWordCheckbox.state == .on)
    }

    @objc private func findRegexToggled(_ sender: Any?) {
        prefs.setFindRegex(findRegexCheckbox.state == .on)
    }

    @objc private func findInFilesScopeChanged(_ sender: Any?) {
        guard isUpdatingFromModel == false else { return }
        let idx = findInFilesScopePopUp.indexOfSelectedItem
        guard idx >= 0,
              let raw = findInFilesScopePopUp.item(at: idx)?.representedObject as? String
        else { return }
        prefs.setFindInFilesDefaultScope(raw)
    }

    @objc private func lspAutoRestartToggled(_ sender: Any?) {
        let enabled = lspAutoRestartCheckbox.state == .on
        prefs.setLspAutoRestartEnabled(enabled)
        setLspAutoRestartControlsEnabled(enabled)
    }

    @objc private func lspAutoRestartMaxAttemptsStepperChanged(_ sender: Any?) {
        guard isUpdatingFromModel == false else { return }
        prefs.setLspAutoRestartMaxAttempts(lspAutoRestartMaxAttemptsStepper.integerValue)
    }

    @objc private func lspAutoRestartBaseDelayStepperChanged(_ sender: Any?) {
        guard isUpdatingFromModel == false else { return }
        prefs.setLspAutoRestartBaseDelaySeconds(lspAutoRestartBaseDelayStepper.doubleValue)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard isUpdatingFromModel == false else { return }
        guard let textView = notification.object as? NSTextView else { return }

        if textView === fontFacesTextView {
            let faces = AttoPreferences.parseMultilineFontFaces(fontFacesTextView.string)
            prefs.setFontFaces(faces)
            return
        }

        if textView === workspaceSearchIncludeGlobsTextView {
            let patterns = AttoPreferences.parseWorkspaceSearchGlobsText(workspaceSearchIncludeGlobsTextView.string)
            prefs.setWorkspaceSearchIncludeGlobs(patterns)
            return
        }

        if textView === workspaceSearchExcludeGlobsTextView {
            let patterns = AttoPreferences.parseWorkspaceSearchGlobsText(workspaceSearchExcludeGlobsTextView.string)
            prefs.setWorkspaceSearchExcludeGlobs(patterns)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === fontSizeField {
            let v = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? prefs.effectiveFontSizePoints
            prefs.setFontSizePoints(v)
            return
        }

        if field === wrapIndentFixedField {
            prefs.setWrapIndent(.fixedCells(currentWrapIndentFixedCells()))
            return
        }

        if field === lspAutoRestartMaxAttemptsField {
            prefs.setLspAutoRestartMaxAttempts(currentLspAutoRestartMaxAttempts())
            return
        }

        if field === lspAutoRestartBaseDelayField {
            prefs.setLspAutoRestartBaseDelaySeconds(currentLspAutoRestartBaseDelaySeconds())
        }
    }

    // MARK: - Theme menu

    private func reloadThemeMenu() {
        let registry = AttoThemeManager.loadRegistry()
        cachedThemeEntries = registry.allEntriesSortedByName()

        themePopUp.removeAllItems()

        if cachedThemeEntries.isEmpty {
            themePopUp.addItem(withTitle: "No themes found")
            themePopUp.isEnabled = false
        } else {
            themePopUp.isEnabled = true
            for entry in cachedThemeEntries {
                let sourceSuffix: String = {
                    switch entry.source {
                    case .builtin: return " (Builtin)"
                    case .custom: return " (Custom)"
                    }
                }()
                themePopUp.addItem(withTitle: entry.theme.name + sourceSuffix)
                themePopUp.item(at: themePopUp.numberOfItems - 1)?.representedObject = entry.theme.name
            }
        }

        reloadThemeSelectionFromModel()
    }

    private func reloadThemeSelectionFromModel() {
        let effectiveName = prefs.effectiveThemeName
        guard themePopUp.isEnabled else { return }

        if let idx = cachedThemeEntries.firstIndex(where: { entry in
            EditorCoreThemeRegistry.normalizeThemeNameKey(entry.theme.name)
                == EditorCoreThemeRegistry.normalizeThemeNameKey(effectiveName)
        }) {
            themePopUp.selectItem(at: idx)
            return
        }

        // Theme not found (e.g. env var points to a missing theme). Add a temporary “missing” item.
        if let existing = themePopUp.itemArray.first(where: { ($0.representedObject as? String) == effectiveName }) {
            themePopUp.select(existing)
            return
        }

        themePopUp.addItem(withTitle: "\(effectiveName) (Missing)")
        themePopUp.item(at: themePopUp.numberOfItems - 1)?.representedObject = effectiveName
        themePopUp.selectItem(at: themePopUp.numberOfItems - 1)
    }

    private func selectWrapMode(_ mode: EcuWrapMode) {
        for idx in 0..<wrapModePopUp.numberOfItems {
            if wrapModePopUp.item(at: idx)?.representedObject as? String == mode.rawValue {
                wrapModePopUp.selectItem(at: idx)
                return
            }
        }
        wrapModePopUp.selectItem(at: 1)
    }

    private func selectWrapIndent(_ indent: EcuWrapIndent) {
        let fixedCells: UInt32
        switch indent {
        case .none:
            wrapIndentPopUp.selectItem(at: 0)
            fixedCells = 2
            setWrapIndentFixedControlsEnabled(false)
        case .sameAsLineIndent:
            wrapIndentPopUp.selectItem(at: 1)
            fixedCells = 2
            setWrapIndentFixedControlsEnabled(false)
        case let .fixedCells(cells):
            wrapIndentPopUp.selectItem(at: 2)
            fixedCells = cells
            setWrapIndentFixedControlsEnabled(true)
        }

        let clamped = UInt32(min(fixedCells, 80))
        wrapIndentFixedField.stringValue = String(clamped)
        wrapIndentFixedStepper.integerValue = Int(clamped)
    }

    private func currentWrapIndentFixedCells() -> UInt32 {
        let raw = wrapIndentFixedField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Int(raw) ?? wrapIndentFixedStepper.integerValue
        return UInt32(max(0, min(80, parsed)))
    }

    private func selectFindInFilesScope(_ rawScope: String) {
        let normalized = AttoPreferences.normalizeFindInFilesDefaultScope(rawScope)
            ?? AttoWorkspacePreferenceSnapshot.defaultFindInFilesScope
        for idx in 0..<findInFilesScopePopUp.numberOfItems {
            if findInFilesScopePopUp.item(at: idx)?.representedObject as? String == normalized {
                findInFilesScopePopUp.selectItem(at: idx)
                return
            }
        }
        findInFilesScopePopUp.selectItem(at: 0)
    }

    private func setWrapIndentFixedControlsEnabled(_ enabled: Bool) {
        wrapIndentFixedField.isEnabled = enabled
        wrapIndentFixedStepper.isEnabled = enabled
    }

    private func currentLspAutoRestartMaxAttempts() -> Int {
        let raw = lspAutoRestartMaxAttemptsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Int(raw) ?? lspAutoRestartMaxAttemptsStepper.integerValue
        return max(0, min(10, parsed))
    }

    private func currentLspAutoRestartBaseDelaySeconds() -> Double {
        let raw = lspAutoRestartBaseDelayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Double(raw) ?? lspAutoRestartBaseDelayStepper.doubleValue
        guard parsed.isFinite else { return 5.0 }
        return min(max(parsed, 0.0), 3_600.0)
    }

    private func setLspAutoRestartControlsEnabled(_ enabled: Bool) {
        lspAutoRestartMaxAttemptsField.isEnabled = enabled
        lspAutoRestartMaxAttemptsStepper.isEnabled = enabled
        lspAutoRestartBaseDelayField.isEnabled = enabled
        lspAutoRestartBaseDelayStepper.isEnabled = enabled
    }

    private static func formatLspBaseDelaySeconds(_ seconds: Double) -> String {
        if seconds.rounded() == seconds {
            return String(Int(seconds))
        }
        return String(seconds)
    }
}
