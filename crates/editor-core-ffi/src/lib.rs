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
use editor_core::intervals::{FoldRegion, Interval, StyleLayerId};
use editor_core::layout::{WrapIndent, WrapMode};
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
use editor_core::{LineEnding, SearchMatch, SearchOptions};
use editor_core_lsp::{
    CompletionTextEditMode, LspCoordinateConverter, apply_completion_item, apply_text_edits,
    completion_item_to_text_edit_specs, decode_semantic_style_id, encode_semantic_style_id,
    file_uri_to_path, locations_from_value, lsp_code_lens_to_processing_edit,
    lsp_diagnostics_to_processing_edits, lsp_document_highlights_to_processing_edit,
    lsp_document_links_to_processing_edit, lsp_document_symbols_to_processing_edit,
    lsp_inlay_hints_to_processing_edit, lsp_workspace_symbols_to_results, path_to_file_uri,
    percent_decode_path, percent_encode_path, semantic_tokens_to_intervals, text_edits_from_value,
};
use editor_core_sublime::{SublimeProcessor, SublimeScopeMapper, SublimeSyntaxSet};
use editor_core_treesitter::{
    TreeSitterProcessor, TreeSitterProcessorConfig, TreeSitterUpdateMode,
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

fn line_ending_from_str(s: &str) -> Result<LineEnding, String> {
    match s.trim().to_ascii_lowercase().as_str() {
        "lf" => Ok(LineEnding::Lf),
        "crlf" => Ok(LineEnding::Crlf),
        other => Err(format!(
            "unsupported line ending: {other} (expected lf|crlf)"
        )),
    }
}

fn line_ending_to_str(line_ending: LineEnding) -> &'static str {
    match line_ending {
        LineEnding::Lf => "lf",
        LineEnding::Crlf => "crlf",
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiPosition {
    line: usize,
    column: usize,
}

impl From<FfiPosition> for Position {
    fn from(value: FfiPosition) -> Self {
        Position::new(value.line, value.column)
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FfiSelectionDirection {
    Forward,
    Backward,
}

impl From<FfiSelectionDirection> for SelectionDirection {
    fn from(value: FfiSelectionDirection) -> Self {
        match value {
            FfiSelectionDirection::Forward => SelectionDirection::Forward,
            FfiSelectionDirection::Backward => SelectionDirection::Backward,
        }
    }
}

fn selection_direction_to_str(direction: SelectionDirection) -> &'static str {
    match direction {
        SelectionDirection::Forward => "forward",
        SelectionDirection::Backward => "backward",
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiSelection {
    start: FfiPosition,
    end: FfiPosition,
    direction: FfiSelectionDirection,
}

impl From<FfiSelection> for Selection {
    fn from(value: FfiSelection) -> Self {
        Selection {
            start: value.start.into(),
            end: value.end.into(),
            direction: value.direction.into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiTextEditSpec {
    start: usize,
    end: usize,
    text: String,
}

impl From<FfiTextEditSpec> for TextEditSpec {
    fn from(value: FfiTextEditSpec) -> Self {
        TextEditSpec {
            start: value.start,
            end: value.end,
            text: value.text,
        }
    }
}

fn default_case_sensitive() -> bool {
    true
}

#[derive(Debug, Clone, Copy, Deserialize)]
struct FfiSearchOptions {
    #[serde(default = "default_case_sensitive")]
    case_sensitive: bool,
    #[serde(default)]
    whole_word: bool,
    #[serde(default)]
    regex: bool,
}

impl Default for FfiSearchOptions {
    fn default() -> Self {
        Self {
            case_sensitive: true,
            whole_word: false,
            regex: false,
        }
    }
}

impl From<FfiSearchOptions> for SearchOptions {
    fn from(value: FfiSearchOptions) -> Self {
        SearchOptions {
            case_sensitive: value.case_sensitive,
            whole_word: value.whole_word,
            regex: value.regex,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiCommentConfig {
    line: Option<String>,
    block_start: Option<String>,
    block_end: Option<String>,
}

impl From<FfiCommentConfig> for editor_core::CommentConfig {
    fn from(value: FfiCommentConfig) -> Self {
        editor_core::CommentConfig {
            line: value.line,
            block_start: value.block_start,
            block_end: value.block_end,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FfiTabKeyBehavior {
    Tab,
    Spaces,
}

impl From<FfiTabKeyBehavior> for TabKeyBehavior {
    fn from(value: FfiTabKeyBehavior) -> Self {
        match value {
            FfiTabKeyBehavior::Tab => TabKeyBehavior::Tab,
            FfiTabKeyBehavior::Spaces => TabKeyBehavior::Spaces,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FfiWrapMode {
    None,
    Char,
    Word,
}

impl From<FfiWrapMode> for WrapMode {
    fn from(value: FfiWrapMode) -> Self {
        match value {
            FfiWrapMode::None => WrapMode::None,
            FfiWrapMode::Char => WrapMode::Char,
            FfiWrapMode::Word => WrapMode::Word,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum FfiWrapIndent {
    None,
    SameAsLineIndent,
    FixedCells { cells: usize },
}

impl From<FfiWrapIndent> for WrapIndent {
    fn from(value: FfiWrapIndent) -> Self {
        match value {
            FfiWrapIndent::None => WrapIndent::None,
            FfiWrapIndent::SameAsLineIndent => WrapIndent::SameAsLineIndent,
            FfiWrapIndent::FixedCells { cells } => WrapIndent::FixedCells(cells),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum FfiCommandInput {
    Edit {
        #[serde(flatten)]
        op: FfiEditCommandInput,
    },
    Cursor {
        #[serde(flatten)]
        op: FfiCursorCommandInput,
    },
    View {
        #[serde(flatten)]
        op: FfiViewCommandInput,
    },
    Style {
        #[serde(flatten)]
        op: FfiStyleCommandInput,
    },
}

impl FfiCommandInput {
    fn into_core(self) -> Command {
        match self {
            Self::Edit { op } => Command::Edit(op.into_core()),
            Self::Cursor { op } => Command::Cursor(op.into_core()),
            Self::View { op } => Command::View(op.into_core()),
            Self::Style { op } => Command::Style(op.into_core()),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum FfiEditCommandInput {
    Insert {
        offset: usize,
        text: String,
    },
    Delete {
        start: usize,
        length: usize,
    },
    Replace {
        start: usize,
        length: usize,
        text: String,
    },
    InsertText {
        text: String,
    },
    InsertTab,
    InsertNewline {
        #[serde(default)]
        auto_indent: bool,
    },
    Indent,
    Outdent,
    DuplicateLines,
    DeleteLines,
    MoveLinesUp,
    MoveLinesDown,
    JoinLines,
    SplitLine,
    ToggleComment {
        config: FfiCommentConfig,
    },
    ApplyTextEdits {
        edits: Vec<FfiTextEditSpec>,
    },
    DeleteToPrevTabStop,
    DeleteGraphemeBack,
    DeleteGraphemeForward,
    DeleteWordBack,
    DeleteWordForward,
    Backspace,
    DeleteForward,
    Undo,
    Redo,
    EndUndoGroup,
    ReplaceCurrent {
        query: String,
        replacement: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
    ReplaceAll {
        query: String,
        replacement: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
}

impl FfiEditCommandInput {
    fn into_core(self) -> EditCommand {
        match self {
            Self::Insert { offset, text } => EditCommand::Insert { offset, text },
            Self::Delete { start, length } => EditCommand::Delete { start, length },
            Self::Replace {
                start,
                length,
                text,
            } => EditCommand::Replace {
                start,
                length,
                text,
            },
            Self::InsertText { text } => EditCommand::InsertText { text },
            Self::InsertTab => EditCommand::InsertTab,
            Self::InsertNewline { auto_indent } => EditCommand::InsertNewline { auto_indent },
            Self::Indent => EditCommand::Indent,
            Self::Outdent => EditCommand::Outdent,
            Self::DuplicateLines => EditCommand::DuplicateLines,
            Self::DeleteLines => EditCommand::DeleteLines,
            Self::MoveLinesUp => EditCommand::MoveLinesUp,
            Self::MoveLinesDown => EditCommand::MoveLinesDown,
            Self::JoinLines => EditCommand::JoinLines,
            Self::SplitLine => EditCommand::SplitLine,
            Self::ToggleComment { config } => EditCommand::ToggleComment {
                config: config.into(),
            },
            Self::ApplyTextEdits { edits } => EditCommand::ApplyTextEdits {
                edits: edits.into_iter().map(Into::into).collect(),
            },
            Self::DeleteToPrevTabStop => EditCommand::DeleteToPrevTabStop,
            Self::DeleteGraphemeBack => EditCommand::DeleteGraphemeBack,
            Self::DeleteGraphemeForward => EditCommand::DeleteGraphemeForward,
            Self::DeleteWordBack => EditCommand::DeleteWordBack,
            Self::DeleteWordForward => EditCommand::DeleteWordForward,
            Self::Backspace => EditCommand::Backspace,
            Self::DeleteForward => EditCommand::DeleteForward,
            Self::Undo => EditCommand::Undo,
            Self::Redo => EditCommand::Redo,
            Self::EndUndoGroup => EditCommand::EndUndoGroup,
            Self::ReplaceCurrent {
                query,
                replacement,
                options,
            } => EditCommand::ReplaceCurrent {
                query,
                replacement,
                options: options.into(),
            },
            Self::ReplaceAll {
                query,
                replacement,
                options,
            } => EditCommand::ReplaceAll {
                query,
                replacement,
                options: options.into(),
            },
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FfiExpandSelectionUnit {
    Character,
    Word,
    Line,
}

impl From<FfiExpandSelectionUnit> for ExpandSelectionUnit {
    fn from(value: FfiExpandSelectionUnit) -> Self {
        match value {
            FfiExpandSelectionUnit::Character => ExpandSelectionUnit::Character,
            FfiExpandSelectionUnit::Word => ExpandSelectionUnit::Word,
            FfiExpandSelectionUnit::Line => ExpandSelectionUnit::Line,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FfiExpandSelectionDirection {
    Backward,
    Forward,
}

impl From<FfiExpandSelectionDirection> for ExpandSelectionDirection {
    fn from(value: FfiExpandSelectionDirection) -> Self {
        match value {
            FfiExpandSelectionDirection::Backward => ExpandSelectionDirection::Backward,
            FfiExpandSelectionDirection::Forward => ExpandSelectionDirection::Forward,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum FfiCursorCommandInput {
    MoveTo {
        line: usize,
        column: usize,
    },
    MoveBy {
        delta_line: isize,
        delta_column: isize,
    },
    MoveVisualBy {
        delta_rows: isize,
    },
    MoveToVisual {
        row: usize,
        x_cells: usize,
    },
    MoveToLineStart,
    MoveToLineEnd,
    MoveToVisualLineStart,
    MoveToVisualLineEnd,
    MoveGraphemeLeft,
    MoveGraphemeRight,
    MoveWordLeft,
    MoveWordRight,
    SetSelection {
        start: FfiPosition,
        end: FfiPosition,
    },
    ExtendSelection {
        to: FfiPosition,
    },
    ClearSelection,
    SetSelections {
        selections: Vec<FfiSelection>,
        primary_index: usize,
    },
    ClearSecondarySelections,
    SetRectSelection {
        anchor: FfiPosition,
        active: FfiPosition,
    },
    SelectLine,
    SelectWord,
    ExpandSelection,
    ExpandSelectionBy {
        unit: FfiExpandSelectionUnit,
        count: usize,
        direction: FfiExpandSelectionDirection,
    },
    AddCursorAbove,
    AddCursorBelow,
    AddNextOccurrence {
        #[serde(default)]
        options: FfiSearchOptions,
    },
    AddAllOccurrences {
        #[serde(default)]
        options: FfiSearchOptions,
    },
    FindNext {
        query: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
    FindPrev {
        query: String,
        #[serde(default)]
        options: FfiSearchOptions,
    },
}

impl FfiCursorCommandInput {
    fn into_core(self) -> CursorCommand {
        match self {
            Self::MoveTo { line, column } => CursorCommand::MoveTo { line, column },
            Self::MoveBy {
                delta_line,
                delta_column,
            } => CursorCommand::MoveBy {
                delta_line,
                delta_column,
            },
            Self::MoveVisualBy { delta_rows } => CursorCommand::MoveVisualBy { delta_rows },
            Self::MoveToVisual { row, x_cells } => CursorCommand::MoveToVisual { row, x_cells },
            Self::MoveToLineStart => CursorCommand::MoveToLineStart,
            Self::MoveToLineEnd => CursorCommand::MoveToLineEnd,
            Self::MoveToVisualLineStart => CursorCommand::MoveToVisualLineStart,
            Self::MoveToVisualLineEnd => CursorCommand::MoveToVisualLineEnd,
            Self::MoveGraphemeLeft => CursorCommand::MoveGraphemeLeft,
            Self::MoveGraphemeRight => CursorCommand::MoveGraphemeRight,
            Self::MoveWordLeft => CursorCommand::MoveWordLeft,
            Self::MoveWordRight => CursorCommand::MoveWordRight,
            Self::SetSelection { start, end } => CursorCommand::SetSelection {
                start: start.into(),
                end: end.into(),
            },
            Self::ExtendSelection { to } => CursorCommand::ExtendSelection { to: to.into() },
            Self::ClearSelection => CursorCommand::ClearSelection,
            Self::SetSelections {
                selections,
                primary_index,
            } => CursorCommand::SetSelections {
                selections: selections.into_iter().map(Into::into).collect(),
                primary_index,
            },
            Self::ClearSecondarySelections => CursorCommand::ClearSecondarySelections,
            Self::SetRectSelection { anchor, active } => CursorCommand::SetRectSelection {
                anchor: anchor.into(),
                active: active.into(),
            },
            Self::SelectLine => CursorCommand::SelectLine,
            Self::SelectWord => CursorCommand::SelectWord,
            Self::ExpandSelection => CursorCommand::ExpandSelection,
            Self::ExpandSelectionBy {
                unit,
                count,
                direction,
            } => CursorCommand::ExpandSelectionBy {
                unit: unit.into(),
                count,
                direction: direction.into(),
            },
            Self::AddCursorAbove => CursorCommand::AddCursorAbove,
            Self::AddCursorBelow => CursorCommand::AddCursorBelow,
            Self::AddNextOccurrence { options } => CursorCommand::AddNextOccurrence {
                options: options.into(),
            },
            Self::AddAllOccurrences { options } => CursorCommand::AddAllOccurrences {
                options: options.into(),
            },
            Self::FindNext { query, options } => CursorCommand::FindNext {
                query,
                options: options.into(),
            },
            Self::FindPrev { query, options } => CursorCommand::FindPrev {
                query,
                options: options.into(),
            },
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum FfiViewCommandInput {
    SetViewportWidth { width: usize },
    SetWrapMode { mode: FfiWrapMode },
    SetWrapIndent { indent: FfiWrapIndent },
    SetTabWidth { width: usize },
    SetTabKeyBehavior { behavior: FfiTabKeyBehavior },
    SetWordBoundaryAsciiBoundaryChars { boundary_chars: String },
    ResetWordBoundaryDefaults,
    ScrollTo { line: usize },
    GetViewport { start_row: usize, count: usize },
}

impl FfiViewCommandInput {
    fn into_core(self) -> ViewCommand {
        match self {
            Self::SetViewportWidth { width } => ViewCommand::SetViewportWidth { width },
            Self::SetWrapMode { mode } => ViewCommand::SetWrapMode { mode: mode.into() },
            Self::SetWrapIndent { indent } => ViewCommand::SetWrapIndent {
                indent: indent.into(),
            },
            Self::SetTabWidth { width } => ViewCommand::SetTabWidth { width },
            Self::SetTabKeyBehavior { behavior } => ViewCommand::SetTabKeyBehavior {
                behavior: behavior.into(),
            },
            Self::SetWordBoundaryAsciiBoundaryChars { boundary_chars } => {
                ViewCommand::SetWordBoundaryAsciiBoundaryChars { boundary_chars }
            }
            Self::ResetWordBoundaryDefaults => ViewCommand::ResetWordBoundaryDefaults,
            Self::ScrollTo { line } => ViewCommand::ScrollTo { line },
            Self::GetViewport { start_row, count } => ViewCommand::GetViewport { start_row, count },
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum FfiStyleCommandInput {
    AddStyle {
        start: usize,
        end: usize,
        style_id: u32,
    },
    RemoveStyle {
        start: usize,
        end: usize,
        style_id: u32,
    },
    Fold {
        start_line: usize,
        end_line: usize,
    },
    Unfold {
        start_line: usize,
    },
    UnfoldAll,
}

impl FfiStyleCommandInput {
    fn into_core(self) -> StyleCommand {
        match self {
            Self::AddStyle {
                start,
                end,
                style_id,
            } => StyleCommand::AddStyle {
                start,
                end,
                style_id,
            },
            Self::RemoveStyle {
                start,
                end,
                style_id,
            } => StyleCommand::RemoveStyle {
                start,
                end,
                style_id,
            },
            Self::Fold {
                start_line,
                end_line,
            } => StyleCommand::Fold {
                start_line,
                end_line,
            },
            Self::Unfold { start_line } => StyleCommand::Unfold { start_line },
            Self::UnfoldAll => StyleCommand::UnfoldAll,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiIntervalInput {
    start: usize,
    end: usize,
    style_id: u32,
}

impl From<FfiIntervalInput> for Interval {
    fn from(value: FfiIntervalInput) -> Self {
        Interval::new(value.start, value.end, value.style_id)
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiFoldRegionInput {
    start_line: usize,
    end_line: usize,
    #[serde(default)]
    is_collapsed: bool,
    #[serde(default = "default_fold_placeholder")]
    placeholder: String,
}

fn default_fold_placeholder() -> String {
    "[...]".to_string()
}

impl From<FfiFoldRegionInput> for FoldRegion {
    fn from(value: FfiFoldRegionInput) -> Self {
        FoldRegion {
            start_line: value.start_line,
            end_line: value.end_line,
            is_collapsed: value.is_collapsed,
            placeholder: value.placeholder,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FfiDiagnosticSeverity {
    Error,
    Warning,
    Information,
    Hint,
}

impl From<FfiDiagnosticSeverity> for DiagnosticSeverity {
    fn from(value: FfiDiagnosticSeverity) -> Self {
        match value {
            FfiDiagnosticSeverity::Error => DiagnosticSeverity::Error,
            FfiDiagnosticSeverity::Warning => DiagnosticSeverity::Warning,
            FfiDiagnosticSeverity::Information => DiagnosticSeverity::Information,
            FfiDiagnosticSeverity::Hint => DiagnosticSeverity::Hint,
        }
    }
}

fn diagnostic_severity_to_str(value: DiagnosticSeverity) -> &'static str {
    match value {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Information => "information",
        DiagnosticSeverity::Hint => "hint",
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiDiagnosticInput {
    range: FfiOffsetRange,
    severity: Option<FfiDiagnosticSeverity>,
    code: Option<String>,
    source: Option<String>,
    message: String,
    related_information_json: Option<String>,
    data_json: Option<String>,
}

impl From<FfiDiagnosticInput> for Diagnostic {
    fn from(value: FfiDiagnosticInput) -> Self {
        Diagnostic {
            range: DiagnosticRange::new(value.range.start, value.range.end),
            severity: value.severity.map(Into::into),
            code: value.code,
            source: value.source,
            message: value.message,
            related_information_json: value.related_information_json,
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FfiDecorationPlacement {
    Before,
    After,
    AboveLine,
}

impl From<FfiDecorationPlacement> for DecorationPlacement {
    fn from(value: FfiDecorationPlacement) -> Self {
        match value {
            FfiDecorationPlacement::Before => DecorationPlacement::Before,
            FfiDecorationPlacement::After => DecorationPlacement::After,
            FfiDecorationPlacement::AboveLine => DecorationPlacement::AboveLine,
        }
    }
}

fn decoration_placement_to_str(value: DecorationPlacement) -> &'static str {
    match value {
        DecorationPlacement::Before => "before",
        DecorationPlacement::After => "after",
        DecorationPlacement::AboveLine => "above_line",
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
enum FfiDecorationKind {
    InlayHint,
    CodeLens,
    DocumentLink,
    Highlight,
    Custom(u32),
}

impl From<FfiDecorationKind> for DecorationKind {
    fn from(value: FfiDecorationKind) -> Self {
        match value {
            FfiDecorationKind::InlayHint => DecorationKind::InlayHint,
            FfiDecorationKind::CodeLens => DecorationKind::CodeLens,
            FfiDecorationKind::DocumentLink => DecorationKind::DocumentLink,
            FfiDecorationKind::Highlight => DecorationKind::Highlight,
            FfiDecorationKind::Custom(v) => DecorationKind::Custom(v),
        }
    }
}

fn decoration_kind_to_json(value: DecorationKind) -> Value {
    match value {
        DecorationKind::InlayHint => json!({ "kind": "inlay_hint" }),
        DecorationKind::CodeLens => json!({ "kind": "code_lens" }),
        DecorationKind::DocumentLink => json!({ "kind": "document_link" }),
        DecorationKind::Highlight => json!({ "kind": "highlight" }),
        DecorationKind::Custom(v) => json!({ "kind": "custom", "value": v }),
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiDecorationInput {
    range: FfiOffsetRange,
    placement: FfiDecorationPlacement,
    kind: FfiDecorationKind,
    text: Option<String>,
    #[serde(default)]
    styles: Vec<u32>,
    tooltip: Option<String>,
    data_json: Option<String>,
}

impl From<FfiDecorationInput> for Decoration {
    fn from(value: FfiDecorationInput) -> Self {
        Decoration {
            range: DecorationRange::new(value.range.start, value.range.end),
            placement: value.placement.into(),
            kind: value.kind.into(),
            text: value.text,
            styles: value.styles,
            tooltip: value.tooltip,
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
enum FfiSymbolKind {
    File,
    Module,
    Namespace,
    Package,
    Class,
    Method,
    Property,
    Field,
    Constructor,
    Enum,
    Interface,
    Function,
    Variable,
    Constant,
    String,
    Number,
    Boolean,
    Array,
    Object,
    Key,
    Null,
    EnumMember,
    Struct,
    Event,
    Operator,
    TypeParameter,
    Custom(u32),
}

impl From<FfiSymbolKind> for SymbolKind {
    fn from(value: FfiSymbolKind) -> Self {
        match value {
            FfiSymbolKind::File => SymbolKind::File,
            FfiSymbolKind::Module => SymbolKind::Module,
            FfiSymbolKind::Namespace => SymbolKind::Namespace,
            FfiSymbolKind::Package => SymbolKind::Package,
            FfiSymbolKind::Class => SymbolKind::Class,
            FfiSymbolKind::Method => SymbolKind::Method,
            FfiSymbolKind::Property => SymbolKind::Property,
            FfiSymbolKind::Field => SymbolKind::Field,
            FfiSymbolKind::Constructor => SymbolKind::Constructor,
            FfiSymbolKind::Enum => SymbolKind::Enum,
            FfiSymbolKind::Interface => SymbolKind::Interface,
            FfiSymbolKind::Function => SymbolKind::Function,
            FfiSymbolKind::Variable => SymbolKind::Variable,
            FfiSymbolKind::Constant => SymbolKind::Constant,
            FfiSymbolKind::String => SymbolKind::String,
            FfiSymbolKind::Number => SymbolKind::Number,
            FfiSymbolKind::Boolean => SymbolKind::Boolean,
            FfiSymbolKind::Array => SymbolKind::Array,
            FfiSymbolKind::Object => SymbolKind::Object,
            FfiSymbolKind::Key => SymbolKind::Key,
            FfiSymbolKind::Null => SymbolKind::Null,
            FfiSymbolKind::EnumMember => SymbolKind::EnumMember,
            FfiSymbolKind::Struct => SymbolKind::Struct,
            FfiSymbolKind::Event => SymbolKind::Event,
            FfiSymbolKind::Operator => SymbolKind::Operator,
            FfiSymbolKind::TypeParameter => SymbolKind::TypeParameter,
            FfiSymbolKind::Custom(v) => SymbolKind::Custom(v),
        }
    }
}

fn symbol_kind_to_json(value: SymbolKind) -> Value {
    match value {
        SymbolKind::File => json!({ "kind": "file" }),
        SymbolKind::Module => json!({ "kind": "module" }),
        SymbolKind::Namespace => json!({ "kind": "namespace" }),
        SymbolKind::Package => json!({ "kind": "package" }),
        SymbolKind::Class => json!({ "kind": "class" }),
        SymbolKind::Method => json!({ "kind": "method" }),
        SymbolKind::Property => json!({ "kind": "property" }),
        SymbolKind::Field => json!({ "kind": "field" }),
        SymbolKind::Constructor => json!({ "kind": "constructor" }),
        SymbolKind::Enum => json!({ "kind": "enum" }),
        SymbolKind::Interface => json!({ "kind": "interface" }),
        SymbolKind::Function => json!({ "kind": "function" }),
        SymbolKind::Variable => json!({ "kind": "variable" }),
        SymbolKind::Constant => json!({ "kind": "constant" }),
        SymbolKind::String => json!({ "kind": "string" }),
        SymbolKind::Number => json!({ "kind": "number" }),
        SymbolKind::Boolean => json!({ "kind": "boolean" }),
        SymbolKind::Array => json!({ "kind": "array" }),
        SymbolKind::Object => json!({ "kind": "object" }),
        SymbolKind::Key => json!({ "kind": "key" }),
        SymbolKind::Null => json!({ "kind": "null" }),
        SymbolKind::EnumMember => json!({ "kind": "enum_member" }),
        SymbolKind::Struct => json!({ "kind": "struct" }),
        SymbolKind::Event => json!({ "kind": "event" }),
        SymbolKind::Operator => json!({ "kind": "operator" }),
        SymbolKind::TypeParameter => json!({ "kind": "type_parameter" }),
        SymbolKind::Custom(v) => json!({ "kind": "custom", "value": v }),
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiOffsetRange {
    start: usize,
    end: usize,
}

#[derive(Debug, Clone, Deserialize)]
struct FfiUtf16Position {
    line: u32,
    character: u32,
}

impl From<FfiUtf16Position> for Utf16Position {
    fn from(value: FfiUtf16Position) -> Self {
        Utf16Position::new(value.line, value.character)
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiUtf16Range {
    start: FfiUtf16Position,
    end: FfiUtf16Position,
}

impl From<FfiUtf16Range> for Utf16Range {
    fn from(value: FfiUtf16Range) -> Self {
        Utf16Range::new(value.start.into(), value.end.into())
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiSymbolLocation {
    uri: String,
    range: FfiUtf16Range,
}

impl From<FfiSymbolLocation> for SymbolLocation {
    fn from(value: FfiSymbolLocation) -> Self {
        SymbolLocation {
            uri: value.uri,
            range: value.range.into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiDocumentSymbolInput {
    name: String,
    detail: Option<String>,
    kind: FfiSymbolKind,
    range: FfiOffsetRange,
    selection_range: FfiOffsetRange,
    #[serde(default)]
    children: Vec<FfiDocumentSymbolInput>,
    data_json: Option<String>,
}

impl From<FfiDocumentSymbolInput> for DocumentSymbol {
    fn from(value: FfiDocumentSymbolInput) -> Self {
        DocumentSymbol {
            name: value.name,
            detail: value.detail,
            kind: value.kind.into(),
            range: SymbolRange::new(value.range.start, value.range.end),
            selection_range: SymbolRange::new(
                value.selection_range.start,
                value.selection_range.end,
            ),
            children: value.children.into_iter().map(Into::into).collect(),
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FfiWorkspaceSymbolInput {
    name: String,
    detail: Option<String>,
    kind: FfiSymbolKind,
    location: FfiSymbolLocation,
    container_name: Option<String>,
    data_json: Option<String>,
}

impl From<FfiWorkspaceSymbolInput> for WorkspaceSymbol {
    fn from(value: FfiWorkspaceSymbolInput) -> Self {
        WorkspaceSymbol {
            name: value.name,
            detail: value.detail,
            kind: value.kind.into(),
            location: value.location.into(),
            container_name: value.container_name,
            data_json: value.data_json,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum FfiProcessingEditInput {
    ReplaceStyleLayer {
        layer: u32,
        intervals: Vec<FfiIntervalInput>,
    },
    ClearStyleLayer {
        layer: u32,
    },
    ReplaceFoldingRegions {
        regions: Vec<FfiFoldRegionInput>,
        #[serde(default)]
        preserve_collapsed: bool,
    },
    ClearFoldingRegions,
    ReplaceDiagnostics {
        diagnostics: Vec<FfiDiagnosticInput>,
    },
    ClearDiagnostics,
    ReplaceDecorations {
        layer: u32,
        decorations: Vec<FfiDecorationInput>,
    },
    ClearDecorations {
        layer: u32,
    },
    ReplaceDocumentSymbols {
        symbols: Vec<FfiDocumentSymbolInput>,
    },
    ClearDocumentSymbols,
}

impl FfiProcessingEditInput {
    fn into_core(self) -> ProcessingEdit {
        match self {
            Self::ReplaceStyleLayer { layer, intervals } => ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::new(layer),
                intervals: intervals.into_iter().map(Into::into).collect(),
            },
            Self::ClearStyleLayer { layer } => ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::new(layer),
            },
            Self::ReplaceFoldingRegions {
                regions,
                preserve_collapsed,
            } => ProcessingEdit::ReplaceFoldingRegions {
                regions: regions.into_iter().map(Into::into).collect(),
                preserve_collapsed,
            },
            Self::ClearFoldingRegions => ProcessingEdit::ClearFoldingRegions,
            Self::ReplaceDiagnostics { diagnostics } => ProcessingEdit::ReplaceDiagnostics {
                diagnostics: diagnostics.into_iter().map(Into::into).collect(),
            },
            Self::ClearDiagnostics => ProcessingEdit::ClearDiagnostics,
            Self::ReplaceDecorations { layer, decorations } => ProcessingEdit::ReplaceDecorations {
                layer: DecorationLayerId::new(layer),
                decorations: decorations.into_iter().map(Into::into).collect(),
            },
            Self::ClearDecorations { layer } => ProcessingEdit::ClearDecorations {
                layer: DecorationLayerId::new(layer),
            },
            Self::ReplaceDocumentSymbols { symbols } => ProcessingEdit::ReplaceDocumentSymbols {
                symbols: DocumentOutline::new(symbols.into_iter().map(Into::into).collect()),
            },
            Self::ClearDocumentSymbols => ProcessingEdit::ClearDocumentSymbols,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
enum FfiProcessingEditsInput {
    One(FfiProcessingEditInput),
    Many(Vec<FfiProcessingEditInput>),
}

impl FfiProcessingEditsInput {
    fn into_core(self) -> Vec<ProcessingEdit> {
        match self {
            Self::One(edit) => vec![edit.into_core()],
            Self::Many(edits) => edits
                .into_iter()
                .map(FfiProcessingEditInput::into_core)
                .collect(),
        }
    }
}

fn value_position(value: Position) -> Value {
    json!({ "line": value.line, "column": value.column })
}

fn value_selection(value: &Selection) -> Value {
    json!({
        "start": value_position(value.start),
        "end": value_position(value.end),
        "direction": selection_direction_to_str(value.direction)
    })
}

fn value_offset_range(start: usize, end: usize) -> Value {
    json!({ "start": start, "end": end })
}

fn value_utf16_position(value: Utf16Position) -> Value {
    json!({ "line": value.line, "character": value.character })
}

fn value_utf16_range(value: Utf16Range) -> Value {
    json!({
        "start": value_utf16_position(value.start),
        "end": value_utf16_position(value.end)
    })
}

fn value_symbol_location(value: &SymbolLocation) -> Value {
    json!({
        "uri": value.uri,
        "range": value_utf16_range(value.range)
    })
}

fn value_document_symbol(symbol: &DocumentSymbol) -> Value {
    json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "range": value_offset_range(symbol.range.start, symbol.range.end),
        "selection_range": value_offset_range(symbol.selection_range.start, symbol.selection_range.end),
        "children": symbol.children.iter().map(value_document_symbol).collect::<Vec<_>>(),
        "data_json": symbol.data_json
    })
}

fn value_workspace_symbol(symbol: &WorkspaceSymbol) -> Value {
    json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "location": value_symbol_location(&symbol.location),
        "container_name": symbol.container_name,
        "data_json": symbol.data_json
    })
}

fn value_interval(interval: &Interval) -> Value {
    json!({
        "start": interval.start,
        "end": interval.end,
        "style_id": interval.style_id
    })
}

fn value_fold_region(region: &FoldRegion) -> Value {
    json!({
        "start_line": region.start_line,
        "end_line": region.end_line,
        "is_collapsed": region.is_collapsed,
        "placeholder": region.placeholder
    })
}

fn value_diagnostic(diagnostic: &Diagnostic) -> Value {
    json!({
        "range": value_offset_range(diagnostic.range.start, diagnostic.range.end),
        "severity": diagnostic.severity.map(diagnostic_severity_to_str),
        "code": diagnostic.code,
        "source": diagnostic.source,
        "message": diagnostic.message,
        "related_information_json": diagnostic.related_information_json,
        "data_json": diagnostic.data_json
    })
}

fn value_decoration(decoration: &Decoration) -> Value {
    json!({
        "range": value_offset_range(decoration.range.start, decoration.range.end),
        "placement": decoration_placement_to_str(decoration.placement),
        "kind": decoration_kind_to_json(decoration.kind),
        "text": decoration.text,
        "styles": decoration.styles,
        "tooltip": decoration.tooltip,
        "data_json": decoration.data_json
    })
}

fn value_processing_edit(edit: &ProcessingEdit) -> Value {
    match edit {
        ProcessingEdit::ReplaceStyleLayer { layer, intervals } => json!({
            "op": "replace_style_layer",
            "layer": layer.0,
            "intervals": intervals.iter().map(value_interval).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearStyleLayer { layer } => json!({
            "op": "clear_style_layer",
            "layer": layer.0
        }),
        ProcessingEdit::ReplaceFoldingRegions {
            regions,
            preserve_collapsed,
        } => json!({
            "op": "replace_folding_regions",
            "regions": regions.iter().map(value_fold_region).collect::<Vec<_>>(),
            "preserve_collapsed": preserve_collapsed,
        }),
        ProcessingEdit::ClearFoldingRegions => json!({ "op": "clear_folding_regions" }),
        ProcessingEdit::ReplaceDiagnostics { diagnostics } => json!({
            "op": "replace_diagnostics",
            "diagnostics": diagnostics.iter().map(value_diagnostic).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDiagnostics => json!({ "op": "clear_diagnostics" }),
        ProcessingEdit::ReplaceDecorations { layer, decorations } => json!({
            "op": "replace_decorations",
            "layer": layer.0,
            "decorations": decorations.iter().map(value_decoration).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDecorations { layer } => json!({
            "op": "clear_decorations",
            "layer": layer.0,
        }),
        ProcessingEdit::ReplaceDocumentSymbols { symbols } => json!({
            "op": "replace_document_symbols",
            "symbols": symbols.symbols.iter().map(value_document_symbol).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDocumentSymbols => json!({ "op": "clear_document_symbols" }),
    }
}

fn value_text_delta(delta: &editor_core::TextDelta) -> Value {
    json!({
        "before_char_count": delta.before_char_count,
        "after_char_count": delta.after_char_count,
        "undo_group_id": delta.undo_group_id,
        "edits": delta.edits.iter().map(|edit| json!({
            "start": edit.start,
            "deleted_text": edit.deleted_text,
            "inserted_text": edit.inserted_text,
        })).collect::<Vec<_>>()
    })
}

fn value_headless_cell(cell: &Cell) -> Value {
    json!({
        "ch": cell.ch.to_string(),
        "width": cell.width,
        "styles": cell.styles,
    })
}

fn value_headless_line(line: &HeadlessLine) -> Value {
    json!({
        "logical_line_index": line.logical_line_index,
        "is_wrapped_part": line.is_wrapped_part,
        "visual_in_logical": line.visual_in_logical,
        "char_offset_start": line.char_offset_start,
        "char_offset_end": line.char_offset_end,
        "segment_x_start_cells": line.segment_x_start_cells,
        "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
        "cells": line.cells.iter().map(value_headless_cell).collect::<Vec<_>>(),
    })
}

fn value_headless_grid(grid: &HeadlessGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_headless_line).collect::<Vec<_>>()
    })
}

fn value_minimap_line(line: &MinimapLine) -> Value {
    json!({
        "logical_line_index": line.logical_line_index,
        "visual_in_logical": line.visual_in_logical,
        "char_offset_start": line.char_offset_start,
        "char_offset_end": line.char_offset_end,
        "total_cells": line.total_cells,
        "non_whitespace_cells": line.non_whitespace_cells,
        "dominant_style": line.dominant_style,
        "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
    })
}

fn value_minimap_grid(grid: &MinimapGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_minimap_line).collect::<Vec<_>>()
    })
}

fn value_composed_cell_source(source: ComposedCellSource) -> Value {
    match source {
        ComposedCellSource::Document { offset } => json!({ "kind": "document", "offset": offset }),
        ComposedCellSource::Virtual { anchor_offset } => {
            json!({ "kind": "virtual", "anchor_offset": anchor_offset })
        }
    }
}

fn value_composed_cell(cell: &ComposedCell) -> Value {
    json!({
        "ch": cell.ch.to_string(),
        "width": cell.width,
        "styles": cell.styles,
        "source": value_composed_cell_source(cell.source),
    })
}

fn value_composed_line_kind(kind: ComposedLineKind) -> Value {
    match kind {
        ComposedLineKind::Document {
            logical_line,
            visual_in_logical,
        } => json!({
            "kind": "document",
            "logical_line": logical_line,
            "visual_in_logical": visual_in_logical,
        }),
        ComposedLineKind::VirtualAboveLine { logical_line } => {
            json!({ "kind": "virtual_above_line", "logical_line": logical_line })
        }
    }
}

fn value_composed_line(line: &ComposedLine) -> Value {
    json!({
        "kind": value_composed_line_kind(line.kind),
        "cells": line.cells.iter().map(value_composed_cell).collect::<Vec<_>>(),
    })
}

fn value_composed_grid(grid: &ComposedGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_composed_line).collect::<Vec<_>>(),
    })
}

fn value_command_result(result: CommandResult) -> Value {
    match result {
        CommandResult::Success => json!({ "kind": "success" }),
        CommandResult::Text(text) => json!({ "kind": "text", "text": text }),
        CommandResult::Position(pos) => {
            json!({ "kind": "position", "position": value_position(pos) })
        }
        CommandResult::Offset(offset) => json!({ "kind": "offset", "offset": offset }),
        CommandResult::Viewport(grid) => {
            json!({ "kind": "viewport", "viewport": value_headless_grid(&grid) })
        }
        CommandResult::SearchMatch { start, end } => {
            json!({ "kind": "search_match", "start": start, "end": end })
        }
        CommandResult::SearchNotFound => json!({ "kind": "search_not_found" }),
        CommandResult::ReplaceResult { replaced } => {
            json!({ "kind": "replace_result", "replaced": replaced })
        }
    }
}

fn value_document_state(state: &DocumentState) -> Value {
    json!({
        "line_count": state.line_count,
        "char_count": state.char_count,
        "byte_count": state.byte_count,
        "is_modified": state.is_modified,
        "version": state.version,
    })
}

fn value_cursor_state(state: &CursorState) -> Value {
    json!({
        "position": value_position(state.position),
        "offset": state.offset,
        "multi_cursors": state.multi_cursors.iter().map(|p| value_position(*p)).collect::<Vec<_>>(),
        "selection": state.selection.as_ref().map(value_selection),
        "selections": state.selections.iter().map(value_selection).collect::<Vec<_>>(),
        "primary_selection_index": state.primary_selection_index,
    })
}

fn value_range_state(start: usize, end: usize) -> Value {
    json!({ "start": start, "end": end })
}

fn value_viewport_state(state: &ViewportState) -> Value {
    json!({
        "width": state.width,
        "height": state.height,
        "scroll_top": state.scroll_top,
        "sub_row_offset": state.sub_row_offset,
        "overscan_rows": state.overscan_rows,
        "visible_lines": value_range_state(state.visible_lines.start, state.visible_lines.end),
        "prefetch_lines": value_range_state(state.prefetch_lines.start, state.prefetch_lines.end),
        "total_visual_lines": state.total_visual_lines,
    })
}

fn value_undo_redo_state(state: &UndoRedoState) -> Value {
    json!({
        "can_undo": state.can_undo,
        "can_redo": state.can_redo,
        "undo_depth": state.undo_depth,
        "redo_depth": state.redo_depth,
        "current_change_group": state.current_change_group,
    })
}

fn value_folding_state(state: &FoldingState) -> Value {
    json!({
        "regions": state.regions.iter().map(value_fold_region).collect::<Vec<_>>(),
        "collapsed_line_count": state.collapsed_line_count,
        "visible_logical_lines": state.visible_logical_lines,
        "total_visual_lines": state.total_visual_lines,
    })
}

fn value_diagnostics_state(state: &DiagnosticsState) -> Value {
    json!({ "diagnostics_count": state.diagnostics_count })
}

fn value_decorations_state(state: &DecorationsState) -> Value {
    json!({
        "layer_count": state.layer_count,
        "decoration_count": state.decoration_count,
    })
}

fn value_style_state(state: &StyleState) -> Value {
    json!({ "style_count": state.style_count })
}

fn value_editor_state(state: &EditorState) -> Value {
    json!({
        "document": value_document_state(&state.document),
        "cursor": value_cursor_state(&state.cursor),
        "viewport": value_viewport_state(&state.viewport),
        "undo_redo": value_undo_redo_state(&state.undo_redo),
        "folding": value_folding_state(&state.folding),
        "diagnostics": value_diagnostics_state(&state.diagnostics),
        "decorations": value_decorations_state(&state.decorations),
        "style": value_style_state(&state.style),
    })
}

fn value_workspace_search_result(item: &WorkspaceSearchResult) -> Value {
    json!({
        "buffer_id": item.id.get(),
        "uri": item.uri,
        "matches": item.matches.iter().map(|m| value_search_match(*m)).collect::<Vec<_>>(),
    })
}

fn value_search_match(m: SearchMatch) -> Value {
    json!({ "start": m.start, "end": m.end })
}

fn value_smooth_scroll_state(state: ViewSmoothScrollState) -> Value {
    json!({
        "top_visual_row": state.top_visual_row,
        "sub_row_offset": state.sub_row_offset,
        "overscan_rows": state.overscan_rows,
    })
}

fn value_workspace_viewport_state(state: &WorkspaceViewportState) -> Value {
    json!({
        "width": state.width,
        "height": state.height,
        "scroll_top": state.scroll_top,
        "visible_lines": value_range_state(state.visible_lines.start, state.visible_lines.end),
        "total_visual_lines": state.total_visual_lines,
        "smooth_scroll": value_smooth_scroll_state(state.smooth_scroll),
        "prefetch_lines": value_range_state(state.prefetch_lines.start, state.prefetch_lines.end),
    })
}

fn value_open_buffer_result(result: OpenBufferResult) -> Value {
    json!({
        "buffer_id": result.buffer_id.get(),
        "view_id": result.view_id.get(),
    })
}

fn parse_command_from_json(json_text: &str) -> Result<Command, String> {
    let input: FfiCommandInput = parse_json(json_text, "command")?;
    Ok(input.into_core())
}

fn parse_processing_edits(json_text: &str) -> Result<Vec<ProcessingEdit>, String> {
    let input: FfiProcessingEditsInput = parse_json(json_text, "processing edits")?;
    Ok(input.into_core())
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
    viewport_width: usize,
) -> *mut EcfEditorState {
    result_ptr(ptr::null_mut(), || {
        let text = require_string(initial_text, "initial_text")?;
        let state = EcfEditorState {
            inner: EditorStateManager::new(&text, viewport_width.max(1)),
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
        let symbols = &state.inner.editor().document_symbols;
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
                .diagnostics
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
            .decorations
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
    start_visual_row: usize,
    count: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
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
    start_visual_row: usize,
    count: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let grid = state.inner.get_minimap_content(start_visual_row, count);
        Ok(value_minimap_grid(&grid))
    })
}

/// Get decoration-aware composed snapshot as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_viewport_composed_json(
    state: *const EcfEditorState,
    start_visual_row: usize,
    count: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
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
    viewport_width: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let uri = optional_string(uri, "uri")?;
        let text = require_string(text, "text")?;
        let opened = workspace
            .inner
            .open_buffer(uri, &text, viewport_width.max(1))
            .map_err(|err| format!("open_buffer failed: {err:?}"))?;
        Ok(value_open_buffer_result(opened))
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
    viewport_width: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
        let view_id = workspace
            .inner
            .create_view(BufferId::from_raw(buffer_id), viewport_width.max(1))
            .map_err(|err| format!("create_view failed: {err:?}"))?;
        Ok(json!({ "view_id": view_id.get() }))
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

/// Set viewport height for a view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_set_viewport_height(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    height: usize,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
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
    top_visual_row: usize,
    sub_row_offset: u16,
    overscan_rows: usize,
) -> bool {
    result_bool(false, || {
        let workspace = require_mut(workspace, "workspace")?;
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
    start_visual_row: usize,
    count: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
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
    start_visual_row: usize,
    count: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
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
    start_visual_row: usize,
    count: usize,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let workspace = require_mut(workspace, "workspace")?;
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
    char_offset: usize,
) -> usize {
    match ffi_catch(|| {
        let line_text = require_string(line_text, "line_text")?;
        Ok(LspCoordinateConverter::char_offset_to_utf16(
            &line_text,
            char_offset,
        ))
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
    utf16_offset: usize,
) -> usize {
    match ffi_catch(|| {
        let line_text = require_string(line_text, "line_text")?;
        Ok(LspCoordinateConverter::utf16_to_char_offset(
            &line_text,
            utf16_offset,
        ))
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
            &state.inner.editor().line_index,
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

        let edits = lsp_diagnostics_to_processing_edits(&state.inner.editor().line_index, &params);
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
    fallback_start: usize,
    fallback_end: usize,
    has_fallback: bool,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        let state = require_ref(state, "state")?;
        let completion_item_json = require_string(completion_item_json, "completion_item_json")?;
        let mode = require_string(mode, "mode")?;

        let mode = parse_completion_mode(&mode)?;
        let item = parse_json_value(&completion_item_json, "completion item")?;
        let fallback = has_fallback.then_some((fallback_start, fallback_end));

        let edits = completion_item_to_text_edit_specs(
            &state.inner.editor().line_index,
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
        let edit = f(&state.inner.editor().line_index, &value);
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
pub unsafe extern "C" fn editor_core_ffi_sublime_processor_free(processor: *mut EcfSublimeProcessor) {
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

/// Built-in Tree-sitter Rust language function.
///
/// This is provided so FFI consumers (including Swift tests/wrappers) can use Tree-sitter
/// without separately linking a language grammar.
///
/// # Safety
///
/// This function returns a raw pointer to the Tree-sitter language function.
/// The returned pointer is valid for the lifetime of the program.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_treesitter_language_rust() -> *const () {
    let language_fn = tree_sitter_rust::LANGUAGE.into_raw();
    unsafe { language_fn() }
}

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

        let mut config = TreeSitterProcessorConfig::new(language, highlights_query);
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
        state
            .inner
            .execute(Command::Cursor(CursorCommand::MoveTo {
                line: line as usize,
                column: column as usize,
            }))
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
            start: Position::new(start_line as usize, start_column as usize),
            end: Position::new(end_line as usize, end_column as usize),
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
        workspace
            .inner
            .execute(
                ViewId::from_raw(view_id),
                Command::Cursor(CursorCommand::MoveTo {
                    line: line as usize,
                    column: column as usize,
                }),
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
        let grid = state
            .inner
            .get_viewport_content_styled(start_visual_row as usize, row_count as usize);
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
        let grid = workspace
            .inner
            .get_viewport_content_styled(
                ViewId::from_raw(view_id),
                start_visual_row as usize,
                row_count as usize,
            )
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
