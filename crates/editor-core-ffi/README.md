# editor-core-ffi

`editor-core-ffi` exposes a C ABI for:

- `editor-core` (state/commands/workspace/snapshots)
- `editor-core-lsp` (URI helpers, UTF-16 conversion, text edits, completion, semantic tokens, highlight/decorations/symbol conversions)
- `editor-core-sublime` (`.sublime-syntax` processor lifecycle + apply/process)
- `editor-core-treesitter` (Tree-sitter processor lifecycle + apply/process)

## ABI Layers

`editor-core-ffi` now exposes two interoperable layers:

1. Typed/binary ABI v1 for hot paths:
  - status-code return (`EcfStatus`)
  - UTF-8 byte input for text insertion
  - binary viewport blobs (`EcfViewportBlobHeader` + line/cell tables)
2. JSON control-plane APIs (legacy + still supported):
  - rich command bridge
  - LSP/Sublime/Tree-sitter conversion helpers
  - debug/introspection surfaces

This keeps per-keystroke/render paths fast while preserving flexible integration APIs.

## Ownership and Errors

- Handles are opaque pointers (`EcfEditorState`, `EcfWorkspace`, ...).
- Returned strings are owned by Rust and must be freed with:

```c
void editor_core_ffi_string_free(char* ptr);
```

- On failure:
  - typed ABI returns non-zero `EcfStatus`
  - legacy JSON APIs return `NULL` / `false` / `0`
  - JSON command envelope APIs return an allocated `{ "ok": false, ... }` JSON string
- In all cases, thread-local last error is retrievable via:

```c
char* editor_core_ffi_last_error_message(void);
```

## Typed ABI v1 (Hot Path)

Version:

```c
uint32_t editor_core_ffi_abi_version(void); /* currently 1 */
uint64_t editor_core_ffi_feature_flags(void);
char* editor_core_ffi_runtime_info_json(void);
```

The feature bitmask is append-only for the current pre-v1 ABI line. Important coarse-grained bits
include:

- `ECF_FEATURE_JSON_COMMAND_DISPATCH`
- `ECF_FEATURE_TYPED_HOT_PATH`
- `ECF_FEATURE_WORKSPACE_TYPED_API`
- `ECF_FEATURE_VIEWPORT_BLOB`
- `ECF_FEATURE_PROCESSING_EDIT_JSON`
- `ECF_FEATURE_LSP_HELPERS`
- `ECF_FEATURE_SUBLIME_PROCESSOR`
- `ECF_FEATURE_TREESITTER_PROCESSOR`
- `ECF_FEATURE_JSON_COMMAND_ENVELOPE`
- `ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE`
- `ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE`
- `ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE`
- `ECF_FEATURE_WORKSPACE_QUERY_ENVELOPE`

`editor_core_ffi_runtime_info_json()` returns a caller-owned one-call capability snapshot for
C/non-Swift hosts:

```json
{
  "kind": "editor-core-ffi",
  "abi_version": 1,
  "version": "0.5.0",
  "feature_flags": 8191,
  "features": [
    { "bit": 0, "flag": 1, "name": "json_command_dispatch", "description": "..." }
  ]
}
```

Core hot-path examples:

```c
int32_t editor_core_ffi_editor_insert_text_utf8(EcfEditorState* s, const uint8_t* bytes, uint32_t len);
int32_t editor_core_ffi_editor_move_to(EcfEditorState* s, uint32_t line, uint32_t column);
int32_t editor_core_ffi_editor_backspace(EcfEditorState* s);
```

Workspace typed helpers (beyond the per-keystroke hot path):

```c
int32_t editor_core_ffi_workspace_open_buffer_typed(
    EcfWorkspace* w,
    const char* uri,  /* nullable */
    const char* text,
    size_t viewport_width,
    EcfOpenBufferResult* out_result);

int32_t editor_core_ffi_workspace_get_info(
    const EcfWorkspace* w,
    EcfWorkspaceInfo* out_info);

int32_t editor_core_ffi_workspace_get_viewport_state(
    EcfWorkspace* w,
    uint64_t view_id,
    EcfWorkspaceViewportState* out_state);
```

Binary viewport snapshot (two-call pattern):

```c
uint32_t len = 0;
int32_t st = editor_core_ffi_editor_get_viewport_blob(s, 0, 120, NULL, 0, &len);
/* st == ECF_ERR_BUFFER_TOO_SMALL, len is required size */
uint8_t* buf = malloc(len);
st = editor_core_ffi_editor_get_viewport_blob(s, 0, 120, buf, len, &len);
/* st == ECF_OK */
```

Blob layout is documented in [`include/editor_core_ffi.h`](include/editor_core_ffi.h).

## JSON Command Bridge

Commands use tagged JSON:

```json
{
  "kind": "edit",
  "op": "insert_text",
  "text": "hello"
}
```

```json
{
  "kind": "cursor",
  "op": "move_to",
  "line": 10,
  "column": 4
}
```

```json
{
  "kind": "view",
  "op": "set_wrap_mode",
  "mode": "word"
}
```

Auto-indent / indentation config:

```json
{
  "kind": "view",
  "op": "set_indentation_config",
  "config": {
    "style": { "kind": "spaces", "width": 4 },
    "indent_triggers": ["{", "[", "(", ":"],
    "outdent_triggers": ["}", "]", ")"]
  }
}
```

```json
{
  "kind": "style",
  "op": "fold",
  "start_line": 10,
  "end_line": 20
}
```

Legacy command bridge functions return the raw command result JSON on success and `NULL` on
failure:

```c
char* editor_core_ffi_editor_state_execute_json(EcfEditorState* state, const char* command_json);
char* editor_core_ffi_workspace_execute_json(EcfWorkspace* workspace, uint64_t view_id, const char* command_json);
```

Envelope command bridge functions keep the legacy entry points intact while returning a stable
success/error wrapper:

```c
char* editor_core_ffi_editor_state_execute_envelope_json(EcfEditorState* state, const char* command_json);
char* editor_core_ffi_workspace_execute_envelope_json(EcfWorkspace* workspace, uint64_t view_id, const char* command_json);
```

```json
{ "ok": true, "value": { "kind": "success" }, "error": null, "version": 1 }
```

```json
{
  "ok": false,
  "value": null,
  "error": {
    "code": "command_failed",
    "status": 6,
    "message": "command execution failed: ..."
  },
  "version": 1
}
```

## Editor-State Derived Snapshot Envelopes

Legacy headless editor-state derived snapshot helpers keep returning raw JSON on success and
`NULL` on failure. Hosts that need non-null structured success/error results can use the envelope
variant guarded by `ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE`:

```c
char* editor_core_ffi_editor_state_derived_snapshot_envelope_json(
    const EcfEditorState* state,
    const char* snapshot_utf8);
```

`snapshot_utf8` accepts:

- `document_symbols`
- `diagnostics`
- `decorations`

Success envelopes preserve the legacy payload under `value` and include the selected snapshot name:

```json
{
  "ok": true,
  "status": "success",
  "snapshot": "diagnostics",
  "value": { "diagnostics": [] },
  "error": null,
  "version": 1
}
```

Failure envelopes report a structured `EcfStatus` and keep the requested snapshot when it is known:

```json
{
  "ok": false,
  "status": "error",
  "snapshot": "unknown",
  "value": null,
  "error": {
    "code": "invalid_argument",
    "status": 1,
    "message": "unknown editor state derived snapshot \"unknown\""
  },
  "version": 1
}
```

## Rendering Snapshot Envelopes

Legacy headless rendering snapshot helpers keep returning raw JSON on success and `NULL` on
failure. Hosts that need non-null structured success/error results can use the envelope variants
guarded by `ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE`:

```c
char* editor_core_ffi_editor_state_viewport_styled_envelope_json(
    const EcfEditorState* state,
    uint32_t start_visual_row,
    uint32_t count);

char* editor_core_ffi_editor_state_minimap_envelope_json(
    const EcfEditorState* state,
    uint32_t start_visual_row,
    uint32_t count);

char* editor_core_ffi_editor_state_viewport_composed_envelope_json(
    const EcfEditorState* state,
    uint32_t start_visual_row,
    uint32_t count);

char* editor_core_ffi_workspace_viewport_styled_envelope_json(
    EcfWorkspace* workspace,
    uint64_t view_id,
    uint32_t start_visual_row,
    uint32_t count);

char* editor_core_ffi_workspace_minimap_envelope_json(
    EcfWorkspace* workspace,
    uint64_t view_id,
    uint32_t start_visual_row,
    uint32_t count);

char* editor_core_ffi_workspace_viewport_composed_envelope_json(
    EcfWorkspace* workspace,
    uint64_t view_id,
    uint32_t start_visual_row,
    uint32_t count);
```

Success envelopes preserve the legacy snapshot payload under `value` and include stable query
metadata. `surface` identifies the snapshot family:

- `editor_state_viewport_styled`
- `editor_state_minimap`
- `editor_state_viewport_composed`
- `workspace_viewport_styled`
- `workspace_minimap`
- `workspace_viewport_composed`

```json
{
  "ok": true,
  "status": "success",
  "surface": "workspace_minimap",
  "view_id": 42,
  "start_visual_row": 0,
  "count": 20,
  "value": { "lines": [] },
  "error": null,
  "version": 1
}
```

Failure envelopes keep the same metadata and report a structured `EcfStatus`:

```json
{
  "ok": false,
  "status": "error",
  "surface": "workspace_minimap",
  "view_id": 999999,
  "start_visual_row": 0,
  "count": 20,
  "value": null,
  "error": {
    "code": "internal",
    "status": 7,
    "message": "get_minimap_content failed: ..."
  },
  "version": 1
}
```

## Workspace Result Envelopes

Legacy workspace result helpers keep returning raw JSON on success and `NULL` on failure. Hosts
that need non-null structured success/error results can use the envelope variants guarded by
`ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE`:

```c
char* editor_core_ffi_workspace_search_all_open_buffers_envelope_json(
    const EcfWorkspace* workspace,
    const char* query,
    const char* options_json);

char* editor_core_ffi_workspace_apply_text_edits_envelope_json(
    EcfWorkspace* workspace,
    const char* edits_json);
```

Success envelopes preserve the legacy result payload under `value` and identify the operation:

```json
{
  "ok": true,
  "status": "success",
  "operation": "search_all_open_buffers",
  "value": { "results": [] },
  "error": null,
  "version": 1
}
```

Failure envelopes return an allocated JSON string with a structured `EcfStatus` instead of the
legacy `NULL` sentinel:

```json
{
  "ok": false,
  "status": "error",
  "operation": "apply_text_edits",
  "value": null,
  "error": {
    "code": "parse",
    "status": 5,
    "message": "invalid workspace text edits JSON: ..."
  },
  "version": 1
}
```

## Workspace Query Envelopes

Legacy workspace query helpers keep returning raw JSON on success and `NULL` on failure. Hosts
that need non-null structured success/error results can use the envelope variants guarded by
`ECF_FEATURE_WORKSPACE_QUERY_ENVELOPE`:

```c
char* editor_core_ffi_workspace_info_envelope_json(
    const EcfWorkspace* workspace);

char* editor_core_ffi_workspace_buffer_text_envelope_json(
    const EcfWorkspace* workspace,
    uint64_t buffer_id);

char* editor_core_ffi_workspace_viewport_state_envelope_json(
    EcfWorkspace* workspace,
    uint64_t view_id);
```

Success envelopes preserve the legacy query payload under `value`:

```json
{
  "ok": true,
  "status": "success",
  "operation": "info",
  "value": {
    "buffer_count": 1,
    "view_count": 1,
    "is_empty": false,
    "active_view_id": 1,
    "active_buffer_id": 1
  },
  "error": null,
  "version": 1
}
```

Query failures use structured status codes. Unknown buffer/view ids are reported as `not_found`:

```json
{
  "ok": false,
  "status": "error",
  "operation": "buffer_text",
  "value": null,
  "error": {
    "code": "not_found",
    "status": 3,
    "message": "buffer_text failed: BufferNotFound(BufferId(...))"
  },
  "version": 1
}
```

## JSON Processing Edits

One edit object or an edit array is accepted:

```json
{
  "op": "replace_style_layer",
  "layer": 3,
  "intervals": [
    { "start": 0, "end": 10, "style_id": 42 }
  ]
}
```

## Build

```bash
cargo build -p editor-core-ffi
```

Artifacts are emitted as `cdylib` + `staticlib` + `rlib`.

Public C declarations are available at:

- `crates/editor-core-ffi/include/editor_core_ffi.h`

Packaging/distribution notes (headers + libs layout, platform link deps):

- `docs/FFI-PACKAGING.md`
- `cargo run -p editor-core-dist -- ffi --out dist/ffi --profile release --mode static`

ABI draft/design notes:

- `docs/abi-v1-draft.md`
