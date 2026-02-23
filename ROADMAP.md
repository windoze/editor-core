# editor-core — Roadmap (Headless Kernel Parity)

This roadmap targets **headless / UI-agnostic** editor-kernel capabilities commonly expected in
mainstream editors (VS Code, Helix, Zed, Neovim), while keeping **rendering, keybinding/UI
widgets, and scripting/plugin hosts** out of scope.

The focus is: a solid kernel that frontends can drive via **command/state APIs**, and render via
**snapshots**.

## Scope and non-goals

### In scope (kernel-level)

- Text model, undo/redo, selections, cursor movement, wrapping and coordinate conversions.
- Structured change events (for incremental consumers like LSP).
- Derived metadata models and application (styles, folding, diagnostics, decorations).
- Workspace/multi-document orchestration at the kernel boundary (host still owns file I/O).
- Headless integration helpers (e.g. LSP bridging) that feed into the kernel derived-state model.

### Out of scope (explicit)

- UI: rendering, theme engines, compositor, widgets, keybinding resolution.
- Scriptability/plugin hosting: supported indirectly via the command/state interface.
- **Multi-encoding internal storage**: host is expected to decode/encode; kernel stays UTF-8.
- **Collaboration/CRDT**: intentionally out of scope for this project’s goals.

## Current baseline (already implemented)

The workspace already provides:

- Storage/index/layout: piece table (`PieceTable`), rope line index (`LineIndex`), soft wrap
  (`LayoutEngine`) and logical↔visual coordinate mapping (wrap + folding aware).
- Editing: multi-cursor + rectangular selection, undo/redo + grouping + clean point,
  indentation primitives, Unicode segmentation (grapheme/word) commands.
- Derived state: style layers + folding regions, first-class diagnostics model, decorations model.
- Snapshots: `HeadlessGrid` text-grid snapshots with Unicode-aware cell widths.
- Multi-document + split panes: `Workspace` with `BufferId` (documents) + `ViewId` (views), plus
  optional URI mapping.
- LSP utilities: UTF-16 conversions, `didChange` delta calculation, semantic tokens, folding,
  diagnostics, inlay hints, multi-document workspace sync + workspace edits.

## Prioritization method

Each item below is ranked by:

- **Popularity**: how often users expect it from mainstream editor UX.
- **Complexity**: implementation risk/effort *within this architecture*.
  - `S` = local feature/additive API
  - `M` = touches multiple subsystems or requires careful invariants
  - `L` = substantial refactor/new subsystem
  - `XL` = deep architectural shift or sustained performance work

“Priority” is therefore not strictly “most complex first”: high-popularity + low/medium-complexity
features come earlier.

---

## P0 — High-popularity, low/medium complexity (recommended next)

### P0.1: Expand the kernel command surface (line/selection ops)

- **Popularity**: High
- **Complexity**: `M`
- **Where**: `crates/editor-core` (`commands.rs` + tests)

Add first-class commands that mainstream editors provide out of the box, implemented as
compositions of existing primitives (but still exposed as stable commands so hosts don’t
re-implement them inconsistently):

- Line ops: duplicate line(s), delete line(s), move line(s) up/down, join lines, split line.
- Selection ops: select line, select word, expand selection (basic), add cursor above/below.
- Multi-cursor match ops: “add next occurrence”, “add all occurrences” (selection-driven).

**DoD**

- All operations work with multi-cursor + rectangular selection.
- Correct undo grouping and clean-point behavior.
- Deterministic integration tests under `crates/editor-core/tests/`.

### P0.2: Comment toggling primitives (language-config driven)

- **Popularity**: High
- **Complexity**: `M`
- **Where**: likely a new small crate (e.g. `crates/editor-core-lang`) + kernel command(s)

Add a headless comment toggling facility that accepts a **language comment config**:

- Line comment token (e.g. `//`, `#`)
- Block comment tokens (e.g. `/* */`) if applicable

The kernel should implement toggling semantics over selections/lines, while language-specific
rules remain data-driven.

**DoD**

- Handles empty selection (current line) and multi-line selections.
- Stable behavior with multiple cursors.
- No UI assumptions (gutter, virtual text, etc.).

### P0.3: Folding stability under text edits (derived vs user folds)

- **Popularity**: High
- **Complexity**: `M`
- **Where**: `crates/editor-core` (`intervals.rs`, command executor)

Today folding is primarily “derived state” refreshed from external providers. Mainstream editors
also support **user folds** that should remain stable across edits.

Proposed direction:

- Maintain two fold sources:
  - **Derived folds** (replaced wholesale by processors like LSP/Sublime/Tree-sitter).
  - **User folds** (explicit user commands) that shift with newline edits.
- Preserve collapsed state across derived fold recomputation where possible.

**DoD**

- User-created folds remain correct after inserting/deleting newlines above/inside regions.
- Derived folds can still be replaced/cleared as before.

### P0.4: Open-buffer workspace utilities (search + apply)

- **Popularity**: High
- **Complexity**: `M`
- **Where**: `crates/editor-core` (`workspace.rs` + new APIs)

Provide headless workspace operations over **open documents** (no file I/O):

- Search across all open documents (regex/options consistent with existing search).
- Apply workspace-wide edits with a consistent event model and undo grouping (per-document).

**DoD**

- Fast enough for “dozens of open buffers”.
- Clear API contracts around ordering and change notifications.

### P0.5: Fill LSP-to-kernel “bridges” for common UX features

- **Popularity**: High
- **Complexity**: `S`–`M`
- **Where**: `crates/editor-core-lsp` + `crates/editor-core`

Add helpers that convert common LSP responses into kernel-derived-state edits:

- Document highlights (`textDocument/documentHighlight`) → style layer
- Document links (`textDocument/documentLink`) → decorations
- Code lens (`textDocument/codeLens`) → decorations
- Completion apply helpers:
  - apply `additionalTextEdits`
  - handle snippet-shaped inserts (actual snippet engine is P1)

**DoD**

- Conversion APIs are dependency-light (`serde_json::Value` based, consistent with the crate).
- Output is expressed as `ProcessingEdit` and/or kernel edit commands.

---

## P1 — High-popularity, high complexity (major capabilities)

### P1.1: Separate Buffer vs View (enables split panes, multiple cursors per view)

- **Popularity**: High
- **Complexity**: `XL`
- **Where**: `crates/editor-core` (new core types + refactor `Workspace`)

Mainstream editors model:

- **Buffer**: document text, undo history, derived metadata tied to the text.
- **View**: selections/cursors, scroll position, wrap width, viewport configuration.

Historically, `editor-core`’s ergonomic APIs bundled “document + view” too tightly (an
`EditorStateManager` acts like both). The `Workspace` model separates them so hosts can build:

- split panes and multiple views into the same buffer
- per-view wrap width, folding visibility preferences, and independent cursors

**Status: done** (implemented in `crates/editor-core/src/workspace.rs`)

Implementation shape:

- Introduce `BufferId` and `ViewId`.
- Workspace owns buffers; views reference buffers.
- Keep an ergonomic “single-buffer single-view” wrapper for simple apps.

**DoD**

- Two views can render different viewports of the same buffer with independent selections/scroll.
- Edits are applied to the buffer; both views observe consistent `TextDelta` events.

### P1.2: Decoration-aware snapshot composition (virtual text layout)

- **Popularity**: High (VS Code/Zed class)
- **Complexity**: `L`
- **Where**: `crates/editor-core` (`snapshot.rs`, layout integration)

Decorations exist as data, but snapshots don’t compose them into what a UI can render without
re-implementing layout rules.

Add an optional snapshot path that can:

- inject “virtual text” (inlay hints, code lens) into the rendered grid
- preserve correct coordinate mapping between document offsets and visual x/row

**DoD**

- Host can render inlay hints/code lens from snapshot data without custom layout logic.
- Cursor movement/editing still operates on the underlying document offsets correctly.

### P1.3: Tree-sitter integration crate (highlighting, folding, structural selection)

- **Popularity**: High (Helix/Zed/Neovim ecosystems)
- **Complexity**: `XL`
- **Where**: new crate, e.g. `crates/editor-core-treesitter`

Provide an offline, incremental parsing pipeline that can generate:

- highlight intervals (style layer)
- fold regions (derived folds)
- structural selection expansion primitives (optional)

**DoD**

- Incremental updates based on `TextDelta` (avoid full reparse on every keystroke where possible).
- Deterministic tests with fixture files.

### P1.4: Symbols/outline data model + indexing hooks

- **Popularity**: High
- **Complexity**: `M`–`L`
- **Where**: `crates/editor-core` + `crates/editor-core-lsp`

Add a first-class, UI-agnostic model for:

- document outline (document symbols)
- workspace symbol search results (optionally cached/indexed)

LSP helpers should parse `documentSymbol` / `workspace/symbol` into this model.

**DoD**

- Stable query APIs for hosts (tree view, fuzzy search) without forcing host-defined schemas.

### P1.5: Large-file performance and incrementality milestones

- **Popularity**: High (practical adoption blocker)
- **Complexity**: `XL`
- **Where**: `crates/editor-core` (+ benches)

Set explicit targets and evolve internals to avoid “rebuild everything” hot paths:

- incremental rope updates (avoid full `get_text()` rebuilds)
- incremental layout invalidation (reflow only affected logical lines)
- snapshot generation that streams visible lines without reconstructing large intermediate strings

**DoD**

- Add `criterion` benches (or lightweight internal benches) for:
  - large file open
  - typing in the middle
  - viewport render of a small slice
- Demonstrate improvements on representative fixtures.

---

## P2 — Power features (optional / later)

### P2.1: Undo tree (branching history)

- **Popularity**: Medium (Neovim power feature)
- **Complexity**: `L`
- **Where**: `crates/editor-core`

### P2.2: Marks/bookmarks + jump list

- **Popularity**: Medium
- **Complexity**: `M`
- **Where**: `crates/editor-core`

### P2.3: Diff/hunk computation primitives (headless)

- **Popularity**: Medium-High
- **Complexity**: `L`
- **Where**: new crate, e.g. `crates/editor-core-diff`

Provide headless diff building blocks for:

- changed-line gutters
- diff/merge views (UI out of scope, hunks are not)

### P2.4: Persistence hooks for undo / view state

- **Popularity**: Medium
- **Complexity**: `M`
- **Where**: `crates/editor-core` + host integration

---

## Suggested “next PRs” (smallest high-leverage sequence)

1. **Kernel command pack v1** (P0.1): duplicate/move/join line(s), select line/word, add cursor above/below.
2. **Multi-cursor match selection** (P0.1): add next/all occurrences + tests.
3. **Comment toggling** (P0.2): language-config driven primitives + tests.
4. **Folding stability** (P0.3): user folds that shift on edits + derived fold preservation policy.
5. **Workspace search across open docs** (P0.4): APIs + tests.
6. **LSP bridges v1** (P0.5): document highlights + links + code lens → derived-state edits.
