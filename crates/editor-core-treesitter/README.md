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
use editor_core_treesitter::{TreeSitterProcessor, TreeSitterProcessorConfig};
use tree_sitter_rust::LANGUAGE;

let mut state = EditorStateManager::new("fn main() {}\n", 80);

let config = TreeSitterProcessorConfig::new(LANGUAGE.into(), tree_sitter_rust::HIGHLIGHTS_QUERY)
    .with_default_rust_folds()
    .with_simple_capture_styles([
        ("comment", 1),
        ("string", 2),
        ("type", 3),
        ("function", 4),
    ]);

let mut processor = TreeSitterProcessor::new(config).unwrap();
state.apply_processor(&mut processor).unwrap();
```

## Notes

- Incrementality is driven by `EditorStateManager::last_text_delta()`; if no delta is available (or
  it doesn't match the processor's internal text), the processor falls back to a full re-parse.
- Queries are Tree-sitter queries (`.scm`) and capture names are mapped to `StyleId` by the host.

