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
  "feature_flags": 67108863,
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
```

`configs_json_utf8` is a JSON array of objects with `key`, `command`, optional `args`,
`language_id`, optional `workspace_roots`, and optional `auto_start`. Rust normalizes keys,
commands, args, language ids, and workspace roots, and the returned JSON array is ordered by the
normalized key. `editor_core_ui_ffi_multi_document_snapshot_json` includes the same list under
`project_lsp_servers`.
