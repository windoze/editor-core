# editor-core-ui-ffi

C ABI bridge for `editor-core-ui`.

The public ABI surface is declared in `include/editor_core_ui_ffi.h`. SwiftPM imports the same
header through `swift/Sources/CEditorCoreUIFFI/include/editor_core_ui_ffi.h`, so new exported
functions must be added to the Rust `extern "C"` implementation and to the header in the same
change.

## Runtime Capabilities

Hosts can either probe scalar ABI values directly:

```c
uint32_t editor_core_ui_ffi_abi_version(void);
uint64_t editor_core_ui_ffi_feature_flags(void);
```

or fetch a caller-owned one-call capability snapshot:

```c
char* editor_core_ui_ffi_runtime_info_json(void);
```

```json
{
  "kind": "editor-core-ui-ffi",
  "abi_version": 1,
  "version": "0.5.0",
  "feature_flags": 2251799813685247,
  "features": [
    { "bit": 0, "flag": 1, "name": "json_command_dispatch", "description": "..." }
  ]
}
```

Hosts should gate feature-specific calls before invoking them. The numeric feature mask is the
machine-readable contract; descriptor names in `runtime_info_json` are intended for diagnostics,
logs, and non-Swift bindings. New integrations should prefer the envelope APIs when their feature
bit is present and fall back to legacy raw JSON symbols only for compatibility. Unknown descriptor
names and unknown envelope status strings are forward-compatible and should not make a host reject
the runtime by default. Every returned runtime-info, envelope, legacy JSON, or allocated error
string must be freed exactly once with `editor_core_ui_ffi_string_free`.

Swift wrappers follow the same rule. Workspace file search/list, project file index, and workspace
file replacement raw JSON helpers that have envelope equivalents remain callable but are marked
deprecated; new Swift/App integrations should use the envelope methods and typed value helpers.
Workspace file list/search/replacement callers that need pagination or scan policy controls should
gate on `ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_SCAN_OPTIONS`.

## JSON Command Envelope

The legacy JSON command dispatcher remains available:

```c
char* editor_core_ui_ffi_editor_ui_execute_command_json(
    EditorUi* ui,
    const char* command_json_utf8
);
```

It returns command-result JSON on success and null on failure, with details in
`editor_core_ui_ffi_last_error_message()`. New hosts that want structured errors can use the
additive envelope variant:

```c
char* editor_core_ui_ffi_editor_ui_execute_command_envelope_json(
    EditorUi* ui,
    const char* command_json_utf8
);
```

The returned JSON is stable:

```json
{ "ok": true, "value": { "kind": "success" }, "error": null, "version": 1 }
```

or:

```json
{
  "ok": false,
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "command_json_utf8 is null" },
  "version": 1
}
```

Both strings are owned by the caller and must be freed with `editor_core_ui_ffi_string_free`.
Availability is advertised by `ECU_FEATURE_JSON_COMMAND_ENVELOPE`.

## EditorUi Configuration Controls

`EditorUi` exposes view-local configuration setters for host-controlled editor behavior. LSP
on-type formatting can be disabled without disabling text synchronization or the explicit
`editor_core_ui_ffi_editor_ui_lsp_format_on_type(...)` request API:

```c
int32_t editor_core_ui_ffi_editor_ui_set_lsp_on_type_formatting_enabled(
    EditorUi* ui,
    uint8_t enabled
);
```

## MultiDocument Workspace Roots Change Envelope

The legacy workspace roots change API remains available as a raw JSON string function:
`editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_json(...)`. Hosts that want a
single JSON result/error shape can use the additive envelope variant:

```c
char* editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* roots_json_utf8
);
```

Success:

```json
{
  "ok": true,
  "status": "success",
  "value": {
    "added": [{ "uri": "file:///project/Alpha", "name": "Alpha" }],
    "removed": []
  },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "roots_json_utf8 is null" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS_CHANGE_ENVELOPE`.

## MultiDocument Snapshot Envelope

The legacy multi-document snapshot API remains available as a raw JSON string function:
`editor_core_ui_ffi_multi_document_snapshot_json(...)`. Hosts that want a single JSON result/error
shape can use the additive envelope variant:

```c
char* editor_core_ui_ffi_multi_document_snapshot_envelope_json(
    MultiDocumentEditorUi* multi
);
```

Success:

```json
{
  "ok": true,
  "status": "success",
  "value": { "active_tab_id": null, "workspace_roots": [], "project_lsp_servers": [], "tabs": [] },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "multi is null" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_MULTI_DOCUMENT_SNAPSHOT_ENVELOPE`.

## MultiDocument Search Envelope

The legacy all-tabs search API remains available as a raw JSON string function:
`editor_core_ui_ffi_multi_document_search_all_tabs_json(...)`. Hosts that want a single JSON
result/error shape can use the additive envelope variant:

```c
char* editor_core_ui_ffi_multi_document_search_all_tabs_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* query_utf8,
    uint8_t case_sensitive,
    uint8_t whole_word,
    uint8_t regex
);
```

Success:

```json
{
  "ok": true,
  "status": "success",
  "value": { "results": [{ "tab_id": 1, "matches": [{ "start": 6, "end": 11 }] }] },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "query_utf8 is null" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_MULTI_DOCUMENT_SEARCH_ENVELOPE`.

## LSP Result Envelope

The legacy LSP take-last APIs remain available as status-code functions with `out_has_result` and
`out_result_json_utf8` out parameters. Hosts that want a single JSON result/error shape can use the
additive slot-based envelope variant:

```c
char* editor_core_ui_ffi_editor_ui_lsp_take_last_result_envelope_json(
    EditorUi* ui,
    const char* slot_utf8
);
```

`slot_utf8` uses the same stable slot names as the LSP result event stream, such as `hover`,
`definition`, `completion`, `code_action`, `semantic_tokens_full`, `document_symbols`,
`workspace_diagnostic`, or `type_hierarchy_subtypes`.

Empty result:

```json
{
  "ok": true,
  "slot": "hover",
  "status": "empty",
  "has_result": false,
  "value": null,
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "slot": "future_slot",
  "status": "error",
  "has_result": false,
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "unknown lsp result slot \"future_slot\"" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_LSP_RESULT_ENVELOPE`.

## LSP Status Envelope

The legacy status snapshot API remains available:

```c
int32_t editor_core_ui_ffi_editor_ui_lsp_status_json(
    EditorUi* ui,
    char** out_status_json_utf8
);
```

Hosts that want the stage-10 structured error model can call the envelope entry point:

```c
char* editor_core_ui_ffi_editor_ui_lsp_status_envelope_json(EditorUi* ui);
```

Success:

```json
{
  "ok": true,
  "status": "success",
  "value": {
    "availability": "disabled",
    "state": "disabled",
    "workspace_folders": []
  },
  "error": null,
  "version": 1
}
```

Failure:

```json
{
  "ok": false,
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "ui is null" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_LSP_STATUS_ENVELOPE`.

## LSP WorkspaceEdit Application Envelope

The legacy per-`EditorUi` WorkspaceEdit apply API remains available as a raw JSON string function:

```c
char* editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(
    EditorUi* ui,
    const char* workspace_edit_json_utf8,
    const char* document_uri_utf8
);
```

Hosts that want the stage-10 structured error model can call the additive envelope entry point:

```c
char* editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_envelope_json(
    EditorUi* ui,
    const char* workspace_edit_json_utf8,
    const char* document_uri_utf8
);
```

Success preserves the legacy apply summary under `value` and records the requested document URI:

```json
{
  "ok": true,
  "status": "success",
  "document_uri": "file:///main.rs",
  "value": {
    "applied": true,
    "applied_uri": "file:///main.rs",
    "applied_edit_count": 1,
    "skipped_uris": [],
    "documents": [
      { "uri": "file:///main.rs", "edit_count": 1, "has_overlapping_edits": false }
    ]
  },
  "error": null,
  "version": 1
}
```

Failure returns a structured error instead of a null pointer:

```json
{
  "ok": false,
  "status": "error",
  "document_uri": "file:///main.rs",
  "value": null,
  "error": { "code": "internal", "status": 4, "message": "failed to parse WorkspaceEdit JSON: ..." },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_LSP_WORKSPACE_EDIT_APPLICATION_ENVELOPE`.

## LSP Derived-State Application Envelopes

The legacy per-`EditorUi` LSP derived-state apply APIs remain available as status-code functions:

```c
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(EditorUi* ui, const char* publish_diagnostics_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(EditorUi* ui, const char* inlay_hints_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(EditorUi* ui, const char* code_lens_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(EditorUi* ui, const char* document_links_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(EditorUi* ui, const char* document_highlights_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_json(EditorUi* ui, const char* document_symbols_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json(EditorUi* ui, const char* folding_ranges_result_json_utf8);
```

Hosts that want the stage-10 structured error model can call the additive envelope variants:

```c
char* editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_envelope_json(EditorUi* ui, const char* publish_diagnostics_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_envelope_json(EditorUi* ui, const char* inlay_hints_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_envelope_json(EditorUi* ui, const char* code_lens_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_document_links_envelope_json(EditorUi* ui, const char* document_links_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_envelope_json(EditorUi* ui, const char* document_highlights_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_envelope_json(EditorUi* ui, const char* document_symbols_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_envelope_json(EditorUi* ui, const char* folding_ranges_result_json_utf8);
```

Success records the applied operation name and a stable minimal value:

```json
{
  "ok": true,
  "operation": "apply_inlay_hints",
  "status": "success",
  "value": { "applied": true },
  "error": null,
  "version": 1
}
```

Failure returns a structured error instead of requiring a separate last-error read:

```json
{
  "ok": false,
  "operation": "apply_inlay_hints",
  "status": "error",
  "value": null,
  "error": { "code": "internal", "status": 7, "message": "failed to parse inlay hints: ..." },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_LSP_DERIVED_STATE_APPLICATION_ENVELOPE`.

## LSP Semantic Tokens Application Envelope

The legacy per-`EditorUi` semantic tokens raw-buffer apply API remains available as a status-code
function:

```c
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
    EditorUi* ui,
    const uint32_t* data,
    uint32_t data_len
);
```

Hosts that want the stage-10 structured error model can call the additive envelope variant:

```c
char* editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens_envelope_json(
    EditorUi* ui,
    const uint32_t* data,
    uint32_t data_len
);
```

Success records the stable operation name and the accepted `uint32_t` count:

```json
{
  "ok": true,
  "operation": "apply_semantic_tokens",
  "status": "success",
  "value": { "applied": true, "data_len": 5 },
  "error": null,
  "version": 1
}
```

Failure returns a structured error instead of requiring a separate last-error read:

```json
{
  "ok": false,
  "operation": "apply_semantic_tokens",
  "status": "error",
  "value": null,
  "error": { "code": "internal", "status": 7, "message": "Semantic tokens data length must be a multiple of 5 (got 1)" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_LSP_SEMANTIC_TOKENS_APPLICATION_ENVELOPE`.

## Event Stream Envelope

The legacy event stream APIs remain available as raw JSON string functions, for example
`editor_core_ui_ffi_editor_ui_state_events_json(...)` and
`editor_core_ui_ffi_multi_document_lsp_request_events_json(...)`. Hosts that want a single
JSON result/error shape can use the additive stream-based envelope variants:

```c
char* editor_core_ui_ffi_editor_ui_event_stream_envelope_json(
    EditorUi* ui,
    const char* stream_utf8,
    uint64_t after_sequence
);

char* editor_core_ui_ffi_multi_document_event_stream_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* stream_utf8,
    uint64_t after_sequence
);
```

`stream_utf8` currently accepts `state_events`, `lsp_result_events`, and `lsp_request_events` for
both `EditorUi` and `MultiDocumentEditorUi`. The multi-document variant also accepts
`workspace_diagnostics_events` and `workspace_edit_transaction_events`.

Success:

```json
{
  "ok": true,
  "owner": "editor_ui",
  "stream": "state_events",
  "status": "success",
  "after_sequence": 0,
  "value": { "latest_sequence": 0, "events": [] },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "owner": "editor_ui",
  "stream": "future_events",
  "status": "error",
  "after_sequence": 7,
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "unknown editor_ui event stream \"future_events\"" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_EVENT_STREAM_ENVELOPE`. The multi-document-only
`workspace_diagnostics_events` and `workspace_edit_transaction_events` streams are additionally
advertised by `ECU_FEATURE_MULTI_DOCUMENT_SPECIAL_EVENT_STREAM_ENVELOPE`.

## Workspace Diagnostics Envelope

The legacy workspace diagnostics APIs remain available as raw JSON string functions:
`editor_core_ui_ffi_multi_document_apply_workspace_diagnostics_json(...)`,
`editor_core_ui_ffi_multi_document_workspace_diagnostics_snapshot_json(...)`,
`editor_core_ui_ffi_multi_document_workspace_diagnostic_markers_json(...)`, and
`editor_core_ui_ffi_multi_document_workspace_diagnostics_previous_result_ids_json(...)`. Hosts that
want a single JSON result/error shape can use the additive operation-based envelope variant:

```c
char* editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* operation_utf8,
    const char* result_json_utf8
);
```

`operation_utf8` accepts `apply`, `snapshot`, `markers`, or `previous_result_ids`. `apply` requires
`result_json_utf8`; read-only operations ignore it and may be called with null.

Success:

```json
{
  "ok": true,
  "operation": "apply",
  "status": "success",
  "value": { "documents": [], "diagnostics": [] },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "operation": "future_operation",
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "unknown workspace diagnostics operation \"future_operation\"" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_WORKSPACE_DIAGNOSTICS_ENVELOPE`.

## Workspace Outline Snapshot Envelope

The legacy workspace outline API remains available as a raw JSON string function:
`editor_core_ui_ffi_multi_document_workspace_outline_snapshot_json(...)`. Hosts that want a single
JSON result/error shape can use the additive envelope variant:

```c
char* editor_core_ui_ffi_multi_document_workspace_outline_snapshot_envelope_json(
    MultiDocumentEditorUi* multi
);
```

Success:

```json
{
  "ok": true,
  "status": "success",
  "value": { "documents": [] },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "multi is null" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT_ENVELOPE`.

## WorkspaceEdit Transaction Envelope

The legacy WorkspaceEdit transaction APIs remain available as raw JSON string functions:
`editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(...)`,
`editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(...)`, and
`editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json(...)`. When
`ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_REDO` is present, hosts may also call
`editor_core_ui_ffi_multi_document_redo_last_workspace_edit_transaction_json(...)`; redo returns the
same result shape as apply with `mode: "redo"` and reuses the normal core WorkspaceEdit conflict
checks. Hosts that want a single JSON result/error shape can use the additive operation-based
envelope variant:

```c
char* editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* operation_utf8,
    const char* workspace_edit_json_utf8
);
```

`operation_utf8` accepts `preview`, `apply`, `undo`, or `redo`. `preview` and `apply` require
`workspace_edit_json_utf8`; `undo` and `redo` ignore it and may be called with null.

WorkspaceEdit transaction results may include `conflicts[]`. Each conflict keeps the stable
`uri`/`kind`/`reason`/`operation`/`message` fields and also includes compatibility-extensible
machine-readable impact fields: `severity`, `apply_impact`, and `resolution`. `apply_impact` is
`skips_change` for partial conflict skips and `blocks_atomic_apply` when atomic apply cannot proceed
until the conflict is resolved. Hosts should ignore unknown conflict fields and tolerate unknown
future enum strings.

Success:

```json
{
  "ok": true,
  "operation": "preview",
  "status": "success",
  "value": { "mode": "preview", "applied": false },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "operation": "future_operation",
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "unknown workspace edit transaction operation \"future_operation\"" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_WORKSPACE_EDIT_TRANSACTION_ENVELOPE`.

## LSP Workspace Lifecycle

The LSP lifecycle APIs are JSON control-plane functions. Workspace folder changes are exposed as:

```c
int32_t editor_core_ui_ffi_editor_ui_lsp_did_change_workspace_folders_json(
    EditorUi* ui,
    const char* added_json_utf8,
    const char* removed_json_utf8
);
```

`added_json_utf8` and `removed_json_utf8` must be UTF-8 JSON arrays of LSP `WorkspaceFolder`
objects:

```json
[{ "uri": "file:///path/to/workspace", "name": "workspace" }]
```

The call sends `workspace/didChangeWorkspaceFolders` for the active UI-owned LSP session and keeps
the client-side `workspace/workspaceFolders` response list synchronized with the accepted change.

## LSP Document Lifecycle

Document open, change, save, and close notifications are exposed as string-based control-plane
functions:

```c
int32_t editor_core_ui_ffi_editor_ui_lsp_did_open_document(
    EditorUi* ui,
    const char* document_uri_utf8,
    const char* language_id_utf8,
    int32_t version,
    const char* text_utf8
);

int32_t editor_core_ui_ffi_editor_ui_lsp_did_change_document(
    EditorUi* ui,
    const char* document_uri_utf8,
    const char* text_utf8
);

int32_t editor_core_ui_ffi_editor_ui_lsp_did_save_document(
    EditorUi* ui,
    const char* document_uri_utf8,
    const char* text_utf8
);

int32_t editor_core_ui_ffi_editor_ui_lsp_did_close_document(
    EditorUi* ui,
    const char* document_uri_utf8
);
```

`document_uri_utf8` must be a UTF-8 LSP document URI. didOpen additionally requires
`language_id_utf8`, a document `version`, and the initial `text_utf8`; it also tracks the document
inside the active session. didChange sends `text_utf8` as a full-document replacement for a tracked
document; Rust owns the per-document text mirror used to compute the LSP range and next version.
didSave `text_utf8` may be null for callers that do not include the optional saved document text.
These calls target the active UI-owned LSP session and return an error status when LSP is not
enabled.

## Multi-document Tab Metadata

The multi-document model stores document URI and language id metadata per tab. The snapshot JSON
includes both values as `document_uri` and `language_id`, and callers can update them independently:

```c
int32_t editor_core_ui_ffi_multi_document_set_tab_document_uri(
    MultiDocumentEditorUi* multi,
    uint64_t tab_id,
    const char* document_uri_utf8
);

int32_t editor_core_ui_ffi_multi_document_set_tab_language_id(
    MultiDocumentEditorUi* multi,
    uint64_t tab_id,
    const char* language_id_utf8
);
```

Passing null clears the corresponding value. Language ids are trimmed and empty values are stored
as null. This metadata is used by project/workspace features to reason about open documents without
maintaining a parallel host-side tab identity model.

## Multi-document Workspace Roots

The multi-document model owns workspace root URI metadata for project-level features. Existing
callers may continue replacing roots without a return value:

```c
int32_t editor_core_ui_ffi_multi_document_set_workspace_roots_json(
    MultiDocumentEditorUi* multi,
    const char* roots_json_utf8
);
```

Hosts that need to notify LSP sessions can use the diff-returning variant:

```c
char* editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_json(
    MultiDocumentEditorUi* multi,
    const char* roots_json_utf8
);
```

`roots_json_utf8` is a JSON array of root URI strings. The returned JSON is:

```json
{
  "added": [{ "uri": "file:///new-root", "name": "new-root" }],
  "removed": [{ "uri": "file:///old-root", "name": "old-root" }]
}
```

The returned string is owned by the caller and must be freed with `editor_core_ui_ffi_string_free`.

## Multi-document Recent Files

The multi-document model also owns a bounded recent file URI list for workspace/session features:

```c
int32_t editor_core_ui_ffi_multi_document_remember_recent_file_uri(
    MultiDocumentEditorUi* multi,
    const char* uri_utf8
);

int32_t editor_core_ui_ffi_multi_document_restore_recent_files_json(
    MultiDocumentEditorUi* multi,
    const char* uris_json_utf8
);

int32_t editor_core_ui_ffi_multi_document_clear_recent_files(MultiDocumentEditorUi* multi);

char* editor_core_ui_ffi_multi_document_recent_files_json(MultiDocumentEditorUi* multi);
```

`remember_recent_file_uri` trims URI strings, ignores empty values, moves duplicates to the front,
and keeps a fixed-size most-recent-first list. `restore_recent_files_json` accepts a JSON array of
URI strings in snapshot order and applies the same normalization. `recent_files_json` returns an
array of objects such as `{ "uri": "file:///project/src/lib.rs" }`, and
`editor_core_ui_ffi_multi_document_snapshot_json` includes the same array under `recent_files`.
Changing workspace roots clears the recent file list so hosts do not carry stale project-local
files across workspaces. Availability is advertised by `ECU_FEATURE_MULTI_DOCUMENT_RECENT_FILES`.

The same model can also own a bounded recent project/workspace root URI list:

```c
int32_t editor_core_ui_ffi_multi_document_remember_recent_project_uri(
    MultiDocumentEditorUi* multi,
    const char* uri_utf8
);

int32_t editor_core_ui_ffi_multi_document_restore_recent_projects_json(
    MultiDocumentEditorUi* multi,
    const char* uris_json_utf8
);

int32_t editor_core_ui_ffi_multi_document_clear_recent_projects(MultiDocumentEditorUi* multi);

char* editor_core_ui_ffi_multi_document_recent_projects_json(MultiDocumentEditorUi* multi);
```

Recent projects use the same trim, ignore-empty, de-duplicate, fixed-size MRU behavior as recent
files, but are not cleared when workspace roots change. `recent_projects_json` returns an array of
objects such as `{ "uri": "file:///project" }`, and
`editor_core_ui_ffi_multi_document_snapshot_json` includes the same array under `recent_projects`.
Availability is advertised by `ECU_FEATURE_MULTI_DOCUMENT_RECENT_PROJECTS`.

## Multi-document Workspace File List

Workspace file listing uses the multi-document workspace roots as its trust boundary and enumerates
local `file://` roots only. It is intended for Quick Open and project file panels that need file
names rather than content matches:

```c
char* editor_core_ui_ffi_multi_document_list_workspace_files_json(
    MultiDocumentEditorUi* multi,
    const char* include_globs_json_utf8,
    const char* exclude_globs_json_utf8,
    uint32_t max_results
);

char* editor_core_ui_ffi_multi_document_list_workspace_files_with_options_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* scan_options_json_utf8
);
```

`include_globs_json_utf8` and `exclude_globs_json_utf8` use the same JSON string-array format and
glob semantics as workspace file search. `max_results == 0` selects the default bounded limit.
Hidden paths, `target`, and `.build` are skipped. The returned JSON is `{ "files": [...], "scan":
{ ... } }`; each entry contains `uri`, `path`, and `relative_path`, sorted by relative path for
stable UI display. The legacy raw JSON/list envelope accepts include/exclude/max arguments; the
options-envelope variant accepts `scan_options_json_utf8`, a JSON object with `include_globs`,
`exclude_globs`, `max_results`, `offset`, `max_file_size_bytes`, `skip_binary`,
`respect_ignore_files`, `cancelled`, and `cancel_after_files`. Availability is advertised by
`ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_LIST`; explicit scan options are advertised by
`ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_SCAN_OPTIONS`.

The `scan` summary reports `offset`, `max_results`, `next_offset`, `truncated`, `cancelled`,
`visited_files`, `matched_results`, `returned_results`, `skipped_large_files`,
`skipped_binary_files`, `skipped_unreadable_files`, and `ignore_files_enabled`. File search and
replacement use the same scan summary shape.

Hosts that want a core-owned project file cache can refresh and query the project file index:

```c
char* editor_core_ui_ffi_multi_document_refresh_project_file_index_json(
    MultiDocumentEditorUi* multi,
    uint32_t max_results
);

char* editor_core_ui_ffi_multi_document_project_file_index_snapshot_json(
    MultiDocumentEditorUi* multi
);

int32_t editor_core_ui_ffi_multi_document_clear_project_file_index(MultiDocumentEditorUi* multi);

char* editor_core_ui_ffi_multi_document_query_project_file_index_json(
    MultiDocumentEditorUi* multi,
    const char* query_utf8,
    uint32_t max_results
);
```

Refreshing the index uses the same root trust boundary, default skip rules, stable sorting, and
`max_results == 0` default as the workspace file list. The returned snapshot has
`workspace_roots`, `files`, `is_built`, and `max_results` fields. Workspace root changes clear the
cached snapshot so hosts do not reuse a previous project's file list.
`query_project_file_index_json` queries the last refreshed snapshot with case-insensitive fuzzy
subsequence matching on `relative_path` and returns `{ "results": [...] }` entries with `uri`,
`path`, `relative_path`, and `score`, ordered by descending score with stable path tie-breaks.
Availability is advertised by `ECU_FEATURE_MULTI_DOCUMENT_PROJECT_FILE_INDEX`; fuzzy queries are
advertised separately by `ECU_FEATURE_MULTI_DOCUMENT_PROJECT_FILE_INDEX_QUERY`.

## Multi-document Workspace File Search

Workspace file search uses the multi-document workspace roots as its trust boundary and searches
local `file://` roots only. The raw JSON API returns `{ "results": [...] }`; the envelope API uses
the same `ok/status/value/error/version` shape as other multi-document search envelopes.

```c
char* editor_core_ui_ffi_multi_document_search_workspace_files_json(
    MultiDocumentEditorUi* multi,
    const char* query_utf8,
    const char* include_globs_json_utf8,
    const char* exclude_globs_json_utf8,
    uint8_t case_sensitive,
    uint8_t whole_word,
    uint8_t regex,
    uint32_t max_results
);

char* editor_core_ui_ffi_multi_document_search_workspace_files_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* query_utf8,
    const char* include_globs_json_utf8,
    const char* exclude_globs_json_utf8,
    uint8_t case_sensitive,
    uint8_t whole_word,
    uint8_t regex,
    uint32_t max_results
);

char* editor_core_ui_ffi_multi_document_search_workspace_files_with_options_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* query_utf8,
    const char* scan_options_json_utf8,
    uint8_t case_sensitive,
    uint8_t whole_word,
    uint8_t regex
);
```

`include_globs_json_utf8` and `exclude_globs_json_utf8` are JSON arrays of string patterns; null or
an empty string means no patterns. Patterns use `/` separators and support `*`, `?`, and `**`.
Patterns without `/` match path components by basename. `max_results == 0` selects the default
bounded limit. The options-envelope variant uses the same `scan_options_json_utf8` schema as
workspace file listing and applies it before reading file content. Text search skips files larger
than `max_file_size_bytes`, binary files with NUL bytes, and invalid UTF-8 files by default.

Each result contains `uri`, `path`, `relative_path`, `line1`, `column1`, `line_text`, `match_start`,
and `match_end`. `line1` and `column1` are 1-based for UI navigation. `match_start` and `match_end`
are 0-based line-local character offsets for preview highlighting. Envelope values include both
`results` and `scan`.

## Multi-document Workspace File Replacement WorkspaceEdit

Hosts can ask the multi-document model to generate a WorkspaceEdit payload for replacing matches
found in local workspace files:

```c
char* editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_json(
    MultiDocumentEditorUi* multi,
    const char* query_utf8,
    const char* replacement_utf8,
    const char* include_globs_json_utf8,
    const char* exclude_globs_json_utf8,
    const char* apply_mode_utf8,
    uint8_t case_sensitive,
    uint8_t whole_word,
    uint8_t regex,
    uint32_t max_results
);

char* editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_with_options_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* query_utf8,
    const char* replacement_utf8,
    const char* scan_options_json_utf8,
    const char* apply_mode_utf8,
    uint8_t case_sensitive,
    uint8_t whole_word,
    uint8_t regex
);
```

`include_globs_json_utf8` and `exclude_globs_json_utf8` use the same JSON string-array format and
glob semantics as workspace file search. `apply_mode_utf8` accepts `partial` or `atomic`; null or an
empty string defaults to `atomic`. `max_results == 0` selects the default bounded limit. The
options-envelope variant uses `scan_options_json_utf8` for pagination, ignore handling, large-file
and binary-file skipping, and cancellation budgets.

The returned JSON is a transaction-compatible envelope:

```json
{
  "workspaceEdit": {
    "documentChanges": [
      {
        "textDocument": { "uri": "file:///project/src/lib.rs" },
        "edits": [
          {
            "range": {
              "start": { "line": 0, "character": 3 },
              "end": { "line": 0, "character": 8 }
            },
            "newText": "replacement"
          }
        ]
      }
    ]
  },
  "applyMode": "atomic",
  "scan": {
    "offset": 0,
    "max_results": 2000,
    "next_offset": null,
    "truncated": false,
    "cancelled": false
  }
}
```

Ranges are LSP UTF-16 positions. When `regex != 0`, `replacement_utf8` uses Rust regex replacement
expansion, so captures such as `$1` are expanded for each generated edit. The returned payload is
not applied automatically; hosts should pass it to the existing multi-document WorkspaceEdit
preview/apply APIs and can use the existing transaction undo/redo APIs after apply. Availability is
advertised by `ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_REPLACEMENT`.

## Multi-document Project LSP Servers

The multi-document model also owns a project-level LSP server configuration list. This is a
control-plane store for launch metadata and does not start or stop servers by itself:

```c
int32_t editor_core_ui_ffi_multi_document_set_project_lsp_servers_json(
    MultiDocumentEditorUi* multi,
    const char* configs_json_utf8
);

char* editor_core_ui_ffi_multi_document_project_lsp_servers_json(MultiDocumentEditorUi* multi);

char* editor_core_ui_ffi_multi_document_project_lsp_servers_envelope_json(
    MultiDocumentEditorUi* multi
);
```

`configs_json_utf8` is a JSON array of objects with `key`, `command`, optional `args`,
`language_id`, optional `workspace_roots`, and optional `auto_start`. Rust normalizes keys,
commands, args, language ids, and workspace roots, and the returned JSON array is ordered by the
normalized key. `editor_core_ui_ffi_multi_document_snapshot_json` includes the same list under
`project_lsp_servers`.

Hosts that want a single JSON result/error shape can use the additive envelope variant:

```json
{
  "ok": true,
  "status": "success",
  "value": [
    {
      "key": "rust",
      "command": "/bin/rust-analyzer",
      "args": ["--stdio"],
      "language_id": "rust",
      "workspace_roots": ["file:///workspace"],
      "auto_start": true
    }
  ],
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "status": "error",
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "multi is null" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_SERVERS_ENVELOPE`.

## Multi-document Project LSP Lifecycle Envelope

Legacy project LSP lifecycle queries remain available as raw JSON string functions:
`editor_core_ui_ffi_multi_document_project_lsp_start_plan_json(...)`,
`editor_core_ui_ffi_multi_document_project_lsp_stop_plan_json(...)`,
`editor_core_ui_ffi_multi_document_project_lsp_restart_plan_json(...)`, and
`editor_core_ui_ffi_multi_document_project_lsp_lifecycle_events_json(...)`. Hosts that want a
single JSON result/error shape can use the additive operation-based envelope variant:

```c
char* editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* operation_utf8,
    uint64_t after_sequence
);
```

`operation_utf8` must be one of `start_plan`, `stop_plan`, `restart_plan`, or
`lifecycle_events`. `after_sequence` is used only by `lifecycle_events`; the plan operations ignore
it. Success envelopes preserve the legacy operation payload under `value`:

```json
{
  "ok": true,
  "operation": "start_plan",
  "status": "success",
  "value": [
    {
      "tab_id": 1,
      "document_uri": "file:///project/main.rs",
      "language_id": "rust",
      "server_key": "rust",
      "command": "/bin/rust-analyzer",
      "args": ["--stdio"],
      "workspace_roots": ["file:///project"],
      "trigger": "auto_start"
    }
  ],
  "error": null,
  "version": 1
}
```

Lifecycle event snapshots return the legacy cursor payload:

```json
{
  "ok": true,
  "operation": "lifecycle_events",
  "status": "success",
  "value": { "latest_sequence": 7, "events": [] },
  "error": null,
  "version": 1
}
```

Error:

```json
{
  "ok": false,
  "operation": "future_operation",
  "status": "error",
  "value": null,
  "error": {
    "code": "invalid_argument",
    "status": 1,
    "message": "unknown project LSP lifecycle operation \"future_operation\""
  },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_LIFECYCLE_ENVELOPE`.

## EditorUi Derived Snapshot Envelope

The legacy per-editor derived-state snapshot APIs remain available:

```c
char* editor_core_ui_ffi_editor_ui_diagnostics_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_decorations_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_document_symbols_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_folding_regions_json(EditorUi* ui);
char* editor_core_ui_ffi_editor_ui_style_intervals_json(
    EditorUi* ui,
    uint32_t start,
    uint32_t end
);
```

Hosts that want the stage-10 structured error model can call the envelope entry point:

```c
char* editor_core_ui_ffi_editor_ui_derived_snapshot_envelope_json(
    EditorUi* ui,
    const char* snapshot_utf8,
    uint32_t start,
    uint32_t end
);
```

`snapshot_utf8` accepts `diagnostics`, `decorations`, `document_symbols`,
`folding_regions`, and `style_intervals`. `start` / `end` are used by
`style_intervals` and ignored by the other snapshot names.

Success:

```json
{
  "ok": true,
  "snapshot": "diagnostics",
  "range": { "start": 0, "end": 0 },
  "status": "success",
  "value": { "diagnostics": [] },
  "error": null,
  "version": 1
}
```

Failure:

```json
{
  "ok": false,
  "snapshot": "future_snapshot",
  "range": { "start": 0, "end": 0 },
  "status": "error",
  "value": null,
  "error": {
    "code": "invalid_argument",
    "status": 1,
    "message": "unknown derived snapshot \"future_snapshot\""
  },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_EDITOR_UI_DERIVED_SNAPSHOT_ENVELOPE`.

## EditorUi Minimap Envelope

The legacy per-editor minimap snapshot API remains available as a raw JSON string function:

```c
char* editor_core_ui_ffi_editor_ui_minimap_json(
    EditorUi* ui,
    uint32_t start_visual_row,
    uint32_t count
);
```

Hosts that want the stage-10 structured error model can call the envelope entry point:

```c
char* editor_core_ui_ffi_editor_ui_minimap_envelope_json(
    EditorUi* ui,
    uint32_t start_visual_row,
    uint32_t count
);
```

Success:

```json
{
  "ok": true,
  "status": "success",
  "start_visual_row": 0,
  "count": 20,
  "value": {
    "start_visual_row": 0,
    "count": 20,
    "actual_line_count": 3,
    "lines": []
  },
  "error": null,
  "version": 1
}
```

Failure:

```json
{
  "ok": false,
  "status": "error",
  "start_visual_row": 0,
  "count": 20,
  "value": null,
  "error": { "code": "invalid_argument", "status": 1, "message": "ui is null" },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_EDITOR_UI_MINIMAP_ENVELOPE`.

## EditorUi View-Point Payload Envelope

The legacy view-point hit-test APIs for document links, inlay hints, and code lenses remain
available as status-code/out-pointer functions. Hosts that want the stage-10 structured error model
can call the generic envelope entry point:

```c
char* editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(
    EditorUi* ui,
    const char* kind_utf8,
    float x_px,
    float y_px
);
```

`kind_utf8` must be one of `document_link`, `inlay_hint`, or `code_lens`.

Success with a hit:

```json
{
  "ok": true,
  "kind": "document_link",
  "status": "success",
  "x_px": 10.0,
  "y_px": 20.0,
  "value": { "target": "https://example.com" },
  "error": null,
  "version": 1
}
```

Success without a hit:

```json
{
  "ok": true,
  "kind": "document_link",
  "status": "empty",
  "x_px": 10.0,
  "y_px": 20.0,
  "value": null,
  "error": null,
  "version": 1
}
```

Failure:

```json
{
  "ok": false,
  "kind": "unknown",
  "status": "error",
  "x_px": 10.0,
  "y_px": 20.0,
  "value": null,
  "error": {
    "code": "invalid_argument",
    "status": 1,
    "message": "unknown view point payload kind \"unknown\""
  },
  "version": 1
}
```

The returned string is owned by the caller and must be freed with
`editor_core_ui_ffi_string_free`. Availability is advertised by
`ECU_FEATURE_EDITOR_UI_VIEW_POINT_PAYLOAD_ENVELOPE`.
