use editor_core_ffi::{
    ECF_ABI_VERSION, EcfDocumentStats, EcfStatus, ecf_abi_version, ecf_editor_backspace,
    ecf_editor_get_viewport_blob, ecf_editor_insert_text_utf8, ecf_editor_move_to,
    editor_core_ffi_editor_get_document_stats, editor_core_ffi_editor_get_viewport_blob,
    editor_core_ffi_editor_insert_text_utf8, editor_core_ffi_editor_state_free,
    editor_core_ffi_editor_state_new, editor_core_ffi_last_error_message,
    editor_core_ffi_string_free, editor_core_ffi_workspace_backspace,
    editor_core_ffi_workspace_free, editor_core_ffi_workspace_get_viewport_blob,
    editor_core_ffi_workspace_insert_text_utf8, editor_core_ffi_workspace_move_to,
    editor_core_ffi_workspace_new, editor_core_ffi_workspace_open_buffer,
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
    let opened_json_ptr =
        editor_core_ffi_workspace_open_buffer(workspace, std::ptr::null(), text.as_ptr(), 80);
    let opened_json = take_string(opened_json_ptr);
    let opened: serde_json::Value = serde_json::from_str(&opened_json).expect("open json");
    let view_id = opened["view_id"].as_u64().expect("view_id");

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
