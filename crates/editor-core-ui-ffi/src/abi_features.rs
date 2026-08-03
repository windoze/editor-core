use crate::make_c_string_ptr;
use serde_json::{Value, json};

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
/// Feature bit: multi-document/project workspace outline snapshot is available.
pub const ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT: u64 = 1 << 18;
/// Feature bit: multi-document tab document URI metadata is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_TAB_DOCUMENT_URI: u64 = 1 << 19;
/// Feature bit: multi-document WorkspaceEdit transaction preview/apply is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION: u64 = 1 << 20;
/// Feature bit: multi-document WorkspaceEdit transaction event stream is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_EVENTS: u64 = 1 << 21;
/// Feature bit: multi-document workspace root URI metadata is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS: u64 = 1 << 22;
/// Feature bit: multi-document WorkspaceEdit transaction undo is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_UNDO: u64 = 1 << 23;
/// Feature bit: multi-document tab language id metadata is available.
pub const ECU_FEATURE_MULTI_DOCUMENT_TAB_LANGUAGE_ID: u64 = 1 << 24;
/// Feature bit: JSON command dispatcher can return `{ ok, value, error, version }` envelopes.
pub const ECU_FEATURE_JSON_COMMAND_ENVELOPE: u64 = 1 << 25;
/// Feature bit: LSP take-last result slots can return `{ ok, value, error, version }` envelopes.
pub const ECU_FEATURE_LSP_RESULT_ENVELOPE: u64 = 1 << 26;
/// Feature bit: UI event streams can return `{ ok, value, error, version }` envelopes.
pub const ECU_FEATURE_EVENT_STREAM_ENVELOPE: u64 = 1 << 27;
/// Feature bit: multi-document diagnostics and WorkspaceEdit event streams are available through the event envelope.
pub const ECU_FEATURE_MULTI_DOCUMENT_SPECIAL_EVENT_STREAM_ENVELOPE: u64 = 1 << 28;
/// Feature bit: multi-document WorkspaceEdit transactions can return structured result envelopes.
pub const ECU_FEATURE_WORKSPACE_EDIT_TRANSACTION_ENVELOPE: u64 = 1 << 29;
/// Feature bit: multi-document workspace diagnostics can return structured result envelopes.
pub const ECU_FEATURE_WORKSPACE_DIAGNOSTICS_ENVELOPE: u64 = 1 << 30;
/// Feature bit: multi-document workspace outline snapshots can return structured result envelopes.
pub const ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT_ENVELOPE: u64 = 1 << 31;
/// Feature bit: multi-document tab/project snapshots can return structured result envelopes.
pub const ECU_FEATURE_MULTI_DOCUMENT_SNAPSHOT_ENVELOPE: u64 = 1 << 32;
/// Feature bit: multi-document all-tabs search can return structured result envelopes.
pub const ECU_FEATURE_MULTI_DOCUMENT_SEARCH_ENVELOPE: u64 = 1 << 33;
/// Feature bit: multi-document workspace roots changes can return structured result envelopes.
pub const ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS_CHANGE_ENVELOPE: u64 = 1 << 34;

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
    | ECU_FEATURE_MULTI_DOCUMENT_STATE_EVENTS
    | ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT
    | ECU_FEATURE_MULTI_DOCUMENT_TAB_DOCUMENT_URI
    | ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION
    | ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_EVENTS
    | ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS
    | ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_UNDO
    | ECU_FEATURE_MULTI_DOCUMENT_TAB_LANGUAGE_ID
    | ECU_FEATURE_JSON_COMMAND_ENVELOPE
    | ECU_FEATURE_LSP_RESULT_ENVELOPE
    | ECU_FEATURE_EVENT_STREAM_ENVELOPE
    | ECU_FEATURE_MULTI_DOCUMENT_SPECIAL_EVENT_STREAM_ENVELOPE
    | ECU_FEATURE_WORKSPACE_EDIT_TRANSACTION_ENVELOPE
    | ECU_FEATURE_WORKSPACE_DIAGNOSTICS_ENVELOPE
    | ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT_ENVELOPE
    | ECU_FEATURE_MULTI_DOCUMENT_SNAPSHOT_ENVELOPE
    | ECU_FEATURE_MULTI_DOCUMENT_SEARCH_ENVELOPE
    | ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS_CHANGE_ENVELOPE;

struct FeatureDescriptor {
    bit: u8,
    flag: u64,
    name: &'static str,
    description: &'static str,
}

const FEATURE_DESCRIPTORS: &[FeatureDescriptor] = &[
    FeatureDescriptor {
        bit: 0,
        flag: ECU_FEATURE_JSON_COMMAND_DISPATCH,
        name: "json_command_dispatch",
        description: "Generic JSON editor command dispatcher.",
    },
    FeatureDescriptor {
        bit: 1,
        flag: ECU_FEATURE_TYPED_DERIVED_SNAPSHOTS,
        name: "typed_derived_snapshots",
        description: "Typed derived-state snapshot JSON exports.",
    },
    FeatureDescriptor {
        bit: 2,
        flag: ECU_FEATURE_LSP_INTERACTIVE_REQUESTS,
        name: "lsp_interactive_requests",
        description: "LSP interactive request/take APIs.",
    },
    FeatureDescriptor {
        bit: 3,
        flag: ECU_FEATURE_LSP_STATUS_SNAPSHOT,
        name: "lsp_status_snapshot",
        description: "LSP status/capability snapshot.",
    },
    FeatureDescriptor {
        bit: 4,
        flag: ECU_FEATURE_WORKSPACE_EDIT_APPLICATION,
        name: "workspace_edit_application",
        description: "LSP WorkspaceEdit application helpers.",
    },
    FeatureDescriptor {
        bit: 5,
        flag: ECU_FEATURE_MULTI_DOCUMENT_UI,
        name: "multi_document_ui",
        description: "Multi-document UI orchestrator ABI.",
    },
    FeatureDescriptor {
        bit: 6,
        flag: ECU_FEATURE_WORKSPACE_DIAGNOSTICS_STORE,
        name: "workspace_diagnostics_store",
        description: "Multi-document workspace diagnostics store.",
    },
    FeatureDescriptor {
        bit: 7,
        flag: ECU_FEATURE_WORKSPACE_DIAGNOSTICS_EVENTS,
        name: "workspace_diagnostics_events",
        description: "Multi-document workspace diagnostics event stream.",
    },
    FeatureDescriptor {
        bit: 8,
        flag: ECU_FEATURE_LSP_RESULT_EVENTS,
        name: "lsp_result_events",
        description: "Per-EditorUi LSP result slot event stream.",
    },
    FeatureDescriptor {
        bit: 9,
        flag: ECU_FEATURE_MULTI_DOCUMENT_LSP_RESULT_EVENTS,
        name: "multi_document_lsp_result_events",
        description: "Multi-document/project LSP result event aggregation.",
    },
    FeatureDescriptor {
        bit: 10,
        flag: ECU_FEATURE_LSP_REQUEST_EVENTS,
        name: "lsp_request_events",
        description: "Per-EditorUi LSP request lifecycle event stream.",
    },
    FeatureDescriptor {
        bit: 11,
        flag: ECU_FEATURE_MULTI_DOCUMENT_LSP_REQUEST_EVENTS,
        name: "multi_document_lsp_request_events",
        description: "Multi-document/project LSP request event aggregation.",
    },
    FeatureDescriptor {
        bit: 12,
        flag: ECU_FEATURE_LSP_REQUEST_CANCEL_TIMEOUT_EVENTS,
        name: "lsp_request_cancel_timeout_events",
        description: "Explicit LSP request cancel/timeout lifecycle markers.",
    },
    FeatureDescriptor {
        bit: 13,
        flag: ECU_FEATURE_LSP_SEMANTIC_TOKENS_REQUESTS,
        name: "lsp_semantic_tokens_requests",
        description: "LSP semantic tokens full/delta/range request APIs.",
    },
    FeatureDescriptor {
        bit: 14,
        flag: ECU_FEATURE_LSP_AUXILIARY_REQUESTS,
        name: "lsp_auxiliary_requests",
        description: "LSP auxiliary inlay hint / document link request APIs.",
    },
    FeatureDescriptor {
        bit: 15,
        flag: ECU_FEATURE_LSP_AUXILIARY_RESOLVE_REQUESTS,
        name: "lsp_auxiliary_resolve_requests",
        description: "LSP auxiliary inlay hint / document link resolve request APIs.",
    },
    FeatureDescriptor {
        bit: 16,
        flag: ECU_FEATURE_EDITOR_UI_STATE_EVENTS,
        name: "editor_ui_state_events",
        description: "Per-EditorUi unified state event stream.",
    },
    FeatureDescriptor {
        bit: 17,
        flag: ECU_FEATURE_MULTI_DOCUMENT_STATE_EVENTS,
        name: "multi_document_state_events",
        description: "Multi-document/project unified state event aggregation.",
    },
    FeatureDescriptor {
        bit: 18,
        flag: ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT,
        name: "workspace_outline_snapshot",
        description: "Multi-document/project workspace outline snapshot.",
    },
    FeatureDescriptor {
        bit: 19,
        flag: ECU_FEATURE_MULTI_DOCUMENT_TAB_DOCUMENT_URI,
        name: "multi_document_tab_document_uri",
        description: "Multi-document tab document URI metadata.",
    },
    FeatureDescriptor {
        bit: 20,
        flag: ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION,
        name: "multi_document_workspace_edit_transaction",
        description: "Multi-document WorkspaceEdit transaction preview/apply.",
    },
    FeatureDescriptor {
        bit: 21,
        flag: ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_EVENTS,
        name: "multi_document_workspace_edit_transaction_events",
        description: "Multi-document WorkspaceEdit transaction event stream.",
    },
    FeatureDescriptor {
        bit: 22,
        flag: ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS,
        name: "multi_document_workspace_roots",
        description: "Multi-document workspace root URI metadata.",
    },
    FeatureDescriptor {
        bit: 23,
        flag: ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_UNDO,
        name: "multi_document_workspace_edit_transaction_undo",
        description: "Multi-document WorkspaceEdit transaction undo.",
    },
    FeatureDescriptor {
        bit: 24,
        flag: ECU_FEATURE_MULTI_DOCUMENT_TAB_LANGUAGE_ID,
        name: "multi_document_tab_language_id",
        description: "Multi-document tab language id metadata.",
    },
    FeatureDescriptor {
        bit: 25,
        flag: ECU_FEATURE_JSON_COMMAND_ENVELOPE,
        name: "json_command_envelope",
        description: "JSON command dispatcher can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 26,
        flag: ECU_FEATURE_LSP_RESULT_ENVELOPE,
        name: "lsp_result_envelope",
        description: "LSP take-last result slots can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 27,
        flag: ECU_FEATURE_EVENT_STREAM_ENVELOPE,
        name: "event_stream_envelope",
        description: "EditorUi and multi-document event streams can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 28,
        flag: ECU_FEATURE_MULTI_DOCUMENT_SPECIAL_EVENT_STREAM_ENVELOPE,
        name: "multi_document_special_event_stream_envelope",
        description: "Multi-document workspace diagnostics and WorkspaceEdit event streams are available through structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 29,
        flag: ECU_FEATURE_WORKSPACE_EDIT_TRANSACTION_ENVELOPE,
        name: "workspace_edit_transaction_envelope",
        description: "Multi-document WorkspaceEdit transaction preview/apply/undo can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 30,
        flag: ECU_FEATURE_WORKSPACE_DIAGNOSTICS_ENVELOPE,
        name: "workspace_diagnostics_envelope",
        description: "Multi-document workspace diagnostics apply/snapshot/marker/previous-result-id APIs can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 31,
        flag: ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT_ENVELOPE,
        name: "workspace_outline_snapshot_envelope",
        description: "Multi-document workspace outline snapshots can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 32,
        flag: ECU_FEATURE_MULTI_DOCUMENT_SNAPSHOT_ENVELOPE,
        name: "multi_document_snapshot_envelope",
        description: "Multi-document tab/project snapshots can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 33,
        flag: ECU_FEATURE_MULTI_DOCUMENT_SEARCH_ENVELOPE,
        name: "multi_document_search_envelope",
        description: "Multi-document all-tabs search can return structured result envelopes.",
    },
    FeatureDescriptor {
        bit: 34,
        flag: ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS_CHANGE_ENVELOPE,
        name: "multi_document_workspace_roots_change_envelope",
        description: "Multi-document workspace roots changes can return structured result envelopes.",
    },
];

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

/// Return structured runtime/capability information as JSON.
///
/// Caller owns returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_runtime_info_json() -> *mut libc::c_char {
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
    make_c_string_ptr(
        json!({
            "kind": "editor-core-ui-ffi",
            "abi_version": ECU_ABI_VERSION,
            "version": env!("CARGO_PKG_VERSION"),
            "feature_flags": ECU_FEATURE_FLAGS,
            "features": features,
        })
        .to_string(),
    )
}
