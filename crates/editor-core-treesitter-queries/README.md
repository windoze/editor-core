# editor-core-treesitter-queries

Built-in **Tree-sitter query packs** (highlights + folds) for `editor-core` integrations.

This crate is intentionally small and data-oriented:

- ships query strings (`.scm`) as `&'static str`
- provides a registry by pack id (e.g. `"rust"`)
- exposes the matching Tree-sitter `Language` for each pack

It does **not** implement parsing/highlighting itself — see `editor-core-treesitter` for the
incremental processor.

