# Tree-sitter WASM + file-based queries

Status: **implemented**  
Date: **2026-03-10**

This repo now supports Tree-sitter via **WASM grammars + on-disk `.scm` queries**, configured via an
FFI-friendly **JSON registry**.

## What shipped

- **No compiled-in language packs**
  - Removed the built-in Rust query pack crate (`crates/editor-core-treesitter-queries`).
  - Removed `tree-sitter-rust` as a runtime dependency of UI/FFI layers.
  - Removed the built-in `editor_core_ffi_treesitter_language_rust()` symbol from `editor-core-ffi`.
- **Tree-sitter WASM enabled**
  - `tree-sitter = { version = "0.26", features = ["wasm"] }` in `editor-core-treesitter`.
- **File-based assets**
  - Grammar: `language.wasm`
  - Queries:
    - `highlights.scm` (required)
    - `folds.scm` (optional, supported to preserve folding parity)
    - `tags.scm` (optional; parsed/loaded but not executed by the highlight processor yet)
    - `injections.scm` (optional; parsed/loaded but not executed yet)
- **Registries**
  - `extension_map`: `extension -> language_id`
  - `languages`: `language_id -> TreeSitterConfig` (file paths)
- **FFI**
  - Swift ↔ Rust uses one JSON blob (`schema_version`ed) for stable evolution.

## On-disk layout (AttoEditor)

Config root:

- `~/Library/Application Support/codes.unwritten.attoeditor`

Tree-sitter root:

- `~/Library/Application Support/codes.unwritten.attoeditor/treesitter`

Per-language layout:

```text
treesitter/
  registry.json                     # optional; extension -> language_id overrides
  rust/
    language.wasm                   # required
    highlights.scm                  # required
    folds.scm                       # optional
    tags.scm                        # optional
    injections.scm                  # optional
  swift/
    language.wasm
    highlights.scm
```

Notes:

- The **directory name is the `language_id`** (e.g. `rust`, `swift`).
- Filenames are conventional to avoid per-language metadata files.

## Registry JSON schema (v1)

One JSON object is passed across FFI:

```json
{
  "schema_version": 1,
  "root_dir": "/Users/me/Library/Application Support/codes.unwritten.attoeditor/treesitter",
  "extension_map": {
    "rs": "rust",
    "swift": "swift"
  },
  "languages": {
    "rust": {
      "wasm": "rust/language.wasm",
      "highlights": "rust/highlights.scm",
      "folds": "rust/folds.scm",
      "tags": "rust/tags.scm",
      "injections": "rust/injections.scm"
    },
    "swift": {
      "wasm": "swift/language.wasm",
      "highlights": "swift/highlights.scm"
    }
  }
}
```

Path resolution rules:

- If `root_dir` is provided:
  - relative paths are resolved relative to `root_dir`
  - absolute paths remain absolute
- If `root_dir` is omitted:
  - all paths must be absolute

Validation rules:

- A language config must have `wasm` + `highlights`.
- Optional fields may be absent or empty.

## Rust API surface

`crates/editor-core-treesitter` now owns the canonical data model:

- `TreeSitterConfig` (paths for one language)
- `TreeSitterRegistry` (extension map + language configs)
- `TreeSitterLanguage` (native vs WASM)
- `load_processor_config_from_config(language_id, &TreeSitterConfig) -> TreeSitterProcessorConfig`

`TreeSitterProcessorConfig` supports:

- native grammars (still allowed for non-FFI Rust consumers)
- WASM grammars loaded from bytes (used by UI/FFI layers)

Implementation note:

- When using WASM grammars, the processor keeps a Wasmtime `Engine` alive for the lifetime of the
  parser’s WASM store (required by the Tree-sitter WASM API).

## UI integration (Rust)

`crates/editor-core-ui::EditorUi` stores a `TreeSitterRegistry` per document and exposes:

- `set_treesitter_registry_json(registry_json)`
- `set_treesitter_language(language_id)`
- `set_treesitter_for_path(path)`

Backwards-compatible aliases remain:

- `set_treesitter_query_pack(pack_id)` → treated as `language_id`
- `set_treesitter_rust_default()` → treated as language id `"rust"`

## FFI integration (C ABI)

`crates/editor-core-ui-ffi` exports:

- `editor_core_ui_ffi_editor_ui_treesitter_set_registry_json(ui, registry_json_utf8)`
- `editor_core_ui_ffi_editor_ui_treesitter_enable_language(ui, language_id_utf8)`
- `editor_core_ui_ffi_editor_ui_treesitter_enable_for_path(ui, path_utf8)`

Backwards-compatible aliases remain:

- `editor_core_ui_ffi_editor_ui_treesitter_enable_query_pack` (alias for enable_language)
- `editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default` (requires registry to contain `"rust"`)

## Swift integration (AttoEditor / demos)

Swift wrapper additions in `swift/Sources/EditorCoreUIFFI/EditorUI.swift`:

- `treeSitterSetRegistryJSON(_:)`
- `treeSitterEnableLanguage(_:)`
- `treeSitterEnableForPath(_:)`

AttoEditor behavior:

- Ensures `~/Library/Application Support/codes.unwritten.attoeditor/treesitter` exists.
- Scans subdirectories to build a registry JSON (best-effort).
- Keeps Rust LSP-first behavior for `.rs`; falls back to Tree-sitter highlighting when LSP fails.

## Tests and fixtures

- Rust fixtures live under:
  - `crates/editor-core-treesitter/tests/fixtures/treesitter/`
- They include a minimal Rust install:
  - `rust/language.wasm`, `highlights.scm`, `tags.scm`, `injections.scm` (from `tree-sitter-rust@0.24.0`)
  - `rust/folds.scm` (repo-provided)
- Coverage:
  - `crates/editor-core-treesitter/tests/treesitter_processor.rs`
  - `crates/editor-core-treesitter/tests/treesitter_registry.rs`
  - UI + FFI tests validate rendering, capture mapping, and folding toggles.

## Known limitations / future work

- `tags.scm` and `injections.scm` are part of the registry model, but the highlight processor does
  not yet execute them (future milestone work).
- Optional improvements:
  - caching WASM engines / query strings across documents
  - hot reload of assets on file change
