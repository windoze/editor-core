import CEditorCoreFFI
import Foundation

func checkedFFIUInt32(_ value: UInt, context: String) throws -> UInt32 {
    guard value <= UInt(UInt32.max) else {
        throw EditorCoreFFIError.ffiStatus(
            code: .invalidArgument,
            context: context,
            message: "value exceeds uint32_t range: \(value)"
        )
    }
    return UInt32(value)
}

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

public struct WorkspaceInfo: Equatable, Sendable {
    public let bufferCount: UInt64
    public let viewCount: UInt64
    public let isEmpty: Bool
    public let activeViewId: UInt64?
    public let activeBufferId: UInt64?

    init(raw: EcfWorkspaceInfo) {
        self.bufferCount = raw.buffer_count
        self.viewCount = raw.view_count
        self.isEmpty = raw.is_empty != 0
        self.activeViewId = raw.has_active_view_id != 0 ? raw.active_view_id : nil
        self.activeBufferId = raw.has_active_buffer_id != 0 ? raw.active_buffer_id : nil
    }
}

public struct WorkspaceViewportState: Equatable, Sendable {
    public let widthCells: UInt32
    public let heightRows: UInt32?
    public let scrollTop: UInt32
    public let subRowOffset: UInt32
    public let overscanRows: UInt32
    public let visibleStart: UInt32
    public let visibleEnd: UInt32
    public let prefetchStart: UInt32
    public let prefetchEnd: UInt32
    public let totalVisualLines: UInt32

    init(raw: EcfWorkspaceViewportState) {
        self.widthCells = raw.width_cells
        self.heightRows = raw.has_height != 0 ? raw.height_rows : nil
        self.scrollTop = raw.scroll_top
        self.subRowOffset = raw.sub_row_offset
        self.overscanRows = raw.overscan_rows
        self.visibleStart = raw.visible_start
        self.visibleEnd = raw.visible_end
        self.prefetchStart = raw.prefetch_start
        self.prefetchEnd = raw.prefetch_end
        self.totalVisualLines = raw.total_visual_lines
    }
}
