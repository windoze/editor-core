# `editor-core-app`

UI-agnostic “editor application shell” primitives built on top of `editor-core`.

This crate intentionally does **not** implement widgets or platform integration. Instead, it
provides shared logic that editor frontends typically need:

- workspace filesystem traversal (file index / quick-open building blocks)
- file explorer helpers (tree-like directory listing + “reveal in tree” segments)
- find-in-files across a workspace (ignore-aware)
- save flows wiring for `editor_core::Workspace` (save / save-as / save-all, atomic write)
- sessions + recents (including optional “hot exit” snapshots with undo/redo restore)
- a lightweight command palette model (fuzzy filter)
- status bar info helper (path/pos/selection/indent)
- pane/window focus model (split + focus cycling building blocks)
- in-memory log buffer + JSONL export (observability)
- anchored search results model (stable under edits via `TextDelta`)

## Example

List and fuzzy-search workspace files:

```bash
cargo run -p editor-core-app --example workspace_file_index -- . main
```

Search across workspace files (ignore-aware):

```bash
cargo run -p editor-core-app --example workspace_find_in_files -- . TODO
```
