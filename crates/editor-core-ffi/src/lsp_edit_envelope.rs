use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_on_type_formatting_params_envelope_json(
    state: *const EcfEditorState,
    uri: *const c_char,
    ch: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("on_type_formatting_params", || {
        lsp_on_type_formatting_params_value(state, uri, ch, options_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_apply_text_edits_envelope_json(
    state: *mut EcfEditorState,
    edits_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("apply_text_edits", || {
        lsp_apply_text_edits_value(state, edits_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_semantic_tokens_to_intervals_envelope_json(
    state: *const EcfEditorState,
    data_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("semantic_tokens_to_intervals", || {
        lsp_semantic_tokens_to_intervals_value(state, data_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_highlights_to_processing_edit_envelope_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("document_highlights_to_processing_edit", || {
        lsp_document_highlights_processing_edit_value(state, result_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_inlay_hints_to_processing_edit_envelope_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("inlay_hints_to_processing_edit", || {
        lsp_inlay_hints_processing_edit_value(state, result_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_links_to_processing_edit_envelope_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("document_links_to_processing_edit", || {
        lsp_document_links_processing_edit_value(state, result_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_code_lens_to_processing_edit_envelope_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("code_lens_to_processing_edit", || {
        lsp_code_lens_processing_edit_value(state, result_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_symbols_to_processing_edit_envelope_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("document_symbols_to_processing_edit", || {
        lsp_document_symbols_processing_edit_value(state, result_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_diagnostics_to_processing_edits_envelope_json(
    state: *const EcfEditorState,
    publish_diagnostics_params_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("diagnostics_to_processing_edits", || {
        lsp_diagnostics_processing_edits_value(state, publish_diagnostics_params_json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_completion_item_to_text_edits_envelope_json(
    state: *const EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
    fallback_start: u64,
    fallback_end: u64,
    has_fallback: bool,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("completion_item_to_text_edits", || {
        lsp_completion_item_to_text_edits_value(
            state,
            completion_item_json,
            mode,
            fallback_start,
            fallback_end,
            has_fallback,
        )
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_apply_completion_item_envelope_json(
    state: *mut EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("apply_completion_item", || {
        lsp_apply_completion_item_value(state, completion_item_json, mode)
    })
}
