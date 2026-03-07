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
    private let documentContainerView = NSView()
    private let stackView = NSStackView()
    private let trailingSpacerView = NSView()

    private let bottomBorderLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Sublime-ish: darker chrome than the editor background.
        layer?.backgroundColor = NSColor(attoHex: 0x2B2B2B).cgColor
        bottomBorderLayer.backgroundColor = NSColor(attoHex: 0x1E1E1E).cgColor
        layer?.addSublayer(bottomBorderLayer)

        documentContainerView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 0
        // Keep vertical padding in sync with the tab bar height (30 = 26 + 2 + 2).
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Ensure tabs do NOT stretch to fill the whole bar (the spacer absorbs extra width).
        trailingSpacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingSpacerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailingSpacerView.translatesAutoresizingMaskIntoConstraints = false

        documentContainerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: documentContainerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentContainerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: documentContainerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentContainerView.bottomAnchor),
        ])

        scrollView.documentView = documentContainerView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
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

        // Scroll view document view Auto Layout:
        // - Pin to the clip view to establish height.
        // - Allow width to grow beyond the visible area when tabs overflow.
        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            documentContainerView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            documentContainerView.topAnchor.constraint(equalTo: clipView.topAnchor),
            documentContainerView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
            documentContainerView.heightAnchor.constraint(equalTo: clipView.heightAnchor),
            documentContainerView.widthAnchor.constraint(greaterThanOrEqualTo: clipView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // 1px bottom divider line.
        bottomBorderLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
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
            chip.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(chip)
        }

        // Trailing flexible space to prevent the first tab from expanding to fill the whole row.
        stackView.addArrangedSubview(trailingSpacerView)
    }
}

@MainActor
private final class AttoTabChipView: NSView {
    private let id: UUID
    private let onSelect: () -> Void
    private let onClose: () -> Void

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton: NSButton
    private var trackingAreaRef: NSTrackingArea?
    private let selected: Bool

    // Sublime-ish sizing.
    private let minWidth: CGFloat = 96
    private let maxWidth: CGFloat = 240

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
        self.selected = selected

        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        {
            self.closeButton = NSButton(image: image, target: nil, action: nil)
        } else {
            self.closeButton = NSButton(title: "×", target: nil, action: nil)
        }
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.backgroundColor = (selected ? NSColor(attoHex: 0x1E1E1E) : NSColor(attoHex: 0x2B2B2B)).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(attoHex: 0x1E1E1E).cgColor

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        self.toolTip = toolTip

        titleLabel.stringValue = title
        let baseFont = NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular)
        titleLabel.font = isPreview
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            : baseFont
        titleLabel.textColor = selected ? NSColor(attoHex: 0xE6E6E6) : NSColor(attoHex: 0xB5B5B5)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.isBordered = false
        closeButton.contentTintColor = selected ? NSColor(attoHex: 0xD0D0D0) : NSColor(attoHex: 0x9A9A9A)
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = selected ? false : true

        addSubview(titleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 12),
            closeButton.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let labelWidth = titleLabel.intrinsicContentSize.width
        let closeWidth: CGFloat = closeButton.isHidden ? 0 : 12
        let paddingLeft: CGFloat = 10
        let paddingRight: CGFloat = closeButton.isHidden ? 10 : 8
        let gap: CGFloat = closeButton.isHidden ? 0 : 8

        let desired = paddingLeft + labelWidth + gap + closeWidth + paddingRight
        return NSSize(width: min(maxWidth, max(minWidth, desired)), height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let opts: NSTrackingArea.Options = [
            .activeInActiveApp,
            .mouseEnteredAndExited,
            .inVisibleRect,
        ]
        let ta = NSTrackingArea(rect: .zero, options: opts, owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingAreaRef = ta
    }

    override func mouseEntered(with event: NSEvent) {
        guard selected == false else { return }
        closeButton.isHidden = false
        invalidateIntrinsicContentSize()
    }

    override func mouseExited(with event: NSEvent) {
        guard selected == false else { return }
        closeButton.isHidden = true
        invalidateIntrinsicContentSize()
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
