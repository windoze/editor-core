use super::super::*;

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

/// Configure per-family OpenType feature strings used when ligatures are enabled.
///
/// `entries_utf8` is a UTF-8 string with one record per line:
/// `<font family>\t<feature string>` (e.g. `Monaspace Neon\t-calt +liga +ss01`).
/// Empty lines are ignored; calling with an empty string clears the map.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_font_feature_map(
    ui: *mut EditorUi,
    entries_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let entries_str = require_cstr(entries_utf8, "entries_utf8")?
            .to_str()
            .map_err(|_| "entries_utf8 is not valid UTF-8".to_string())?;
        let mut entries: Vec<(String, String)> = Vec::new();
        for (line_index, line) in entries_str.lines().enumerate() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            let Some((family, spec)) = line.split_once('\t') else {
                return Err(format!(
                    "font feature map line {} is missing a TAB separator",
                    line_index + 1
                ));
            };
            entries.push((family.trim().to_string(), spec.trim().to_string()));
        }
        ui.set_font_feature_map(entries);
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_lsp_on_type_formatting_enabled(
    ui: *mut EditorUi,
    enabled: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_lsp_on_type_formatting_enabled(enabled != 0)
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
