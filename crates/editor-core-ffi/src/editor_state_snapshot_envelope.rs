use super::*;

pub(crate) fn editor_state_derived_snapshot_envelope_json_ptr(
    state: *const EcfEditorState,
    snapshot_utf8: *const c_char,
) -> *mut c_char {
    let mut snapshot_name = None;
    let envelope = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state =
            require_ref(state, "state").map_err(|message| (EcfStatus::InvalidArgument, message))?;
        let snapshot = require_string_status(snapshot_utf8, "snapshot_utf8")?;
        snapshot_name = Some(snapshot.clone());
        let value = editor_state_derived_snapshot_value(state, &snapshot)?;
        Ok(editor_state_derived_snapshot_success(&snapshot, value))
    })) {
        Ok(Ok(value)) => {
            clear_last_error();
            value
        }
        Ok(Err((status, message))) => {
            set_last_error(message.clone());
            editor_state_derived_snapshot_error(snapshot_name.as_deref(), status, message)
        }
        Err(_) => {
            let message = "panic across FFI boundary".to_string();
            set_last_error(message.clone());
            editor_state_derived_snapshot_error(
                snapshot_name.as_deref(),
                EcfStatus::Internal,
                message,
            )
        }
    };

    json_ptr(envelope)
}

fn editor_state_derived_snapshot_value(
    state: &EcfEditorState,
    snapshot: &str,
) -> Result<Value, (EcfStatus, String)> {
    match snapshot {
        "document_symbols" => {
            let symbols = state.inner.editor().document_symbols();
            Ok(json!({
                "symbols": symbols
                    .symbols
                    .iter()
                    .map(value_document_symbol)
                    .collect::<Vec<_>>()
            }))
        }
        "diagnostics" => Ok(json!({
            "diagnostics": state
                .inner
                .editor()
                .diagnostics()
                .iter()
                .map(value_diagnostic)
                .collect::<Vec<_>>()
        })),
        "decorations" => {
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
        }
        other => Err((
            EcfStatus::InvalidArgument,
            format!("unknown editor state derived snapshot \"{other}\""),
        )),
    }
}

fn editor_state_derived_snapshot_success(snapshot: &str, value: Value) -> Value {
    json!({
        "ok": true,
        "status": "success",
        "snapshot": snapshot,
        "value": value,
        "error": Value::Null,
        "version": ECF_ABI_VERSION,
    })
}

fn editor_state_derived_snapshot_error(
    snapshot: Option<&str>,
    status: EcfStatus,
    message: String,
) -> Value {
    json!({
        "ok": false,
        "status": "error",
        "snapshot": snapshot,
        "value": Value::Null,
        "error": {
            "code": ecf_status_label(status),
            "status": status.code(),
            "message": message,
        },
        "version": ECF_ABI_VERSION,
    })
}
