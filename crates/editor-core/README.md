# editor-core

`editor-core` is a **headless** editor engine focused on state management, Unicode-aware text
measurement, and coordinate conversion. It is intentionally UI-agnostic: consumers render from
snapshots and drive edits through the command/state APIs.

## Features

- **Efficient text storage** via a Piece Table (`PieceTable`) for inserts/deletes.
- **Fast line indexing** via a rope-backed `LineIndex` for line access and conversions.
- **Soft wrapping layout** (`LayoutEngine`) with Unicode-aware cell widths.
- **Style + folding metadata** via interval trees (`IntervalTree`) and fold regions (`FoldingManager`).
- **Headless snapshots** (`SnapshotGenerator` → `HeadlessGrid`) for building “text grid” UIs.
- **Command interface** (`CommandExecutor`) and **state/query layer** (`EditorStateManager`).
- **Kernel-level editing commands** for common editor UX:
  - line ops: `DuplicateLines`, `DeleteLines`, `MoveLinesUp/Down`, `JoinLines`, `SplitLine`
  - comment toggling: `ToggleComment` (language-config driven)
  - selection/multi-cursor ops: `SelectLine`, `SelectWord`, `ExpandSelection`, `AddCursorAbove/Below`,
    `AddNextOccurrence`, `AddAllOccurrences`
- **Search utilities** (`find_next`, `find_prev`, `find_all`) operating on character offsets.

## Design overview

`editor-core` is organized as a set of small layers:

- **Storage**: Piece Table holds the document text.
- **Indexing**: `LineIndex` provides line access + offset/position conversions.
- **Layout**: `LayoutEngine` computes wrap points and logical↔visual mappings.
- **Intervals**: styles/folding are represented as ranges and queried efficiently.
- **Snapshots**: a UI-facing “text grid” snapshot (`HeadlessGrid`) can be rendered by any frontend.
- **State/commands**: public APIs for edits, queries, versioning, and change notifications.

### Offsets and coordinates

- Many public APIs use **character offsets** (not byte offsets) for robustness with Unicode.
- Rendering uses **cell widths** (`Cell.width` is typically 1 or 2) to support CJK and emoji.
- There is a distinction between **logical lines** (document lines) and **visual lines**
  (after soft wrapping and/or folding).

### Derived state pipeline

Higher-level integrations (like LSP semantic tokens or syntax highlighting) can compute derived
editor metadata and apply it through:

- `DocumentProcessor` (produce edits)
- `ProcessingEdit` (apply edits)
- `EditorStateManager::apply_processing_edits` (update state consistently)

## Quick start

### Command-driven editing

```rust
use editor_core::{Command, CommandExecutor, CursorCommand, EditCommand, Position};

let mut executor = CommandExecutor::empty(80);

executor.execute(Command::Edit(EditCommand::Insert {
    offset: 0,
    text: "Hello\nWorld".to_string(),
})).unwrap();

executor.execute(Command::Cursor(CursorCommand::MoveTo {
    line: 1,
    column: 2,
})).unwrap();

assert_eq!(executor.editor().cursor_position(), Position::new(1, 2));
```

### State queries + change notifications

```rust
use editor_core::{Command, EditCommand, EditorStateManager, StateChangeType};

let mut manager = EditorStateManager::new("Initial text", 80);
manager.subscribe(|change| {
    println!("change={:?} version {}->{}", change.change_type, change.old_version, change.new_version);
});

manager.execute(Command::Edit(EditCommand::Insert {
    offset: 0,
    text: "New: ".to_string(),
})).unwrap();
assert!(manager.get_document_state().is_modified);

// Manual edits are possible, but callers must preserve invariants and call `mark_modified`.
manager.editor_mut().piece_table.insert(0, "X");
manager.mark_modified(StateChangeType::DocumentModified);
```

## Related crates

- `editor-core-lsp`: LSP integration (UTF-16 conversions, semantic tokens helpers, stdio JSON-RPC).
- `editor-core-sublime`: `.sublime-syntax` highlighting + folding engine.
