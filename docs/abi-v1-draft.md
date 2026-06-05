# editor-core ABI v1 Draft

Status: Draft aligned with the current ABI-v1 implementation
Scope date: 2026-06-05

## Goals

- Define a stable C ABI for native hosts on:
  - macOS: Swift
  - Windows: C++ and C# (.NET)
  - Linux: C/C++ (GTK+ stack)
- Minimize hot-path overhead (typing, cursor movement, viewport fetch).
- Preserve forward/backward compatibility discipline.
- Keep the Rust core UI-agnostic.

## Non-Goals

- Expose every internal Rust type 1:1.
- Define a network protocol.
- Replace all JSON usage immediately.

## Recommendation Summary

v1 should use a layered contract:

1. Typed C functions for hot-path operations (required).
2. Binary snapshot retrieval (required).
3. JSON control-plane APIs for complex/low-frequency payloads (required in v1 for pragmatism).
4. Optional ioctl-style generic dispatcher for extension points (optional in v1).

This gives good performance now and allows schema-rich features without blocking integration.

## ABI Rules

- Calling convention: `extern "C"`.
- Endianness: little-endian.
- Public integers in structs and function signatures: fixed-width only (`uint8_t`, `uint16_t`, `uint32_t`, `uint64_t`, `int32_t`, etc.).
- Public booleans: `uint8_t` (`0` false, `1` true).
- No C bitfields in public structs.
- No Rust `usize` / C `size_t` in public structs or public function signatures.
- All extensible structs include:
  - `uint32_t abi_version`
  - `uint32_t struct_size`
- Unknown trailing bytes in input structs must be ignored if `struct_size > known_size`.
- Output buffers use the two-call pattern: `out_cap` and `out_len` are `uint32_t`; `out_len` must be non-null; null `out_buf` or insufficient `out_cap` returns `ECF_ERR_BUFFER_TOO_SMALL` and writes the required byte length.
- Rust-side conversions from public fixed-width integers to internal `usize` must be checked. Too-large values return `ECF_ERR_INVALID_ARGUMENT` for status-returning APIs; JSON/string or legacy bool APIs return their failure sentinel and set `last_error_message`.

## Handle Model

Opaque pointer handles:

- `EcfEditorState*`
- `EcfWorkspace*`
- `EcfSublimeProcessor*`
- `EcfTreeSitterProcessor*`

Lifecycle:

- `*_new` returns handle or `NULL`.
- `*_free` accepts `NULL` and is idempotent only for `NULL`.
- No transfer of ownership between handles unless API explicitly says so.

## Threading Model

- Contract: opaque handles are single-thread-owned for the duration of each call.
- Callers must not invoke concurrent mutable operations on the same handle, and must not alias a handle through another API while a mutable call is in progress.
- Read-only calls are not guaranteed to be concurrency-safe unless a specific API explicitly documents otherwise.
- Error state is thread-local (`last_error_message`).

## Error Model

Primary return form:

- `int32_t` error code (`0` success, non-zero failure).

Companion APIs:

- `const char* ecf_last_error_message(void)` style or allocated string variant.
- Optional structured error payload in future (`domain`, `code`, `message`, `details_json`).

Proposed error codes:

```c
typedef enum EcfStatus {
  ECF_OK = 0,
  ECF_ERR_INVALID_ARGUMENT = 1,
  ECF_ERR_INVALID_UTF8 = 2,
  ECF_ERR_NOT_FOUND = 3,
  ECF_ERR_BUFFER_TOO_SMALL = 4,
  ECF_ERR_PARSE = 5,
  ECF_ERR_COMMAND_FAILED = 6,
  ECF_ERR_INTERNAL = 7,
  ECF_ERR_UNSUPPORTED = 8,
  ECF_ERR_VERSION_MISMATCH = 9,
} EcfStatus;
```

## Memory Ownership

- Borrowed input pointers are valid for the duration of call only.
- Returned allocated strings/blobs must be freed via ABI free function.
- For high-frequency output, caller-allocated output buffers are preferred.

## Required v1 API Sets

## 1) Typed Hot-Path Commands (Required)

Expose direct functions for high-frequency editor actions.

Editor-state flavor:

```c
int32_t ecf_editor_insert_text_utf8(EcfEditorState* s, const uint8_t* bytes, uint32_t len);
int32_t ecf_editor_backspace(EcfEditorState* s);
int32_t ecf_editor_delete_forward(EcfEditorState* s);
int32_t ecf_editor_move_to(EcfEditorState* s, uint32_t line, uint32_t column);
int32_t ecf_editor_move_by(EcfEditorState* s, int32_t delta_line, int32_t delta_column);
int32_t ecf_editor_set_selection(
    EcfEditorState* s,
    uint32_t start_line,
    uint32_t start_col,
    uint32_t end_line,
    uint32_t end_col,
    uint8_t direction /*0=fwd,1=back*/);
int32_t ecf_editor_clear_selection(EcfEditorState* s);
int32_t ecf_editor_undo(EcfEditorState* s);
int32_t ecf_editor_redo(EcfEditorState* s);
```

Workspace flavor (same ops with `view_id`):

```c
int32_t ecf_workspace_insert_text_utf8(EcfWorkspace* w, uint64_t view_id, const uint8_t* bytes, uint32_t len);
int32_t ecf_workspace_move_to(EcfWorkspace* w, uint64_t view_id, uint32_t line, uint32_t column);
/* ... */
```

Notes:

- Keep command set small in v1, extend in v1.x.
- Return compact result structs for commands that produce values.

## 2) Binary Snapshot API (Required)

JSON snapshots are too expensive for per-frame rendering.
Use a binary blob format with two-call pattern.

```c
int32_t ecf_editor_get_viewport_blob(
    EcfEditorState* s,
    uint32_t start_visual_row,
    uint32_t row_count,
    uint8_t* out_buf,
    uint32_t out_cap,
    uint32_t* out_len);
```

Blob layout (little-endian):

```c
typedef struct EcfViewportBlobHeader {
  uint32_t abi_version;
  uint32_t header_size;
  uint32_t line_count;
  uint32_t cell_count;
  uint32_t style_id_count;
  uint32_t lines_offset;
  uint32_t cells_offset;
  uint32_t style_ids_offset;
  uint32_t reserved;
} EcfViewportBlobHeader;

typedef struct EcfViewportLine {
  uint32_t logical_line_index;
  uint32_t visual_in_logical;
  uint32_t char_offset_start;
  uint32_t char_offset_end;
  uint32_t cell_start_index;
  uint32_t cell_count;
  uint16_t segment_x_start_cells;
  uint8_t is_wrapped_part;
  uint8_t is_fold_placeholder_appended;
} EcfViewportLine;

typedef struct EcfViewportCell {
  uint32_t scalar_value;      /* Unicode scalar, not UTF-16 */
  uint16_t width;             /* usually 1 or 2 */
  uint16_t style_count;
  uint32_t style_start_index; /* index into style_ids array */
} EcfViewportCell;
```

Same model for workspace viewport APIs with `view_id` argument.

## 3) Control Plane APIs (Required in v1)

Keep JSON for complex payloads that are not hot-path:

- LSP payload transforms (semantic tokens, diagnostics, symbols, links, code lens).
- Complex config and ad-hoc tooling.
- Debug and inspection endpoints.

This avoids blocking integrations while typed/binary surfaces mature.

## 4) Generic ioctl-Style Dispatcher (Optional v1)

Optional extension point for future ops without exploding symbol count.

```c
int32_t ecf_dispatch(
    void* handle,
    uint32_t domain,  /* editor/workspace/lsp/sublime/treesitter */
    uint32_t op,
    const void* in_buf,
    uint32_t in_len,
    void* out_buf,
    uint32_t out_cap,
    uint32_t* out_len);
```

Guidelines:

- Use only for medium-frequency or experimental ops.
- Keep very hot operations as direct typed calls.

## Versioning Strategy

- ABI major version baked into library and exported via `ecf_abi_version()`.
- Compatible additions:
  - new functions
  - new enum values
  - new struct tail fields with `struct_size` guards
- Breaking changes require ABI v2 symbol namespace or library major bump.

## Cross-Language Binding Notes

## Swift (macOS)

- Import via module map + bridging header.
- Wrap handles in `final class` with `deinit` calling `*_free`.
- Prefer `Data.withUnsafeBytes` for UTF-8 and blob APIs.
- For frame rendering, parse viewport blob into Swift structs once per frame.

## C# (Windows)

- Use `DllImport` with `CallingConvention.Cdecl`.
- Wrap handles in `SafeHandle` subclasses.
- Use `Span<byte>`/`Memory<byte>` + pinned buffers for blob APIs.
- Avoid per-keystroke JSON serialization from managed code.

## C/C++ (Windows/Linux)

- Include C header directly.
- Add thin C++ RAII wrappers for handle lifecycle.
- Use reusable arena/stack buffers for snapshot calls to reduce heap churn.

## Data Model Decisions

- Coordinates at API boundary:
  - logical positions: `(line, column)` using Unicode scalar columns
  - ranges: half-open `[start, end)` offsets where applicable
- IDs:
  - `buffer_id` and `view_id` are `uint64_t`
- View rows, row counts, viewport widths/heights, tab widths, and logical line/column values in typed APIs are `uint32_t`.
- Document-wide char offsets and lengths use `uint64_t` when they cross the C ABI boundary.
- Style/decor layer IDs:
  - `uint32_t`

## Current Fixed-Width JSON/Control-Plane Surfaces

The JSON/control-plane functions still return JSON strings for schema flexibility, but their scalar ABI parameters are fixed-width:

```c
EcfEditorState* editor_core_ffi_editor_state_new(const char* initial_text, uint32_t viewport_width);
char* editor_core_ffi_editor_state_viewport_styled_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_minimap_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_viewport_composed_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);

int32_t editor_core_ffi_workspace_open_buffer_typed(EcfWorkspace* workspace, const char* uri, const char* text, uint32_t viewport_width, EcfOpenBufferResult* out_result);
int32_t editor_core_ffi_workspace_create_view_typed(EcfWorkspace* workspace, uint64_t buffer_id, uint32_t viewport_width, EcfCreateViewResult* out_result);
bool editor_core_ffi_workspace_set_viewport_height(EcfWorkspace* workspace, uint64_t view_id, uint32_t height);
bool editor_core_ffi_workspace_set_smooth_scroll_state(EcfWorkspace* workspace, uint64_t view_id, uint32_t top_visual_row, uint16_t sub_row_offset, uint32_t overscan_rows);

uint64_t editor_core_ffi_lsp_char_offset_to_utf16(const char* line_text, uint64_t char_offset);
uint64_t editor_core_ffi_lsp_utf16_to_char_offset(const char* line_text, uint64_t utf16_offset);
char* editor_core_ffi_lsp_formatting_options_json(uint32_t tab_size, bool insert_spaces);
```

## Suggested Initial Typed Command Set (v1)

- Text input/edit:
  - insert text
  - backspace/delete-forward
  - insert newline/tab
  - undo/redo
- Cursor/selection:
  - move to/by
  - move word left/right
  - set/clear selection
- View:
  - set viewport width
  - set wrap mode
  - set tab width
- Query:
  - get document stats
  - get cursor state
  - get viewport blob

Everything else can remain JSON in v1.

## Suggested Metrics to Validate ABI Design

- Typing throughput: 10k inserts, p50/p95 latency.
- Cursor movement throughput under soft-wrap.
- Viewport fetch throughput at 60/120 FPS equivalent rates.
- Managed interop overhead (C#) before and after typed/blob APIs.

## Migration Plan from Current JSON-Heavy FFI

1. Keep existing JSON exports intact.
2. Add typed hot-path functions (parallel API track).
3. Add binary viewport blob APIs.
4. Update platform bindings to prefer typed/blob paths.
5. Restrict JSON path to control plane and tooling.

## Open Questions

- Should v1 expose callback-based change notifications, or keep pull/poll only?
- Should batch command API be part of v1 (`apply_batch`) or v1.1?
- Should composed/decorated viewport have separate blob schema in v1 or stay JSON first?
- Do we need UTF-16 position variants in typed API for direct LSP host integration?

## Proposed Minimal Header Additions (Illustrative)

```c
uint32_t ecf_abi_version(void);

int32_t ecf_editor_insert_text_utf8(EcfEditorState* s, const uint8_t* bytes, uint32_t len);
int32_t ecf_editor_move_to(EcfEditorState* s, uint32_t line, uint32_t column);
int32_t ecf_editor_backspace(EcfEditorState* s);

int32_t ecf_editor_get_viewport_blob(
    EcfEditorState* s,
    uint32_t start_visual_row,
    uint32_t row_count,
    uint8_t* out_buf,
    uint32_t out_cap,
    uint32_t* out_len);
```

This is the proposed direction for ABI v1 implementation planning.
