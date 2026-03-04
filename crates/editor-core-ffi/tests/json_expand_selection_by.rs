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
    editor_core_ffi_string_free(ptr);
    text
}

fn exec_json(state: *mut editor_core_ffi::EcfEditorState, cmd: &str) -> serde_json::Value {
    let cmd = CString::new(cmd).expect("cstring");
    let out_ptr = editor_core_ffi_editor_state_execute_json(state, cmd.as_ptr());
    if out_ptr.is_null() {
        let msg = take_string(editor_core_ffi_last_error_message());
        panic!("execute_json returned null; last_error={msg}");
    }
    let text = take_string(out_ptr);
    serde_json::from_str(&text).expect("result json")
}

#[test]
fn json_expand_selection_by_word_expands_only() {
    let initial = CString::new("one two three").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    let r = exec_json(state, r#"{ "kind": "cursor", "op": "move_to", "line": 0, "column": 4 }"#);
    assert_eq!(r["kind"], "success");

    let r = exec_json(
        state,
        r#"{ "kind": "cursor", "op": "expand_selection_by", "unit": "word", "count": 1, "direction": "forward" }"#,
    );
    assert_eq!(r["kind"], "success");

    let r = exec_json(
        state,
        r#"{ "kind": "cursor", "op": "expand_selection_by", "unit": "word", "count": 1, "direction": "forward" }"#,
    );
    assert_eq!(r["kind"], "success");

    // Change direction: expand-only behavior means we keep the existing end and only extend start.
    let r = exec_json(
        state,
        r#"{ "kind": "cursor", "op": "expand_selection_by", "unit": "word", "count": 1, "direction": "backward" }"#,
    );
    assert_eq!(r["kind"], "success");

    let full_ptr = editor_core_ffi_editor_state_full_state_json(state);
    let full_text = take_string(full_ptr);
    let full: serde_json::Value = serde_json::from_str(&full_text).expect("full state json");

    let sel = full["cursor"]["selection"].as_object().expect("selection object");
    assert_eq!(sel["start"]["line"], 0);
    assert_eq!(sel["start"]["column"], 0);
    assert_eq!(sel["end"]["line"], 0);
    assert_eq!(sel["end"]["column"], 13);

    editor_core_ffi_editor_state_free(state);
}

#[test]
fn json_unknown_op_returns_error() {
    let initial = CString::new("hello").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());

    let cmd = CString::new(r#"{ "kind": "cursor", "op": "expand_selection_by", "unit": "wat", "count": 1, "direction": "forward" }"#)
        .expect("cstring");
    let out_ptr = editor_core_ffi_editor_state_execute_json(state, cmd.as_ptr());
    assert!(out_ptr.is_null());
    let msg = take_string(editor_core_ffi_last_error_message());
    assert!(!msg.is_empty());

    editor_core_ffi_editor_state_free(state);
}
