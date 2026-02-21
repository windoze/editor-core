# editor-core — Missing Features (Proposal)

This document lists **kernel-level** features that are commonly required by a “full-featured” code
editor (VS Code / Sublime / Neovim class), but are **not yet fully covered** by the current
`editor-core` workspace.

It is intentionally written from the perspective of a **headless editor engine**:

- If a feature is purely UI (widgets, themes, compositor), it is called out as **out of scope**.
- If a feature needs a stable data model in the kernel but is rendered by the host, it is listed
  as **kernel + host**.
- If a feature can live entirely as an integration (`editor-core-*` processor), it is listed as
  **integration**.

The goal is to provide an actionable **roadmap** without starting implementation work.

## Status tracker

Legend:

- `planned` — identified gap, no implementation yet
- `in_progress` — partially implemented / API draft in flight
- `done` — implemented + tested in this repo

| ID | Feature | Scope | Status | Notes |
|---|---|---|---|---|
| P0-1 | Multi-document / workspace model | kernel + host | done | `Workspace` + `DocumentId` with optional uri mapping; host still owns file I/O + view composition. |
| P0-2 | Structured `TextDelta` events | kernel | done | Implemented as `TextDelta` + `StateChange.text_delta` with tests. |
| P0-3 | Consistent line-ending model (CRLF/LF) | kernel + host | done | Normalize `\\r\\n`/`\\r` → `\\n` internally; track save preference via `LineEnding`. |
| P0-4 | Visual-row cursor movement (wrap + folding aware) | kernel | done | Added visual movement commands + wrap/fold mapping with tests. |
| P0-5 | Wrap modes (char/word) + wrapped indent | kernel | done | `WrapMode` + `WrapIndent` + `ViewCommand::{SetWrapMode, SetWrapIndent}` with tests. |
| P0-6 | Unicode segmentation for UX (graphemes/words) | kernel | done | `CursorCommand::{MoveGrapheme*, MoveWord*}` + `EditCommand::{DeleteGrapheme*, DeleteWord*}` with tests. |
| P0-7 | Indentation / whitespace primitives | kernel | done | `EditCommand::{InsertNewline{auto_indent}, Indent, Outdent, DeleteToPrevTabStop}` + tests. |
| P1-8 | First-class diagnostics model | kernel + integration | done | `Diagnostic` model + `ProcessingEdit::{ReplaceDiagnostics, ClearDiagnostics}`; LSP publishDiagnostics populates both styles and data. |
| P1-9 | Decorations model (inlay hints, code lens, links, match highlights) | kernel + integration | done | `Decoration*` model + `ProcessingEdit::{ReplaceDecorations, ClearDecorations}`. |
| P1-10 | Multi-document LSP sync + workspace edits | integration + kernel workspace | planned | Route per-doc state and apply workspace edits reliably. |

## Current coverage (what already exists)

From a quick pass over the current code:

- **Text storage**: `PieceTable` (`crates/editor-core/src/storage.rs`)
- **Line indexing & conversions**: `LineIndex` based on `ropey` (`crates/editor-core/src/line_index.rs`)
- **Layout / soft wrapping** with Unicode cell widths + tab width expansion:
  `LayoutEngine` (`crates/editor-core/src/layout.rs`)
- **Selections**: primary + secondary selections (multi-cursor) + rectangular selection:
  `Selection`, `CursorCommand` (`crates/editor-core/src/commands.rs`)
- **Editing**: insert/delete/replace, multi-caret typing (`InsertText`), backspace/delete-forward,
  tab insertion policy, undo/redo grouping (`crates/editor-core/src/commands.rs`)
- **Search**: forward/backward find + replace current/all with regex support:
  `crates/editor-core/src/search.rs` and edit commands
- **Derived state pipeline**: `DocumentProcessor` → `ProcessingEdit` for style layers + folding:
  `crates/editor-core/src/processing.rs`
- **Highlighting / folding integrations**:
  - regex highlighter (`crates/editor-core-highlight-simple/`)
  - Sublime `.sublime-syntax` highlighting + folding (`crates/editor-core-sublime/`)
  - LSP session utilities, including semantic tokens, folding, and diagnostics-as-style overlays
    (`crates/editor-core-lsp/`)
- **Headless snapshots**: `HeadlessGrid` / `Cell { ch, width, styles }` (`crates/editor-core/src/snapshot.rs`)

The missing items below are about moving from “solid kernel demo” to “kernel that can back a
full editor UX with minimal host-side reinvention”.

## P0 — Foundational kernel gaps (recommended first)

### 1) Multi-document / workspace model

**Status: done**

**What’s missing**

The core API surface is fundamentally “one editor = one document”. A full editor typically needs:

- multiple open buffers (some modified, some read-only)
- stable document identities (URI/path + internal `DocumentId`)
- workspace-wide operations (multi-file search, rename apply across files, etc.)
- per-document derived state + per-document view state

**Why it matters**

Without a workspace model, host apps tend to re-implement a second “editor manager” layer, and
integration crates (notably LSP) can’t naturally coordinate edits across multiple open documents.

**What’s implemented**

In `editor-core`:

- `Workspace` container that manages multiple open documents as `EditorStateManager`s
- `DocumentId` as a stable, opaque handle
- optional `uri -> DocumentId` mapping for integrations (e.g. LSP)
- a host-driven “active document” convenience slot

**Notes / still host-driven**

- File I/O (load/save, change detection) remains outside the kernel.
- Split views of the same document are not modeled yet (workspace currently treats each
  `EditorStateManager` as a “document + view” bundle).

---

### 2) Structured “text delta” events for incremental consumers

**What’s missing**

`EditorStateManager` provides `StateChange { change_type, affected_region }`, but it does not
expose a durable edit description such as:

- exact ranges inserted/deleted/replaced
- inserted text (and/or deleted text)
- per-selection edits for multi-caret typing
- a stable edit grouping id

**Why it matters**

Full editors typically have incremental consumers that *must* react to edits efficiently:

- LSP `textDocument/didChange` (range edits)
- incremental parsers / tree-sitter-like pipelines
- incremental indexing (symbols, outline)
- search match highlighting maintenance

Without deltas, every consumer is forced into “diff old/new text”, which is expensive and
error-prone.

**Proposal (kernel)**

- Define a single edit record type emitted by the command executor:
  - `TextDelta { before_version, after_version, edits: Vec<TextEditDelta>, group_id, ... }`
  - `TextEditDelta` should be in **character offsets**, and optionally include cached byte offsets
    for convenience.
- Extend `StateChange` (or add a new callback type) to carry the delta on
  `StateChangeType::DocumentModified`.
- Ensure the delta model is compatible with multi-caret edits:
  - either store all edits in **descending offset order** (how the executor applies them today),
    or store them as “original document coordinates” + a canonical application order.

**Notes**

This is a high leverage addition that makes many “full editor” features feasible as processors
without re-diffing.

---

### 3) Consistent line-ending model (CRLF/LF) + save semantics

**What’s missing / risky today**

Some code paths strip trailing `'\r'` when splitting or reading lines (e.g.
`split_lines_preserve_trailing`, `LineIndex::get_line_text`), but the underlying coordinate model
still counts `'\r'` as a character in several conversions.

That can lead to subtle inconsistencies:

- cursor columns that can land “inside” the `'\r'` of a CRLF line ending
- layout computations that don’t agree with char-offset conversions on CRLF inputs
- round-tripping file contents with CRLF may not preserve exact content

**Why it matters**

Line-ending handling is a classic “paper cut” that becomes a correctness issue in:

- LSP position mapping
- multi-cursor edits on Windows-style files
- exact save / diff workflows

**Proposal (kernel + host)**

Pick and document one of these strategies:

1. **Normalize-on-load (recommended)**:
   - Convert CRLF → LF internally.
   - Track `LineEnding` preference (`LF`/`CRLF`) as document metadata for saving.
2. **Preserve exact bytes**:
   - Treat `\r\n` as a single logical newline in the coordinate model.
   - Requires a more complex indexing/conversion layer.

For most editors, (1) is simpler and matches common practice.

---

### 4) Visual-line-aware cursor movement (wrap + folding aware)

**What’s missing**

The current command set supports:

- `MoveTo { line, column }` (logical)
- `MoveBy { delta_line, delta_column }` (logical)

A full editor with soft wrapping and folded regions typically needs built-in movement primitives:

- move up/down by **visual rows** (wrap segments)
- “preferred x” tracking in **cells** (sticky column) across short lines and wide glyphs
- home/end variants (logical line vs visual segment)
- page up/down and viewport-relative navigation

**Why it matters**

If the kernel doesn’t provide these semantics, every host must re-implement them and keep them
consistent with the kernel’s wrap/fold mapping, which is fragile.

**Proposal (kernel)**

- Add cursor commands that operate in **visual coordinates**:
  - `MoveVisualBy { delta_rows: isize }`
  - `MoveToVisual { row: usize, x_cells: usize }`
  - `MoveToLineStart/End` (logical) and `MoveToVisualLineStart/End` (segment)
- Store a per-view “preferred x in cells” in a view-state struct (see workspace proposal).

---

### 5) Word wrap modes (character-wrap vs word-wrap) + wrapped-line indentation

**Status: done**

**What’s missing**

`LayoutEngine` wraps based on cell width and character boundaries. Full editors often support:

- `wrap_mode: None | Char | Word`
- optional hanging indent for wrapped continuations
- configurable wrap column / viewport width interactions

**Why it matters**

For code editing, word-wrap and wrapped indentation dramatically improve readability, especially
with comments/docstrings and long strings.

**Proposal (kernel)**

- Extend `LayoutEngine` with a `WrapMode`:
  - `Char`: current behavior
  - `Word`: prefer wrapping at whitespace/punctuation boundaries
- Add an optional `wrapped_indent` policy:
  - `None`
  - `SameAsLineIndent` (measure leading whitespace)
  - `FixedCells(n)`

**Notes**

This stays UI-agnostic: it only changes how visual rows are computed.

---

### 6) Unicode segmentation for editor UX (graphemes + words)

**Status: done**

**What’s missing**

The kernel’s API coordinate is `char` offsets / columns (Unicode scalar values). That’s a solid
baseline, but full editor UX commonly expects:

- grapheme-cluster-aware cursor movement and deletion
  - e.g., “👨‍👩‍👧‍👦” should behave like one unit for arrow/backspace in many editors
- Unicode-aware word boundaries for:
  - `Ctrl+Left/Right`, `Alt+Backspace`, “select word”
  - whole-word search (today it’s ASCII-ish: alnum + `_`)

**Why it matters**

This is one of the most visible “feels like a real editor” differences, especially for non-English
text and emoji-heavy content.

**Proposal (kernel + host)**

Keep the **storage/index/layout** layers char-based, but add an optional UX layer:

- Introduce a `TextSegmentation` trait (or feature-flagged module) that provides:
  - `prev_grapheme_boundary(offset)`, `next_grapheme_boundary(offset)`
  - `prev_word_boundary(offset)`, `next_word_boundary(offset)`
- Add new cursor/edit commands that use those boundaries:
  - `MoveWordLeft/Right`, `DeleteWordBack/Forward`, `SelectWord`, etc.

This allows hosts to opt into `unicode-segmentation` without forcing it into the minimal kernel.

---

### 7) Indentation / whitespace editing primitives

**Status: done**

**What’s missing**

Beyond inserting tabs/spaces, a full editor needs indentation primitives that are consistent across
multi-cursor edits and selection sets:

- `IndentSelection` / `OutdentSelection`
- auto-indent on newline (basic “copy previous line indent”)
- “smart backspace” (delete to previous tab stop in leading whitespace)
- convert indentation (tabs ↔ spaces) for a range / whole document

**Why it matters**

These features are used constantly and are very hard to implement correctly in UI code when
selections, virtual space, and wrapping are involved.

**Proposal (kernel)**

- Add edit commands:
  - `InsertNewline { auto_indent: bool }`
  - `Indent { mode: IndentMode }` / `Outdent { mode: IndentMode }`
  - `DeleteToPrevTabStop`
- Keep the indentation rule engine minimal by default (“copy whitespace prefix”), but define an
  extension point for language-specific indentation (integration or host).

## P1 — Derived metadata beyond “styles and folds”

### 8) First-class diagnostics (not just style overlays)

**Status: done**

**What exists today**

`editor-core-lsp` can convert diagnostics into a style layer (`StyleLayerId::DIAGNOSTICS`), which
is great for underlines.

**What’s implemented**

In `editor-core`:

- `diagnostics` module with a stable, UI-agnostic `Diagnostic` data model
- `EditorCore.diagnostics: Vec<Diagnostic>` + query API
- `ProcessingEdit::{ReplaceDiagnostics, ClearDiagnostics}` + `StateChangeType::DiagnosticsChanged`

In `editor-core-lsp`:

- `publishDiagnostics` is converted into both:
  - underline intervals in `StyleLayerId::DIAGNOSTICS`
  - structured diagnostics in the editor state

Rendering remains host-driven (gutter markers, Problems panel, tooltips, etc.).

---

### 9) Inline decorations: inlay hints, code lens, links, search highlights

**Status: done**

**What’s missing**

These are ubiquitous in modern editors:

- LSP inlay hints (inline type hints)
- code lens (inline actionable text)
- document links (clickable paths/URLs)
- “highlight all matches” for current selection / search query
- selection match / bracket match highlighting

Today, the derived-state model is limited to:

- style intervals (good for coloring/underlines)
- folding regions

That’s insufficient to represent inline text that does not exist in the document (virtual text).

**What’s implemented**

In `editor-core`:

- `decorations` module with:
  - `DecorationLayerId` (layered sources, similar to style layers)
  - `Decoration { range, placement, kind, text, styles, ... }`
- `ProcessingEdit::{ReplaceDecorations, ClearDecorations}` and `StateChangeType::DecorationsChanged`

Notes:

- Decorations are stored and exposed to the host, but do **not** mutate the document text.
- Rendering (inline virtual text layout, click handling, tooltips) remains host-driven.

## P1 — LSP + tooling ergonomics

### 10) Multi-document LSP synchronization and workspace edits

**What exists today**

`editor-core-lsp` has:

- a single-document `LspSession` that drives didOpen/didChange for one URI
- helpers to parse/apply `TextEdit` / `WorkspaceEdit` payloads

**What’s missing for a full editor**

- managing multiple open documents in one LSP session:
  - open/close per doc
  - per-doc versions
  - per-doc semantic tokens / folding / diagnostics
- applying workspace edits across many documents (some not open yet)
- consistent policy hooks for server->client requests that require UI input

**Proposal (integration + kernel workspace model)**

Once a `Workspace`/multi-document model exists in the kernel, add an LSP wrapper that:

- tracks a map of `uri -> DocumentId`
- routes notifications/events into the correct document’s derived state
- applies workspace edits by opening/loading documents on demand (host-provided I/O hook)

## P2 — “Power editor” features (optional / later)

### 11) Richer command set (expected in mature editors)

These are not required for the kernel to be “correct”, but they strongly affect UX and reduce host
re-implementation:

- line operations: duplicate line, move line up/down, join lines
- selection operations: select word/line/paragraph, expand selection, add next occurrence
- comment toggling (line/block) with language-aware rules (integration)
- snippet insertion and placeholder navigation (kernel + host)
- bookmarks/marks + jump list (kernel + host)

Proposal: keep the base command enums small, but add a “higher-level command module” that composes
existing primitives and emits structured `TextDelta` output.

### 12) Persistence + file I/O hooks (still UI-agnostic)

Not a UI feature, but beyond the current kernel:

- document metadata: `path/uri`, encoding, line ending preference, read-only flag
- save/load hooks provided by the host, but with kernel-managed `is_modified`/clean points
- file change detection integration points (“file changed on disk” reload workflow)

### 13) Performance and scalability targets (beyond 1k-line demos)

The current architecture is sound, but full editors eventually need:

- more incremental updates (rope/layout/style queries) on large files
- avoiding full-text materialization in hot paths (`get_text()` everywhere)
- snapshot generation that can stream only visible lines without reconstructing large strings

This is mostly about implementation strategy, not API shape, but it’s worth tracking as a “missing
feature” because it impacts feasibility on real codebases.

## Explicit non-goals (for this repo)

Even a “full-featured editor” typically keeps these out of the kernel:

- theme engines, font rendering, pixel layout, GPU rendering
- UI widgets (tabs, minimap, command palette)
- keybinding resolution (except maybe a reference implementation in `tui-editor`)
- async runtimes / threading models (kernel should remain runtime-agnostic)

## Suggested sequencing (if/when this becomes a roadmap)

1. Add **structured `TextDelta`** (unblocks most integrations).
2. Add a **workspace / multi-document** model (unblocks realistic LSP).
3. Fix **line ending normalization** for correctness.
4. Add **visual-row cursor movement** + sticky x for wrap/fold aware UX.
5. Extend derived state beyond styles/folds (diagnostics data + decorations).
