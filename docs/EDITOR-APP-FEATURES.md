# Editor App Features (Helix / Sublime-class, not an IDE)

This document lists what a **full-featured code editor application** should have when built on
top of the `editor-core*` crates.

Target parity:

- “Mainstream editor” UX like **Helix** or **Sublime Text** (fast, keyboard-friendly, code-focused).
- **Not** an IDE-style product like VS Code / Xcode (no debugger, no extension marketplace, etc.).

Platform targets (native frontends, shared Rust core):

- **Windows**: WinUI 3 + C++
- **macOS**: AppKit + Swift (today’s `AttoEditor` baseline)
- **Linux**: GTK 4 (C++ or Rust)

This list intentionally includes features that already exist in **AttoEditor** (macOS-only today),
because the goal is to ship the same capabilities on all target platforms.

---

## Scope & non-goals

### In scope

- A fast, responsive editor for **code + plain text**.
- Multi-file workflows: open folder, quick-open, tabs, splits.
- Syntax highlighting + folding (Tree-sitter/Sublime syntax), and **optional LSP** features (Helix-class).
- A solid “editor shell”: command palette, settings, keybindings, basic panels.

### Explicit non-goals

- **IDE features**:
  - debugger / breakpoints / run targets UI
  - extension marketplace / full plugin host (lightweight scripting may be considered later, but not required for parity)
  - project build systems UI, test explorer UI, container/remote dev UI
- **Horizontal scrolling** (explicitly ruled out for this project).
- **BiDi / RTL correctness** (explicitly ruled out for this project).

Note: an **integrated terminal** can still be useful in a code editor app, but it’s treated as an
**optional, low-priority** add-on (see “11) Optional add-ons”) rather than a core IDE scope item.

---

## Cross-platform architecture requirements

Tag legend (for bring-up priority):

- **[xplat]** cross-platform and **does not rely on OS/platform-specific system integration**
  (e.g. IME, clipboard, file dialogs/pickers, native menus, drag&drop, file associations, PTY).
  Good candidates to start from; implement once and share across platforms where possible.

Checklist policy:

- For **[xplat]** items, `[x]` means the workspace contains a **shared Rust implementation**
  (kernel / app-shell helpers / UI wrapper primitives) with tests where appropriate.
- Platform frontends may still need to supply **OS integration + widgets** around these primitives.

- [x] **[xplat]** **Shared core**: all editing/layout/highlighting state comes from Rust (`editor-core*`).
- [x] **[xplat]** **Stable FFI boundary**: platform UIs talk to Rust via `editor-core-ffi` / `editor-core-ui-ffi`.
- [x] **[xplat]** **Feature parity policy**: define “must match” behaviors across platforms (selection, undo grouping, find/replace, etc.).
- [x] **[xplat]** **Input parity**: consistent keyboard shortcuts and text-edit semantics across platforms, with per-OS conventions where appropriate.
- [ ] **Rendering portability**: a clear story for GPU backends per OS (Metal / D3D / Vulkan|GL) plus a CPU fallback for bring-up/testing.

---

## Feature checklist (editor app)

### 1) Workspace, files, and sessions

- [x] **[xplat]** **Open folder (workspace root)** (AttoEditor: yes)
- [x] **[xplat]** **File explorer sidebar** with directory tree, expand/collapse, and “reveal in tree” (AttoEditor: yes)
- [x] **[xplat]** **Open file** from explorer (AttoEditor: yes)
- [ ] **Open file** from file dialog / picker (AttoEditor: yes)
- [x] **[xplat]** **Preview vs pinned open**
  - single-click previews a file in a transient tab
  - double-click (or edit) pins the tab (AttoEditor: yes)
- [x] **[xplat]** **Tabs**
  - close tab / close others / close to the right
  - dirty indicators and “unsaved changes” prompts (AttoEditor: yes for dirty + save)
- [x] **[xplat]** **Recent folders + recent files** (AttoEditor: yes for recent files)
- [x] **[xplat]** **Session restore**
  - reopen last workspace folder
  - reopen last open tabs/splits (optional “hot exit”)
- [x] **[xplat]** **Save flows**
  - save, save as, save all
  - atomic save + safe-write policy
  - preserve file permissions (when possible)
- [ ] **External file change detection**
  - prompt to reload if modified on disk
  - handle deleted/renamed files gracefully
- [x] **[xplat]** **Encoding + newline policy**
  - default UTF-8
  - detect / preserve CRLF vs LF on save (kernel supports newline preference; app must wire it)
- [x] **[xplat]** **“Find in Files” (workspace search)**
  - search across the filesystem (not just open buffers)
  - respect ignore rules (`.gitignore`, `.ignore`, custom excludes)

### 2) Editor layout: tabs, splits, panes

- [x] **[xplat]** **Split panes** (vertical + horizontal)
  - multiple views into the same buffer (shared text, independent cursor/scroll)
  - drag tab to split / move tab between splits
- [x] **[xplat]** **Multiple windows** (optional, but common in Sublime-class editors)
- [x] **[xplat]** **Focus management** and keyboard navigation between panes
- [x] **[xplat]** **Minimap** (AttoEditor: yes)
  - placement options (right of scrollbar vs far right)
  - click/drag to scroll (minimap navigation)
- [x] **[xplat]** **Scrollbars**
  - smooth scrolling
  - optional markers (search matches, diagnostics)
- [x] **[xplat]** **Status bar** (AttoEditor: yes)
  - path (or relative path), line/column, selection length, file size
  - language name + indentation settings (tab width, spaces/tabs)

### 3) Editing fundamentals (text, selections, undo)

- [x] **[xplat]** **Core editing**
  - insert/delete/backspace
  - newline + auto-indent
  - tabs/spaces behavior and tab width setting
- [x] **[xplat]** **Selections**
  - normal selection, extend selection, select all
  - word/line selection
  - rectangular/column selection
- [x] **[xplat]** **Multi-cursor**
  - add cursor above/below
  - add next/all occurrence
  - multi-cursor paste/typing semantics
- [x] **[xplat]** **Undo/redo with sensible grouping** (AttoEditor: yes)
- [ ] **Clipboard integration**
  - cut/copy/paste
  - multi-selection copy semantics
  - primary selection behavior on Linux (optional, but expected by many Linux users)
- [ ] **IME / composition input**
  - macOS marked text (AttoEditor baseline includes IME in the AppKit component)
  - Windows IME (TSF)
  - Linux IME (IBus/Fcitx via GTK)
- [x] **[xplat]** **Line operations**
  - duplicate lines, delete lines, move lines up/down, join lines, split line
- [x] **[xplat]** **Comment toggling** (language-config driven; kernel has primitives)
- [x] **[xplat]** **Auto-pairs and bracket matching** (expected for mainstream code editing)
- [x] **[xplat]** **Snippets**
  - snippet insertion (including LSP snippet completions)
  - placeholder navigation (tab/shift-tab)

### 4) Search & navigation

- [x] **[xplat]** **Find in file**
  - incremental search, next/prev
  - regex + whole-word + case sensitivity
  - replace current / replace all
- [x] **[xplat]** **Search results UI**
  - show matches with context
  - click to jump; keep results stable as buffers change
- [x] **[xplat]** **Go to line / column**
- [x] **[xplat]** **Go to file** (fuzzy quick-open) (AttoEditor: yes)
- [x] **[xplat]** **Go to symbol** (document symbols + workspace symbols)
- [x] **[xplat]** **Jump list** (back/forward navigation) and **bookmarks**

### 5) Rendering + visual aids (code-friendly UX)

- [x] **[xplat]** **Themes**
  - dark/light theme bundles
  - user theme overrides
  - stable `StyleId` → color mapping (shared across platforms)
- [x] **[xplat]** **Font configuration**
  - font family fallback list
  - font size, line height
  - ligatures toggle (AttoEditor: yes)
- [x] **[xplat]** **Gutter** (AttoEditor: yes)
  - line numbers
  - fold markers
  - optional diagnostics markers
- [x] **[xplat]** **Indent guides** (AttoEditor: yes)
- [x] **[xplat]** **Whitespace rendering modes** (AttoEditor: yes: selection-only)
- [x] **[xplat]** **Code folding**
  - fold/unfold at cursor
  - fold/unfold all
  - preserve user folds under edits
- [x] **[xplat]** **Hover + link interactions**
  - open document links
  - tooltip/popover for hover content (AttoEditor: yes)
- [x] **[xplat]** **Context menu basics** (AttoEditor: yes for cut/copy/paste/select all)

### 6) Language features (highlighting, folding, LSP)

- [x] **[xplat]** **Syntax highlighting + folding pipeline**
  - Tree-sitter based highlighting/folding
  - Sublime `.sublime-syntax` highlighting/folding (optional compatibility path)
  - fallback “simple regex” highlighting for tiny formats
- [x] **[xplat]** **LSP integration (optional but Helix-class)**
  - per-language LSP server config (command/args/root detection)
  - server lifecycle: start/stop/restart, logs, error surfaces
- [x] **[xplat]** **Core LSP UX**
  - diagnostics (underline + list panel)
  - completion popup + apply (incl. additionalTextEdits)
  - hover (AttoEditor: yes)
  - go to definition (AttoEditor: yes via Cmd-click)
  - references
  - rename
  - formatting (document + range)
  - code actions (lightweight UI)
- [x] **[xplat]** **Symbols**
  - outline view (document symbols)
  - workspace symbol search
- [x] **[xplat]** **Virtual text**
  - inlay hints
  - code lens (optional)

### 7) Command system, keybindings, and settings

- [x] **[xplat]** **Command palette** with fuzzy search + keyboard navigation (AttoEditor: yes)
- [x] **[xplat]** **Keybinding system**
  - configurable keymaps
  - multi-stroke chords (optional)
  - per-OS default bindings (Cmd vs Ctrl conventions)
- [x] **[xplat]** **Settings system**
  - human-editable config file (TOML/JSON)
  - live reload (or “reload settings” command)
  - per-language overrides (tab width, wrap mode, etc.)
- [x] **[xplat]** **Discoverability**
  - command palette entries mirror core commands and show shortcuts
  - “open settings / keybindings” commands

### 8) Platform integration polish

- [ ] **Native menus + standard shortcuts**
  - macOS menu bar + “Services” integration (optional)
  - Windows app menu/ribbon conventions (keep it simple)
  - Linux app menu (or header bar actions)
  - menu items mirror core commands and show shortcuts
- [x] **[xplat]** **Command line interface (CLI) / system editor integration**
  - open files/dirs from the shell: `editor <path>...` (including `editor .`)
  - optional `--wait`: block until the opened file(s) are closed in the UI (for `$EDITOR` workflows)
  - exit code on `--wait`: `0` if unchanged, `1` if changed (and `>1` for errors); for multiple files, return `1` if any file changed
  - (optional) `--line/--column` (or `file:line:col`) for “open at location”
- [ ] **File associations / “Open With…” support**
- [ ] **Drag & drop**
  - drop files to open
  - (optional) drag tabs between windows
- [ ] **Accessibility (minimum viable)**
  - focus rings / keyboard navigation
  - high-contrast compatibility
  - screen-reader baseline support where feasible

### 9) Reliability, performance, and diagnostics

- [x] **[xplat]** **Large file handling**
  - responsive open, scroll, selection, and search on big inputs
  - background processing degradation modes (visible-range highlighting, debounce)
- [x] **[xplat]** **Crash resilience**
  - recoverable session state
  - safe autosave (optional)
- [x] **[xplat]** **Observability**
  - internal logs view (or log file)
  - performance counters for render + processing (debug builds)

### 10) Shipping & maintenance (multi-platform)

- [ ] **CI builds on all targets** (Windows/macOS/Linux)
- [ ] **Packaging**
  - macOS: signed + notarized app bundle (if distributing outside dev)
  - Windows: installer/MSIX (or zip for dev builds), signing (optional early)
  - Linux: AppImage/Flatpak/deb (choose one first)
- [ ] **Update mechanism** (optional early; required for mainstream distribution later)
- [ ] **Compatibility tests**
  - cross-platform smoke tests for open/edit/save/find
  - golden rendering tests where practical

### 11) Optional add-ons (low priority)

- [ ] **Integrated terminal** (`integrated-terminal`) (optional, low priority)
  - useful for running project commands (tests/formatters/git) without leaving the editor
  - explicitly **not** a full IDE “run/debug/tasks” surface
  - note: requires PTY + process integration per OS; treat as a separate module / effort
