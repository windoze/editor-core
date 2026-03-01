#if canImport(AppKit)
import AppKit

final class EditorGutterView: NSView {
    weak var textView: EditorTextView? {
        didSet { needsDisplay = true }
    }

    var lineNumbers: [Int] = [] {
        didSet { needsDisplay = true }
    }

    var foldRegions: [EditorFoldRegion] = [] {
        didSet { needsDisplay = true }
    }

    var showsLineNumbers: Bool = true {
        didSet { needsDisplay = true }
    }

    var onToggleFoldRegion: ((EditorFoldRegion) -> Void)?

    private var foldMarkerRects: [(rect: CGRect, region: EditorFoldRegion)] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        guard let textView else {
            return
        }

        let metrics = textView.logicalLineMetrics().filter { metric in
            metric.rect.maxY >= dirtyRect.minY && metric.rect.minY <= dirtyRect.maxY
        }
        let foldStarts = Dictionary(uniqueKeysWithValues: foldRegions.map { ($0.startLine, $0) })

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        foldMarkerRects = []
        for metric in metrics {
            if showsLineNumbers {
                let displayLine = metric.logicalLine + 1
                let lineText = lineNumbers.indices.contains(metric.logicalLine)
                    ? "\(lineNumbers[metric.logicalLine])"
                    : "\(displayLine)"

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph
                ]

                NSString(string: lineText).draw(
                    in: CGRect(x: 0, y: metric.rect.minY, width: bounds.width - 18, height: metric.rect.height),
                    withAttributes: attrs
                )
            }

            guard let region = foldStarts[metric.logicalLine], region.endLine > region.startLine else {
                continue
            }

            let markerRect = CGRect(
                x: max(bounds.width - 14, 2),
                y: metric.rect.midY - 5,
                width: 10,
                height: 10
            )
            foldMarkerRects.append((markerRect, region))

            let color = region.isCollapsed
                ? NSColor.controlAccentColor
                : NSColor.tertiaryLabelColor
            color.setFill()
            foldMarkerPath(in: markerRect, collapsed: region.isCollapsed).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let item = foldMarkerRects.first(where: { $0.rect.contains(point) }) {
            onToggleFoldRegion?(item.region)
            return
        }
        super.mouseDown(with: event)
    }

    private func foldMarkerPath(in rect: CGRect, collapsed: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        if collapsed {
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 1))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY))
            path.line(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 1))
        } else {
            path.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 2))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.minY + 2))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 2))
        }
        path.close()
        return path
    }
}
#endif
