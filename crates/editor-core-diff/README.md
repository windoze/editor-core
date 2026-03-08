# editor-core-diff

Line-based diff and hunk primitives for the `editor-core` workspace.

This crate is intended to power editor features like:

- “modified lines” gutter indicators (diff current buffer vs. baseline)
- diff views / merge editors (UI aside)

It is **UI-agnostic** and returns **line-indexed hunks** plus per-line change records.

## Quick start

```rust
use editor_core_diff::{diff_line_hunks, LineDiffConfig};

let before = "a\nb\nc\n";
let after = "a\nb\nx\nc\n";

let hunks = diff_line_hunks(before, after, LineDiffConfig::default());
assert_eq!(hunks.len(), 1);
assert!(hunks[0].lines.iter().any(|l| l.kind.is_change()));
```

## Notes

- Lines include their newline (`\n`) when present, matching typical unified diff formatting.
- Internally this is powered by `imara-diff` (Histogram / Myers algorithms).

