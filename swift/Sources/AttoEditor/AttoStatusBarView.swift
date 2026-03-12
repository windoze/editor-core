import AppKit
import Foundation

@MainActor
final class AttoStatusBarView: NSView {
    struct LanguageOption: Equatable {
        /// `nil` 表示 Plain Text（禁用语法/高亮引擎）。
        let id: String?
        let title: String
    }

    var onSelectLanguage: ((String?) -> Void)?

    private let leftLabel = NSTextField(labelWithString: "")
    private let languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lspLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let fileSizeLabel = NSTextField(labelWithString: "")

    private let rightStack = NSStackView()
    private let topBorderLayer = CALayer()

    private var languageOptions: [LanguageOption] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        // Sublime-ish: neutral dark status bar (avoid VSCode blue).
        layer?.backgroundColor = NSColor(attoHex: 0x2B2B2B).cgColor
        topBorderLayer.backgroundColor = NSColor(attoHex: 0x1E1E1E).cgColor
        layer?.addSublayer(topBorderLayer)

        leftLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        leftLabel.textColor = NSColor(attoHex: 0xB5B5B5)
        leftLabel.lineBreakMode = .byTruncatingMiddle
        leftLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftLabel.translatesAutoresizingMaskIntoConstraints = false

        languagePopUp.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        languagePopUp.controlSize = .small
        languagePopUp.isBordered = false
        languagePopUp.contentTintColor = NSColor(attoHex: 0xB5B5B5)
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged(_:))
        languagePopUp.translatesAutoresizingMaskIntoConstraints = false

        for l in [positionLabel, selectionLabel, fileSizeLabel] {
            l.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            l.textColor = NSColor(attoHex: 0xB5B5B5)
            l.translatesAutoresizingMaskIntoConstraints = false
        }

        lspLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        lspLabel.textColor = NSColor(attoHex: 0xB5B5B5)
        lspLabel.translatesAutoresizingMaskIntoConstraints = false

        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 12
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.addArrangedSubview(languagePopUp)
        rightStack.addArrangedSubview(lspLabel)
        rightStack.addArrangedSubview(positionLabel)
        rightStack.addArrangedSubview(selectionLabel)
        rightStack.addArrangedSubview(fileSizeLabel)

        addSubview(leftLabel)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -10),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Default language list: always include "Plain Tex" (MVP); richer options are supplied by the host.
        setLanguageOptions([.init(id: nil, title: "Plain Tex")])
        update(
            leftText: nil,
            languageId: nil,
            languageIsEnabled: false,
            lspText: nil,
            positionText: "Ln -, Col -",
            selectionText: nil,
            fileSizeText: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // 1px top divider line.
        topBorderLayer.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }

    func setLanguageOptions(_ options: [LanguageOption]) {
        guard options != languageOptions else { return }
        languageOptions = options

        languagePopUp.removeAllItems()
        for opt in options {
            languagePopUp.addItem(withTitle: opt.title)
            languagePopUp.lastItem?.representedObject = opt.id ?? NSNull()
        }
    }

    func update(
        leftText: String?,
        languageId: String?,
        languageIsEnabled: Bool,
        lspText: String?,
        positionText: String,
        selectionText: String?,
        fileSizeText: String?
    ) {
        leftLabel.stringValue = leftText ?? ""

        // Language selector
        languagePopUp.isEnabled = languageIsEnabled
        if languageOptions.isEmpty == false {
            if let idx = languageOptions.firstIndex(where: { $0.id == languageId }) {
                languagePopUp.selectItem(at: idx)
            } else if let idx = languageOptions.firstIndex(where: { $0.id == nil }) {
                languagePopUp.selectItem(at: idx)
            } else {
                languagePopUp.selectItem(at: 0)
            }
        }

        lspLabel.stringValue = lspText ?? ""
        lspLabel.isHidden = (lspText?.isEmpty != false)
        positionLabel.stringValue = positionText
        selectionLabel.stringValue = selectionText ?? ""
        fileSizeLabel.stringValue = fileSizeText ?? ""
    }

    @objc private func languageChanged(_ sender: Any?) {
        let idx = languagePopUp.indexOfSelectedItem
        guard (0..<languageOptions.count).contains(idx) else { return }
        onSelectLanguage?(languageOptions[idx].id)
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
