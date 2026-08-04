import CEditorCoreUIFFI
import Foundation

public enum EcuStatus: Int32, CustomStringConvertible, Sendable {
    case ok = 0
    case invalidArgument = 1
    case invalidUtf8 = 2
    case notFound = 3
    case bufferTooSmall = 4
    case parse = 5
    case commandFailed = 6
    case `internal` = 7
    case unsupported = 8
    case versionMismatch = 9

    public var abiLabel: String {
        switch self {
        case .ok:
            return "ok"
        case .invalidArgument:
            return "invalid_argument"
        case .invalidUtf8:
            return "invalid_utf8"
        case .notFound:
            return "not_found"
        case .bufferTooSmall:
            return "buffer_too_small"
        case .parse:
            return "parse"
        case .commandFailed:
            return "command_failed"
        case .internal:
            return "internal"
        case .unsupported:
            return "unsupported"
        case .versionMismatch:
            return "version_mismatch"
        }
    }

    public var description: String {
        switch self {
        case .ok:
            return "ECU_OK"
        case .invalidArgument:
            return "ECU_ERR_INVALID_ARGUMENT"
        case .invalidUtf8:
            return "ECU_ERR_INVALID_UTF8"
        case .notFound:
            return "ECU_ERR_NOT_FOUND"
        case .bufferTooSmall:
            return "ECU_ERR_BUFFER_TOO_SMALL"
        case .parse:
            return "ECU_ERR_PARSE"
        case .commandFailed:
            return "ECU_ERR_COMMAND_FAILED"
        case .internal:
            return "ECU_ERR_INTERNAL"
        case .unsupported:
            return "ECU_ERR_UNSUPPORTED"
        case .versionMismatch:
            return "ECU_ERR_VERSION_MISMATCH"
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

public indirect enum EcuJSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([EcuJSONValue])
    case object([String: EcuJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([EcuJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: EcuJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

public struct EcuJSONCommandEnvelope: Equatable, Sendable, Decodable {
    public var ok: Bool
    public var value: EcuJSONValue?
    public var error: EcuJSONCommandError?
    public var version: UInt32

    public init(ok: Bool, value: EcuJSONValue?, error: EcuJSONCommandError?, version: UInt32) {
        self.ok = ok
        self.value = value
        self.error = error
        self.version = version
    }
}

public struct EcuJSONCommandError: Equatable, Sendable, Decodable {
    public var code: String
    public var status: EcuStatus?
    public var message: String

    public init(code: String, status: EcuStatus?, message: String) {
        self.code = code
        self.status = status
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case status
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        if let rawStatus = try container.decodeIfPresent(Int32.self, forKey: .status) {
            status = EcuStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

public struct EcuLspResultEnvelope: Equatable, Sendable, Decodable {
    public var ok: Bool
    public var slot: String?
    public var status: String
    public var hasResult: Bool
    public var value: EcuJSONValue?
    public var error: EcuLspResultEnvelopeError?
    public var version: UInt32

    public init(
        ok: Bool,
        slot: String?,
        status: String,
        hasResult: Bool,
        value: EcuJSONValue?,
        error: EcuLspResultEnvelopeError?,
        version: UInt32
    ) {
        self.ok = ok
        self.slot = slot
        self.status = status
        self.hasResult = hasResult
        self.value = value
        self.error = error
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case slot
        case status
        case hasResult
        case hasResultSnake = "has_result"
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        slot = try container.decodeIfPresent(String.self, forKey: .slot)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        hasResult = try container.decodeIfPresent(Bool.self, forKey: .hasResultSnake)
            ?? container.decodeIfPresent(Bool.self, forKey: .hasResult)
            ?? false
        if container.contains(.value) {
            value = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            value = nil
        }
        error = try container.decodeIfPresent(EcuLspResultEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuLspResultEnvelopeError: Equatable, Sendable, Decodable {
    public var code: String
    public var status: EcuStatus?
    public var message: String

    public init(code: String, status: EcuStatus?, message: String) {
        self.code = code
        self.status = status
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case status
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        if let rawStatus = try container.decodeIfPresent(Int32.self, forKey: .status) {
            status = EcuStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

public struct EcuJSONEventStreamEnvelope: Equatable, Sendable, Decodable {
    public var ok: Bool
    public var owner: String
    public var stream: String?
    public var status: String
    public var afterSequence: UInt64
    public var value: EcuJSONValue?
    public var error: EcuJSONEventStreamEnvelopeError?
    public var version: UInt32

    public init(
        ok: Bool,
        owner: String,
        stream: String?,
        status: String,
        afterSequence: UInt64,
        value: EcuJSONValue?,
        error: EcuJSONEventStreamEnvelopeError?,
        version: UInt32
    ) {
        self.ok = ok
        self.owner = owner
        self.stream = stream
        self.status = status
        self.afterSequence = afterSequence
        self.value = value
        self.error = error
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case owner
        case stream
        case status
        case afterSequence
        case afterSequenceSnake = "after_sequence"
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? "unknown"
        stream = try container.decodeIfPresent(String.self, forKey: .stream)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        afterSequence = try container.decodeIfPresent(UInt64.self, forKey: .afterSequenceSnake)
            ?? container.decodeIfPresent(UInt64.self, forKey: .afterSequence)
            ?? 0
        if container.contains(.value) {
            value = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            value = nil
        }
        error = try container.decodeIfPresent(EcuJSONEventStreamEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuJSONEventStreamEnvelopeError: Equatable, Sendable, Decodable {
    public var code: String
    public var status: EcuStatus?
    public var message: String

    public init(code: String, status: EcuStatus?, message: String) {
        self.code = code
        self.status = status
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case status
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        if let rawStatus = try container.decodeIfPresent(Int32.self, forKey: .status) {
            status = EcuStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

public enum EcuLspAvailability: Equatable, Sendable, Decodable {
    case disabled
    case enabled
    case failed
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        case .failed: return "failed"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "disabled": self = .disabled
        case "enabled": self = .enabled
        case "failed": self = .failed
        default: self = .unknown(value)
        }
    }
}

public enum EcuLspWorkState: Equatable, Sendable, Decodable {
    case disabled
    case ready
    case indexing
    case busy
    case failed
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .disabled: return "disabled"
        case .ready: return "ready"
        case .indexing: return "indexing"
        case .busy: return "busy"
        case .failed: return "failed"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "disabled": self = .disabled
        case "ready": self = .ready
        case "indexing": self = .indexing
        case "busy": self = .busy
        case "failed": self = .failed
        default: self = .unknown(value)
        }
    }
}

@frozen
public struct EcuLspWorkspaceFolder: Equatable, Sendable, Codable {
    public var uri: String
    public var name: String

    public init(uri: String, name: String) {
        self.uri = uri
        self.name = name
    }
}

@frozen
public struct EcuLspServerStatus: Equatable, Sendable, Decodable {
    public var name: String?
    public var version: String?
    public var command: String?
    public var args: [String]

    public init(name: String?, version: String?, command: String?, args: [String] = []) {
        self.name = name
        self.version = version
        self.command = command
        self.args = args
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case version
        case command
        case args
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.version = try container.decodeIfPresent(String.self, forKey: .version)
        self.command = try container.decodeIfPresent(String.self, forKey: .command)
        self.args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
    }
}

@frozen
public struct EcuLspActivity: Equatable, Sendable, Decodable {
    public var title: String?
    public var message: String?
    public var percentage: Double?

    public init(title: String?, message: String?, percentage: Double?) {
        self.title = title
        self.message = message
        self.percentage = percentage
    }
}

public enum EcuLspProcessState: Equatable, Sendable, Decodable {
    case running
    case exited
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .running:
            "running"
        case .exited:
            "exited"
        case .unknown(let value):
            value
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "running":
            self = .running
        case "exited":
            self = .exited
        default:
            self = .unknown(raw)
        }
    }
}

@frozen
public struct EcuLspProcessStatus: Equatable, Sendable, Decodable {
    public var pid: UInt32?
    public var state: EcuLspProcessState
    public var exitCode: Int32?
    public var signal: Int32?
    public var stderrTail: String?

    public init(
        pid: UInt32? = nil,
        state: EcuLspProcessState,
        exitCode: Int32? = nil,
        signal: Int32? = nil,
        stderrTail: String? = nil
    ) {
        self.pid = pid
        self.state = state
        self.exitCode = exitCode
        self.signal = signal
        self.stderrTail = stderrTail
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case state
        case exitCode = "exit_code"
        case signal
        case stderrTail = "stderr_tail"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pid = try container.decodeIfPresent(UInt32.self, forKey: .pid)
        self.state = try container.decodeIfPresent(EcuLspProcessState.self, forKey: .state) ?? .unknown("unknown")
        self.exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        self.signal = try container.decodeIfPresent(Int32.self, forKey: .signal)
        self.stderrTail = try container.decodeIfPresent(String.self, forKey: .stderrTail)
    }
}

@frozen
public struct EcuLspCompletionCapability: Equatable, Sendable, Decodable {
    public var supported: Bool
    public var triggerCharacters: [String]
    public var allCommitCharacters: [String]

    public init(supported: Bool, triggerCharacters: [String] = [], allCommitCharacters: [String] = []) {
        self.supported = supported
        self.triggerCharacters = triggerCharacters
        self.allCommitCharacters = allCommitCharacters
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case triggerCharacters = "trigger_characters"
        case allCommitCharacters = "all_commit_characters"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.supported = try container.decodeIfPresent(Bool.self, forKey: .supported) ?? false
        self.triggerCharacters = try container.decodeIfPresent([String].self, forKey: .triggerCharacters) ?? []
        self.allCommitCharacters = try container.decodeIfPresent([String].self, forKey: .allCommitCharacters) ?? []
    }
}

@frozen
public struct EcuLspSignatureHelpCapability: Equatable, Sendable, Decodable {
    public var supported: Bool
    public var triggerCharacters: [String]
    public var retriggerCharacters: [String]

    public init(supported: Bool, triggerCharacters: [String] = [], retriggerCharacters: [String] = []) {
        self.supported = supported
        self.triggerCharacters = triggerCharacters
        self.retriggerCharacters = retriggerCharacters
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case triggerCharacters = "trigger_characters"
        case retriggerCharacters = "retrigger_characters"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.supported = try container.decodeIfPresent(Bool.self, forKey: .supported) ?? false
        self.triggerCharacters = try container.decodeIfPresent([String].self, forKey: .triggerCharacters) ?? []
        self.retriggerCharacters = try container.decodeIfPresent([String].self, forKey: .retriggerCharacters) ?? []
    }
}

@frozen
public struct EcuLspCapabilities: Equatable, Sendable, Decodable {
    public var semanticTokens: Bool
    public var semanticTokensDelta: Bool
    public var completionItemResolve: Bool
    public var completion: EcuLspCompletionCapability
    public var foldingRanges: Bool
    public var onTypeFormatting: Bool
    public var signatureHelp: EcuLspSignatureHelpCapability

    public init(
        semanticTokens: Bool = false,
        semanticTokensDelta: Bool = false,
        completionItemResolve: Bool = false,
        completion: EcuLspCompletionCapability = .init(supported: false),
        foldingRanges: Bool = false,
        onTypeFormatting: Bool = false,
        signatureHelp: EcuLspSignatureHelpCapability = .init(supported: false)
    ) {
        self.semanticTokens = semanticTokens
        self.semanticTokensDelta = semanticTokensDelta
        self.completionItemResolve = completionItemResolve
        self.completion = completion
        self.foldingRanges = foldingRanges
        self.onTypeFormatting = onTypeFormatting
        self.signatureHelp = signatureHelp
    }

    private enum CodingKeys: String, CodingKey {
        case semanticTokens = "semantic_tokens"
        case semanticTokensDelta = "semantic_tokens_delta"
        case completionItemResolve = "completion_item_resolve"
        case completion
        case foldingRanges = "folding_ranges"
        case onTypeFormatting = "on_type_formatting"
        case signatureHelp = "signature_help"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.semanticTokens = try container.decodeIfPresent(Bool.self, forKey: .semanticTokens) ?? false
        self.semanticTokensDelta = try container.decodeIfPresent(Bool.self, forKey: .semanticTokensDelta) ?? false
        self.completionItemResolve = try container.decodeIfPresent(Bool.self, forKey: .completionItemResolve) ?? false
        self.completion = try container.decodeIfPresent(EcuLspCompletionCapability.self, forKey: .completion) ?? .init(supported: false)
        self.foldingRanges = try container.decodeIfPresent(Bool.self, forKey: .foldingRanges) ?? false
        self.onTypeFormatting = try container.decodeIfPresent(Bool.self, forKey: .onTypeFormatting) ?? false
        self.signatureHelp = try container.decodeIfPresent(EcuLspSignatureHelpCapability.self, forKey: .signatureHelp) ?? .init(supported: false)
    }
}

@frozen
public struct EcuLspStatusSnapshot: Equatable, Sendable, Decodable {
    public var availability: EcuLspAvailability
    public var state: EcuLspWorkState
    public var server: EcuLspServerStatus?
    public var activity: EcuLspActivity?
    public var detail: String?
    public var capabilities: EcuLspCapabilities?
    public var process: EcuLspProcessStatus?
    public var workspaceFolders: [EcuLspWorkspaceFolder]

    public init(
        availability: EcuLspAvailability,
        state: EcuLspWorkState,
        server: EcuLspServerStatus?,
        activity: EcuLspActivity?,
        detail: String?,
        capabilities: EcuLspCapabilities?,
        process: EcuLspProcessStatus? = nil,
        workspaceFolders: [EcuLspWorkspaceFolder] = []
    ) {
        self.availability = availability
        self.state = state
        self.server = server
        self.activity = activity
        self.detail = detail
        self.capabilities = capabilities
        self.process = process
        self.workspaceFolders = workspaceFolders
    }

    private enum CodingKeys: String, CodingKey {
        case availability
        case state
        case server
        case activity
        case detail
        case capabilities
        case process
        case workspaceFolders = "workspace_folders"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.availability = try container.decodeIfPresent(EcuLspAvailability.self, forKey: .availability) ?? .disabled
        self.state = try container.decodeIfPresent(EcuLspWorkState.self, forKey: .state) ?? .disabled
        self.server = try container.decodeIfPresent(EcuLspServerStatus.self, forKey: .server)
        self.activity = try container.decodeIfPresent(EcuLspActivity.self, forKey: .activity)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.capabilities = try container.decodeIfPresent(EcuLspCapabilities.self, forKey: .capabilities)
        self.process = try container.decodeIfPresent(EcuLspProcessStatus.self, forKey: .process)
        self.workspaceFolders = try container.decodeIfPresent([EcuLspWorkspaceFolder].self, forKey: .workspaceFolders) ?? []
    }
}

@frozen
public struct EcuOffsetRange: Equatable, Sendable, Decodable {
    public var start: UInt32
    public var end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }
}

public enum EcuDiagnosticSeverity: String, Equatable, Sendable, Decodable {
    case error
    case warning
    case information
    case hint
}

@frozen
public struct EcuDiagnostic: Equatable, Sendable, Decodable {
    public var range: EcuOffsetRange
    public var severity: EcuDiagnosticSeverity?
    public var code: String?
    public var source: String?
    public var message: String
    public var relatedInformationJSON: String?
    public var dataJSON: String?

    public init(
        range: EcuOffsetRange,
        severity: EcuDiagnosticSeverity?,
        code: String?,
        source: String?,
        message: String,
        relatedInformationJSON: String?,
        dataJSON: String?
    ) {
        self.range = range
        self.severity = severity
        self.code = code
        self.source = source
        self.message = message
        self.relatedInformationJSON = relatedInformationJSON
        self.dataJSON = dataJSON
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case severity
        case code
        case source
        case message
        case relatedInformationJSON = "related_information_json"
        case dataJSON = "data_json"
    }
}

@frozen
public struct EcuDiagnosticsSnapshot: Equatable, Sendable, Decodable {
    public var diagnostics: [EcuDiagnostic]

    public init(diagnostics: [EcuDiagnostic]) {
        self.diagnostics = diagnostics
    }
}

public enum EcuDecorationPlacement: String, Equatable, Sendable, Decodable {
    case before
    case after
    case aboveLine = "above_line"
}

@frozen
public struct EcuDecoration: Equatable, Sendable, Decodable {
    public var range: EcuOffsetRange
    public var placement: EcuDecorationPlacement
    public var kind: EcuJSONValue
    public var text: String?
    public var styles: [UInt32]
    public var tooltip: String?
    public var dataJSON: String?

    public init(
        range: EcuOffsetRange,
        placement: EcuDecorationPlacement,
        kind: EcuJSONValue,
        text: String?,
        styles: [UInt32],
        tooltip: String?,
        dataJSON: String?
    ) {
        self.range = range
        self.placement = placement
        self.kind = kind
        self.text = text
        self.styles = styles
        self.tooltip = tooltip
        self.dataJSON = dataJSON
    }

    private enum CodingKeys: String, CodingKey {
        case range
        case placement
        case kind
        case text
        case styles
        case tooltip
        case dataJSON = "data_json"
    }
}

@frozen
public struct EcuDecorationLayerSnapshot: Equatable, Sendable, Decodable {
    public var layer: UInt32
    public var decorations: [EcuDecoration]

    public init(layer: UInt32, decorations: [EcuDecoration]) {
        self.layer = layer
        self.decorations = decorations
    }
}

@frozen
public struct EcuDecorationsSnapshot: Equatable, Sendable, Decodable {
    public var layers: [EcuDecorationLayerSnapshot]

    public init(layers: [EcuDecorationLayerSnapshot]) {
        self.layers = layers
    }
}

@frozen
public struct EcuDocumentSymbol: Equatable, Sendable, Decodable {
    public var name: String
    public var detail: String?
    public var kind: EcuJSONValue
    public var range: EcuOffsetRange
    public var selectionRange: EcuOffsetRange
    public var children: [EcuDocumentSymbol]
    public var dataJSON: String?

    public init(
        name: String,
        detail: String?,
        kind: EcuJSONValue,
        range: EcuOffsetRange,
        selectionRange: EcuOffsetRange,
        children: [EcuDocumentSymbol],
        dataJSON: String?
    ) {
        self.name = name
        self.detail = detail
        self.kind = kind
        self.range = range
        self.selectionRange = selectionRange
        self.children = children
        self.dataJSON = dataJSON
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case detail
        case kind
        case range
        case selectionRange = "selection_range"
        case children
        case dataJSON = "data_json"
    }
}

@frozen
public struct EcuDocumentSymbolsSnapshot: Equatable, Sendable, Decodable {
    public var symbols: [EcuDocumentSymbol]

    public init(symbols: [EcuDocumentSymbol]) {
        self.symbols = symbols
    }
}

@frozen
public struct EcuWorkspaceOutlineDocument: Equatable, Sendable, Decodable {
    public var tabId: UInt64
    public var viewIndex: UInt32
    public var documentURI: String?
    public var title: String?
    public var symbolCount: UInt32
    public var symbols: [EcuDocumentSymbol]

    public init(
        tabId: UInt64,
        viewIndex: UInt32,
        documentURI: String?,
        title: String?,
        symbolCount: UInt32,
        symbols: [EcuDocumentSymbol]
    ) {
        self.tabId = tabId
        self.viewIndex = viewIndex
        self.documentURI = documentURI
        self.title = title
        self.symbolCount = symbolCount
        self.symbols = symbols
    }

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case viewIndex = "view_index"
        case documentURI = "document_uri"
        case title
        case symbolCount = "symbol_count"
        case symbols
    }
}

@frozen
public struct EcuWorkspaceOutlineSnapshot: Equatable, Sendable, Decodable {
    public var documents: [EcuWorkspaceOutlineDocument]

    public init(documents: [EcuWorkspaceOutlineDocument]) {
        self.documents = documents
    }
}

public enum EcuWorkspaceOutlineSnapshotEnvelopeStatus: Hashable, Sendable {
    case success
    case error
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "success":
            self = .success
        case "error":
            self = .error
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .success:
            return "success"
        case .error:
            return "error"
        case let .unknown(rawValue):
            return rawValue
        }
    }
}

public struct EcuWorkspaceOutlineSnapshotEnvelope: Equatable, Sendable, Decodable {
    public var ok: Bool
    public var status: String
    public var value: EcuJSONValue?
    public var error: EcuWorkspaceOutlineSnapshotEnvelopeError?
    public var version: UInt32

    public var statusKind: EcuWorkspaceOutlineSnapshotEnvelopeStatus {
        EcuWorkspaceOutlineSnapshotEnvelopeStatus(rawValue: status)
    }

    public init(
        ok: Bool,
        status: String,
        value: EcuJSONValue?,
        error: EcuWorkspaceOutlineSnapshotEnvelopeError?,
        version: UInt32
    ) {
        self.ok = ok
        self.status = status
        self.value = value
        self.error = error
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case status
        case value
        case error
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        if container.contains(.value) {
            value = try container.decode(EcuJSONValue.self, forKey: .value)
        } else {
            value = nil
        }
        error = try container.decodeIfPresent(EcuWorkspaceOutlineSnapshotEnvelopeError.self, forKey: .error)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
    }
}

public struct EcuWorkspaceOutlineSnapshotEnvelopeError: Equatable, Sendable, Decodable {
    public var code: String
    public var status: EcuStatus?
    public var message: String

    public init(code: String, status: EcuStatus?, message: String) {
        self.code = code
        self.status = status
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case status
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        if let rawStatus = try container.decodeIfPresent(Int32.self, forKey: .status) {
            status = EcuStatus(rawValue: rawStatus)
        } else {
            status = nil
        }
    }
}

@frozen
public struct EcuFoldingRegion: Equatable, Sendable, Decodable {
    public var startLine: UInt32
    public var endLine: UInt32
    public var isCollapsed: Bool
    public var placeholder: String?

    public init(startLine: UInt32, endLine: UInt32, isCollapsed: Bool, placeholder: String?) {
        self.startLine = startLine
        self.endLine = endLine
        self.isCollapsed = isCollapsed
        self.placeholder = placeholder
    }

    private enum CodingKeys: String, CodingKey {
        case startLine = "start_line"
        case endLine = "end_line"
        case isCollapsed = "is_collapsed"
        case placeholder
    }
}

@frozen
public struct EcuFoldingRegionsSnapshot: Equatable, Sendable, Decodable {
    public var regions: [EcuFoldingRegion]

    public init(regions: [EcuFoldingRegion]) {
        self.regions = regions
    }
}

@frozen
public struct EcuStyleInterval: Equatable, Sendable, Decodable {
    public var start: UInt32
    public var end: UInt32
    public var styleId: UInt32

    public init(start: UInt32, end: UInt32, styleId: UInt32) {
        self.start = start
        self.end = end
        self.styleId = styleId
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case styleId = "style_id"
    }
}

@frozen
public struct EcuStyleIntervalLayerSnapshot: Equatable, Sendable, Decodable {
    public var layer: UInt32
    public var intervals: [EcuStyleInterval]

    public init(layer: UInt32, intervals: [EcuStyleInterval]) {
        self.layer = layer
        self.intervals = intervals
    }
}

@frozen
public struct EcuStyleIntervalsSnapshot: Equatable, Sendable, Decodable {
    public var layers: [EcuStyleIntervalLayerSnapshot]

    public init(layers: [EcuStyleIntervalLayerSnapshot]) {
        self.layers = layers
    }
}

// 注意：
// - C 侧的 `EcuRgba8/EcuTheme/EcuStyleColors/EcuSelectionRange/EcuViewportState` 由 `CEditorCoreUIFFI`
//   模块提供；Swift 侧仅做更易用的 wrapper（camelCase + Optional）。
