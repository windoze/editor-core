use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_process_envelope_json(
    processor: *mut EcfSublimeProcessor,
    state: *const EcfEditorState,
) -> *mut c_char {
    processor_result_envelope_json_ptr("sublime_process", || {
        sublime_processor_process_value(processor, state)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_sublime_processor_scope_for_style_id_envelope_json(
    processor: *const EcfSublimeProcessor,
    style_id: u32,
) -> *mut c_char {
    processor_result_envelope_json_ptr("sublime_scope_for_style_id", || {
        sublime_processor_scope_for_style_id_value(processor, style_id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_process_envelope_json(
    processor: *mut EcfTreeSitterProcessor,
    state: *const EcfEditorState,
) -> *mut c_char {
    processor_result_envelope_json_ptr("treesitter_process", || {
        treesitter_processor_process_value(processor, state)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_processor_last_update_mode_envelope_json(
    processor: *const EcfTreeSitterProcessor,
) -> *mut c_char {
    processor_result_envelope_json_ptr("treesitter_last_update_mode", || {
        treesitter_processor_last_update_mode_value(processor)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_treesitter_indenter_reindent_line_envelope_json(
    indenter: *mut EcfTreeSitterIndenter,
    state: *const EcfEditorState,
    line: u32,
    indentation_config_json: *const c_char,
) -> *mut c_char {
    processor_result_envelope_json_ptr("treesitter_reindent_line", || {
        treesitter_indenter_reindent_line_value(indenter, state, line, indentation_config_json)
    })
}

fn processor_result_envelope_json_ptr<F>(operation: &'static str, f: F) -> *mut c_char
where
    F: FnOnce() -> Result<Value, (EcfStatus, String)>,
{
    let envelope = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(Ok(value)) => {
            clear_last_error();
            processor_result_envelope_success(operation, value)
        }
        Ok(Err((status, message))) => {
            set_last_error(message.clone());
            processor_result_envelope_error(operation, status, message)
        }
        Err(_) => {
            let message = "panic across FFI boundary".to_string();
            set_last_error(message.clone());
            processor_result_envelope_error(operation, EcfStatus::Internal, message)
        }
    };
    json_ptr(envelope)
}

fn processor_result_envelope_success(operation: &'static str, value: Value) -> Value {
    json!({
        "ok": true,
        "operation": operation,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECF_ABI_VERSION,
    })
}

fn processor_result_envelope_error(
    operation: &'static str,
    status: EcfStatus,
    message: String,
) -> Value {
    json!({
        "ok": false,
        "operation": operation,
        "status": "error",
        "value": Value::Null,
        "error": {
            "code": ecf_status_label(status),
            "status": status.code(),
            "message": message,
        },
        "version": ECF_ABI_VERSION,
    })
}
