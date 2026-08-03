/// Feature bit: generic headless JSON editor command dispatcher is available.
pub const ECF_FEATURE_JSON_COMMAND_DISPATCH: u64 = 1 << 0;
/// Feature bit: typed hot-path editing and movement APIs are available.
pub const ECF_FEATURE_TYPED_HOT_PATH: u64 = 1 << 1;
/// Feature bit: typed workspace open/create/info/viewport APIs are available.
pub const ECF_FEATURE_WORKSPACE_TYPED_API: u64 = 1 << 2;
/// Feature bit: binary viewport blob APIs are available.
pub const ECF_FEATURE_VIEWPORT_BLOB: u64 = 1 << 3;
/// Feature bit: processing edit JSON APIs are available.
pub const ECF_FEATURE_PROCESSING_EDIT_JSON: u64 = 1 << 4;
/// Feature bit: LSP conversion/helper JSON APIs are available.
pub const ECF_FEATURE_LSP_HELPERS: u64 = 1 << 5;
/// Feature bit: Sublime processor lifecycle and process/apply APIs are available.
pub const ECF_FEATURE_SUBLIME_PROCESSOR: u64 = 1 << 6;
/// Feature bit: Tree-sitter processor and indenter APIs are available.
pub const ECF_FEATURE_TREESITTER_PROCESSOR: u64 = 1 << 7;
/// Feature bit: JSON command dispatcher can return `{ ok, value, error, version }` envelopes.
pub const ECF_FEATURE_JSON_COMMAND_ENVELOPE: u64 = 1 << 8;

pub const ECF_FEATURE_FLAGS: u64 = ECF_FEATURE_JSON_COMMAND_DISPATCH
    | ECF_FEATURE_TYPED_HOT_PATH
    | ECF_FEATURE_WORKSPACE_TYPED_API
    | ECF_FEATURE_VIEWPORT_BLOB
    | ECF_FEATURE_PROCESSING_EDIT_JSON
    | ECF_FEATURE_LSP_HELPERS
    | ECF_FEATURE_SUBLIME_PROCESSOR
    | ECF_FEATURE_TREESITTER_PROCESSOR
    | ECF_FEATURE_JSON_COMMAND_ENVELOPE;

/// Return a bitmask of optional headless FFI features supported by this build.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_feature_flags() -> u64 {
    ECF_FEATURE_FLAGS
}

/// ABI-v1 alias: see `editor_core_ffi_feature_flags`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_feature_flags() -> u64 {
    editor_core_ffi_feature_flags()
}
