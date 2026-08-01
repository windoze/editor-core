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
use editor_core_ui::{ChromeTheme, EditorUi, UiError};
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
        let viewport_width_cells = u32_to_usize(viewport_width_cells, "viewport_width_cells")?;
        let ui = EditorUi::new(initial, viewport_width_cells);
        Ok(Box::into_raw(Box::new(ui)))
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            default
        }
    }
}

/// Clone an Editor UI handle as a new view (shared document/buffer, independent view state).
///
/// Returns null on error and sets last error message.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_clone_view(
    ui: *mut EditorUi,
    viewport_width_cells: u32,
) -> *mut EditorUi {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let viewport_width_cells = u32_to_usize(viewport_width_cells, "viewport_width_cells")?;
        let cloned = ui.clone_view(viewport_width_cells).map_err(map_ui_error)?;
        Ok(Box::into_raw(Box::new(cloned)))
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            default
        }
    }
}

/// Free an Editor UI handle.
///
/// # Safety
///
/// `ui` must be a valid pointer returned by `editor_core_ui_ffi_editor_ui_new`, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_free(ui: *mut EditorUi) {
    if ui.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(ui));
    }
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `theme` must be a valid pointer to an `EcuTheme`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_theme(
    ui: *mut EditorUi,
    theme: *const EcuTheme,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if theme.is_null() {
            return Err(invalid_argument("theme is null"));
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

/// Replace the current UI chrome theme (gutter, fold marker colors, ...).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `theme` must be a valid pointer to an `EcuChromeTheme`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_chrome_theme(
    ui: *mut EditorUi,
    theme: *const EcuChromeTheme,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if theme.is_null() {
            return Err(invalid_argument("theme is null"));
        }
        let theme = unsafe { &*theme };
        ui.set_chrome_theme(chrome_theme_from_ffi(theme));
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
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `styles` must be a valid pointer to an array of `EcuStyleColors` with at least `style_count` elements.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_style_colors(
    ui: *mut EditorUi,
    styles: *const EcuStyleColors,
    style_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if styles.is_null() && style_count != 0 {
            return Err(invalid_argument("styles is null"));
        }

        let mut map = BTreeMap::<u32, StyleColors>::new();
        if style_count != 0 {
            let slice =
                unsafe { ffi_slice_from_raw_parts(styles, style_count, "styles", "style_count")? };
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

/// Replace the current theme's `StyleId -> font style` override map.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `fonts` must be a valid pointer to an array of `EcuStyleFont` with at least `font_count` elements.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_style_fonts(
    ui: *mut EditorUi,
    fonts: *const EcuStyleFont,
    font_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if fonts.is_null() && font_count != 0 {
            return Err(invalid_argument("fonts is null"));
        }

        let mut map = BTreeMap::<u32, StyleFont>::new();
        if font_count != 0 {
            let slice =
                unsafe { ffi_slice_from_raw_parts(fonts, font_count, "fonts", "font_count")? };
            for entry in slice {
                let (style_id, font) = style_font_from_ffi(entry);
                map.insert(style_id, font);
            }
        }

        ui.set_style_fonts(map);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Replace the current theme's `StyleId -> text decorations` override map.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `decorations` must be a valid pointer to an array of `EcuStyleTextDecorations` with at least `decoration_count` elements.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_style_text_decorations(
    ui: *mut EditorUi,
    decorations: *const EcuStyleTextDecorations,
    decoration_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if decorations.is_null() && decoration_count != 0 {
            return Err(invalid_argument("decorations is null"));
        }

        let mut map = BTreeMap::<u32, TextDecorations>::new();
        if decoration_count != 0 {
            let slice = unsafe {
                ffi_slice_from_raw_parts(
                    decorations,
                    decoration_count,
                    "decorations",
                    "decoration_count",
                )?
            };
            for entry in slice {
                let (style_id, decos) = text_decorations_from_ffi(entry)?;
                map.insert(style_id, decos);
            }
        }

        ui.set_style_text_decorations(map);
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_sublime_disable(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.disable_sublime_syntax();
        Ok(())
    });
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `scope_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_style_id` must be a valid pointer to a `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(
    ui: *mut EditorUi,
    scope_utf8: *const c_char,
    out_style_id: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_style_id.is_null() {
            return Err(invalid_argument("out_style_id is null"));
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
            set_last_error_from_error(err);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_set_registry_json(
    ui: *mut EditorUi,
    registry_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let registry_json = require_cstr(registry_json_utf8, "registry_json_utf8")?
            .to_str()
            .map_err(|_| "registry_json_utf8 is not valid UTF-8".to_string())?;

        ui.set_treesitter_registry_json(registry_json)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_enable_language(
    ui: *mut EditorUi,
    language_id_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let language_id = require_cstr(language_id_utf8, "language_id_utf8")?
            .to_str()
            .map_err(|_| "language_id_utf8 is not valid UTF-8".to_string())?;
        ui.set_treesitter_language(language_id)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_enable_for_path(
    ui: *mut EditorUi,
    path_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let path = require_cstr(path_utf8, "path_utf8")?
            .to_str()
            .map_err(|_| "path_utf8 is not valid UTF-8".to_string())?;
        ui.set_treesitter_for_path(std::path::Path::new(path))
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_enable_query_pack(
    ui: *mut EditorUi,
    pack_id_utf8: *const c_char,
) -> c_int {
    // Backwards-compatible alias: treat pack id as language id.
    editor_core_ui_ffi_editor_ui_treesitter_enable_language(ui, pack_id_utf8)
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_disable(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.disable_treesitter();
        Ok(())
    });
}

/// Enable an stdio LSP session for the current document.
///
/// Notes:
/// - `args_utf8` may be null or an empty string; when present it is split by whitespace.
/// - `root_uri_utf8` / `doc_uri_utf8` should be `file:///...` URIs for best server behavior.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// All C string parameters must be valid null-terminated UTF-8 pointers or null where allowed.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_enable(
    ui: *mut EditorUi,
    cmd_utf8: *const c_char,
    args_utf8: *const c_char,
    root_uri_utf8: *const c_char,
    doc_uri_utf8: *const c_char,
    language_id_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let cmd = require_cstr(cmd_utf8, "cmd_utf8")?
            .to_str()
            .map_err(|_| "cmd_utf8 is not valid UTF-8".to_string())?;
        let root_uri = require_cstr(root_uri_utf8, "root_uri_utf8")?
            .to_str()
            .map_err(|_| "root_uri_utf8 is not valid UTF-8".to_string())?;
        let doc_uri = require_cstr(doc_uri_utf8, "doc_uri_utf8")?
            .to_str()
            .map_err(|_| "doc_uri_utf8 is not valid UTF-8".to_string())?;
        let language_id = require_cstr(language_id_utf8, "language_id_utf8")?
            .to_str()
            .map_err(|_| "language_id_utf8 is not valid UTF-8".to_string())?;

        let args = if args_utf8.is_null() {
            Vec::<String>::new()
        } else {
            let s = require_cstr(args_utf8, "args_utf8")?
                .to_str()
                .map_err(|_| "args_utf8 is not valid UTF-8".to_string())?;
            s.split_whitespace().map(|p| p.to_string()).collect()
        };

        ui.lsp_enable_stdio(cmd, &args, root_uri, doc_uri, language_id)
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_disable(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.lsp_disable();
        Ok(())
    });
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_enabled` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_is_enabled(
    ui: *mut EditorUi,
    out_enabled: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_enabled.is_null() {
            return Err(invalid_argument("out_enabled is null"));
        }
        unsafe {
            *out_enabled = if ui.lsp_is_enabled() { 1 } else { 0 };
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

/// Return a best-effort LSP status snapshot as JSON.
///
/// - `out_status_json_utf8` receives a newly allocated string that must be freed with
///   `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_status_json_utf8` must be a valid pointer to a `*mut c_char`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_status_json(
    ui: *mut EditorUi,
    out_status_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_status_json_utf8.is_null() {
            return Err(invalid_argument("out_status_json_utf8 is null"));
        }

        unsafe {
            *out_status_json_utf8 = ptr::null_mut();
        }

        let json = ui.lsp_status_json();
        unsafe {
            *out_status_json_utf8 = make_c_string_ptr(json);
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

/// Request LSP hover for a logical position (0-based line/column in Unicode scalars).
///
/// This is non-blocking: the result arrives asynchronously and can be read via
/// `editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json` after polling processing.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_request_id` must be a valid pointer to a `u64`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_hover(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = ui
            .lsp_request_hover(u32_to_usize(line, "line")?, u32_to_usize(column, "column")?)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

/// Take the last LSP hover result payload as JSON (`Hover | null`).
///
/// - On success, returns `ECU_OK` and sets:
///   - `out_has_result = 1` and `out_result_json_utf8` to a newly allocated string, or
///   - `out_has_result = 0` and `out_result_json_utf8 = NULL` when there is no new result.
///
/// Caller must free the returned string with `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_result` and `out_result_json_utf8` must be valid pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = ui.lsp_take_last_hover_result_json();
        unsafe {
            if let Some(json) = json {
                *out_has_result = 1;
                *out_result_json_utf8 = make_c_string_ptr(json);
            } else {
                *out_has_result = 0;
                *out_result_json_utf8 = ptr::null_mut();
            }
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

/// Request LSP go-to-definition for a logical position (0-based line/column in Unicode scalars).
///
/// This is non-blocking: the result arrives asynchronously and can be read via
/// `editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json` after polling processing.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_request_id` must be a valid pointer to a `u64`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_definition(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = ui
            .lsp_request_definition(u32_to_usize(line, "line")?, u32_to_usize(column, "column")?)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

/// Take the last LSP go-to-definition result payload as JSON (`Definition | null`).
///
/// - On success, returns `ECU_OK` and sets:
///   - `out_has_result = 1` and `out_result_json_utf8` to a newly allocated string, or
///   - `out_has_result = 0` and `out_result_json_utf8 = NULL` when there is no new result.
///
/// Caller must free the returned string with `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_result` and `out_result_json_utf8` must be valid pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = ui.lsp_take_last_definition_result_json();
        unsafe {
            if let Some(json) = json {
                *out_has_result = 1;
                *out_result_json_utf8 = make_c_string_ptr(json);
            } else {
                *out_has_result = 0;
                *out_result_json_utf8 = ptr::null_mut();
            }
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

fn lsp_request_position_ffi(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
    request: impl FnOnce(&mut EditorUi, usize, usize) -> Result<u64, editor_core_ui::UiError>,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = request(
            ui,
            u32_to_usize(line, "line")?,
            u32_to_usize(column, "column")?,
        )
        .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

fn lsp_request_no_position_ffi(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
    request: impl FnOnce(&mut EditorUi) -> Result<u64, editor_core_ui::UiError>,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = request(ui).map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

fn lsp_take_result_json_ffi(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
    take: impl FnOnce(&mut EditorUi) -> Option<String>,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = take(ui);
        unsafe {
            if let Some(json) = json {
                *out_has_result = 1;
                *out_result_json_utf8 = make_c_string_ptr(json);
            } else {
                *out_has_result = 0;
                *out_result_json_utf8 = ptr::null_mut();
            }
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_declaration(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_declaration(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_declaration_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_declaration_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_type_definition(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_type_definition(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_type_definition_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_type_definition_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_implementation(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_implementation(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_implementation_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_implementation_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_references(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    include_declaration: u8,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_references(line, column, include_declaration != 0)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_references_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_references_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_completion(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_completion(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_completion_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_completion_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_signature_help(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_signature_help(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_signature_help_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_signature_help_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_prepare_rename(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_prepare_rename(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_rename_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_prepare_rename_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_rename(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    new_name_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let new_name = require_cstr(new_name_utf8, "new_name_utf8")?
            .to_str()
            .map_err(|_| "new_name_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_rename(
                u32_to_usize(line, "line")?,
                u32_to_usize(column, "column")?,
                new_name,
            )
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_rename_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_rename_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_code_action(
    ui: *mut EditorUi,
    start_offset: u32,
    end_offset: u32,
    context_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let context_json = require_cstr(context_json_utf8, "context_json_utf8")?
            .to_str()
            .map_err(|_| "context_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_code_action(
                u32_to_usize(start_offset, "start_offset")?,
                u32_to_usize(end_offset, "end_offset")?,
                context_json,
            )
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_code_action_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_code_action_resolve(
    ui: *mut EditorUi,
    action_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let action_json = require_cstr(action_json_utf8, "action_json_utf8")?
            .to_str()
            .map_err(|_| "action_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_code_action_resolve(action_json)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_resolve_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_code_action_resolve_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_execute_command(
    ui: *mut EditorUi,
    command_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let command_json = require_cstr(command_json_utf8, "command_json_utf8")?
            .to_str()
            .map_err(|_| "command_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_execute_command(command_json)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_execute_command_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_execute_command_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_document_symbols(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_no_position_ffi(ui, out_request_id, |ui| ui.lsp_request_document_symbols())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_document_symbols_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_document_symbols_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_workspace_symbols(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let query = require_cstr(query_utf8, "query_utf8")?
            .to_str()
            .map_err(|_| "query_utf8 is not valid UTF-8".to_string())?;
        let id = ui
            .lsp_request_workspace_symbols(query)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_symbols_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_workspace_symbols_result_json()
    })
}

/// Format the current document via LSP (`textDocument/formatting`) and apply edits locally.
///
/// - `formatting_options_json_utf8`: optional JSON `FormattingOptions` object; pass `NULL` or an
///   empty string to use a small default.
/// - `timeout_ms`: maximum time to wait for the response.
/// - `out_applied`: set to 1 if any edits were applied.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_applied` must be a valid pointer to `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_format_document(
    ui: *mut EditorUi,
    formatting_options_json_utf8: *const c_char,
    timeout_ms: u32,
    out_applied: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }

        let options = if formatting_options_json_utf8.is_null() {
            ""
        } else {
            require_cstr(formatting_options_json_utf8, "formatting_options_json_utf8")?
                .to_str()
                .map_err(|_| "formatting_options_json_utf8 is not valid UTF-8".to_string())?
        };

        let applied = ui
            .lsp_format_document(options, timeout_ms)
            .map_err(map_ui_error)?;
        unsafe {
            *out_applied = if applied { 1 } else { 0 };
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

/// Poll and apply any completed async processing (Tree-sitter highlighting/folding).
///
/// This is non-blocking: it never waits for the worker thread.
///
/// - `out_applied`: set to 1 if new edits were applied.
/// - `out_pending`: set to 1 if there is still pending work.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_applied` and `out_pending` must be valid pointers to `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_poll_processing(
    ui: *mut EditorUi,
    out_applied: *mut u8,
    out_pending: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }
        if out_pending.is_null() {
            return Err(invalid_argument("out_pending is null"));
        }

        let result = ui.poll_processing().map_err(map_ui_error)?;
        unsafe {
            *out_applied = if result.applied { 1 } else { 0 };
            *out_pending = if result.pending { 1 } else { 0 };
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `capture_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_style_id` must be a valid pointer to a `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(
    ui: *mut EditorUi,
    capture_utf8: *const c_char,
    out_style_id: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_style_id.is_null() {
            return Err(invalid_argument("out_style_id is null"));
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
            set_last_error_from_error(err);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(
    ui: *mut EditorUi,
    inlay_hints_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(inlay_hints_result_json_utf8, "inlay_hints_result_json_utf8")?
            .to_str()
            .map_err(|_| "inlay_hints_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_inlay_hints_json(json)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(
    ui: *mut EditorUi,
    code_lens_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(code_lens_result_json_utf8, "code_lens_result_json_utf8")?
            .to_str()
            .map_err(|_| "code_lens_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_code_lens_json(json)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(
    ui: *mut EditorUi,
    document_links_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            document_links_result_json_utf8,
            "document_links_result_json_utf8",
        )?
        .to_str()
        .map_err(|_| "document_links_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_document_links_json(json)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(
    ui: *mut EditorUi,
    document_highlights_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            document_highlights_result_json_utf8,
            "document_highlights_result_json_utf8",
        )?
        .to_str()
        .map_err(|_| "document_highlights_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_document_highlights_json(json)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_json(
    ui: *mut EditorUi,
    document_symbols_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            document_symbols_result_json_utf8,
            "document_symbols_result_json_utf8",
        )?
        .to_str()
        .map_err(|_| "document_symbols_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_document_symbols_json(json)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(
    ui: *mut EditorUi,
    workspace_edit_json_utf8: *const c_char,
    document_uri_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let workspace_edit_json =
            require_cstr(workspace_edit_json_utf8, "workspace_edit_json_utf8")?
                .to_str()
                .map_err(|_| "workspace_edit_json_utf8 is not valid UTF-8".to_string())?;
        let document_uri = if document_uri_utf8.is_null() {
            None
        } else {
            Some(
                require_cstr(document_uri_utf8, "document_uri_utf8")?
                    .to_str()
                    .map_err(|_| "document_uri_utf8 is not valid UTF-8".to_string())?,
            )
        };
        ui.lsp_apply_workspace_edit_json(workspace_edit_json, document_uri)
            .map(make_c_string_ptr)
            .map_err(map_ui_error)
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error(err);
            ptr::null_mut()
        }
    }
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `data` must be a valid pointer to an array of `u32` with at least `data_len` elements,
/// or null if `data_len` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
    ui: *mut EditorUi,
    data: *const u32,
    data_len: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if data.is_null() && data_len != 0 {
            return Err(invalid_argument("data is null"));
        }
        let slice = unsafe { ffi_slice_from_raw_parts(data, data_len, "data", "data_len")? };
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_text_vertical_align(
    ui: *mut EditorUi,
    align: u8,
) -> c_int {
    match ffi_catch(|| {
        use editor_core_render_skia::TextVerticalAlign;

        let ui = require_mut(ui, "ui")?;
        let align = match align {
            0 => TextVerticalAlign::Top,
            1 => TextVerticalAlign::Center,
            2 => TextVerticalAlign::Bottom,
            _ => return Err(format!("invalid text vertical align: {align}")),
        };
        ui.set_text_vertical_align(align);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_caret_width_px(
    ui: *mut EditorUi,
    width_px: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_caret_width_px(width_px);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_caret_visible(
    ui: *mut EditorUi,
    visible: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_caret_visible(visible != 0);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_indent_guides_enabled(
    ui: *mut EditorUi,
    enabled: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_indent_guides_enabled(enabled != 0);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_whitespace_render_mode(
    ui: *mut EditorUi,
    mode: u8,
) -> c_int {
    match ffi_catch(|| {
        use editor_core_render_skia::WhitespaceRenderMode;

        let ui = require_mut(ui, "ui")?;
        let mode = match mode {
            0 => WhitespaceRenderMode::None,
            1 => WhitespaceRenderMode::Selection,
            2 => WhitespaceRenderMode::All,
            _ => return Err(format!("invalid whitespace render mode: {mode}")),
        };
        ui.set_whitespace_render_mode(mode);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_fold_marker_style(
    ui: *mut EditorUi,
    style: u8,
) -> c_int {
    match ffi_catch(|| {
        use editor_core_render_skia::FoldMarkerStyle;

        let ui = require_mut(ui, "ui")?;
        let style = match style {
            0 => FoldMarkerStyle::Hidden,
            1 => FoldMarkerStyle::Block,
            2 => FoldMarkerStyle::Triangle,
            _ => return Err(format!("invalid fold marker style: {style}")),
        };
        ui.set_fold_marker_style(style);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_tab_width(
    ui: *mut EditorUi,
    width_cells: u32,
) -> c_int {
    if width_cells == 0 {
        return status_from_invalid_argument("width_cells must be > 0".to_string());
    }

    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_tab_width(u32_to_usize(width_cells, "width_cells")?)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_tab_key_behavior(
    ui: *mut EditorUi,
    behavior: u8,
) -> c_int {
    match ffi_catch(|| {
        use editor_core::TabKeyBehavior;

        let ui = require_mut(ui, "ui")?;
        let behavior = match behavior {
            0 => TabKeyBehavior::Tab,
            1 => TabKeyBehavior::Spaces,
            _ => return Err(format!("invalid tab key behavior: {behavior}")),
        };
        ui.set_tab_key_behavior(behavior)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_auto_pairs_enabled(
    ui: *mut EditorUi,
    enabled: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_auto_pairs_enabled(enabled != 0)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_bracket_match_highlights_enabled(
    ui: *mut EditorUi,
    enabled: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_bracket_match_highlights_enabled(enabled != 0)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_word_boundary_ascii_boundary_chars(
    ui: *mut EditorUi,
    boundary_chars_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let boundary_chars = require_cstr(boundary_chars_utf8, "boundary_chars_utf8")?
            .to_str()
            .map_err(|_| "boundary_chars_utf8 is not valid UTF-8".to_string())?;
        ui.set_word_boundary_ascii_boundary_chars(boundary_chars)
            .map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_reset_word_boundary_defaults(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.reset_word_boundary_defaults().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_logical_line_count(
    ui: *mut EditorUi,
    out_count: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out = require_out_mut(out_count, "out_count")?;
        *out = ui.logical_line_count();
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_gutter_width_cells(
    ui: *mut EditorUi,
    out_width_cells: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out = require_out_mut(out_width_cells, "out_width_cells")?;
        *out = ui.gutter_width_cells();
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_scroll_by_rows(
    ui: *mut EditorUi,
    delta_rows: c_int,
) {
    if ui.is_null() {
        set_last_error_from_error(invalid_argument("ui is null"));
        return;
    }
    let ui = unsafe { &mut *ui };
    ui.scroll_by_rows(delta_rows as isize);
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_scroll_by_pixels(
    ui: *mut EditorUi,
    delta_y_px: c_float,
) {
    if ui.is_null() {
        set_last_error_from_error(invalid_argument("ui is null"));
        return;
    }
    let ui = unsafe { &mut *ui };
    ui.scroll_by_pixels(delta_y_px);
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_viewport_state(
    ui: *mut EditorUi,
    out_state: *mut EcuViewportState,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out = require_out_mut(out_state, "out_state")?;

        let vp = ui.viewport_state();
        *out = EcuViewportState {
            width_cells: usize_to_u32(vp.width, "viewport width")?,
            height_rows: usize_to_u32(vp.height.unwrap_or_default(), "viewport height")?,
            has_height: if vp.height.is_some() { 1 } else { 0 },
            scroll_top: usize_to_u32(vp.scroll_top, "viewport scroll_top")?,
            sub_row_offset: u32::from(vp.sub_row_offset),
            overscan_rows: usize_to_u32(vp.overscan_rows, "viewport overscan_rows")?,
            visible_start: usize_to_u32(vp.visible_lines.start, "viewport visible_start")?,
            visible_end: usize_to_u32(vp.visible_lines.end, "viewport visible_end")?,
            prefetch_start: usize_to_u32(vp.prefetch_lines.start, "viewport prefetch_start")?,
            prefetch_end: usize_to_u32(vp.prefetch_lines.end, "viewport prefetch_end")?,
            total_visual_lines: usize_to_u32(vp.total_visual_lines, "viewport total_visual_lines")?,
        };

        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(
    ui: *mut EditorUi,
    top_visual_row: u32,
    sub_row_offset: u32,
) {
    ffi_void(|| {
        let ui = require_mut(ui, "ui")?;
        let top_visual_row = u32_to_usize(top_visual_row, "top_visual_row")?;
        ui.set_smooth_scroll_state(top_visual_row, (sub_row_offset.min(u16::MAX as u32)) as u16);
        Ok(())
    });
}

/// Reveal the primary caret by adjusting the viewport scroll position (best-effort).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_reveal_primary_caret(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.reveal_primary_caret();
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

/// Execute one editor command encoded as JSON and return the command-result JSON.
///
/// The JSON schema matches the headless FFI command plane, with UI additions for snippets,
/// auto-pairs config, and bracket-match highlight commands. Caller owns the returned string and
/// must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_execute_command_json(
    ui: *mut EditorUi,
    command_json_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let command_json = require_str(command_json_utf8, "command_json_utf8")?;
        ui.execute_command_json(command_json).map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Export current diagnostics for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_diagnostics_json(ui: *mut EditorUi) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.diagnostics_json().map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Export current decoration layers for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_decorations_json(ui: *mut EditorUi) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.decorations_json().map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Export current document symbols for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_document_symbols_json(
    ui: *mut EditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.document_symbols_json().map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Export current folding regions for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_folding_regions_json(
    ui: *mut EditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.folding_regions_json().map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Export current style intervals overlapping `[start, end)` as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_style_intervals_json(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.style_intervals_json(u32_to_usize(start, "start")?, u32_to_usize(end, "end")?)
            .map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_insert_tab(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.insert_tab().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_insert_backtab(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.insert_backtab().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Check whether a snippet session (placeholders + tabstop navigation) is currently active.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_active` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_has_active_snippet_session(
    ui: *mut EditorUi,
    out_active: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_active.is_null() {
            return Err(invalid_argument("out_active is null"));
        }
        let active = ui.has_active_snippet_session().map_err(map_ui_error)?;
        unsafe {
            *out_active = if active { 1 } else { 0 };
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_word_back(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_word_back().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_word_forward(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_word_forward()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_style(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
    style_id: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_style(
            u32_to_usize(start, "start")?,
            u32_to_usize(end, "end")?,
            style_id,
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_remove_style(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
    style_id: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.remove_style(
            u32_to_usize(start, "start")?,
            u32_to_usize(end, "end")?,
            style_id,
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

/// Replace match highlight ranges (e.g. search matches) as a style overlay layer.
///
/// - `ranges` are character-offset ranges (inclusive-exclusive).
/// - Passing `range_count = 0` clears the layer (and allows `ranges` to be null).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `ranges` must be a valid pointer to an array of `EcuSelectionRange` with at least `range_count` elements,
/// or null if `range_count` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_match_highlights(
    ui: *mut EditorUi,
    ranges: *const EcuSelectionRange,
    range_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        if range_count == 0 {
            ui.set_match_highlights_offsets(&[]);
            return Ok(ECU_OK);
        }
        if ranges.is_null() {
            return Err(invalid_argument("ranges is null"));
        }

        let ranges =
            unsafe { ffi_slice_from_raw_parts(ranges, range_count, "ranges", "range_count")? };
        let mut out: Vec<(usize, usize)> = Vec::with_capacity(ranges.len());
        for r in ranges {
            out.push((
                u32_to_usize(r.start, "range start")?,
                u32_to_usize(r.end, "range end")?,
            ));
        }

        ui.set_match_highlights_offsets(&out);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_match_count` must be a valid pointer to a `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_search_set_query(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_match_count: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let count = ui.search_set_query(query, options).map_err(map_ui_error)?;
        if !out_match_count.is_null() {
            unsafe {
                *out_match_count = usize_to_u32(count, "match count")?;
            }
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_search_clear(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.search_clear();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_found` must be a valid pointer to a `u8`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_find_next(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_found: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let found = ui.find_next(query, options).map_err(map_ui_error)?;
        if !out_found.is_null() {
            unsafe {
                *out_found = if found { 1 } else { 0 };
            }
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_found` must be a valid pointer to a `u8`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_find_prev(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_found: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let found = ui.find_prev(query, options).map_err(map_ui_error)?;
        if !out_found.is_null() {
            unsafe {
                *out_found = if found { 1 } else { 0 };
            }
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` and `replacement_utf8` must be valid null-terminated UTF-8 C string pointers.
/// `out_replaced` must be a valid pointer to a `u32`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_replace_current(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    replacement_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_replaced: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let replacement = require_str(replacement_utf8, "replacement_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let replaced = ui
            .replace_current(query, replacement, options)
            .map_err(map_ui_error)?;
        if !out_replaced.is_null() {
            unsafe {
                *out_replaced = usize_to_u32(replaced, "replace count")?;
            }
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` and `replacement_utf8` must be valid null-terminated UTF-8 C string pointers.
/// `out_replaced` must be a valid pointer to a `u32`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_replace_all(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    replacement_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_replaced: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let replacement = require_str(replacement_utf8, "replacement_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let replaced = ui
            .replace_all(query, replacement, options)
            .map_err(map_ui_error)?;
        if !out_replaced.is_null() {
            unsafe {
                *out_replaced = usize_to_u32(replaced, "replace count")?;
            }
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_left(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_left().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_right(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_right().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_matching_bracket(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_matching_bracket()
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

// MARK: - Bookmarks / marks / jump list

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_toggle_bookmark_at_cursor_line(
    ui: *mut EditorUi,
    out_added: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_added = require_mut(out_added, "out_added")?;
        let added = ui.toggle_bookmark_at_cursor_line().map_err(map_ui_error)?;
        *out_added = if added { 1 } else { 0 };
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_goto_next_bookmark(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.goto_next_bookmark().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_goto_prev_bookmark(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.goto_prev_bookmark().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_mark_at_cursor(
    ui: *mut EditorUi,
    name_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let name = require_str(name_utf8, "name_utf8")?;
        ui.set_mark_at_cursor(name.to_string())
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_goto_mark(
    ui: *mut EditorUi,
    name_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let name = require_str(name_utf8, "name_utf8")?;
        let _ = ui.goto_mark(name).map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_push_jump_location(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.push_jump_location().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_jump_back(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.jump_back().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_jump_forward(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.jump_forward().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_start(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_start()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_end(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_end()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_start(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_start()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_end(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_end()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_pages(
    ui: *mut EditorUi,
    delta_pages: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_pages(delta_pages as isize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_left_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_left_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_right_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_right_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_start_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_start_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_end_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_end_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_start_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_start_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_end_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_end_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_pages_and_modify_selection(
    ui: *mut EditorUi,
    delta_pages: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_pages_and_modify_selection(delta_pages as isize)
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
        ui.add_cursor_above().map(|_| ECU_OK).map_err(map_ui_error)
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
        ui.add_cursor_below().map(|_| ECU_OK).map_err(map_ui_error)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_line_selection_offsets(
    ui: *mut EditorUi,
    anchor_offset: u32,
    active_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_line_selection_offsets(
            u32_to_usize(anchor_offset, "anchor_offset")?,
            u32_to_usize(active_offset, "active_offset")?,
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_select_paragraph_at_char_offset(
    ui: *mut EditorUi,
    char_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.select_paragraph_at_char_offset(u32_to_usize(char_offset, "char_offset")?)
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
        ui.set_paragraph_selection_offsets(
            u32_to_usize(anchor_offset, "anchor_offset")?,
            u32_to_usize(active_offset, "active_offset")?,
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_expand_selection(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.expand_selection().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_expand_selection_by(
    ui: *mut EditorUi,
    unit: u32,
    count: u32,
    direction: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        let unit = match unit {
            0 => ExpandSelectionUnit::Character,
            1 => ExpandSelectionUnit::Word,
            2 => ExpandSelectionUnit::Line,
            _ => {
                return Err(invalid_argument(format!(
                    "invalid expand selection unit {unit} (expected 0=character, 1=word, 2=line)"
                )));
            }
        };

        let direction = match direction {
            0 => ExpandSelectionDirection::Backward,
            1 => ExpandSelectionDirection::Forward,
            _ => {
                return Err(invalid_argument(format!(
                    "invalid expand selection direction {direction} (expected 0=backward, 1=forward)"
                )));
            }
        };

        ui.expand_selection_by(unit, u32_to_usize(count, "count")?, direction)
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
        ui.add_caret_at_char_offset(u32_to_usize(char_offset, "char_offset")?, make_primary != 0)
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
            Some((
                u32_to_usize(replace_start, "replace_start")?,
                u32_to_usize(replace_len, "replace_len")?,
            ))
        };

        ui.set_marked_text_with_selection(
            text,
            u32_to_usize(selected_start, "selected_start")?,
            u32_to_usize(selected_len, "selected_len")?,
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_unmark_text(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.unmark_text();
        Ok(())
    });
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_paste_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.paste_text(text).map(|_| ECU_OK).map_err(map_ui_error)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_down_ex(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    modifiers: u32,
    click_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        // Bit layout mirrors `editor_core_ui::Modifiers`:
        // - bit0: shift
        // - bit1: ctrl
        // - bit2: alt/option
        // - bit3: meta/cmd
        let mut mods = editor_core_ui::Modifiers::NONE;
        if (modifiers & 0b0001) != 0 {
            mods.insert(editor_core_ui::Modifiers::SHIFT);
        }
        if (modifiers & 0b0010) != 0 {
            mods.insert(editor_core_ui::Modifiers::CTRL);
        }
        if (modifiers & 0b0100) != 0 {
            mods.insert(editor_core_ui::Modifiers::ALT);
        }
        if (modifiers & 0b1000) != 0 {
            mods.insert(editor_core_ui::Modifiers::META);
        }

        let click = click_count.min(u8::MAX as u32) as u8;
        ui.mouse_down_with_modifiers_and_click_count(x_px, y_px, mods, click)
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_mouse_up(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.mouse_up();
        Ok(())
    });
}

/// Render the current visible viewport into an RGBA buffer.
///
/// - The caller provides an output buffer and capacity.
/// - If capacity is insufficient, returns `ECU_ERR_BUFFER_TOO_SMALL` and writes the required size to `out_len`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_len` must be a valid pointer to a `u32`.
/// `out_buf` must be a valid pointer to a buffer with at least `out_cap` bytes, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_render_rgba(
    ui: *mut EditorUi,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_len = require_out_mut(out_len, "out_len")?;

        let required = usize_to_u32(ui.required_rgba_len(), "rgba buffer required length")?;
        *out_len = required;

        if out_buf.is_null() {
            // Two-call pattern: allow caller to query required size.
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        if out_cap < required {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        let dst = unsafe {
            ffi_slice_from_raw_parts_mut(out_buf, required, "out_buf", "required rgba length")?
        };
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

/// Enable Skia Metal backend for this editor instance (macOS only).
///
/// - `metal_device`: `id<MTLDevice>`
/// - `metal_command_queue`: `id<MTLCommandQueue>`
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_enable_metal(
    ui: *mut EditorUi,
    metal_device: *mut c_void,
    metal_command_queue: *mut c_void,
) -> c_int {
    if metal_device.is_null() {
        return status_from_invalid_argument("metal_device is null".to_string());
    }
    if metal_command_queue.is_null() {
        return status_from_invalid_argument("metal_command_queue is null".to_string());
    }

    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.enable_metal(metal_device, metal_command_queue)
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

/// Render the current visible viewport into a Metal texture (macOS only).
///
/// - `metal_texture`: `id<MTLTexture>`
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_render_metal(
    ui: *mut EditorUi,
    metal_texture: *mut c_void,
) -> c_int {
    if metal_texture.is_null() {
        return status_from_invalid_argument("metal_texture is null".to_string());
    }

    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.render_metal_visible_into_texture(metal_texture)
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
            set_last_error_from_error(err);
            default
        }
    }
}

/// Check whether the document is modified (dirty) relative to the last `mark_saved` / clean state.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_modified` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_is_modified(
    ui: *mut EditorUi,
    out_modified: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_modified.is_null() {
            return Err(invalid_argument("out_modified is null"));
        }
        unsafe {
            *out_modified = if ui.is_modified() { 1 } else { 0 };
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

/// Mark the current document state as saved (clean), resetting dirty tracking.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_mark_saved(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.mark_saved();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Get selected text (primary + secondary selections) as UTF-8, joined with `'\n'`.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_selected_text(ui: *mut EditorUi) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        Ok(make_c_string_ptr(ui.selected_text()))
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            default
        }
    }
}

/// Get minimap snapshot as JSON.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_minimap_json(
    ui: *mut EditorUi,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        Ok(make_c_string_ptr(ui.minimap_json(
            u32_to_usize(start_visual_row, "start_visual_row")?,
            u32_to_usize(count, "count")?,
        )))
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            default
        }
    }
}

/// Get primary selection offsets (character offsets).
///
/// Writes `start` and `end` (inclusive-exclusive) offsets.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_start` and `out_end` must be valid pointers to `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_selection_offsets(
    ui: *mut EditorUi,
    out_start: *mut u32,
    out_end: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_start = require_out_mut(out_start, "out_start")?;
        let out_end = require_out_mut(out_end, "out_end")?;
        let (start, end) = ui.primary_selection_offsets();
        *out_start = usize_to_u32(start, "selection start")?;
        *out_end = usize_to_u32(end, "selection end")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Delete only non-empty selections (primary + secondary), keeping empty carets intact.
///
/// This is intended for clipboard "cut" behavior.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_selections_only(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_selections_only()
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

/// Get all selections (including primary) as character-offset ranges.
///
/// - `out_len` receives the required number of ranges.
/// - `out_primary_index` receives the primary selection index.
/// - If `out_ranges` is null or `out_cap` is insufficient, returns `ECU_ERR_BUFFER_TOO_SMALL`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_len` and `out_primary_index` must be valid pointers to `u32`.
/// `out_ranges` must be a valid pointer to a buffer with at least `out_cap` elements, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_selections(
    ui: *mut EditorUi,
    out_ranges: *mut EcuSelectionRange,
    out_cap: u32,
    out_len: *mut u32,
    out_primary_index: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_len = require_out_mut(out_len, "out_len")?;
        let out_primary_index = require_out_mut(out_primary_index, "out_primary_index")?;

        let (ranges, primary) = ui.selections_offsets();
        let required = usize_to_u32(ranges.len(), "selection range count")?;
        let primary = usize_to_u32(primary, "primary selection index")?;
        let converted = ranges
            .into_iter()
            .map(|(start, end)| {
                Ok(EcuSelectionRange {
                    start: usize_to_u32(start, "selection range start")?,
                    end: usize_to_u32(end, "selection range end")?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        *out_len = required;
        *out_primary_index = primary;

        if out_ranges.is_null() {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }
        if out_cap < required {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        let dst = unsafe {
            ffi_slice_from_raw_parts_mut(
                out_ranges,
                required,
                "out_ranges",
                "selection range count",
            )?
        };
        dst.copy_from_slice(&converted);
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
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `ranges` must be a valid pointer to an array of `EcuSelectionRange` with at least `range_count` elements.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_selections(
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

        let slice =
            unsafe { ffi_slice_from_raw_parts(ranges, range_count, "ranges", "range_count")? };
        let mut vec = Vec::with_capacity(slice.len());
        for r in slice {
            vec.push((
                u32_to_usize(r.start, "range start")?,
                u32_to_usize(r.end, "range end")?,
            ));
        }

        ui.set_selections_offsets(
            vec.as_slice(),
            u32_to_usize(primary_index, "primary_index")?,
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

/// Set a rectangular (box) selection from two character offsets.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_rect_selection(
    ui: *mut EditorUi,
    anchor_offset: u32,
    active_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_rect_selection_offsets(
            u32_to_usize(anchor_offset, "anchor_offset")?,
            u32_to_usize(active_offset, "active_offset")?,
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

/// Get IME marked text range.
///
/// If there is no marked text, writes `has_marked = 0` and `out_start/out_len = 0`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_marked` must be a valid pointer to a `u8`.
/// `out_start` and `out_len` must be valid pointers to `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_marked_range(
    ui: *mut EditorUi,
    out_has_marked: *mut u8,
    out_start: *mut u32,
    out_len: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_has_marked = require_out_mut(out_has_marked, "out_has_marked")?;
        let out_start = require_out_mut(out_start, "out_start")?;
        let out_len = require_out_mut(out_len, "out_len")?;

        let (has, start, len) = match ui.marked_range() {
            Some((s, l)) => (
                1u8,
                usize_to_u32(s, "marked range start")?,
                usize_to_u32(l, "marked range length")?,
            ),
            None => (0u8, 0u32, 0u32),
        };
        *out_has_marked = has;
        *out_start = start;
        *out_len = len;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Map a character offset to logical `(line, column)` (both char-indexed).
///
/// - `char_offset` is a Unicode scalar index.
/// - `out_line/out_column` receive 0-based indices.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_line` and `out_column` must be valid pointers to `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_char_offset_to_logical_position(
    ui: *mut EditorUi,
    char_offset: u32,
    out_line: *mut u32,
    out_column: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_line = require_out_mut(out_line, "out_line")?;
        let out_column = require_out_mut(out_column, "out_column")?;

        let (line, col) =
            ui.char_offset_to_logical_position(u32_to_usize(char_offset, "char_offset")?);
        *out_line = usize_to_u32(line, "logical line")?;
        *out_column = usize_to_u32(col, "logical column")?;
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
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_x`, `out_y`, and `out_line_height_px` must be valid pointers to `c_float`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_char_offset_to_view_point(
    ui: *mut EditorUi,
    char_offset: u32,
    out_x: *mut c_float,
    out_y: *mut c_float,
    out_line_height_px: *mut c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_x = require_out_mut(out_x, "out_x")?;
        let out_y = require_out_mut(out_y, "out_y")?;
        let out_line_height_px = require_out_mut(out_line_height_px, "out_line_height_px")?;

        let (x, y) = ui
            .char_offset_to_view_point_px(u32_to_usize(char_offset, "char_offset")?)
            .ok_or_else(|| "failed to map char offset to view point".to_string())?;

        *out_x = x;
        *out_y = y;
        *out_line_height_px = ui.line_height_px();
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
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_char_offset` must be a valid pointer to a `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_view_point_to_char_offset(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    out_char_offset: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_char_offset = require_out_mut(out_char_offset, "out_char_offset")?;
        let offset = ui
            .view_point_to_char_offset(x_px, y_px)
            .ok_or_else(|| "failed to hit-test view point".to_string())?;
        *out_char_offset = usize_to_u32(offset, "char offset")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Hit-test a view point and return the raw LSP `DocumentLink` JSON payload (if present).
///
/// - `out_has_link` is set to 1 when a link is present.
/// - `out_json_utf8` receives a newly allocated string that must be freed with
///   `editor_core_ui_ffi_string_free` (or is set to NULL when no link is present).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_link` must be a valid pointer to a `u8`.
/// `out_json_utf8` must be a valid pointer to a `*mut c_char`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    out_has_link: *mut u8,
    out_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_link.is_null() {
            return Err(invalid_argument("out_has_link is null"));
        }

        unsafe {
            *out_has_link = 0;
        }
        if !out_json_utf8.is_null() {
            unsafe {
                *out_json_utf8 = ptr::null_mut();
            }
        }

        let Some(json) = ui.document_link_json_at_view_point_px(x_px, y_px) else {
            return Ok(ECU_OK);
        };

        unsafe {
            *out_has_link = 1;
        }

        if out_json_utf8.is_null() {
            return Ok(ECU_OK);
        }

        unsafe {
            *out_json_utf8 = make_c_string_ptr(json);
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
    use std::ptr;

    fn wait_for_processing(ui: *mut EditorUi) {
        let start = std::time::Instant::now();
        loop {
            let mut applied: u8 = 0;
            let mut pending: u8 = 0;
            assert_eq!(
                unsafe {
                    editor_core_ui_ffi_editor_ui_poll_processing(ui, &mut applied, &mut pending)
                },
                ECU_OK
            );
            if pending == 0 {
                break;
            }
            if start.elapsed() > std::time::Duration::from_secs(2) {
                panic!("timeout waiting for async processing");
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }

    fn set_test_treesitter_registry(ui: *mut EditorUi) {
        // Keep the tree-sitter worker at normal priority in tests so a single grammar load/parse
        // finishes within the bounded wait window (see editor-core-ui's QoS helper). Set here,
        // before any worker is spawned by treesitter_set_language below.
        // SAFETY: test-only; called on the main test thread before spawning the worker.
        unsafe { std::env::set_var("EDITOR_CORE_DISABLE_TS_WORKER_QOS", "1") };

        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../editor-core-treesitter/tests/fixtures/treesitter");
        let json = serde_json::json!({
            "schema_version": 1,
            "root_dir": root.to_string_lossy(),
            "extension_map": { "rs": "rust" },
            "languages": {
                "rust": {
                    "wasm": "rust/language.wasm",
                    "highlights": "rust/highlights.scm",
                    "folds": "rust/folds.scm"
                }
            }
        })
        .to_string();
        let json = CString::new(json).unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_treesitter_set_registry_json(ui, json.as_ptr()),
            ECU_OK
        );
    }

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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
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
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "!abc");

        // undo/redo smoke
        assert_eq!(editor_core_ui_ffi_editor_ui_undo(ui), ECU_OK);
        let t2_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let t2 = unsafe { CStr::from_ptr(t2_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(t2_ptr) };
        assert_eq!(t2, "abc");
        assert_eq!(editor_core_ui_ffi_editor_ui_redo(ui), ECU_OK);

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 80 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());
        assert_eq!(pixel(&buf, 80, 70, 30), [10, 20, 30, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_insert_tab_default_spaces_mode_inserts_to_next_stop() {
        let initial = CString::new("abc").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Caret at end of "abc" (col=3, tab_width=4) => inserts 1 space.
        let ranges = [EcuSelectionRange { start: 3, end: 3 }];
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
            ECU_OK
        );
        assert_eq!(editor_core_ui_ffi_editor_ui_insert_tab(ui), ECU_OK);

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "abc ");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_insert_tab_respects_tab_width_setting_in_spaces_mode() {
        let initial = CString::new("a").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        assert_eq!(editor_core_ui_ffi_editor_ui_set_tab_width(ui, 2), ECU_OK);

        // Caret at end of "a" (col=1, tab_width=2) => inserts 1 space.
        let ranges = [EcuSelectionRange { start: 1, end: 1 }];
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
            ECU_OK
        );
        assert_eq!(editor_core_ui_ffi_editor_ui_insert_tab(ui), ECU_OK);

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "a ");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_insert_tab_respects_tab_key_behavior_tab_mode() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_tab_key_behavior(ui, 0),
            ECU_OK
        );
        assert_eq!(editor_core_ui_ffi_editor_ui_insert_tab(ui), ECU_OK);

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "\t");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_minimap_json_smoke() {
        let initial = CString::new("a\nb\nc").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let ptr = editor_core_ui_ffi_editor_ui_minimap_json(ui, 0, 20);
        assert!(!ptr.is_null());
        let json = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        unsafe { editor_core_ui_ffi_string_free(ptr) };

        assert!(json.contains("\"lines\""));
        assert!(json.contains("\"actual_line_count\""));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_selected_text_and_delete_selections_only_roundtrip() {
        let initial = CString::new("one two three").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Selections: "one", caret, "three".
        let ranges = [
            EcuSelectionRange { start: 0, end: 3 },
            EcuSelectionRange { start: 4, end: 4 },
            EcuSelectionRange { start: 8, end: 13 },
        ];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );

        let sel_ptr = editor_core_ui_ffi_editor_ui_get_selected_text(ui);
        assert!(!sel_ptr.is_null());
        let sel = unsafe { CStr::from_ptr(sel_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(sel_ptr) };
        assert_eq!(sel, "one\nthree");

        assert_eq!(
            editor_core_ui_ffi_editor_ui_delete_selections_only(ui),
            ECU_OK
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, " two ");

        // Cut should clear selections (leave carets only), so selected text becomes empty.
        let sel2_ptr = editor_core_ui_ffi_editor_ui_get_selected_text(ui);
        assert!(!sel2_ptr.is_null());
        let sel2 = unsafe { CStr::from_ptr(sel2_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(sel2_ptr) };
        assert_eq!(sel2, "");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 80 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Styled cell is at x in [10..20], pick a center pixel at y=10.
        assert_eq!(pixel(&buf, 80, 15, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_set_style_text_decorations_affects_rendering() {
        // Use a space in the styled cell so glyph rasterization does not affect the pixel sample.
        let initial = CString::new("a c").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let bg = EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        };
        let theme = EcuTheme {
            background: bg,
            foreground: bg,
            selection_background: bg,
            caret: bg,
        };
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 20, 1.0),
            ECU_OK
        );

        // Apply style id 42 to the middle cell (a space).
        assert_eq!(editor_core_ui_ffi_editor_ui_add_style(ui, 1, 2, 42), ECU_OK);

        let decorations = [EcuStyleTextDecorations {
            style_id: 42,
            flags: ECU_TEXT_DECORATION_FLAG_UNDERLINE | ECU_TEXT_DECORATION_FLAG_UNDERLINE_COLOR,
            underline_style: 3, // squiggly
            underline_color: EcuRgba8 {
                r: 1,
                g: 200,
                b: 2,
                a: 255,
            },
            strikethrough: 0,
            strikethrough_color: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
        }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_text_decorations(
                    ui,
                    decorations.as_ptr(),
                    decorations.len() as u32,
                )
            },
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 80 * 20 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Styled cell is at x in [10..20]. The squiggle starts at y=9 (line height 10).
        assert_eq!(pixel(&buf, 80, 11, 9), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
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
            unsafe {
                editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(
                    ui,
                    scope.as_ptr(),
                    &mut style_id,
                )
            },
            ECU_OK
        );

        let scope_ptr = editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(ui, style_id);
        assert!(!scope_ptr.is_null());
        let roundtrip = unsafe { CStr::from_ptr(scope_ptr) }.to_str().unwrap();
        assert_eq!(roundtrip, "comment.line.demo");
        unsafe { editor_core_ui_ffi_string_free(scope_ptr) };

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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // "a # " => space at col=3 is highlighted => x in [30..40]
        assert_eq!(pixel(&buf, 200, 35, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        set_test_treesitter_registry(ui);
        let language_id = CString::new("rust").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_treesitter_enable_language(ui, language_id.as_ptr()),
            ECU_OK
        );
        wait_for_processing(ui);

        let capture = CString::new("comment").unwrap();
        let mut style_id: u32 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(
                    ui,
                    capture.as_ptr(),
                    &mut style_id,
                )
            },
            ECU_OK
        );

        let name_ptr = editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(ui, style_id);
        assert!(!name_ptr.is_null());
        let roundtrip = unsafe { CStr::from_ptr(name_ptr) }.to_str().unwrap();
        assert_eq!(roundtrip, "comment");
        unsafe { editor_core_ui_ffi_string_free(name_ptr) };

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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Comment contains a space at col=2 => x in [20..30]
        assert_eq!(pixel(&buf, 200, 25, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );

        let mut required: u32 = 0;
        let mut primary: u32 = 0;
        let code = unsafe {
            editor_core_ui_ffi_editor_ui_get_selections(
                ui,
                ptr::null_mut(),
                0,
                &mut required,
                &mut primary,
            )
        };
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(required, 2);
        assert_eq!(primary, 0);

        let mut out = vec![EcuSelectionRange { start: 0, end: 0 }; required as usize];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_selections(
                    ui,
                    out.as_mut_ptr(),
                    out.len() as u32,
                    &mut required,
                    &mut primary,
                )
            },
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
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "Xabc\nXdef\n");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "aXc\ndXf\ngXi\n");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_multi_cursor_commands_work() {
        let initial = CString::new("aa\naa\naa\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // One caret at line 1 col 1 => offset 4.
        let ranges = [EcuSelectionRange { start: 4, end: 4 }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );

        assert_eq!(editor_core_ui_ffi_editor_ui_add_cursor_above(ui), ECU_OK);

        let insert = CString::new("X").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
            ECU_OK
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "aXa\naXa\naa\n");

        assert_eq!(
            editor_core_ui_ffi_editor_ui_clear_secondary_selections(ui),
            ECU_OK
        );

        let mut required: u32 = 0;
        let mut primary: u32 = 0;
        let code = unsafe {
            editor_core_ui_ffi_editor_ui_get_selections(
                ui,
                ptr::null_mut(),
                0,
                &mut required,
                &mut primary,
            )
        };
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(required, 1);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_select_word_and_add_all_occurrences() {
        let initial = CString::new("foo foo foo\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Place caret at start.
        let ranges = [EcuSelectionRange { start: 0, end: 0 }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
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
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "X X X\n");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_expand_selection_by_word_is_expand_only() {
        let initial = CString::new("one two three").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // caret at start of "two" (offset 4)
        let ranges = [EcuSelectionRange { start: 4, end: 4 }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );

        // 1 = word, 1 = forward
        assert_eq!(
            editor_core_ui_ffi_editor_ui_expand_selection_by(ui, 1, 2, 1),
            ECU_OK
        );

        let mut start: u32 = 0;
        let mut end: u32 = 0;
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (4, 13));

        // Change direction: 0 = backward. Expand-only means we keep the end and extend start.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_expand_selection_by(ui, 1, 1, 0),
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (0, 13));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_word_boundary_config_affects_select_word() {
        let initial = CString::new("foo-bar").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // caret inside "foo"
        let ranges = [EcuSelectionRange { start: 1, end: 1 }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );
        assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);

        let mut start: u32 = 0;
        let mut end: u32 = 0;
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (0, 3)); // "foo"

        // Make '-' a word char (do not include it in boundary chars).
        let boundary = CString::new(".").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_word_boundary_ascii_boundary_chars(
                ui,
                boundary.as_ptr()
            ),
            ECU_OK
        );

        // Clear selection and select word again to observe config change.
        let ranges = [EcuSelectionRange { start: 1, end: 1 }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );
        assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (0, 7)); // "foo-bar"

        // Reset defaults: '-' becomes boundary again.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_reset_word_boundary_defaults(ui),
            ECU_OK
        );
        let ranges = [EcuSelectionRange { start: 1, end: 1 }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );
        assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (0, 3)); // "foo"

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_word_movement_and_word_deletion_roundtrip() {
        let initial = CString::new("one two").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Move word right: 0 -> 3.
        assert_eq!(editor_core_ui_ffi_editor_ui_move_word_right(ui), ECU_OK);
        let mut start: u32 = 0;
        let mut end: u32 = 0;
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (3, 3));

        // Shift+Option right: extend selection to next boundary (3..4).
        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_word_right_and_modify_selection(ui),
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (3, 4));

        // Delete word back from end.
        let ranges = [EcuSelectionRange { start: 7, end: 7 }];
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
            ECU_OK
        );
        assert_eq!(editor_core_ui_ffi_editor_ui_delete_word_back(ui), ECU_OK);
        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "one ");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_line_document_and_page_navigation_roundtrip() {
        // Line/document navigation.
        let initial = CString::new("abc\ndef").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        // Caret at offset 2 ("ab|c").
        let ranges = [EcuSelectionRange { start: 2, end: 2 }];
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_to_visual_line_start(ui),
            ECU_OK
        );
        let mut start: u32 = 0;
        let mut end: u32 = 0;
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (0, 0));

        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_to_document_end(ui),
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (7, 7));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };

        // Page navigation depends on viewport height rows.
        let initial = CString::new("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 10.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 100, 30, 1.0),
            ECU_OK
        ); // 3 rows

        let ranges = [EcuSelectionRange { start: 0, end: 0 }];
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_visual_by_pages(ui, 1),
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (6, 6));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 60, 1.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_fold_marker_style(ui, 1),
            ECU_OK
        );
        set_test_treesitter_registry(ui);
        assert_eq!(
            editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(ui),
            ECU_OK
        );
        wait_for_processing(ui);

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_gutter_width_cells(ui, 4),
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 60 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Expanded fold marker at first gutter cell.
        assert_eq!(pixel(&buf, 200, 5, 10), [9, 9, 9, 255]);
        // Gutter background after the 2-cell block marker column.
        assert_eq!(pixel(&buf, 200, 25, 10), [1, 2, 3, 255]);

        // Click in gutter should toggle fold collapse.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_mouse_down(ui, 5.0, 10.0),
            ECU_OK
        );
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(pixel(&buf, 200, 5, 10), [8, 8, 8, 255]);

        // And expand again on second click.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_mouse_down(ui, 5.0, 10.0),
            ECU_OK
        );
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(pixel(&buf, 200, 5, 10), [9, 9, 9, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_move_and_modify_selection_extends_from_anchor() {
        let initial = CString::new("abc\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let ranges = [EcuSelectionRange { start: 2, end: 2 }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_selections(
                    ui,
                    ranges.as_ptr(),
                    ranges.len() as u32,
                    0,
                )
            },
            ECU_OK
        );

        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(ui),
            ECU_OK
        );
        let mut s: u32 = 0;
        let mut e: u32 = 0;
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e) },
            ECU_OK
        );
        assert_eq!((s, e), (1, 2));

        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(ui),
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e) },
            ECU_OK
        );
        assert_eq!((s, e), (0, 2));

        assert_eq!(
            editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(ui),
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e) },
            ECU_OK
        );
        assert_eq!((s, e), (1, 2));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        // LSP diagnostics style id encoding: 0x0400_0100 | severity.
        let styles = [EcuStyleColors {
            style_id: 0x0400_0100 | 1,
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
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
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_lsp_inlay_hints_affect_rendering() {
        // Use a space in the inlay hint label so glyph rasterization does not affect the pixel sample.
        let initial = CString::new("ab\n").unwrap();
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        // Built-in style id for LSP inlay hint virtual text: 0x0800_0001
        let styles = [EcuStyleColors {
            style_id: 0x0800_0001,
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let result = CString::new(
            r#"[
              {
                "position": { "line": 0, "character": 1 },
                "label": " "
              }
            ]"#,
        )
        .unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(ui, result.as_ptr()),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Inlay hint at offset=1 => inserted between 'a' and 'b' => col=1 => x in [10..20]
        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_lsp_code_lens_affect_rendering() {
        // Use a space in the code lens title so glyph rasterization does not affect the pixel sample.
        let initial = CString::new("line1\nline2\n").unwrap();
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        // Built-in style id for LSP code lens virtual text: 0x0800_0002
        let styles = [EcuStyleColors {
            style_id: 0x0800_0002,
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
                "command": { "title": " ", "command": "noop" }
              }
            ]"#,
        )
        .unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(ui, result.as_ptr()),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Code lens is an above-line virtual text line inserted at the top => row=0, col=0.
        assert_eq!(pixel(&buf, 200, 5, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_lsp_document_links_affect_rendering() {
        // Use a space in the document link range so glyph rasterization does not affect the pixel sample.
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 10.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 20, 1.0),
            ECU_OK
        );

        // Built-in style id for LSP document links underline: 0x0800_0003
        let styles = [EcuStyleColors {
            style_id: 0x0800_0003,
            flags: ECU_STYLE_FLAG_FOREGROUND,
            foreground: EcuRgba8 {
                r: 1,
                g: 200,
                b: 2,
                a: 255,
            },
            background: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
        }];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
                "target": "https://example.com"
              }
            ]"#,
        )
        .unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(ui, result.as_ptr()),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 20 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Underline is at y = line_height_px - 1 (scale=1), i.e. y=9. Link range is at col=1 => x in [10..20].
        assert_eq!(pixel(&buf, 200, 15, 9), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_document_link_hit_test_returns_payload_json() {
        let initial = CString::new("a c\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 10.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 20, 1.0),
            ECU_OK
        );

        let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
                "target": "https://example.com"
              }
            ]"#,
        )
        .unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(ui, result.as_ptr()),
            ECU_OK
        );

        let mut x: c_float = 0.0;
        let mut y: c_float = 0.0;
        let mut lh: c_float = 0.0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_char_offset_to_view_point(
                    ui, 1, &mut x, &mut y, &mut lh,
                )
            },
            ECU_OK
        );
        assert!(lh > 0.0);

        let mut has: u8 = 0;
        let mut json_ptr: *mut c_char = ptr::null_mut();
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(
                    ui,
                    x + 1.0,
                    y + 1.0,
                    &mut has,
                    &mut json_ptr,
                )
            },
            ECU_OK
        );
        assert_eq!(has, 1);
        assert!(!json_ptr.is_null());

        let json = unsafe { CStr::from_ptr(json_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(json_ptr) };
        assert!(json.contains("https://example.com"));

        // No link at col=0.
        let mut has2: u8 = 0;
        let mut json_ptr2: *mut c_char = ptr::null_mut();
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(
                    ui,
                    1.0,
                    1.0,
                    &mut has2,
                    &mut json_ptr2,
                )
            },
            ECU_OK
        );
        assert_eq!(has2, 0);
        assert!(json_ptr2.is_null());

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_lsp_document_highlights_affect_rendering() {
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        // Built-in style id for LSP document highlight text: 0x0400_0001
        let styles = [EcuStyleColors {
            style_id: 0x0400_0001,
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
                "kind": 1
              }
            ]"#,
        )
        .unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(ui, result.as_ptr()),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Highlighted cell at col=1 => x in [10..20]
        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_match_highlights_affect_rendering() {
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        // Built-in match highlight style id: 0x0800_0004
        let styles = [EcuStyleColors {
            style_id: 0x0800_0004,
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let ranges = [EcuSelectionRange { start: 1, end: 2 }];
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_match_highlights(ui, ranges.as_ptr(), 1) },
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Highlighted cell at col=1 => x in [10..20]
        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_lsp_apply_workspace_edit_json_applies_current_document() {
        let initial = CString::new("abc\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let workspace_edit = CString::new(
            r#"{
                "changes": {
                    "file:///test.rs": [
                        { "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } }, "newText": "B" }
                    ],
                    "file:///other.rs": [
                        { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } }, "newText": "X" }
                    ]
                }
            }"#,
        )
        .unwrap();
        let uri = CString::new("file:///test.rs").unwrap();

        let result_ptr = editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(
            ui,
            workspace_edit.as_ptr(),
            uri.as_ptr(),
        );
        assert!(!result_ptr.is_null());
        let result_json = unsafe { CStr::from_ptr(result_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(result_ptr) };

        let result: serde_json::Value = serde_json::from_str(&result_json).unwrap();
        assert_eq!(result["applied"], true);
        assert_eq!(result["applied_uri"], "file:///test.rs");
        assert_eq!(result["applied_edit_count"], 1);
        assert_eq!(
            result["skipped_uris"],
            serde_json::json!(["file:///other.rs"])
        );

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "aBc\n");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_search_set_query_sets_match_highlights_and_returns_count() {
        // Use spaces as matches so glyph rasterization does not affect the pixel sample.
        let initial = CString::new("a c a\n").unwrap();
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        // Built-in match highlight style id: 0x0800_0004
        let styles = [EcuStyleColors {
            style_id: 0x0800_0004,
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let query = CString::new(" ").unwrap();
        let mut count: u32 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_search_set_query(
                    ui,
                    query.as_ptr(),
                    1,
                    0,
                    0,
                    &mut count,
                )
            },
            ECU_OK
        );
        assert_eq!(count, 2);

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // First space at col=1 => x in [10..20]
        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);
        // Second space at col=3 => x in [30..40]
        assert_eq!(pixel(&buf, 200, 35, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_find_next_and_replace_roundtrip() {
        let initial = CString::new("foo foo foo\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let query = CString::new("foo").unwrap();
        let mut found: u8 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_find_next(ui, query.as_ptr(), 1, 0, 0, &mut found)
            },
            ECU_OK
        );
        assert_eq!(found, 1);

        let mut sel_start: u32 = 0;
        let mut sel_end: u32 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut sel_start, &mut sel_end)
            },
            ECU_OK
        );
        assert_eq!((sel_start, sel_end), (0, 3));

        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_find_next(ui, query.as_ptr(), 1, 0, 0, &mut found)
            },
            ECU_OK
        );
        assert_eq!(found, 1);
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut sel_start, &mut sel_end)
            },
            ECU_OK
        );
        assert_eq!((sel_start, sel_end), (4, 7));

        let replacement = CString::new("bar").unwrap();
        let mut replaced: u32 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_replace_current(
                    ui,
                    query.as_ptr(),
                    replacement.as_ptr(),
                    1,
                    0,
                    0,
                    &mut replaced,
                )
            },
            ECU_OK
        );
        assert_eq!(replaced, 1);

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "foo bar foo\n");

        let replacement_all = CString::new("baz").unwrap();
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_replace_all(
                    ui,
                    query.as_ptr(),
                    replacement_all.as_ptr(),
                    1,
                    0,
                    0,
                    &mut replaced,
                )
            },
            ECU_OK
        );
        assert_eq!(replaced, 2);

        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "baz bar baz\n");

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
            ECU_OK
        );

        let style_id = 7u32 << 16;
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
            unsafe {
                editor_core_ui_ffi_editor_ui_set_style_colors(
                    ui,
                    styles.as_ptr(),
                    styles.len() as u32,
                )
            },
            ECU_OK
        );

        let data = [0u32, 1, 1, 7, 0];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
                    ui,
                    data.as_ptr(),
                    data.len() as u32,
                )
            },
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 200 * 40 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
        assert!(msg.to_lowercase().contains("utf-8") || !msg.is_empty());

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        // Turning ligatures off again should also succeed.
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(ui, 0),
            ECU_OK
        );

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_set_caret_width_and_visibility_affect_render_rgba() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 20, 10, 1.0);

        let theme = EcuTheme {
            background: EcuRgba8 {
                r: 0xFF,
                g: 0xFF,
                b: 0xFF,
                a: 0xFF,
            },
            foreground: EcuRgba8 {
                r: 0x11,
                g: 0x11,
                b: 0x11,
                a: 0xFF,
            },
            selection_background: EcuRgba8 {
                r: 0xC7,
                g: 0xDD,
                b: 0xFF,
                a: 0xFF,
            },
            caret: EcuRgba8 {
                r: 0x00,
                g: 0x00,
                b: 0x00,
                a: 0xFF,
            },
        };
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
            ECU_OK
        );

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_caret_width_px(ui, 4.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_caret_visible(ui, 1),
            ECU_OK
        );

        let mut out_len: u32 = 0;
        let mut buf = vec![0u8; 20 * 10 * 4];
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        assert_eq!(out_len as usize, buf.len());

        let caret_px = [0u8, 0u8, 0u8, 255u8];
        let caret_count0 = buf.chunks_exact(4).filter(|p| *p == caret_px).count();
        assert_eq!(
            caret_count0,
            4 * 10,
            "expected caret to fill a 4x10 rectangle"
        );

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_caret_visible(ui, 0),
            ECU_OK
        );
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_render_rgba(
                    ui,
                    buf.as_mut_ptr(),
                    buf.len() as u32,
                    &mut out_len,
                )
            },
            ECU_OK
        );
        let caret_count1 = buf.chunks_exact(4).filter(|p| *p == caret_px).count();
        assert_eq!(
            caret_count1, 0,
            "expected caret pixels to disappear when hidden"
        );

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
        let code = unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        };
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(out_len, 80 * 40 * 4);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_render_allows_out_buf_null_as_size_query() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0);

        let mut out_len: u32 = 0;
        let code = unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(ui, ptr::null_mut(), 0, &mut out_len)
        };
        assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
        assert_eq!(out_len, 80 * 40 * 4);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_render_rejects_null_out_len() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let code = unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(ui, ptr::null_mut(), 0, ptr::null_mut())
        };
        assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);

        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
        assert!(msg.contains("out_len is null"));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_render_rejects_required_length_that_exceeds_u32() {
        let initial = CString::new("").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 1.0, 1.0, 1.0, 0.0, 0.0),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_viewport_px(ui, u32::MAX, 2, 1.0),
            ECU_OK
        );

        let mut out_len: u32 = 123;
        let code = unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(ui, ptr::null_mut(), 0, &mut out_len)
        };
        assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);
        assert_eq!(out_len, 123);

        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
        assert!(msg.contains("rgba buffer required length"));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_set_match_highlights_rejects_null_nonzero_ranges() {
        let initial = CString::new("abc").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let code = unsafe { editor_core_ui_ffi_editor_ui_set_match_highlights(ui, ptr::null(), 1) };
        assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);

        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
        assert!(msg.contains("ranges is null"));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_null_args_set_last_error() {
        let code = editor_core_ui_ffi_editor_ui_insert_text(ptr::null_mut(), ptr::null());
        assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);
        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
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
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
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
            unsafe {
                editor_core_ui_ffi_editor_ui_get_marked_range(ui, &mut has, &mut ms, &mut ml)
            },
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
                1,        // selected_start inside "你好"
                0,        // selected_len
                u32::MAX, // replace_start: use existing marked range
                0         // replace_len (ignored)
            ),
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
            ECU_OK
        );
        assert_eq!((start, end), (1, 1));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
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
            unsafe {
                editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 25.0, 10.0, &mut off)
            },
            ECU_OK
        );
        assert_eq!(off, 2);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_char_offset_to_logical_position_roundtrip() {
        let initial = CString::new("ab\ncde\nf").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let mut line: u32 = 0;
        let mut col: u32 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_char_offset_to_logical_position(
                    ui, 4, &mut line, &mut col,
                )
            },
            ECU_OK
        );
        assert_eq!(line, 1);
        assert_eq!(col, 1);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_get_viewport_state_and_set_smooth_scroll_state_roundtrip() {
        let initial = CString::new("0\n1\n2\n3\n4\n5\n6\n7").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 20, 1.0);

        let mut vp = EcuViewportState {
            width_cells: 0,
            height_rows: 0,
            has_height: 0,
            scroll_top: 0,
            sub_row_offset: 0,
            overscan_rows: 0,
            visible_start: 0,
            visible_end: 0,
            prefetch_start: 0,
            prefetch_end: 0,
            total_visual_lines: 0,
        };
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
            ECU_OK
        );
        assert_eq!(vp.total_visual_lines, 8);
        assert_eq!(vp.has_height, 1);
        assert_eq!(vp.height_rows, 2);
        assert_eq!(vp.scroll_top, 0);
        assert_eq!(vp.sub_row_offset, 0);

        unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui, 3, 32768) };
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
            ECU_OK
        );
        assert_eq!(vp.scroll_top, 3);
        assert_eq!(vp.sub_row_offset, 32768);

        // Clamp to maximum scroll position (total - height = 6).
        unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui, 999, 65535) };
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
            ECU_OK
        );
        assert_eq!(vp.scroll_top, 6);
        assert_eq!(vp.sub_row_offset, 0);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_clone_view_shares_text_and_has_independent_scroll_state() {
        let initial = CString::new("abc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n").unwrap();
        let ui1 = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui1.is_null());
        let ui2 = editor_core_ui_ffi_editor_ui_clone_view(ui1, 80);
        assert!(!ui2.is_null());

        // Initial view state is independent.
        let r1 = EcuSelectionRange { start: 0, end: 0 };
        let r2 = EcuSelectionRange { start: 4, end: 4 };
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui1, &r1 as *const _, 1, 0) },
            ECU_OK
        );
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui2, &r2 as *const _, 1, 0) },
            ECU_OK
        );

        let mut start: u32 = 0;
        let mut end: u32 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_selection_offsets(ui1, &mut start, &mut end)
            },
            ECU_OK
        );
        assert_eq!((start, end), (0, 0));
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_selection_offsets(ui2, &mut start, &mut end)
            },
            ECU_OK
        );
        assert_eq!((start, end), (4, 4));

        // Text edits are shared across views.
        let insert = CString::new("X").unwrap();
        assert_eq!(
            editor_core_ui_ffi_editor_ui_insert_text(ui1, insert.as_ptr()),
            ECU_OK
        );
        let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui2);
        assert!(!text_ptr.is_null());
        let text = unsafe { CStr::from_ptr(text_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(text_ptr) };
        assert_eq!(text, "Xabc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n");

        // Each view tracks its own selection, but receives the same text delta.
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_get_selection_offsets(ui2, &mut start, &mut end)
            },
            ECU_OK
        );
        assert_eq!((start, end), (5, 5));

        // Scroll state is view-local.
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui1, 10.0, 10.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui2, 10.0, 10.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui1, 80, 20, 1.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui2, 80, 20, 1.0);

        unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui1, 1, 0) };
        unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui2, 3, 0) };

        let mut vp1 = EcuViewportState {
            width_cells: 0,
            height_rows: 0,
            has_height: 0,
            scroll_top: 0,
            sub_row_offset: 0,
            overscan_rows: 0,
            visible_start: 0,
            visible_end: 0,
            prefetch_start: 0,
            prefetch_end: 0,
            total_visual_lines: 0,
        };
        let mut vp2 = vp1;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_viewport_state(ui1, &mut vp1),
            ECU_OK
        );
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_viewport_state(ui2, &mut vp2),
            ECU_OK
        );
        assert_eq!(vp1.scroll_top, 1);
        assert_eq!(vp2.scroll_top, 3);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui2) };
        unsafe { editor_core_ui_ffi_editor_ui_free(ui1) };
    }

    #[test]
    fn ffi_smooth_scroll_by_pixels_affects_hit_test_and_view_point_mapping() {
        let initial = CString::new("a\nb\nc\n").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 20, 1.0);

        // Scroll down by half a row: content should move up by 5px.
        unsafe { editor_core_ui_ffi_editor_ui_scroll_by_pixels(ui, 5.0) };

        // "b" starts at char offset 2 ("a\nb..."), its y should be (1*10 - 5) = 5.
        let mut x: c_float = 0.0;
        let mut y: c_float = 0.0;
        let mut line_h: c_float = 0.0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_char_offset_to_view_point(
                    ui,
                    2,
                    &mut x,
                    &mut y,
                    &mut line_h,
                )
            },
            ECU_OK
        );
        assert_eq!(y, 5.0);

        let mut off: u32 = 0;
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 0.0, 4.0, &mut off)
            },
            ECU_OK
        );
        assert_eq!(off, 0);
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 0.0, 5.0, &mut off)
            },
            ECU_OK
        );
        assert_eq!(off, 2);
        assert_eq!(
            unsafe {
                editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 0.0, 9.0, &mut off)
            },
            ECU_OK
        );
        assert_eq!(off, 2);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_metal_enable_rejects_null_handles() {
        let initial = CString::new("abc").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        assert_eq!(
            editor_core_ui_ffi_editor_ui_enable_metal(ui, ptr::null_mut(), ptr::null_mut()),
            ECU_ERR_INVALID_ARGUMENT
        );

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_metal_render_rejects_null_texture() {
        let initial = CString::new("abc").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        assert_eq!(
            editor_core_ui_ffi_editor_ui_render_metal(ui, ptr::null_mut()),
            ECU_ERR_INVALID_ARGUMENT
        );

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_get_logical_line_count_and_gutter_width_roundtrip() {
        let initial = CString::new("a\nb\nc").unwrap(); // 3 logical lines
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let mut lines: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_logical_line_count(ui, &mut lines),
            ECU_OK
        );
        assert_eq!(lines, 3);

        assert_eq!(
            editor_core_ui_ffi_editor_ui_set_gutter_width_cells(ui, 7),
            ECU_OK
        );
        let mut gutter: u32 = 0;
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_gutter_width_cells(ui, &mut gutter),
            ECU_OK
        );
        assert_eq!(gutter, 7);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_reveal_primary_caret_scrolls_to_make_caret_visible() {
        let text = (0..100).map(|_| "x").collect::<Vec<_>>().join("\n");
        let initial = CString::new(text).unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 14.0, 10.0, 8.0, 0.0, 0.0);
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 800, 50, 1.0);
        unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui, 0, 0) };

        // Line 50, col 0 in "x\nx\n..." => offset 50*(1+1) = 100.
        let range = EcuSelectionRange {
            start: 100,
            end: 100,
        };
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, &range as *const _, 1, 0) },
            ECU_OK
        );

        assert_eq!(
            editor_core_ui_ffi_editor_ui_reveal_primary_caret(ui),
            ECU_OK
        );

        let mut vp = EcuViewportState {
            width_cells: 0,
            height_rows: 0,
            has_height: 0,
            scroll_top: 0,
            sub_row_offset: 0,
            overscan_rows: 0,
            visible_start: 0,
            visible_end: 0,
            prefetch_start: 0,
            prefetch_end: 0,
            total_visual_lines: 0,
        };
        assert_eq!(
            editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
            ECU_OK
        );
        assert_eq!(vp.has_height, 1);
        assert_eq!(vp.height_rows, 5);
        assert_eq!(vp.scroll_top, 46);

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_lsp_request_definition_errors_when_lsp_disabled() {
        let initial = CString::new("hello").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let mut out_id: u64 = 0;
        let code =
            unsafe { editor_core_ui_ffi_editor_ui_lsp_request_definition(ui, 0, 0, &mut out_id) };
        assert_eq!(code, ECU_ERR_INTERNAL);

        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
        assert!(msg.to_lowercase().contains("lsp") && msg.to_lowercase().contains("enabled"));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    #[test]
    fn ffi_lsp_format_document_errors_when_lsp_disabled() {
        let initial = CString::new("hello").unwrap();
        let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
        assert!(!ui.is_null());

        let mut applied: u8 = 0;
        let code = unsafe {
            editor_core_ui_ffi_editor_ui_lsp_format_document(ui, ptr::null(), 50, &mut applied)
        };
        assert_eq!(code, ECU_ERR_INTERNAL);

        let msg_ptr = editor_core_ui_ffi_last_error_message();
        let msg = unsafe { CStr::from_ptr(msg_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
        assert!(msg.to_lowercase().contains("lsp") && msg.to_lowercase().contains("enabled"));

        unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
    }

    fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
        let idx = ((y * width_px + x) * 4) as usize;
        [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
