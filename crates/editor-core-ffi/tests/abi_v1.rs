use editor_core_ffi::{
    ECF_ABI_VERSION, ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE,
    ECF_FEATURE_JSON_COMMAND_DISPATCH, ECF_FEATURE_JSON_COMMAND_ENVELOPE, ECF_FEATURE_LSP_HELPERS,
    ECF_FEATURE_PROCESSING_EDIT_JSON, ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE,
    ECF_FEATURE_SUBLIME_PROCESSOR, ECF_FEATURE_TREESITTER_PROCESSOR, ECF_FEATURE_TYPED_HOT_PATH,
    ECF_FEATURE_VIEWPORT_BLOB, ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE,
    ECF_FEATURE_WORKSPACE_TYPED_API, EcfCreateViewResult, EcfDocumentStats, EcfEditorState,
    EcfOpenBufferResult, EcfStatus, EcfWorkspace, EcfWorkspaceInfo, EcfWorkspaceViewportState,
    ecf_abi_version, ecf_editor_backspace, ecf_editor_get_viewport_blob,
    ecf_editor_insert_text_utf8, ecf_editor_move_to, ecf_feature_flags,
    editor_core_ffi_editor_get_document_stats, editor_core_ffi_editor_get_viewport_blob,
    editor_core_ffi_editor_insert_text_utf8,
    editor_core_ffi_editor_state_derived_snapshot_envelope_json,
    editor_core_ffi_editor_state_execute_envelope_json, editor_core_ffi_editor_state_free,
    editor_core_ffi_editor_state_minimap_envelope_json, editor_core_ffi_editor_state_minimap_json,
    editor_core_ffi_editor_state_new, editor_core_ffi_editor_state_viewport_composed_envelope_json,
    editor_core_ffi_editor_state_viewport_composed_json,
    editor_core_ffi_editor_state_viewport_styled_envelope_json,
    editor_core_ffi_editor_state_viewport_styled_json, editor_core_ffi_feature_flags,
    editor_core_ffi_last_error_message, editor_core_ffi_lsp_char_offset_to_utf16,
    editor_core_ffi_lsp_completion_item_to_text_edits_json,
    editor_core_ffi_lsp_formatting_options_json, editor_core_ffi_lsp_utf16_to_char_offset,
    editor_core_ffi_runtime_info_json, editor_core_ffi_string_free,
    editor_core_ffi_workspace_apply_text_edits_envelope_json, editor_core_ffi_workspace_backspace,
    editor_core_ffi_workspace_create_view_typed, editor_core_ffi_workspace_execute_envelope_json,
    editor_core_ffi_workspace_free, editor_core_ffi_workspace_get_info,
    editor_core_ffi_workspace_get_viewport_blob, editor_core_ffi_workspace_get_viewport_state,
    editor_core_ffi_workspace_insert_text_utf8, editor_core_ffi_workspace_minimap_envelope_json,
    editor_core_ffi_workspace_minimap_json, editor_core_ffi_workspace_move_to,
    editor_core_ffi_workspace_new, editor_core_ffi_workspace_open_buffer_typed,
    editor_core_ffi_workspace_search_all_open_buffers_envelope_json,
    editor_core_ffi_workspace_set_smooth_scroll_state,
    editor_core_ffi_workspace_set_viewport_height,
    editor_core_ffi_workspace_viewport_composed_envelope_json,
    editor_core_ffi_workspace_viewport_composed_json,
    editor_core_ffi_workspace_viewport_styled_envelope_json,
    editor_core_ffi_workspace_viewport_styled_json,
};
use std::ffi::{CStr, CString};

fn status(v: EcfStatus) -> i32 {
    v as i32
}

fn take_string(ptr: *mut std::ffi::c_char) -> String {
    assert!(!ptr.is_null());
    // SAFETY: pointer returned by ffi and nul-terminated.
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ffi_string_free(ptr) };
    text
}

fn read_u32_le(bytes: &[u8], off: usize) -> u32 {
    u32::from_le_bytes(bytes[off..off + 4].try_into().expect("u32"))
}

#[test]
fn abi_version_and_alias_work() {
    assert_eq!(ecf_abi_version(), ECF_ABI_VERSION);
}

#[test]
fn feature_flags_and_alias_work() {
    let flags = editor_core_ffi_feature_flags();
    assert_eq!(ecf_feature_flags(), flags);
    assert_ne!(flags & ECF_FEATURE_JSON_COMMAND_DISPATCH, 0);
    assert_ne!(flags & ECF_FEATURE_TYPED_HOT_PATH, 0);
    assert_ne!(flags & ECF_FEATURE_WORKSPACE_TYPED_API, 0);
    assert_ne!(flags & ECF_FEATURE_VIEWPORT_BLOB, 0);
    assert_ne!(flags & ECF_FEATURE_PROCESSING_EDIT_JSON, 0);
    assert_ne!(flags & ECF_FEATURE_LSP_HELPERS, 0);
    assert_ne!(flags & ECF_FEATURE_SUBLIME_PROCESSOR, 0);
    assert_ne!(flags & ECF_FEATURE_TREESITTER_PROCESSOR, 0);
    assert_ne!(flags & ECF_FEATURE_JSON_COMMAND_ENVELOPE, 0);
    assert_ne!(flags & ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE, 0);
    assert_ne!(
        flags & ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE,
        0
    );
    assert_ne!(flags & ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE, 0);
}

#[test]
fn runtime_info_json_reports_version_and_feature_descriptors() {
    let runtime_json = take_string(editor_core_ffi_runtime_info_json());
    let runtime: serde_json::Value = serde_json::from_str(&runtime_json).unwrap();

    assert_eq!(runtime["kind"], "editor-core-ffi");
    assert_eq!(runtime["abi_version"], ECF_ABI_VERSION);
    assert_eq!(runtime["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(runtime["feature_flags"], editor_core_ffi_feature_flags());

    let features = runtime["features"].as_array().expect("features array");
    assert!(features.iter().any(|feature| {
        feature["name"] == "json_command_envelope"
            && feature["bit"] == 8
            && feature["flag"] == ECF_FEATURE_JSON_COMMAND_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "rendering_snapshot_envelope"
            && feature["bit"] == 9
            && feature["flag"] == ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "editor_state_derived_snapshot_envelope"
            && feature["bit"] == 10
            && feature["flag"] == ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "workspace_result_envelope"
            && feature["bit"] == 11
            && feature["flag"] == ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "lsp_helpers"
            && feature["flag"].as_u64().unwrap() & ECF_FEATURE_LSP_HELPERS != 0
    }));
}

#[test]
fn public_abi_scalar_signatures_are_fixed_width() {
    let _: extern "C" fn() -> u64 = editor_core_ffi_feature_flags;
    let _: extern "C" fn() -> u64 = ecf_feature_flags;
    let _: extern "C" fn() -> *mut std::ffi::c_char = editor_core_ffi_runtime_info_json;

    let _: extern "C" fn(*const std::ffi::c_char, u32) -> *mut EcfEditorState =
        editor_core_ffi_editor_state_new;
    let _: extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_viewport_styled_json;
    let _: extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_viewport_styled_envelope_json;
    let _: extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_minimap_json;
    let _: extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_minimap_envelope_json;
    let _: extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_viewport_composed_json;
    let _: extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_viewport_composed_envelope_json;
    let _: extern "C" fn(*mut EcfEditorState, *const std::ffi::c_char) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_execute_envelope_json;
    let _: extern "C" fn(*const EcfEditorState, *const std::ffi::c_char) -> *mut std::ffi::c_char =
        editor_core_ffi_editor_state_derived_snapshot_envelope_json;

    let _: unsafe extern "C" fn(
        *mut EcfWorkspace,
        *const std::ffi::c_char,
        *const std::ffi::c_char,
        u32,
        *mut EcfOpenBufferResult,
    ) -> i32 = editor_core_ffi_workspace_open_buffer_typed;
    let _: unsafe extern "C" fn(*mut EcfWorkspace, u64, u32, *mut EcfCreateViewResult) -> i32 =
        editor_core_ffi_workspace_create_view_typed;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32) -> bool =
        editor_core_ffi_workspace_set_viewport_height;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32, u16, u32) -> bool =
        editor_core_ffi_workspace_set_smooth_scroll_state;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_viewport_styled_json;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_viewport_styled_envelope_json;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_minimap_json;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_minimap_envelope_json;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_viewport_composed_json;
    let _: extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_viewport_composed_envelope_json;
    let _: extern "C" fn(*mut EcfWorkspace, u64, *const std::ffi::c_char) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_execute_envelope_json;
    let _: extern "C" fn(
        *const EcfWorkspace,
        *const std::ffi::c_char,
        *const std::ffi::c_char,
    ) -> *mut std::ffi::c_char = editor_core_ffi_workspace_search_all_open_buffers_envelope_json;
    let _: extern "C" fn(*mut EcfWorkspace, *const std::ffi::c_char) -> *mut std::ffi::c_char =
        editor_core_ffi_workspace_apply_text_edits_envelope_json;

    let _: extern "C" fn(*const std::ffi::c_char, u64) -> u64 =
        editor_core_ffi_lsp_char_offset_to_utf16;
    let _: extern "C" fn(*const std::ffi::c_char, u64) -> u64 =
        editor_core_ffi_lsp_utf16_to_char_offset;
    let _: extern "C" fn(u32, bool) -> *mut std::ffi::c_char =
        editor_core_ffi_lsp_formatting_options_json;
    let _: extern "C" fn(
        *const EcfEditorState,
        *const std::ffi::c_char,
        *const std::ffi::c_char,
        u64,
        u64,
        bool,
    ) -> *mut std::ffi::c_char = editor_core_ffi_lsp_completion_item_to_text_edits_json;
}

#[test]
fn typed_editor_commands_and_stats_work() {
    let initial = CString::new("abc\n").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    let mut stats = EcfDocumentStats {
        abi_version: 0,
        struct_size: std::mem::size_of::<EcfDocumentStats>() as u32,
        line_count: 0,
        char_count: 0,
        byte_count: 0,
        is_modified: 0,
        reserved0: [0; 7],
        version: 0,
    };

    let st = unsafe { editor_core_ffi_editor_get_document_stats(state, &mut stats) };
    assert_eq!(st, status(EcfStatus::Ok));
    assert_eq!(stats.abi_version, ECF_ABI_VERSION);
    assert_eq!(stats.line_count, 2);

    let st = ecf_editor_move_to(state, 0, 3);
    assert_eq!(st, status(EcfStatus::Ok));

    let insert = b"XYZ";
    let st = ecf_editor_insert_text_utf8(state, insert.as_ptr(), insert.len() as u32);
    assert_eq!(st, status(EcfStatus::Ok));

    let st = ecf_editor_backspace(state);
    assert_eq!(st, status(EcfStatus::Ok));

    let st = unsafe { editor_core_ffi_editor_get_document_stats(state, &mut stats) };
    assert_eq!(st, status(EcfStatus::Ok));
    assert!(stats.char_count >= 6);
    assert_eq!(stats.is_modified, 1);

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn editor_state_execute_envelope_json_reports_success_and_errors() {
    let initial = CString::new("abc\n").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    let command = CString::new(r#"{"kind":"edit","op":"insert_text","text":"!"}"#).unwrap();
    let ok_json = take_string(editor_core_ffi_editor_state_execute_envelope_json(
        state,
        command.as_ptr(),
    ));
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["version"], ECF_ABI_VERSION);
    assert_eq!(ok["value"]["kind"], "success");
    assert!(ok["error"].is_null());

    let bad_json = CString::new("{this is not json").unwrap();
    let parse_json = take_string(editor_core_ffi_editor_state_execute_envelope_json(
        state,
        bad_json.as_ptr(),
    ));
    let parse: serde_json::Value = serde_json::from_str(&parse_json).unwrap();
    assert_eq!(parse["ok"], false);
    assert_eq!(parse["error"]["code"], "parse");
    assert_eq!(parse["error"]["status"], status(EcfStatus::Parse));

    let command = CString::new(r#"{"kind":"view","op":"set_viewport_width","width":0}"#).unwrap();
    let failed_json = take_string(editor_core_ffi_editor_state_execute_envelope_json(
        state,
        command.as_ptr(),
    ));
    let failed: serde_json::Value = serde_json::from_str(&failed_json).unwrap();
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["error"]["code"], "command_failed");
    assert_eq!(failed["error"]["status"], status(EcfStatus::CommandFailed));
    assert!(
        failed["error"]["message"]
            .as_str()
            .unwrap()
            .contains("command execution failed")
    );

    let null_arg_json = take_string(editor_core_ffi_editor_state_execute_envelope_json(
        state,
        std::ptr::null(),
    ));
    let null_arg: serde_json::Value = serde_json::from_str(&null_arg_json).unwrap();
    assert_eq!(null_arg["ok"], false);
    assert_eq!(null_arg["error"]["code"], "invalid_argument");
    assert_eq!(
        null_arg["error"]["status"],
        status(EcfStatus::InvalidArgument)
    );
    assert_eq!(null_arg["error"]["message"], "command_json is null");

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn editor_state_minimap_envelope_json_reports_success_and_errors() {
    let initial = CString::new("abc\nsecond\nthird\n").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    let ok_json = take_string(editor_core_ffi_editor_state_minimap_envelope_json(
        state, 0, 20,
    ));
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["status"], "success");
    assert_eq!(ok["surface"], "editor_state_minimap");
    assert!(ok["view_id"].is_null());
    assert_eq!(ok["start_visual_row"], 0);
    assert_eq!(ok["count"], 20);
    assert!(ok["value"]["lines"].is_array());
    assert!(ok["error"].is_null());
    assert_eq!(ok["version"], ECF_ABI_VERSION);

    let failed_json = take_string(editor_core_ffi_editor_state_minimap_envelope_json(
        std::ptr::null(),
        0,
        20,
    ));
    let failed: serde_json::Value = serde_json::from_str(&failed_json).unwrap();
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["status"], "error");
    assert_eq!(failed["surface"], "editor_state_minimap");
    assert!(failed["view_id"].is_null());
    assert_eq!(failed["value"], serde_json::Value::Null);
    assert_eq!(failed["error"]["code"], "invalid_argument");
    assert_eq!(
        failed["error"]["status"],
        status(EcfStatus::InvalidArgument)
    );
    assert_eq!(failed["error"]["message"], "state is null");

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn editor_state_viewport_envelope_json_reports_success_and_errors() {
    let initial = CString::new("abc\nsecond\nthird\n").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    for (surface, function) in [
        (
            "editor_state_viewport_styled",
            editor_core_ffi_editor_state_viewport_styled_envelope_json
                as extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char,
        ),
        (
            "editor_state_viewport_composed",
            editor_core_ffi_editor_state_viewport_composed_envelope_json
                as extern "C" fn(*const EcfEditorState, u32, u32) -> *mut std::ffi::c_char,
        ),
    ] {
        let ok_json = take_string(function(state, 0, 20));
        let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
        assert_eq!(ok["ok"], true);
        assert_eq!(ok["status"], "success");
        assert_eq!(ok["surface"], surface);
        assert!(ok["view_id"].is_null());
        assert_eq!(ok["start_visual_row"], 0);
        assert_eq!(ok["count"], 20);
        assert!(ok["value"]["lines"].is_array());
        assert!(ok["error"].is_null());
        assert_eq!(ok["version"], ECF_ABI_VERSION);

        let failed_json = take_string(function(std::ptr::null(), 0, 20));
        let failed: serde_json::Value = serde_json::from_str(&failed_json).unwrap();
        assert_eq!(failed["ok"], false);
        assert_eq!(failed["status"], "error");
        assert_eq!(failed["surface"], surface);
        assert!(failed["view_id"].is_null());
        assert_eq!(failed["value"], serde_json::Value::Null);
        assert_eq!(failed["error"]["code"], "invalid_argument");
        assert_eq!(
            failed["error"]["status"],
            status(EcfStatus::InvalidArgument)
        );
        assert_eq!(failed["error"]["message"], "state is null");
    }

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn editor_state_derived_snapshot_envelope_json_reports_success_and_errors() {
    let initial = CString::new("abc\nsecond\nthird\n").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    for (snapshot, expected_key) in [
        ("document_symbols", "symbols"),
        ("diagnostics", "diagnostics"),
        ("decorations", "layers"),
    ] {
        let snapshot_c = CString::new(snapshot).unwrap();
        let ok_json = take_string(editor_core_ffi_editor_state_derived_snapshot_envelope_json(
            state,
            snapshot_c.as_ptr(),
        ));
        let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
        assert_eq!(ok["ok"], true);
        assert_eq!(ok["status"], "success");
        assert_eq!(ok["snapshot"], snapshot);
        assert!(ok["value"][expected_key].is_array());
        assert!(ok["error"].is_null());
        assert_eq!(ok["version"], ECF_ABI_VERSION);
    }

    let unknown = CString::new("unknown").unwrap();
    let failed_json = take_string(editor_core_ffi_editor_state_derived_snapshot_envelope_json(
        state,
        unknown.as_ptr(),
    ));
    let failed: serde_json::Value = serde_json::from_str(&failed_json).unwrap();
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["status"], "error");
    assert_eq!(failed["snapshot"], "unknown");
    assert_eq!(failed["value"], serde_json::Value::Null);
    assert_eq!(failed["error"]["code"], "invalid_argument");
    assert_eq!(
        failed["error"]["status"],
        status(EcfStatus::InvalidArgument)
    );
    assert!(
        failed["error"]["message"]
            .as_str()
            .unwrap()
            .contains("unknown editor state derived snapshot")
    );

    let null_arg_json = take_string(editor_core_ffi_editor_state_derived_snapshot_envelope_json(
        state,
        std::ptr::null(),
    ));
    let null_arg: serde_json::Value = serde_json::from_str(&null_arg_json).unwrap();
    assert_eq!(null_arg["ok"], false);
    assert_eq!(null_arg["status"], "error");
    assert!(null_arg["snapshot"].is_null());
    assert_eq!(null_arg["error"]["code"], "invalid_argument");
    assert_eq!(null_arg["error"]["message"], "snapshot_utf8 is null");

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn invalid_utf8_returns_status_and_error_message() {
    let initial = CString::new("hello").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    let invalid = [0xFFu8, 0xFFu8, 0x00u8];
    let st = editor_core_ffi_editor_insert_text_utf8(state, invalid.as_ptr(), 2);
    assert_eq!(st, status(EcfStatus::InvalidUtf8));

    let msg = take_string(unsafe { editor_core_ffi_last_error_message() });
    assert!(msg.contains("utf") || msg.contains("UTF"));

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn typed_abi_invalid_required_output_pointer_reports_invalid_argument() {
    let workspace = editor_core_ffi_workspace_new();
    assert!(!workspace.is_null());

    let text = CString::new("abc\n").expect("cstring");
    let st = unsafe {
        editor_core_ffi_workspace_open_buffer_typed(
            workspace,
            std::ptr::null(),
            text.as_ptr(),
            u32::MAX,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(st, status(EcfStatus::InvalidArgument));
    let msg = take_string(unsafe { editor_core_ffi_last_error_message() });
    assert!(msg.contains("out_result"));

    unsafe { editor_core_ffi_workspace_free(workspace) };
}

#[test]
fn lsp_coordinate_helpers_accept_u64_boundary_without_truncating() {
    let text = CString::new("a👋b").expect("cstring");

    assert_eq!(
        editor_core_ffi_lsp_char_offset_to_utf16(text.as_ptr(), 0),
        0
    );
    assert_eq!(
        editor_core_ffi_lsp_char_offset_to_utf16(text.as_ptr(), 2),
        3
    );
    assert_eq!(
        editor_core_ffi_lsp_char_offset_to_utf16(text.as_ptr(), u64::MAX),
        4
    );

    assert_eq!(
        editor_core_ffi_lsp_utf16_to_char_offset(text.as_ptr(), 0),
        0
    );
    assert_eq!(
        editor_core_ffi_lsp_utf16_to_char_offset(text.as_ptr(), 4),
        3
    );
    assert_eq!(
        editor_core_ffi_lsp_utf16_to_char_offset(text.as_ptr(), u64::MAX),
        3
    );
}

#[test]
fn viewport_blob_two_call_pattern_works() {
    let initial = CString::new("hello\nworld\n").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    let mut out_len = 0u32;
    let st = editor_core_ffi_editor_get_viewport_blob(
        state,
        0,
        32,
        std::ptr::null_mut(),
        0,
        &mut out_len,
    );
    assert_eq!(st, status(EcfStatus::BufferTooSmall));
    assert!(out_len > 0);

    let mut too_small = vec![0u8; (out_len as usize).saturating_sub(1)];
    let st = editor_core_ffi_editor_get_viewport_blob(
        state,
        0,
        32,
        too_small.as_mut_ptr(),
        too_small.len() as u32,
        &mut out_len,
    );
    assert_eq!(st, status(EcfStatus::BufferTooSmall));

    let mut blob = vec![0u8; out_len as usize];
    let st = ecf_editor_get_viewport_blob(
        state,
        0,
        32,
        blob.as_mut_ptr(),
        blob.len() as u32,
        &mut out_len,
    );
    assert_eq!(st, status(EcfStatus::Ok));
    assert_eq!(blob.len(), out_len as usize);

    let abi = read_u32_le(&blob, 0);
    let header_size = read_u32_le(&blob, 4);
    let line_count = read_u32_le(&blob, 8);
    let cell_count = read_u32_le(&blob, 12);
    let lines_offset = read_u32_le(&blob, 20);
    let cells_offset = read_u32_le(&blob, 24);
    let styles_offset = read_u32_le(&blob, 28);

    assert_eq!(abi, ECF_ABI_VERSION);
    assert_eq!(
        header_size as usize,
        std::mem::size_of::<editor_core_ffi::EcfViewportBlobHeader>()
    );
    assert!(line_count > 0);
    assert!(cell_count > 0);
    assert!(lines_offset >= header_size);
    assert!(cells_offset >= lines_offset);
    assert!(styles_offset >= cells_offset);

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn workspace_typed_commands_and_blob_work() {
    let workspace = editor_core_ffi_workspace_new();
    assert!(!workspace.is_null());

    let text = CString::new("abc\n").expect("cstring");
    let mut opened = EcfOpenBufferResult {
        abi_version: 0,
        struct_size: 0,
        buffer_id: 0,
        view_id: 0,
    };
    let st = unsafe {
        editor_core_ffi_workspace_open_buffer_typed(
            workspace,
            std::ptr::null(),
            text.as_ptr(),
            80,
            &mut opened,
        )
    };
    assert_eq!(st, status(EcfStatus::Ok));
    assert_eq!(opened.abi_version, ECF_ABI_VERSION);
    assert_eq!(
        opened.struct_size as usize,
        std::mem::size_of::<EcfOpenBufferResult>()
    );

    let buffer_id = opened.buffer_id;
    let view_id = opened.view_id;

    let mut info = EcfWorkspaceInfo {
        abi_version: 0,
        struct_size: 0,
        buffer_count: 0,
        view_count: 0,
        is_empty: 0,
        has_active_view_id: 0,
        has_active_buffer_id: 0,
        reserved0: 0,
        active_view_id: 0,
        active_buffer_id: 0,
    };
    let st = unsafe { editor_core_ffi_workspace_get_info(workspace, &mut info) };
    assert_eq!(st, status(EcfStatus::Ok));
    assert_eq!(info.abi_version, ECF_ABI_VERSION);
    assert_eq!(info.buffer_count, 1);
    assert_eq!(info.view_count, 1);
    assert_eq!(info.is_empty, 0);
    assert_eq!(info.has_active_view_id, 1);
    assert_eq!(info.has_active_buffer_id, 1);
    assert_eq!(info.active_view_id, view_id);
    assert_eq!(info.active_buffer_id, buffer_id);

    let insert = b"123";
    let st = editor_core_ffi_workspace_insert_text_utf8(
        workspace,
        view_id,
        insert.as_ptr(),
        insert.len() as u32,
    );
    assert_eq!(st, status(EcfStatus::Ok));

    let st = editor_core_ffi_workspace_move_to(workspace, view_id, 0, 1);
    assert_eq!(st, status(EcfStatus::Ok));

    let st = editor_core_ffi_workspace_backspace(workspace, view_id);
    assert_eq!(st, status(EcfStatus::Ok));

    assert!(editor_core_ffi_workspace_set_viewport_height(
        workspace, view_id, 1
    ));
    assert!(editor_core_ffi_workspace_set_smooth_scroll_state(
        workspace, view_id, 0, 123, 2
    ));
    let mut viewport = EcfWorkspaceViewportState {
        abi_version: 0,
        struct_size: 0,
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
    let st =
        unsafe { editor_core_ffi_workspace_get_viewport_state(workspace, view_id, &mut viewport) };
    assert_eq!(st, status(EcfStatus::Ok));
    assert_eq!(viewport.abi_version, ECF_ABI_VERSION);
    assert_eq!(
        viewport.struct_size as usize,
        std::mem::size_of::<EcfWorkspaceViewportState>()
    );
    assert_eq!(viewport.width_cells, 80);
    assert_eq!(viewport.has_height, 1);
    assert_eq!(viewport.height_rows, 1);
    assert_eq!(viewport.scroll_top, 0);
    assert_eq!(viewport.sub_row_offset, 123);
    assert_eq!(viewport.overscan_rows, 2);
    assert!(viewport.total_visual_lines >= 2);
    assert_eq!(viewport.visible_start, 0);
    assert_eq!(viewport.visible_end, 1);
    assert_eq!(viewport.prefetch_start, 0);
    assert_eq!(viewport.prefetch_end, 2);

    let mut out_len = 0u32;
    let st = editor_core_ffi_workspace_get_viewport_blob(
        workspace,
        view_id,
        0,
        32,
        std::ptr::null_mut(),
        0,
        &mut out_len,
    );
    assert_eq!(st, status(EcfStatus::BufferTooSmall));
    assert!(out_len > 0);

    let mut blob = vec![0u8; out_len as usize];
    let st = editor_core_ffi_workspace_get_viewport_blob(
        workspace,
        view_id,
        0,
        32,
        blob.as_mut_ptr(),
        blob.len() as u32,
        &mut out_len,
    );
    assert_eq!(st, status(EcfStatus::Ok));

    unsafe { editor_core_ffi_workspace_free(workspace) };
}

#[test]
fn workspace_execute_envelope_json_reports_success_and_errors() {
    let workspace = editor_core_ffi_workspace_new();
    assert!(!workspace.is_null());

    let text = CString::new("abc\n").expect("cstring");
    let mut opened = EcfOpenBufferResult {
        abi_version: 0,
        struct_size: 0,
        buffer_id: 0,
        view_id: 0,
    };
    let st = unsafe {
        editor_core_ffi_workspace_open_buffer_typed(
            workspace,
            std::ptr::null(),
            text.as_ptr(),
            80,
            &mut opened,
        )
    };
    assert_eq!(st, status(EcfStatus::Ok));

    let command = CString::new(r#"{"kind":"edit","op":"insert_text","text":"!"}"#).unwrap();
    let ok_json = take_string(editor_core_ffi_workspace_execute_envelope_json(
        workspace,
        opened.view_id,
        command.as_ptr(),
    ));
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["version"], ECF_ABI_VERSION);
    assert_eq!(ok["value"]["kind"], "success");

    let bad_json = CString::new("{this is not json").unwrap();
    let parse_json = take_string(editor_core_ffi_workspace_execute_envelope_json(
        workspace,
        opened.view_id,
        bad_json.as_ptr(),
    ));
    let parse: serde_json::Value = serde_json::from_str(&parse_json).unwrap();
    assert_eq!(parse["ok"], false);
    assert_eq!(parse["error"]["code"], "parse");
    assert_eq!(parse["error"]["status"], status(EcfStatus::Parse));

    let command = CString::new(r#"{"kind":"cursor","op":"move_to","line":0,"column":0}"#).unwrap();
    let failed_json = take_string(editor_core_ffi_workspace_execute_envelope_json(
        workspace,
        999_999,
        command.as_ptr(),
    ));
    let failed: serde_json::Value = serde_json::from_str(&failed_json).unwrap();
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["error"]["code"], "command_failed");
    assert_eq!(failed["error"]["status"], status(EcfStatus::CommandFailed));
    assert!(
        failed["error"]["message"]
            .as_str()
            .unwrap()
            .contains("workspace execute failed")
    );

    unsafe { editor_core_ffi_workspace_free(workspace) };
}

#[test]
fn workspace_result_envelope_json_reports_success_and_errors() {
    let workspace = editor_core_ffi_workspace_new();
    assert!(!workspace.is_null());

    let text = CString::new("alpha beta\nsecond alpha\n").expect("cstring");
    let uri = CString::new("file:///workspace-result.txt").expect("cstring");
    let mut opened = EcfOpenBufferResult {
        abi_version: 0,
        struct_size: 0,
        buffer_id: 0,
        view_id: 0,
    };
    let st = unsafe {
        editor_core_ffi_workspace_open_buffer_typed(
            workspace,
            uri.as_ptr(),
            text.as_ptr(),
            80,
            &mut opened,
        )
    };
    assert_eq!(st, status(EcfStatus::Ok));

    let query = CString::new("alpha").unwrap();
    let search_json = take_string(
        editor_core_ffi_workspace_search_all_open_buffers_envelope_json(
            workspace,
            query.as_ptr(),
            std::ptr::null(),
        ),
    );
    let search: serde_json::Value = serde_json::from_str(&search_json).unwrap();
    assert_eq!(search["ok"], true);
    assert_eq!(search["status"], "success");
    assert_eq!(search["operation"], "search_all_open_buffers");
    assert_eq!(search["version"], ECF_ABI_VERSION);
    assert!(search["error"].is_null());
    let results = search["value"]["results"].as_array().unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["buffer_id"], opened.buffer_id);
    assert_eq!(results[0]["uri"], "file:///workspace-result.txt");
    assert_eq!(results[0]["matches"].as_array().unwrap().len(), 2);

    let bad_options = CString::new("{this is not json").unwrap();
    let parse_json = take_string(
        editor_core_ffi_workspace_search_all_open_buffers_envelope_json(
            workspace,
            query.as_ptr(),
            bad_options.as_ptr(),
        ),
    );
    let parse: serde_json::Value = serde_json::from_str(&parse_json).unwrap();
    assert_eq!(parse["ok"], false);
    assert_eq!(parse["status"], "error");
    assert_eq!(parse["operation"], "search_all_open_buffers");
    assert!(parse["value"].is_null());
    assert_eq!(parse["error"]["code"], "parse");
    assert_eq!(parse["error"]["status"], status(EcfStatus::Parse));
    assert!(
        parse["error"]["message"]
            .as_str()
            .unwrap()
            .contains("invalid search options JSON")
    );

    let edits = CString::new(format!(
        r#"[{{"buffer_id":{},"edits":[{{"start":0,"end":5,"text":"omega"}}]}}]"#,
        opened.buffer_id
    ))
    .unwrap();
    let apply_json = take_string(editor_core_ffi_workspace_apply_text_edits_envelope_json(
        workspace,
        edits.as_ptr(),
    ));
    let apply: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(apply["ok"], true);
    assert_eq!(apply["status"], "success");
    assert_eq!(apply["operation"], "apply_text_edits");
    assert_eq!(apply["version"], ECF_ABI_VERSION);
    assert!(apply["error"].is_null());
    let applied = apply["value"]["applied"].as_array().unwrap();
    assert_eq!(applied.len(), 1);
    assert_eq!(applied[0]["buffer_id"], opened.buffer_id);
    assert_eq!(applied[0]["edit_count"], 1);

    let bad_edits = CString::new("{this is not json").unwrap();
    let parse_json = take_string(editor_core_ffi_workspace_apply_text_edits_envelope_json(
        workspace,
        bad_edits.as_ptr(),
    ));
    let parse: serde_json::Value = serde_json::from_str(&parse_json).unwrap();
    assert_eq!(parse["ok"], false);
    assert_eq!(parse["status"], "error");
    assert_eq!(parse["operation"], "apply_text_edits");
    assert!(parse["value"].is_null());
    assert_eq!(parse["error"]["code"], "parse");
    assert_eq!(parse["error"]["status"], status(EcfStatus::Parse));
    assert!(
        parse["error"]["message"]
            .as_str()
            .unwrap()
            .contains("invalid workspace text edits JSON")
    );

    let null_workspace_json =
        take_string(editor_core_ffi_workspace_apply_text_edits_envelope_json(
            std::ptr::null_mut(),
            edits.as_ptr(),
        ));
    let null_workspace: serde_json::Value = serde_json::from_str(&null_workspace_json).unwrap();
    assert_eq!(null_workspace["ok"], false);
    assert_eq!(null_workspace["status"], "error");
    assert_eq!(null_workspace["operation"], "apply_text_edits");
    assert_eq!(null_workspace["error"]["code"], "invalid_argument");
    assert_eq!(
        null_workspace["error"]["status"],
        status(EcfStatus::InvalidArgument)
    );
    assert_eq!(null_workspace["error"]["message"], "workspace is null");

    unsafe { editor_core_ffi_workspace_free(workspace) };
}

#[test]
fn workspace_minimap_envelope_json_reports_success_and_errors() {
    let workspace = editor_core_ffi_workspace_new();
    assert!(!workspace.is_null());

    let text = CString::new("abc\nsecond\nthird\n").expect("cstring");
    let mut opened = EcfOpenBufferResult {
        abi_version: 0,
        struct_size: 0,
        buffer_id: 0,
        view_id: 0,
    };
    let st = unsafe {
        editor_core_ffi_workspace_open_buffer_typed(
            workspace,
            std::ptr::null(),
            text.as_ptr(),
            80,
            &mut opened,
        )
    };
    assert_eq!(st, status(EcfStatus::Ok));

    let ok_json = take_string(editor_core_ffi_workspace_minimap_envelope_json(
        workspace,
        opened.view_id,
        0,
        20,
    ));
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["status"], "success");
    assert_eq!(ok["surface"], "workspace_minimap");
    assert_eq!(ok["view_id"], opened.view_id);
    assert_eq!(ok["start_visual_row"], 0);
    assert_eq!(ok["count"], 20);
    assert!(ok["value"]["lines"].is_array());
    assert!(ok["error"].is_null());
    assert_eq!(ok["version"], ECF_ABI_VERSION);

    let failed_json = take_string(editor_core_ffi_workspace_minimap_envelope_json(
        workspace, 999_999, 0, 20,
    ));
    let failed: serde_json::Value = serde_json::from_str(&failed_json).unwrap();
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["status"], "error");
    assert_eq!(failed["surface"], "workspace_minimap");
    assert_eq!(failed["view_id"], 999_999);
    assert_eq!(failed["value"], serde_json::Value::Null);
    assert_eq!(failed["error"]["code"], "internal");
    assert_eq!(failed["error"]["status"], status(EcfStatus::Internal));
    assert!(
        failed["error"]["message"]
            .as_str()
            .unwrap()
            .contains("get_minimap_content failed")
    );

    unsafe { editor_core_ffi_workspace_free(workspace) };
}

#[test]
fn workspace_viewport_envelope_json_reports_success_and_errors() {
    let workspace = editor_core_ffi_workspace_new();
    assert!(!workspace.is_null());

    let text = CString::new("abc\nsecond\nthird\n").expect("cstring");
    let mut opened = EcfOpenBufferResult {
        abi_version: 0,
        struct_size: 0,
        buffer_id: 0,
        view_id: 0,
    };
    let st = unsafe {
        editor_core_ffi_workspace_open_buffer_typed(
            workspace,
            std::ptr::null(),
            text.as_ptr(),
            80,
            &mut opened,
        )
    };
    assert_eq!(st, status(EcfStatus::Ok));

    for (surface, function, expected_error) in [
        (
            "workspace_viewport_styled",
            editor_core_ffi_workspace_viewport_styled_envelope_json
                as extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char,
            "get_viewport_content_styled failed",
        ),
        (
            "workspace_viewport_composed",
            editor_core_ffi_workspace_viewport_composed_envelope_json
                as extern "C" fn(*mut EcfWorkspace, u64, u32, u32) -> *mut std::ffi::c_char,
            "get_viewport_content_composed failed",
        ),
    ] {
        let ok_json = take_string(function(workspace, opened.view_id, 0, 20));
        let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
        assert_eq!(ok["ok"], true);
        assert_eq!(ok["status"], "success");
        assert_eq!(ok["surface"], surface);
        assert_eq!(ok["view_id"], opened.view_id);
        assert_eq!(ok["start_visual_row"], 0);
        assert_eq!(ok["count"], 20);
        assert!(ok["value"]["lines"].is_array());
        assert!(ok["error"].is_null());
        assert_eq!(ok["version"], ECF_ABI_VERSION);

        let failed_json = take_string(function(workspace, 999_999, 0, 20));
        let failed: serde_json::Value = serde_json::from_str(&failed_json).unwrap();
        assert_eq!(failed["ok"], false);
        assert_eq!(failed["status"], "error");
        assert_eq!(failed["surface"], surface);
        assert_eq!(failed["view_id"], 999_999);
        assert_eq!(failed["value"], serde_json::Value::Null);
        assert_eq!(failed["error"]["code"], "internal");
        assert_eq!(failed["error"]["status"], status(EcfStatus::Internal));
        assert!(
            failed["error"]["message"]
                .as_str()
                .unwrap()
                .contains(expected_error)
        );
    }

    unsafe { editor_core_ffi_workspace_free(workspace) };
}
