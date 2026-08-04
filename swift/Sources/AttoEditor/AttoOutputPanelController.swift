import AppKit

@MainActor
final class AttoOutputPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let scrollView = NSScrollView(frame: .zero)
    private let textView = NSTextView(frame: .zero)
    private let panelTitle: String

    init(title: String) {
        self.panelTitle = title
        super.init()
    }

    var text: String {
        textView.string
    }

    func setText(_ text: String) {
        ensurePanel()
        textView.string = text
        scrollToBottom()
    }

    func appendText(_ text: String) {
        ensurePanel()
        textView.textStorage?.append(NSAttributedString(string: text))
        scrollToBottom()
    }

    func show(relativeTo window: NSWindow) {
        ensurePanel()
        guard let panel else { return }
        position(panel: panel, relativeTo: window)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    private func ensurePanel() {
        if panel == nil {
            panel = buildPanel()
        }
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 280),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = panelTitle
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.delegate = self

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView(frame: .zero)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        return panel
    }

    private func position(panel: NSPanel, relativeTo window: NSWindow) {
        let parent = window.frame
        let size = panel.frame.size
        let x = parent.midX - size.width / 2
        let y = max(parent.minY + 48, parent.minY + parent.height * 0.12)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scrollToBottom() {
        guard let textStorage = textView.textStorage else { return }
        textView.scrollRangeToVisible(NSRange(location: textStorage.length, length: 0))
    }
}
