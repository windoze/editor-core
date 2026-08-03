use super::*;

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

/// Execute one command encoded as JSON and return a stable result envelope.
///
/// Success: `{ "ok": true, "value": <command result>, "error": null, "version": ECF_ABI_VERSION }`
/// Failure: `{ "ok": false, "value": null, "error": { "code": "...", "status": N, "message": "..." }, "version": ECF_ABI_VERSION }`
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_execute_envelope_json(
    state: *mut EcfEditorState,
    command_json: *const c_char,
) -> *mut c_char {
    result_envelope_json_ptr(|| {
        let state =
            require_mut(state, "state").map_err(|message| (EcfStatus::InvalidArgument, message))?;
        let command_json = require_string_status(command_json, "command_json")?;
        let command = parse_command_from_json(&command_json)
            .map_err(|message| (EcfStatus::Parse, message))?;
        let result = state.inner.execute(command).map_err(|err| {
            (
                EcfStatus::CommandFailed,
                format!("command execution failed: {err}"),
            )
        })?;
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

/// Get styled viewport snapshot as a stable JSON result envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_viewport_styled_envelope_json(
    state: *const EcfEditorState,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    rendering_snapshot_envelope_json_ptr(
        "editor_state_viewport_styled",
        None,
        start_visual_row,
        count,
        || {
            let state = require_ref(state, "state")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let count = usize_from_u32(count, "count")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let grid = state
                .inner
                .get_viewport_content_styled(start_visual_row, count);
            Ok(value_headless_grid(&grid))
        },
    )
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

/// Get minimap snapshot as a stable JSON result envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_minimap_envelope_json(
    state: *const EcfEditorState,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    rendering_snapshot_envelope_json_ptr(
        "editor_state_minimap",
        None,
        start_visual_row,
        count,
        || {
            let state = require_ref(state, "state")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let count = usize_from_u32(count, "count")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let grid = state.inner.get_minimap_content(start_visual_row, count);
            Ok(value_minimap_grid(&grid))
        },
    )
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

/// Get decoration-aware composed snapshot as a stable JSON result envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_state_viewport_composed_envelope_json(
    state: *const EcfEditorState,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    rendering_snapshot_envelope_json_ptr(
        "editor_state_viewport_composed",
        None,
        start_visual_row,
        count,
        || {
            let state = require_ref(state, "state")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let start_visual_row = usize_from_u32(start_visual_row, "start_visual_row")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let count = usize_from_u32(count, "count")
                .map_err(|message| (EcfStatus::InvalidArgument, message))?;
            let grid = state
                .inner
                .get_viewport_content_composed(start_visual_row, count);
            Ok(value_composed_grid(&grid))
        },
    )
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
