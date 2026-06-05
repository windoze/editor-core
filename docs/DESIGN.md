# editor-core — Design Notes

This document explains the internal design of the `editor-core` workspace and how the crates fit
together. It is written for:

- UI/front-end authors integrating the engine
- contributors extending storage/index/layout/derived-state subsystems

If you only need API-level usage, start with the workspace `README.md` and the per-crate READMEs
under `crates/*/README.md`.

## Terminology: “workspace” vs `Workspace`

This repo uses “workspace” in two different senses:

- **Cargo workspace**: the Rust monorepo layout (multiple crates under one `Cargo.toml`).
- **`editor_core::Workspace`**: the editor-kernel model for **multiple open buffers** and
  **multiple views per buffer** (split panes).

Most of this document is about the internal design of the crates in the Cargo workspace, but the
`Workspace` type is also covered because it is the boundary where full editor hosts typically
integrate (tabs/splits/multi-file operations).

## Goals and non-goals

### Goals

- **Headless / UI-agnostic**: the engine produces snapshots and state; the host renders and maps
  styles to visuals.
- **Unicode-aware basics**:
  - edit operations use **character offsets** (Rust `char` indices), not byte offsets
  - layout uses **cell widths** (typical terminals: 1 or 2) for CJK/emoji
- **Coordinate conversions**:
  - char offsets ⇄ logical `(line, column)`
  - logical ⇄ visual rows (soft wrapping, folding)
  - UTF-16 conversions for LSP via `editor-core-lsp`
- **Composable derived state**: highlight/folding/diagnostics are “derived metadata”, applied as
  patches (`ProcessingEdit`) rather than hardwired into the core.

### Non-goals (currently)

- A full UI renderer, theme system, or widget toolkit.
- A fully typed LSP framework (`editor-core-lsp` intentionally uses `serde_json::Value`).
- A full grapheme-indexed coordinate, selection, or layout model (see “Unicode model” below).
- A full incremental parsing pipeline. Highlighting integrations are meant to be swappable.

## High-level architecture

The core engine (`crates/editor-core`) is organized in layers that build up from text storage to UI
snapshots:

```text
┌──────────────────────────────────────────────┐
│ Workspace (buffers + views) [optional]       │  multi-buffer/multi-view orchestration
├──────────────────────────────────────────────┤
│ State + commands (CommandExecutor/State)     │  public edit/query surface
├──────────────────────────────────────────────┤
│ Snapshots (HeadlessGrid)                     │  UI reads + renders
├──────────────────────────────────────────────┤
│ Styles + folding (IntervalTree/FoldingMgr)   │  derived metadata overlays
├──────────────────────────────────────────────┤
│ Layout (LayoutEngine)                        │  soft wrap + logical↔visual
├──────────────────────────────────────────────┤
│ Text storage + line index                     │  TextBuffer/LineIndex (rope edits + pos↔offset)
├──────────────────────────────────────────────┤
│ Deprecated compat shadow                      │  PieceTable debug validation / old API only
└──────────────────────────────────────────────┘
```

“Integration” crates (`editor-core-lsp`, `editor-core-sublime`, `editor-core-highlight-simple`)
compute derived metadata and/or drive external protocols. They feed results back into the core via
the shared derived-state interfaces.

## Coordinate model

`editor-core` needs multiple coordinate spaces. Using them consistently is the key to correct UI
behavior.

### 1) Byte offsets (UTF-8)

- Used internally in deprecated `PieceTable` compatibility *buffers* (`Piece.start`,
  `Piece.byte_length`).
- Not used as the primary API coordinate, because bytes are not stable under Unicode operations.

### 2) Character offsets (Unicode scalar values)

Most public APIs use **character offsets** (`usize`):

- Offsets count Rust `char`s across the whole document, including newline characters.
- Ranges are typically half-open: `[start, end)`.

Tradeoff: a user-perceived “character” (a grapheme cluster like `👨‍👩‍👧‍👦`) may be multiple `char`s.
Some cursor/delete commands understand grapheme or Unicode word boundaries, but stored positions,
selection ranges, layout columns, and public offsets remain Unicode-scalar based unless a specific
integration layer documents another unit.

### 3) Logical positions (line/column)

`Position { line, column }` is used for cursor/selection APIs.

- `line` is a logical line index (0-based)
- `column` is a character column within the logical line (0-based, counted in `char`s)

Conversions are provided by `LineIndex`:

- `LineIndex::char_offset_to_position(char_offset) -> (line, column)`
- `LineIndex::position_to_char_offset(line, column) -> char_offset`

### 4) Visual positions (soft wrap + folding)

Layout introduces a “visual row” coordinate:

- Soft wrapping splits a single logical line into multiple visual rows.
- Folding can hide logical lines and optionally append a placeholder to a fold start line.

Conversions exist in `LayoutEngine` (wrap-only) and `EditorCore` (wrap + folding):

- `LayoutEngine::logical_to_visual_line(logical_line)`
- `LayoutEngine::visual_to_logical_line(visual_line)`
- `EditorCore::logical_position_to_visual(...)`
- `EditorCore::visual_to_logical_line(visual_line)`

Visual `x` positions are expressed in **cells**, not characters.

### 5) LSP UTF-16 positions (integration crate)

The Language Server Protocol uses UTF-16 code units for `Position.character`.

`editor-core-lsp` provides `LspCoordinateConverter` and helpers to map between:

- editor char offsets / positions
- LSP UTF-16 positions / ranges

## Core data structures

### PieceTable (deprecated compatibility storage)

File: `crates/editor-core/src/storage.rs`

`PieceTable` is a deprecated compatibility layer and standalone validation target, not the text
truth source for editing. The main editing path stores text in the rope-backed `TextBuffer` behind
`LineIndex`. The compatibility piece table is a classic **piece table**:

- `original_buffer`: immutable bytes of the initial document
- `add_buffer`: append-only bytes for inserted text
- `pieces: Vec<Piece>`: each piece references a slice of one buffer

Each `Piece` stores:

- `start` + `byte_length` (byte range into the buffer)
- `char_count` (cached to support char-offset operations)

Edits:

- Insert:
  - append inserted bytes to `add_buffer`
  - find the piece containing the target char offset
  - split the containing piece if inserting in the middle
  - insert a new `Piece` referencing the new add-buffer region
- Delete:
  - split boundary pieces as needed and remove affected pieces/ranges

Notes:

- Splitting a piece at a *character* offset requires converting to a byte offset (currently an
  O(n) scan of the piece’s UTF-8 segment).
- Adjacent pieces from the add buffer are merged to reduce fragmentation.
- A simple GC compacts `add_buffer` by copying referenced regions and rewriting piece starts.

### LineIndex (logical line access)

File: `crates/editor-core/src/line_index.rs`

The line index is built on `ropey::Rope`:

- fast line access (`rope.line(i)`)
- efficient conversions between char offsets and line/column

The main edit path mutates the rope-backed `TextBuffer` through `LineIndex::insert/delete` and then
updates the affected layout window. Full line/layout reflow is still used for operations that change
layout-wide options or otherwise need to rebuild derived layout state.

Two offset conversion styles exist:

- `char_offset_to_position` / `position_to_char_offset`: preferred; match rope semantics where the
  newline is a character in the text stream.
- `line_to_offset` / `offset_to_line`: legacy helpers that treat offsets as “excluding newlines”
  and are mostly used in validation tests.

### LayoutEngine (soft wrapping)

File: `crates/editor-core/src/layout.rs`

Layout is a **headless reflow** engine:

- Input: logical line text and `viewport_width` (in cells)
- Output: wrap points (`WrapPoint { char_index, byte_offset }`) and `visual_line_count`

`char_width(ch)` uses the `unicode-width` crate:

- wide CJK/emoji → typically `2`
- combining marks → often `0`

Because width is computed per Unicode scalar value, multi-codepoint grapheme clusters are not
treated as single units for wrapping, layout columns, or public position ranges. Dedicated cursor and
delete commands can use grapheme or Unicode word boundaries, but that does not change the core
coordinate model.

The engine provides coordinate conversion for wrapped lines:

- `logical_position_to_visual(line, column) -> (visual_row, x_in_cells)`
- `logical_position_to_visual_allow_virtual(...)`: allows “virtual spaces” beyond line end, used by
  rectangular selection / column editing.

### IntervalTree and style layers (derived styling)

File: `crates/editor-core/src/intervals.rs`

Styles are represented as **intervals** over character offsets:

- `StyleId` is an opaque `u32` identifier
- `Interval { start, end, style_id }` uses half-open char ranges `[start, end)`

`IntervalTree` is implemented as:

- a vector sorted by `start`
- a `prefix_max_end` array for pruning during queries

This supports:

- point queries: “which styles apply at this offset?”
- range queries: “which intervals overlap this viewport?”

The core maintains:

- `interval_tree`: base style intervals
- `style_layers: BTreeMap<StyleLayerId, IntervalTree>`: per-source overlays (LSP semantic tokens,
  Sublime syntax, diagnostics, …)

Snapshots merge styles from the base tree and all layers, then sort+dedup the `StyleId` list for
each cell.

### FoldingManager (visibility)

File: `crates/editor-core/src/intervals.rs`

Folding is represented as line-based regions:

- `FoldRegion { start_line, end_line, is_collapsed, placeholder }`
- `end_line` is inclusive

`FoldingManager` stores a sorted list of regions and provides:

- toggling/collapsing/expanding
- mapping between logical and visual lines when folds hide content

When a region is collapsed, lines `(start_line + 1 ..= end_line)` become hidden.

Snapshots optionally append the region’s placeholder on the fold **start** line using the built-in
`FOLD_PLACEHOLDER_STYLE_ID`.

Current behavior:

- Existing fold regions are line-based. Text edits that insert or delete newlines apply a line delta
  to the stored regions and then clamp them to the current line count.
- User-created folds are kept in a separate set from derived folds, so manual fold state can survive
  derived-region refreshes when ranges still match.
- Derived fold regions are normally replaced from `ProcessingEdit::ReplaceFoldingRegions`; callers can
  request collapsed-state preservation for matching or slightly drifted derived ranges.
- LSP folding range responses are tied to the document version captured when the request was sent;
  stale responses are ignored instead of entering core folding state.

## Command and state layers

### EditorCore (aggregated model)

File: `crates/editor-core/src/commands.rs` (`pub struct EditorCore`)

`EditorCore` aggregates all major subsystems:

- text: rope-backed `TextBuffer` through `LineIndex` (`PieceTable` exists only as a deprecated
  compatibility API and debug consistency shadow)
- layout: `LayoutEngine`
- derived metadata: `IntervalTree`, style layers, `FoldingManager`
- selection state: cursor + selection(s)
- viewport width

It provides the styled snapshot helper:

- `EditorCore::get_headless_grid_styled(start_visual_row, count)`

This is the primary “UI reads data” method: it applies wrapping + folding and merges styles into
cells.

### CommandExecutor (mutations)

File: `crates/editor-core/src/commands.rs` (`pub struct CommandExecutor`)

Edits are applied through a command enum:

- `EditCommand`: insert/delete/replace, multi-caret typing, undo/redo, find/replace helpers
- `CursorCommand`: movement, selection, multi-cursor, rectangular selection
- `ViewCommand`: viewport width changes, request an unstyled viewport snapshot
- `StyleCommand`: ad-hoc base styles and manual folding toggles

Implementation notes:

- Edit commands mutate the `LineIndex`/`TextBuffer`, keep style interval offsets consistent (shift on
  insert/delete), apply folding line deltas when newline counts change, refresh only the affected
  layout window, and sync or invalidate the visual-row index cache.
- Multi-caret typing is applied by computing all edit ranges in the *original* document and then
  applying changes in descending offset order (so earlier edits don’t invalidate later offsets).

#### Undo/redo model

Undo/redo is implemented by `undo.rs` (`UndoRedoManager`) and used through the `commands` facade:

- Each applied edit produces one or more `TextEdit` records (deleted_text + inserted_text).
- Edits are grouped into `UndoStep { group_id, ... }`.
- Pure insertions that don’t contain newlines may be coalesced into the current “open group” to
  produce typical typing undo behavior.
- A “clean point” is tracked to support `is_modified`/save prompts in higher layers.

### EditorStateManager (queries + notifications)

File: `crates/editor-core/src/state.rs`

`EditorStateManager` wraps `CommandExecutor` and adds:

- a monotonically increasing `version`
- `is_modified` tracking + `mark_saved()`
- subscription callbacks (`subscribe`) for change notifications
- viewport bookkeeping (`scroll_top`, optional viewport height)
- structured query methods:
  - `get_document_state`, `get_cursor_state`, `get_viewport_state`, `get_style_state`, …

#### Derived state interface

The state manager is also the “integration point” for derived metadata:

- `DocumentProcessor` (trait): compute derived updates
- `ProcessingEdit` (enum): replace/clear style layers and folding regions

Processors are expected to be:

- deterministic given the editor state
- side-effect-free with respect to the editor (they return edits; the host applies them)

This pattern allows multiple independent integrations to coexist:

- a syntax highlighter can populate `StyleLayerId::SUBLIME_SYNTAX`
- an LSP session can populate `StyleLayerId::SEMANTIC_TOKENS` and folding regions
- a diagnostics engine can populate `StyleLayerId::DIAGNOSTICS`

### Workspace (multi-buffer + multi-view)

File: `crates/editor-core/src/workspace.rs`

`EditorStateManager` is a convenient “single buffer + single view” wrapper. Full editors
typically need:

- multiple open buffers (tabs)
- multiple views into the same buffer (split panes)
- workspace-wide operations (search across open buffers, apply multi-file edits from LSP)

`editor_core::Workspace` provides this orchestration layer while staying UI-agnostic. It models:

- **Buffer** (`BufferId`): document text + undo history + derived state tied to the text.
  Internally this is a `CommandExecutor` + some metadata (like an optional URI).
- **View** (`ViewId`): per-viewport state like selections/cursors, wrap configuration, and scroll.
  - includes smooth-scrolling metadata (`sub_row_offset`, `overscan_rows`) used for prefetch range planning.

Key behavior:

- `Workspace::execute(view_id, Command)` runs commands **against a specific view**.
  - Cursor/selection state is view-local.
  - Text edits mutate the underlying buffer.
  - Any resulting `TextDelta` is broadcast to *all* views of the buffer (split panes stay in sync).
- Derived metadata is stored at the buffer level and can be applied via
  `Workspace::apply_processing_edits(buffer_id, edits)`, which notifies all views of that buffer.
- For incremental consumers that want “one delta per buffer edit”, use
  `Workspace::take_last_text_delta_for_buffer`.
- Visual-row query APIs are available on `Workspace` (view-aware):
  - `total_visual_lines_for_view`
  - `visual_to_logical_for_view`
  - `logical_to_visual_for_view`
  - `visual_position_to_logical_for_view`
  - `viewport_state_for_view` (includes visible range + prefetch range + smooth-scroll metadata)

Conceptually, one `EditorStateManager` corresponds to “a `Workspace` with one buffer and one
view”; `Workspace` makes the identities explicit and allows additional views to share the same
buffer state.

## Snapshots

File: `crates/editor-core/src/snapshot.rs`

The snapshot format is intentionally small and UI-friendly:

- `HeadlessGrid { lines, start_visual_row, count }`
- `HeadlessLine { logical_line_index, is_wrapped_part, visual_in_logical, char_offset_start, char_offset_end, segment_x_start_cells, is_fold_placeholder_appended, cells }`
- `Cell { ch, width, styles }`
- `MinimapGrid { lines, start_visual_row, count }` (lightweight overview snapshot)
- `MinimapLine { logical_line_index, visual_in_logical, char_offset_start, char_offset_end, total_cells, non_whitespace_cells, dominant_style, is_fold_placeholder_appended }`

There are two snapshot paths:

1. `SnapshotGenerator` (text-only):
   - owns a `Vec<String>` of lines + its own `LayoutEngine`
   - produces unstyled snapshots
   - useful for tests and simple usage
2. `EditorCore::get_headless_grid_styled` (recommended for real UIs):
   - uses the editor’s live `LineIndex` + `LayoutEngine`
   - merges styles and applies folding
3. `EditorCore::get_minimap_grid`:
   - uses the same layout/folding semantics
   - returns per-line aggregates instead of per-cell payload for minimap/overview scenarios

## Integration crates

### editor-core-highlight-simple

Path: `crates/editor-core-highlight-simple/`

A lightweight, regex-based highlighter intended for simple formats (JSON/INI/etc.):

- `RegexHighlighter` runs regex rules line-by-line and emits style `Interval`s in char offsets.
- `RegexHighlightProcessor` implements `DocumentProcessor` and emits
  `ProcessingEdit::ReplaceStyleLayer` for `StyleLayerId::SIMPLE_SYNTAX`.

### editor-core-sublime

Path: `crates/editor-core-sublime/`

Implements a subset of the Sublime Text `.sublime-syntax` model:

- compile YAML syntax definitions
- run a highlighting engine to produce:
  - style intervals (char offsets)
  - fold regions (logical line ranges)
- expose a `SublimeProcessor` (`DocumentProcessor`) that outputs:
  - `StyleLayerId::SUBLIME_SYNTAX`
  - folding edits

This provides “good enough” highlighting/folding for many languages without requiring an LSP.

### editor-core-lsp

Path: `crates/editor-core-lsp/`

Provides runtime-agnostic helpers for LSP integration:

- UTF-16 conversion helpers (`LspCoordinateConverter`)
- incremental text change helpers (`DeltaCalculator`)
- semantic tokens decoding into editor style intervals
- workspace/text edit parsing + application (`serde_json::Value` based)
- stdio JSON-RPC client (`LspClient`) and a higher-level session (`LspSession`)

`LspSession` can be used as a `DocumentProcessor`:

- polls the server
- updates editor derived state with `ProcessingEdit` (semantic tokens + folding ranges, etc.)

## TUI demo app

Path: `crates/tui-editor/`

`tui-editor` is a runnable example that:

- renders `HeadlessGrid` using `ratatui`
- drives edits via `EditorStateManager`
- optionally enables:
  - Sublime syntax highlighting/folding (if a matching `.sublime-syntax` exists in the CWD)
  - LSP semantic tokens/folding ranges (stdio server)

It is meant as:

- a functional integration test for the workspace
- a reference for how a UI can consume snapshots and apply derived state

For multi-buffer/multi-view wiring, see the `editor-core` workspace examples (e.g.
`crates/editor-core/examples/multiview_workspace.rs`).

## Known limitations / extension points

- **Grapheme clusters and words**: public cursor/selection coordinates and layout columns are
  `char`/cell-based. Dedicated grapheme movement/delete and Unicode word-boundary commands exist,
  but full grapheme-indexed selection or layout semantics are not part of the core API.
- **Tabs/control chars**: layout measures per `char` width; hosts typically implement tab expansion
  at render time or by transforming snapshots.
- **Folding edits**: line-based folds are shifted by newline deltas and clamped after edits, but
  parser/LSP-derived fold structure is still refreshed by replacing derived folding regions.
- **Incrementality**: some operations rebuild derived structures from the full text for simplicity.
  The architecture is intentionally layered so internal components can be made more incremental
  over time without breaking the public API shape.
