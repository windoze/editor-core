import AppKit
import Foundation

@MainActor
final class AttoSidebarViewController: NSViewController {
    enum Tab: Int {
        case fileExplorer = 0
        case openedFiles = 1
        case findInFiles = 2
    }

    let fileExplorerController: AttoFileExplorerViewController
    let openedFilesController: AttoOpenedFilesViewController
    let findInFilesController: AttoFindInFilesViewController

    private let tabBarView = NSView(frame: .zero)
    private let tabControl = NSSegmentedControl(labels: ["Explorer", "Opened", "Search"], trackingMode: .selectOne, target: nil, action: nil)
    private let contentHostView = NSView(frame: .zero)
    private let bottomBorderLayer = CALayer()

    private var activeTab: Tab?

    init(
        fileExplorerController: AttoFileExplorerViewController,
        openedFilesController: AttoOpenedFilesViewController,
        findInFilesController: AttoFindInFilesViewController
    ) {
        self.fileExplorerController = fileExplorerController
        self.openedFilesController = openedFilesController
        self.findInFilesController = findInFilesController
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

        tabBarView.wantsLayer = true
        tabBarView.layer?.backgroundColor = NSColor(attoHex: 0x2B2B2B).cgColor
        bottomBorderLayer.backgroundColor = NSColor(attoHex: 0x1E1E1E).cgColor
        tabBarView.layer?.addSublayer(bottomBorderLayer)
        tabBarView.translatesAutoresizingMaskIntoConstraints = false

        tabControl.controlSize = .small
        tabControl.selectedSegment = Tab.fileExplorer.rawValue
        tabControl.target = self
        tabControl.action = #selector(tabChanged(_:))
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.setToolTip("File Explorer", forSegment: Tab.fileExplorer.rawValue)
        tabControl.setToolTip("Opened Files", forSegment: Tab.openedFiles.rawValue)
        tabControl.setToolTip("Find in Files", forSegment: Tab.findInFiles.rawValue)

        contentHostView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBarView)
        tabBarView.addSubview(tabControl)
        view.addSubview(contentHostView)

        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 32),

            tabControl.leadingAnchor.constraint(equalTo: tabBarView.leadingAnchor, constant: 8),
            tabControl.trailingAnchor.constraint(lessThanOrEqualTo: tabBarView.trailingAnchor, constant: -8),
            tabControl.centerYAnchor.constraint(equalTo: tabBarView.centerYAnchor),

            contentHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHostView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Default tab.
        showTab(.fileExplorer)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        bottomBorderLayer.frame = CGRect(x: 0, y: 0, width: tabBarView.bounds.width, height: 1)
    }

    func selectTab(_ tab: Tab) {
        tabControl.selectedSegment = tab.rawValue
        showTab(tab)
    }

    private func showTab(_ tab: Tab) {
        if activeTab == tab, children.isEmpty == false { return }
        activeTab = tab

        let vc: NSViewController = switch tab {
        case .fileExplorer: fileExplorerController
        case .openedFiles: openedFilesController
        case .findInFiles: findInFilesController
        }

        children.forEach { child in
            child.view.removeFromSuperview()
            child.removeFromParent()
        }

        addChild(vc)
        let v = vc.view
        v.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            v.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            v.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),
        ])

        if tab == .findInFiles {
            findInFilesController.focusSearchField()
        }
    }

    @objc private func tabChanged(_ sender: Any?) {
        let tab = Tab(rawValue: tabControl.selectedSegment) ?? .fileExplorer
        showTab(tab)
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
