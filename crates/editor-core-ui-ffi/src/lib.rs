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

use editor_core_render_skia::{RenderTheme, Rgba8, StyleColors};
use editor_core_ui::{EditorUi, UiError};
use libc::{c_char, c_float, c_int};
use std::cell::RefCell;
use std::collections::BTreeMap;
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

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EcuSelectionRange {
    pub start: u32,
    pub end: u32,
}

const ECU_STYLE_FLAG_FOREGROUND: u32 = 1 << 0;
const ECU_STYLE_FLAG_BACKGROUND: u32 = 1 << 1;

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

/// Replace the current theme's `StyleId -> colors` override map.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_style_colors(
    ui: *mut EditorUi,
    styles: *const EcuStyleColors,
    style_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if styles.is_null() && style_count != 0 {
            return Err("styles is null".to_string());
        }

        let mut map = BTreeMap::<u32, StyleColors>::new();
        if style_count != 0 {
            // SAFETY: caller provided `style_count` entries.
            let slice = unsafe { slice::from_raw_parts(styles, style_count as usize) };
            for entry in slice {
                let (style_id, colors) = style_colors_from_ffi(entry);
                map.insert(style_id, colors);
            }
        }

        ui.set_style_colors(map);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml(
    ui: *mut EditorUi,
    yaml_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let yaml = require_cstr(yaml_utf8, "yaml_utf8")?
            .to_str()
            .map_err(|_| "yaml_utf8 is not valid UTF-8".to_string())?;
        ui.set_sublime_syntax_yaml(yaml)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_sublime_set_syntax_path(
    ui: *mut EditorUi,
    path_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let path = require_cstr(path_utf8, "path_utf8")?
            .to_str()
            .map_err(|_| "path_utf8 is not valid UTF-8".to_string())?;
        ui.set_sublime_syntax_path(std::path::Path::new(path))
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_sublime_disable(ui: *mut EditorUi) {
    if ui.is_null() {
        set_last_error("ui is null".to_string());
        return;
    }
    unsafe { &mut *ui }.disable_sublime_syntax();
    clear_last_error();
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(
    ui: *mut EditorUi,
    scope_utf8: *const c_char,
    out_style_id: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_style_id.is_null() {
            return Err("out_style_id is null".to_string());
        }
        let scope = require_cstr(scope_utf8, "scope_utf8")?
            .to_str()
            .map_err(|_| "scope_utf8 is not valid UTF-8".to_string())?;
        let style_id = ui.sublime_style_id_for_scope(scope).map_err(map_ui_error)?;
        unsafe {
            *out_style_id = style_id;
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

/// Map a Sublime `StyleId` to its original scope string.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(
    ui: *mut EditorUi,
    style_id: u32,
) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let scope = ui
            .sublime_scope_for_style_id(style_id)
            .ok_or_else(|| "unknown style_id (or Sublime not enabled)".to_string())?;
        Ok(make_c_string_ptr(scope.to_string()))
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_treesitter_rust_default()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_rust_enable_with_queries(
    ui: *mut EditorUi,
    highlights_query_utf8: *const c_char,
    folds_query_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let highlights = require_cstr(highlights_query_utf8, "highlights_query_utf8")?
            .to_str()
            .map_err(|_| "highlights_query_utf8 is not valid UTF-8".to_string())?;

        let folds = if folds_query_utf8.is_null() {
            None
        } else {
            Some(
                require_cstr(folds_query_utf8, "folds_query_utf8")?
                    .to_str()
                    .map_err(|_| "folds_query_utf8 is not valid UTF-8".to_string())?,
            )
        };

        ui.set_treesitter_rust_with_queries(highlights, folds)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_disable(ui: *mut EditorUi) {
    if ui.is_null() {
        set_last_error("ui is null".to_string());
        return;
    }
    unsafe { &mut *ui }.disable_treesitter();
    clear_last_error();
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(
    ui: *mut EditorUi,
    capture_utf8: *const c_char,
    out_style_id: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_style_id.is_null() {
            return Err("out_style_id is null".to_string());
        }
        let capture = require_cstr(capture_utf8, "capture_utf8")?
            .to_str()
            .map_err(|_| "capture_utf8 is not valid UTF-8".to_string())?;
        let style_id = ui.treesitter_style_id_for_capture(capture);
        unsafe {
            *out_style_id = style_id;
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

/// Map a Tree-sitter capture style id to its capture name.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(
    ui: *mut EditorUi,
    style_id: u32,
) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let name = ui
            .treesitter_capture_for_style_id(style_id)
            .ok_or_else(|| "unknown style_id".to_string())?;
        Ok(make_c_string_ptr(name.to_string()))
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(
    ui: *mut EditorUi,
    publish_diagnostics_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            publish_diagnostics_json_utf8,
            "publish_diagnostics_json_utf8",
        )?
        .to_str()
        .map_err(|_| "publish_diagnostics_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_publish_diagnostics_json(json)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
    ui: *mut EditorUi,
    data: *const u32,
    data_len: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if data.is_null() && data_len != 0 {
            return Err("data is null".to_string());
        }
        // SAFETY: caller provided `data_len` items.
        let slice = if data_len == 0 {
            &[][..]
        } else {
            unsafe { slice::from_raw_parts(data, data_len as usize) }
        };
        ui.lsp_apply_semantic_tokens(slice)
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
        ui.set_render_metrics(
            font_size,
            line_height_px,
            cell_width_px,
            padding_x_px,
            padding_y_px,
        );
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_font_families_csv(
    ui: *mut EditorUi,
    families_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let families = require_cstr(families_utf8, "families_utf8")?
            .to_str()
            .map_err(|_| "families_utf8 is not valid UTF-8".to_string())?;
        ui.set_font_families_csv(families);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(
    ui: *mut EditorUi,
    enabled: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_font_ligatures_enabled(enabled != 0);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_gutter_width_cells(
    ui: *mut EditorUi,
    width_cells: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_gutter_width_cells(width_cells)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_scroll_by_rows(
    ui: *mut EditorUi,
    delta_rows: c_int,
) {
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_style(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
    style_id: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_style(start as usize, end as usize, style_id)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_remove_style(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
    style_id: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.remove_style(start as usize, end as usize, style_id)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_undo(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.undo().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_redo(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.redo().map(|_| ECU_OK).map_err(map_ui_error)
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
        ui.move_grapheme_left()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_left_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_right_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_rows_and_modify_selection(
    ui: *mut EditorUi,
    delta_rows: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_rows_and_modify_selection(delta_rows as isize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_clear_secondary_selections(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.clear_secondary_selections()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_cursor_above(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_cursor_above()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_cursor_below(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_cursor_below()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_next_occurrence(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_next_occurrence(editor_core::SearchOptions::default())
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_all_occurrences(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_all_occurrences(editor_core::SearchOptions::default())
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_select_word(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.select_word().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_select_line(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.select_line().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_select_paragraph_at_char_offset(
    ui: *mut EditorUi,
    char_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.select_paragraph_at_char_offset(char_offset as usize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_paragraph_selection_offsets(
    ui: *mut EditorUi,
    anchor_offset: u32,
    active_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_paragraph_selection_offsets(anchor_offset as usize, active_offset as usize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_expand_selection(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.expand_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_caret_at_char_offset(
    ui: *mut EditorUi,
    char_offset: u32,
    make_primary: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_caret_at_char_offset(char_offset as usize, make_primary != 0)
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
        ui.set_marked_text(text)
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

/// Set IME marked text with explicit selection and optional replacement range.
///
/// - `selected_start/selected_len`: selection within `text` (character offsets).
/// - `replace_start/replace_len`: document char-offset range to replace.
///   If `replace_start == UINT32_MAX`, the UI layer will use the current marked range (if any),
///   otherwise it falls back to the current selection/caret.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_marked_text_ex(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
    selected_start: u32,
    selected_len: u32,
    replace_start: u32,
    replace_len: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;

        let replace_range = if replace_start == u32::MAX {
            None
        } else {
            Some((replace_start as usize, replace_len as usize))
        };

        ui.set_marked_text_with_selection(
            text,
            selected_start as usize,
            selected_len as usize,
            replace_range,
        )
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
        ui.mouse_down(x_px, y_px)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_dragged(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.mouse_dragged(x_px, y_px)
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

        let required = ui.required_rgba_len() as u32;
        unsafe { *out_len = required };

        if out_buf.is_null() {
            // Two-call pattern: allow caller to query required size.
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        if out_cap < required {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        // SAFETY: caller provided buffer with capacity >= required.
        let dst = unsafe { slice::from_raw_parts_mut(out_buf, required as usize) };
        ui.render_rgba_visible_into(dst)
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

/// Get all selections (including primary) as character-offset ranges.
///
/// - `out_len` receives the required number of ranges.
/// - `out_primary_index` receives the primary selection index.
/// - If `out_ranges` is null or `out_cap` is insufficient, returns `ECU_ERR_BUFFER_TOO_SMALL`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_selections(
    ui: *mut EditorUi,
    out_ranges: *mut EcuSelectionRange,
    out_cap: u32,
    out_len: *mut u32,
    out_primary_index: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_len.is_null() {
            return Err("out_len is null".to_string());
        }
        if out_primary_index.is_null() {
            return Err("out_primary_index is null".to_string());
        }

        let (ranges, primary) = ui.selections_offsets();
        let required = ranges.len() as u32;
        unsafe {
            *out_len = required;
            *out_primary_index = primary as u32;
        }

        if out_ranges.is_null() {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }
        if out_cap < required {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        // SAFETY: caller provided buffer with capacity >= required.
        let dst = unsafe { slice::from_raw_parts_mut(out_ranges, required as usize) };
        for (i, (start, end)) in ranges.into_iter().enumerate() {
            dst[i] = EcuSelectionRange {
                start: start as u32,
                end: end as u32,
            };
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

/// Set the full selection set (including primary) from character-offset ranges.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_selections(
    ui: *mut EditorUi,
    ranges: *const EcuSelectionRange,
    range_count: u32,
    primary_index: u32,
) -> c_int {
    if range_count == 0 {
        return status_from_invalid_argument("range_count must be > 0".to_string());
    }
    if ranges.is_null() {
        return status_from_invalid_argument("ranges is null".to_string());
    }

    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        let slice = unsafe { slice::from_raw_parts(ranges, range_count as usize) };
        let mut vec = Vec::with_capacity(slice.len());
        for r in slice {
            vec.push((r.start as usize, r.end as usize));
        }

        ui.set_selections_offsets(vec.as_slice(), primary_index as usize)
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

/// Set a rectangular (box) selection from two character offsets.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_rect_selection(
    ui: *mut EditorUi,
    anchor_offset: u32,
    active_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_rect_selection_offsets(anchor_offset as usize, active_offset as usize)
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

/// Hit-test a view point (pixels, top-left origin) and return the corresponding character offset.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_view_point_to_char_offset(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    out_char_offset: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_char_offset.is_null() {
            return Err("out_char_offset is null".to_string());
        }
        let offset = ui
            .view_point_to_char_offset(x_px, y_px)
            .ok_or_else(|| "failed to hit-test view point".to_string())?;
        unsafe { *out_char_offset = offset as u32 };
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
            background: EcuRgba8 {
                r: 10,
                g: 20,
                b: 30,
                a: 255,
            },
            foreground: EcuRgba8 {
                r: 250,
                g: 250,
                b: 250,
                a: 255,
            },
            selection_background: EcuRgba8 {
                r: 200,
                g: 0,
                b: 0,
                a: 255,
            },
            caret: EcuRgba8 {
                r: 0,
                g: 0,
                b: 200,
                a: 255,
            },
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
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        editor_core_ui_ffi_string_free(text_ptr);
        assert_eq!(text, "!abc");

        // undo/redo smoke
        assert_eq!(editor_core_ui_ffi_editor_ui_undo(ui), ECU_OK);
        let t2_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let t2 = unsafe { CStr::from_ptr(t2_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        editor_core_ui_ffi_string_free(t2_ptr);
        assert_eq!(t2, "abc");
        assert_eq!(editor_core_ui_ffi_editor_ui_redo(ui), ECU_OK);

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
    fn ffi_set_style_colors_affects_rendering() {
        // Use a space in the styled cell so glyph rasterization does not affect the pixel sample.
        let initial = CString::new("a c").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let theme = EcuTheme {
            background: EcuRgba8 {
                r: 10,
                g: 20,
                b: 30,
                a: 255,
            },
            foreground: EcuRgba8 {
                r: 250,
                g: 250,
                b: 250,
                a: 255,
            },
            selection_background: EcuRgba8 {
                r: 200,
                g: 0,
                b: 0,
                a: 255,
            },
            caret: EcuRgba8 {
                r: 0,
                g: 0,
                b: 200,
                a: 255,
            },
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

        // Apply style id 42 to the middle cell (a space).
        assert_eq!(editor_core_ui_ffi_editor_ui_add_style(ui, 1, 2, 42), ECU_OK);

        let styles = [EcuStyleColors {
            style_id: 42,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 1,
                g: 200,
                b: 2,
                a: 255,
            },
        }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32),
            ECU_OK
        );

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

        // Styled cell is at x in [10..20], pick a center pixel at y=10.
        assert_eq!(pixel(&buf, 80, 15, 10), [1, 200, 2, 255]);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_sublime_highlight_scope_mapping_and_rendering() {
        // Put a space after '#' so we can sample a highlighted cell without glyph pixels.
        let initial = CString::new("a # \n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let theme = EcuTheme {
            background: EcuRgba8 {
                r: 10,
                g: 20,
                b: 30,
                a: 255,
            },
            foreground: EcuRgba8 {
                r: 250,
                g: 250,
                b: 250,
                a: 255,
            },
            selection_background: EcuRgba8 {
                r: 200,
                g: 0,
                b: 0,
                a: 255,
            },
            caret: EcuRgba8 {
                r: 0,
                g: 0,
                b: 200,
                a: 255,
            },
        };
        assert_eq!(editor_core_ui_ffi_editor_ui_set_theme(ui, &theme), ECU_OK);
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        let yaml = CString::new(
            r##"%YAML 1.2
---
name: Demo
scope: source.demo
contexts:
  main:
    - match: "#.*$"
      scope: comment.line.demo
"##,
        )
        .unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml(ui, yaml.as_ptr()),
            ECU_OK
        );

        let scope = CString::new("comment.line.demo").unwrap();
        let mut style_id: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(
                ui,
                scope.as_ptr(),
                &mut style_id
            ),
            ECU_OK
        );

        let scope_ptr = editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(ui, style_id);
        assert!(!scope_ptr.is_null());
        let roundtrip = unsafe { CStr::from_ptr(scope_ptr) }.to_str().unwrap();
        assert_eq!(roundtrip, "comment.line.demo");
        editor_core_ui_ffi_string_free(scope_ptr);

        let styles = [EcuStyleColors {
            style_id,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 1,
                g: 200,
                b: 2,
                a: 255,
            },
        }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
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

        // "a # " => space at col=3 is highlighted => x in [30..40]
        assert_eq!(pixel(&buf, 200, 35, 10), [1, 200, 2, 255]);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_treesitter_highlight_capture_mapping_and_rendering() {
        let initial = CString::new("// c\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let theme = EcuTheme {
            background: EcuRgba8 {
                r: 10,
                g: 20,
                b: 30,
                a: 255,
            },
            foreground: EcuRgba8 {
                r: 250,
                g: 250,
                b: 250,
                a: 255,
            },
            selection_background: EcuRgba8 {
                r: 200,
                g: 0,
                b: 0,
                a: 255,
            },
            caret: EcuRgba8 {
                r: 0,
                g: 0,
                b: 200,
                a: 255,
            },
        };
        assert_eq!(editor_core_ui_ffi_editor_ui_set_theme(ui, &theme), ECU_OK);
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        let highlights = CString::new("(line_comment) @comment").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_treesitter_rust_enable_with_queries(
                ui,
                highlights.as_ptr(),
                ptr::null()
            ),
            ECU_OK
        );

        let capture = CString::new("comment").unwrap();
        let mut style_id: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(
                ui,
                capture.as_ptr(),
                &mut style_id
            ),
            ECU_OK
        );

        let name_ptr = editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(ui, style_id);
        assert!(!name_ptr.is_null());
        let roundtrip = unsafe { CStr::from_ptr(name_ptr) }.to_str().unwrap();
        assert_eq!(roundtrip, "comment");
        editor_core_ui_ffi_string_free(name_ptr);

        let styles = [EcuStyleColors {
            style_id,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 1,
                g: 200,
                b: 2,
                a: 255,
            },
        }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
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

        // Comment contains a space at col=2 => x in [20..30]
        assert_eq!(pixel(&buf, 200, 25, 10), [1, 200, 2, 255]);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_get_set_selections_roundtrip_and_insert_applies_to_all() {
        let initial = CString::new("abc\ndef\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let ranges = [
            EcuSelectionRange { start: 0, end: 0 },
            EcuSelectionRange { start: 4, end: 4 },
        ];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0),
            ECU_OK
        );

        let mut required: u32 = 0;
        let mut primary: u32 = 0;
        let code = editor_core_ui_ffi_editor_ui_get_selections(
            ui,
            ptr::null_mut(),
            0,
            &mut required,
            &mut primary,
        );
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(required, 2);
        assert_eq!(primary, 0);

        let mut out = vec![
            EcuSelectionRange { start: 0, end: 0 };
            required as usize
        ];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_selections(
                ui,
                out.as_mut_ptr(),
                out.len() as u32,
                &mut required,
                &mut primary
            ),
            ECU_OK
        );
        assert_eq!(required as usize, out.len());
        assert_eq!(out[0].start, 0);
        assert_eq!(out[0].end, 0);
        assert_eq!(out[1].start, 4);
        assert_eq!(out[1].end, 4);

        let insert = CString::new("X").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
            ECU_OK
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let text = unsafe { CStr::from_ptr(text_ptr) }.to_str().unwrap().to_string();
        editor_core_ui_ffi_string_free(text_ptr);
        assert_eq!(text, "Xabc\nXdef\n");

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_rect_selection_replaces_each_line_range() {
        let initial = CString::new("abc\ndef\nghi\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // anchor: offset 1 ('b'), active: offset 10 ('i')
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_rect_selection(ui, 1, 10),
            ECU_OK
        );

        let insert = CString::new("X").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
            ECU_OK
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let text = unsafe { CStr::from_ptr(text_ptr) }.to_str().unwrap().to_string();
        editor_core_ui_ffi_string_free(text_ptr);
        assert_eq!(text, "aXc\ndXf\ngXi\n");

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_multi_cursor_commands_work() {
        let initial = CString::new("aa\naa\naa\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // One caret at line 1 col 1 => offset 4.
        let ranges = [EcuSelectionRange { start: 4, end: 4 }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0),
            ECU_OK
        );

        assert_eq!(editor_core_ui_ffi_editor_ui_add_cursor_above(ui), ECU_OK);

        let insert = CString::new("X").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
            ECU_OK
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let text = unsafe { CStr::from_ptr(text_ptr) }.to_str().unwrap().to_string();
        editor_core_ui_ffi_string_free(text_ptr);
        assert_eq!(text, "aXa\naXa\naa\n");

        assert_eq!(
            editor_core_ui_ffi_editor_ui_clear_secondary_selections(ui),
            ECU_OK
        );

        let mut required: u32 = 0;
        let mut primary: u32 = 0;
        let code = editor_core_ui_ffi_editor_ui_get_selections(
            ui,
            ptr::null_mut(),
            0,
            &mut required,
            &mut primary,
        );
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(required, 1);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_select_word_and_add_all_occurrences() {
        let initial = CString::new("foo foo foo\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Place caret at start.
        let ranges = [EcuSelectionRange { start: 0, end: 0 }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0),
            ECU_OK
        );

        assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);
        assert_eq!(editor_core_ui_ffi_editor_ui_add_all_occurrences(ui), ECU_OK);

        let insert = CString::new("X").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
            ECU_OK
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let text = unsafe { CStr::from_ptr(text_ptr) }.to_str().unwrap().to_string();
        editor_core_ui_ffi_string_free(text_ptr);
        assert_eq!(text, "X X X\n");

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_gutter_renders_fold_marker_and_click_toggles_fold() {
        let initial = CString::new("fn main() {\n  let x = 1;\n}\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let theme = EcuTheme {
            background: EcuRgba8 {
                r: 10,
                g: 20,
                b: 30,
                a: 255,
            },
            foreground: EcuRgba8 {
                r: 250,
                g: 250,
                b: 250,
                a: 255,
            },
            selection_background: EcuRgba8 {
                r: 200,
                g: 0,
                b: 0,
                a: 255,
            },
            caret: EcuRgba8 {
                r: 0,
                g: 0,
                b: 200,
                a: 255,
            },
        };
        assert_eq!(editor_core_ui_ffi_editor_ui_set_theme(ui, &theme), ECU_OK);
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 60, 1.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(ui),
            ECU_OK
        );

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_gutter_width_cells(ui, 2),
            ECU_OK
        );

        let styles = [
            // Make the gutter background visible and keep digits "invisible" to keep pixel tests deterministic.
            EcuStyleColors {
                style_id: editor_core_render_skia::GUTTER_BACKGROUND_STYLE_ID,
                flags: ECU_STYLE_FLAG_BACKGROUND,
                foreground: EcuRgba8 {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 0,
                },
                background: EcuRgba8 {
                    r: 1,
                    g: 2,
                    b: 3,
                    a: 255,
                },
            },
            EcuStyleColors {
                style_id: editor_core_render_skia::GUTTER_FOREGROUND_STYLE_ID,
                flags: ECU_STYLE_FLAG_FOREGROUND,
                foreground: EcuRgba8 {
                    r: 1,
                    g: 2,
                    b: 3,
                    a: 255,
                },
                background: EcuRgba8 {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 0,
                },
            },
            EcuStyleColors {
                style_id: editor_core_render_skia::FOLD_MARKER_EXPANDED_STYLE_ID,
                flags: ECU_STYLE_FLAG_BACKGROUND,
                foreground: EcuRgba8 {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 0,
                },
                background: EcuRgba8 {
                    r: 9,
                    g: 9,
                    b: 9,
                    a: 255,
                },
            },
            EcuStyleColors {
                style_id: editor_core_render_skia::FOLD_MARKER_COLLAPSED_STYLE_ID,
                flags: ECU_STYLE_FLAG_BACKGROUND,
                foreground: EcuRgba8 {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 0,
                },
                background: EcuRgba8 {
                    r: 8,
                    g: 8,
                    b: 8,
                    a: 255,
                },
            },
        ];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 60 * 4];
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

        // Expanded fold marker at first gutter cell.
        assert_eq!(pixel(&buf, 200, 5, 10), [9, 9, 9, 255]);
        // Gutter background in second cell (avoid line number glyph area).
        assert_eq!(pixel(&buf, 200, 19, 10), [1, 2, 3, 255]);

        // Click in gutter should toggle fold collapse.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_mouse_down(ui, 5.0, 10.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len
            ),
            ECU_OK
        );
        assert_eq!(pixel(&buf, 200, 5, 10), [8, 8, 8, 255]);

        // And expand again on second click.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_mouse_down(ui, 5.0, 10.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len
            ),
            ECU_OK
        );
        assert_eq!(pixel(&buf, 200, 5, 10), [9, 9, 9, 255]);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_move_and_modify_selection_extends_from_anchor() {
        let initial = CString::new("abc\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let ranges = [EcuSelectionRange { start: 2, end: 2 }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0),
            ECU_OK
        );

        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(ui),
            ECU_OK
        );
        let mut s: u32 = 0;
        let mut e: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e),
            ECU_OK
        );
        assert_eq!((s, e), (1, 2));

        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(ui),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e),
            ECU_OK
        );
        assert_eq!((s, e), (0, 2));

        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(ui),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e),
            ECU_OK
        );
        assert_eq!((s, e), (1, 2));

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_lsp_diagnostics_affect_rendering() {
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let initial = CString::new("a c\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let theme = EcuTheme {
            background: EcuRgba8 {
                r: 10,
                g: 20,
                b: 30,
                a: 255,
            },
            foreground: EcuRgba8 {
                r: 250,
                g: 250,
                b: 250,
                a: 255,
            },
            selection_background: EcuRgba8 {
                r: 200,
                g: 0,
                b: 0,
                a: 255,
            },
            caret: EcuRgba8 {
                r: 0,
                g: 0,
                b: 200,
                a: 255,
            },
        };
        assert_eq!(editor_core_ui_ffi_editor_ui_set_theme(ui, &theme), ECU_OK);
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        // LSP diagnostics style id encoding: 0x0400_0000 | severity.
        let styles = [EcuStyleColors {
            style_id: 0x0400_0000 | 1,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 1,
                g: 200,
                b: 2,
                a: 255,
            },
        }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32),
            ECU_OK
        );

        let params = CString::new(
            r#"{
              "uri": "file:///test",
              "diagnostics": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 2 }
                  },
                  "severity": 1,
                  "message": "unit"
                }
              ],
              "version": 1
            }"#,
        )
        .unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(ui, params.as_ptr()),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
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

        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_lsp_semantic_tokens_affect_rendering() {
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let initial = CString::new("a c\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let theme = EcuTheme {
            background: EcuRgba8 {
                r: 10,
                g: 20,
                b: 30,
                a: 255,
            },
            foreground: EcuRgba8 {
                r: 250,
                g: 250,
                b: 250,
                a: 255,
            },
            selection_background: EcuRgba8 {
                r: 200,
                g: 0,
                b: 0,
                a: 255,
            },
            caret: EcuRgba8 {
                r: 0,
                g: 0,
                b: 200,
                a: 255,
            },
        };
        assert_eq!(editor_core_ui_ffi_editor_ui_set_theme(ui, &theme), ECU_OK);
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        let style_id = (7u32 << 16) | 0u32;
        let styles = [EcuStyleColors {
            style_id,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 1,
                g: 200,
                b: 2,
                a: 255,
            },
        }];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32),
            ECU_OK
        );

        let data = [0u32, 1, 1, 7, 0];
        assert_eq!(
            editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
                ui,
                data.as_ptr(),
                data.len() as u32
            ),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
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

        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_set_font_families_csv_accepts_unknown_and_rejects_invalid_utf8() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let fonts = CString::new("Menlo, PingFang SC, Apple Color Emoji").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_font_families_csv(ui, fonts.as_ptr()),
            ECU_OK
        );

        // Unknown fonts should still succeed (renderer falls back to a default typeface).
        let unknown = CString::new("ThisFontShouldNotExist-xyz").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_font_families_csv(ui, unknown.as_ptr()),
            ECU_OK
        );

        // Invalid UTF-8 must be rejected with a non-empty last error message.
        let bad_bytes: [u8; 2] = [0xFF, 0x00];
        let code = editor_core_ui_ffi_editor_ui_set_font_families_csv(
            ui,
            bad_bytes.as_ptr() as *const c_char,
        );
        assert_ne!(code, ECU_OK);

        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        editor_core_ui_ffi_string_free(msg_ptr);
        assert!(msg.to_lowercase().contains("utf-8") || !msg.is_empty());

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_set_font_ligatures_enabled_smoke() {
        let initial = CString::new("a->b != c").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0);

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(ui, 1),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
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

        // Turning ligatures off again should also succeed.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(ui, 0),
            ECU_OK
        );

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
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
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

        // Inline/preedit: selection inside marked string.
        let marked2 = CString::new("你好").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_marked_text_ex(
                ui,
                marked2.as_ptr(),
                1,                 // selected_start inside "你好"
                0,                 // selected_len
                u32::MAX,          // replace_start: use existing marked range
                0                  // replace_len (ignored)
            ),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end),
            ECU_OK
        );
        assert_eq!((start, end), (1, 1));

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    #[test]
    fn ffi_view_point_hit_test_returns_char_offset() {
        let initial = CString::new("abcd\nefgh\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 60, 1.0);

        // Point at row 0, col ~2.
        let mut off: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 25.0, 10.0, &mut off),
            ECU_OK
        );
        assert_eq!(off, 2);

        editor_core_ui_ffi_editor_ui_free(ui);
    }

    fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
        let idx = ((y * width_px + x) * 4) as usize;
        [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
