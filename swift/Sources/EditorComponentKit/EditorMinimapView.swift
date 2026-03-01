#if canImport(AppKit)
import AppKit

final class EditorMinimapView: NSView {
    var snapshot: EditorMinimapSnapshot = .init(startVisualRow: 0, requestedCount: 0, lines: []) {
        didSet { needsDisplay = true }
    }

    var visibleVisualRange: Range<Int>? {
        didSet { needsDisplay = true }
    }

    var dominantStyleColorProvider: ((UInt32) -> NSColor?)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard !snapshot.lines.isEmpty else {
            return
        }

        let maxCells = max(snapshot.lines.map(\.totalCells).max() ?? 1, 1)
        let rowHeight = max(bounds.height / CGFloat(snapshot.lines.count), 1)

        for (index, line) in snapshot.lines.enumerated() {
            let fillColor: NSColor
            if let styleID = line.dominantStyle, let styleColor = dominantStyleColorProvider?(styleID) {
                fillColor = styleColor.withAlphaComponent(0.35)
            } else {
                let alpha = min(max(CGFloat(line.nonWhitespaceCells) / CGFloat(maxCells), 0.1), 1.0)
                fillColor = NSColor.tertiaryLabelColor.withAlphaComponent(alpha)
            }

            fillColor.setFill()
            let width = CGFloat(line.totalCells) / CGFloat(maxCells) * bounds.width
            CGRect(
                x: 0,
                y: CGFloat(index) * rowHeight,
                width: width,
                height: max(rowHeight - 0.5, 0.5)
            ).fill()
        }

        if let visibleVisualRange {
            let lower = max(0, visibleVisualRange.lowerBound)
            let upper = min(snapshot.lines.count, max(visibleVisualRange.upperBound, lower))
            if upper > lower {
                let rect = CGRect(
                    x: 0.5,
                    y: CGFloat(lower) * rowHeight + 0.5,
                    width: bounds.width - 1,
                    height: CGFloat(upper - lower) * rowHeight - 1
                )
                NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
                rect.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
                NSBezierPath(rect: rect).stroke()
            }
        }
    }
}
#endif
