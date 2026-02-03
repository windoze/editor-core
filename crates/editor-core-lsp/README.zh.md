# editor-core-lsp

`editor-core-lsp` 为 `editor-core` 提供**语言服务器协议(LSP)**集成工具。它专为无头/编辑器内核使用而设计:无 UI 假设,无异步运行时要求,依赖面小。

## 特性

- **UTF-16 坐标转换**(`LspCoordinateConverter`)用于在编辑器字符偏移量和 LSP 位置之间映射。
- **增量变更计算**(`DeltaCalculator`)用于生成 `didChange` 样式的编辑。
- **语义令牌助手**:
  - 将 LSP 语义令牌解码为编辑器样式区间
  - 稳定的样式 ID 编码/解码助手
  - `SemanticTokensManager` 用于相对→绝对转换
- **工作区编辑助手**: 使用 `serde_json::Value` 解析/应用 `TextEdit` / `WorkspaceEdit` 结构。
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

宿主可以通过 `EditorStateManager::apply_processing_edits` 应用这些编辑。

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

## 注意事项

- LSP 服务器在能力和期望上差异很大;`LspSession` 旨在成为一个实用的无头助手,而非完整类型化的 LSP 框架。
- 有关 UI 层面的通知和服务器→客户端请求,请参见 `LspEvent` / `LspNotification` 和服务器请求策略助手。
