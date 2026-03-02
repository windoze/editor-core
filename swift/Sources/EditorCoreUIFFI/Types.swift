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

    // Memory layout must match `EcuTheme` in `editor_core_ui_ffi.h`.
    var ffi: _EcuThemeFFI {
        _EcuThemeFFI(
            background: _EcuRgba8FFI(r: background.r, g: background.g, b: background.b, a: background.a),
            foreground: _EcuRgba8FFI(r: foreground.r, g: foreground.g, b: foreground.b, a: foreground.a),
            selection_background: _EcuRgba8FFI(r: selectionBackground.r, g: selectionBackground.g, b: selectionBackground.b, a: selectionBackground.a),
            caret: _EcuRgba8FFI(r: caret.r, g: caret.g, b: caret.b, a: caret.a)
        )
    }
}

struct _EcuRgba8FFI {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

struct _EcuThemeFFI {
    var background: _EcuRgba8FFI
    var foreground: _EcuRgba8FFI
    var selection_background: _EcuRgba8FFI
    var caret: _EcuRgba8FFI
}
