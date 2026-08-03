use super::*;

pub(crate) fn rendering_snapshot_envelope_json_ptr<F>(
    surface: &'static str,
    view_id: Option<u64>,
    start_visual_row: u32,
    count: u32,
    f: F,
) -> *mut c_char
where
    F: FnOnce() -> Result<Value, (EcfStatus, String)>,
{
    let envelope = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(Ok(value)) => {
            clear_last_error();
            rendering_snapshot_envelope_success(surface, view_id, start_visual_row, count, value)
        }
        Ok(Err((status, message))) => {
            set_last_error(message.clone());
            rendering_snapshot_envelope_error(
                surface,
                view_id,
                start_visual_row,
                count,
                status,
                message,
            )
        }
        Err(_) => {
            let message = "panic across FFI boundary".to_string();
            set_last_error(message.clone());
            rendering_snapshot_envelope_error(
                surface,
                view_id,
                start_visual_row,
                count,
                EcfStatus::Internal,
                message,
            )
        }
    };

    json_ptr(envelope)
}

fn rendering_snapshot_envelope_success(
    surface: &'static str,
    view_id: Option<u64>,
    start_visual_row: u32,
    count: u32,
    value: Value,
) -> Value {
    json!({
        "ok": true,
        "status": "success",
        "surface": surface,
        "view_id": view_id,
        "start_visual_row": start_visual_row,
        "count": count,
        "value": value,
        "error": Value::Null,
        "version": ECF_ABI_VERSION,
    })
}

fn rendering_snapshot_envelope_error(
    surface: &'static str,
    view_id: Option<u64>,
    start_visual_row: u32,
    count: u32,
    status: EcfStatus,
    message: String,
) -> Value {
    json!({
        "ok": false,
        "status": "error",
        "surface": surface,
        "view_id": view_id,
        "start_visual_row": start_visual_row,
        "count": count,
        "value": Value::Null,
        "error": {
            "code": ecf_status_label(status),
            "status": status.code(),
            "message": message,
        },
        "version": ECF_ABI_VERSION,
    })
}
