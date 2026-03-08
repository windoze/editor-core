# Missing Features (Gap List)

This repository already ships a fairly complete **headless editor kernel** (`crates/editor-core`)
plus several “editor-adjacent” crates (`editor-core-lsp`, `editor-core-treesitter`,
`editor-core-render-skia`, `editor-core-ui`, and FFI bridges).

This document lists the **remaining gaps** you’d typically need to close to build a
**full-featured, production-quality code editor** primarily from the `editor-core*` crates.

Notes:

- Some items below are **intentionally out-of-scope** for `editor-core` (per `ROADMAP.md` and the
  project’s “headless kernel” positioning). They’re still “missing” from the workspace if the
  goal is a complete editor product.
- “Where” points at the *best-fit* location in this workspace (crate / layer) if we were to
  implement it here.

Legend:

- **[core]** belongs in `crates/editor-core/` (kernel / state / commands / snapshots)
- **[integration]** belongs in an integration crate (`editor-core-lsp`, `editor-core-treesitter`,
  `editor-core-sublime`, `editor-core-lang`, …)
- **[ui]** belongs in `editor-core-ui` / `editor-core-render-skia`
- **[host]** should live in the embedding application (still required for a “full editor”, but not
  a good fit for these crates)

---

## No-goals (explicitly ruled out)

These items are sometimes expected in mainstream editors, but are intentionally **not goals** for
this workspace (per your request).

- **Horizontal scrolling model**
  - No `scroll_left_*` state, commands, or snapshot clipping by x-range.
  - Assumption: UIs prefer soft wrapping (`WrapMode::Char` / `WrapMode::Word`) or accept that long
    lines may be partially off-screen without a first-class horizontal scroll feature.

- **BiDi / RTL correctness**
  - No attempt to provide fully-correct cursor movement/hit-testing/rendering for bidirectional
    scripts in a monospace grid model.

---

## Kernel gaps (`crates/editor-core/`)

- [x] **[core] Undo history persistence** (serialize/restore)
  - Undo/redo exists, but there is no built-in way to persist and later restore the undo stack,
    clean point, and grouping boundaries.
  - Needed for “hot exit” workflows and some embedded-editor use cases.
  - Implemented via `undo_history_snapshot` / `restore_undo_history` (see `UndoHistorySnapshot`).
    Optional `editor-core` feature `serde` enables `serde` (de)serialization of the snapshot types.

- [ ] **[core] Undo tree (branching history)** (optional power feature)
  - Current undo/redo is linear. Branching undo (like Vim’s undo tree) is not exposed.

- [ ] **[core] Bookmarks / marks / jump list**
  - No first-class bookmark/mark model that shifts correctly under edits.
  - A jump list (navigation history) is also typically expected in editors with go-to-definition.

- [ ] **[core] Diff / hunk primitives**
  - No built-in diff/hunk computation suitable for:
    - “modified lines” gutter indicators
    - diff views / merge editors (UI aside)
  - This likely belongs in a new crate (similar to the older roadmap idea of `editor-core-diff`).

- [ ] **[core] Snippet engine (placeholders + navigation)**
  - The LSP completion helper currently **downgrades** snippet-formatted inserts to plain text
    (see `crates/editor-core-lsp/src/lsp_completion.rs`).
  - A real snippet subsystem needs:
    - parsing `${1:placeholder}`, `$0`, choice placeholders, variables
    - tracking “active snippet ranges” under subsequent edits
    - tab/shift-tab navigation between placeholders

- [ ] **[core] Language-aware indentation beyond “copy leading whitespace”**
  - `InsertNewline { auto_indent: true }` copies the current line’s leading whitespace, but there’s
    no syntax-aware indentation engine (brace/paren rules, hanging indent, etc.).
  - A pragmatic route is: data-driven indentation rules in `editor-core-lang`, optionally refined
    by Tree-sitter queries.

- [x] **[core] Auto-pairs + bracket matching**
  - Typical baseline editor behavior that’s not exposed as first-class kernel commands:
    - auto-close pairs (`()`, `{}`, `[]`, quotes)
    - “skip over” closing delimiters
    - delete-pair behavior
    - highlight matching bracket / jump to matching bracket
  - Implemented via:
    - `EditCommand::TypeChar` + `AutoPairsConfig` (view-local; set via `ViewCommand::SetAutoPairsConfig` / `SetAutoPairsEnabled`)
    - delete-pair behavior integrated into `Backspace` / `DeleteForward` when enabled
    - `CursorCommand::MoveToMatchingBracket`
    - `StyleCommand::UpdateBracketMatchHighlights` / `ClearBracketMatchHighlights` (writes `StyleLayerId::BRACKET_MATCHES` with `MATCH_HIGHLIGHT_STYLE_ID`)
  - UI/FFI integration:
    - `editor-core-ui::EditorUi` exposes view-local toggles:
      - `set_auto_pairs_enabled(...)`
      - `set_bracket_match_highlights_enabled(...)` (auto-updates after cursor moves/edits)
      - `move_to_matching_bracket()`
      - `paste_text(...)` (clipboard path; always bulk insert, no auto-pairs)
    - `editor-core-ui-ffi` exports the above to Swift/AppKit hosts.
    - AttoEditor enables auto-pairs + bracket-match highlights by default when opening a tab,
      and exposes “Go: Go to Matching Bracket” in the command palette.
  - Tests:
    - Kernel: `crates/editor-core/tests/auto_pairs_brackets.rs`
    - UI wrapper: `crates/editor-core-ui/src/lib.rs` (unit tests)
    - Swift/AppKit: `swift/Tests/AttoEditorTests/AttoAutoPairsAndBracketsTests.swift`

---

## Language & tooling gaps (`editor-core-*` integrations)

- [x] **[integration] Language registry / configuration system**
  - `editor-core-lang` currently only contains `CommentConfig`.
  - A full editor typically needs a unified per-language config surface for:
    - comment tokens (already)
    - bracket pairs / auto-pairs rules
    - indentation rules / indentation triggers
    - word separators (beyond the current ASCII-boundary override)
    - optional Tree-sitter grammar + query resolution
    - optional LSP launch config (server command, root detection, initialization options)
  - Implemented in `crates/editor-core-lang`:
    - `LanguageRegistry` + `LanguageConfig` (+ matching by file name / extension)
    - `AutoPairsConfig`, `IndentationConfig`, `WordBoundaryLanguageConfig`
    - `TreeSitterLanguageConfig` (data-only; resolved by integration layers)
    - `LspLanguageConfig` with `detect_root_dir` helper (marker-based root detection)
  - Tests: `crates/editor-core-lang/tests/language_registry_tests.rs`
  - Example: `cargo run -p editor-core-lang --example language_registry`

- [x] **[integration] Tree-sitter structural selection / syntax-aware “expand selection”**
  - `editor-core-treesitter` produces highlighting + folding, but does not expose a syntax-tree
    driven selection expansion API (common in Helix/Zed/modern IDEs).
  - Implemented as `TreeSitterProcessor::expand_selection_syntax(start, end) -> Option<(start, end)>`
    (returns the next enclosing syntax node range in `char` offsets).
  - Tests: `crates/editor-core-treesitter/tests/treesitter_processor.rs`
  - Example: `cargo run -p editor-core-treesitter --example structural_selection`

- [ ] **[integration] Tree-sitter query packs / distribution**
  - The workspace has Tree-sitter processing primitives, but no first-class “query pack” story:
    - shipping and selecting highlight/fold queries per language
    - mapping captures to `StyleId`s in a consistent themeable way
  - Today this is mostly “bring your own query string”.

- [ ] **[integration] LSP feature coverage beyond the current bridges**
  - `editor-core-lsp` covers a useful subset (semantic tokens, folding, diagnostics, inlay hints,
    code lens, document links/highlights, completion apply helpers, symbol parsing).
  - Typical “full editor” LSP expectations still missing as **turnkey helpers**:
    - signature help (`textDocument/signatureHelp`)
    - hover parsing / rich hover rendering model (currently treated as JSON in UI layers)
    - rename (`textDocument/rename`) UX helpers (preview, conflict detection)
    - references (`textDocument/references`)
    - code actions (`textDocument/codeAction`) + apply helpers (incl. commands)
    - formatting (`textDocument/formatting`, range formatting) + apply helpers

- [x] **[integration] Responding to `workspace/applyEdit` automatically**
  - `LspClient::handle_server_request` currently replies to `workspace/applyEdit` with
    `{ applied: false, ... }` because it’s headless.
  - A full editor integration should:
    - apply edits into the active `Workspace`
    - respond `applied: true` (or `false` with a concrete failure reason)
    - preserve undo grouping per document
  - Implemented in `LspWorkspaceSync::poll_workspace()` (auto-applies by default; see
    `LspWorkspaceSync::set_auto_apply_workspace_edits` and `LspWorkspaceSync::drain_events`).

- [ ] **[integration] More complete “language intelligence” derived state**
  - The kernel has derived-state plumbing (`ProcessingEdit`), but the workspace does not yet ship a
    unified model for some common code-editor surfaces (depending on your target UX):
    - call hierarchy view models
    - type hierarchy view models
    - references panels / search result collections as first-class state
  - These can be done in hosts, but become painful to keep consistent across UIs.

---

## UI / rendering gaps (`editor-core-ui`, `editor-core-render-skia`)

- [ ] **[ui] Multi-document UI wrapper**
  - `editor-core` has `Workspace` (multi-buffer + multi-view), but `editor-core-ui::EditorUi`
    intentionally wraps **one buffer + one view** (with `clone_view` support).
  - A “full editor” needs a higher-level UI-facing orchestrator:
    - open/close/switch buffers (tabs)
    - per-buffer language selection + processing pipeline
    - split management + focus tracking
    - global commands (e.g. “close all”, “save all”, “find in workspace”)

- [ ] **[ui] Keybinding resolution + command dispatch**
  - The workspace provides commands; a full editor still needs:
    - keymap format (user config)
    - chord handling (e.g. `Ctrl+K Ctrl+C`)
    - platform normalization (Cmd/Ctrl variants)
    - focus/when-clauses (editor vs panels)
  - This is currently not part of `editor-core-ui`.

- [ ] **[ui] Full mouse + gesture interaction layer**
  - Core selection primitives exist, but a production editor typically expects a cohesive “mouse
    policy” implementation:
    - single/double/triple click semantics
    - drag selection + rectangular selection modifiers
    - word/line/paragraph selection rules matching platform expectations
    - scroll wheel inertia / trackpad phases (platform-specific)

- [ ] **[ui] Cross-platform windowing / widget integration**
  - `editor-core-render-skia` renders; it does not provide an actual cross-platform app/window.
  - A complete editor needs a “shell” (winit/tao/AppKit/WinUI/GTK/Qt) that manages:
    - surfaces, DPI scale, frame scheduling
    - accessibility and input method plumbing

- [ ] **[ui] IME and complex text input hardening across platforms**
  - The kernel has IME-friendly edit primitives (`ReplaceCoalescingUndo*`) and UI layers have
    marked-text style IDs, but a full editor still needs robust platform-specific IME behavior:
    - candidate window positioning
    - composition cancel/commit edge cases
    - per-platform event ordering quirks (AppKit/Win32/GTK)

- [ ] **[ui] Rendering performance features (caching + partial redraw)**
  - Skia rendering exists, but “full editor” workloads often need:
    - glyph run caching across frames
    - minimap rendering strategy (throttling / caching)
    - partial invalidation (only redraw dirty rows when possible)

---

## FFI / embedding gaps (`editor-core-ffi`, `editor-core-ui-ffi`)

- [ ] **[ui] Expand the typed ABI surface to cover more than the hot path**
  - The typed ABI is great for per-keystroke and per-frame operations, but some non-hot-path
    surfaces are still easier to use via JSON control-plane APIs.
  - A production embedding typically wants more “typed” coverage over time (to reduce JSON churn).

- [ ] **[host] Packaging + distribution story for each target platform**
  - Building and shipping Skia + Rust + headers for:
    - macOS app bundles / Swift packages
    - Windows (MSVC, .dll + .lib, C#/C++)
    - Linux (so/distro portability)
  - This is typically solved in the host build system, not inside the kernel crates.

---

## Product-level gaps (expected in a full editor, but not a great fit for these crates)

- [ ] **[host] File I/O and encoding handling**
  - The kernel is UTF-8 internally; a full editor must handle:
    - encoding detection (UTF-8/UTF-16/legacy code pages)
    - BOM handling
    - “mixed line endings” policy
    - atomic saves, backups, file permissions

- [ ] **[host] Workspace filesystem model**
  - Project tree, file watchers, “dirty on disk” detection, and reload prompts.

- [ ] **[host] Search across workspace files (not just open buffers)**
  - `Workspace::search_all_open_buffers` exists, but “Find in Files” typically requires:
    - filesystem crawling
    - ignore files (.gitignore/.ignore)
    - ripgrep-like performance

- [ ] **[host] UI surfaces outside the editor viewport**
  - Tabs, command palette, settings UI, completion UI, hover UI, symbol search UI, diagnostics
    panel, etc.
  - The kernel can supply the data, but the widgets are host-level.

- [ ] **[host] Plugin/extension host**
  - Explicitly out of scope for the kernel crates, but required for VS Code-like extensibility.

- [ ] **[host] Collaboration (CRDT / multi-user)**
  - Explicitly out of scope per `ROADMAP.md`, but required for real-time collaborative editors.
