# editor-core ABI v1 Draft

Status: Draft aligned with the current pre-v1 fixed-width implementation
Scope date: 2026-08-04

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
- Public booleans in new typed structs and out-parameters: `uint8_t` (`0` false, `1` true). The current pre-v1 `editor_core_ffi.h` still contains legacy C `bool` return values for older JSON/control-plane helpers; do not add new `bool` APIs before v1 finalization.
- No C bitfields in public structs.
- No Rust `usize` / C `size_t` in public structs or public function signatures.
- All extensible structs include:
  - `uint32_t abi_version`
  - `uint32_t struct_size`
- Unknown trailing bytes in input structs must be ignored if `struct_size > known_size`.
- Output buffers use the two-call pattern: `out_cap` and `out_len` are `uint32_t`; `out_len` must be non-null; null `out_buf` or insufficient `out_cap` returns `ECF_ERR_BUFFER_TOO_SMALL` / `ECU_ERR_BUFFER_TOO_SMALL` and writes the required byte length or element count.
- For byte/string/blob outputs, `out_cap` and `out_len` are byte counts. For typed array outputs, they are element counts of the pointed-to element type. APIs must state which unit they use when the name alone is ambiguous.
- Input array `count`/`len` parameters are element counts for typed arrays and byte counts for UTF-8/blob inputs; Rust must validate pointer nullability, count conversion, and slice construction before reading.
- If a required output length or count cannot be represented as `uint32_t`, the function must not truncate it; status-returning APIs return `INVALID_ARGUMENT` and set `last_error_message`.
- Rust-side conversions from public fixed-width integers to internal `usize` must be checked. Too-large values return `ECF_ERR_INVALID_ARGUMENT` / `ECU_ERR_INVALID_ARGUMENT` for status-returning APIs; JSON/string or legacy bool APIs return their failure sentinel and set `last_error_message`.

## Handle Model

Opaque pointer handles:

- `EcfEditorState*`
- `EcfWorkspace*`
- `EcfSublimeProcessor*`
- `EcfTreeSitterProcessor*`
- `EcfTreeSitterIndenter*`

Lifecycle:

- `*_new` returns handle or `NULL`.
- `*_free` accepts `NULL` and is idempotent only for `NULL`.
- No transfer of ownership between handles unless API explicitly says so.
- Callers must not use a handle after `*_free` starts, and must not pass the same handle more than
  once to an API unless that API explicitly documents the aliasing behavior.

## Threading Model

- Contract: opaque handles are single-thread-owned for the duration of each call, not merely a usage recommendation.
- A caller must provide exclusive access to a handle while any mutable call is in progress.
- Callers must not invoke concurrent operations on the same handle, including read-only calls, unless a specific API explicitly documents that it is concurrency-safe.
- Callers must not alias a handle through another API while a mutable call is in progress.
- Error state is thread-local (`last_error_message`).

## Error Model

Primary return form:

- `int32_t` error code (`0` success, non-zero failure).

Companion APIs:

- `const char* ecf_last_error_message(void)` style or allocated string variant.
- JSON control-plane calls may expose a structured envelope:
  `{ "ok": bool, "value": <json-or-null>, "error": { "code": string, "status": int32, "message": string } | null, "version": abi_version }`.
  The headless and UI FFI command/result surfaces have this as an additive API while the legacy
  null-pointer + `last_error_message` symbols remain available for compatibility.

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

Current `editor-core-ui-ffi` LSP lifecycle control-plane APIs follow this model. For example,
`editor_core_ui_ffi_editor_ui_lsp_did_change_workspace_folders_json(EditorUi* ui,
const char* added_json_utf8, const char* removed_json_utf8)` accepts two UTF-8 JSON arrays of
LSP `WorkspaceFolder` objects (`{ "uri": string, "name": string }`) and sends
`workspace/didChangeWorkspaceFolders` for the active UI-owned LSP session. Implementations must
also keep the client-side `workspace/workspaceFolders` response list coherent with the accepted
change.

Document lifecycle control-plane APIs use typed string parameters for common notification shapes.
`editor_core_ui_ffi_editor_ui_lsp_did_open_document(EditorUi* ui, const char* document_uri_utf8,
const char* language_id_utf8, int32_t version, const char* text_utf8)` sends
`textDocument/didOpen` for the active UI-owned LSP session and tracks that document in the session.
`editor_core_ui_ffi_editor_ui_lsp_did_change_document(EditorUi* ui,
const char* document_uri_utf8, const char* text_utf8)` sends a full-document
`textDocument/didChange` for a tracked document; the Rust session owns the per-document mirror used
to compute the LSP range and version.
`editor_core_ui_ffi_editor_ui_lsp_did_save_document(EditorUi* ui, const char* document_uri_utf8,
const char* text_utf8)` sends `textDocument/didSave`; `text_utf8` may be null when the host does
not want to include the optional saved document text. The companion
`editor_core_ui_ffi_editor_ui_lsp_did_close_document(EditorUi* ui, const char* document_uri_utf8)`
sends `textDocument/didClose` for the same session.

Multi-document workspace root control-plane APIs use the same JSON shape. For example,
`editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_json(MultiDocumentEditorUi*
multi, const char* roots_json_utf8)` accepts a UTF-8 JSON string array of workspace root URIs,
replaces the core-owned root list, and returns `{ "added": WorkspaceFolder[], "removed":
WorkspaceFolder[] }` so host UIs can drive `workspace/didChangeWorkspaceFolders` from the
core-owned project/workspace model instead of maintaining a parallel Swift-side root diff.
The same multi-document model can own project-local recent file URIs through
`editor_core_ui_ffi_multi_document_remember_recent_file_uri(...)`,
`editor_core_ui_ffi_multi_document_restore_recent_files_json(...)`,
`editor_core_ui_ffi_multi_document_clear_recent_files(...)`, and
`editor_core_ui_ffi_multi_document_recent_files_json(...)`. The recent list is trimmed,
de-duplicated, bounded, ordered most-recent-first, included in `snapshot_json` as `recent_files`,
and cleared when workspace roots change.
The same model can own recent project/workspace root URIs through
`editor_core_ui_ffi_multi_document_remember_recent_project_uri(...)`,
`editor_core_ui_ffi_multi_document_restore_recent_projects_json(...)`,
`editor_core_ui_ffi_multi_document_clear_recent_projects(...)`, and
`editor_core_ui_ffi_multi_document_recent_projects_json(...)`. Recent project entries use the same
normalization and fixed-size MRU behavior, are included in `snapshot_json` as `recent_projects`,
and are not cleared when the active workspace roots change.
For Quick Open/project file panels, hosts can query the same roots with
`editor_core_ui_ffi_multi_document_list_workspace_files_json(...)`, which returns a bounded
`{ "files": [...] }` payload containing local file `uri`, absolute `path`, and `relative_path`
entries after applying include/exclude globs.
Hosts can also refresh and read a core-owned project file index snapshot through
`editor_core_ui_ffi_multi_document_refresh_project_file_index_json(...)`,
`editor_core_ui_ffi_multi_document_project_file_index_snapshot_json(...)`, and
`editor_core_ui_ffi_multi_document_clear_project_file_index(...)`. Hosts can query the last
refreshed snapshot with
`editor_core_ui_ffi_multi_document_query_project_file_index_json(...)`, which returns
`{ "results": [...] }` entries containing `uri`, `path`, `relative_path`, and fuzzy `score`,
ordered by descending score with stable path tie-breaks. The index snapshot uses the same root trust
boundary, skip rules, stable sorting, and bounded result semantics as workspace file listing,
reports `workspace_roots`, `files`, `is_built`, and `max_results`, and is cleared when workspace
roots change.

Open-tab metadata is part of the same core-owned multi-document model. Hosts can set or clear
document URI metadata with `editor_core_ui_ffi_multi_document_set_tab_document_uri(...)` and
language metadata with `editor_core_ui_ffi_multi_document_set_tab_language_id(...)`. The snapshot
JSON includes these fields as `document_uri` and `language_id` on each tab. Language ids are
trimmed and empty values are represented as null, giving project-level LSP lifecycle planning a
stable way to match open documents to project server configs without treating Swift/AppKit tab
state as the long-term owner.

Project-level LSP launch metadata is also a JSON control-plane surface on `MultiDocumentEditorUi`.
`editor_core_ui_ffi_multi_document_set_project_lsp_servers_json(MultiDocumentEditorUi* multi,
const char* configs_json_utf8)` accepts a UTF-8 JSON array of server configs with `key`,
`command`, optional `args`, `language_id`, optional `language_name`, optional
`server_capabilities`, optional `shared_session`, optional `workspace_roots`, optional
`workspace_folders`, optional `auto_start`, and optional `recovery_policy`. `language_name` is
normalized as display metadata and falls back to the normalized `language_id` when omitted.
`server_capabilities` is a JSON object for host-provided server capability metadata; it defaults to
`{}` and non-object values are rejected. `shared_session` defaults to `true` and declares whether
the host expects a server configuration to be shared across matching documents. `workspace_folders`
is a typed descriptor list with `uri`, `name`, and optional `root_alias`; when omitted, core derives
folder descriptors from `workspace_roots`, and when roots are omitted, core derives roots from
folder URIs. The legacy `workspace_roots` string list remains the compatibility surface for hosts
that only need root URIs. `recovery_policy` is a typed object with `enabled`, `max_attempts`, and
`base_delay_millis`; omitted policies default to `{ "enabled": true, "max_attempts": 3,
"base_delay_millis": 5000 }`, and core normalizes host-provided values to at most 10 attempts and a
3,600,000 ms base delay so the policy is directly interpretable by lifecycle executors.
The companion `editor_core_ui_ffi_multi_document_project_lsp_servers_json(MultiDocumentEditorUi*
multi)` returns the normalized list ordered by key, and
`editor_core_ui_ffi_multi_document_snapshot_json` includes the same list as
`project_lsp_servers`. This is a project/workspace ownership schema for launch metadata; server
process start/stop remains an explicit host action. Hosts can query core-derived lifecycle work
through `editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(...)` using
`operation_utf8` values of `start_plan`, `stop_plan`, `restart_plan`, or `lifecycle_events`.
Each plan entry carries an explicit `operation` string (`start`, `stop`, or `restart`) alongside
the tab id, active view index, document URI, language id/name, server capabilities, shared-session
flag, recovery policy, server key, command, args, workspace roots/folders, and optional proposed
`attempt_id` so hosts can execute and record lifecycle outcomes from a single typed action
descriptor instead of inferring ownership from the endpoint used to fetch the plan. Lifecycle
outcomes and events carry the same `recovery_policy` object, which lets hosts audit the exact
policy used for requested, started, stopped, failed, or skipped outcomes. Core derives the proposed
`attempt_id` from the next lifecycle event sequence and expects hosts to echo it in requested,
started, stopped, failed, or skipped outcomes for the same execution attempt; older outcome records
without an explicit attempt id continue to use the recorded lifecycle sequence for requested
events.
The envelope value is the same payload as the corresponding legacy plan/event JSON surface, while
invalid operations and null handles return `{ "ok": false, "operation": ..., "status": "error",
"error": ..., "version": 1 }` instead of a null pointer.

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
- The headless FFI exports `editor_core_ffi_abi_version()` and
  `editor_core_ffi_feature_flags()` so Swift/third-party hosts can probe the loaded core ABI and
  gate optional feature paths before calling newer symbols.
- The UI FFI exports `editor_core_ui_ffi_abi_version()` and
  `editor_core_ui_ffi_feature_flags()` so Swift/App hosts can probe the loaded UI ABI and gate
  optional feature paths before calling newer symbols.
- Both FFI layers also expose `*_runtime_info_json()` as a one-call capability snapshot for
  third-party C/non-Swift hosts. The JSON contains `kind`, `abi_version`, `version`,
  `feature_flags`, and append-only feature descriptors.
- Headless and UI FFI feature flags are append-only within the pre-v1 line. As of the current
  draft, `ECF_FEATURE_JSON_COMMAND_ENVELOPE`,
  `ECF_FEATURE_RENDERING_SNAPSHOT_ENVELOPE`,
  `ECF_FEATURE_EDITOR_STATE_DERIVED_SNAPSHOT_ENVELOPE`,
  `ECF_FEATURE_WORKSPACE_RESULT_ENVELOPE`,
  `ECF_FEATURE_WORKSPACE_QUERY_ENVELOPE`,
  `ECF_FEATURE_WORKSPACE_LIFECYCLE_ENVELOPE`,
  `ECF_FEATURE_EDITOR_STATE_QUERY_ENVELOPE`,
  `ECF_FEATURE_LSP_HELPER_ENVELOPE`,
  `ECF_FEATURE_LSP_EDIT_HELPER_ENVELOPE`,
  `ECF_FEATURE_PROCESSOR_RESULT_ENVELOPE`,
  `ECU_FEATURE_JSON_COMMAND_ENVELOPE`, and
  `ECU_FEATURE_LSP_RESULT_ENVELOPE` / `ECU_FEATURE_EVENT_STREAM_ENVELOPE` /
  `ECU_FEATURE_MULTI_DOCUMENT_SPECIAL_EVENT_STREAM_ENVELOPE` /
  `ECU_FEATURE_WORKSPACE_EDIT_TRANSACTION_ENVELOPE` /
  `ECU_FEATURE_WORKSPACE_DIAGNOSTICS_ENVELOPE` /
  `ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT_ENVELOPE` /
  `ECU_FEATURE_MULTI_DOCUMENT_SNAPSHOT_ENVELOPE` /
  `ECU_FEATURE_MULTI_DOCUMENT_SEARCH_ENVELOPE` /
  `ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS_CHANGE_ENVELOPE` /
  `ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_SERVERS_ENVELOPE` /
  `ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_LIFECYCLE_ENVELOPE` /
  `ECU_FEATURE_EDITOR_UI_DERIVED_SNAPSHOT_ENVELOPE` /
  `ECU_FEATURE_EDITOR_UI_MINIMAP_ENVELOPE` /
  `ECU_FEATURE_EDITOR_UI_VIEW_POINT_PAYLOAD_ENVELOPE` /
  `ECU_FEATURE_LSP_STATUS_ENVELOPE` /
  `ECU_FEATURE_LSP_WORKSPACE_EDIT_APPLICATION_ENVELOPE` /
  `ECU_FEATURE_LSP_DERIVED_STATE_APPLICATION_ENVELOPE` /
  `ECU_FEATURE_LSP_SEMANTIC_TOKENS_APPLICATION_ENVELOPE` /
  `ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_SEARCH` /
  `ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_REPLACEMENT` mark availability of the corresponding
  JSON envelope symbols, workspace file search/replacement symbols, and stream/result coverage.
- The current cycle is still pre-v1; breaking fixed-width cleanup is allowed before tagging v1, and `editor_core_ffi.h` is the authoritative declaration of the current C surface.
- Compatible additions:
  - new functions
  - new enum values
  - new struct tail fields with `struct_size` guards
- Breaking changes require ABI v2 symbol namespace or library major bump.

## Runtime Capability Negotiation

Hosts should treat capability negotiation as a startup or dynamic-library-load step, not as an
ad-hoc check at each call site:

1. Resolve the base symbols for the layer in use: `*_abi_version()`, `*_feature_flags()`,
   `*_runtime_info_json()`, the string free function, and `*_last_error_message()`.
2. Verify the returned ABI major version before enabling the binding. A newer compatible build may
   expose more feature bits, but a mismatched major version must disable the binding or select a
   different adapter.
3. Build a required feature mask for each workflow. Do not call a symbol guarded by a missing
   feature bit; either use the documented legacy fallback or disable that specific panel/command.
4. Prefer envelope APIs for new integrations. Legacy raw JSON APIs remain compatibility fallbacks
   and keep their older null-pointer plus `last_error_message` failure shape.
5. Use `*_runtime_info_json()` for diagnostics, logs, and non-Swift hosts that need descriptor
   names. The numeric feature mask remains the machine gate; unknown descriptor names and unknown
   status strings are forward-compatible and must not make the host reject the runtime by default.
6. Free every returned runtime-info, envelope, legacy JSON, and allocated error string exactly once
   with the matching layer's string free function.

When a host links statically, the headers and library archive must be produced by the same build
that supplied the feature bit. Dynamic/plugin-style hosts may resolve optional symbols after
feature probing, but still must not call a symbol that is absent from the loaded library.

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

The C headers are authoritative. The examples below are representative surfaces that have been moved to fixed-width scalar parameters while still returning JSON strings for schema flexibility. Entries that still use C `bool` are legacy pre-v1 exports covered by the boolean policy above:

```c
EcfEditorState* editor_core_ffi_editor_state_new(const char* initial_text, uint32_t viewport_width);
uint32_t editor_core_ffi_abi_version(void);
uint64_t editor_core_ffi_feature_flags(void);
char* editor_core_ffi_runtime_info_json(void);
char* editor_core_ffi_editor_state_viewport_styled_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_viewport_styled_envelope_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_minimap_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_minimap_envelope_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_viewport_composed_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_viewport_composed_envelope_json(const EcfEditorState* state, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_editor_state_derived_snapshot_envelope_json(const EcfEditorState* state, const char* snapshot_utf8);
char* editor_core_ffi_editor_state_execute_envelope_json(EcfEditorState* state, const char* command_json);
char* editor_core_ffi_editor_state_full_state_envelope_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_text_envelope_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_text_for_saving_envelope_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_get_line_ending_envelope_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_last_text_delta_envelope_json(const EcfEditorState* state);
char* editor_core_ffi_editor_state_take_last_text_delta_envelope_json(EcfEditorState* state);

int32_t editor_core_ffi_workspace_open_buffer_typed(EcfWorkspace* workspace, const char* uri, const char* text, uint32_t viewport_width, EcfOpenBufferResult* out_result);
int32_t editor_core_ffi_workspace_create_view_typed(EcfWorkspace* workspace, uint64_t buffer_id, uint32_t viewport_width, EcfCreateViewResult* out_result);
char* editor_core_ffi_workspace_open_buffer_envelope_json(EcfWorkspace* workspace, const char* uri, const char* text, uint32_t viewport_width);
char* editor_core_ffi_workspace_create_view_envelope_json(EcfWorkspace* workspace, uint64_t buffer_id, uint32_t viewport_width);
bool editor_core_ffi_workspace_set_viewport_height(EcfWorkspace* workspace, uint64_t view_id, uint32_t height);
bool editor_core_ffi_workspace_set_smooth_scroll_state(EcfWorkspace* workspace, uint64_t view_id, uint32_t top_visual_row, uint16_t sub_row_offset, uint32_t overscan_rows);
char* editor_core_ffi_workspace_execute_envelope_json(EcfWorkspace* workspace, uint64_t view_id, const char* command_json);
char* editor_core_ffi_workspace_viewport_styled_envelope_json(EcfWorkspace* workspace, uint64_t view_id, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_workspace_minimap_envelope_json(EcfWorkspace* workspace, uint64_t view_id, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_workspace_viewport_composed_envelope_json(EcfWorkspace* workspace, uint64_t view_id, uint32_t start_visual_row, uint32_t count);
char* editor_core_ffi_workspace_info_envelope_json(const EcfWorkspace* workspace);
char* editor_core_ffi_workspace_buffer_text_envelope_json(const EcfWorkspace* workspace, uint64_t buffer_id);
char* editor_core_ffi_workspace_viewport_state_envelope_json(EcfWorkspace* workspace, uint64_t view_id);
char* editor_core_ffi_workspace_search_all_open_buffers_envelope_json(const EcfWorkspace* workspace, const char* query, const char* options_json);
char* editor_core_ffi_workspace_apply_text_edits_envelope_json(EcfWorkspace* workspace, const char* edits_json);

uint64_t editor_core_ffi_lsp_char_offset_to_utf16(const char* line_text, uint64_t char_offset);
uint64_t editor_core_ffi_lsp_utf16_to_char_offset(const char* line_text, uint64_t utf16_offset);
char* editor_core_ffi_lsp_formatting_options_json(uint32_t tab_size, bool insert_spaces);
char* editor_core_ffi_lsp_path_to_file_uri_envelope_json(const char* path);
char* editor_core_ffi_lsp_file_uri_to_path_envelope_json(const char* uri);
char* editor_core_ffi_lsp_percent_encode_path_envelope_json(const char* path);
char* editor_core_ffi_lsp_percent_decode_path_envelope_json(const char* path);
char* editor_core_ffi_lsp_formatting_options_envelope_json(uint32_t tab_size, bool insert_spaces);
char* editor_core_ffi_lsp_formatting_options_for_indentation_config_envelope_json(const char* indentation_config_json, uint32_t tab_width);
char* editor_core_ffi_lsp_on_type_formatting_params_envelope_json(const EcfEditorState* state, const char* uri, const char* ch, const char* options_json);
char* editor_core_ffi_lsp_apply_text_edits_envelope_json(EcfEditorState* state, const char* edits_json);
char* editor_core_ffi_lsp_semantic_tokens_to_intervals_envelope_json(const EcfEditorState* state, const char* data_json);
char* editor_core_ffi_lsp_decode_semantic_style_id_envelope_json(uint32_t style_id);
char* editor_core_ffi_lsp_document_highlights_to_processing_edit_envelope_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_inlay_hints_to_processing_edit_envelope_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_document_links_to_processing_edit_envelope_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_code_lens_to_processing_edit_envelope_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_document_symbols_to_processing_edit_envelope_json(const EcfEditorState* state, const char* result_json);
char* editor_core_ffi_lsp_diagnostics_to_processing_edits_envelope_json(const EcfEditorState* state, const char* publish_diagnostics_params_json);
char* editor_core_ffi_lsp_workspace_symbols_envelope_json(const char* result_json);
char* editor_core_ffi_lsp_locations_envelope_json(const char* result_json);
char* editor_core_ffi_lsp_completion_item_to_text_edits_envelope_json(const EcfEditorState* state, const char* completion_item_json, const char* mode, uint64_t fallback_start, uint64_t fallback_end, bool has_fallback);
char* editor_core_ffi_lsp_apply_completion_item_envelope_json(EcfEditorState* state, const char* completion_item_json, const char* mode);
char* editor_core_ffi_sublime_processor_process_envelope_json(EcfSublimeProcessor* processor, const EcfEditorState* state);
char* editor_core_ffi_sublime_processor_scope_for_style_id_envelope_json(const EcfSublimeProcessor* processor, uint32_t style_id);
char* editor_core_ffi_treesitter_processor_process_envelope_json(EcfTreeSitterProcessor* processor, const EcfEditorState* state);
char* editor_core_ffi_treesitter_processor_last_update_mode_envelope_json(const EcfTreeSitterProcessor* processor);
char* editor_core_ffi_treesitter_indenter_reindent_line_envelope_json(EcfTreeSitterIndenter* indenter, const EcfEditorState* state, uint32_t line, const char* indentation_config_json);
```

The UI FFI (`editor-core-ui-ffi`) follows the same fixed-width boundary discipline for its C surface. Examples include:

```c
uint32_t editor_core_ui_ffi_abi_version(void);
uint64_t editor_core_ui_ffi_feature_flags(void);
char* editor_core_ui_ffi_runtime_info_json(void);
EditorUi* editor_core_ui_ffi_editor_ui_new(const char* initial_text_utf8, uint32_t viewport_width_cells);
EditorUi* editor_core_ui_ffi_editor_ui_clone_view(EditorUi* ui, uint32_t viewport_width_cells);
char* editor_core_ui_ffi_editor_ui_execute_command_envelope_json(EditorUi* ui, const char* command_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_take_last_result_envelope_json(EditorUi* ui, const char* slot_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_envelope_json(EditorUi* ui, const char* workspace_edit_json_utf8, const char* document_uri_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_envelope_json(EditorUi* ui, const char* publish_diagnostics_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_envelope_json(EditorUi* ui, const char* inlay_hints_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_envelope_json(EditorUi* ui, const char* code_lens_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_document_links_envelope_json(EditorUi* ui, const char* document_links_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_envelope_json(EditorUi* ui, const char* document_highlights_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_envelope_json(EditorUi* ui, const char* document_symbols_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_envelope_json(EditorUi* ui, const char* folding_ranges_result_json_utf8);
char* editor_core_ui_ffi_editor_ui_minimap_envelope_json(EditorUi* ui, uint32_t start_visual_row, uint32_t count);
char* editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(EditorUi* ui, const char* kind_utf8, float x_px, float y_px);
char* editor_core_ui_ffi_editor_ui_event_stream_envelope_json(EditorUi* ui, const char* stream_utf8, uint64_t after_sequence);
char* editor_core_ui_ffi_multi_document_snapshot_envelope_json(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_search_all_tabs_envelope_json(MultiDocumentEditorUi* multi, const char* query_utf8, uint8_t case_sensitive, uint8_t whole_word, uint8_t regex);
char* editor_core_ui_ffi_multi_document_list_workspace_files_json(MultiDocumentEditorUi* multi, const char* include_globs_json_utf8, const char* exclude_globs_json_utf8, uint32_t max_results);
char* editor_core_ui_ffi_multi_document_search_workspace_files_json(MultiDocumentEditorUi* multi, const char* query_utf8, const char* include_globs_json_utf8, const char* exclude_globs_json_utf8, uint8_t case_sensitive, uint8_t whole_word, uint8_t regex, uint32_t max_results);
char* editor_core_ui_ffi_multi_document_search_workspace_files_envelope_json(MultiDocumentEditorUi* multi, const char* query_utf8, const char* include_globs_json_utf8, const char* exclude_globs_json_utf8, uint8_t case_sensitive, uint8_t whole_word, uint8_t regex, uint32_t max_results);
char* editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_json(MultiDocumentEditorUi* multi, const char* query_utf8, const char* replacement_utf8, const char* include_globs_json_utf8, const char* exclude_globs_json_utf8, const char* apply_mode_utf8, uint8_t case_sensitive, uint8_t whole_word, uint8_t regex, uint32_t max_results);
int32_t editor_core_ui_ffi_multi_document_remember_recent_file_uri(MultiDocumentEditorUi* multi, const char* uri_utf8);
int32_t editor_core_ui_ffi_multi_document_restore_recent_files_json(MultiDocumentEditorUi* multi, const char* uris_json_utf8);
int32_t editor_core_ui_ffi_multi_document_clear_recent_files(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_recent_files_json(MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_multi_document_remember_recent_project_uri(MultiDocumentEditorUi* multi, const char* uri_utf8);
int32_t editor_core_ui_ffi_multi_document_restore_recent_projects_json(MultiDocumentEditorUi* multi, const char* uris_json_utf8);
int32_t editor_core_ui_ffi_multi_document_clear_recent_projects(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_recent_projects_json(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_refresh_project_file_index_json(MultiDocumentEditorUi* multi, uint32_t max_results);
char* editor_core_ui_ffi_multi_document_project_file_index_snapshot_json(MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_multi_document_clear_project_file_index(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_query_project_file_index_json(MultiDocumentEditorUi* multi, const char* query_utf8, uint32_t max_results);
char* editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_envelope_json(MultiDocumentEditorUi* multi, const char* roots_json_utf8);
char* editor_core_ui_ffi_multi_document_project_lsp_servers_envelope_json(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_event_stream_envelope_json(MultiDocumentEditorUi* multi, const char* stream_utf8, uint64_t after_sequence);
char* editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(MultiDocumentEditorUi* multi, const char* operation_utf8, const char* workspace_edit_json_utf8);
char* editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(MultiDocumentEditorUi* multi, const char* operation_utf8, const char* result_json_utf8);
char* editor_core_ui_ffi_multi_document_workspace_outline_snapshot_envelope_json(MultiDocumentEditorUi* multi);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_hover(EditorUi* ui, uint32_t line, uint32_t column, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_set_tab_width(EditorUi* ui, uint32_t width_cells);
int32_t editor_core_ui_ffi_editor_ui_set_lsp_on_type_formatting_enabled(EditorUi* ui, uint8_t enabled);
char* editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(EditorUi* ui, const char* workspace_edit_json_utf8, const char* document_uri_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_completion_item_resolve(EditorUi* ui, const char* item_json_utf8, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_completion_item_resolve_json(EditorUi* ui, uint8_t* out_has_result, char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_execute_command(EditorUi* ui, const char* command_json_utf8, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_execute_command_json(EditorUi* ui, uint8_t* out_has_result, char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_inlay_hints(EditorUi* ui, uint32_t start_offset, uint32_t end_offset, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hints_json(EditorUi* ui, uint8_t* out_has_result, char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_inlay_hint_resolve(EditorUi* ui, const char* hint_json_utf8, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hint_resolve_json(EditorUi* ui, uint8_t* out_has_result, char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_links(EditorUi* ui, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_document_links_json(EditorUi* ui, uint8_t* out_has_result, char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_link_resolve(EditorUi* ui, const char* link_json_utf8, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_document_link_resolve_json(EditorUi* ui, uint8_t* out_has_result, char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges(EditorUi* ui, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_take_last_folding_ranges_json(EditorUi* ui, uint8_t* out_has_result, char** out_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json(EditorUi* ui, const char* folding_ranges_result_json_utf8);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_selection_range(EditorUi* ui, const char* positions_json_utf8, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(EditorUi* ui, const char* previous_result_id_utf8, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_document_color(EditorUi* ui, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_prepare_call_hierarchy(EditorUi* ui, uint32_t line, uint32_t column, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_request_prepare_type_hierarchy(EditorUi* ui, uint32_t line, uint32_t column, uint64_t* out_request_id);
int32_t editor_core_ui_ffi_editor_ui_lsp_format_document(EditorUi* ui, const char* formatting_options_json_utf8, uint32_t timeout_ms, uint8_t* out_applied);
int32_t editor_core_ui_ffi_editor_ui_lsp_format_range(EditorUi* ui, uint32_t start_offset, uint32_t end_offset, const char* formatting_options_json_utf8, uint32_t timeout_ms, uint8_t* out_applied);
int32_t editor_core_ui_ffi_editor_ui_lsp_format_on_type(EditorUi* ui, uint32_t logical_line, uint32_t logical_column, const char* trigger_utf8, const char* formatting_options_json_utf8, uint32_t timeout_ms, uint8_t* out_applied);
char* editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_multi_document_redo_last_workspace_edit_transaction_json(MultiDocumentEditorUi* multi);
char* editor_core_ui_ffi_editor_ui_minimap_json(EditorUi* ui, uint32_t start_visual_row, uint32_t count);
int32_t editor_core_ui_ffi_editor_ui_render_rgba(EditorUi* ui, uint8_t* out_buf, uint32_t out_cap, uint32_t* out_len);
int32_t editor_core_ui_ffi_editor_ui_get_selections(EditorUi* ui, EcuSelectionRange* out_ranges, uint32_t out_cap, uint32_t* out_len, uint32_t* out_primary_index);
```

`editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json` is a pre-v1 JSON/control-plane
surface for rename/code-action style payloads. It applies `TextEdit`s that target the supplied
document URI, or the UI's current LSP document URI when the argument is null/empty, and returns an
allocated JSON summary with `applied`, `applied_uri`, `applied_edit_count`, `skipped_uris`, and
per-document edit counts/conflict hints. The caller owns the returned string and must release it
with the UI FFI string free function.

`editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json` is a pre-v1
JSON/control-plane surface for restoring the most recent successful core-owned WorkspaceEdit
transaction in a `MultiDocumentEditorUi`. Hosts must probe
`ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_UNDO` before treating the command as
available. The returned JSON includes `undone`, `restored_uris`,
`restored_open_tab_count`, `restored_filesystem_entry_count`, and `message`; the caller owns the
returned string and must release it with the UI FFI string free function.

`editor_core_ui_ffi_multi_document_redo_last_workspace_edit_transaction_json` is a pre-v1
JSON/control-plane surface for reapplying the most recently undone core-owned WorkspaceEdit
transaction in a `MultiDocumentEditorUi`. Hosts must probe
`ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_REDO` before treating the command as
available. The returned JSON uses the same result shape as WorkspaceEdit transaction apply, with
`mode` set to `redo`; unavailable redo returns `applied: false`. Redo goes through the normal core
WorkspaceEdit transaction path, so existing version/dirty/root-gated conflict checks still apply.

WorkspaceEdit transaction `conflicts[]` entries are compatibility-extensible JSON objects. Current
entries include `uri`, `kind`, `severity`, `apply_impact`, `resolution`, `reason`, `operation`, and
`message`. `severity` is currently `warning` for partial skipped changes and `error` for atomic
blocking conflicts or runtime apply failures. `apply_impact` distinguishes `skips_change` from
`blocks_atomic_apply`; `resolution` is a machine-readable hint such as `save_or_discard`,
`refresh_request`, `restore_resource`, `adjust_target`, `unsupported`, or `inspect`. Hosts must
ignore unknown conflict fields and tolerate unknown enum strings.

All public array counts (`style_count`, `font_count`, `decoration_count`, `range_count`, `data_len`, `out_cap`) are `uint32_t`; Rust checks conversion to internal `usize` and validates Rust slice length limits before constructing slices.

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

1. Complete pre-v1 breaking cleanup of fixed-width scalar types, checked conversions, and legacy boolean policy.
2. Keep existing JSON exports intact where their signatures match the fixed-width contract; otherwise update them before v1 rather than carrying parallel legacy aliases.
3. Add typed hot-path functions (parallel API track).
4. Add binary viewport blob APIs.
5. Update platform bindings to prefer typed/blob paths.
6. Restrict JSON path to control plane and tooling.

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
