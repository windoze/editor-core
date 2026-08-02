//! C ABI bridge for the editor UI component.
//!
//! This crate exposes a C ABI intended for native host UI toolkits.
//! The Rust side owns:
//! - editor state (`editor-core`)
//! - input mapping (`editor-core-ui`)
//! - rendering (Skia CPU raster in `editor-core-render-skia`)
//!
//! The host side is responsible for:
//! - OS window/view lifecycle
//! - event collection (IME/keyboard/mouse/scroll)
//! - presenting the rendered pixels (RGBA buffer) to screen

use editor_core::{ExpandSelectionDirection, ExpandSelectionUnit};
use editor_core_render_skia::{
    RenderTheme, Rgba8, StyleColors, StyleFont, TextDecorations, UnderlineStyle,
};
use editor_core_ui::{ChromeTheme, EditorUi, MultiDocumentEditorUi, TabId, UiError};
use libc::{c_char, c_float, c_int, c_void};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::mem;
use std::ptr;
use std::slice;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

/// ABI version for the UI C contract exposed by this crate.
pub const ECU_ABI_VERSION: u32 = 1;

/// Feature bit: generic JSON editor command dispatcher is available.
pub const ECU_FEATURE_JSON_COMMAND_DISPATCH: u64 = 1 << 0;
/// Feature bit: typed derived-state snapshot JSON exports are available.
pub const ECU_FEATURE_TYPED_DERIVED_SNAPSHOTS: u64 = 1 << 1;
/// Feature bit: LSP interactive request/take APIs are available.
pub const ECU_FEATURE_LSP_INTERACTIVE_REQUESTS: u64 = 1 << 2;
/// Feature bit: LSP status/capability snapshot is available.
pub const ECU_FEATURE_LSP_STATUS_SNAPSHOT: u64 = 1 << 3;
/// Feature bit: LSP WorkspaceEdit application helpers are available.
pub const ECU_FEATURE_WORKSPACE_EDIT_APPLICATION: u64 = 1 << 4;
/// Feature bit: multi-document UI orchestrator ABI is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_UI: u64 = 1 << 5;
/// Feature bit: multi-document workspace diagnostics store is available.
pub const ECU_FEATURE_WORKSPACE_DIAGNOSTICS_STORE: u64 = 1 << 6;
/// Feature bit: multi-document workspace diagnostics event stream is available.
pub const ECU_FEATURE_WORKSPACE_DIAGNOSTICS_EVENTS: u64 = 1 << 7;
/// Feature bit: per-EditorUi LSP result slot event stream is available.
pub const ECU_FEATURE_LSP_RESULT_EVENTS: u64 = 1 << 8;
/// Feature bit: multi-document/project LSP result event aggregation is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_LSP_RESULT_EVENTS: u64 = 1 << 9;
/// Feature bit: per-EditorUi LSP request lifecycle event stream is available.
pub const ECU_FEATURE_LSP_REQUEST_EVENTS: u64 = 1 << 10;
/// Feature bit: multi-document/project LSP request event aggregation is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_LSP_REQUEST_EVENTS: u64 = 1 << 11;
/// Feature bit: explicit LSP request cancel/timeout lifecycle markers are available.
pub const ECU_FEATURE_LSP_REQUEST_CANCEL_TIMEOUT_EVENTS: u64 = 1 << 12;

pub const ECU_FEATURE_FLAGS: u64 = ECU_FEATURE_JSON_COMMAND_DISPATCH
    | ECU_FEATURE_TYPED_DERIVED_SNAPSHOTS
    | ECU_FEATURE_LSP_INTERACTIVE_REQUESTS
    | ECU_FEATURE_LSP_STATUS_SNAPSHOT
    | ECU_FEATURE_WORKSPACE_EDIT_APPLICATION
    | ECU_FEATURE_MULTI_DOCUMENT_UI
    | ECU_FEATURE_WORKSPACE_DIAGNOSTICS_STORE
    | ECU_FEATURE_WORKSPACE_DIAGNOSTICS_EVENTS
    | ECU_FEATURE_LSP_RESULT_EVENTS
    | ECU_FEATURE_MULTI_DOCUMENT_LSP_RESULT_EVENTS
    | ECU_FEATURE_LSP_REQUEST_EVENTS
    | ECU_FEATURE_MULTI_DOCUMENT_LSP_REQUEST_EVENTS
    | ECU_FEATURE_LSP_REQUEST_CANCEL_TIMEOUT_EVENTS;

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

const INVALID_ARGUMENT_PREFIX: &str = "invalid argument: ";

fn invalid_argument(msg: impl Into<String>) -> String {
    format!("{INVALID_ARGUMENT_PREFIX}{}", msg.into())
}

fn strip_invalid_argument_prefix(err: &str) -> Option<&str> {
    err.strip_prefix(INVALID_ARGUMENT_PREFIX)
}

fn set_last_error_from_error(err: String) {
    if let Some(msg) = strip_invalid_argument_prefix(&err) {
        set_last_error(msg.to_string());
    } else {
        set_last_error(err);
    }
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

/// Run a `void`-returning FFI operation under `catch_unwind`, updating the thread-local last-error
/// slot. On success the error is cleared; on error (including a caught panic) the message is
/// recorded. This prevents a panic from unwinding across the `extern "C"` boundary.
fn ffi_void<F>(f: F)
where
    F: FnOnce() -> Result<(), String>,
{
    match ffi_catch(f) {
        Ok(()) => clear_last_error(),
        Err(err) => set_last_error_from_error(err),
    }
}

fn make_c_string_ptr(mut s: String) -> *mut c_char {
    if s.contains('\0') {
        // CString forbids interior NUL. Keep it deterministic.
        s = s.replace('\0', "\\u0000");
    }
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("").expect("empty cstring").into_raw(),
    }
}

fn require_mut<'a, T>(ptr: *mut T, name: &str) -> Result<&'a mut T, String> {
    if ptr.is_null() {
        return Err(invalid_argument(format!("{name} is null")));
    }
    // SAFETY: checked for null; caller promises valid pointer.
    Ok(unsafe { &mut *ptr })
}

fn require_out_mut<'a, T>(ptr: *mut T, name: &str) -> Result<&'a mut T, String> {
    if ptr.is_null() {
        return Err(invalid_argument(format!("{name} is null")));
    }
    // SAFETY: checked for null; caller promises valid output pointer.
    Ok(unsafe { &mut *ptr })
}

fn require_cstr<'a>(ptr: *const c_char, name: &str) -> Result<&'a CStr, String> {
    if ptr.is_null() {
        return Err(invalid_argument(format!("{name} is null")));
    }
    Ok(unsafe { CStr::from_ptr(ptr) })
}

fn require_str<'a>(ptr: *const c_char, name: &str) -> Result<&'a str, String> {
    let cstr = require_cstr(ptr, name)?;
    cstr.to_str()
        .map_err(|_| invalid_argument(format!("{name} is not valid UTF-8")))
}

fn u32_to_usize(value: u32, name: &str) -> Result<usize, String> {
    usize::try_from(value).map_err(|_| {
        invalid_argument(format!(
            "{name} value {value} does not fit in usize on this platform"
        ))
    })
}

fn usize_to_u32(value: usize, name: &str) -> Result<u32, String> {
    u32::try_from(value)
        .map_err(|_| invalid_argument(format!("{name} value {value} exceeds the u32 ABI limit")))
}

fn ffi_count_to_usize<T>(value: u32, name: &str) -> Result<usize, String> {
    let len = u32_to_usize(value, name)?;
    let elem_size = mem::size_of::<T>().max(1);
    let max_len = isize::MAX as usize / elem_size;
    if len > max_len {
        return Err(invalid_argument(format!(
            "{name} value {value} exceeds the maximum slice length"
        )));
    }
    Ok(len)
}

unsafe fn ffi_slice_from_raw_parts<'a, T>(
    ptr: *const T,
    count: u32,
    ptr_name: &str,
    count_name: &str,
) -> Result<&'a [T], String> {
    let len = ffi_count_to_usize::<T>(count, count_name)?;
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() {
        return Err(invalid_argument(format!("{ptr_name} is null")));
    }
    // SAFETY: caller promises `ptr` is valid for `len` elements; this helper validates null,
    // fixed-width conversion, and Rust slice length limits before constructing the slice.
    Ok(unsafe { slice::from_raw_parts(ptr, len) })
}

unsafe fn ffi_slice_from_raw_parts_mut<'a, T>(
    ptr: *mut T,
    count: u32,
    ptr_name: &str,
    count_name: &str,
) -> Result<&'a mut [T], String> {
    let len = ffi_count_to_usize::<T>(count, count_name)?;
    if len == 0 {
        return Ok(&mut []);
    }
    if ptr.is_null() {
        return Err(invalid_argument(format!("{ptr_name} is null")));
    }
    // SAFETY: caller promises `ptr` is valid for `len` elements; this helper validates null,
    // fixed-width conversion, and Rust slice length limits before constructing the slice.
    Ok(unsafe { slice::from_raw_parts_mut(ptr, len) })
}

fn status_from_error(err: String) -> c_int {
    let status = if strip_invalid_argument_prefix(&err).is_some() {
        ECU_ERR_INVALID_ARGUMENT
    } else {
        ECU_ERR_INTERNAL
    };
    set_last_error_from_error(err);
    status
}

const ECU_OK: c_int = 0;
const ECU_ERR_INVALID_ARGUMENT: c_int = 1;
const ECU_ERR_BUFFER_TOO_SMALL: c_int = 4;
const ECU_ERR_INTERNAL: c_int = 7;

fn status_from_invalid_argument(err: String) -> c_int {
    set_last_error(err);
    ECU_ERR_INVALID_ARGUMENT
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuRgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuTheme {
    pub background: EcuRgba8,
    pub foreground: EcuRgba8,
    pub selection_background: EcuRgba8,
    pub caret: EcuRgba8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuChromeTheme {
    pub gutter_background: EcuRgba8,
    pub gutter_foreground: EcuRgba8,
    pub gutter_separator: EcuRgba8,
    pub fold_marker_collapsed: EcuRgba8,
    pub fold_marker_expanded: EcuRgba8,
}

/// A single `StyleId` override entry.
///
/// `flags` is a bitmask:
/// - bit 0: foreground is present
/// - bit 1: background is present
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuStyleColors {
    pub style_id: u32,
    pub flags: u32,
    pub foreground: EcuRgba8,
    pub background: EcuRgba8,
}

/// A single `StyleId` text-decoration override entry (underline/strikethrough).
///
/// `flags` is a bitmask:
/// - bit 0: underline style is present
/// - bit 1: underline color is present
/// - bit 2: strikethrough is present
/// - bit 3: strikethrough color is present
///
/// `underline_style` values:
/// - 1: single underline
/// - 2: double underline
/// - 3: squiggly underline
///
/// `strikethrough` values:
/// - 0: disabled
/// - 1: enabled
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuStyleTextDecorations {
    pub style_id: u32,
    pub flags: u32,
    pub underline_style: u32,
    pub underline_color: EcuRgba8,
    pub strikethrough: u32,
    pub strikethrough_color: EcuRgba8,
}

/// A single StyleId font-style override entry.
///
/// flags bitmask:
/// - bit 0: bold present
/// - bit 1: italic present
///
/// Values:
/// - bold: 0=disabled, 1=enabled
/// - italic: 0=disabled, 1=enabled
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuStyleFont {
    pub style_id: u32,
    pub flags: u32,
    pub bold: u32,
    pub italic: u32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuSelectionRange {
    pub start: u32,
    pub end: u32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuViewportState {
    pub width_cells: u32,
    pub height_rows: u32,
    pub has_height: u32,
    pub scroll_top: u32,
    pub sub_row_offset: u32,
    pub overscan_rows: u32,
    pub visible_start: u32,
    pub visible_end: u32,
    pub prefetch_start: u32,
    pub prefetch_end: u32,
    pub total_visual_lines: u32,
}

const ECU_STYLE_FLAG_FOREGROUND: u32 = 1 << 0;
const ECU_STYLE_FLAG_BACKGROUND: u32 = 1 << 1;

const ECU_TEXT_DECORATION_FLAG_UNDERLINE: u32 = 1 << 0;
const ECU_TEXT_DECORATION_FLAG_UNDERLINE_COLOR: u32 = 1 << 1;
const ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH: u32 = 1 << 2;
const ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH_COLOR: u32 = 1 << 3;

const ECU_STYLE_FONT_FLAG_BOLD: u32 = 1 << 0;
const ECU_STYLE_FONT_FLAG_ITALIC: u32 = 1 << 1;

fn theme_from_ffi(theme: &EcuTheme) -> RenderTheme {
    RenderTheme {
        background: Rgba8::new(
            theme.background.r,
            theme.background.g,
            theme.background.b,
            theme.background.a,
        ),
        foreground: Rgba8::new(
            theme.foreground.r,
            theme.foreground.g,
            theme.foreground.b,
            theme.foreground.a,
        ),
        selection_background: Rgba8::new(
            theme.selection_background.r,
            theme.selection_background.g,
            theme.selection_background.b,
            theme.selection_background.a,
        ),
        caret: Rgba8::new(theme.caret.r, theme.caret.g, theme.caret.b, theme.caret.a),
        styles: BTreeMap::new(),
        style_fonts: BTreeMap::new(),
        text_decorations: BTreeMap::new(),
    }
}

fn rgba8_from_ffi(c: EcuRgba8) -> Rgba8 {
    Rgba8::new(c.r, c.g, c.b, c.a)
}

fn chrome_theme_from_ffi(theme: &EcuChromeTheme) -> ChromeTheme {
    ChromeTheme {
        gutter_background: rgba8_from_ffi(theme.gutter_background),
        gutter_foreground: rgba8_from_ffi(theme.gutter_foreground),
        gutter_separator: rgba8_from_ffi(theme.gutter_separator),
        fold_marker_collapsed: rgba8_from_ffi(theme.fold_marker_collapsed),
        fold_marker_expanded: rgba8_from_ffi(theme.fold_marker_expanded),
    }
}

fn style_colors_from_ffi(entry: &EcuStyleColors) -> (u32, StyleColors) {
    let fg = if entry.flags & ECU_STYLE_FLAG_FOREGROUND != 0 {
        Some(Rgba8::new(
            entry.foreground.r,
            entry.foreground.g,
            entry.foreground.b,
            entry.foreground.a,
        ))
    } else {
        None
    };

    let bg = if entry.flags & ECU_STYLE_FLAG_BACKGROUND != 0 {
        Some(Rgba8::new(
            entry.background.r,
            entry.background.g,
            entry.background.b,
            entry.background.a,
        ))
    } else {
        None
    };

    (entry.style_id, StyleColors::new(fg, bg))
}

fn text_decorations_from_ffi(
    entry: &EcuStyleTextDecorations,
) -> Result<(u32, TextDecorations), String> {
    let mut out = TextDecorations::default();

    if entry.flags & ECU_TEXT_DECORATION_FLAG_UNDERLINE != 0 {
        let underline = match entry.underline_style {
            1 => UnderlineStyle::Single,
            2 => UnderlineStyle::Double,
            3 => UnderlineStyle::Squiggly,
            other => {
                return Err(format!(
                    "invalid underline_style {} for style_id=0x{:08X}",
                    other, entry.style_id
                ));
            }
        };
        out.underline = Some(underline);
    }

    if entry.flags & ECU_TEXT_DECORATION_FLAG_UNDERLINE_COLOR != 0 {
        out.underline_color = Some(Rgba8::new(
            entry.underline_color.r,
            entry.underline_color.g,
            entry.underline_color.b,
            entry.underline_color.a,
        ));
    }

    if entry.flags & ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH != 0 {
        out.strikethrough = Some(entry.strikethrough != 0);
    }

    if entry.flags & ECU_TEXT_DECORATION_FLAG_STRIKETHROUGH_COLOR != 0 {
        out.strikethrough_color = Some(Rgba8::new(
            entry.strikethrough_color.r,
            entry.strikethrough_color.g,
            entry.strikethrough_color.b,
            entry.strikethrough_color.a,
        ));
    }

    Ok((entry.style_id, out))
}

fn style_font_from_ffi(entry: &EcuStyleFont) -> (u32, StyleFont) {
    let mut out = StyleFont::default();
    if entry.flags & ECU_STYLE_FONT_FLAG_BOLD != 0 {
        out.bold = Some(entry.bold != 0);
    }
    if entry.flags & ECU_STYLE_FONT_FLAG_ITALIC != 0 {
        out.italic = Some(entry.italic != 0);
    }
    (entry.style_id, out)
}

fn map_ui_error(err: UiError) -> String {
    err.to_string()
}

/// Free a C string returned by this library.
///
/// # Safety
///
/// `ptr` must be a valid pointer returned by a function in this library that allocates C strings,
/// or null. The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

/// Retrieve the latest thread-local error message.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_last_error_message() -> *mut c_char {
    let message = LAST_ERROR.with(|slot| {
        slot.borrow()
            .clone()
            .unwrap_or_else(|| "no error".to_string())
    });
    make_c_string_ptr(message)
}

/// Return the UI FFI crate version as string.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_version() -> *mut c_char {
    make_c_string_ptr(env!("CARGO_PKG_VERSION").to_string())
}

/// Return ABI version for the UI C contract.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_abi_version() -> u32 {
    ECU_ABI_VERSION
}

/// Return a bitmask of optional UI FFI features supported by this build.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_feature_flags() -> u64 {
    ECU_FEATURE_FLAGS
}

mod editor_ui_abi;
pub use editor_ui_abi::*;

#[cfg(test)]
mod tests;
