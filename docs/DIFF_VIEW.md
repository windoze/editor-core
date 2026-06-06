# editor-core — Diff View Design

> **Status:** Design proposal (not yet implemented), as of 2026-06-06.
> This document records the agreed-upon design direction for a diff/merge viewer built on top of
> `editor-core`. It is intended to be implemented in a new crate `editor-core-diff-view`.

This document explains how a diff viewer fits into the `editor-core` architecture. It is written
for:

- contributors implementing the diff/merge viewer
- UI/front-end authors integrating it

For the engine internals it builds on, see [`DESIGN.md`](./DESIGN.md). For the line-diff
primitives, see `crates/editor-core-diff`.

## Design principles

The diff viewer follows the same philosophy as the rest of `editor-core`:

- **Fully headless / UI-agnostic.** The engine produces aligned, styled grid data; the host
  renders it and maps styles to visuals. Skia/Swift/TUI front-ends are built *around* the engine,
  never inside it.
- **No UI concepts in the abstraction.** There is no "splitter" concept in the headless layer.
  A splitter is a UI act of placing columns side by side. What the headless layer produces is an
  **aligned, multi-column row axis**; how many columns and how they are laid out is the host's
  business.
- **Soft wrap is mandatory.** `editor-core` deliberately avoids horizontal scrollbars (a poor
  experience on both desktop and mobile), so soft wrap must work in diff mode too. This is the main
  source of complexity for side-by-side alignment, and the design addresses it head-on rather than
  disabling wrap.

## High-level architecture

The diff viewer is a **consumer/compositor** of the headless grid, not a new core feature. The
core abstraction stays "one file → one headless grid"; the diff viewer orchestrates several of
those plus alignment.

There are three layers, all headless, plus the host's render engine:

```
                         ┌───────────────────────────────────────────┐
                         │ DiffModel  (underlying truth)             │
   file + patch  ──────► │  - sides: Vec<SideDoc>                    │  width-independent
   (or base + N sides)   │  - alignment: Vec<AlignUnit>              │  mode-independent
                         │  - NO spacer                              │  no spacer
                         └────────────────────┬──────────────────────┘
                                              │ mode + per-column widths
                                              ▼
                         ┌───────────────────────────────────────────┐
                         │ DiffProjection  (presentation)            │
                         │  - columns: usize                         │  width-dependent
                         │  - rows: Vec<Row>  (unified row axis)     │  spacer/mark/style
                         │  - generates spacer + gutter mark + style │  generated here
                         └────────────────────┬──────────────────────┘
                                              │ project column i
                                              ▼
                         ┌───────────────────────────────────────────┐
                         │ Views  (one per column)                   │
                         │  - thin projection of rows[*].slots[i]    │  readonly EditorCore
                         │  - readonly editor command interface      │  behind each view
                         └────────────────────┬──────────────────────┘
                                              │ data only
                                              ▼
                         ┌───────────────────────────────────────────┐
                         │ Render engine (host)                      │
                         │  scroll + sync + splitter layout          │
                         └───────────────────────────────────────────┘
```

The key invariant tying it together: **all columns share a single unified visual row axis**
(`DiffProjection::rows`). Row `i` is drawn at the same vertical position in every column. This is
what makes synchronized scrolling trivial — the render engine scrolls one axis, and every view
reads the same `[start, count)` slice.

## Layer 1: `DiffModel` (the underlying truth)

`DiffModel` is the diff fact, independent of viewport width and independent of presentation mode.
It contains **no spacer rows** — those are a presentation artifact (see Layer 2).

```rust
/// One side of the diff (a readonly document).
struct SideDoc {
    // backed by editor-core's text/line/layout machinery (e.g. SnapshotGenerator)
    // owns logical lines; width-dependent wrapping is computed in the projection layer
}

/// How a run of logical lines on each side relates across sides.
enum AlignUnit {
    /// Unchanged lines present on all sides (1:1 across sides).
    Context { /* per-side logical line ranges */ },
    /// A modified block: removed lines on the left, added lines on the right.
    Replace { /* left logical line range, right logical line range */ },
    /// Lines present only on the "after" side.
    Add { /* right logical line range */ },
    /// Lines present only on the "before" side.
    Remove { /* left logical line range */ },
}

struct DiffModel {
    sides: Vec<SideDoc>,        // 2 = diff, 3 = three-way merge
    alignment: Vec<AlignUnit>,  // ordered alignment units covering the whole document
}
```

### Data source: `file + patch`

The primary data source is **one file plus one patch**, rather than two full texts:

- The patch already encodes the line pairing (which lines are add/remove/context), so there is no
  need to re-run a diff algorithm to build `alignment`.
- A patch typically carries only a few context lines around each change. The full `file` is still
  needed to fill in the large unchanged regions outside the patch hunks. So: **the file provides
  the full text; the patch provides the pairing and the changed content.** The other side's full
  text is reconstructed by applying the patch.

Two notes:

- `before + after` (two full texts) is an alternative source; it requires running
  `editor-core-diff::diff_line_hunks` to derive `alignment`. Both sources reduce to the same
  `DiffModel`.
- **Three-way merge does not fit a single patch.** The data entry point is abstracted as "N sides +
  their alignment relationship". `file + patch` is the 2-side special case. Do not hardcode
  "left/right" into the types; leave room for a third side.

## Layer 2: `DiffProjection` (presentation)

Given a `DiffMode` and per-column widths, the projection produces the **unified visual row axis**.
This is where soft wrap, spacer rows, gutter marks, and diff styles are materialized.

```rust
enum DiffMode { Unified, SideBySide /*, ThreeWay */ }

struct DiffProjection {
    columns: usize,        // Unified = 1, SideBySide = 2, ThreeWay = 3
    rows: Vec<Row>,        // the unified visual row axis (the render engine scrolls this)
}

struct Row {
    slots: Vec<RowSlot>,   // slots.len() == columns
}

enum RowSlot {
    /// A real visual line segment from one side's document.
    Line {
        side: usize,
        logical_line: usize,
        visual_in_logical: usize,   // which soft-wrap segment of the logical line
        change: DiffLineKind,       // Context / Add / Remove (from editor-core-diff)
    },
    /// An alignment filler row that does not exist in any side's document.
    /// Produced only in SideBySide / ThreeWay; never in Unified.
    Spacer { change: DiffLineKind },
}
```

### Unified is not a special case — it is `columns == 1`

The same `DiffModel`, projected with a different `DiffMode` + column widths, yields a different
`rows`. Side-by-side, unified, and three-way merge all share one data structure and one scrolling
model:

- **`SideBySide`** (`columns == 2`): each side wraps independently; per alignment unit, take
  `max(nLeft, nRight)` visual rows and pad the shorter side with `Spacer` at the end so the next
  unit's start stays aligned.
- **`Unified`** (`columns == 1`): no spacer needed; a modified block expands into sequential rows
  (removed lines first, then added lines) in a single column. This is the wrap-friendly mode and is
  recommended as the default on narrow / mobile viewports.
- **`ThreeWay`** (`columns == 3`): same as side-by-side, generalized to three columns.

### Alignment unit is the logical-line pairing, not the visual row

This is the core idea that makes soft wrap tractable. The headless layer has no notion of "row
height"; a logical line that wraps into N segments simply occupies N visual rows. "Keeping both
sides aligned" therefore means **making the visual row counts equal per alignment unit**:

1. From `alignment`, walk the ordered `AlignUnit`s.
2. For each unit, wrap each side's logical lines using **that column's width**, yielding `nSide`
   visual rows per side.
3. Take `max` across sides; pad shorter sides with `Spacer` at the end of the unit.

Width differences between columns produce different wrap counts, so spacers are common — this is
the inherent cost of side-by-side + soft wrap, not a flaw of the design. Unified mode sidesteps it
entirely.

### Recompute layering (what depends on width)

Not everything depends on width; recompute can be staged to avoid wasted work:

- **Width-independent** (parse the patch once, cache): each side's logical lines, the alignment
  pairing, and per-line change kind.
- **Width-dependent** (recompute when a width changes): each side's soft-wrap layout, and the
  spacer positions / the `rows` axis derived from per-side visual row counts.

A splitter drag does not enter the headless layer, but the **per-column width it derives is a
legitimate headless input** — exactly like `viewport_width` for a single buffer
(`crates/editor-core/src/snapshot.rs`). Dragging a splitter is equivalent to a resize-triggered
reflow: the host calls the projection again with new widths; the alignment pairing is untouched and
only the wrap + `rows` are rebuilt.

### Two classes of style

`Cell.styles` (`crates/editor-core/src/snapshot.rs`) carries the union of:

- **Diff-semantic styles** — added/removed line backgrounds, spacer marker, intra-line highlight.
  These depend on the pairing and are produced in the projection layer. (Note: `diff_line_hunks`
  is line-level only; intra-line highlight needs an extra word/char diff.)
- **Syntax-highlight styles** — from LSP / tree-sitter, per-side and per-file, following each
  side's document.

Views overlay both when projecting.

### Gutter via line marks

The gutter (`+`/`-`/`~` indicators, line numbers) is not a core concept and is not about rendering.
It is fed by a generic, per-logical-line **line mark** abstraction:

- A line mark is anchored to a logical line and carries an id / payload; the host decides how to
  render it.
- This is a sibling of the decoration model (`crates/editor-core/src/decorations.rs`): a decoration
  is anchored to a character offset and carries virtual text; a line mark is anchored to a logical
  line and feeds the gutter.
- Recommendation: implement line marks as a **generic core capability** (breakpoints, git blame,
  fold indicators can all reuse it), with the diff viewer as the first consumer.
- For diff, the projection attaches the appropriate marks per alignment unit onto the `Row` /
  `RowSlot`. Line numbers fall out naturally: the left gutter shows `before_line`, the right shows
  `after_line` (the two fields of `editor-core-diff`'s `DiffLine`).

## Layer 3: Views (one per column)

Each view is a thin projector of `rows[*].slots[i]` for its column, translating each slot into
cells / style / line-mark (a `Spacer` yields an empty row).

### Readonly editor command interface

Behind each view sits a **readonly `EditorCore` / `CommandExecutor`** (`crates/editor-core/src/commands.rs`).
The view exposes the same command interface as a normal editor, restricted to the read-only /
navigation subset:

- **Allowed:** cursor movement, selection, scroll, find, go-to.
- **Rejected:** insert, delete, replace, undo/redo.
- Recommendation: add an `is_mutating()` classification to `Command` and have the view layer reject
  mutating commands, rather than defining a separate command enum.

The payoff: the host's keybinding → command mapping is written once and drives both normal editors
and diff panes, giving a consistent interaction experience.

### Two coordinate systems: per-side vs unified

Commands act on the **per-side document's real coordinates** (reusing all of the editor's
navigation logic with zero changes). Rendering and scrolling use the **unified row axis**. The
projection provides a bidirectional mapping **per-side visual row ↔ unified row**.

A pleasant side effect: **the cursor naturally skips spacers.** A spacer is not part of any side's
real line sequence, so "move down one line" increments the side's real visual row and then maps
back to the unified axis — the cursor can never land on a filler row.

## Render engine (host responsibilities)

Everything visual and stateful about layout lives in the host:

- **Scrolling and synchronization** — the render engine scrolls the unified `rows` index; every
  view reads the same `[start, count)`, so horizontal alignment is automatic.
- **Splitter layout** — placing columns side by side, deriving per-column widths, feeding them back
  into the projection.

Views provide data only; they do not manage scrolling, layout, or splitters.

## Open questions / future work

- **Fold.** Folding does not change text (so it reads as "read-only"), but it changes a single
  side's visual row count — folding one side without the other breaks alignment. Lean toward
  **disabling fold in the diff view for the first version**; synchronized fold (folding a hunk on
  both sides together, per alignment unit) is future work, since it would force the projection's
  alignment algorithm to also account for folding as a variable beyond width.
- **Intra-line diff.** `diff_line_hunks` is line-level. Highlighting the exact changed characters
  within a modified line needs an additional word/char diff, surfaced as a diff-semantic style.
- **Incremental recompute.** The first version may rebuild `rows` wholesale on a width change
  (same order of magnitude as a resize reflow). Incremental wrap/alignment updates are a later
  optimization.

## Relationship to existing crates

- `editor-core` — provides the per-side text/line/layout/snapshot machinery (`SnapshotGenerator`,
  `Cell`, `StyleId`) and the readonly command engine (`EditorCore`, `CommandExecutor`).
- `editor-core-diff` — provides the line-diff primitives: `diff_line_hunks` returning `LineHunk`s
  whose `DiffLine`s carry `before_line` / `after_line` / `kind`
  (`crates/editor-core-diff/src/lib.rs`).
- `editor-core-diff-view` *(new)* — the three layers described here: `DiffModel`, `DiffProjection`,
  and the views. Headless; depends on the two crates above; contains no rendering, scrolling, or
  splitter logic.

## First implementation step

Pin down the shape of `AlignUnit` and the two projection builders — `project_unified` and
`project_side_by_side` — together with the alignment algorithm (in particular, how left/right lines
within a `Replace` block are paired). Once these are fixed, the model and the views can be built in
parallel.
