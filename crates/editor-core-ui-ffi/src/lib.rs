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

use editor_core_render_skia::{RenderConfig, RenderTheme, Rgba8};
use editor_core_ui::{EditorUi, UiError};
use libc::{c_char, c_float, c_int};
use std::cell::RefCell;
use std::ffi::{CStr, CString};
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
        return Err(format!("{name} is null"));
    }
    // SAFETY: checked for null; caller promises valid pointer.
    Ok(unsafe { &mut *ptr })
}

fn require_cstr<'a>(ptr: *const c_char, name: &str) -> Result<&'a CStr, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    Ok(unsafe { CStr::from_ptr(ptr) })
}

fn status_from_error(err: String) -> c_int {
    set_last_error(err);
    ECU_ERR_INTERNAL
}

const ECU_OK: c_int = 0;
const ECU_ERR_BUFFER_TOO_SMALL: c_int = 4;
const ECU_ERR_INTERNAL: c_int = 7;

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

fn theme_from_ffi(theme: &EcuTheme) -> RenderTheme {
    RenderTheme {
        background: Rgba8::new(theme.background.r, theme.background.g, theme.background.b, theme.background.a),
        foreground: Rgba8::new(theme.foreground.r, theme.foreground.g, theme.foreground.b, theme.foreground.a),
        selection_background: Rgba8::new(
            theme.selection_background.r,
            theme.selection_background.g,
            theme.selection_background.b,
            theme.selection_background.a,
        ),
        caret: Rgba8::new(theme.caret.r, theme.caret.g, theme.caret.b, theme.caret.a),
    }
}

fn map_ui_error(err: UiError) -> String {
    err.to_string()
}

/// Free a C string returned by this library.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_string_free(ptr: *mut c_char) {
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

/// Create a new Editor UI handle.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_new(
    initial_text_utf8: *const c_char,
    viewport_width_cells: u32,
) -> *mut EditorUi {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let initial = require_cstr(initial_text_utf8, "initial_text_utf8")?
            .to_str()
            .map_err(|_| "initial_text_utf8 is not valid UTF-8".to_string())?;
        let ui = EditorUi::new(initial, viewport_width_cells as usize);
        Ok(Box::into_raw(Box::new(ui)))
    }) {
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

/// Free an Editor UI handle.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_free(ui: *mut EditorUi) {
    if ui.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(ui));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_theme(
    ui: *mut EditorUi,
    theme: *const EcuTheme,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if theme.is_null() {
            return Err("theme is null".to_string());
        }
        let theme = unsafe { &*theme };
        ui.set_theme(theme_from_ffi(theme));
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_render_metrics(
    ui: *mut EditorUi,
    font_size: c_float,
    line_height_px: c_float,
    cell_width_px: c_float,
    padding_x_px: c_float,
    padding_y_px: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let mut cfg = RenderConfig::default();
        cfg.font_size = font_size;
        cfg.line_height_px = line_height_px;
        cfg.cell_width_px = cell_width_px;
        cfg.padding_x_px = padding_x_px;
        cfg.padding_y_px = padding_y_px;
        ui.set_render_config(cfg);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_viewport_px(
    ui: *mut EditorUi,
    width_px: u32,
    height_px: u32,
    scale: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_viewport_px(width_px, height_px, scale)
            .map(|_| ECU_OK)
            .map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_scroll_by_rows(ui: *mut EditorUi, delta_rows: c_int) {
    if ui.is_null() {
        set_last_error("ui is null".to_string());
        return;
    }
    let ui = unsafe { &mut *ui };
    ui.scroll_by_rows(delta_rows as isize);
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_insert_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.insert_text(text).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_backspace(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.backspace().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_forward(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_forward().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_rows(
    ui: *mut EditorUi,
    delta_rows: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_rows(delta_rows as isize)
            .map(|_| ECU_OK)
            .map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_left(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_left().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_right(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_right()
            .map(|_| ECU_OK)
            .map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_marked_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.set_marked_text(text).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_unmark_text(ui: *mut EditorUi) {
    if ui.is_null() {
        set_last_error("ui is null".to_string());
        return;
    }
    unsafe { &mut *ui }.unmark_text();
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_commit_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.commit_text(text).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_down(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.mouse_down(x_px, y_px).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_dragged(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.mouse_dragged(x_px, y_px).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_up(ui: *mut EditorUi) {
    if ui.is_null() {
        set_last_error("ui is null".to_string());
        return;
    }
    unsafe { &mut *ui }.mouse_up();
}

/// Render the current visible viewport into an RGBA buffer.
///
/// - The caller provides an output buffer and capacity.
/// - If capacity is insufficient, returns `ECU_ERR_BUFFER_TOO_SMALL` and writes the required size to `out_len`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_render_rgba(
    ui: *mut EditorUi,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_len.is_null() {
            return Err("out_len is null".to_string());
        }

        let pixels = ui.render_rgba_visible().map_err(map_ui_error)?;
        let required = pixels.len() as u32;
        unsafe { *out_len = required };

        if out_buf.is_null() {
            // Two-call pattern: allow caller to query required size.
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        if out_cap < required {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        // SAFETY: caller provided buffer with capacity >= required.
        unsafe {
            let dst = slice::from_raw_parts_mut(out_buf, required as usize);
            dst.copy_from_slice(&pixels);
        }

        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Get the full document text as UTF-8.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_text(ui: *mut EditorUi) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        Ok(make_c_string_ptr(ui.text()))
    }) {
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

/// Get primary selection offsets (character offsets).
///
/// Writes `start` and `end` (inclusive-exclusive) offsets.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_selection_offsets(
    ui: *mut EditorUi,
    out_start: *mut u32,
    out_end: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_start.is_null() {
            return Err("out_start is null".to_string());
        }
        if out_end.is_null() {
            return Err("out_end is null".to_string());
        }
        let (start, end) = ui.primary_selection_offsets();
        unsafe {
            *out_start = start as u32;
            *out_end = end as u32;
        }
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Get IME marked text range.
///
/// If there is no marked text, writes `has_marked = 0` and `out_start/out_len = 0`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_marked_range(
    ui: *mut EditorUi,
    out_has_marked: *mut u8,
    out_start: *mut u32,
    out_len: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_marked.is_null() {
            return Err("out_has_marked is null".to_string());
        }
        if out_start.is_null() {
            return Err("out_start is null".to_string());
        }
        if out_len.is_null() {
            return Err("out_len is null".to_string());
        }

        let (has, start, len) = match ui.marked_range() {
            Some((s, l)) => (1u8, s as u32, l as u32),
            None => (0u8, 0u32, 0u32),
        };
        unsafe {
            *out_has_marked = has;
            *out_start = start;
            *out_len = len;
        }
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Map a character offset to a view point (in pixels, top-left origin).
///
/// Writes `out_x/out_y` and `out_line_height_px`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_char_offset_to_view_point(
    ui: *mut EditorUi,
    char_offset: u32,
    out_x: *mut c_float,
    out_y: *mut c_float,
    out_line_height_px: *mut c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_x.is_null() {
            return Err("out_x is null".to_string());
        }
        if out_y.is_null() {
            return Err("out_y is null".to_string());
        }
        if out_line_height_px.is_null() {
            return Err("out_line_height_px is null".to_string());
        }

        let (x, y) = ui
            .char_offset_to_view_point_px(char_offset as usize)
            .ok_or_else(|| "failed to map char offset to view point".to_string())?;

        unsafe {
            *out_x = x;
            *out_y = y;
            *out_line_height_px = ui.line_height_px();
        }
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn ffi_smoke_create_insert_render_get_text() {
        let initial = CString::new("abc").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Configure rendering for deterministic pixel tests.
        let theme = EcuTheme {
            background: EcuRgba8 { r: 10, g: 20, b: 30, a: 255 },
            foreground: EcuRgba8 { r: 250, g: 250, b: 250, a: 255 },
            selection_background: EcuRgba8 { r: 200, g: 0, b: 0, a: 255 },
            caret: EcuRgba8 { r: 0, g: 0, b: 200, a: 255 },
        };
        assert_eq!(editor_core_ui_ffi_editor_ui_set_theme(ui, &theme), ECU_OK);
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0),
            ECU_OK
        );

        let insert = CString::new("!").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
            ECU_OK
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }.to_str().unwrap().to_string();
        editor_core_ui_ffi_string_free(text_ptr);
        assert_eq!(text, "!abc");

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 80 * 40 * 4];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len
            ),
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());
        assert_eq!(pixel(&buf, 80, 70, 30), [10, 20, 30, 255]);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_render_buffer_too_small_sets_out_len() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0);

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 10];
        let code = editor_core_ui_ffi_editor_ui_render_rgba(
            ui,
            buf.as_mut_ptr(),
            buf.len() as u32,
            &mut out_len,
        );
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(out_len, 80 * 40 * 4);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_render_allows_out_buf_null_as_size_query() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0);

        let mut out_len: u32 = 0;
        let code = editor_core_ui_ffi_editor_ui_render_rgba(ui, ptr::null_mut(), 0, &mut out_len);
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(out_len, 80 * 40 * 4);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_null_args_set_last_error() {
        let code = editor_core_ui_ffi_editor_ui_insert_text(ptr::null_mut(), ptr::null());
        assert_eq!(code, ECU_ERR_INTERNAL);
        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }.to_str().unwrap().to_string();
        editor_core_ui_ffi_string_free(msg_ptr);
        assert!(msg.contains("ui is null") || msg.contains("text_utf8 is null"));
    }

    #[test]
    fn ffi_selection_and_marked_range_queries() {
        let initial = CString::new("abcd").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Configure minimal metrics/viewport so offset mapping can work.
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 60, 1.0);

        // Default selection is caret at 0.
        let mut start: u32 = 0;
        let mut end: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end),
            ECU_OK
        );
        assert_eq!((start, end), (0, 0));

        // Marked text.
        let marked = CString::new("你").unwrap();
        editor_core_ui_ffi_editor_ui_set_marked_text(ui, marked.as_ptr());

        let mut has: u8 = 0;
        let mut ms: u32 = 0;
        let mut ml: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_marked_range(ui, &mut has, &mut ms, &mut ml),
            ECU_OK
        );
        assert_eq!(has, 1);
        assert_eq!(ml, 1);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
        let idx = ((y * width_px + x) * 4) as usize;
        [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
