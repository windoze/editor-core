use super::*;
use serde_json::{Value, json};

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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_minimap_envelope_json(
    ui: *mut EditorUi,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let value = minimap_value(ui.minimap_json(
            u32_to_usize(start_visual_row, "start_visual_row")?,
            u32_to_usize(count, "count")?,
        ))?;
        Ok(minimap_envelope_success(start_visual_row, count, value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            minimap_envelope_error(start_visual_row, count, status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn minimap_value(result_json: String) -> Result<Value, String> {
    serde_json::from_str::<Value>(&result_json)
        .map_err(|err| format!("minimap returned invalid JSON: {err}"))
}

fn minimap_envelope_success(start_visual_row: u32, count: u32, value: Value) -> String {
    json!({
        "ok": true,
        "status": "success",
        "start_visual_row": start_visual_row,
        "count": count,
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn minimap_envelope_error(
    start_visual_row: u32,
    count: u32,
    status: c_int,
    message: String,
) -> String {
    json!({
        "ok": false,
        "status": "error",
        "start_visual_row": start_visual_row,
        "count": count,
        "value": Value::Null,
        "error": {
            "code": status_code_name(status),
            "status": status,
            "message": message,
        },
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}
