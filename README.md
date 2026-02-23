# editor-core

Headless editor engine + integrations for building UI-agnostic text editors.

`editor-core` focuses on:

- **State management** (commands, undo/redo, selection state, change notifications)
- **Unicode-aware measurement** (cell widths for CJK/emoji)
- **Coordinate conversions** (char offsets ⇄ line/column ⇄ wrapped “visual” rows; plus UTF-16 for LSP)

The project is intentionally **UI-agnostic**: frontends render from snapshots (`HeadlessGrid`) and
drive edits through the command/state APIs.

## Workspace crates (Rust/Cargo workspace)

> Note: this section lists the crates in this repository’s **Cargo workspace**. The editor’s
> multi-buffer model is the `editor_core::Workspace` type (see “Workspace model” below).

- `crates/editor-core/` — core headless editor engine (`PieceTable`, `LineIndex`, `LayoutEngine`, snapshots, commands/state).
  - See `crates/editor-core/README.md`
- `crates/editor-core-lang/` — lightweight language configs (e.g. comment tokens) for kernel features.
- `crates/editor-core-lsp/` — LSP integration (UTF-16 conversions, semantic tokens decoding, stdio JSON-RPC client/session).
  - See `crates/editor-core-lsp/README.md`
- `crates/editor-core-sublime/` — `.sublime-syntax` highlighting + folding engine (headless output as style intervals + fold regions).
  - See `crates/editor-core-sublime/README.md`
- `crates/editor-core-treesitter/` — Tree-sitter integration (incremental parsing → highlighting + folding).
  - See `crates/editor-core-treesitter/README.md`
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

The canonical coordinate model is still `char`-indexed (Unicode scalar values), but the kernel
also includes grapheme/word-aware cursor and delete commands (UAX #29). This means host UIs can
opt into “move by grapheme/word” behavior without introducing a separate coordinate space.

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

### Workspace model (buffers + views)

Full editors typically need more than “one document, one viewport”. `editor-core` provides an
optional `Workspace` model with two core concepts:

- **Buffer**: document text + undo/redo + derived metadata tied to the text (styles, folding,
  diagnostics, decorations, symbols…).
- **View**: per-viewport state like selections/cursors, wrap width/mode, and scroll position.

In `editor_core::Workspace`, commands are executed **against a `ViewId`**. Text edits are applied
to the underlying buffer, and any resulting `TextDelta` is broadcast to all views of that buffer
(so split panes stay consistent).

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

There are two primary entry points, depending on whether you need multi-buffer/multi-view:

- **Single-buffer / single-view**: `EditorStateManager`
  - ergonomic wrapper around a `CommandExecutor`
  - adds `version`, `is_modified`, and change notifications
  - convenient for simple apps, tests, and “one file open” tools
- **Multi-buffer / multi-view (split panes)**: `Workspace`
  - owns multiple buffers and multiple views per buffer
  - routes commands via `Workspace::execute(view_id, Command)`
  - exposes buffer-wide utilities like search and applying multi-buffer edits (useful for LSP)

If you’re building a “single document” editor (or a code editor widget embedded in a larger app),
start with `EditorStateManager`. If you need tabs/split panes/multi-file operations, use
`Workspace` and treat each `ViewId` as a UI viewport.

### Minimal editing + rendering loop (single view)

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

### Minimal multi-view editing (Workspace)

```rust
use editor_core::{Command, CursorCommand, EditCommand, Workspace};

let mut ws = Workspace::new();
let opened = ws
    .open_buffer(Some("file:///demo.txt".to_string()), "Hello\nWorld\n", 80)
    .unwrap();

let view = opened.view_id;
ws.execute(view, Command::Cursor(CursorCommand::MoveTo { line: 1, column: 0 }))
    .unwrap();
ws.execute(view, Command::Edit(EditCommand::InsertText { text: ">> ".into() }))
    .unwrap();

let grid = ws.get_viewport_content_styled(view, 0, 20).unwrap();
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
- `editor-core-treesitter` (`TreeSitterProcessor`)
- `editor-core-lsp` (`LspSession`)

## Documentation

- Design: `docs/DESIGN.md`
- API docs: `cargo doc --no-deps --open`
- Examples:
  - `cargo run -p editor-core --example command_interface`
  - `cargo run -p editor-core --example multiview_workspace`
  - `cargo run -p editor-core --example workspace_search_apply`
  - `cargo run -p editor-core --example state_management`
  - `cargo run -p editor-core --example performance_milestones`

### Performance benches

`editor-core` includes a small criterion benchmark suite for large-file/open/typing/viewport paths:

```bash
cargo bench -p editor-core --bench performance
```

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
