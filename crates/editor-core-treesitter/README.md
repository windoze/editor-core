# editor-core-treesitter

`editor-core-treesitter` provides an **offline**, **incremental** Tree-sitter pipeline for
`editor-core`:

- syntax highlighting → `ProcessingEdit::ReplaceStyleLayer`
- folding regions → `ProcessingEdit::ReplaceFoldingRegions`

The public output is expressed in `editor-core`'s derived-state model, so hosts can apply results
through `EditorStateManager::apply_processing_edits` (or `apply_processor`).

## Quick start

```rust
use editor_core::EditorStateManager;
use editor_core_treesitter::{
    load_processor_config_from_config, TreeSitterConfig, TreeSitterProcessor,
};
use std::collections::BTreeMap;
use std::path::PathBuf;

let mut state = EditorStateManager::new("fn main() {}\n", 80);

// Point this at your Tree-sitter assets directory:
//
// treesitter/
//   rust/
//     language.wasm
//     highlights.scm
//     folds.scm            # optional
let treesitter_root = PathBuf::from("/path/to/treesitter");
let rust_dir = treesitter_root.join("rust");
let rust_cfg = TreeSitterConfig::from_language_dir(&rust_dir).expect("rust treesitter assets");

let mut config = load_processor_config_from_config("rust", &rust_cfg).unwrap();
config.capture_styles = BTreeMap::from([
    ("comment".to_string(), 1),
    ("string".to_string(), 2),
    ("type".to_string(), 3),
    ("function".to_string(), 4),
]);

let mut processor = TreeSitterProcessor::new(config).unwrap();
state.apply_processor(&mut processor).unwrap();
```

## Notes

- Incrementality is driven by `EditorStateManager::last_text_delta()`; if no delta is available (or
  it doesn't match the processor's internal text), the processor falls back to a full re-parse.
- Queries are Tree-sitter queries (`.scm`) loaded from disk, and capture names are mapped to
  `StyleId` by the host.
