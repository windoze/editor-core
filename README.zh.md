# editor-core (工作空间)

无头编辑器引擎 + 集成，用于构建 UI 无关的文本编辑器。

`editor-core` 专注于：

- **状态管理**（命令、撤销/重做、选择状态、变更通知）
- **Unicode 感知度量**（CJK/emoji 的单元格宽度）
- **坐标转换**（字符偏移量 ⇄ 行/列 ⇄ 换行后的"视觉"行；以及用于 LSP 的 UTF-16）

本项目特意设计为 **UI 无关**：前端从快照（`HeadlessGrid`）渲染，并通过命令/状态 API 驱动编辑操作。

## 工作空间 crates

- `crates/editor-core/` — 核心无头编辑器引擎（`PieceTable`、`LineIndex`、`LayoutEngine`、快照、命令/状态）。
  - 参见 `crates/editor-core/README.md`
- `crates/editor-core-lsp/` — LSP 集成（UTF-16 转换、语义 token 解码、stdio JSON-RPC 客户端/会话）。
  - 参见 `crates/editor-core-lsp/README.md`
- `crates/editor-core-sublime/` — `.sublime-syntax` 高亮 + 折叠引擎（以样式区间 + 折叠区域形式输出无头数据）。
  - 参见 `crates/editor-core-sublime/README.md`
- `crates/editor-core-highlight-simple/` — 轻量级基于正则表达式的高亮辅助工具（JSON/INI 等）。
- `crates/tui-editor/` — 可运行的 TUI 演示应用（ratatui + crossterm），将所有组件连接在一起。

## 核心概念（TL;DR）

### 偏移量与坐标

编辑器在 API 边界一致使用**字符偏移量**（Rust `char` 索引）：

- **字符偏移量**：文档中以 Unicode 标量值（而非字节）为单位的索引。
- **逻辑位置**：`(line, column)`，其中 `column` 也以 `char` 为单位计数。
- **视觉位置**：经过**软换行**（以及可选的折叠）后，单个逻辑行可以映射到多个视觉行。
- **LSP 位置**：`(line, character)`，其中 `character` 是 **UTF-16 code units**（参见 `editor-core-lsp`）。

本项目目前*不*支持"按 grapheme cluster 移动光标"（例如， 家庭 emoji 序列比如“👨‍👩‍👧‍👦” 是多个 `char`）。许多编辑器选择支持 grapheme-cluster 感知的移动；如果需要，可以在命令逻辑层实现。

### "文本网格"快照（渲染输入）

前端从 `HeadlessGrid` 渲染：

- 快照包含一个**视觉行**列表。
- 每行是一个**单元格**列表，其中 `Cell.width` 通常为 `1` 或 `2`（Unicode 感知）。
- 每个单元格携带一个 `StyleId` 列表；UI/主题层将 `StyleId` 映射到颜色/字体。

### 派生状态流水线（高亮/折叠）

派生元数据（语义 token、语法高亮、折叠范围、诊断叠加层等）表示为编辑器的**派生状态**编辑：

- `DocumentProcessor` 计算一个 `ProcessingEdit` 列表。
- `EditorStateManager::apply_processing_edits` 应用这些编辑（替换样式层、折叠区域等）。

这使得高层集成可组合，并保持核心引擎 UI 无关。

## 快速开始

### 要求

- Rust **1.91+**（参见工作空间 `Cargo.toml` 中的 `rust-version`）

### 构建和测试

```bash
cargo build
cargo test
```

仅运行主 `editor-core` 集成测试：

```bash
cargo test -p editor-core --test integration_test
```

### 运行 TUI 演示

```bash
cargo run -p tui-editor -- crates/editor-core/tests/fixtures/demo_file.txt
```

TUI 演示支持：

- 软换行 + Unicode 宽度
- 选择、多光标、矩形选择
- 查找/替换
- 通过 Sublime syntax 或 LSP 的可选高亮/折叠

#### 可选：Sublime `.sublime-syntax`

如果当前目录包含匹配的 `.sublime-syntax` 文件（例如：`Rust.sublime-syntax` 或 `TOML.sublime-syntax`），`tui-editor` 将自动启用 `editor-core-sublime` 高亮和折叠。否则将回退到内置的正则表达式高亮器处理简单格式（JSON/INI）。

#### 可选：LSP（stdio JSON-RPC）

演示可以连接到任何 stdio LSP 服务器。

- 默认行为：打开 `.rs` 文件时，将尝试启动 `rust-analyzer`（如果已安装）。
- 通过环境变量覆盖（适用于所有文件类型）：

```bash
# 示例：Python
EDITOR_CORE_LSP_CMD=pylsp \
EDITOR_CORE_LSP_LANGUAGE_ID=python \
cargo run -p tui-editor -- foo.py
```

其他环境变量：

- `EDITOR_CORE_LSP_ARGS` — 传递给 LSP 服务器的空格分隔参数
- `EDITOR_CORE_LSP_ROOT` — 覆盖 LSP 初始化的工作空间根目录

## 将 `editor-core` 作为库使用

大多数应用的推荐入口点是 `EditorStateManager`：

- 它包装了 `CommandExecutor` + `EditorCore`
- 它跟踪 `version` + `is_modified`
- 它发出变更通知
- 它提供视口/快照辅助工具

### 最小编辑 + 渲染循环

```rust
use editor_core::{Command, EditCommand, EditorStateManager};

let mut state = EditorStateManager::new("Hello\nWorld\n", 80);

// 通过命令接口应用编辑。
state.execute(Command::Edit(EditCommand::Insert {
    offset: 0,
    text: "Title: ".to_string(),
})).unwrap();

// 渲染视口快照（视觉行）。
let grid = state.get_viewport_content_styled(0, 20);
assert!(grid.actual_line_count() > 0);
```

### 添加派生高亮（简单格式）

```rust
use editor_core::EditorStateManager;
use editor_core_highlight_simple::{RegexHighlightProcessor, SimpleJsonStyles};

let mut state = EditorStateManager::new(r#"{ "k": 1, "ok": true }"#, 80);

let mut processor =
    RegexHighlightProcessor::json_default(SimpleJsonStyles::default()).unwrap();
state.apply_processor(&mut processor).unwrap();

let grid = state.get_viewport_content_styled(0, 10);
assert!(grid.lines[0].cells.iter().any(|c| !c.styles.is_empty()));
```

对于更丰富的语法高亮和折叠，请使用：

- `editor-core-sublime`（`SublimeProcessor`）
- `editor-core-lsp`（`LspSession`）

## 文档

- 设计文档：`docs/DESIGN.md`
- API 文档：`cargo doc --no-deps --open`
- 示例：
  - `cargo run -p editor-core --example command_interface`
  - `cargo run -p editor-core --example state_management`

## 开发注意事项

常用命令：

```bash
cargo fmt
cargo clippy --all-targets --all-features
```

仓库布局要点：

- `crates/editor-core/src/` — 存储/索引/布局/区间/快照 + 命令/状态层
- `crates/*/tests/` — 阶段验证和集成测试

## 许可证

本内容采用以下任一许可证授权：

* Apache许可证第2.0版（LICENSE-APACHE 或 http://www.apache.org/licenses/LICENSE-2.0）
* MIT许可证（LICENSE-MIT 或 http://opensource.org/licenses/MIT）

