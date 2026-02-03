# editor-core (workspace)

Headless editor engine + integrations for building UI-agnostic text editors.

`editor-core` focuses on:

- **State management** (commands, undo/redo, selection state, change notifications)
- **Unicode-aware measurement** (cell widths for CJK/emoji)
- **Coordinate conversions** (char offsets ⇄ line/column ⇄ wrapped “visual” rows; plus UTF-16 for LSP)

The project is intentionally **UI-agnostic**: frontends render from snapshots (`HeadlessGrid`) and
drive edits through the command/state APIs.

## Workspace crates

- `crates/editor-core/` — core headless editor engine (`PieceTable`, `LineIndex`, `LayoutEngine`, snapshots, commands/state).
  - See `crates/editor-core/README.md`
- `crates/editor-core-lsp/` — LSP integration (UTF-16 conversions, semantic tokens decoding, stdio JSON-RPC client/session).
  - See `crates/editor-core-lsp/README.md`
- `crates/editor-core-sublime/` — `.sublime-syntax` highlighting + folding engine (headless output as style intervals + fold regions).
  - See `crates/editor-core-sublime/README.md`
- `crates/editor-core-highlight-simple/` — lightweight regex-based highlighting helpers (JSON/INI/etc).
- `crates/tui-editor/` — runnable TUI demo app (ratatui + crossterm) that wires everything together.

## Key concepts (TL;DR)

### Offsets and coordinates

The editor consistently uses **character offsets** (Rust `char` indices) at API boundaries:

- **Character offset**: index into the whole document in Unicode scalar values (not bytes).
- **Logical position**: `(line, column)` where `column` is also counted in `char`s.
- **Visual position**: after **soft wrapping** (and optional folding), a single logical line can map
  to multiple visual rows.
- **LSP positions**: `(line, character)` where `character` is **UTF-16 code units** (see `editor-core-lsp`).

This project does *not* currently model “cursor movement by grapheme cluster” (e.g. family emoji
sequences are multiple `char`s). Many editors choose grapheme-cluster-aware movement; if you need
that, you can layer it in your command logic.

### “Text grid” snapshots (rendering input)

Frontends render from `HeadlessGrid`:

- A snapshot contains a list of **visual lines**.
- Each line is a list of **cells** where `Cell.width` is typically `1` or `2` (Unicode-aware).
- Each cell carries a list of `StyleId`s; the UI/theme layer maps `StyleId` → colors/fonts.

### Derived state pipeline (highlighting / folding)

Derived metadata (semantic tokens, syntax highlighting, folding ranges, diagnostics overlays, …) is
represented as editor edits of **derived state**:

- `DocumentProcessor` computes a list of `ProcessingEdit`s.
- `EditorStateManager::apply_processing_edits` applies them (replacing style layers, folding regions, …).

This makes high-level integrations composable and keeps the core engine UI-agnostic.

## Quick start

### Requirements

- Rust **1.91+** (see `rust-version` in the workspace `Cargo.toml`)

### Build and test

```bash
cargo build
cargo test
```

Run the main `editor-core` integration test only:

```bash
cargo test -p editor-core --test integration_test
```

### Run the TUI demo

```bash
cargo run -p tui-editor -- crates/editor-core/tests/fixtures/demo_file.txt
```

The TUI demo supports:

- soft wrapping + Unicode width
- selection, multi-cursor, rectangular selection
- find/replace
- optional highlighting/folding via Sublime syntax or LSP

#### Optional: Sublime `.sublime-syntax`

If the current directory contains a matching `.sublime-syntax` file (example: `Rust.sublime-syntax`
or `TOML.sublime-syntax`), `tui-editor` will auto-enable `editor-core-sublime` highlighting and folding.
Otherwise it falls back to the built-in regex highlighter for simple formats (JSON/INI).

#### Optional: LSP (stdio JSON-RPC)

The demo can connect to any stdio LSP server.

- Default behavior: when opening a `.rs` file, it will try to start `rust-analyzer` (if installed).
- Override via env vars (applies to all file types):

```bash
# Example: Python
EDITOR_CORE_LSP_CMD=pylsp \
EDITOR_CORE_LSP_LANGUAGE_ID=python \
cargo run -p tui-editor -- foo.py
```

Additional env vars:

- `EDITOR_CORE_LSP_ARGS` — whitespace-separated args passed to the LSP server
- `EDITOR_CORE_LSP_ROOT` — override workspace root for LSP initialization

## Using `editor-core` as a library

The recommended entry point for most apps is `EditorStateManager`:

- it wraps `CommandExecutor` + `EditorCore`
- it tracks `version` + `is_modified`
- it emits change notifications
- it provides viewport/snapshot helpers

### Minimal editing + rendering loop

```rust
use editor_core::{Command, EditCommand, EditorStateManager};

let mut state = EditorStateManager::new("Hello\nWorld\n", 80);

// Apply an edit via the command interface.
state.execute(Command::Edit(EditCommand::Insert {
    offset: 0,
    text: "Title: ".to_string(),
})).unwrap();

// Render a viewport snapshot (visual lines).
let grid = state.get_viewport_content_styled(0, 20);
assert!(grid.actual_line_count() > 0);
```

### Add derived highlighting (simple formats)

```rust
use editor_core::EditorStateManager;
use editor_core_highlight_simple::{RegexHighlightProcessor, SimpleJsonStyles};

let mut state = EditorStateManager::new(r#"{ "k": 1, "ok": true }"#, 80);

let mut processor =
    RegexHighlightProcessor::json_default(SimpleJsonStyles::default()).unwrap();
state.apply_processor(&mut processor).unwrap();

let grid = state.get_viewport_content_styled(0, 10);
assert!(grid.lines[0].cells.iter().any(|c| !c.styles.is_empty()));
```

For richer syntax highlighting and folding, use:

- `editor-core-sublime` (`SublimeProcessor`)
- `editor-core-lsp` (`LspSession`)

## Documentation

- Design: `docs/DESIGN.md`
- API docs: `cargo doc --no-deps --open`
- Examples:
  - `cargo run -p editor-core --example command_interface`
  - `cargo run -p editor-core --example state_management`

## Development notes

Common commands:

```bash
cargo fmt
cargo clippy --all-targets --all-features
```

Repo layout highlights:

- `crates/editor-core/src/` — storage/index/layout/intervals/snapshot + command/state layers
- `crates/*/tests/` — stage validations and integration tests

## License

Licensed under either of

* Apache License, Version 2.0,(LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0)
* MIT license (LICENSE-MIT or http://opensource.org/licenses/MIT) at your option.