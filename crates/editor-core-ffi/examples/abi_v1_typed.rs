use editor_core_ffi::{
    ECF_ABI_VERSION, EcfStatus, editor_core_ffi_editor_get_viewport_blob,
    editor_core_ffi_editor_insert_text_utf8, editor_core_ffi_editor_state_free,
    editor_core_ffi_editor_state_new,
};
use std::ffi::CString;

fn read_u32_le(bytes: &[u8], off: usize) -> u32 {
    u32::from_le_bytes(bytes[off..off + 4].try_into().expect("u32"))
}

fn main() {
    let initial_text = CString::new("fn main() {\n}\n").expect("cstring");
    let state = editor_core_ffi_editor_state_new(initial_text.as_ptr(), 80);
    assert!(!state.is_null());

    let insert = b"    println!(\"hello\");\n";
    let status =
        editor_core_ffi_editor_insert_text_utf8(state, insert.as_ptr(), insert.len() as u32);
    assert_eq!(status, EcfStatus::Ok as i32);

    let mut out_len = 0u32;
    let status = editor_core_ffi_editor_get_viewport_blob(
        state,
        0,
        64,
        std::ptr::null_mut(),
        0,
        &mut out_len,
    );
    assert_eq!(status, EcfStatus::BufferTooSmall as i32);
    assert!(out_len > 0);

    let mut blob = vec![0u8; out_len as usize];
    let status = editor_core_ffi_editor_get_viewport_blob(
        state,
        0,
        64,
        blob.as_mut_ptr(),
        blob.len() as u32,
        &mut out_len,
    );
    assert_eq!(status, EcfStatus::Ok as i32);

    let abi_version = read_u32_le(&blob, 0);
    assert_eq!(abi_version, ECF_ABI_VERSION);

    let line_count = read_u32_le(&blob, 8);
    let cell_count = read_u32_le(&blob, 12);
    println!(
        "blob header: abi={}, lines={}, cells={}",
        abi_version, line_count, cell_count
    );

    unsafe { editor_core_ffi_editor_state_free(state) };
}
