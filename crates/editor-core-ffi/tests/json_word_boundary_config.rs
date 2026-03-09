use editor_core_ffi::{
    editor_core_ffi_editor_state_execute_json, editor_core_ffi_editor_state_free,
    editor_core_ffi_editor_state_full_state_json, editor_core_ffi_editor_state_new,
    editor_core_ffi_last_error_message, editor_core_ffi_string_free,
};
use std::ffi::{CStr, CString};

fn take_string(ptr: *mut std::ffi::c_char) -> String {
    assert!(!ptr.is_null());
    // SAFETY: pointer returned by ffi and nul-terminated.
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ffi_string_free(ptr) };
    text
}

fn exec_json(state: *mut editor_core_ffi::EcfEditorState, cmd: &str) -> serde_json::Value {
    let cmd = CString::new(cmd).expect("cstring");
    let out_ptr = editor_core_ffi_editor_state_execute_json(state, cmd.as_ptr());
    if out_ptr.is_null() {
        let msg = take_string(unsafe { editor_core_ffi_last_error_message() });
        panic!("execute_json returned null; last_error={msg}");
    }
    let text = take_string(out_ptr);
    serde_json::from_str(&text).expect("result json")
}

fn selection_cols(state: *mut editor_core_ffi::EcfEditorState) -> (u64, u64) {
    let full_ptr = editor_core_ffi_editor_state_full_state_json(state);
    let full_text = take_string(full_ptr);
    let full: serde_json::Value = serde_json::from_str(&full_text).expect("full state json");
    let sel = full["cursor"]["selection"]
        .as_object()
        .expect("selection object");
    let start = sel["start"]["column"].as_u64().unwrap();
    let end = sel["end"]["column"].as_u64().unwrap();
    (start, end)
}

#[test]
fn json_word_boundary_config_affects_select_word() {
    let initial = CString::new("foo-bar").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    exec_json(
        state,
        r#"{ "kind": "cursor", "op": "move_to", "line": 0, "column": 1 }"#,
    );
    exec_json(state, r#"{ "kind": "cursor", "op": "select_word" }"#);
    assert_eq!(selection_cols(state), (0, 3));

    // Make '-' a word char by not including it in the boundary set.
    exec_json(
        state,
        r#"{ "kind": "view", "op": "set_word_boundary_ascii_boundary_chars", "boundary_chars": "." }"#,
    );

    // Clear selection so SelectWord will recompute using the new config.
    exec_json(state, r#"{ "kind": "cursor", "op": "clear_selection" }"#);
    exec_json(
        state,
        r#"{ "kind": "cursor", "op": "move_to", "line": 0, "column": 1 }"#,
    );
    exec_json(state, r#"{ "kind": "cursor", "op": "select_word" }"#);
    assert_eq!(selection_cols(state), (0, 7));

    // Reset defaults: '-' becomes boundary again.
    exec_json(
        state,
        r#"{ "kind": "view", "op": "reset_word_boundary_defaults" }"#,
    );
    exec_json(state, r#"{ "kind": "cursor", "op": "clear_selection" }"#);
    exec_json(
        state,
        r#"{ "kind": "cursor", "op": "move_to", "line": 0, "column": 1 }"#,
    );
    exec_json(state, r#"{ "kind": "cursor", "op": "select_word" }"#);
    assert_eq!(selection_cols(state), (0, 3));

    unsafe { editor_core_ffi_editor_state_free(state) };
}
