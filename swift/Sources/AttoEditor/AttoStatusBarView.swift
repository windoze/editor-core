import AppKit
import Foundation

@MainActor
final class AttoStatusBarView: NSView {
    private let leftLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let fileSizeLabel = NSTextField(labelWithString: "")

    private let rightStack = NSStackView()
    private let topBorderLayer = CALayer()

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

        for l in [positionLabel, selectionLabel, fileSizeLabel] {
            l.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            l.textColor = NSColor(attoHex: 0xB5B5B5)
            l.translatesAutoresizingMaskIntoConstraints = false
        }

        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 12
        rightStack.translatesAutoresizingMaskIntoConstraints = false
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

        update(leftText: nil, positionText: "Ln -, Col -", selectionText: nil, fileSizeText: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // 1px top divider line.
        topBorderLayer.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }

    func update(leftText: String?, positionText: String, selectionText: String?, fileSizeText: String?) {
        leftLabel.stringValue = leftText ?? ""
        positionLabel.stringValue = positionText
        selectionLabel.stringValue = selectionText ?? ""
        fileSizeLabel.stringValue = fileSizeText ?? ""
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
