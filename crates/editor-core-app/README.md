# `editor-core-app`

UI-agnostic “editor application shell” primitives built on top of `editor-core`.

This crate intentionally does **not** implement widgets or platform integration. Instead, it
provides shared logic that editor frontends typically need:

- workspace filesystem traversal (file index / quick-open building blocks)
- fuzzy matching helpers (command palette / go-to-file)

## Example

List and fuzzy-search workspace files:

```bash
cargo run -p editor-core-app --example workspace_file_index -- . main
```

