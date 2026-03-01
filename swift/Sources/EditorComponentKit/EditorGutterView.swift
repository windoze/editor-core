#if canImport(AppKit)
import AppKit

final class EditorGutterView: NSView {
    var lineNumbers: [Int] = [] {
        didSet { needsDisplay = true }
    }

    var selectedFoldStartLines: Set<Int> = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        for (index, lineNumber) in lineNumbers.enumerated() {
            let y = CGFloat(index) * 18
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: selectedFoldStartLines.contains(lineNumber)
                    ? NSColor.controlAccentColor
                    : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]

            NSString(string: "\(lineNumber)").draw(
                in: CGRect(x: 0, y: y, width: bounds.width - 6, height: 16),
                withAttributes: attrs
            )
        }
    }
}
#endif
