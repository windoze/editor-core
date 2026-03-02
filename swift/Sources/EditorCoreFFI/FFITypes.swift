import Foundation

struct EcfDocumentStatsRaw {
    var abi_version: UInt32
    var struct_size: UInt32
    var line_count: UInt64
    var char_count: UInt64
    var byte_count: UInt64
    var is_modified: UInt8
    var reserved0: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    var version: UInt64

    init() {
        self.abi_version = 0
        self.struct_size = 0
        self.line_count = 0
        self.char_count = 0
        self.byte_count = 0
        self.is_modified = 0
        self.reserved0 = (0, 0, 0, 0, 0, 0, 0)
        self.version = 0
    }
}

public struct DocumentStats: Equatable, Sendable {
    public let lineCount: UInt64
    public let charCount: UInt64
    public let byteCount: UInt64
    public let isModified: Bool
    public let version: UInt64

    init(raw: EcfDocumentStatsRaw) {
        self.lineCount = raw.line_count
        self.charCount = raw.char_count
        self.byteCount = raw.byte_count
        self.isModified = raw.is_modified != 0
        self.version = raw.version
    }
}
