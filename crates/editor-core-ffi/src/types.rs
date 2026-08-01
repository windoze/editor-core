use super::*;

/// Opaque editor-state handle.
#[repr(C)]
pub struct EcfEditorState {
    pub(crate) inner: EditorStateManager,
}

/// Opaque workspace handle.
#[repr(C)]
pub struct EcfWorkspace {
    pub(crate) inner: Workspace,
}

/// Opaque Sublime processor handle.
#[repr(C)]
pub struct EcfSublimeProcessor {
    pub(crate) inner: SublimeProcessor,
}

/// Opaque Tree-sitter processor handle.
#[repr(C)]
pub struct EcfTreeSitterProcessor {
    pub(crate) inner: TreeSitterProcessor,
}

/// Opaque Tree-sitter indenter handle.
#[repr(C)]
pub struct EcfTreeSitterIndenter {
    pub(crate) inner: TreeSitterIndenter,
}

/// ABI version for the typed/binary C contract in this crate.
pub const ECF_ABI_VERSION: u32 = 1;

/// Status codes returned by ABI-v1 typed/binary APIs.
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EcfStatus {
    /// Operation succeeded.
    Ok = 0,
    /// Invalid arguments (null pointer, invalid id, etc.).
    InvalidArgument = 1,
    /// Invalid UTF-8 payload.
    InvalidUtf8 = 2,
    /// Target object not found.
    NotFound = 3,
    /// Output buffer too small; caller should retry with returned size.
    BufferTooSmall = 4,
    /// Parsing failure.
    Parse = 5,
    /// Command execution failed.
    CommandFailed = 6,
    /// Internal failure.
    Internal = 7,
    /// Unsupported operation or value.
    Unsupported = 8,
    /// ABI/version mismatch.
    VersionMismatch = 9,
}

impl EcfStatus {
    pub(crate) fn code(self) -> i32 {
        self as i32
    }
}

/// Packed viewport blob header for ABI-v1.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfViewportBlobHeader {
    /// ABI version.
    pub abi_version: u32,
    /// Header byte size.
    pub header_size: u32,
    /// Number of line records.
    pub line_count: u32,
    /// Number of cell records.
    pub cell_count: u32,
    /// Number of style ids in trailing array.
    pub style_id_count: u32,
    /// Byte offset of line table from blob start.
    pub lines_offset: u32,
    /// Byte offset of cell table from blob start.
    pub cells_offset: u32,
    /// Byte offset of style id array from blob start.
    pub style_ids_offset: u32,
    /// Reserved for future use.
    pub reserved: u32,
}

/// Packed viewport line record for ABI-v1.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfViewportLine {
    /// Logical line index.
    pub logical_line_index: u32,
    /// Wrapped segment index in logical line.
    pub visual_in_logical: u32,
    /// Segment start char offset.
    pub char_offset_start: u32,
    /// Segment end char offset.
    pub char_offset_end: u32,
    /// Start index into the cell table.
    pub cell_start_index: u32,
    /// Number of cells in this line.
    pub cell_count: u32,
    /// Segment x start in cells.
    pub segment_x_start_cells: u16,
    /// 1 if wrapped part; 0 otherwise.
    pub is_wrapped_part: u8,
    /// 1 if fold placeholder was appended; 0 otherwise.
    pub is_fold_placeholder_appended: u8,
}

/// Packed viewport cell record for ABI-v1.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfViewportCell {
    /// Unicode scalar value (`char` as `u32`).
    pub scalar_value: u32,
    /// Display width in cells.
    pub width: u16,
    /// Number of style ids for this cell.
    pub style_count: u16,
    /// Start index into the style id array.
    pub style_start_index: u32,
}

/// Basic document stats output for ABI-v1 typed APIs.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfDocumentStats {
    /// ABI version.
    pub abi_version: u32,
    /// Struct byte size.
    pub struct_size: u32,
    /// Logical line count.
    pub line_count: u64,
    /// Character count.
    pub char_count: u64,
    /// UTF-8 byte count.
    pub byte_count: u64,
    /// 1 if modified since clean mark, otherwise 0.
    pub is_modified: u8,
    /// Reserved padding.
    pub reserved0: [u8; 7],
    /// State version.
    pub version: u64,
}

/// Workspace open-buffer output for typed ABI calls.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfOpenBufferResult {
    /// ABI version.
    pub abi_version: u32,
    /// Struct byte size.
    pub struct_size: u32,
    /// Opened buffer id.
    pub buffer_id: u64,
    /// Initial view id for the buffer.
    pub view_id: u64,
}

/// Workspace create-view output for typed ABI calls.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfCreateViewResult {
    /// ABI version.
    pub abi_version: u32,
    /// Struct byte size.
    pub struct_size: u32,
    /// Newly created view id.
    pub view_id: u64,
}

/// Workspace basic stats output for typed ABI calls.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfWorkspaceInfo {
    /// ABI version.
    pub abi_version: u32,
    /// Struct byte size.
    pub struct_size: u32,
    /// Number of open buffers.
    pub buffer_count: u64,
    /// Number of views across all buffers.
    pub view_count: u64,
    /// 1 if empty, otherwise 0.
    pub is_empty: u8,
    /// 1 if `active_view_id` is present, otherwise 0.
    pub has_active_view_id: u8,
    /// 1 if `active_buffer_id` is present, otherwise 0.
    pub has_active_buffer_id: u8,
    /// Reserved padding.
    pub reserved0: u8,
    /// Active view id (valid when `has_active_view_id=1`).
    pub active_view_id: u64,
    /// Active buffer id (valid when `has_active_buffer_id=1`).
    pub active_buffer_id: u64,
}

/// Workspace viewport state snapshot for typed ABI calls.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EcfWorkspaceViewportState {
    /// ABI version.
    pub abi_version: u32,
    /// Struct byte size.
    pub struct_size: u32,
    /// Viewport width (in cells).
    pub width_cells: u32,
    /// Viewport height (in rows). Valid only when `has_height=1`.
    pub height_rows: u32,
    /// 1 if height is set, otherwise 0.
    pub has_height: u32,
    /// Current top visual row.
    pub scroll_top: u32,
    /// Sub-row offset within `scroll_top` (0..=65535, normalized).
    pub sub_row_offset: u32,
    /// Overscan rows for prefetching.
    pub overscan_rows: u32,
    /// Visible range start (visual row).
    pub visible_start: u32,
    /// Visible range end (visual row).
    pub visible_end: u32,
    /// Prefetch range start (visual row).
    pub prefetch_start: u32,
    /// Prefetch range end (visual row).
    pub prefetch_end: u32,
    /// Total visual line count under current view config (wrap + folding aware).
    pub total_visual_lines: u32,
}
