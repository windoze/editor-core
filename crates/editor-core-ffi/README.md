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
  - JSON APIs return `NULL` / `false` / `0`
- In all cases, thread-local last error is retrievable via:

```c
char* editor_core_ffi_last_error_message(void);
```

## Typed ABI v1 (Hot Path)

Version:

```c
uint32_t editor_core_ffi_abi_version(void); /* currently 1 */
```

Core hot-path examples:

```c
int32_t editor_core_ffi_editor_insert_text_utf8(EcfEditorState* s, const uint8_t* bytes, uint32_t len);
int32_t editor_core_ffi_editor_move_to(EcfEditorState* s, uint32_t line, uint32_t column);
int32_t editor_core_ffi_editor_backspace(EcfEditorState* s);
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

```json
{
  "kind": "style",
  "op": "fold",
  "start_line": 10,
  "end_line": 20
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

ABI draft/design notes:

- `docs/abi-v1-draft.md`
