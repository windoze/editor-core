# VI Mode: Missing Infrastructure + Implementation Plan

This repo already has a strong “editor kernel” (`crates/editor-core`) plus a host-agnostic UI wrapper (`crates/editor-core-ui`) and Swift/AppKit host (`swift/`). What’s missing for a real **VI/Vim-style modal editing mode** is mostly *input semantics infrastructure* (state machine + motion/operator model), plus a small amount of *host routing* so keys can be interpreted as commands instead of text insertion.

This document is a plan only (no code changes yet).

---

## 0) Define scope (important)

“VI mode” can mean anything from “hjkl + Esc” to “near-Vim”. Before implementing, decide which tier you want:

- **Tier A (Vim-lite, MVP)**: Normal/Insert/Visual (char+line) + core motions + delete/yank/change + paste + undo/redo + repeat `.` (optional) + basic `/` search.
- **Tier B (practical daily-driver)**: add counts, registers, macros, text objects, `:` command-line subset, marks/jumps integration, `f/t` motions, visual block.
- **Tier C (full Vim parity)**: mappings, operators edge-cases, folds, digraphs, complex ex commands, full option model (`iskeyword`, `virtualedit`, etc).

The rest of this plan assumes **Tier A → Tier B**.

---

## 1) What we already have (reusable building blocks)

### Kernel / command layer (Rust)

- A unified command API with editing + cursor + view commands:
  - `crates/editor-core/src/commands.rs` (`EditCommand`, `CursorCommand`, `Command`)
- Undo/redo with a branching “undo tree” model (Vim-like):
  - See `MISSING-FEATURES.md` (“Undo tree” implemented)
- Marks / jump list / bookmarks (very Vim-adjacent):
  - See `MISSING-FEATURES.md` (“Bookmarks / marks / jump list” implemented)

### Host-agnostic UI wrapper (Rust)

- `EditorUi` convenience methods that wrap core commands + do the “editor UX bookkeeping”:
  - selection helpers (`selected_text`, `selections_offsets`, `set_selections_offsets`)
  - IME paths (`set_marked_text_with_selection`, `commit_text`, etc.)
  - explicit `end_undo_group()` for undo boundary control
  - file: `crates/editor-core-ui/src/lib.rs`
- A VSCode-ish keymap + chord resolver (useful for non-VI shortcuts; not sufficient for VI semantics):
  - file: `crates/editor-core-ui/src/keybindings.rs`

### Swift/AppKit host

- A working input plumbing for Insert-like typing via AppKit text system:
  - `EditorCoreSkiaView.keyDown` uses `interpretKeyEvents` which calls `insertText` / `setMarkedText` / `doCommand(by:)`
  - file: `swift/Sources/EditorCoreUI/EditorCoreSkiaView.swift`
- Clipboard integration exists at the host level (`copy/cut/paste` actions).

---

## 2) Infrastructure that is still missing (for real VI mode)

### A) Modal input routing (host integration gap)

Right now, `EditorCoreSkiaView.keyDown` always calls `interpretKeyEvents(...)` (except Cmd shortcuts). That means:

- Pressing `j` produces *text insertion*, not “move down”.
- AppKit handles keybindings before you can interpret “raw” VI keystrokes.

**Missing pieces**

- A *mode-aware* key routing decision:
  - **Insert mode**: keep `interpretKeyEvents` (IME, dead keys, compose, etc).
  - **Normal/Visual mode**: bypass `interpretKeyEvents` and feed raw keystrokes into a VI engine.
- A way to translate `NSEvent` → a stable “keystroke” representation (key + modifiers) that matches Rust-side expectations.
- Cursor/UI feedback plumbing (block cursor for Normal, bar cursor for Insert, etc.) and a status indicator (“-- NORMAL --”).

### B) VI state machine + grammar (core missing infra)

VI is not “keybindings”; it’s a *language* of keystrokes:

- **modes**: Normal / Insert / Visual (char/line/block) / Replace (optional)
- **prefixes**: counts (`3dw`), registers (`"a`), operator-pending (`d` then motion), etc.
- **multi-key commands**: `gg`, `ciw`, `dap`, `f{char}`, `/{pattern}`…
- **cancel/reset**: `Esc` should reliably clear pending prefixes and exit to Normal

**Missing pieces**

- A dedicated **VI input interpreter** with explicit state:
  - current mode
  - pending count
  - pending operator
  - pending register
  - pending motion/text-object
  - pending “expect a char” (e.g. `f`/`t` target)
- A deterministic “feed one keystroke” API that returns:
  - either “handled + emitted edit/navigation commands”
  - or “pending, waiting for more keys”
  - or “not handled”

### C) Motion + text-object range engine (kernel-adjacent gap)

The current core has many movement commands (`MoveWordRight`, `MoveToLineStart`, etc.) but VI operators need **ranges**:

- `dw` means “delete *range described by motion*”, not “move then delete word”.
- Inclusive/exclusive semantics matter (`de` vs `dw`, linewise vs charwise, etc.).
- Vim’s “word” and “WORD” semantics differ from Unicode word boundaries.

**Missing pieces**

- A way to compute **motion ranges** from the current caret/selection:
  - word motions: `w/W`, `b/B`, `e/E`
  - line motions: `0`, `^`, `$`, `g_`
  - doc motions: `gg`, `G`
  - find-char motions: `f/F/t/T{char}`
  - paragraph/sentence: `{` `}` (optional)
- Text objects for Tier B:
  - `iw/aw`, `i(/a(`, `i{/a{`, `i\"/a\"`, etc.
- Configuration hooks:
  - Vim-like word boundary config (`iskeyword`-ish), not only UAX #29 boundaries.

### D) Registers + yank/put model (missing data model)

Core/UI supports “get selected text” and “paste text”, but VI expects:

- unnamed register (`""`), numbered registers (`"0`..`"9`), named (`"a`..`"z`)
- linewise vs characterwise yanks/deletes (affects `p/P`)
- `y`/`d` should populate registers (including system clipboard integration optionally)

**Missing pieces**

- A register store (likely *outside* `editor-core` kernel; best in `editor-core-ui` or host):
  - content + kind (charwise/linewise/blockwise)
  - last-used register semantics
- A clear interface between VI engine and host clipboard:
  - “write to system clipboard when register is `+`/`*`”
  - “read from system clipboard for `"+p`”

### E) Repeat (`.`) and macros (Tier B infra)

To feel like Vim, you need:

- `.` repeat last change (not last keystroke)
- macro record/play (`q{reg}` … `q`, then `@{reg}`)

**Missing pieces**

- A representation for “repeatable change” at the right abstraction level:
  - store high-level VI actions, or store emitted core commands + inserted text
  - ensure undo-group boundaries match repeat boundaries
- Macro recording that is robust across IME / text insertion paths.

### F) Testing & fixtures (missing validation scaffolding)

VI mode is easy to regress; you’ll want:

- unit tests for the VI parser/state machine
- integration tests that apply key sequences and assert:
  - final text
  - caret/selection offsets
  - mode state
  - register contents

**Missing pieces**

- A deterministic test harness for “feed keys → apply → snapshot/assert”.
- Golden fixtures for tricky cases (Unicode, indentation, end-of-line, empty buffer, etc.).

---

## 3) Recommended architecture (where to put VI mode)

### Preferred: implement VI engine in Rust (host-agnostic)

Rationale:

- Keeps semantics consistent across TUI / winit / Swift host.
- Lets you reuse existing command/state machinery and keep Unicode/range logic in one place.

Suggested placement:

- **Option 1:** `crates/editor-core-ui/src/vi/` (new module) because:
  - `EditorUi` is where input policy already lives (mouse gestures, keybindings dispatch, IME helpers)
  - it’s host-agnostic and already has FFI (`editor-core-ui-ffi`)
- **Option 2:** a new crate `crates/editor-core-vi/` if you want to keep it independent from `EditorUi`.

Public surface (rough sketch):

- `ViEngine` state (mode + pending prefixes + registers + last-change)
- `feed_key(stroke, editor_ui, host_hooks) -> ViFeedResult`
  - emits edits/navigation by calling `EditorUi` methods or by producing `editor_core::Command`s

### Swift host responsibilities (even with Rust VI engine)

- Decide when to route keys to VI engine vs AppKit text system (mode-aware).
- Translate `NSEvent` into the keystroke representation consumed by the VI engine.
- Provide clipboard hooks (system clipboard read/write).
- Render mode/status + cursor style.

---

## 4) Step-by-step plan (Tier A → Tier B)

### Phase 1 — “Mode-aware routing” (Swift)

Deliverables:

- A single source of truth for current editor mode (Normal/Insert/Visual…)
- `keyDown` routing:
  - Normal/Visual: bypass `interpretKeyEvents`, forward raw key to VI handler
  - Insert: keep `interpretKeyEvents` for IME correctness
- `Esc` handling that always returns to Normal and clears pending state
- UI indicator: status text + cursor style

Risks:

- AppKit IME and dead-key behavior: must not break Insert mode text input.

### Phase 2 — “VI engine skeleton” (Rust)

Deliverables:

- `ViEngine` with:
  - mode enum
  - pending prefix tracking (at least operator-pending + partial multi-key like `g`)
  - `feed_key` returning {Handled, Pending, NotHandled}
- Minimal command set (Tier A):
  - Normal: `h j k l`, `w b e` (approx), `0 $`, `gg G`
  - Insert entry: `i a o O`, exit `Esc`
  - Edit ops: `x`, `dd`, `yy`, `p/P`, `u`, `Ctrl+r`
  - Visual: `v` (char), `V` (line), `y`, `d`
- Undo boundary rules:
  - end undo group on leaving Insert mode
  - operators (`d/y/c`) are single undo steps

### Phase 3 — “Ranges + operators” (Rust)

Deliverables:

- Operator-pending model:
  - `d{motion}`, `y{motion}`, `c{motion}`
  - linewise special-cases: `dd`, `yy`, `cc`
- A range computation layer that is explicit about:
  - charwise vs linewise
  - inclusive/exclusive behavior
  - word boundary policy
- Register store + clipboard hooks:
  - at least unnamed + system clipboard register (`+`)

### Phase 4 — “FFI + Swift wiring” (Rust + Swift)

Deliverables:

- Expose VI engine via `editor-core-ui-ffi` (create/destroy/feed/query mode)
- Swift wrapper in `swift/Sources/EditorCoreUIFFI/` to call into the VI engine
- `EditorCoreSkiaView` integration:
  - mode-aware routing
  - clipboard bridging
  - redraw + viewport notifications when VI commands execute

### Phase 5 — “Tier B quality” (Rust)

Pick a subset that gives the biggest payoff:

- Counts (`3w`, `10j`, `2dw`, `3dd`)
- Text objects (`iw/aw`, `i(/a(`, `i{/a{`, quotes)
- Find-char motions (`f/F/t/T`)
- Repeat `.` (record last change at VI-action level)
- Macros (`q` / `@`) if desired
- Search (`/` `?`) and “n/N” repeat-search (likely host UI for prompt, engine stores last pattern)

---

## 5) Open questions (decide early)

- **Word semantics:** Vim `w`/`W` vs current UAX #29 “word boundaries”. Do we introduce a Vim-style classifier?
- **Visual vs logical movement:** Should `j/k` be logical lines or visual (wrap-aware) rows? (Vim uses logical; `gj/gk` are visual.)
- **Multi-cursor:** Collapse to a single caret in VI mode, or apply to all selections?
- **Registers location:** Keep in Rust (consistent across hosts) vs keep in Swift (native clipboard easy) with a Rust “hook” API.
- **Key mapping:** Support `:map`/`imap`/`nmap` later, or rely on the existing VSCode-ish keymap layer?

---

## 6) Suggested first milestone (“1-week MVP”)

If you want something quickly usable:

- Normal/Insert toggle with `Esc`, `i`, `a`
- Navigation: `hjkl`, `w`, `b`, `0`, `$`, `gg`, `G`
- Edit: `x`, `dd`, `yy`, `p`, `u`, `Ctrl+r`
- Visual (char): `v` + `y/d`
- Status indicator + cursor style

That MVP forces the missing infrastructure to exist (mode routing + VI parser + minimal range ops) without immediately requiring full Vim complexity.

