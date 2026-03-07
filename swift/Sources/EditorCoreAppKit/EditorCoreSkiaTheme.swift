import AppKit
import EditorCoreUIFFI
import Foundation

/// `EditorCoreSkiaView` 相关 UI 元素的主题（AppKit 侧）。
///
/// 设计目标：
/// - 把「编辑器渲染主题（Rust/Skia）」与「外部 UI chrome（minimap/scrollbar）」放在同一份配置里；
/// - 允许按 `StyleId` 自定义颜色与视觉装饰（underline/strikethrough 等）；
/// - 允许按 Tree-sitter capture name（如 `comment`/`string`）配置样式，内部自动映射到 `StyleId`。
@frozen
public struct EditorCoreSkiaTheme: Equatable {
    /// 编辑器主视口（Rust/Skia renderer）的基础颜色。
    public var editorBackground: EcuRgba8
    public var editorForeground: EcuRgba8
    public var selectionBackground: EcuRgba8
    public var caret: EcuRgba8

    /// Gutter / fold marker（由 Rust/Skia renderer 绘制，但属于 UI chrome）配色。
    public var gutterBackground: EcuRgba8
    public var gutterForeground: EcuRgba8
    public var gutterSeparator: EcuRgba8
    public var foldMarkerCollapsed: EcuRgba8
    public var foldMarkerExpanded: EcuRgba8

    /// Minimap 背景色（AppKit 侧渲染）。
    ///
    /// 若为 `nil`，默认使用 `editorBackground` 的“略微变暗”版本。
    public var minimapBackground: EcuRgba8?

    /// Scrollbar（AppKit 侧渲染）的配色。
    ///
    /// - `scrollbarBackground`: 轨道背景（knob slot）
    /// - `scrollbarForeground`: 滑块（thumb / knob）
    ///
    /// 若为 `nil`，将基于 `editorBackground` 自动推导出一个有对比度的默认值。
    public var scrollbarBackground: EcuRgba8?
    public var scrollbarForeground: EcuRgba8?

    /// 按 `StyleId` 配置的样式覆盖（颜色 + underline/strikethrough 等）。
    public var styleOverrides: [EditorCoreSkiaStyleOverride]

    /// 按 Tree-sitter capture name 配置的样式覆盖（会在 `apply` 时映射到 StyleId）。
    public var treeSitterCaptureOverrides: [EditorCoreSkiaTreeSitterCaptureOverride]

    public init(
        editorBackground: EcuRgba8,
        editorForeground: EcuRgba8,
        selectionBackground: EcuRgba8,
        caret: EcuRgba8,
        gutterBackground: EcuRgba8,
        gutterForeground: EcuRgba8,
        gutterSeparator: EcuRgba8,
        foldMarkerCollapsed: EcuRgba8,
        foldMarkerExpanded: EcuRgba8,
        minimapBackground: EcuRgba8? = nil,
        scrollbarBackground: EcuRgba8? = nil,
        scrollbarForeground: EcuRgba8? = nil,
        styleOverrides: [EditorCoreSkiaStyleOverride] = [],
        treeSitterCaptureOverrides: [EditorCoreSkiaTreeSitterCaptureOverride] = []
    ) {
        self.editorBackground = editorBackground
        self.editorForeground = editorForeground
        self.selectionBackground = selectionBackground
        self.caret = caret
        self.gutterBackground = gutterBackground
        self.gutterForeground = gutterForeground
        self.gutterSeparator = gutterSeparator
        self.foldMarkerCollapsed = foldMarkerCollapsed
        self.foldMarkerExpanded = foldMarkerExpanded
        self.minimapBackground = minimapBackground
        self.scrollbarBackground = scrollbarBackground
        self.scrollbarForeground = scrollbarForeground
        self.styleOverrides = styleOverrides
        self.treeSitterCaptureOverrides = treeSitterCaptureOverrides
    }

    /// Demo/默认：浅色主题。
    public static func defaultLight() -> Self {
        Self(
            editorBackground: EcuRgba8(r: 0xFF, g: 0xFF, b: 0xFF, a: 0xFF),
            editorForeground: EcuRgba8(r: 0x11, g: 0x11, b: 0x11, a: 0xFF),
            selectionBackground: EcuRgba8(r: 0xC7, g: 0xDD, b: 0xFF, a: 0xFF),
            caret: EcuRgba8(r: 0x11, g: 0x11, b: 0x11, a: 0xFF),
            gutterBackground: EcuRgba8(r: 0xF5, g: 0xF5, b: 0xF5, a: 0xFF),
            gutterForeground: EcuRgba8(r: 0x88, g: 0x88, b: 0x88, a: 0xFF),
            gutterSeparator: EcuRgba8(r: 0xDD, g: 0xDD, b: 0xDD, a: 0xFF),
            foldMarkerCollapsed: EcuRgba8(r: 0x77, g: 0x77, b: 0x77, a: 0xFF),
            foldMarkerExpanded: EcuRgba8(r: 0xAA, g: 0xAA, b: 0xAA, a: 0xFF)
        )
    }

    /// Demo：适合 Rust + LSP（semantic tokens / inlay hints / diagnostics）的深色主题。
    ///
    /// 说明：
    /// - 语义 token 的 `StyleId` 编码使用 `editor-core-lsp` 的默认规则：
    ///   `style_id = (token_type_idx << 16) | (token_modifiers_bits & 0xFFFF)`
    /// - 这里的 tokenTypes/tokenModifiers 列表需要与 Rust 侧 `lsp_enable_stdio` 里声明的保持一致。
    public static func demoRustLspDark() -> Self {
        var theme = Self(
            editorBackground: EcuRgba8(r: 0x1E, g: 0x1E, b: 0x1E, a: 0xFF),
            editorForeground: EcuRgba8(r: 0xD4, g: 0xD4, b: 0xD4, a: 0xFF),
            selectionBackground: EcuRgba8(r: 0x26, g: 0x4F, b: 0x78, a: 0xFF),
            caret: EcuRgba8(r: 0xAE, g: 0xAF, b: 0xAD, a: 0xFF),
            gutterBackground: EcuRgba8(r: 0x25, g: 0x25, b: 0x26, a: 0xFF),
            gutterForeground: EcuRgba8(r: 0x85, g: 0x85, b: 0x85, a: 0xFF),
            gutterSeparator: EcuRgba8(r: 0x33, g: 0x33, b: 0x33, a: 0xFF),
            foldMarkerCollapsed: EcuRgba8(r: 0x6B, g: 0x6B, b: 0x6B, a: 0xFF),
            foldMarkerExpanded: EcuRgba8(r: 0xA0, g: 0xA0, b: 0xA0, a: 0xFF)
        )

        theme.minimapBackground = theme.editorBackground.darkened(by: 0.08)
        theme.scrollbarBackground = theme.editorBackground.darkened(by: 0.10)
        theme.scrollbarForeground = theme.editorBackground.lightened(by: 0.22)

        // Built-in overlay / virtual-text styles.
        theme.styleOverrides = [
            // Inlay hints：灰色前景 + 微弱背景，便于辨认虚拟文本。
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.inlayHint,
                foreground: EcuRgba8(r: 0x9A, g: 0xA0, b: 0xA6, a: 0xFF),
                background: EcuRgba8(r: 0x2A, g: 0x2A, b: 0x2A, a: 0xFF),
                italic: true
            ),
            // Code lens：更淡一些。
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.codeLens,
                foreground: EcuRgba8(r: 0x8A, g: 0x8A, b: 0x8A, a: 0xFF),
                background: EcuRgba8(r: 0x22, g: 0x22, b: 0x22, a: 0xFF),
                italic: true
            ),
            // Document links：蓝色 + 双下划线（演示 TextDecorations）。
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.documentLink,
                foreground: EcuRgba8(r: 0x4F, g: 0xC1, b: 0xFF, a: 0xFF),
                underline: .double
            ),
            // Search match highlights.
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.matchHighlight,
                background: EcuRgba8(r: 0x51, g: 0x44, b: 0x00, a: 0xFF)
            ),
            // Folding placeholder text.
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.foldPlaceholder,
                foreground: EcuRgba8(r: 0x80, g: 0x80, b: 0x80, a: 0xFF)
            ),
            // IME marked text：默认单下划线（颜色可见即可）。
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.imeMarkedText,
                underline: .single,
                underlineColor: EcuRgba8(r: 0xC5, g: 0x86, b: 0xC0, a: 0xFF)
            ),
            // LSP diagnostics underline：用 squiggly 展示 “波浪线”。
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.lspDiagnostic(severity: 1),
                underline: .squiggly,
                underlineColor: EcuRgba8(r: 0xF4, g: 0x47, b: 0x47, a: 0xFF)
            ),
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.lspDiagnostic(severity: 2),
                underline: .squiggly,
                underlineColor: EcuRgba8(r: 0xFF, g: 0xC1, b: 0x07, a: 0xFF)
            ),
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.lspDiagnostic(severity: 3),
                underline: .squiggly,
                underlineColor: EcuRgba8(r: 0x4F, g: 0xC1, b: 0xFF, a: 0xFF)
            ),
            .init(
                styleId: EditorCoreSkiaBuiltinStyleId.lspDiagnostic(severity: 4),
                underline: .squiggly,
                underlineColor: EcuRgba8(r: 0x9A, g: 0xA0, b: 0xA6, a: 0xFF)
            ),
        ]

        // Semantic token colors (Rust Analyzer / LSP).
        let baseTokenColors: [(String, EcuRgba8)] = [
            ("keyword", EcuRgba8(r: 0xC5, g: 0x86, b: 0xC0, a: 0xFF)),
            ("comment", EcuRgba8(r: 0x6A, g: 0x99, b: 0x55, a: 0xFF)),
            ("string", EcuRgba8(r: 0xCE, g: 0x91, b: 0x78, a: 0xFF)),
            ("number", EcuRgba8(r: 0xB5, g: 0xCE, b: 0xA8, a: 0xFF)),
            ("type", EcuRgba8(r: 0x4E, g: 0xC9, b: 0xB0, a: 0xFF)),
            ("struct", EcuRgba8(r: 0x4E, g: 0xC9, b: 0xB0, a: 0xFF)),
            ("enum", EcuRgba8(r: 0x4E, g: 0xC9, b: 0xB0, a: 0xFF)),
            ("interface", EcuRgba8(r: 0x4E, g: 0xC9, b: 0xB0, a: 0xFF)),
            ("function", EcuRgba8(r: 0xDC, g: 0xDC, b: 0xAA, a: 0xFF)),
            ("method", EcuRgba8(r: 0xDC, g: 0xDC, b: 0xAA, a: 0xFF)),
            ("macro", EcuRgba8(r: 0xC5, g: 0x86, b: 0xC0, a: 0xFF)),
            ("variable", EcuRgba8(r: 0x9C, g: 0xDC, b: 0xFE, a: 0xFF)),
            ("parameter", EcuRgba8(r: 0x9C, g: 0xDC, b: 0xFE, a: 0xFF)),
            ("property", EcuRgba8(r: 0x9C, g: 0xDC, b: 0xFE, a: 0xFF)),
            ("namespace", EcuRgba8(r: 0x4E, g: 0xC9, b: 0xB0, a: 0xFF)),
        ]

        let readonlyBit = EditorCoreSkiaLspSemanticStyleId.modifierBit(named: "readonly")
        let deprecatedBit = EditorCoreSkiaLspSemanticStyleId.modifierBit(named: "deprecated")

        for (token, color) in baseTokenColors {
            guard let baseId = EditorCoreSkiaLspSemanticStyleId.styleId(tokenType: token, modifierBits: 0) else {
                continue
            }
            let bold: Bool? = (token == "keyword" || token == "macro") ? true : nil
            let italic: Bool? = (token == "comment") ? true : nil
            theme.styleOverrides.append(.init(styleId: baseId, foreground: color, bold: bold, italic: italic))

            let combos: [UInt32] = [
                readonlyBit,
                deprecatedBit,
                readonlyBit | deprecatedBit,
            ].filter { $0 != 0 }

            for bits in combos {
                guard let id = EditorCoreSkiaLspSemanticStyleId.styleId(tokenType: token, modifierBits: bits) else {
                    continue
                }
                theme.styleOverrides.append(
                    .init(
                        styleId: id,
                        foreground: color,
                        bold: bold,
                        italic: italic,
                        underline: (bits & readonlyBit) != 0 ? .single : nil,
                        strikethrough: (bits & deprecatedBit) != 0 ? true : nil,
                        strikethroughColor: (bits & deprecatedBit) != 0 ? EcuRgba8(r: 0xF4, g: 0x47, b: 0x47, a: 0xFF) : nil
                    )
                )
            }
        }

        return theme
    }

    public var resolvedMinimapBackground: EcuRgba8 {
        minimapBackground ?? editorBackground.darkened(by: 0.06)
    }

    public var resolvedScrollbarBackground: EcuRgba8 {
        scrollbarBackground ?? resolvedMinimapBackground
    }

    public var resolvedScrollbarForeground: EcuRgba8 {
        if let v = scrollbarForeground { return v }
        // 让 thumb 相对轨道有一点对比度：浅色背景时更暗；深色背景时更亮。
        let base = resolvedScrollbarBackground
        return base.isDark ? base.lightened(by: 0.18) : base.darkened(by: 0.18)
    }

    /// 应用到 Rust/Skia 渲染主题（不包含 minimap/scrollbar 的 AppKit 侧渲染）。
    public func apply(to editor: EditorUI) throws {
        try editor.setTheme(
            EcuTheme(
                background: editorBackground,
                foreground: editorForeground,
                selectionBackground: selectionBackground,
                caret: caret
            )
        )

        // 1) 先写入 UI overlay（gutter / fold markers）的 reserved StyleId。
        var byStyleId: [UInt32: EditorCoreSkiaStyleSpec] = [
            EditorCoreSkiaReservedStyleId.gutterBackground: EditorCoreSkiaStyleSpec(background: gutterBackground),
            EditorCoreSkiaReservedStyleId.gutterForeground: EditorCoreSkiaStyleSpec(foreground: gutterForeground),
            EditorCoreSkiaReservedStyleId.gutterSeparator: EditorCoreSkiaStyleSpec(foreground: gutterSeparator),
            EditorCoreSkiaReservedStyleId.foldMarkerCollapsed: EditorCoreSkiaStyleSpec(background: foldMarkerCollapsed),
            EditorCoreSkiaReservedStyleId.foldMarkerExpanded: EditorCoreSkiaStyleSpec(background: foldMarkerExpanded),
        ]

        // 2) 合并显式的 styleId overrides（后写覆盖先写）。
        for entry in styleOverrides {
            byStyleId[entry.styleId] = entry.spec
        }

        // 3) 合并 Tree-sitter capture overrides（capture -> styleId 在 UI 侧动态映射）。
        //
        // 注意：`treeSitterStyleId(forCapture:)` 即便当前未启用 Tree-sitter，也能返回一个稳定的映射 id；
        // 这让 host 可以“先设置主题，再开启 processor”，依然能得到一致的配色。
        if treeSitterCaptureOverrides.isEmpty == false {
            for entry in treeSitterCaptureOverrides {
                let styleId = try editor.treeSitterStyleId(forCapture: entry.capture)
                byStyleId[styleId] = entry.spec
            }
        }

        let sortedStyleIds = byStyleId.keys.sorted()

        var colors: [EcuStyleColors] = []
        colors.reserveCapacity(sortedStyleIds.count)

        var fonts: [EcuStyleFont] = []
        fonts.reserveCapacity(sortedStyleIds.count)

        var decorations: [EcuStyleTextDecorations] = []
        decorations.reserveCapacity(sortedStyleIds.count)

        for styleId in sortedStyleIds {
            guard let spec = byStyleId[styleId] else { continue }
            if let c = spec.toStyleColors(styleId: styleId) {
                colors.append(c)
            }
            if let f = spec.toStyleFont(styleId: styleId) {
                fonts.append(f)
            }
            if let d = spec.toTextDecorations(styleId: styleId) {
                decorations.append(d)
            }
        }

        try editor.setStyleColors(colors)
        try editor.setStyleFonts(fonts)
        try editor.setStyleTextDecorations(decorations)
    }

    /// 应用到 `EditorCoreSkiaView`（渲染主题 + 触发重绘）。
    @MainActor
    public func apply(to editorView: EditorCoreSkiaView) throws {
        try apply(to: editorView.editor)
        editorView.needsDisplay = true
        editorView.notifyViewportStateDidChange()
    }

    /// 应用到 `EditorCoreSkiaScrollContainer`（渲染主题 + scrollbar 配色）。
    @MainActor
    public func apply(to scrollContainer: EditorCoreSkiaScrollContainer) throws {
        try apply(to: scrollContainer.editorView)
        scrollContainer.setScrollbarColors(
            background: resolvedScrollbarBackground.nsColor,
            foreground: resolvedScrollbarForeground.nsColor
        )
    }

    /// 应用到 `EditorCoreSkiaMinimapContainer`（渲染主题 + scrollbar + minimap）。
    @MainActor
    public func apply(to minimapContainer: EditorCoreSkiaMinimapContainer) throws {
        try apply(to: minimapContainer.scrollContainer)
        minimapContainer.minimapView.backgroundColor = resolvedMinimapBackground.nsColor
        minimapContainer.minimapView.needsDisplay = true
    }
}

// MARK: - Style specs

/// 主题里一条“样式规格”（颜色 + 视觉装饰），可被绑定到某个 `StyleId` 或 Tree-sitter capture。
@frozen
public struct EditorCoreSkiaStyleSpec: Equatable {
    public var foreground: EcuRgba8?
    public var background: EcuRgba8?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: EcuUnderlineStyle?
    public var underlineColor: EcuRgba8?
    public var strikethrough: Bool?
    public var strikethroughColor: EcuRgba8?

    public init(
        foreground: EcuRgba8? = nil,
        background: EcuRgba8? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: EcuUnderlineStyle? = nil,
        underlineColor: EcuRgba8? = nil,
        strikethrough: Bool? = nil,
        strikethroughColor: EcuRgba8? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.underlineColor = underlineColor
        self.strikethrough = strikethrough
        self.strikethroughColor = strikethroughColor
    }

    fileprivate func toStyleColors(styleId: UInt32) -> EcuStyleColors? {
        guard foreground != nil || background != nil else { return nil }
        return EcuStyleColors(styleId: styleId, foreground: foreground, background: background)
    }

    fileprivate func toStyleFont(styleId: UInt32) -> EcuStyleFont? {
        guard bold != nil || italic != nil else { return nil }
        return EcuStyleFont(styleId: styleId, bold: bold, italic: italic)
    }

    fileprivate func toTextDecorations(styleId: UInt32) -> EcuStyleTextDecorations? {
        guard underline != nil || underlineColor != nil || strikethrough != nil || strikethroughColor != nil else {
            return nil
        }
        return EcuStyleTextDecorations(
            styleId: styleId,
            underline: underline,
            underlineColor: underlineColor,
            strikethrough: strikethrough,
            strikethroughColor: strikethroughColor
        )
    }
}

/// 绑定到显式 `StyleId` 的主题覆盖项。
@frozen
public struct EditorCoreSkiaStyleOverride: Equatable {
    public var styleId: UInt32
    public var spec: EditorCoreSkiaStyleSpec

    public init(styleId: UInt32, spec: EditorCoreSkiaStyleSpec) {
        self.styleId = styleId
        self.spec = spec
    }

    public init(
        styleId: UInt32,
        foreground: EcuRgba8? = nil,
        background: EcuRgba8? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: EcuUnderlineStyle? = nil,
        underlineColor: EcuRgba8? = nil,
        strikethrough: Bool? = nil,
        strikethroughColor: EcuRgba8? = nil
    ) {
        self.styleId = styleId
        self.spec = EditorCoreSkiaStyleSpec(
            foreground: foreground,
            background: background,
            bold: bold,
            italic: italic,
            underline: underline,
            underlineColor: underlineColor,
            strikethrough: strikethrough,
            strikethroughColor: strikethroughColor
        )
    }
}

/// 绑定到 Tree-sitter capture name 的主题覆盖项（在 apply 时映射到 `StyleId`）。
@frozen
public struct EditorCoreSkiaTreeSitterCaptureOverride: Equatable {
    public var capture: String
    public var spec: EditorCoreSkiaStyleSpec

    public init(capture: String, spec: EditorCoreSkiaStyleSpec) {
        self.capture = capture
        self.spec = spec
    }

    public init(
        capture: String,
        foreground: EcuRgba8? = nil,
        background: EcuRgba8? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: EcuUnderlineStyle? = nil,
        underlineColor: EcuRgba8? = nil,
        strikethrough: Bool? = nil,
        strikethroughColor: EcuRgba8? = nil
    ) {
        self.capture = capture
        self.spec = EditorCoreSkiaStyleSpec(
            foreground: foreground,
            background: background,
            bold: bold,
            italic: italic,
            underline: underline,
            underlineColor: underlineColor,
            strikethrough: strikethrough,
            strikethroughColor: strikethroughColor
        )
    }
}

// MARK: - Reserved StyleIds

/// `editor-core-render-skia` 里保留的 UI overlay StyleId（gutter / fold markers）。
public enum EditorCoreSkiaReservedStyleId {
    public static let uiOverlayBase: UInt32 = 0x0600_0000
    public static let gutterBackground: UInt32 = uiOverlayBase | 1
    public static let gutterForeground: UInt32 = uiOverlayBase | 2
    public static let gutterSeparator: UInt32 = uiOverlayBase | 3
    public static let foldMarkerCollapsed: UInt32 = uiOverlayBase | 4
    public static let foldMarkerExpanded: UInt32 = uiOverlayBase | 5
    public static let indentGuide: UInt32 = uiOverlayBase | 6
    public static let whitespace: UInt32 = uiOverlayBase | 7
}

/// `editor-core` 内建（跨 renderer/host 的）StyleId 常量（用于 demo / 主题覆盖）。
public enum EditorCoreSkiaBuiltinStyleId {
    public static let foldPlaceholder: UInt32 = 0x0300_0001
    public static let imeMarkedText: UInt32 = 0x0700_0001
    public static let inlayHint: UInt32 = 0x0800_0001
    public static let codeLens: UInt32 = 0x0800_0002
    public static let documentLink: UInt32 = 0x0800_0003
    public static let matchHighlight: UInt32 = 0x0800_0004

    /// LSP diagnostics style id encoding: `0x0400_0100 | severity(1..=4)`.
    public static func lspDiagnostic(severity: UInt32) -> UInt32 {
        0x0400_0100 | (severity & 0xFF)
    }
}

/// Helper for computing semantic-token `StyleId`s used by `editor-core-lsp` default encoding.
public enum EditorCoreSkiaLspSemanticStyleId {
    // Keep this list in sync with Rust `EditorUi::lsp_enable_stdio`.
    public static let tokenTypes: [String] = [
        "namespace",
        "type",
        "class",
        "enum",
        "interface",
        "struct",
        "typeParameter",
        "parameter",
        "variable",
        "property",
        "enumMember",
        "event",
        "function",
        "method",
        "macro",
        "keyword",
        "modifier",
        "comment",
        "string",
        "number",
        "regexp",
        "operator",
    ]

    public static let tokenModifiers: [String] = [
        "declaration",
        "definition",
        "readonly",
        "static",
        "deprecated",
        "abstract",
        "async",
        "modification",
        "documentation",
        "defaultLibrary",
    ]

    public static func modifierBit(named name: String) -> UInt32 {
        guard let idx = tokenModifiers.firstIndex(of: name) else { return 0 }
        if idx >= 32 { return 0 }
        return 1 << UInt32(idx)
    }

    public static func styleId(tokenType: String, modifierBits: UInt32) -> UInt32? {
        guard let idx = tokenTypes.firstIndex(of: tokenType) else { return nil }
        return (UInt32(idx) << 16) | (modifierBits & 0xFFFF)
    }
}

// MARK: - Color helpers

private extension EcuRgba8 {
    var nsColor: NSColor {
        NSColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }

    // W3C relative luminance (approx).
    var luminance: Double {
        func srgbToLinear(_ v: UInt8) -> Double {
            let x = Double(v) / 255.0
            if x <= 0.04045 { return x / 12.92 }
            return pow((x + 0.055) / 1.055, 2.4)
        }
        let rLin = srgbToLinear(r)
        let gLin = srgbToLinear(g)
        let bLin = srgbToLinear(b)
        return 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
    }

    var isDark: Bool { luminance < 0.45 }

    func darkened(by amount: Double) -> EcuRgba8 {
        let a = amount.clamped(to: 0.0...1.0)
        func f(_ v: UInt8) -> UInt8 {
            let out = Double(v) * (1.0 - a)
            return UInt8(out.rounded(.toNearestOrAwayFromZero).clamped(to: 0.0...255.0))
        }
        return EcuRgba8(r: f(r), g: f(g), b: f(b), a: self.a)
    }

    func lightened(by amount: Double) -> EcuRgba8 {
        let a = amount.clamped(to: 0.0...1.0)
        func f(_ v: UInt8) -> UInt8 {
            let out = Double(v) + (255.0 - Double(v)) * a
            return UInt8(out.rounded(.toNearestOrAwayFromZero).clamped(to: 0.0...255.0))
        }
        return EcuRgba8(r: f(r), g: f(g), b: f(b), a: self.a)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
