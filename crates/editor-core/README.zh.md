# editor-core

`editor-core` 是一个**无头(headless)**编辑器引擎,专注于状态管理、Unicode 感知的文本测量和坐标转换。它特意设计为 UI 无关的:使用者从快照进行渲染,并通过命令/状态 API 驱动编辑操作。

## 特性

- 通过片段表(`PieceTable`)实现**高效的文本存储**,用于插入/删除操作。
- 通过基于 rope 的 `LineIndex` 实现**快速行索引**,用于行访问和转换。
- **软换行布局**(`LayoutEngine`),具有 Unicode 感知的单元格宽度。
- 通过区间树(`IntervalTree`)和折叠区域(`FoldingManager`)管理**样式 + 折叠元数据**。
- **无头快照**(`SnapshotGenerator` → `HeadlessGrid`)用于构建"文本网格" UI。
- **命令接口**(`CommandExecutor`)和**状态/查询层**(`EditorStateManager`)。
- **搜索工具**(`find_next`、`find_prev`、`find_all`)基于字符偏移量操作。

## 设计概览

`editor-core` 被组织为一组小型分层结构:

- **存储**: 片段表保存文档文本。
- **索引**: `LineIndex` 提供行访问 + 偏移量/位置转换。
- **布局**: `LayoutEngine` 计算换行点和逻辑↔视觉映射。
- **区间**: 样式/折叠被表示为范围并高效查询。
- **快照**: 面向 UI 的"文本网格"快照(`HeadlessGrid`)可以被任何前端渲染。
- **状态/命令**: 用于编辑、查询、版本控制和变更通知的公共 API。

### 偏移量和坐标

- 许多公共 API 使用**字符偏移量**(而非字节偏移量)以增强对 Unicode 的鲁棒性。
- 渲染使用**单元格宽度**(`Cell.width` 通常为 1 或 2)以支持 CJK 和表情符号。
- **逻辑行**(文档行)和**视觉行**(经过软换行和/或折叠后)之间存在区别。

### 派生状态管道

更高层次的集成(如 LSP 语义令牌或语法高亮)可以计算派生的编辑器元数据并通过以下方式应用:

- `DocumentProcessor`(生成编辑)
- `ProcessingEdit`(应用编辑)
- `EditorStateManager::apply_processing_edits`(一致地更新状态)

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

## 相关 crate

- `editor-core-lsp`: LSP 集成(UTF-16 转换、语义令牌助手、stdio JSON-RPC)。
- `editor-core-sublime`: `.sublime-syntax` 高亮 + 折叠引擎。
