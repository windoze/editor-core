import CEditorCoreUIFFI
import Foundation

public enum EcuStatus: Int32, CustomStringConvertible, Sendable {
    case ok = 0
    case invalidArgument = 1
    case bufferTooSmall = 4
    case `internal` = 7

    public var description: String {
        switch self {
        case .ok: return "ok"
        case .invalidArgument: return "invalidArgument"
        case .bufferTooSmall: return "bufferTooSmall"
        case .internal: return "internal"
        }
    }
}

@frozen
public struct EcuRgba8: Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

@frozen
public struct EcuTheme: Equatable {
    public var background: EcuRgba8
    public var foreground: EcuRgba8
    public var selectionBackground: EcuRgba8
    public var caret: EcuRgba8

    public init(background: EcuRgba8, foreground: EcuRgba8, selectionBackground: EcuRgba8, caret: EcuRgba8) {
        self.background = background
        self.foreground = foreground
        self.selectionBackground = selectionBackground
        self.caret = caret
    }

    var ffi: CEditorCoreUIFFI.EcuTheme {
        CEditorCoreUIFFI.EcuTheme(
            background: CEditorCoreUIFFI.EcuRgba8(r: background.r, g: background.g, b: background.b, a: background.a),
            foreground: CEditorCoreUIFFI.EcuRgba8(r: foreground.r, g: foreground.g, b: foreground.b, a: foreground.a),
            selection_background: CEditorCoreUIFFI.EcuRgba8(r: selectionBackground.r, g: selectionBackground.g, b: selectionBackground.b, a: selectionBackground.a),
            caret: CEditorCoreUIFFI.EcuRgba8(r: caret.r, g: caret.g, b: caret.b, a: caret.a)
        )
    }
}

@frozen
public struct EcuStyleColors: Equatable {
    public var styleId: UInt32
    public var foreground: EcuRgba8?
    public var background: EcuRgba8?

    public init(styleId: UInt32, foreground: EcuRgba8? = nil, background: EcuRgba8? = nil) {
        self.styleId = styleId
        self.foreground = foreground
        self.background = background
    }

    var ffi: CEditorCoreUIFFI.EcuStyleColors {
        var flags: UInt32 = 0
        if foreground != nil { flags |= 1 << 0 }
        if background != nil { flags |= 1 << 1 }

        let fg = foreground ?? EcuRgba8(r: 0, g: 0, b: 0, a: 0)
        let bg = background ?? EcuRgba8(r: 0, g: 0, b: 0, a: 0)
        return CEditorCoreUIFFI.EcuStyleColors(
            style_id: styleId,
            flags: flags,
            foreground: CEditorCoreUIFFI.EcuRgba8(r: fg.r, g: fg.g, b: fg.b, a: fg.a),
            background: CEditorCoreUIFFI.EcuRgba8(r: bg.r, g: bg.g, b: bg.b, a: bg.a)
        )
    }
}

@frozen
public struct EcuChromeTheme: Equatable {
    public var gutterBackground: EcuRgba8
    public var gutterForeground: EcuRgba8
    public var gutterSeparator: EcuRgba8
    public var foldMarkerCollapsed: EcuRgba8
    public var foldMarkerExpanded: EcuRgba8

    public init(
        gutterBackground: EcuRgba8,
        gutterForeground: EcuRgba8,
        gutterSeparator: EcuRgba8,
        foldMarkerCollapsed: EcuRgba8,
        foldMarkerExpanded: EcuRgba8
    ) {
        self.gutterBackground = gutterBackground
        self.gutterForeground = gutterForeground
        self.gutterSeparator = gutterSeparator
        self.foldMarkerCollapsed = foldMarkerCollapsed
        self.foldMarkerExpanded = foldMarkerExpanded
    }

    var ffi: CEditorCoreUIFFI.EcuChromeTheme {
        CEditorCoreUIFFI.EcuChromeTheme(
            gutter_background: CEditorCoreUIFFI.EcuRgba8(r: gutterBackground.r, g: gutterBackground.g, b: gutterBackground.b, a: gutterBackground.a),
            gutter_foreground: CEditorCoreUIFFI.EcuRgba8(r: gutterForeground.r, g: gutterForeground.g, b: gutterForeground.b, a: gutterForeground.a),
            gutter_separator: CEditorCoreUIFFI.EcuRgba8(r: gutterSeparator.r, g: gutterSeparator.g, b: gutterSeparator.b, a: gutterSeparator.a),
            fold_marker_collapsed: CEditorCoreUIFFI.EcuRgba8(r: foldMarkerCollapsed.r, g: foldMarkerCollapsed.g, b: foldMarkerCollapsed.b, a: foldMarkerCollapsed.a),
            fold_marker_expanded: CEditorCoreUIFFI.EcuRgba8(r: foldMarkerExpanded.r, g: foldMarkerExpanded.g, b: foldMarkerExpanded.b, a: foldMarkerExpanded.a)
        )
    }
}

public enum EcuUnderlineStyle: UInt32, Sendable {
    case single = 1
    case double = 2
    case squiggly = 3
}

@frozen
public struct EcuStyleTextDecorations: Equatable {
    public var styleId: UInt32
    public var underline: EcuUnderlineStyle?
    public var underlineColor: EcuRgba8?
    public var strikethrough: Bool?
    public var strikethroughColor: EcuRgba8?

    public init(
        styleId: UInt32,
        underline: EcuUnderlineStyle? = nil,
        underlineColor: EcuRgba8? = nil,
        strikethrough: Bool? = nil,
        strikethroughColor: EcuRgba8? = nil
    ) {
        self.styleId = styleId
        self.underline = underline
        self.underlineColor = underlineColor
        self.strikethrough = strikethrough
        self.strikethroughColor = strikethroughColor
    }

    var ffi: CEditorCoreUIFFI.EcuStyleTextDecorations {
        var flags: UInt32 = 0
        if underline != nil { flags |= 1 << 0 }
        if underlineColor != nil { flags |= 1 << 1 }
        if strikethrough != nil { flags |= 1 << 2 }
        if strikethroughColor != nil { flags |= 1 << 3 }

        let uStyle = underline?.rawValue ?? 0
        let uColor = underlineColor ?? EcuRgba8(r: 0, g: 0, b: 0, a: 0)
        let sValue: UInt32 = (strikethrough == true) ? 1 : 0
        let sColor = strikethroughColor ?? EcuRgba8(r: 0, g: 0, b: 0, a: 0)

        return CEditorCoreUIFFI.EcuStyleTextDecorations(
            style_id: styleId,
            flags: flags,
            underline_style: uStyle,
            underline_color: CEditorCoreUIFFI.EcuRgba8(r: uColor.r, g: uColor.g, b: uColor.b, a: uColor.a),
            strikethrough: sValue,
            strikethrough_color: CEditorCoreUIFFI.EcuRgba8(r: sColor.r, g: sColor.g, b: sColor.b, a: sColor.a)
        )
    }
}

@frozen
public struct EcuStyleFont: Equatable {
    public var styleId: UInt32
    public var bold: Bool?
    public var italic: Bool?

    public init(styleId: UInt32, bold: Bool? = nil, italic: Bool? = nil) {
        self.styleId = styleId
        self.bold = bold
        self.italic = italic
    }

    var ffi: CEditorCoreUIFFI.EcuStyleFont {
        var flags: UInt32 = 0
        if bold != nil { flags |= 1 << 0 }
        if italic != nil { flags |= 1 << 1 }

        let boldValue: UInt32 = (bold == true) ? 1 : 0
        let italicValue: UInt32 = (italic == true) ? 1 : 0

        return CEditorCoreUIFFI.EcuStyleFont(
            style_id: styleId,
            flags: flags,
            bold: boldValue,
            italic: italicValue
        )
    }
}

@frozen
public struct EcuSelectionRange: Equatable, Sendable {
    public var start: UInt32
    public var end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }

    var ffi: CEditorCoreUIFFI.EcuSelectionRange {
        CEditorCoreUIFFI.EcuSelectionRange(start: start, end: end)
    }
}

@frozen
public struct EcuViewportState: Equatable, Sendable {
    public var widthCells: UInt32
    public var heightRows: UInt32?
    public var scrollTop: UInt32
    public var subRowOffset: UInt32
    public var overscanRows: UInt32
    public var visibleLines: Range<UInt32>
    public var prefetchLines: Range<UInt32>
    public var totalVisualLines: UInt32

    init(ffi: CEditorCoreUIFFI.EcuViewportState) {
        widthCells = ffi.width_cells
        heightRows = ffi.has_height != 0 ? ffi.height_rows : nil
        scrollTop = ffi.scroll_top
        subRowOffset = ffi.sub_row_offset
        overscanRows = ffi.overscan_rows
        visibleLines = ffi.visible_start..<ffi.visible_end
        prefetchLines = ffi.prefetch_start..<ffi.prefetch_end
        totalVisualLines = ffi.total_visual_lines
    }
}

public enum EcuExpandSelectionUnit: UInt32, Sendable {
    case character = 0
    case word = 1
    case line = 2
}

public enum EcuExpandSelectionDirection: UInt32, Sendable {
    case backward = 0
    case forward = 1
}

@frozen
public struct EcuSearchOptions: Equatable, Sendable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var regex: Bool

    public init(caseSensitive: Bool = true, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.regex = regex
    }

    var ffiCaseSensitive: UInt8 { caseSensitive ? 1 : 0 }
    var ffiWholeWord: UInt8 { wholeWord ? 1 : 0 }
    var ffiRegex: UInt8 { regex ? 1 : 0 }
}

public enum EcuWrapMode: String, Equatable, Sendable {
    case none
    case char
    case word
}

public enum EcuWrapIndent: Equatable, Sendable {
    case none
    case sameAsLineIndent
    case fixedCells(UInt32)

    var jsonObject: [String: Any] {
        switch self {
        case .none:
            return ["kind": "none"]
        case .sameAsLineIndent:
            return ["kind": "same_as_line_indent"]
        case let .fixedCells(cells):
            return ["kind": "fixed_cells", "cells": Int(cells)]
        }
    }
}

public enum EcuIndentStyle: Equatable, Sendable {
    case tabs
    case spaces(width: UInt8)

    var jsonObject: [String: Any] {
        switch self {
        case .tabs:
            return ["kind": "tabs"]
        case let .spaces(width):
            return ["kind": "spaces", "width": Int(width)]
        }
    }
}

@frozen
public struct EcuIndentationConfig: Equatable, Sendable {
    public var style: EcuIndentStyle?
    public var indentTriggers: [String]?
    public var outdentTriggers: [String]?

    public init(
        style: EcuIndentStyle? = nil,
        indentTriggers: [String]? = nil,
        outdentTriggers: [String]? = nil
    ) {
        self.style = style
        self.indentTriggers = indentTriggers
        self.outdentTriggers = outdentTriggers
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        if let style {
            object["style"] = style.jsonObject
        }
        if let indentTriggers {
            object["indent_triggers"] = indentTriggers
        }
        if let outdentTriggers {
            object["outdent_triggers"] = outdentTriggers
        }
        return object
    }
}

@frozen
public struct EcuAutoPair: Equatable, Sendable {
    public var open: String
    public var close: String

    public init(open: String, close: String) {
        self.open = open
        self.close = close
    }

    var jsonObject: [String: Any] {
        ["open": open, "close": close]
    }
}

@frozen
public struct EcuAutoPairsConfig: Equatable, Sendable {
    public var enabled: Bool?
    public var pairs: [EcuAutoPair]?
    public var wrapSelection: Bool?
    public var skipOverClosing: Bool?
    public var deletePair: Bool?

    public init(
        enabled: Bool? = nil,
        pairs: [EcuAutoPair]? = nil,
        wrapSelection: Bool? = nil,
        skipOverClosing: Bool? = nil,
        deletePair: Bool? = nil
    ) {
        self.enabled = enabled
        self.pairs = pairs
        self.wrapSelection = wrapSelection
        self.skipOverClosing = skipOverClosing
        self.deletePair = deletePair
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        if let enabled {
            object["enabled"] = enabled
        }
        if let pairs {
            object["pairs"] = pairs.map(\.jsonObject)
        }
        if let wrapSelection {
            object["wrap_selection"] = wrapSelection
        }
        if let skipOverClosing {
            object["skip_over_closing"] = skipOverClosing
        }
        if let deletePair {
            object["delete_pair"] = deletePair
        }
        return object
    }
}

@frozen
public struct EcuCommentConfig: Equatable, Sendable {
    public var line: String?
    public var blockStart: String?
    public var blockEnd: String?

    public init(line: String? = nil, blockStart: String? = nil, blockEnd: String? = nil) {
        self.line = line
        self.blockStart = blockStart
        self.blockEnd = blockEnd
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        if let line {
            object["line"] = line
        }
        if let blockStart {
            object["block_start"] = blockStart
        }
        if let blockEnd {
            object["block_end"] = blockEnd
        }
        return object
    }
}

@frozen
public struct EcuTextEdit: Equatable, Sendable {
    public var start: UInt32
    public var end: UInt32
    public var text: String

    public init(start: UInt32, end: UInt32, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    var jsonObject: [String: Any] {
        ["start": Int(start), "end": Int(end), "text": text]
    }
}

// 注意：
// - C 侧的 `EcuRgba8/EcuTheme/EcuStyleColors/EcuSelectionRange/EcuViewportState` 由 `CEditorCoreUIFFI`
//   模块提供；Swift 侧仅做更易用的 wrapper（camelCase + Optional）。
