#if canImport(AppKit)
import AppKit

extension EditorRGBAColor {
    var nsColor: NSColor {
        NSColor(
            red: CGFloat(max(0, min(red, 1))),
            green: CGFloat(max(0, min(green, 1))),
            blue: CGFloat(max(0, min(blue, 1))),
            alpha: CGFloat(max(0, min(alpha, 1)))
        )
    }
}

extension EditorStyleAttributes {
    func textAttributes(baseFont: NSFont?) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        if let foreground {
            attrs[.foregroundColor] = foreground.nsColor
        }
        if let background {
            attrs[.backgroundColor] = background.nsColor
        }
        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if let baseFont {
            attrs[.font] = styledFont(from: baseFont)
        }

        return attrs
    }

    func inlayAttributes(baseFont: NSFont?, scale: Double) -> [NSAttributedString.Key: Any] {
        var attrs = textAttributes(baseFont: baseFont)
        let font = styledFont(from: baseFont)
        attrs[.font] = font.withSize(font.pointSize * CGFloat(max(scale, 0.2)))
        if attrs[.foregroundColor] == nil {
            attrs[.foregroundColor] = NSColor.secondaryLabelColor
        }
        return attrs
    }

    private func styledFont(from baseFont: NSFont?) -> NSFont {
        guard var font = baseFont else {
            return NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }

        let manager = NSFontManager.shared
        if bold {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if italic {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}
#endif
