# editor-core-lsp

`editor-core-lsp` 为 `editor-core` 提供**语言服务器协议（LSP）**集成工具。它专为无头/编辑器内核使用而设计：
无 UI 假设、无异步运行时要求、依赖面小。

## 特性

- **UTF-16 坐标转换**(`LspCoordinateConverter`)用于在编辑器字符偏移量和 LSP 位置之间映射。
- **增量变更计算**(`DeltaCalculator`)用于生成 `didChange` 样式的编辑。
- **语义令牌助手**:
  - 将 LSP 语义令牌解码为编辑器样式区间
  - 稳定的样式 ID 编码/解码助手
  - `SemanticTokensManager` 用于相对→绝对转换
- **工作区编辑助手**: 使用 `serde_json::Value` 解析/应用 `TextEdit` / `WorkspaceEdit` 结构。
- **常见 UX 桥接**(LSP → 内核派生状态):
  - 文档高亮 → `ProcessingEdit::ReplaceStyleLayer`(`StyleLayerId::DOCUMENT_HIGHLIGHTS`)
  - 文档链接 → `ProcessingEdit::ReplaceDecorations`(`DecorationLayerId::DOCUMENT_LINKS`)
  - Code lens → `ProcessingEdit::ReplaceDecorations`(`DecorationLayerId::CODE_LENS`)
  - 补全应用助手: 批量应用 `additionalTextEdits`，并对 snippet 形态插入做尽力降级
- **符号/大纲助手**:
  - 文档符号(`textDocument/documentSymbol`) → `DocumentOutline` / `ProcessingEdit::ReplaceDocumentSymbols`
  - 工作区符号(`workspace/symbol`) → `Vec<WorkspaceSymbol>`
- **Stdio JSON-RPC 客户端**(`LspClient`)用于驱动 LSP 服务器进程。
- **高级会话包装器**(`LspSession`)用于轮询消息、发出类型化事件,并为编辑器生成派生状态编辑(`ProcessingEdit`)。

## 设计概览

此 crate 特意使用 `serde_json::Value` 而不是 `lsp-types`:

- 保持 crate 轻量且灵活。
- 让宿主在不改变类型层面的情况下塑造/扩展负载。
- 适用于 UI 无关的集成(TUI、测试、嵌入式等)。

### 派生状态集成

`LspSession` 将服务器结果转换为 `editor-core` 的派生状态格式:

- 语义令牌 → `ProcessingEdit::ReplaceStyleLayer`(通常为 `StyleLayerId::SEMANTIC_TOKENS`)
- 折叠范围 → `ProcessingEdit::ReplaceFoldingRegions`
- Inlay hints → `ProcessingEdit::ReplaceDecorations`(通常为 `DecorationLayerId::INLAY_HINTS`)

宿主可以通过以下方式应用这些编辑：

- `EditorStateManager::apply_processing_edits`（单 buffer / 单 view）
- `Workspace::apply_processing_edits(buffer_id, edits)`（多 buffer / 多 view）

### UX 桥接(手动/按需)

部分 LSP 功能通常是按需请求的(例如 document highlight、document link、code lens、completion 等)。
本 crate 提供了一些小型 helper，把常见结果 payload 转换为 `editor-core` 的派生状态编辑或内核编辑命令:

```rust
use editor_core::{EditorStateManager};
use editor_core_lsp::{
    CompletionTextEditMode, apply_completion_item,
    lsp_code_lens_to_processing_edit, lsp_document_highlights_to_processing_edit,
    lsp_document_links_to_processing_edit,
};
use serde_json::json;

let mut state = EditorStateManager::new("fn main() {\n    fo\n}\n", 80);

// `textDocument/documentHighlight` -> 样式层
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

// 将 `CompletionItem` 作为一次可撤销操作应用(additionalTextEdits + snippets)。
let completion_item = json!({
  "insertTextFormat": 2,
  "textEdit": { "range": { "start": { "line": 1, "character": 4 }, "end": { "line": 1, "character": 6 } }, "newText": "println!(${1:msg})$0" }
});
apply_completion_item(&mut state, &completion_item, CompletionTextEditMode::Insert).unwrap();
```

## 快速开始

### 添加依赖

```toml
[dependencies]
editor-core-lsp = "0.1"
```

### 轮询会话(高级)

宿主负责为目标服务器提供适当的 `initialize` 参数。

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

// 在主循环中:
session.poll(&mut state).unwrap();
// 使用 `state.get_viewport_content(...)` 等进行渲染。
```

### 多文档：接入 `editor_core::Workspace`

如果你的宿主编辑器需要 tab/分屏，一般会使用 `editor_core::Workspace` 配合 `LspWorkspaceSync`
（见 `crates/editor-core-lsp/src/workspace_sync.rs`）：

- 通过 `Workspace::open_buffer` 或 `Workspace::set_buffer_uri` 确保每个打开的 buffer 都有稳定的 URI
  （例如 `file:///...`）。
- 当一个 buffer 需要被 LSP 会话跟踪时，调用
  `LspWorkspaceSync::open_workspace_document(&workspace, buffer_id, language_id)`。
- 本地编辑之后，调用
  `LspWorkspaceSync::did_change_from_text_delta(&mut workspace, buffer_id)`，基于该 buffer 的最后一次
  `TextDelta` 发送 `textDocument/didChange`。
- 在主循环中调用 `LspWorkspaceSync::poll_workspace(&mut workspace)`，以：
  - 将派生状态编辑（语义 token、折叠等）应用到当前活跃 buffer
  - 根据 URI 把 `publishDiagnostics` 路由到正确的 buffer
- 对于服务端触发的多文件编辑，调用
  `LspWorkspaceSync::apply_workspace_edit(&mut workspace, &workspace_edit_value)`。

## 注意事项

- LSP 服务器在能力和期望上差异很大;`LspSession` 旨在成为一个实用的无头助手,而非完整类型化的 LSP 框架。
- 有关 UI 层面的通知和服务器→客户端请求,请参见 `LspEvent` / `LspNotification` 和服务器请求策略助手。

### 示例

运行一个小型 bridges demo(纯 JSON `Value` 输入):

```bash
cargo run -p editor-core-lsp --example bridges_v1
```
