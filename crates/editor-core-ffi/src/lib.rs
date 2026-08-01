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
    FoldRegion, IndentStyle, IndentationConfig, Interval, LineEnding, SearchMatch, SearchOptions,
    StyleLayerId, WrapIndent, WrapMode,
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

/// Free a C string allocated by this crate.
///
/// # Safety
///
/// `ptr` must be a valid pointer returned by a function in this crate that allocates C strings,
/// or null. The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // SAFETY: pointer was returned by CString::into_raw in this crate.
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

/// Retrieve the latest thread-local error message.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ffi_string_free`].
///
/// # Safety
///
/// This function is safe to call. The returned pointer must be freed with
/// [`editor_core_ffi_string_free`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_last_error_message() -> *mut c_char {
    let message = LAST_ERROR.with(|slot| {
        slot.borrow()
            .clone()
            .unwrap_or_else(|| "no error".to_string())
    });
    make_c_string_ptr(message)
}

/// Return the FFI crate version.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_version() -> *mut c_char {
    make_c_string_ptr(env!("CARGO_PKG_VERSION").to_string())
}

/// Create a new editor state manager.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_new(
    initial_text: *const c_char,
    viewport_width: u32,
) -> *mut EcfEditorState {
    result_ptr(ptr::null_mut(), || {
        let text = require_string(initial_text, "initial_text")?;
        let viewport_width = usize_from_u32(viewport_width, "viewport_width")?.max(1);
        let state = EcfEditorState {
            inner: EditorStateManager::new(&text, viewport_width),
        };
        Ok(Box::into_raw(Box::new(state)))
    })
}

/// Destroy an editor state handle.
///
/// # Safety
///
/// `state` must be a valid pointer returned by `editor_core_ffi_editor_state_new`, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_editor_state_free(state: *mut EcfEditorState) {
    if state.is_null() {
        return;
    }
    // SAFETY: pointer must come from editor_core_ffi_editor_state_new.
    unsafe {
        drop(Box::from_raw(state));
    }
}

/// Execute one command encoded as JSON.
///
/// Returns command result JSON. Caller owns returned string and must free it.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_execute_json(
    state: *mut EcfEditorState,
    command_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_mut(state, "state")?;
        let command_json = require_string(command_json, "command_json")?;
        let command = parse_command_from_json(&command_json)?;
        let result = state
            .inner
            .execute(command)
            .map_err(|err| format!("command execution failed: {err}"))?;
        Ok(value_command_result(result))
    })
}

/// Apply one or more processing edits encoded as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_apply_processing_edits_json(
    state: *mut EcfEditorState,
    edits_json: *const c_char,
) -> bool {
    result_bool(false, || {
        let state = require_mut(state, "state")?;
        let edits_json = require_string(edits_json, "edits_json")?;
        let edits = parse_processing_edits(&edits_json)?;
        state.inner.apply_processing_edits(edits);
        Ok(true)
    })
}

/// Return full editor state as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_full_state_json(
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        Ok(value_editor_state(&state.inner.get_full_state()))
    })
}

/// Return full document text (LF-normalized internal text).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_text(state: *const EcfEditorState) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        Ok(json!({ "text": state.inner.editor().get_text() }))
    })
}

/// Return full document text converted to preferred save line ending.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_text_for_saving(
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        Ok(json!({
            "text": state.inner.get_text_for_saving(),
            "line_ending": line_ending_to_str(state.inner.line_ending()),
        }))
    })
}

/// Return current document symbols / outline as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_document_symbols_json(
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let symbols = state.inner.editor().document_symbols();
        Ok(json!({
            "symbols": symbols
                .symbols
                .iter()
                .map(value_document_symbol)
                .collect::<Vec<_>>()
        }))
    })
}

/// Return current diagnostics list as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_diagnostics_json(
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        Ok(json!({
            "diagnostics": state
                .inner
                .editor()
                .diagnostics()
                .iter()
                .map(value_diagnostic)
                .collect::<Vec<_>>()
        }))
    })
}

/// Return current decorations list as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_decorations_json(
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let layers = state
            .inner
            .editor()
            .decorations()
            .iter()
            .map(|(layer, decorations)| {
                json!({
                    "layer": layer.0,
                    "decorations": decorations.iter().map(value_decoration).collect::<Vec<_>>()
                })
            })
            .collect::<Vec<_>>();
        Ok(json!({ "layers": layers }))
    })
}

/// Set preferred line ending (`"lf"` or `"crlf"`).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_set_line_ending(
    state: *mut EcfEditorState,
    line_ending: *const c_char,
) -> bool {
    result_bool(false, || {
        let state = require_mut(state, "state")?;
        let line_ending = require_string(line_ending, "line_ending")?;
        state
            .inner
            .set_line_ending(line_ending_from_str(&line_ending)?);
        Ok(true)
    })
}

/// Get preferred line ending as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_get_line_ending(
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        Ok(json!({ "line_ending": line_ending_to_str(state.inner.line_ending()) }))
    })
}

/// Get styled viewport snapshot as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_viewport_styled_json(
    state: *const EcfEditorState,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = state
            .inner
            .get_viewport_content_styled(start_visual_row, count);
        Ok(value_headless_grid(&grid))
    })
}

/// Get minimap snapshot as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_minimap_json(
    state: *const EcfEditorState,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = state.inner.get_minimap_content(start_visual_row, count);
        Ok(value_minimap_grid(&grid))
    })
}

/// Get decoration-aware composed snapshot as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_viewport_composed_json(
    state: *const EcfEditorState,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = state
            .inner
            .get_viewport_content_composed(start_visual_row, count);
        Ok(value_composed_grid(&grid))
    })
}

/// Take and return last text delta as JSON (or null delta).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_take_last_text_delta_json(
    state: *mut EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_mut(state, "state")?;
        let value = state
            .inner
            .take_last_text_delta()
            .as_deref()
            .map(value_text_delta);
        Ok(json!({ "delta": value }))
    })
}

/// Return last text delta as JSON without consuming it.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_last_text_delta_json(
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let value = state.inner.last_text_delta().map(value_text_delta);
        Ok(json!({ "delta": value }))
    })
}

/// Create a new workspace.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_new() -> *mut EcfWorkspace {
    result_ptr(ptr::null_mut(), || {
        Ok(Box::into_raw(Box::new(EcfWorkspace {
            inner: Workspace::new(),
        })))
    })
}

/// Destroy a workspace handle.
///
/// # Safety
///
/// `workspace` must be a valid pointer returned by `editor_core_ffi_workspace_new`, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_free(workspace: *mut EcfWorkspace) {
    if workspace.is_null() {
        return;
    }
    // SAFETY: pointer must come from editor_core_ffi_workspace_new.
    unsafe {
        drop(Box::from_raw(workspace));
    }
}

/// Open a buffer and create its initial view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_open_buffer(
    workspace: *mut EcfWorkspace,
    uri: *const c_char,
    text: *const c_char,
    viewport_width: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let uri = optional_string(uri, "uri")?;
        let text = require_string(text, "text")?;
        let viewport_width = usize_from_u32(viewport_width, "viewport_width")?.max(1);
        let opened = workspace
            .inner
            .open_buffer(uri, &text, viewport_width)
            .map_err(|err| format!("open_buffer failed: {err:?}"))?;
        Ok(value_open_buffer_result(opened))
    })
}

/// Typed ABI variant: open a buffer and create its initial view.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `text` must be a valid NUL-terminated UTF-8 string pointer.
/// - `out_result` must be a valid writable pointer to an `EcfOpenBufferResult`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_open_buffer_typed(
    workspace: *mut EcfWorkspace,
    uri: *const c_char,
    text: *const c_char,
    viewport_width: u32,
    out_result: *mut EcfOpenBufferResult,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_result.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_result is null".to_string()));
        }
        let uri =
            optional_string(uri, "uri").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let text = require_string(text, "text")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let viewport_width = status_usize_from_u32(viewport_width, "viewport_width")?.max(1);

        let opened = workspace
            .inner
            .open_buffer(uri, &text, viewport_width)
            .map_err(|err| (EcfStatus::Internal, format!("open_buffer failed: {err:?}")))?;

        let result = EcfOpenBufferResult {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfOpenBufferResult>() as u32,
            buffer_id: opened.buffer_id.get(),
            view_id: opened.view_id.get(),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_result = result;
        }
        Ok(())
    })
}

/// Close a buffer by id.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_close_buffer(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        workspace
            .inner
            .close_buffer(BufferId::from_raw(buffer_id))
            .map_err(|err| format!("close_buffer failed: {err:?}"))?;
        Ok(true)
    })
}

/// Close a view by id.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_close_view(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        workspace
            .inner
            .close_view(ViewId::from_raw(view_id))
            .map_err(|err| format!("close_view failed: {err:?}"))?;
        Ok(true)
    })
}

/// Create a new view for an existing buffer.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_create_view(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
    viewport_width: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let viewport_width = usize_from_u32(viewport_width, "viewport_width")?.max(1);
        let view_id = workspace
            .inner
            .create_view(BufferId::from_raw(buffer_id), viewport_width)
            .map_err(|err| format!("create_view failed: {err:?}"))?;
        Ok(json!({ "view_id": view_id.get() }))
    })
}

/// Typed ABI variant: create a new view for an existing buffer.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `out_result` must be a valid writable pointer to an `EcfCreateViewResult`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_create_view_typed(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
    viewport_width: u32,
    out_result: *mut EcfCreateViewResult,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_result.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_result is null".to_string()));
        }

        let viewport_width = status_usize_from_u32(viewport_width, "viewport_width")?.max(1);
        let view_id = workspace
            .inner
            .create_view(BufferId::from_raw(buffer_id), viewport_width)
            .map_err(|err| (EcfStatus::Internal, format!("create_view failed: {err:?}")))?;

        let result = EcfCreateViewResult {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfCreateViewResult>() as u32,
            view_id: view_id.get(),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_result = result;
        }
        Ok(())
    })
}

/// Set active view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_set_active_view(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        workspace
            .inner
            .set_active_view(ViewId::from_raw(view_id))
            .map_err(|err| format!("set_active_view failed: {err:?}"))?;
        Ok(true)
    })
}

/// Return workspace basic stats and active ids as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_info_json(
    workspace: *const EcfWorkspace,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_ref(workspace, "workspace")?;
        Ok(json!({
            "buffer_count": workspace.inner.len(),
            "view_count": workspace.inner.view_count(),
            "is_empty": workspace.inner.is_empty(),
            "active_view_id": workspace.inner.active_view_id().map(|id| id.get()),
            "active_buffer_id": workspace.inner.active_buffer_id().map(|id| id.get()),
        }))
    })
}

/// Typed ABI variant: return workspace basic stats and active ids.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `out_info` must be a valid writable pointer to an `EcfWorkspaceInfo`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_get_info(
    workspace: *const EcfWorkspace,
    out_info: *mut EcfWorkspaceInfo,
) -> i32 {
    status_result(|| {
        let workspace = require_ref(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_info.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_info is null".to_string()));
        }

        let active_view_id = workspace.inner.active_view_id().map(|id| id.get());
        let active_buffer_id = workspace.inner.active_buffer_id().map(|id| id.get());

        let info = EcfWorkspaceInfo {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfWorkspaceInfo>() as u32,
            buffer_count: workspace.inner.len() as u64,
            view_count: workspace.inner.view_count() as u64,
            is_empty: if workspace.inner.is_empty() { 1 } else { 0 },
            has_active_view_id: if active_view_id.is_some() { 1 } else { 0 },
            has_active_buffer_id: if active_buffer_id.is_some() { 1 } else { 0 },
            reserved0: 0,
            active_view_id: active_view_id.unwrap_or(0),
            active_buffer_id: active_buffer_id.unwrap_or(0),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_info = info;
        }

        Ok(())
    })
}

/// Execute one command against a view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_execute_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    command_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let command_json = require_string(command_json, "command_json")?;
        let command = parse_command_from_json(&command_json)?;
        let result = workspace
            .inner
            .execute(ViewId::from_raw(view_id), command)
            .map_err(|err| format!("workspace execute failed: {err:?}"))?;
        Ok(value_command_result(result))
    })
}

/// Apply one or more processing edits to a workspace buffer.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_apply_processing_edits_json(
    workspace: *mut EcfWorkspace,
    buffer_id: u64,
    edits_json: *const c_char,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        let edits_json = require_string(edits_json, "edits_json")?;
        let edits = parse_processing_edits(&edits_json)?;
        workspace
            .inner
            .apply_processing_edits(BufferId::from_raw(buffer_id), edits)
            .map_err(|err| format!("apply_processing_edits failed: {err:?}"))?;
        Ok(true)
    })
}

/// Get buffer text as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_buffer_text_json(
    workspace: *const EcfWorkspace,
    buffer_id: u64,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_ref(workspace, "workspace")?;
        let text = workspace
            .inner
            .buffer_text(BufferId::from_raw(buffer_id))
            .map_err(|err| format!("buffer_text failed: {err:?}"))?;
        Ok(json!({ "text": text }))
    })
}

/// Get viewport state for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_state_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let state = workspace
            .inner
            .viewport_state_for_view(ViewId::from_raw(view_id))
            .map_err(|err| format!("viewport_state_for_view failed: {err:?}"))?;
        Ok(value_workspace_viewport_state(&state))
    })
}

/// Typed ABI variant: return workspace viewport state for a view.
///
/// # Safety
///
/// - `workspace` must be a valid `EcfWorkspace*` returned by this crate.
/// - `out_state` must be a valid writable pointer to an `EcfWorkspaceViewportState`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_workspace_get_viewport_state(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    out_state: *mut EcfWorkspaceViewportState,
) -> i32 {
    fn saturating_u32(value: usize) -> u32 {
        value.try_into().unwrap_or(u32::MAX)
    }

    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_state.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_state is null".to_string()));
        }

        let state = workspace
            .inner
            .viewport_state_for_view(ViewId::from_raw(view_id))
            .map_err(|err| {
                (
                    EcfStatus::Internal,
                    format!("viewport_state_for_view failed: {err:?}"),
                )
            })?;

        let height_rows = state.height.map(saturating_u32).unwrap_or(0);
        let has_height = if state.height.is_some() { 1 } else { 0 };

        let out = EcfWorkspaceViewportState {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfWorkspaceViewportState>() as u32,
            width_cells: saturating_u32(state.width),
            height_rows,
            has_height,
            scroll_top: saturating_u32(state.scroll_top),
            sub_row_offset: state.smooth_scroll.sub_row_offset as u32,
            overscan_rows: saturating_u32(state.smooth_scroll.overscan_rows),
            visible_start: saturating_u32(state.visible_lines.start),
            visible_end: saturating_u32(state.visible_lines.end),
            prefetch_start: saturating_u32(state.prefetch_lines.start),
            prefetch_end: saturating_u32(state.prefetch_lines.end),
            total_visual_lines: saturating_u32(state.total_visual_lines),
        };

        // SAFETY: non-null checked; caller provides writable memory.
        unsafe {
            *out_state = out;
        }
        Ok(())
    })
}

/// Set viewport height for a view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_set_viewport_height(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    height: u32,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        let height = usize_from_u32(height, "height")?;
        workspace
            .inner
            .set_viewport_height(ViewId::from_raw(view_id), height)
            .map_err(|err| format!("set_viewport_height failed: {err:?}"))?;
        Ok(true)
    })
}

/// Set smooth-scroll state for a view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_set_smooth_scroll_state(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    top_visual_row: u32,
    sub_row_offset: u16,
    overscan_rows: u32,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
        let top_visual_row = usize_from_u32(top_visual_row, "top_visual_row")?;
        let overscan_rows = usize_from_u32(overscan_rows, "overscan_rows")?;
        workspace
            .inner
            .set_smooth_scroll_state(
                ViewId::from_raw(view_id),
                ViewSmoothScrollState {
                    top_visual_row,
                    sub_row_offset,
                    overscan_rows,
                },
            )
            .map_err(|err| format!("set_smooth_scroll_state failed: {err:?}"))?;
        Ok(true)
    })
}

/// Get styled viewport snapshot for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_styled_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = workspace
            .inner
            .get_viewport_content_styled(ViewId::from_raw(view_id), start_visual_row, count)
            .map_err(|err| format!("get_viewport_content_styled failed: {err:?}"))?;
        Ok(value_headless_grid(&grid))
    })
}

/// Get minimap snapshot for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_minimap_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = workspace
            .inner
            .get_minimap_content(ViewId::from_raw(view_id), start_visual_row, count)
            .map_err(|err| format!("get_minimap_content failed: {err:?}"))?;
        Ok(value_minimap_grid(&grid))
    })
}

/// Get composed viewport snapshot for a view as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_viewport_composed_json(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")?;
        let count = usize_from_u32(count, "count")?;
        let grid = workspace
            .inner
            .get_viewport_content_composed(ViewId::from_raw(view_id), start_visual_row, count)
            .map_err(|err| format!("get_viewport_content_composed failed: {err:?}"))?;
        Ok(value_composed_grid(&grid))
    })
}

/// Search all open buffers.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_search_all_open_buffers_json(
    workspace: *const EcfWorkspace,
    query: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_ref(workspace, "workspace")?;
        let query = require_string(query, "query")?;
        let options = if options_json.is_null() {
            SearchOptions::default()
        } else {
            let options_text = require_string(options_json, "options_json")?;
            let parsed: FfiSearchOptions = parse_json(&options_text, "search options")?;
            parsed.into()
        };

        let results = workspace
            .inner
            .search_all_open_buffers(&query, options)
            .map_err(|err| format!("search failed: {err}"))?;
        Ok(json!({
            "results": results.iter().map(value_workspace_search_result).collect::<Vec<_>>()
        }))
    })
}

/// Apply text edits grouped by buffer id.
///
/// Input JSON format:
/// `[ { "buffer_id": 1, "edits": [ {"start": 0, "end": 3, "text": "x"} ] } ]`
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_apply_text_edits_json(
    workspace: *mut EcfWorkspace,
    edits_json: *const c_char,
) -> *mut c_char {
    #[derive(Debug, Deserialize)]
    struct WorkspaceEditsItem {
        buffer_id: u64,
        edits: Vec<FfiTextEditSpec>,
    }

    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let edits_json = require_string(edits_json, "edits_json")?;
        let parsed: Vec<WorkspaceEditsItem> = parse_json(&edits_json, "workspace text edits")?;

        let edits = parsed.into_iter().map(|item| {
            (
                BufferId::from_raw(item.buffer_id),
                item.edits
                    .into_iter()
                    .map(Into::into)
                    .collect::<Vec<TextEditSpec>>(),
            )
        });

        let applied = workspace
            .inner
            .apply_text_edits(edits)
            .map_err(|err| format!("apply_text_edits failed: {err:?}"))?;

        Ok(json!({
            "applied": applied
                .into_iter()
                .map(|(id, count)| json!({ "buffer_id": id.get(), "edit_count": count }))
                .collect::<Vec<_>>()
        }))
    })
}

/// Convert a local path to `file://` URI.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_path_to_file_uri(path: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let path = require_string(path, "path")?;
        let uri = path_to_file_uri(Path::new(&path));
        Ok(json!({ "uri": uri }))
    })
}

/// Convert a `file://` URI to path.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_file_uri_to_path(uri: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let uri = require_string(uri, "uri")?;
        let path = file_uri_to_path(&uri)
            .map(|p| p.to_string_lossy().to_string())
            .ok_or_else(|| "invalid file URI".to_string())?;
        Ok(json!({ "path": path }))
    })
}

/// Percent-encode a path segment.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_percent_encode_path(path: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let path = require_string(path, "path")?;
        Ok(json!({ "encoded": percent_encode_path(&path) }))
    })
}

/// Percent-decode a path segment.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_percent_decode_path(path: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let path = require_string(path, "path")?;
        Ok(json!({ "decoded": percent_decode_path(&path) }))
    })
}

/// Convert char offset to UTF-16 code units for one line of text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_char_offset_to_utf16(
    line_text: *const c_char,
    char_offset: u64,
) -> u64 {
    match ffi_catch(|| {
        let line_text = require_string(line_text, "line_text")?;
        let char_offset = usize_from_u64(char_offset, "char_offset")?;
        let utf16_offset = LspCoordinateConverter::char_offset_to_utf16(&line_text, char_offset);
        u64_from_usize(utf16_offset, "utf16_offset")
    }) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            0
        }
    }
}

/// Convert UTF-16 code units to char offset for one line of text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_utf16_to_char_offset(
    line_text: *const c_char,
    utf16_offset: u64,
) -> u64 {
    match ffi_catch(|| {
        let line_text = require_string(line_text, "line_text")?;
        let utf16_offset = usize_from_u64(utf16_offset, "utf16_offset")?;
        let char_offset = LspCoordinateConverter::utf16_to_char_offset(&line_text, utf16_offset);
        u64_from_usize(char_offset, "char_offset")
    }) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            0
        }
    }
}

/// Build minimal LSP `FormattingOptions` JSON.
///
/// This is primarily useful for indentation and on-type formatting requests.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_formatting_options_json(
    tab_size: u32,
    insert_spaces: bool,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let tab_size = usize_from_u32(tab_size, "tab_size")?;
        Ok(json!({ "options": lsp_formatting_options(tab_size, insert_spaces) }))
    })
}

/// Build LSP `FormattingOptions` JSON from an `editor-core` indentation config JSON.
///
/// `indentation_config_json` uses the same shape as the JSON command bridge:
///
/// ```json
/// { "style": { "kind": "spaces", "width": 4 } }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_formatting_options_for_indentation_config_json(
    indentation_config_json: *const c_char,
    tab_width: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let json_text = require_string(indentation_config_json, "indentation_config_json")?;
        let cfg: FfiIndentationConfig = parse_json(&json_text, "indentation config")?;
        let cfg: IndentationConfig = cfg.into();
        let tab_width = usize_from_u32(tab_width, "tab_width")?;
        Ok(json!({
            "options": lsp_formatting_options_for_indentation_config(&cfg, tab_width)
        }))
    })
}

/// Build LSP `textDocument/onTypeFormatting` params JSON for the current cursor position.
///
/// Notes:
/// - `options_json` is optional (nullable). When null, `{}` is used.
/// - The returned payload is the *params object* (not a full JSON-RPC envelope).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_on_type_formatting_params_json(
    state: *const EcfEditorState,
    uri: *const c_char,
    ch: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let uri = require_string(uri, "uri")?;
        let ch = require_string(ch, "ch")?;

        let options = if let Some(options_json) = optional_string(options_json, "options_json")? {
            parse_json_value(&options_json, "formatting options")?
        } else {
            json!({})
        };

        let pos = state.inner.editor().cursor_position();
        let line_text = state
            .inner
            .editor()
            .line_index()
            .get_line_text(pos.line)
            .unwrap_or_default();
        let utf16_character = LspCoordinateConverter::char_offset_to_utf16(&line_text, pos.column);

        Ok(json!({
            "params": {
                "textDocument": { "uri": uri },
                "position": { "line": pos.line, "character": utf16_character },
                "ch": ch,
                "options": options,
            }
        }))
    })
}

/// Apply LSP `TextEdit[]` JSON to an editor state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_apply_text_edits_json(
    state: *mut EcfEditorState,
    edits_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_mut(state, "state")?;
        let edits_json = require_string(edits_json, "edits_json")?;
        let value = parse_json_value(&edits_json, "LSP text edits")?;
        let edits = text_edits_from_value(&value);
        let changed = apply_text_edits(&mut state.inner, &edits)
            .map_err(|err| format!("apply LSP text edits failed: {err}"))?;
        Ok(json!({
            "changed_ranges": changed
                .into_iter()
                .map(|(start, end)| value_offset_range(start, end))
                .collect::<Vec<_>>()
        }))
    })
}

/// Convert semantic tokens data (`u32[]`) into style intervals for current state text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_semantic_tokens_to_intervals_json(
    state: *const EcfEditorState,
    data_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let data_json = require_string(data_json, "data_json")?;
        let data: Vec<u32> = parse_json(&data_json, "semantic tokens data")?;
        let intervals = semantic_tokens_to_intervals(
            &data,
            state.inner.editor().line_index(),
            encode_semantic_style_id,
        )
        .map_err(|err| format!("semantic_tokens_to_intervals failed: {err}"))?;

        Ok(json!({
            "intervals": intervals.iter().map(value_interval).collect::<Vec<_>>()
        }))
    })
}

/// Decode default semantic style id into `(token_type, token_modifiers)`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_decode_semantic_style_id(style_id: u32) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let (token_type, token_modifiers) = decode_semantic_style_id(style_id);
        Ok(json!({
            "token_type": token_type,
            "token_modifiers": token_modifiers,
        }))
    })
}

/// Convert LSP document highlights result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_highlights_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_single_processing_edit_from_state_json(state, result_json, |line_index, value| {
        lsp_document_highlights_to_processing_edit(line_index, value)
    })
}

/// Convert LSP inlay hints result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_inlay_hints_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_single_processing_edit_from_state_json(state, result_json, |line_index, value| {
        lsp_inlay_hints_to_processing_edit(line_index, value)
    })
}

/// Convert LSP document links result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_links_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_single_processing_edit_from_state_json(state, result_json, |line_index, value| {
        lsp_document_links_to_processing_edit(line_index, value)
    })
}

/// Convert LSP code lens result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_code_lens_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_single_processing_edit_from_state_json(state, result_json, |line_index, value| {
        lsp_code_lens_to_processing_edit(line_index, value)
    })
}

/// Convert LSP document symbols result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_symbols_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_single_processing_edit_from_state_json(state, result_json, |line_index, value| {
        lsp_document_symbols_to_processing_edit(line_index, value)
    })
}

/// Convert LSP diagnostics notification params JSON into processing edits JSON array.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_diagnostics_to_processing_edits_json(
    state: *const EcfEditorState,
    publish_diagnostics_params_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let params_json = require_string(
            publish_diagnostics_params_json,
            "publish_diagnostics_params_json",
        )?;
        let params_value = parse_json_value(&params_json, "publishDiagnostics params")?;

        let notification = editor_core_lsp::LspNotification::from_method_and_params(
            "textDocument/publishDiagnostics",
            &params_value,
        )
        .ok_or_else(|| "invalid publishDiagnostics params".to_string())?;

        let editor_core_lsp::LspNotification::PublishDiagnostics(params) = notification else {
            return Err("invalid publishDiagnostics payload".to_string());
        };

        let edits = lsp_diagnostics_to_processing_edits(state.inner.editor().line_index(), &params);
        Ok(json!({
            "edits": edits.iter().map(value_processing_edit).collect::<Vec<_>>()
        }))
    })
}

/// Convert LSP workspace symbol result JSON into workspace symbols JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_workspace_symbols_json(
    result_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let result_json = require_string(result_json, "result_json")?;
        let value = parse_json_value(&result_json, "workspace symbols")?;
        let symbols = lsp_workspace_symbols_to_results(&value);
        Ok(json!({
            "symbols": symbols.iter().map(value_workspace_symbol).collect::<Vec<_>>()
        }))
    })
}

/// Normalize LSP locations result JSON (`Location|Location[]|LocationLink|LocationLink[]`).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_locations_json(result_json: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let result_json = require_string(result_json, "result_json")?;
        let value = parse_json_value(&result_json, "locations")?;
        let locations = locations_from_value(&value);
        Ok(json!({
            "locations": locations
                .iter()
                .map(|loc| {
                    json!({
                        "uri": loc.uri,
                        "range": {
                            "start": {
                                "line": loc.range.start.line,
                                "character": loc.range.start.character,
                            },
                            "end": {
                                "line": loc.range.end.line,
                                "character": loc.range.end.character,
                            }
                        }
                    })
                })
                .collect::<Vec<_>>()
        }))
    })
}

/// Build completion text edits (`TextEditSpec[]`) from one completion item JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_completion_item_to_text_edits_json(
    state: *const EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
    fallback_start: u64,
    fallback_end: u64,
    has_fallback: bool,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let completion_item_json = require_string(completion_item_json, "completion_item_json")?;
        let mode = require_string(mode, "mode")?;

        let mode = parse_completion_mode(&mode)?;
        let item = parse_json_value(&completion_item_json, "completion item")?;
        let fallback = if has_fallback {
            Some((
                usize_from_u64(fallback_start, "fallback_start")?,
                usize_from_u64(fallback_end, "fallback_end")?,
            ))
        } else {
            None
        };

        let edits = completion_item_to_text_edit_specs(
            state.inner.editor().line_index(),
            &item,
            mode,
            fallback,
        );

        Ok(json!({
            "edits": edits
                .into_iter()
                .map(|e| json!({ "start": e.start, "end": e.end, "text": e.text }))
                .collect::<Vec<_>>()
        }))
    })
}

/// Apply one completion item JSON as a single undoable edit.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_apply_completion_item_json(
    state: *mut EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
) -> bool {
    result_bool(false, || {
        let state = require_mut(state, "state")?;
        let completion_item_json = require_string(completion_item_json, "completion_item_json")?;
        let mode = require_string(mode, "mode")?;

        let item = parse_json_value(&completion_item_json, "completion item")?;
        let mode = parse_completion_mode(&mode)?;

        apply_completion_item(&mut state.inner, &item, mode)
            .map_err(|err| format!("apply_completion_item failed: {err}"))?;
        Ok(true)
    })
}

fn parse_completion_mode(mode: &str) -> Result<CompletionTextEditMode, String> {
    match mode.trim().to_ascii_lowercase().as_str() {
        "insert" => Ok(CompletionTextEditMode::Insert),
        "replace" => Ok(CompletionTextEditMode::Replace),
        other => Err(format!(
            "invalid completion mode: {other} (expected insert|replace)"
        )),
    }
}

fn lsp_single_processing_edit_from_state_json<F>(
    state: *const EcfEditorState,
    result_json: *const c_char,
    f: F,
) -> *mut c_char
where
    F: Fn(&editor_core::LineIndex, &Value) -> ProcessingEdit,
{
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let result_json = require_string(result_json, "result_json")?;
        let value = parse_json_value(&result_json, "LSP result")?;
        let edit = f(state.inner.editor().line_index(), &value);
        Ok(value_processing_edit(&edit))
    })
}

/// Create a Sublime processor from YAML syntax text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_new_from_yaml(
    yaml: *const c_char,
) -> *mut EcfSublimeProcessor {
    result_ptr(ptr::null_mut(), || {
        let yaml = require_string(yaml, "yaml")?;
        let mut syntax_set = SublimeSyntaxSet::new();
        let syntax = syntax_set
            .load_from_str(&yaml)
            .map_err(|err| format!("failed to load syntax from YAML: {err}"))?;
        let processor = SublimeProcessor::new(syntax, syntax_set);
        Ok(Box::into_raw(Box::new(EcfSublimeProcessor {
            inner: processor,
        })))
    })
}

/// Create a Sublime processor from syntax file path.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_new_from_path(
    path: *const c_char,
) -> *mut EcfSublimeProcessor {
    result_ptr(ptr::null_mut(), || {
        let path = require_string(path, "path")?;
        let mut syntax_set = SublimeSyntaxSet::new();
        let syntax = syntax_set
            .load_from_path(&path)
            .map_err(|err| format!("failed to load syntax from path: {err}"))?;
        let processor = SublimeProcessor::new(syntax, syntax_set);
        Ok(Box::into_raw(Box::new(EcfSublimeProcessor {
            inner: processor,
        })))
    })
}

/// Destroy a Sublime processor.
///
/// # Safety
///
/// `processor` must be a valid pointer returned by a constructor in this crate, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_sublime_processor_free(
    processor: *mut EcfSublimeProcessor,
) {
    if processor.is_null() {
        return;
    }
    // SAFETY: pointer must come from a constructor in this crate.
    unsafe {
        drop(Box::from_raw(processor));
    }
}

/// Add a search path used to resolve `Packages/...` references.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_add_search_path(
    processor: *mut EcfSublimeProcessor,
    path: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let path = require_string(path, "path")?;
        processor.inner.syntax_set_mut().add_search_path(path);
        Ok(true)
    })
}

/// Load syntax YAML into processor's syntax set.
///
/// # Safety
///
/// `processor` must be a valid pointer returned by a constructor in this crate.
/// `yaml` must be a valid null-terminated UTF-8 C string pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_sublime_processor_load_syntax_from_yaml(
    processor: *mut EcfSublimeProcessor,
    yaml: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let yaml = require_string(yaml, "yaml")?;
        processor
            .inner
            .syntax_set_mut()
            .load_from_str(&yaml)
            .map_err(|err| format!("failed to load syntax from YAML: {err}"))?;
        Ok(true)
    })
}

/// Load syntax from path into processor's syntax set.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_load_syntax_from_path(
    processor: *mut EcfSublimeProcessor,
    path: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let path = require_string(path, "path")?;
        processor
            .inner
            .syntax_set_mut()
            .load_from_path(&path)
            .map_err(|err| format!("failed to load syntax from path: {err}"))?;
        Ok(true)
    })
}

/// Switch active syntax by Sublime reference.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_set_active_syntax_by_reference(
    processor: *mut EcfSublimeProcessor,
    reference: *const c_char,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let reference = require_string(reference, "reference")?;

        let preserve = processor.inner.preserve_collapsed_folds();
        let mut scope_mapper =
            std::mem::replace(&mut processor.inner.scope_mapper, SublimeScopeMapper::new());
        let mut syntax_set = std::mem::take(processor.inner.syntax_set_mut());
        let syntax = syntax_set
            .load_by_reference(&reference)
            .map_err(|err| format!("failed to load syntax by reference: {err}"))?;

        let mut next = SublimeProcessor::new(syntax, syntax_set);
        next.scope_mapper = std::mem::replace(&mut scope_mapper, SublimeScopeMapper::new());
        next.set_preserve_collapsed_folds(preserve);
        processor.inner = next;

        Ok(true)
    })
}

/// Configure whether fold replacement preserves collapsed state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_set_preserve_collapsed_folds(
    processor: *mut EcfSublimeProcessor,
    preserve: bool,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        processor.inner.set_preserve_collapsed_folds(preserve);
        Ok(true)
    })
}

/// Run Sublime processing and return generated processing edits JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_process_json(
    processor: *mut EcfSublimeProcessor,
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_mut(processor, "processor")?;
        let state = require_ref(state, "state")?;
        let edits = processor
            .inner
            .process(&state.inner)
            .map_err(|err| format!("sublime process failed: {err}"))?;
        Ok(json!({
            "edits": edits.iter().map(value_processing_edit).collect::<Vec<_>>()
        }))
    })
}

/// Run Sublime processor and apply edits to state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_apply(
    processor: *mut EcfSublimeProcessor,
    state: *mut EcfEditorState,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let state = require_mut(state, "state")?;
        state
            .inner
            .apply_processor(&mut processor.inner)
            .map_err(|err| format!("sublime apply failed: {err}"))?;
        Ok(true)
    })
}

/// Return scope string for a style id in current Sublime scope mapper.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_scope_for_style_id(
    processor: *const EcfSublimeProcessor,
    style_id: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_ref(processor, "processor")?;
        Ok(json!({
            "scope": processor.inner.scope_mapper.scope_for_style_id(style_id)
        }))
    })
}

/// Tree-sitter language function pointer type expected by this FFI.
pub type EcfTreeSitterLanguageFn = unsafe extern "C" fn() -> *const ();

/// Create a Tree-sitter processor.
///
/// `capture_styles_json` is optional object JSON: `{ "capture.name": 123, ... }`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_new(
    language_fn: Option<EcfTreeSitterLanguageFn>,
    highlights_query: *const c_char,
    folds_query: *const c_char,
    capture_styles_json: *const c_char,
    style_layer: u32,
    preserve_collapsed_folds: bool,
) -> *mut EcfTreeSitterProcessor {
    result_ptr(ptr::null_mut(), || {
        let language_fn = language_fn.ok_or_else(|| "language_fn is null".to_string())?;
        let highlights_query = require_string(highlights_query, "highlights_query")?;

        let language = tree_sitter::Language::new(unsafe {
            tree_sitter_language::LanguageFn::from_raw(language_fn)
        });

        let mut config =
            TreeSitterProcessorConfig::new(TreeSitterLanguage::native(language), highlights_query);
        if let Some(folds_query) = optional_string(folds_query, "folds_query")?
            && !folds_query.trim().is_empty()
        {
            config = config.with_folds_query(folds_query);
        }

        if let Some(capture_styles_json) =
            optional_string(capture_styles_json, "capture_styles_json")?
        {
            let capture_styles: BTreeMap<String, u32> =
                parse_json(&capture_styles_json, "capture styles")?;
            config.capture_styles = capture_styles;
        }

        config.style_layer = StyleLayerId::new(style_layer);
        config.set_preserve_collapsed_folds(preserve_collapsed_folds);

        let processor = TreeSitterProcessor::new(config)
            .map_err(|err| format!("failed to create tree-sitter processor: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterProcessor {
            inner: processor,
        })))
    })
}

/// Create a Tree-sitter WASM processor from a grammar file path.
///
/// This is useful for FFI consumers that want to avoid shipping native Tree-sitter grammars as
/// compiled-in dependencies.
///
/// `capture_styles_json` is optional object JSON: `{ "capture.name": 123, ... }`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_new_wasm_from_path(
    language_id_utf8: *const c_char,
    wasm_path_utf8: *const c_char,
    highlights_query: *const c_char,
    folds_query: *const c_char,
    capture_styles_json: *const c_char,
    style_layer: u32,
    preserve_collapsed_folds: bool,
) -> *mut EcfTreeSitterProcessor {
    result_ptr(ptr::null_mut(), || {
        let language_id = require_string(language_id_utf8, "language_id_utf8")?;
        let wasm_path = require_string(wasm_path_utf8, "wasm_path_utf8")?;
        let highlights_query = require_string(highlights_query, "highlights_query")?;

        let wasm_bytes = std::fs::read(&wasm_path)
            .map_err(|e| format!("failed to read wasm file '{}': {e}", wasm_path))?;

        let mut config = TreeSitterProcessorConfig::new(
            TreeSitterLanguage::wasm(language_id, wasm_bytes),
            highlights_query,
        );

        if let Some(folds_query) = optional_string(folds_query, "folds_query")?
            && !folds_query.trim().is_empty()
        {
            config = config.with_folds_query(folds_query);
        }

        if let Some(capture_styles_json) =
            optional_string(capture_styles_json, "capture_styles_json")?
        {
            let capture_styles: BTreeMap<String, u32> =
                parse_json(&capture_styles_json, "capture styles")?;
            config.capture_styles = capture_styles;
        }

        config.style_layer = StyleLayerId::new(style_layer);
        config.set_preserve_collapsed_folds(preserve_collapsed_folds);

        let processor = TreeSitterProcessor::new(config)
            .map_err(|err| format!("failed to create tree-sitter processor: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterProcessor {
            inner: processor,
        })))
    })
}

/// Destroy a Tree-sitter processor.
///
/// # Safety
///
/// `processor` must be a valid pointer returned by a constructor in this crate, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_treesitter_processor_free(
    processor: *mut EcfTreeSitterProcessor,
) {
    if processor.is_null() {
        return;
    }
    // SAFETY: pointer must come from constructor in this crate.
    unsafe {
        drop(Box::from_raw(processor));
    }
}

/// Run Tree-sitter processing and return generated processing edits JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_process_json(
    processor: *mut EcfTreeSitterProcessor,
    state: *const EcfEditorState,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_mut(processor, "processor")?;
        let state = require_ref(state, "state")?;
        let edits = processor
            .inner
            .process(&state.inner)
            .map_err(|err| format!("tree-sitter process failed: {err}"))?;
        Ok(json!({
            "edits": edits.iter().map(value_processing_edit).collect::<Vec<_>>()
        }))
    })
}

/// Run Tree-sitter processor and apply edits to state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_apply(
    processor: *mut EcfTreeSitterProcessor,
    state: *mut EcfEditorState,
) -> bool {
    result_bool(false, || {
        let processor = require_mut(processor, "processor")?;
        let state = require_mut(state, "state")?;
        state
            .inner
            .apply_processor(&mut processor.inner)
            .map_err(|err| format!("tree-sitter apply failed: {err}"))?;
        Ok(true)
    })
}

/// Get Tree-sitter processor last update mode.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_last_update_mode_json(
    processor: *const EcfTreeSitterProcessor,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let processor = require_ref(processor, "processor")?;
        let mode = match processor.inner.last_update_mode() {
            TreeSitterUpdateMode::Initial => "initial",
            TreeSitterUpdateMode::Incremental => "incremental",
            TreeSitterUpdateMode::FullReparse => "full_reparse",
            TreeSitterUpdateMode::Skipped => "skipped",
        };
        Ok(json!({ "mode": mode }))
    })
}

/// Create a Tree-sitter indenter from a native grammar function.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_indenter_new(
    language_fn: Option<EcfTreeSitterLanguageFn>,
    indents_query: *const c_char,
) -> *mut EcfTreeSitterIndenter {
    result_ptr(ptr::null_mut(), || {
        let language_fn = language_fn.ok_or_else(|| "language_fn is null".to_string())?;
        let indents_query = require_string(indents_query, "indents_query")?;

        let language = tree_sitter::Language::new(unsafe {
            tree_sitter_language::LanguageFn::from_raw(language_fn)
        });

        let config =
            TreeSitterIndenterConfig::new(TreeSitterLanguage::native(language), indents_query);
        let indenter = TreeSitterIndenter::new(config)
            .map_err(|err| format!("failed to create tree-sitter indenter: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterIndenter {
            inner: indenter,
        })))
    })
}

/// Create a Tree-sitter indenter from a WASM grammar file path.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_indenter_new_wasm_from_path(
    language_id_utf8: *const c_char,
    wasm_path_utf8: *const c_char,
    indents_query: *const c_char,
) -> *mut EcfTreeSitterIndenter {
    result_ptr(ptr::null_mut(), || {
        let language_id = require_string(language_id_utf8, "language_id_utf8")?;
        let wasm_path = require_string(wasm_path_utf8, "wasm_path_utf8")?;
        let indents_query = require_string(indents_query, "indents_query")?;

        let wasm_bytes = std::fs::read(&wasm_path)
            .map_err(|e| format!("failed to read wasm file '{}': {e}", wasm_path))?;

        let config = TreeSitterIndenterConfig::new(
            TreeSitterLanguage::wasm(language_id, wasm_bytes),
            indents_query,
        );
        let indenter = TreeSitterIndenter::new(config)
            .map_err(|err| format!("failed to create tree-sitter indenter: {err}"))?;

        Ok(Box::into_raw(Box::new(EcfTreeSitterIndenter {
            inner: indenter,
        })))
    })
}

/// Destroy a Tree-sitter indenter.
///
/// # Safety
///
/// `indenter` must be a valid pointer returned by a constructor in this crate, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_treesitter_indenter_free(
    indenter: *mut EcfTreeSitterIndenter,
) {
    if indenter.is_null() {
        return;
    }
    // SAFETY: pointer must come from constructor in this crate.
    unsafe {
        drop(Box::from_raw(indenter));
    }
}

/// Compute a reindent `TextEditSpec` for a given logical line using a Tree-sitter indenter.
///
/// - `indentation_config_json` is optional (nullable). When null, `IndentationConfig::default()` is used.
/// - The indenter is synchronized from the full document text on each call (skipped when the
///   editor version is unchanged).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_indenter_reindent_line_json(
    indenter: *mut EcfTreeSitterIndenter,
    state: *const EcfEditorState,
    line: u32,
    indentation_config_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let indenter = require_mut(indenter, "indenter")?;
        let state = require_ref(state, "state")?;
        let line = usize_from_u32(line, "line")?;

        let cfg = if let Some(json_text) =
            optional_string(indentation_config_json, "indentation_config_json")?
        {
            let parsed: FfiIndentationConfig = parse_json(&json_text, "indentation config")?;
            IndentationConfig::from(parsed)
        } else {
            IndentationConfig::default()
        };

        let text = state.inner.editor().get_text();
        indenter
            .inner
            .sync_to_text(state.inner.version(), &text)
            .map_err(|err| format!("treesitter indenter sync failed: {err}"))?;

        let edit = indenter
            .inner
            .reindent_text_edit_for_line(line, cfg.style.clone());

        Ok(json!({
            "has_edit": edit.is_some(),
            "edit": edit.map(|e| json!({ "start": e.start, "end": e.end, "text": e.text })),
        }))
    })
}

/// Encode semantic `(token_type, token_modifiers)` pair into default style id.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_encode_semantic_style_id(
    token_type: u32,
    token_modifiers: u32,
) -> u32 {
    match ffi_catch(|| Ok(encode_semantic_style_id(token_type, token_modifiers))) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            0
        }
    }
}

/// Return ABI version for typed/binary APIs.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_abi_version() -> u32 {
    ECF_ABI_VERSION
}

/// Fill basic document stats.
///
/// # Safety
///
/// `state` must be a valid pointer to an `EcfEditorState`.
/// `out_stats` must be a valid pointer to an `EcfDocumentStats` struct.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_editor_get_document_stats(
    state: *const EcfEditorState,
    out_stats: *mut EcfDocumentStats,
) -> i32 {
    status_result(|| {
        let state =
            require_ref(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_stats.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_stats is null".to_string()));
        }

        let doc = state.inner.get_document_state();
        let stats = EcfDocumentStats {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfDocumentStats>() as u32,
            line_count: doc.line_count as u64,
            char_count: doc.char_count as u64,
            byte_count: doc.byte_count as u64,
            is_modified: if doc.is_modified { 1 } else { 0 },
            reserved0: [0; 7],
            version: doc.version,
        };

        // SAFETY: non-null checked; caller provides writable memory for output struct.
        unsafe {
            *out_stats = stats;
        }
        Ok(())
    })
}

/// Insert UTF-8 text at current selection/cursor(s).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_insert_text_utf8(
    state: *mut EcfEditorState,
    bytes: *const u8,
    len: u32,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let text = require_utf8_bytes(bytes, len, "bytes")?.to_string();
        state
            .inner
            .execute(Command::Edit(EditCommand::InsertText { text }))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("insert_text failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Backspace at current selection/cursor(s).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_backspace(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::Backspace))
            .map_err(|err| (EcfStatus::CommandFailed, format!("backspace failed: {err}")))?;
        Ok(())
    })
}

/// Delete forward at current selection/cursor(s).
///
/// # Safety
///
/// `state` must be a valid pointer to an `EcfEditorState`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_editor_delete_forward(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::DeleteForward))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("delete_forward failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Undo one change group.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_undo(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::Undo))
            .map_err(|err| (EcfStatus::CommandFailed, format!("undo failed: {err}")))?;
        Ok(())
    })
}

/// Redo one change group.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_redo(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::Redo))
            .map_err(|err| (EcfStatus::CommandFailed, format!("redo failed: {err}")))?;
        Ok(())
    })
}

/// Move cursor to a logical `(line, column)` position.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_move_to(
    state: *mut EcfEditorState,
    line: u32,
    column: u32,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let line = status_usize_from_u32(line, "line")?;
        let column = status_usize_from_u32(column, "column")?;
        state
            .inner
            .execute(Command::Cursor(CursorCommand::MoveTo { line, column }))
            .map_err(|err| (EcfStatus::CommandFailed, format!("move_to failed: {err}")))?;
        Ok(())
    })
}

/// Move cursor by deltas in logical line/column space.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_move_by(
    state: *mut EcfEditorState,
    delta_line: i32,
    delta_column: i32,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Cursor(CursorCommand::MoveBy {
                delta_line: delta_line as isize,
                delta_column: delta_column as isize,
            }))
            .map_err(|err| (EcfStatus::CommandFailed, format!("move_by failed: {err}")))?;
        Ok(())
    })
}

/// Set primary selection with explicit direction (`0=forward`, `1=backward`).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_set_selection(
    state: *mut EcfEditorState,
    start_line: u32,
    start_column: u32,
    end_line: u32,
    end_column: u32,
    direction: u8,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let start_line = status_usize_from_u32(start_line, "start_line")?;
        let start_column = status_usize_from_u32(start_column, "start_column")?;
        let end_line = status_usize_from_u32(end_line, "end_line")?;
        let end_column = status_usize_from_u32(end_column, "end_column")?;
        let direction = match direction {
            0 => SelectionDirection::Forward,
            1 => SelectionDirection::Backward,
            _ => {
                return Err((
                    EcfStatus::InvalidArgument,
                    "direction must be 0 (forward) or 1 (backward)".to_string(),
                ));
            }
        };

        let selection = Selection {
            start: Position::new(start_line, start_column),
            end: Position::new(end_line, end_column),
            direction,
        };

        state
            .inner
            .execute(Command::Cursor(CursorCommand::SetSelections {
                selections: vec![selection],
                primary_index: 0,
            }))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("set_selection failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Clear selection (collapse to caret).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_clear_selection(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Cursor(CursorCommand::ClearSelection))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("clear_selection failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Workspace variant: insert UTF-8 text in a specific view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_insert_text_utf8(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    bytes: *const u8,
    len: u32,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let text = require_utf8_bytes(bytes, len, "bytes")?.to_string();
        workspace
            .inner
            .execute(
                ViewId::from_raw(view_id),
                Command::Edit(EditCommand::InsertText { text }),
            )
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("workspace insert_text failed: {err:?}"),
                )
            })?;
        Ok(())
    })
}

/// Workspace variant: move cursor in a specific view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_move_to(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    line: u32,
    column: u32,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let line = status_usize_from_u32(line, "line")?;
        let column = status_usize_from_u32(column, "column")?;
        workspace
            .inner
            .execute(
                ViewId::from_raw(view_id),
                Command::Cursor(CursorCommand::MoveTo { line, column }),
            )
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("workspace move_to failed: {err:?}"),
                )
            })?;
        Ok(())
    })
}

/// Workspace variant: backspace in a specific view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_backspace(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        workspace
            .inner
            .execute(
                ViewId::from_raw(view_id),
                Command::Edit(EditCommand::Backspace),
            )
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("workspace backspace failed: {err:?}"),
                )
            })?;
        Ok(())
    })
}

/// Retrieve styled viewport snapshot as ABI-v1 binary blob.
///
/// Returns `ECF_ERR_BUFFER_TOO_SMALL` and writes required size to `out_len` when `out_cap` is
/// insufficient (or `out_buf` is null).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_get_viewport_blob(
    state: *const EcfEditorState,
    start_visual_row: u32,
    row_count: u32,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> i32 {
    status_result(|| {
        let state =
            require_ref(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let start_visual_row = status_usize_from_u32(start_visual_row, "start_visual_row")?;
        let row_count = status_usize_from_u32(row_count, "row_count")?;
        let grid = state
            .inner
            .get_viewport_content_styled(start_visual_row, row_count);
        let blob = build_viewport_blob(&grid)?;
        copy_blob_to_output(&blob, out_buf, out_cap, out_len)
    })
}

/// Workspace variant of `editor_core_ffi_editor_get_viewport_blob`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_get_viewport_blob(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    row_count: u32,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let start_visual_row = status_usize_from_u32(start_visual_row, "start_visual_row")?;
        let row_count = status_usize_from_u32(row_count, "row_count")?;
        let grid = workspace
            .inner
            .get_viewport_content_styled(ViewId::from_raw(view_id), start_visual_row, row_count)
            .map_err(|err| {
                (
                    EcfStatus::NotFound,
                    format!("get_viewport_content_styled failed: {err:?}"),
                )
            })?;
        let blob = build_viewport_blob(&grid)?;
        copy_blob_to_output(&blob, out_buf, out_cap, out_len)
    })
}

/// ABI-v1 alias: see `editor_core_ffi_abi_version`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_abi_version() -> u32 {
    editor_core_ffi_abi_version()
}

/// ABI-v1 alias: see `editor_core_ffi_editor_insert_text_utf8`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_insert_text_utf8(
    state: *mut EcfEditorState,
    bytes: *const u8,
    len: u32,
) -> i32 {
    editor_core_ffi_editor_insert_text_utf8(state, bytes, len)
}

/// ABI-v1 alias: see `editor_core_ffi_editor_move_to`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_move_to(state: *mut EcfEditorState, line: u32, column: u32) -> i32 {
    editor_core_ffi_editor_move_to(state, line, column)
}

/// ABI-v1 alias: see `editor_core_ffi_editor_backspace`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_backspace(state: *mut EcfEditorState) -> i32 {
    editor_core_ffi_editor_backspace(state)
}

/// ABI-v1 alias: see `editor_core_ffi_editor_get_viewport_blob`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_get_viewport_blob(
    state: *const EcfEditorState,
    start_visual_row: u32,
    row_count: u32,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> i32 {
    editor_core_ffi_editor_get_viewport_blob(
        state,
        start_visual_row,
        row_count,
        out_buf,
        out_cap,
        out_len,
    )
}
