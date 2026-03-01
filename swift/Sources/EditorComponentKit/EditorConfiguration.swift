import Foundation

public struct EditorRGBAColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let clear = Self(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = Self(red: 0, green: 0, blue: 0, alpha: 1)
    public static let white = Self(red: 1, green: 1, blue: 1, alpha: 1)
}

public struct EditorStyleAttributes: Equatable, Sendable {
    public var foreground: EditorRGBAColor?
    public var background: EditorRGBAColor?
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public init(
        foreground: EditorRGBAColor? = nil,
        background: EditorRGBAColor? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }
}

public struct EditorStylePalette: Sendable {
    public var styles: [UInt32: EditorStyleAttributes]

    public init(styles: [UInt32: EditorStyleAttributes] = [:]) {
        self.styles = styles
    }

    public static func `default`() -> Self {
        Self(styles: [
            1: EditorStyleAttributes(
                foreground: EditorRGBAColor(red: 0.13, green: 0.32, blue: 0.86),
                bold: true
            ),
            2: EditorStyleAttributes(
                foreground: EditorRGBAColor(red: 0.67, green: 0.09, blue: 0.38)
            ),
            3: EditorStyleAttributes(
                foreground: EditorRGBAColor(red: 0.01, green: 0.49, blue: 0.22)
            ),
            4: EditorStyleAttributes(
                foreground: EditorRGBAColor(red: 0.48, green: 0.25, blue: 0.79),
                italic: true
            ),
            5: EditorStyleAttributes(
                foreground: EditorRGBAColor(red: 0.52, green: 0.52, blue: 0.52),
                italic: true
            ),
            6: EditorStyleAttributes(
                foreground: EditorRGBAColor(red: 0.71, green: 0.07, blue: 0.07),
                underline: true
            )
        ])
    }
}

public struct EditorFeatureFlags: Equatable, Hashable, Sendable {
    public var showsGutter: Bool
    public var showsLineNumbers: Bool
    public var showsMinimap: Bool
    public var showsIndentGuides: Bool
    public var showsStructureGuides: Bool

    public init(
        showsGutter: Bool = true,
        showsLineNumbers: Bool = true,
        showsMinimap: Bool = false,
        showsIndentGuides: Bool = true,
        showsStructureGuides: Bool = true
    ) {
        self.showsGutter = showsGutter
        self.showsLineNumbers = showsLineNumbers
        self.showsMinimap = showsMinimap
        self.showsIndentGuides = showsIndentGuides
        self.showsStructureGuides = showsStructureGuides
    }
}

public struct EditorVisualStyle: Sendable {
    public var fontName: String
    public var fontSize: Double
    public var lineHeightMultiplier: Double
    public var enablesLigatures: Bool
    public var stylePalette: EditorStylePalette
    public var inlayFontScale: Double
    public var inlayHorizontalPadding: Double
    public var guideIndentColumns: Int

    public init(
        fontName: String = "Menlo",
        fontSize: Double = 13,
        lineHeightMultiplier: Double = 1.25,
        enablesLigatures: Bool = true,
        stylePalette: EditorStylePalette = .default(),
        inlayFontScale: Double = 0.9,
        inlayHorizontalPadding: Double = 3,
        guideIndentColumns: Int = 4
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineHeightMultiplier = lineHeightMultiplier
        self.enablesLigatures = enablesLigatures
        self.stylePalette = stylePalette
        self.inlayFontScale = inlayFontScale
        self.inlayHorizontalPadding = inlayHorizontalPadding
        self.guideIndentColumns = max(1, guideIndentColumns)
    }
}

public struct EditorComponentConfiguration: Sendable {
    public var features: EditorFeatureFlags
    public var visualStyle: EditorVisualStyle

    public init(features: EditorFeatureFlags = .init(), visualStyle: EditorVisualStyle = .init()) {
        self.features = features
        self.visualStyle = visualStyle
    }
}
