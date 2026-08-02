use crate::make_c_string_ptr;

/// ABI version for the UI C contract exposed by this crate.
pub const ECU_ABI_VERSION: u32 = 1;

/// Feature bit: generic JSON editor command dispatcher is available.
pub const ECU_FEATURE_JSON_COMMAND_DISPATCH: u64 = 1 << 0;
/// Feature bit: typed derived-state snapshot JSON exports are available.
pub const ECU_FEATURE_TYPED_DERIVED_SNAPSHOTS: u64 = 1 << 1;
/// Feature bit: LSP interactive request/take APIs are available.
pub const ECU_FEATURE_LSP_INTERACTIVE_REQUESTS: u64 = 1 << 2;
/// Feature bit: LSP status/capability snapshot is available.
pub const ECU_FEATURE_LSP_STATUS_SNAPSHOT: u64 = 1 << 3;
/// Feature bit: LSP WorkspaceEdit application helpers are available.
pub const ECU_FEATURE_WORKSPACE_EDIT_APPLICATION: u64 = 1 << 4;
/// Feature bit: multi-document UI orchestrator ABI is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_UI: u64 = 1 << 5;
/// Feature bit: multi-document workspace diagnostics store is available.
pub const ECU_FEATURE_WORKSPACE_DIAGNOSTICS_STORE: u64 = 1 << 6;
/// Feature bit: multi-document workspace diagnostics event stream is available.
pub const ECU_FEATURE_WORKSPACE_DIAGNOSTICS_EVENTS: u64 = 1 << 7;
/// Feature bit: per-EditorUi LSP result slot event stream is available.
pub const ECU_FEATURE_LSP_RESULT_EVENTS: u64 = 1 << 8;
/// Feature bit: multi-document/project LSP result event aggregation is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_LSP_RESULT_EVENTS: u64 = 1 << 9;
/// Feature bit: per-EditorUi LSP request lifecycle event stream is available.
pub const ECU_FEATURE_LSP_REQUEST_EVENTS: u64 = 1 << 10;
/// Feature bit: multi-document/project LSP request event aggregation is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_LSP_REQUEST_EVENTS: u64 = 1 << 11;
/// Feature bit: explicit LSP request cancel/timeout lifecycle markers are available.
pub const ECU_FEATURE_LSP_REQUEST_CANCEL_TIMEOUT_EVENTS: u64 = 1 << 12;
/// Feature bit: LSP semantic tokens full/delta/range request and typed Swift consumption are available.
pub const ECU_FEATURE_LSP_SEMANTIC_TOKENS_REQUESTS: u64 = 1 << 13;
/// Feature bit: LSP auxiliary inlay hint / document link request and typed Swift consumption are available.
pub const ECU_FEATURE_LSP_AUXILIARY_REQUESTS: u64 = 1 << 14;
/// Feature bit: LSP auxiliary inlay hint / document link resolve request APIs are available.
pub const ECU_FEATURE_LSP_AUXILIARY_RESOLVE_REQUESTS: u64 = 1 << 15;
/// Feature bit: per-EditorUi unified state event stream is available.
pub const ECU_FEATURE_EDITOR_UI_STATE_EVENTS: u64 = 1 << 16;
/// Feature bit: multi-document/project unified state event aggregation is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_STATE_EVENTS: u64 = 1 << 17;

pub const ECU_FEATURE_FLAGS: u64 = ECU_FEATURE_JSON_COMMAND_DISPATCH
    | ECU_FEATURE_TYPED_DERIVED_SNAPSHOTS
    | ECU_FEATURE_LSP_INTERACTIVE_REQUESTS
    | ECU_FEATURE_LSP_STATUS_SNAPSHOT
    | ECU_FEATURE_WORKSPACE_EDIT_APPLICATION
    | ECU_FEATURE_MULTI_DOCUMENT_UI
    | ECU_FEATURE_WORKSPACE_DIAGNOSTICS_STORE
    | ECU_FEATURE_WORKSPACE_DIAGNOSTICS_EVENTS
    | ECU_FEATURE_LSP_RESULT_EVENTS
    | ECU_FEATURE_MULTI_DOCUMENT_LSP_RESULT_EVENTS
    | ECU_FEATURE_LSP_REQUEST_EVENTS
    | ECU_FEATURE_MULTI_DOCUMENT_LSP_REQUEST_EVENTS
    | ECU_FEATURE_LSP_REQUEST_CANCEL_TIMEOUT_EVENTS
    | ECU_FEATURE_LSP_SEMANTIC_TOKENS_REQUESTS
    | ECU_FEATURE_LSP_AUXILIARY_REQUESTS
    | ECU_FEATURE_LSP_AUXILIARY_RESOLVE_REQUESTS
    | ECU_FEATURE_EDITOR_UI_STATE_EVENTS
    | ECU_FEATURE_MULTI_DOCUMENT_STATE_EVENTS;

/// Return the UI FFI crate version as string.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_version() -> *mut libc::c_char {
    make_c_string_ptr(env!("CARGO_PKG_VERSION").to_string())
}

/// Return ABI version for the UI C contract.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_abi_version() -> u32 {
    ECU_ABI_VERSION
}

/// Return a bitmask of optional UI FFI features supported by this build.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_feature_flags() -> u64 {
    ECU_FEATURE_FLAGS
}
