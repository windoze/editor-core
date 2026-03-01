#if canImport(AppKit)
import AppKit

final class EditorMinimapView: NSView {
    var snapshot: EditorMinimapSnapshot = .init(startVisualRow: 0, requestedCount: 0, lines: []) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard !snapshot.lines.isEmpty else {
            return
        }

        let maxCells = max(snapshot.lines.map(\ .totalCells).max() ?? 1, 1)
        let rowHeight = max(bounds.height / CGFloat(snapshot.lines.count), 1)

        for (index, line) in snapshot.lines.enumerated() {
            let alpha = min(max(CGFloat(line.nonWhitespaceCells) / CGFloat(maxCells), 0.1), 1.0)
            NSColor.tertiaryLabelColor.withAlphaComponent(alpha).setFill()
            let width = CGFloat(line.totalCells) / CGFloat(maxCells) * bounds.width
            CGRect(x: 0, y: CGFloat(index) * rowHeight, width: width, height: rowHeight - 0.5).fill()
        }
    }
}
#endif
