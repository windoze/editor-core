# editor-core-sublime

`editor-core-sublime` provides a lightweight `.sublime-syntax` **syntax highlighting + folding**
engine for `editor-core`.

It is intended for headless/editor-kernel usage: it produces style intervals and fold regions that
can be applied to an `EditorStateManager` without requiring any particular UI.

## Features

- Load and compile Sublime Text YAML-based `.sublime-syntax` definitions.
- Supports common Sublime features used for highlighting and folding:
  - contexts, includes, meta scopes
  - basic inheritance via `extends`
  - multi-line context folding
- Highlight documents into:
  - style intervals (`Interval`, in character offsets)
  - fold regions (`FoldRegion`, in logical line ranges)
- Stable mapping between Sublime scopes and editor `StyleId`s via `SublimeScopeMapper`.
- `SublimeProcessor` implements `editor_core::processing::DocumentProcessor` and emits
  `ProcessingEdit` updates (`StyleLayerId::SUBLIME_SYNTAX` + folding edits).

## Design overview

This crate keeps the output format aligned with `editor-core`:

- All interval offsets are **character offsets** (not byte offsets).
- Highlighting produces a “derived state” patch (`ProcessingEdit`) that the host applies to the
  editor state manager.
- Folding regions can optionally preserve user-collapsed state across re-highlighting passes.

The low-level engine is exposed via `highlight_document`, and the high-level integration via
`SublimeProcessor`.

## Quick start

### Add the dependency

```toml
[dependencies]
editor-core = "0.1"
editor-core-sublime = "0.1"
```

### Highlight and apply derived state

```rust
use editor_core::EditorStateManager;
use editor_core::processing::DocumentProcessor;
use editor_core_sublime::{SublimeProcessor, SublimeSyntaxSet};

let mut state = EditorStateManager::new("fn main() {}\n", 80);

// Load a syntax (from YAML, from file, or from a reference via search paths).
let mut set = SublimeSyntaxSet::new();
let syntax = set.load_from_str(r#"
%YAML 1.2
---
name: Minimal Rust
scope: source.rust
contexts:
  main:
    - match: '\\b(fn|let)\\b'
      scope: keyword.control.rust
"#).unwrap();

let mut processor = SublimeProcessor::new(syntax, set);

let edits = processor.process(&state).unwrap();
state.apply_processing_edits(edits);

// Render using `state.get_viewport_content_styled(...)`.
```

## Notes

- `.sublime-syntax` is a large format; this crate focuses on the subset needed for practical
  headless highlighting/folding.
- Use `SublimeScopeMapper` to map `StyleId` values back to scopes for theming.
