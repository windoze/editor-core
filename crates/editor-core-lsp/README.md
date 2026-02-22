# editor-core-lsp

`editor-core-lsp` provides **Language Server Protocol (LSP)** integration utilities for
`editor-core`. It is designed for headless/editor-kernel use: no UI assumptions, no async runtime
requirements, and a small dependency surface.

## Features

- **UTF-16 coordinate conversion** (`LspCoordinateConverter`) for mapping between editor
  character offsets and LSP positions.
- **Incremental change calculation** (`DeltaCalculator`) for producing `didChange`-style edits.
- **Semantic tokens helpers**:
  - decode LSP semantic tokens into editor style intervals
  - stable style id encoding/decoding helpers
  - `SemanticTokensManager` for relative→absolute conversion
- **Workspace edit helpers**: parse/apply `TextEdit` / `WorkspaceEdit` shapes using `serde_json::Value`.
- **Common UX bridges** (LSP → kernel derived state):
  - document highlights → `ProcessingEdit::ReplaceStyleLayer` (`StyleLayerId::DOCUMENT_HIGHLIGHTS`)
  - document links → `ProcessingEdit::ReplaceDecorations` (`DecorationLayerId::DOCUMENT_LINKS`)
  - code lens → `ProcessingEdit::ReplaceDecorations` (`DecorationLayerId::CODE_LENS`)
  - completion apply helpers: batch `additionalTextEdits` and best-effort snippet downgrade
- **Symbols/outline helpers**:
  - document symbols (`textDocument/documentSymbol`) → `DocumentOutline` / `ProcessingEdit::ReplaceDocumentSymbols`
  - workspace symbols (`workspace/symbol`) → `Vec<WorkspaceSymbol>`
- **Stdio JSON-RPC client** (`LspClient`) for driving an LSP server process.
- **High-level session wrapper** (`LspSession`) that polls messages, emits typed events, and produces
  derived-state edits (`ProcessingEdit`) for the editor.

## Design overview

This crate intentionally uses `serde_json::Value` instead of `lsp-types`:

- Keeps the crate lightweight and flexible.
- Lets hosts shape/extend payloads without type-level churn.
- Works well for UI-agnostic integrations (TUI, tests, embedded, etc.).

### Derived state integration

`LspSession` converts server results into `editor-core`’s derived-state format:

- Semantic tokens → `ProcessingEdit::ReplaceStyleLayer` (typically `StyleLayerId::SEMANTIC_TOKENS`)
- Folding ranges → `ProcessingEdit::ReplaceFoldingRegions`
- Inlay hints → `ProcessingEdit::ReplaceDecorations` (typically `DecorationLayerId::INLAY_HINTS`)

Hosts can apply those edits via `EditorStateManager::apply_processing_edits`.

### UX bridges (manual / on-demand)

Some LSP features are typically requested on demand (cursor hover, go-to, document highlight, ...).
This crate provides small helpers that convert common result payloads into `editor-core` derived
state edits or kernel edit commands:

```rust
use editor_core::{EditorStateManager};
use editor_core_lsp::{
    CompletionTextEditMode, apply_completion_item,
    lsp_code_lens_to_processing_edit, lsp_document_highlights_to_processing_edit,
    lsp_document_links_to_processing_edit,
};
use serde_json::json;

let mut state = EditorStateManager::new("fn main() {\n    fo\n}\n", 80);

// `textDocument/documentHighlight` -> style layer
let highlights = json!([
  { "range": { "start": { "line": 1, "character": 4 }, "end": { "line": 1, "character": 6 } }, "kind": 1 }
]);
state.apply_processing_edits(vec![
  lsp_document_highlights_to_processing_edit(&state.editor().line_index, &highlights)
]);

// `textDocument/documentLink` -> decorations
let links = json!([
  { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 2 } }, "target": "https://example.com" }
]);
state.apply_processing_edits(vec![
  lsp_document_links_to_processing_edit(&state.editor().line_index, &links)
]);

// `textDocument/codeLens` -> decorations
let lenses = json!([
  { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } }, "command": { "title": "Run", "command": "run" } }
]);
state.apply_processing_edits(vec![
  lsp_code_lens_to_processing_edit(&state.editor().line_index, &lenses)
]);

// Apply a `CompletionItem` as a single undoable step (additionalTextEdits + snippets).
let completion_item = json!({
  "insertTextFormat": 2,
  "textEdit": { "range": { "start": { "line": 1, "character": 4 }, "end": { "line": 1, "character": 6 } }, "newText": "println!(${1:msg})$0" }
});
apply_completion_item(&mut state, &completion_item, CompletionTextEditMode::Insert).unwrap();
```

## Quick start

### Add the dependency

```toml
[dependencies]
editor-core-lsp = "0.1"
```

### Polling a session (high-level)

The host is responsible for providing `initialize` params appropriate for the target server.

```rust
use editor_core::{EditorStateManager};
use editor_core_lsp::{LspDocument, LspSession, LspSessionStartOptions};
use serde_json::json;
use std::process::Command;
use std::time::Duration;

let mut state = EditorStateManager::new("fn main() {}\n", 80);

let session = LspSession::start(LspSessionStartOptions {
    cmd: Command::new("rust-analyzer"),
    workspace_folders: vec![],
    initialize_params: json!({
        "capabilities": {},
        "rootUri": null,
        "workspaceFolders": [],
    }),
    initialize_timeout: Duration::from_secs(10),
    document: LspDocument { uri: "file:///tmp/main.rs".into(), language_id: "rust".into(), version: 1 },
    initial_text: state.editor().get_text(),
}).unwrap();

let mut session = session;

// In your main loop:
session.poll(&mut state).unwrap();
// Render using `state.get_viewport_content(...)`, etc.
```

## Notes

- LSP servers vary widely in capabilities and expectations; `LspSession` aims to be a practical
  headless helper, not a fully typed LSP framework.
- For UI-facing notifications and server->client requests, see `LspEvent` / `LspNotification` and
  the server-request policy helpers.

### Examples

Run a small "bridges" demo (pure JSON `Value` inputs):

```bash
cargo run -p editor-core-lsp --example bridges_v1
```
