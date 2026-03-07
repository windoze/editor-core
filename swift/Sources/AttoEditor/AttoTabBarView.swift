import AppKit
import Foundation

@MainActor
final class AttoTabBarView: NSView {
    struct Tab: Equatable {
        let id: UUID
        let title: String
        let toolTip: String?
        let isPreview: Bool
    }

    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(attoHex: 0x2D2D2D).cgColor

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)

        scrollView.documentView = stackView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTabs(tabs: [Tab], selectedID: UUID?) {
        stackView.arrangedSubviews.forEach { v in
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        if tabs.isEmpty {
            let label = NSTextField(labelWithString: "No file open")
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = NSColor(attoHex: 0x8A8A8A)
            stackView.addArrangedSubview(label)
            return
        }

        for tab in tabs {
            let chip = AttoTabChipView(
                id: tab.id,
                title: tab.title,
                toolTip: tab.toolTip,
                isPreview: tab.isPreview,
                selected: tab.id == selectedID,
                onSelect: { [weak self] in self?.onSelectTab?(tab.id) },
                onClose: { [weak self] in self?.onCloseTab?(tab.id) }
            )
            stackView.addArrangedSubview(chip)
        }
    }
}

@MainActor
private final class AttoTabChipView: NSView {
    private let id: UUID
    private let onSelect: () -> Void
    private let onClose: () -> Void

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "×", target: nil, action: nil)

    init(
        id: UUID,
        title: String,
        toolTip: String?,
        isPreview: Bool,
        selected: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.id = id
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = (selected ? NSColor(attoHex: 0x1E1E1E) : NSColor(attoHex: 0x2D2D2D)).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(attoHex: selected ? 0x3C3C3C : 0x2D2D2D).cgColor

        self.toolTip = toolTip

        titleLabel.stringValue = title
        let baseFont = NSFont.systemFont(ofSize: 12)
        titleLabel.font = isPreview
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            : baseFont
        titleLabel.textColor = selected ? NSColor(attoHex: 0xFFFFFF) : NSColor(attoHex: 0xCCCCCC)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        closeButton.contentTintColor = NSColor(attoHex: 0xCCCCCC)
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect()
    }

    @objc private func closeClicked(_ sender: Any?) {
        onClose()
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
