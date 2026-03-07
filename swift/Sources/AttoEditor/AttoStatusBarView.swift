import AppKit
import Foundation

@MainActor
final class AttoStatusBarView: NSView {
    private let leftLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let fileSizeLabel = NSTextField(labelWithString: "")

    private let rightStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        // VSCode-ish status bar blue.
        layer?.backgroundColor = NSColor(attoHex: 0x007ACC).cgColor

        leftLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        leftLabel.textColor = .white
        leftLabel.lineBreakMode = .byTruncatingMiddle
        leftLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftLabel.translatesAutoresizingMaskIntoConstraints = false

        for l in [positionLabel, selectionLabel, fileSizeLabel] {
            l.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            l.textColor = .white
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

