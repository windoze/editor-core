use super::super::*;
use serde_json::{Value, json};

/// Export one derived-state snapshot through a stable JSON result envelope.
///
/// `snapshot_utf8` accepts:
/// - `diagnostics`
/// - `decorations`
/// - `document_symbols`
/// - `folding_regions`
/// - `style_intervals`
///
/// `start` / `end` are used by `style_intervals`; other snapshots ignore the range.
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_derived_snapshot_envelope_json(
    ui: *mut EditorUi,
    snapshot_utf8: *const c_char,
    start: u32,
    end: u32,
) -> *mut c_char {
    let mut snapshot_name = None;
    let envelope = match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let snapshot = require_str(snapshot_utf8, "snapshot_utf8")?.to_string();
        snapshot_name = Some(snapshot.clone());
        let value = derived_snapshot_value(ui, &snapshot, start, end)?;
        Ok(derived_snapshot_envelope_success(
            &snapshot, start, end, value,
        ))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            derived_snapshot_envelope_error(snapshot_name.as_deref(), start, end, status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn derived_snapshot_value(
    ui: &mut EditorUi,
    snapshot: &str,
    start: u32,
    end: u32,
) -> Result<Value, String> {
    let result_json = match snapshot {
        "diagnostics" => ui.diagnostics_json().map_err(map_ui_error)?,
        "decorations" => ui.decorations_json().map_err(map_ui_error)?,
        "document_symbols" => ui.document_symbols_json().map_err(map_ui_error)?,
        "folding_regions" => ui.folding_regions_json().map_err(map_ui_error)?,
        "style_intervals" => ui
            .style_intervals_json(u32_to_usize(start, "start")?, u32_to_usize(end, "end")?)
            .map_err(map_ui_error)?,
        other => {
            return Err(invalid_argument(format!(
                "unknown derived snapshot \"{other}\""
            )));
        }
    };
    parse_snapshot_value(snapshot, result_json)
}

fn parse_snapshot_value(snapshot: &str, result_json: String) -> Result<Value, String> {
    serde_json::from_str::<Value>(&result_json)
        .map_err(|err| format!("derived snapshot {snapshot} returned invalid JSON: {err}"))
}

fn derived_snapshot_envelope_success(snapshot: &str, start: u32, end: u32, value: Value) -> String {
    json!({
        "ok": true,
        "snapshot": snapshot,
        "range": {
            "start": start,
            "end": end,
        },
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn derived_snapshot_envelope_error(
    snapshot: Option<&str>,
    start: u32,
    end: u32,
    status: c_int,
    message: String,
) -> String {
    json!({
        "ok": false,
        "snapshot": snapshot,
        "range": {
            "start": start,
            "end": end,
        },
        "status": "error",
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
