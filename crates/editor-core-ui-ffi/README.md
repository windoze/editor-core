# editor-core-ui-ffi

C ABI bridge for `editor-core-ui`.

The public ABI surface is declared in `include/editor_core_ui_ffi.h`. SwiftPM imports the same
header through `swift/Sources/CEditorCoreUIFFI/include/editor_core_ui_ffi.h`, so new exported
functions must be added to the Rust `extern "C"` implementation and to the header in the same
change.

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
