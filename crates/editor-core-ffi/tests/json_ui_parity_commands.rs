use editor_core_ffi::{
    EcfEditorState, editor_core_ffi_editor_state_execute_json, editor_core_ffi_editor_state_free,
    editor_core_ffi_editor_state_full_state_json, editor_core_ffi_editor_state_new,
    editor_core_ffi_editor_state_text, editor_core_ffi_last_error_message,
    editor_core_ffi_string_free,
};
use std::ffi::{CStr, CString, c_char};

fn take_string(ptr: *mut c_char) -> String {
    assert!(!ptr.is_null());
    // SAFETY: pointer returned by ffi and nul-terminated.
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ffi_string_free(ptr) };
    text
}

fn new_state(text: &str) -> *mut EcfEditorState {
    let initial = CString::new(text).expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial.as_ptr(), 80);
    assert!(!state.is_null());
    state
}

fn exec_json(state: *mut EcfEditorState, cmd: &str) -> serde_json::Value {
    let cmd = CString::new(cmd).expect("cstring");
    let out_ptr = editor_core_ffi_editor_state_execute_json(state, cmd.as_ptr());
    if out_ptr.is_null() {
        let msg = take_string(unsafe { editor_core_ffi_last_error_message() });
        panic!("execute_json returned null; last_error={msg}");
    }
    let text = take_string(out_ptr);
    serde_json::from_str(&text).expect("result json")
}

fn assert_success(value: serde_json::Value) {
    assert_eq!(value["kind"], "success");
}

fn state_text(state: *mut EcfEditorState) -> String {
    let text = take_string(editor_core_ffi_editor_state_text(state));
    let value: serde_json::Value = serde_json::from_str(&text).expect("text json");
    value["text"].as_str().expect("text string").to_string()
}

fn cursor_offset(state: *mut EcfEditorState) -> u64 {
    let text = take_string(editor_core_ffi_editor_state_full_state_json(state));
    let value: serde_json::Value = serde_json::from_str(&text).expect("full state json");
    value["cursor"]["offset"].as_u64().expect("cursor offset")
}

#[test]
fn json_command_plane_accepts_type_char_auto_pairs_and_bracket_commands() {
    let state = new_state("(x)");

    assert_success(exec_json(
        state,
        r#"{"kind":"view","op":"set_auto_pairs_enabled","enabled":true}"#,
    ));
    assert_success(exec_json(
        state,
        r#"{"kind":"view","op":"set_auto_pairs_config","config":{"enabled":true,"pairs":[{"open":"<","close":">"}]}}"#,
    ));
    assert_success(exec_json(
        state,
        r#"{"kind":"cursor","op":"move_to","line":0,"column":3}"#,
    ));
    assert_success(exec_json(
        state,
        r#"{"kind":"edit","op":"type_char","ch":"<"}"#,
    ));
    assert_eq!(state_text(state), "(x)<>");

    assert_success(exec_json(
        state,
        r#"{"kind":"cursor","op":"move_to","line":0,"column":0}"#,
    ));
    assert_success(exec_json(
        state,
        r#"{"kind":"cursor","op":"move_to_matching_bracket"}"#,
    ));
    assert_eq!(cursor_offset(state), 2);

    assert_success(exec_json(
        state,
        r#"{"kind":"style","op":"update_bracket_match_highlights"}"#,
    ));
    assert_success(exec_json(
        state,
        r#"{"kind":"style","op":"clear_bracket_match_highlights"}"#,
    ));

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn json_command_plane_accepts_snippet_and_coalescing_commands() {
    let state = new_state("");

    assert_success(exec_json(
        state,
        r#"{"kind":"edit","op":"apply_snippet","start":0,"end":0,"snippet":"println!(${1:msg})$0","additional_edits":[]}"#,
    ));
    assert_eq!(state_text(state), "println!(msg)");

    assert_success(exec_json(
        state,
        r#"{"kind":"cursor","op":"snippet_next_placeholder"}"#,
    ));
    assert_success(exec_json(
        state,
        r#"{"kind":"cursor","op":"snippet_prev_placeholder"}"#,
    ));

    assert_success(exec_json(
        state,
        r#"{"kind":"edit","op":"replace_coalescing_undo","start":0,"length":7,"text":"log"}"#,
    ));
    assert_eq!(state_text(state), "log!(msg)");

    assert_success(exec_json(
        state,
        r#"{"kind":"edit","op":"replace_coalescing_undo_with_selection","start":0,"length":3,"text":"dbg","selection_start":0,"selection_end":3}"#,
    ));
    assert_eq!(state_text(state), "dbg!(msg)");

    unsafe { editor_core_ffi_editor_state_free(state) };
}

#[test]
fn json_command_plane_rejects_non_single_character_fields() {
    let state = new_state("");

    let cmd = CString::new(r#"{"kind":"edit","op":"type_char","ch":"too long"}"#).expect("cstring");
    let out_ptr = editor_core_ffi_editor_state_execute_json(state, cmd.as_ptr());
    assert!(out_ptr.is_null());
    let msg = take_string(unsafe { editor_core_ffi_last_error_message() });
    assert!(msg.contains("exactly one character"));

    let cmd = CString::new(
        r#"{"kind":"view","op":"set_auto_pairs_config","config":{"pairs":[{"open":"ab","close":">"}]}}"#,
    )
    .expect("cstring");
    let out_ptr = editor_core_ffi_editor_state_execute_json(state, cmd.as_ptr());
    assert!(out_ptr.is_null());
    let msg = take_string(unsafe { editor_core_ffi_last_error_message() });
    assert!(msg.contains("exactly one character"));

    unsafe { editor_core_ffi_editor_state_free(state) };
}
