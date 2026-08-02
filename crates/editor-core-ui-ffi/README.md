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
