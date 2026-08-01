use super::super::*;

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
