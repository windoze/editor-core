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
  "feature_flags": 274877906943,
  "features": [
    { "bit": 0, "flag": 1, "name": "json_command_dispatch", "description": "..." }
  ]
}
```

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
`editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json(...)`. Hosts that want
a single JSON result/error shape can use the additive operation-based envelope variant:

```c
char* editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(
    MultiDocumentEditorUi* multi,
    const char* operation_utf8,
    const char* workspace_edit_json_utf8
);
```

`operation_utf8` accepts `preview`, `apply`, or `undo`. `preview` and `apply` require
`workspace_edit_json_utf8`; `undo` ignores it and may be called with null.

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
