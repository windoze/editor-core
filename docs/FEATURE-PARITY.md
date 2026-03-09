# Cross-platform feature parity policy

This repository targets “Helix / Sublime-class” editor behavior with **multiple native frontends**
(AppKit/Swift on macOS, WinUI/C++ on Windows, GTK on Linux) sharing a **single Rust core**.

Because different host toolkits have different default behaviors, we treat the Rust workspace as
the **source of truth** for editing semantics.

## What must match across platforms

The following behaviors are expected to be consistent across all frontends:

- **Offsets & coordinates**:
  - API boundaries use Unicode scalar offsets (`char` indices).
  - `(line, column)` columns are `char`-indexed.
  - LSP uses UTF‑16 code units with explicit conversion helpers.
- **Editing semantics**:
  - insert/delete/backspace and newline normalization (CRLF → LF internally)
  - selection and multi-cursor invariants (normalization, primary selection rules)
  - undo/redo grouping and “clean point” semantics
  - line ops, comment toggle, auto-pairs, snippets
- **Search semantics**:
  - find/replace options (case/whole-word/regex) and match ranges (char offsets)
- **Coordinate conversions**:
  - logical ⇄ visual mapping under soft wrap and folding

Frontends **may** differ in:

- keybinding defaults (Cmd vs Ctrl conventions)
- platform-standard menu placements and terminology
- IME plumbing and clipboard integration details

## Where parity is enforced

Parity is enforced by:

- `crates/editor-core/tests/*` — kernel-level semantic tests
- `crates/editor-core-ui/tests/*` — UI wrapper invariants (IME mapping, multi-doc orchestration, etc.)
- FFI ABI tests (`crates/editor-core-ffi/tests/*`, `crates/editor-core-ui-ffi/tests/*`) when exposing behaviors across language boundaries

If a frontend observes behavior differences, the desired outcome should be:

1) Add/extend a Rust test that captures the expected semantics.
2) Fix the kernel / shared layer until the test passes.
3) Keep host code thin: it should map events and render, not re-implement semantics.

