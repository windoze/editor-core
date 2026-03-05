import CEditorCoreFFI
import Foundation

public struct DocumentStats: Equatable, Sendable {
    public let lineCount: UInt64
    public let charCount: UInt64
    public let byteCount: UInt64
    public let isModified: Bool
    public let version: UInt64

    init(raw: EcfDocumentStats) {
        self.lineCount = raw.line_count
        self.charCount = raw.char_count
        self.byteCount = raw.byte_count
        self.isModified = raw.is_modified != 0
        self.version = raw.version
    }
}
