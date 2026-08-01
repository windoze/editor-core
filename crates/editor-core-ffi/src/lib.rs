//! C/FFI bridge for `editor-core` and integration crates.
//!
//! This crate exposes a C ABI focused on native host integrations (Windows/macOS/Linux).
//! Complex payloads use UTF-8 JSON strings for forward-compatible schema evolution.

use editor_core::commands::{
    Command, CommandResult, CursorCommand, EditCommand, ExpandSelectionDirection,
    ExpandSelectionUnit, Position, Selection, SelectionDirection, StyleCommand, TabKeyBehavior,
    TextEditSpec, ViewCommand,
};
use editor_core::decorations::{
    Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange,
};
use editor_core::diagnostics::{Diagnostic, DiagnosticRange, DiagnosticSeverity};
use editor_core::processing::{DocumentProcessor, ProcessingEdit};
use editor_core::snapshot::{
    Cell, ComposedCell, ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind,
    HeadlessGrid, HeadlessLine, MinimapGrid, MinimapLine,
};
use editor_core::state::{
    CursorState, DecorationsState, DiagnosticsState, DocumentState, EditorState,
    EditorStateManager, FoldingState, StyleState, UndoRedoState, ViewportState,
};
use editor_core::symbols::{
    DocumentOutline, DocumentSymbol, SymbolKind, SymbolLocation, SymbolRange, Utf16Position,
    Utf16Range, WorkspaceSymbol,
};
use editor_core::workspace::{
    BufferId, OpenBufferResult, ViewId, ViewSmoothScrollState, Workspace, WorkspaceSearchResult,
    WorkspaceViewportState,
};
use editor_core::{
    AutoPair, AutoPairsConfig, FoldRegion, IndentStyle, IndentationConfig, Interval, LineEnding,
    SearchMatch, SearchOptions, StyleLayerId, WrapIndent, WrapMode,
};
use editor_core_lsp::{
    CompletionTextEditMode, LspCoordinateConverter, apply_completion_item, apply_text_edits,
    completion_item_to_text_edit_specs, decode_semantic_style_id, encode_semantic_style_id,
    file_uri_to_path, locations_from_value, lsp_code_lens_to_processing_edit,
    lsp_diagnostics_to_processing_edits, lsp_document_highlights_to_processing_edit,
    lsp_document_links_to_processing_edit, lsp_document_symbols_to_processing_edit,
    lsp_formatting_options, lsp_formatting_options_for_indentation_config,
    lsp_inlay_hints_to_processing_edit, lsp_workspace_symbols_to_results, path_to_file_uri,
    percent_decode_path, percent_encode_path, semantic_tokens_to_intervals, text_edits_from_value,
};
use editor_core_sublime::{SublimeProcessor, SublimeScopeMapper, SublimeSyntaxSet};
use editor_core_treesitter::{
    TreeSitterIndenter, TreeSitterIndenterConfig, TreeSitterLanguage, TreeSitterProcessor,
    TreeSitterProcessorConfig, TreeSitterUpdateMode,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::ffi::{CStr, CString, c_char};
use std::mem::size_of;
use std::path::Path;
use std::ptr;
use std::slice;

mod json_bridge;
use json_bridge::*;
mod binary_abi;
mod editor_state_abi;
mod lsp_abi;
mod processors_abi;
mod workspace_abi;

pub use binary_abi::*;
pub use editor_state_abi::*;
pub use lsp_abi::*;
pub use processors_abi::*;
pub use workspace_abi::*;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

fn set_last_error(msg: impl Into<String>) {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = Some(msg.into());
    });
}

fn clear_last_error() {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = None;
    });
}

fn ffi_catch<T, F>(f: F) -> Result<T, String>
where
    F: FnOnce() -> Result<T, String>,
{
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(_) => Err("panic across FFI boundary".to_string()),
    }
}

fn make_c_string_ptr(mut s: String) -> *mut c_char {
    if s.contains('\0') {
        // CString forbids interior NUL. Keep JSON parseable and deterministic.
        s = s.replace('\0', "\\u0000");
    }
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("").expect("empty cstring").into_raw(),
    }
}

fn json_ptr(value: Value) -> *mut c_char {
    make_c_string_ptr(value.to_string())
}

fn result_json_ptr<T, F>(default: *mut c_char, f: F) -> *mut c_char
where
    F: FnOnce() -> Result<T, String>,
    T: Into<Value>,
{
    match ffi_catch(f) {
        Ok(v) => {
            clear_last_error();
            json_ptr(v.into())
        }
        Err(err) => {
            set_last_error(err);
            default
        }
    }
}

fn result_ptr<T, F>(default: *mut T, f: F) -> *mut T
where
    F: FnOnce() -> Result<*mut T, String>,
{
    match ffi_catch(f) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error(err);
            default
        }
    }
}

fn result_bool<F>(default: bool, f: F) -> bool
where
    F: FnOnce() -> Result<bool, String>,
{
    match ffi_catch(f) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            default
        }
    }
}

fn require_mut<'a, T>(ptr: *mut T, name: &str) -> Result<&'a mut T, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    // SAFETY: checked for null; caller promises unique mutable pointer.
    Ok(unsafe { &mut *ptr })
}

fn require_ref<'a, T>(ptr: *const T, name: &str) -> Result<&'a T, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    // SAFETY: checked for null; caller promises valid pointer.
    Ok(unsafe { &*ptr })
}

fn require_string(ptr: *const c_char, name: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    // SAFETY: checked for null; caller provides NUL-terminated string.
    let cstr = unsafe { CStr::from_ptr(ptr) };
    cstr.to_str()
        .map(|s| s.to_string())
        .map_err(|err| format!("{name} is not valid UTF-8: {err}"))
}

fn optional_string(ptr: *const c_char, name: &str) -> Result<Option<String>, String> {
    if ptr.is_null() {
        return Ok(None);
    }
    require_string(ptr, name).map(Some)
}

fn parse_json<T: for<'de> Deserialize<'de>>(text: &str, what: &str) -> Result<T, String> {
    serde_json::from_str(text).map_err(|err| format!("invalid {what} JSON: {err}"))
}

fn parse_json_value(text: &str, what: &str) -> Result<Value, String> {
    serde_json::from_str(text).map_err(|err| format!("invalid {what} JSON: {err}"))
}

fn status_result<F>(f: F) -> i32
where
    F: FnOnce() -> Result<(), (EcfStatus, String)>,
{
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(Ok(())) => {
            clear_last_error();
            EcfStatus::Ok.code()
        }
        Ok(Err((status, msg))) => {
            set_last_error(msg);
            status.code()
        }
        Err(_) => {
            set_last_error("panic across FFI boundary");
            EcfStatus::Internal.code()
        }
    }
}

fn checked_u32(v: usize, what: &str) -> Result<u32, (EcfStatus, String)> {
    u32::try_from(v).map_err(|_| {
        (
            EcfStatus::Unsupported,
            format!("{what} exceeds u32 range: {v}"),
        )
    })
}

fn checked_u16(v: usize, what: &str) -> Result<u16, (EcfStatus, String)> {
    u16::try_from(v).map_err(|_| {
        (
            EcfStatus::Unsupported,
            format!("{what} exceeds u16 range: {v}"),
        )
    })
}

fn usize_from_u32(v: u32, what: &str) -> Result<usize, String> {
    usize::try_from(v).map_err(|_| format!("{what} exceeds usize range: {v}"))
}

fn usize_from_u64(v: u64, what: &str) -> Result<usize, String> {
    usize::try_from(v).map_err(|_| format!("{what} exceeds usize range: {v}"))
}

fn u64_from_usize(v: usize, what: &str) -> Result<u64, String> {
    u64::try_from(v).map_err(|_| format!("{what} exceeds u64 range: {v}"))
}

fn status_usize_from_u32(v: u32, what: &str) -> Result<usize, (EcfStatus, String)> {
    usize_from_u32(v, what).map_err(|msg| (EcfStatus::InvalidArgument, msg))
}

fn require_utf8_bytes<'a>(
    ptr: *const u8,
    len: u32,
    name: &str,
) -> Result<&'a str, (EcfStatus, String)> {
    if len == 0 {
        return Ok("");
    }
    if ptr.is_null() {
        return Err((
            EcfStatus::InvalidArgument,
            format!("{name} is null but len={len}"),
        ));
    }
    let len_usize = usize::try_from(len).map_err(|_| {
        (
            EcfStatus::Unsupported,
            format!("{name} length exceeds usize: {len}"),
        )
    })?;
    // SAFETY: pointer checked for non-null and len provided by caller.
    let bytes = unsafe { slice::from_raw_parts(ptr, len_usize) };
    std::str::from_utf8(bytes).map_err(|err| (EcfStatus::InvalidUtf8, format!("{name}: {err}")))
}

fn write_le_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn write_le_u16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn build_viewport_blob(grid: &HeadlessGrid) -> Result<Vec<u8>, (EcfStatus, String)> {
    let line_count = checked_u32(grid.lines.len(), "line_count")?;

    let mut line_records: Vec<EcfViewportLine> = Vec::with_capacity(grid.lines.len());
    let mut cell_records: Vec<EcfViewportCell> = Vec::new();
    let mut style_ids: Vec<u32> = Vec::new();

    for line in &grid.lines {
        let line_cell_start_index = checked_u32(cell_records.len(), "cell_start_index")?;
        let line_cell_count = checked_u32(line.cells.len(), "line_cell_count")?;

        for cell in &line.cells {
            let style_start_index = checked_u32(style_ids.len(), "style_start_index")?;
            let style_count = checked_u16(cell.styles.len(), "style_count")?;
            style_ids.extend(cell.styles.iter().copied());

            cell_records.push(EcfViewportCell {
                scalar_value: u32::from(cell.ch),
                width: checked_u16(cell.width, "cell width")?,
                style_count,
                style_start_index,
            });
        }

        line_records.push(EcfViewportLine {
            logical_line_index: checked_u32(line.logical_line_index, "logical_line_index")?,
            visual_in_logical: checked_u32(line.visual_in_logical, "visual_in_logical")?,
            char_offset_start: checked_u32(line.char_offset_start, "char_offset_start")?,
            char_offset_end: checked_u32(line.char_offset_end, "char_offset_end")?,
            cell_start_index: line_cell_start_index,
            cell_count: line_cell_count,
            segment_x_start_cells: checked_u16(
                line.segment_x_start_cells,
                "segment_x_start_cells",
            )?,
            is_wrapped_part: if line.is_wrapped_part { 1 } else { 0 },
            is_fold_placeholder_appended: if line.is_fold_placeholder_appended {
                1
            } else {
                0
            },
        });
    }

    let cell_count = checked_u32(cell_records.len(), "cell_count")?;
    let style_id_count = checked_u32(style_ids.len(), "style_id_count")?;

    let header_size = checked_u32(size_of::<EcfViewportBlobHeader>(), "header_size")?;
    let line_size = checked_u32(size_of::<EcfViewportLine>(), "line_size")?;
    let cell_size = checked_u32(size_of::<EcfViewportCell>(), "cell_size")?;

    let lines_bytes = line_count.checked_mul(line_size).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "line table size overflow".to_string(),
        )
    })?;
    let cells_bytes = cell_count.checked_mul(cell_size).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "cell table size overflow".to_string(),
        )
    })?;
    let styles_bytes = style_id_count.checked_mul(4).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "style table size overflow".to_string(),
        )
    })?;

    let lines_offset = header_size;
    let cells_offset = lines_offset
        .checked_add(lines_bytes)
        .ok_or_else(|| (EcfStatus::Unsupported, "cells_offset overflow".to_string()))?;
    let style_ids_offset = cells_offset.checked_add(cells_bytes).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "style_ids_offset overflow".to_string(),
        )
    })?;
    let total_len = style_ids_offset.checked_add(styles_bytes).ok_or_else(|| {
        (
            EcfStatus::Unsupported,
            "blob total size overflow".to_string(),
        )
    })?;

    let total_len_usize = usize::try_from(total_len).map_err(|_| {
        (
            EcfStatus::Unsupported,
            "blob size exceeds addressable memory".to_string(),
        )
    })?;

    let mut out = Vec::<u8>::with_capacity(total_len_usize);

    let header = EcfViewportBlobHeader {
        abi_version: ECF_ABI_VERSION,
        header_size,
        line_count,
        cell_count,
        style_id_count,
        lines_offset,
        cells_offset,
        style_ids_offset,
        reserved: 0,
    };

    write_le_u32(&mut out, header.abi_version);
    write_le_u32(&mut out, header.header_size);
    write_le_u32(&mut out, header.line_count);
    write_le_u32(&mut out, header.cell_count);
    write_le_u32(&mut out, header.style_id_count);
    write_le_u32(&mut out, header.lines_offset);
    write_le_u32(&mut out, header.cells_offset);
    write_le_u32(&mut out, header.style_ids_offset);
    write_le_u32(&mut out, header.reserved);

    for line in &line_records {
        write_le_u32(&mut out, line.logical_line_index);
        write_le_u32(&mut out, line.visual_in_logical);
        write_le_u32(&mut out, line.char_offset_start);
        write_le_u32(&mut out, line.char_offset_end);
        write_le_u32(&mut out, line.cell_start_index);
        write_le_u32(&mut out, line.cell_count);
        write_le_u16(&mut out, line.segment_x_start_cells);
        out.push(line.is_wrapped_part);
        out.push(line.is_fold_placeholder_appended);
    }

    for cell in &cell_records {
        write_le_u32(&mut out, cell.scalar_value);
        write_le_u16(&mut out, cell.width);
        write_le_u16(&mut out, cell.style_count);
        write_le_u32(&mut out, cell.style_start_index);
    }

    for style_id in &style_ids {
        write_le_u32(&mut out, *style_id);
    }

    if out.len() != total_len_usize {
        return Err((
            EcfStatus::Internal,
            format!(
                "unexpected viewport blob length: got {}, expected {}",
                out.len(),
                total_len_usize
            ),
        ));
    }

    Ok(out)
}

fn copy_blob_to_output(
    blob: &[u8],
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> Result<(), (EcfStatus, String)> {
    if out_len.is_null() {
        return Err((EcfStatus::InvalidArgument, "out_len is null".to_string()));
    }

    let needed = checked_u32(blob.len(), "blob length")?;
    // SAFETY: checked non-null and owned by caller.
    unsafe {
        *out_len = needed;
    }

    if out_buf.is_null() || out_cap < needed {
        return Err((
            EcfStatus::BufferTooSmall,
            format!("output buffer too small: need {needed}, have {out_cap}"),
        ));
    }

    let needed_usize = usize::try_from(needed).map_err(|_| {
        (
            EcfStatus::Unsupported,
            "blob size exceeds usize".to_string(),
        )
    })?;
    // SAFETY: caller provided valid buffer with at least needed bytes; pointers do not overlap.
    unsafe {
        ptr::copy_nonoverlapping(blob.as_ptr(), out_buf, needed_usize);
    }

    Ok(())
}

/// Opaque editor-state handle.
#[repr(C)]
pub struct EcfEditorState {
    inner: EditorStateManager,
}

/// Opaque workspace handle.
#[repr(C)]
pub struct EcfWorkspace {
    inner: Workspace,
}

/// Opaque Sublime processor handle.
#[repr(C)]
pub struct EcfSublimeProcessor {
    inner: SublimeProcessor,
}

/// Opaque Tree-sitter processor handle.
#[repr(C)]
pub struct EcfTreeSitterProcessor {
    inner: TreeSitterProcessor,
}

/// Opaque Tree-sitter indenter handle.
#[repr(C)]
pub struct EcfTreeSitterIndenter {
    inner: TreeSitterIndenter,
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
    fn code(self) -> i32 {
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
