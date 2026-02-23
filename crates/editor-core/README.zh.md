# editor-core

`editor-core` 是一个**无头（headless）**编辑器引擎，专注于状态管理、Unicode 感知的文本测量和坐标转换。
它特意设计为 UI 无关：使用者从快照渲染，并通过命令/状态 API 驱动编辑操作。

## 特性

- **高效的文本存储**：使用 Piece Table（`PieceTable`）支持插入/删除。
- **快速的行索引**：基于 rope 的 `LineIndex`，用于行访问和各种坐标转换。
- **软换行布局**：`LayoutEngine`，支持 Unicode 感知的单元格宽度。
- **样式 + 折叠元数据**：区间树（`IntervalTree`）与折叠区域（`FoldingManager`）
  （派生折叠 + 稳定的用户折叠）。
- **符号/大纲模型**：`DocumentOutline`、`DocumentSymbol`、`WorkspaceSymbol`，用于构建大纲树与符号搜索 UI
  （通常由 LSP 填充）。
- **无头快照**：`SnapshotGenerator` → `HeadlessGrid`，用于构建“文本网格”UI。
- **支持装饰的组合快照**：`ComposedGrid` 可以注入虚拟文本（inlay hints、code lens），宿主无需重写布局规则即可从快照渲染。
- **命令接口**：`CommandExecutor` 与 **状态/查询层**：`EditorStateManager`。
- **Workspace 模型**（`Workspace`）支持多 buffer + 多 view（分屏）：
  - 打开 buffer：`Workspace::open_buffer` → `OpenBufferResult { buffer_id, view_id }`
  - 创建额外 view：`Workspace::create_view`
  - 针对 view 执行命令：`Workspace::execute`
  - 从 view 渲染：`Workspace::get_viewport_content_styled`
  - 跨打开 buffers 搜索：`Workspace::search_all_open_buffers`
  - 应用 workspace 范围文本编辑（每个 buffer 一次 undo 分组）：`Workspace::apply_text_edits`
- **内核级编辑命令**（常见编辑器 UX）：
  - 行操作：`DuplicateLines`、`DeleteLines`、`MoveLinesUp/Down`、`JoinLines`、`SplitLine`
  - 注释切换：`ToggleComment`（由语言配置驱动）
  - 选择/多光标：`SelectLine`、`SelectWord`、`ExpandSelection`、`AddCursorAbove/Below`、
    `AddNextOccurrence`、`AddAllOccurrences`
- **搜索工具**：`find_next`、`find_prev`、`find_all`（基于字符偏移量）。

## 选择 API 层级（单视图 vs Workspace）

`editor-core` 保持 UI 无关，但你可以在不同层级集成：

- `CommandExecutor`：最低层的命令执行器，面向 **单个 buffer**，包含 undo/redo。
  - 如果你需要最大控制并且已有自己的状态管理层，可以直接持有它
  - `EditorStateManager` 与 `Workspace` 内部都使用它
- `EditorStateManager`：易用的 **单 buffer / 单 view** 封装。
  - 增加 `version`、`is_modified`、订阅回调，以及结构化查询辅助
  - 适合简单应用与测试的首选入口
- `Workspace`：**多 buffer + 多 view** 模型（tab + 分屏）。
  - buffers 由 `BufferId` 标识，拥有文本 + undo + 派生元数据
  - views 由 `ViewId` 标识，拥有光标/选择 + 视口配置 + 滚动

### 与旧的“单视图”接口关系

如果你之前把 `EditorStateManager` 当作“整个编辑器”，这种用法仍然成立并且会继续支持。概念上，它相当于
“一个只包含 1 个 buffer + 1 个 view 的 `Workspace`”。迁移到 `Workspace` 的价值在于把这些身份显式化，
从而让多个 view 可以共享同一份 buffer 状态。

### 迁移速查表（`EditorStateManager` → `Workspace`）

- 执行命令：`state.execute(cmd)` → `ws.execute(view_id, cmd)`
- 渲染视口：`state.get_viewport_content_styled(start, count)` →
  `ws.get_viewport_content_styled(view_id, start, count)`
- 订阅变更：`state.subscribe(cb)` → `ws.subscribe_view(view_id, cb)`
- 应用派生状态：`state.apply_processing_edits(edits)` →
  `ws.apply_processing_edits(buffer_id, edits)`
- 观察文本增量：`state.take_last_text_delta()` →
  `ws.take_last_text_delta_for_buffer(buffer_id)`（每次 buffer 编辑只消费一次）或
  `ws.take_last_text_delta_for_view(view_id)`（按 view 消费）

## 设计概览

`editor-core` 被组织为一组小型分层结构：

- **存储**：Piece Table 保存文档文本。
- **索引**：`LineIndex` 提供行访问 + 偏移量/位置转换。
- **布局**：`LayoutEngine` 计算换行点和逻辑↔视觉映射。
- **区间**：样式/折叠被表示为范围并高效查询。
- **快照**：面向 UI 的“文本网格”快照（`HeadlessGrid`）可以被任何前端渲染。
- **状态/命令**：用于编辑、查询、版本控制和变更通知的公共 API。

### 偏移量和坐标

- 许多公共 API 使用**字符偏移量**（而非字节偏移量），以增强对 Unicode 的鲁棒性。
- 渲染使用**单元格宽度**（`Cell.width` 通常为 1 或 2）以支持 CJK 和 emoji。
- **逻辑行**（文档行）和**视觉行**（经过软换行和/或折叠后）之间存在区别。

### 派生状态管道

更高层次的集成（如 LSP 语义 token 或语法高亮）可以计算派生的编辑器元数据并通过以下方式应用：

- `DocumentProcessor`（生成编辑）
- `ProcessingEdit`（应用编辑）
- `EditorStateManager::apply_processing_edits`（一致地更新状态）

## 快速开始

### 命令驱动的编辑

```rust
use editor_core::{Command, CommandExecutor, CursorCommand, EditCommand, Position};

let mut executor = CommandExecutor::empty(80);

executor.execute(Command::Edit(EditCommand::Insert {
    offset: 0,
    text: "Hello\nWorld".to_string(),
})).unwrap();

executor.execute(Command::Cursor(CursorCommand::MoveTo {
    line: 1,
    column: 2,
})).unwrap();

assert_eq!(executor.editor().cursor_position(), Position::new(1, 2));
```

### 状态查询 + 变更通知

```rust
use editor_core::{Command, EditCommand, EditorStateManager, StateChangeType};

let mut manager = EditorStateManager::new("Initial text", 80);
manager.subscribe(|change| {
    println!("change={:?} version {}->{}", change.change_type, change.old_version, change.new_version);
});

manager.execute(Command::Edit(EditCommand::Insert {
    offset: 0,
    text: "New: ".to_string(),
})).unwrap();
assert!(manager.get_document_state().is_modified);

// 手动编辑是可能的,但调用者必须保持不变量并调用 `mark_modified`。
manager.editor_mut().piece_table.insert(0, "X");
manager.mark_modified(StateChangeType::DocumentModified);
```

### 多 view 工作空间（分屏）

```rust
use editor_core::{Command, CursorCommand, EditCommand, Workspace};

let mut ws = Workspace::new();
let opened = ws.open_buffer(Some("file:///demo.txt".to_string()), "0123456789\n", 10).unwrap();

let left = opened.view_id;
let right = ws.create_view(opened.buffer_id, 5).unwrap();

ws.execute(left, Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 })).unwrap();
ws.execute(right, Command::Cursor(CursorCommand::MoveTo { line: 0, column: 5 })).unwrap();

ws.execute(left, Command::Edit(EditCommand::InsertText { text: "X".to_string() })).unwrap();
assert_eq!(ws.buffer_text(opened.buffer_id).unwrap(), "0X123456789\n");
```

### 支持装饰的组合快照（虚拟文本）

如果你应用了包含 `Decoration.text` 的装饰（例如 inlay hints 或 code lens），可以通过 `ComposedGrid`
渲染它们：

```rust
use editor_core::{
    Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange,
    EditorStateManager, ProcessingEdit,
};

let mut manager = EditorStateManager::new("a = 1\n", 80);
let anchor = manager.editor().line_index.position_to_char_offset(0, 1);

manager.apply_processing_edits(vec![ProcessingEdit::ReplaceDecorations {
    layer: DecorationLayerId::INLAY_HINTS,
    decorations: vec![Decoration {
        range: DecorationRange::new(anchor, anchor),
        placement: DecorationPlacement::After,
        kind: DecorationKind::InlayHint,
        text: Some(": i32".to_string()),
        styles: vec![],
        tooltip: None,
        data_json: None,
    }],
}]);

let composed = manager.get_viewport_content_composed(0, 10);
assert!(composed.actual_line_count() > 0);
```

## 性能与基准测试

`editor-core` 目标是让常见编辑器热路径保持**增量**：

- 文本编辑增量更新 `LineIndex` 与 `LayoutEngine`（而不是每次按键都从 `get_text()` 全量重建）。
- 视口渲染从 `LineIndex` + `LayoutEngine` 流式读取可见行（避免在视口路径构建整份文档的中间字符串）。

运行 P1.5 基准测试套件：

```bash
cargo bench -p editor-core --bench performance
```

快速本地 sanity（更小样本）：

```bash
cargo bench -p editor-core --bench performance -- --sample-size 10 --warm-up-time 0.1 --measurement-time 0.1
```

也有一个运行时示例（打印耗时便于观察）：

```bash
cargo run -p editor-core --example performance_milestones
```

## 相关 crate

- `editor-core-lsp`：LSP 集成（UTF-16 转换、语义 token 辅助、stdio JSON-RPC）。
- `editor-core-sublime`: `.sublime-syntax` 高亮 + 折叠引擎。
- `editor-core-treesitter`: Tree-sitter 集成（增量解析 → 高亮 + 折叠）。
