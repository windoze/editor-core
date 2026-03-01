import Foundation

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

    public init(
        fontName: String = "Menlo",
        fontSize: Double = 13,
        lineHeightMultiplier: Double = 1.25,
        enablesLigatures: Bool = true
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineHeightMultiplier = lineHeightMultiplier
        self.enablesLigatures = enablesLigatures
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
