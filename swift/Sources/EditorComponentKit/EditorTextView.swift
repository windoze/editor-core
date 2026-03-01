#if canImport(AppKit)
import AppKit

struct EditorTextLineMetric {
    var logicalLine: Int
    var utf16Range: NSRange
    var rect: CGRect
    var indentLevel: Int
}

final class EditorTextView: NSTextView {
    var keybindingRegistry: EditorKeybindingRegistry?
    var commandDispatcher: EditorCommandDispatching?

    var featureFlags: EditorFeatureFlags = .init() {
        didSet { needsDisplay = true }
    }

    var foldRegions: [EditorFoldRegion] = [] {
        didSet { needsDisplay = true }
    }

    private var stylePalette: EditorStylePalette = .default()
    private var inlays: [EditorInlay] = []
    private var diagnostics: EditorDiagnosticsSnapshot = .init(items: [])
    private var guideIndentColumns: Int = 4
    private var inlayFontScale: Double = 0.9
    private var inlayHorizontalPadding: CGFloat = 3
    private var offsetTranslator = EditorOffsetTranslator(text: "")

    override func didChangeText() {
        super.didChangeText()
        offsetTranslator = EditorOffsetTranslator(text: string)
    }

    func applyDecorations(
        styleSpans: [EditorStyleSpan],
        inlays: [EditorInlay],
        foldRegions: [EditorFoldRegion],
        diagnostics: EditorDiagnosticsSnapshot,
        visualStyle: EditorVisualStyle,
        featureFlags: EditorFeatureFlags
    ) {
        self.stylePalette = visualStyle.stylePalette
        self.inlays = inlays.sorted { lhs, rhs in
            if lhs.offset == rhs.offset {
                return lhs.text < rhs.text
            }
            return lhs.offset < rhs.offset
        }
        self.foldRegions = foldRegions
        self.diagnostics = diagnostics
        self.featureFlags = featureFlags
        self.guideIndentColumns = max(1, visualStyle.guideIndentColumns)
        self.inlayFontScale = max(0.2, visualStyle.inlayFontScale)
        self.inlayHorizontalPadding = CGFloat(max(0, visualStyle.inlayHorizontalPadding))

        applyTemporaryAttributes(styleSpans: styleSpans, diagnostics: diagnostics)
        needsDisplay = true
    }

    func logicalLineMetrics() -> [EditorTextLineMetric] {
        guard let layoutManager, let textContainer else {
            return []
        }
        layoutManager.ensureLayout(for: textContainer)

        let nsText = string as NSString
        let ranges = lineRanges(nsText: nsText)
        guard !ranges.isEmpty else {
            return []
        }

        let lineHeight = layoutManager.defaultLineHeight(
            for: font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )

        return ranges.enumerated().map { (index, range) in
            let rect = lineRect(
                forLineRange: range,
                lineIndex: index,
                totalLineCount: ranges.count,
                lineHeight: lineHeight,
                nsLength: nsText.length
            )
            let lineText = nsText.substring(with: range)
            let indentLevel = Self.indentLevel(
                for: lineText,
                guideIndentColumns: guideIndentColumns
            )
            return EditorTextLineMetric(
                logicalLine: index,
                utf16Range: range,
                rect: rect,
                indentLevel: indentLevel
            )
        }
    }

    func editorPosition(at point: NSPoint) -> EditorPosition? {
        guard let layoutManager, let textContainer else {
            return nil
        }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let scalarOffset = offsetTranslator.scalarOffset(forUTF16Offset: charIndex)
        return position(forScalarOffset: scalarOffset)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawGuides(in: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawInlays(in: dirtyRect)
    }

    override func keyDown(with event: NSEvent) {
        if let command = resolveCommand(from: event) {
            commandDispatcher?.dispatch(command)
            return
        }

        if !event.charactersIgnoringModifiers.isNilOrEmpty,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           let text = event.characters,
           !text.isEmpty,
           text != "\u{7F}",
           text != "\u{8}",
           text != "\t",
           text != "\r" {
            commandDispatcher?.dispatch(.insertText(text))
            return
        }

        super.keyDown(with: event)
    }

    private func applyTemporaryAttributes(
        styleSpans: [EditorStyleSpan],
        diagnostics: EditorDiagnosticsSnapshot
    ) {
        guard let layoutManager else {
            return
        }

        offsetTranslator = EditorOffsetTranslator(text: string)
        let fullRange = NSRange(location: 0, length: offsetTranslator.utf16Count)
        if fullRange.length > 0 {
            for key in Self.temporaryAttributeKeys {
                layoutManager.removeTemporaryAttribute(key, forCharacterRange: fullRange)
            }
        }

        for span in styleSpans {
            let range = offsetTranslator.utf16Range(
                startScalar: span.startOffset,
                endScalar: span.endOffset
            )
            guard range.length > 0, let style = stylePalette.styles[span.styleID] else {
                continue
            }
            let attrs = style.textAttributes(baseFont: font)
            guard !attrs.isEmpty else {
                continue
            }
            layoutManager.addTemporaryAttributes(attrs, forCharacterRange: range)
        }

        for item in diagnostics.items {
            let range = offsetTranslator.utf16Range(
                startScalar: item.startOffset,
                endScalar: item.endOffset
            )
            guard range.length > 0 else {
                continue
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: diagnosticUnderlineColor(for: item.severity)
            ]
            layoutManager.addTemporaryAttributes(attrs, forCharacterRange: range)
        }
    }

    private func drawInlays(in dirtyRect: NSRect) {
        guard !inlays.isEmpty else {
            return
        }

        let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        for inlay in inlays {
            let utf16Offset = offsetTranslator.utf16Offset(forScalarOffset: inlay.offset)
            guard let insertionPoint = insertionPoint(forUTF16Offset: utf16Offset) else {
                continue
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: defaultFont.withSize(defaultFont.pointSize * CGFloat(inlayFontScale)),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            if let styleID = inlay.styleIDs.first, let style = stylePalette.styles[styleID] {
                let styleAttrs = style.inlayAttributes(baseFont: defaultFont, scale: inlayFontScale)
                attrs.merge(styleAttrs, uniquingKeysWith: { _, new in new })
            }

            let attributed = NSAttributedString(string: inlay.text, attributes: attrs)
            let textSize = attributed.size()
            var drawPoint = insertionPoint

            switch inlay.placement {
            case .before:
                drawPoint.x -= textSize.width + inlayHorizontalPadding * 2 + 2
            case .after:
                drawPoint.x += 2
            case .aboveLine:
                drawPoint.y -= textSize.height + 3
            }

            let drawRect = CGRect(
                x: drawPoint.x,
                y: drawPoint.y,
                width: textSize.width + inlayHorizontalPadding * 2,
                height: textSize.height + 2
            )

            guard drawRect.intersects(dirtyRect) else {
                continue
            }

            NSColor.quaternaryLabelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(
                roundedRect: drawRect,
                xRadius: 3,
                yRadius: 3
            ).fill()

            attributed.draw(at: NSPoint(
                x: drawRect.minX + inlayHorizontalPadding,
                y: drawRect.minY + 1
            ))
        }
    }

    private func drawGuides(in rect: NSRect) {
        guard featureFlags.showsIndentGuides || featureFlags.showsStructureGuides else {
            return
        }

        let metrics = logicalLineMetrics().filter { $0.rect.intersects(rect) }
        guard !metrics.isEmpty else {
            return
        }

        let spaceWidth = max(
            (" " as NSString).size(withAttributes: [.font: font as Any]).width,
            1
        )
        let indentStep = CGFloat(guideIndentColumns) * spaceWidth
        let guideColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.25)

        guideColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1

        if featureFlags.showsIndentGuides {
            for metric in metrics where metric.indentLevel > 0 {
                for level in 1...metric.indentLevel {
                    let x = textContainerInset.width + CGFloat(level) * indentStep
                    path.move(to: NSPoint(x: x, y: metric.rect.minY + 1))
                    path.line(to: NSPoint(x: x, y: metric.rect.maxY - 1))
                }
            }
        }

        if featureFlags.showsStructureGuides {
            let lineMap = Dictionary(uniqueKeysWithValues: metrics.map { ($0.logicalLine, $0) })
            for fold in foldRegions where fold.endLine > fold.startLine {
                guard let start = lineMap[fold.startLine], let end = lineMap[fold.endLine] else {
                    continue
                }
                let level = max(start.indentLevel, 1)
                let x = textContainerInset.width + CGFloat(level) * indentStep - indentStep * 0.5
                path.move(to: NSPoint(x: x, y: start.rect.minY + 1))
                path.line(to: NSPoint(x: x, y: end.rect.maxY - 1))
            }
        }

        path.stroke()
    }

    private func resolveCommand(from event: NSEvent) -> EditorCommand? {
        guard let chars = event.charactersIgnoringModifiers else {
            return nil
        }

        let flags = Self.modifiers(from: event.modifierFlags)
        let chord = EditorKeyChord(key: chars.lowercased(), modifiers: flags)
        return keybindingRegistry?.resolve(chord)
    }

    private func lineRanges(nsText: NSString) -> [NSRange] {
        let length = nsText.length
        if length == 0 {
            return [NSRange(location: 0, length: 0)]
        }

        var ranges: [NSRange] = []
        var lineStart = 0
        var index = 0
        while index < length {
            if nsText.character(at: index) == 10 {
                ranges.append(NSRange(location: lineStart, length: index - lineStart))
                lineStart = index + 1
            }
            index += 1
        }
        ranges.append(NSRange(location: lineStart, length: length - lineStart))
        return ranges
    }

    private func lineRect(
        forLineRange lineRange: NSRange,
        lineIndex: Int,
        totalLineCount: Int,
        lineHeight: CGFloat,
        nsLength: Int
    ) -> CGRect {
        guard let layoutManager, let textContainer else {
            let y = textContainerInset.height + CGFloat(lineIndex) * lineHeight
            return CGRect(
                x: textContainerInset.width,
                y: y,
                width: bounds.width - textContainerInset.width * 2,
                height: lineHeight
            )
        }

        if layoutManager.numberOfGlyphs == 0 {
            let y = textContainerInset.height + CGFloat(lineIndex) * lineHeight
            return CGRect(
                x: textContainerInset.width,
                y: y,
                width: textContainer.size.width,
                height: lineHeight
            )
        }

        if lineRange.location >= nsLength, lineIndex == totalLineCount - 1 {
            var rect = layoutManager.extraLineFragmentUsedRect
            if rect.isEmpty {
                let glyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
                let last = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let inferredHeight = max(last.height, lineHeight)
                rect = CGRect(x: last.minX, y: last.maxY, width: last.width, height: inferredHeight)
            }
            return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        }

        let charLocation = min(lineRange.location, max(nsLength - 1, 0))
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: charLocation, length: 0),
            actualCharacterRange: nil
        )
        let glyphIndex = min(max(glyphRange.location, 0), max(layoutManager.numberOfGlyphs - 1, 0))
        var rect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        if rect.isEmpty {
            rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }
        if rect.isEmpty {
            rect = CGRect(
                x: 0,
                y: CGFloat(lineIndex) * lineHeight,
                width: textContainer.size.width,
                height: lineHeight
            )
        }
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    private static func indentLevel(for line: String, guideIndentColumns: Int) -> Int {
        var columns = 0
        for scalar in line.unicodeScalars {
            if scalar == " " {
                columns += 1
            } else if scalar == "\t" {
                columns += guideIndentColumns
            } else {
                break
            }
        }
        return columns / max(guideIndentColumns, 1)
    }

    private func insertionPoint(forUTF16Offset offset: Int) -> NSPoint? {
        let nsLength = (string as NSString).length
        let clamped = max(0, min(offset, nsLength))
        let charRange = NSRange(location: clamped, length: 0)

        if window != nil {
            let screenRect = firstRect(forCharacterRange: charRange, actualRange: nil)
            if !screenRect.isEmpty {
                let windowPoint = window?.convertPoint(fromScreen: screenRect.origin) ?? screenRect.origin
                return convert(windowPoint, from: nil)
            }
        }

        guard let layoutManager, let textContainer else {
            return NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        }
        layoutManager.ensureLayout(for: textContainer)

        if layoutManager.numberOfGlyphs == 0 {
            return NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        }

        let glyphIndex: Int
        if clamped >= nsLength {
            glyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
            var rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            if rect.isEmpty {
                rect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            }
            return NSPoint(
                x: rect.maxX + textContainerOrigin.x,
                y: rect.minY + textContainerOrigin.y
            )
        } else {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: charRange,
                actualCharacterRange: nil
            )
            glyphIndex = min(max(glyphRange.location, 0), max(layoutManager.numberOfGlyphs - 1, 0))
        }

        var rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        if rect.isEmpty {
            rect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }
        return NSPoint(x: rect.minX + textContainerOrigin.x, y: rect.minY + textContainerOrigin.y)
    }

    private func position(forScalarOffset scalarOffset: Int) -> EditorPosition {
        let target = max(0, scalarOffset)
        var offset = 0
        var line = 0
        var column = 0

        for scalar in string.unicodeScalars {
            if offset >= target {
                break
            }
            if scalar == "\n" {
                line += 1
                column = 0
            } else {
                column += 1
            }
            offset += 1
        }

        return EditorPosition(line: line, column: column)
    }

    private func diagnosticUnderlineColor(for severity: String) -> NSColor {
        switch severity.lowercased() {
        case "error":
            return NSColor.systemRed
        case "warning":
            return NSColor.systemOrange
        case "info":
            return NSColor.systemBlue
        default:
            return NSColor.systemGray
        }
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> EditorModifierFlags {
        var result: EditorModifierFlags = []
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        if flags.contains(.option) {
            result.insert(.option)
        }
        if flags.contains(.command) {
            result.insert(.command)
        }
        return result
    }

    private static let temporaryAttributeKeys: [NSAttributedString.Key] = [
        .foregroundColor,
        .backgroundColor,
        .underlineStyle,
        .underlineColor,
        .font
    ]
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
#endif
