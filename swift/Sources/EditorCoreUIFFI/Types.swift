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

// 注意：
// - C 侧的 `EcuRgba8/EcuTheme/EcuStyleColors/EcuSelectionRange/EcuViewportState` 由 `CEditorCoreUIFFI`
//   模块提供；Swift 侧仅做更易用的 wrapper（camelCase + Optional）。
