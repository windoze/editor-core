use crate::{ECF_ABI_VERSION, json_ptr};
use serde_json::{Value, json};

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
/// Feature bit: headless rendering snapshot query APIs can return structured envelopes.
pub const ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE: u64 = 1 << 9;
/// Feature bit: headless editor-state derived snapshot query APIs can return structured envelopes.
pub const ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE: u64 = 1 << 10;
/// Feature bit: headless workspace search/apply JSON result APIs can return structured envelopes.
pub const ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE: u64 = 1 << 11;
/// Feature bit: headless workspace query JSON APIs can return structured envelopes.
pub const ECF_FEATURE_WORKSPACE_QUERY_ENVELOPE: u64 = 1 << 12;
/// Feature bit: headless workspace lifecycle JSON APIs can return structured envelopes.
pub const ECF_FEATURE_WORKSPACE_LIFECYCLE_ENVELOPE: u64 = 1 << 13;
/// Feature bit: headless editor-state query JSON APIs can return structured envelopes.
pub const ECF_FEATURE_EDITOR_STATE_QUERY_ENVELOPE: u64 = 1 << 14;
/// Feature bit: headless LSP helper JSON APIs can return structured envelopes.
pub const ECF_FEATURE_LSP_HELPER_ENVELOPE: u64 = 1 << 15;

pub const ECF_FEATURE_FLAGS: u64 = ECF_FEATURE_JSON_COMMAND_DISPATCH
    | ECF_FEATURE_TYPED_HOT_PATH
    | ECF_FEATURE_WORKSPACE_TYPED_API
    | ECF_FEATURE_VIEWPORT_BLOB
    | ECF_FEATURE_PROCESSING_EDIT_JSON
    | ECF_FEATURE_LSP_HELPERS
    | ECF_FEATURE_SUBLIME_PROCESSOR
    | ECF_FEATURE_TREESITTER_PROCESSOR
    | ECF_FEATURE_JSON_COMMAND_ENVELOPE
    | ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE
    | ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE
    | ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE
    | ECF_FEATURE_WORKSPACE_QUERY_ENVELOPE
    | ECF_FEATURE_WORKSPACE_LIFECYCLE_ENVELOPE
    | ECF_FEATURE_EDITOR_STATE_QUERY_ENVELOPE
    | ECF_FEATURE_LSP_HELPER_ENVELOPE;

struct FeatureDescriptor {
    bit: u8,
    flag: u64,
    name: &'static str,
    description: &'static str,
}

const FEATURE_DESCRIPTORS: &[FeatureDescriptor] = &[
    FeatureDescriptor {
        bit: 0,
        flag: ECF_FEATURE_JSON_COMMAND_DISPATCH,
        name: "json_command_dispatch",
        description: "Generic headless JSON editor command dispatcher.",
    },
    FeatureDescriptor {
        bit: 1,
        flag: ECF_FEATURE_TYPED_HOT_PATH,
        name: "typed_hot_path",
        description: "Typed hot-path editing and movement APIs.",
    },
    FeatureDescriptor {
        bit: 2,
        flag: ECF_FEATURE_WORKSPACE_TYPED_API,
        name: "workspace_typed_api",
        description: "Typed workspace open/create/info/viewport APIs.",
    },
    FeatureDescriptor {
        bit: 3,
        flag: ECF_FEATURE_VIEWPORT_BLOB,
        name: "viewport_blob",
        description: "Binary viewport blob APIs.",
    },
    FeatureDescriptor {
        bit: 4,
        flag: ECF_FEATURE_PROCESSING_EDIT_JSON,
        name: "processing_edit_json",
        description: "Processing edit JSON APIs.",
    },
    FeatureDescriptor {
        bit: 5,
        flag: ECF_FEATURE_LSP_HELPERS,
        name: "lsp_helpers",
        description: "LSP conversion/helper JSON APIs.",
    },
    FeatureDescriptor {
        bit: 6,
        flag: ECF_FEATURE_SUBLIME_PROCESSOR,
        name: "sublime_processor",
        description: "Sublime processor lifecycle and process/apply APIs.",
    },
    FeatureDescriptor {
        bit: 7,
        flag: ECF_FEATURE_TREESITTER_PROCESSOR,
        name: "treesitter_processor",
        description: "Tree-sitter processor and indenter APIs.",
    },
    FeatureDescriptor {
        bit: 8,
        flag: ECF_FEATURE_JSON_COMMAND_ENVELOPE,
        name: "json_command_envelope",
        description: "JSON command dispatcher can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 9,
        flag: ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE,
        name: "rendering_snapshot_envelope",
        description: "Headless rendering snapshot query APIs can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 10,
        flag: ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE,
        name: "editor_state_derived_snapshot_envelope",
        description: "Headless editor-state derived snapshot query APIs can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 11,
        flag: ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE,
        name: "workspace_result_envelope",
        description: "Headless workspace search/apply JSON result APIs can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 12,
        flag: ECF_FEATURE_WORKSPACE_QUERY_ENVELOPE,
        name: "workspace_query_envelope",
        description: "Headless workspace info/buffer/viewport query APIs can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 13,
        flag: ECF_FEATURE_WORKSPACE_LIFECYCLE_ENVELOPE,
        name: "workspace_lifecycle_envelope",
        description: "Headless workspace open/create lifecycle JSON APIs can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 14,
        flag: ECF_FEATURE_EDITOR_STATE_QUERY_ENVELOPE,
        name: "editor_state_query_envelope",
        description: "Headless editor-state full-state/text/line-ending/text-delta query APIs can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 15,
        flag: ECF_FEATURE_LSP_HELPER_ENVELOPE,
        name: "lsp_helper_envelope",
        description: "Headless LSP URI, formatting, and normalization helper JSON APIs can return structured result envelopes.",
    },
];

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

/// Return structured runtime/capability information as JSON.
///
/// Caller owns returned string and must free it with `editor_core_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_runtime_info_json() -> *mut std::ffi::c_char {
    let features: Vec<Value> = FEATURE_DESCRIPTORS
        .iter()
        .map(|feature| {
            json!({
                "bit": feature.bit,
                "flag": feature.flag,
                "name": feature.name,
                "description": feature.description,
            })
        })
        .collect();
    json_ptr(json!({
        "kind": "editor-core-ffi",
        "abi_version": ECF_ABI_VERSION,
        "version": env!("CARGO_PKG_VERSION"),
        "feature_flags": ECF_FEATURE_FLAGS,
        "features": features,
    }))
}
