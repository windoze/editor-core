import AppKit
import Foundation

@MainActor
final class AttoFindReplaceBarView: NSView {
    enum Mode: Equatable {
        case find
        case replace
    }

    let searchField = NSSearchField(frame: .zero)
    let replaceField = NSTextField(frame: .zero)

    let caseSensitiveButton = NSButton(checkboxWithTitle: "Aa", target: nil, action: nil)
    let wholeWordButton = NSButton(checkboxWithTitle: "Word", target: nil, action: nil)
    let regexButton = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)

    let matchCountLabel = NSTextField(labelWithString: "0 matches")

    let findPrevButton: NSButton
    let findNextButton: NSButton
    let clearButton: NSButton

    let replaceCurrentButton: NSButton
    let replaceAllButton: NSButton

    let closeButton: NSButton

    private let rootStack = NSStackView()
    private let findRow = NSStackView()
    private let replaceRow = NSStackView()
    private let bottomBorderLayer = CALayer()

    private var mode: Mode = .find

    override init(frame frameRect: NSRect) {
        if let image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Find Previous")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        {
            findPrevButton = NSButton(image: image, target: nil, action: nil)
        } else {
            findPrevButton = NSButton(title: "Prev", target: nil, action: nil)
        }

        if let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Find Next")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        {
            findNextButton = NSButton(image: image, target: nil, action: nil)
        } else {
            findNextButton = NSButton(title: "Next", target: nil, action: nil)
        }

        clearButton = NSButton(title: "Clear", target: nil, action: nil)

        replaceCurrentButton = NSButton(title: "Replace", target: nil, action: nil)
        replaceAllButton = NSButton(title: "All", target: nil, action: nil)

        if let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close Find")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        {
            closeButton = NSButton(image: image, target: nil, action: nil)
        } else {
            closeButton = NSButton(title: "×", target: nil, action: nil)
        }

        super.init(frame: frameRect)

        identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findReplaceBar)
        wantsLayer = true
        layer?.backgroundColor = NSColor(attoHex: 0x252526).cgColor
        bottomBorderLayer.backgroundColor = NSColor(attoHex: 0x1E1E1E).cgColor
        layer?.addSublayer(bottomBorderLayer)

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 6
        rootStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Find"
        searchField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findSearchField)
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)])

        replaceField.placeholderString = "Replace"
        replaceField.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findReplaceField)
        replaceField.controlSize = .small
        replaceField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        replaceField.focusRingType = .none
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)])

        for b in [caseSensitiveButton, wholeWordButton, regexButton] {
            b.setButtonType(.switch)
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        caseSensitiveButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findCaseSensitiveButton)
        wholeWordButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findWholeWordButton)
        regexButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findRegexButton)
        caseSensitiveButton.state = .on

        matchCountLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        matchCountLabel.textColor = NSColor(attoHex: 0xB5B5B5)
        matchCountLabel.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findMatchCountLabel)

        for b in [findPrevButton, findNextButton, clearButton, replaceCurrentButton, replaceAllButton] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        findPrevButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findPreviousButton)
        findNextButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findNextButton)
        clearButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findClearButton)
        replaceCurrentButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findReplaceCurrentButton)
        replaceAllButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findReplaceAllButton)
        replaceAllButton.title = "All"

        closeButton.isBordered = false
        closeButton.identifier = NSUserInterfaceItemIdentifier(AttoAccessibilityID.findCloseButton)
        closeButton.contentTintColor = NSColor(attoHex: 0x9A9A9A)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        findRow.orientation = .horizontal
        findRow.alignment = .centerY
        findRow.spacing = 8
        findRow.translatesAutoresizingMaskIntoConstraints = false

        findRow.addArrangedSubview(searchField)
        findRow.addArrangedSubview(caseSensitiveButton)
        findRow.addArrangedSubview(wholeWordButton)
        findRow.addArrangedSubview(regexButton)
        findRow.addArrangedSubview(matchCountLabel)
        findRow.addArrangedSubview(findPrevButton)
        findRow.addArrangedSubview(findNextButton)
        findRow.addArrangedSubview(clearButton)

        let spacer = NSView(frame: .zero)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        findRow.addArrangedSubview(spacer)
        findRow.addArrangedSubview(closeButton)

        replaceRow.orientation = .horizontal
        replaceRow.alignment = .centerY
        replaceRow.spacing = 8
        replaceRow.translatesAutoresizingMaskIntoConstraints = false

        replaceRow.addArrangedSubview(replaceField)
        replaceRow.addArrangedSubview(replaceCurrentButton)
        replaceRow.addArrangedSubview(replaceAllButton)

        rootStack.addArrangedSubview(findRow)
        rootStack.addArrangedSubview(replaceRow)

        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setMode(.find)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // 1px bottom divider line.
        bottomBorderLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        replaceRow.isHidden = (mode == .find)
    }

    func currentMode() -> Mode { mode }
}

private extension NSColor {
    convenience init(attoHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((attoHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((attoHex >> 8) & 0xFF) / 255.0
        let b = CGFloat(attoHex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
