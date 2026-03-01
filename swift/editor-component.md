# Swift Editor Component Plan (AppKit + TextKit)

This document defines the implementation plan for a Swift-first editor UI component targeting macOS AppKit, backed by `editor-core` capabilities (core, LSP, sublime, tree-sitter) via adapter interfaces.

## Goals

- Build an AppKit component that can be embedded into native macOS apps.
- Use TextKit for text rendering and input (ligatures, emoji, grapheme-safe handling).
- Surface styles, inlay text, line numbers, folding, optional gutter/minimap, and structural guides.
- Provide keybinding/command routing and host extension points for hover/context menus.
- Include tests, runnable examples, and integration docs.

## Implementation Steps

## Step 1: Plan + Scope Freeze

Deliverables:

- This plan document (`swift/editor-component.md`).
- Scope boundaries and phased acceptance criteria.

Commit message:

- `docs(swift): add AppKit editor component implementation plan`

## Step 2: Package Scaffold + Core Architecture

Deliverables:

- New SwiftPM package under `swift/`.
- Core modules/types:
  - `EditorPosition`, `EditorSelection`, `EditorSnapshot`, `EditorStyleSpan`, `EditorInlay`, `EditorFoldRegion`.
  - `EditorEngineProtocol` (engine adapter interface for editor-core features).
  - `EditorCommand`, `EditorCommandDispatcher`, `EditorKeybindingRegistry`.
  - `EditorComponentView` host container with AppKit subviews.

Acceptance criteria:

- Package builds.
- Basic component can be instantiated in tests.

Commit message:

- `feat(swift): scaffold AppKit editor component package and core architecture`

## Step 3: TextKit Rendering + Visual Features

Deliverables:

- TextKit-backed editor view (`NSTextView`/`NSLayoutManager` integration).
- Styling pipeline (style spans -> attributed text/temporary attributes).
- Inlay rendering layer (non-destructive visual inserts).
- Gutter with line numbers and folding affordances.
- Indentation/code-structure guide overlays.
- Optional minimap view.

Acceptance criteria:

- Component renders text and styles.
- Inlay overlays are visible without mutating source text.
- Gutter/minimap/guides can be toggled.

Commit message:

- `feat(swift): implement TextKit rendering, styles, inlays, gutter, guides, and minimap`

## Step 4: Commands, Keybindings, Hover, Context Menus

Deliverables:

- Keybinding registry with customizable mappings.
- Command dispatch bridge from key events to engine commands.
- Hover provider protocol + tooltip bridge hooks.
- Context-menu provider protocol + menu construction hooks.
- Folding toggle interaction from gutter.

Acceptance criteria:

- Keybinding remap works.
- Hover/context hooks are callable from host app.

Commit message:

- `feat(swift): add command routing, keybinding customization, hover and context menu interfaces`

## Step 5: Tests, Example App, Documentation

Deliverables:

- Comprehensive unit tests:
  - keybinding resolution
  - command dispatch plumbing
  - style/inlay/folding model transforms
  - viewport/minimap rendering state derivation
- AppKit integration tests for component creation and interaction wiring.
- Runnable demo target (AppKit window with editor component).
- Documentation:
  - `swift/README.md` (architecture + usage)
  - API usage snippets

Acceptance criteria:

- `swift test` passes.
- Demo target builds and launches.
- Docs explain embedding + extension points.

Commit message:

- `test(swift): add editor component test suite, demo app, and usage documentation`

## Build and Test Commands

- `cd swift && swift build`
- `cd swift && swift test`
- `cd swift && swift run EditorComponentDemo`

## Notes and Constraints

- Engine integration is adapter-first (`EditorEngineProtocol`) so host apps can choose transport:
  - direct C ABI (`editor-core-ffi`)
  - IPC/service boundary
  - mock engine for tests
- Full parity with all `editor-core-*` features is represented in protocol/API surfaces first, with incremental deepening for rendering and UX.
- TextKit owns input and glyph rendering; editor-core remains source of truth for document state and derived metadata.
