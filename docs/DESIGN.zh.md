# editor-core — 设计文档

本文档解释了 `editor-core` 工作空间的内部设计以及各个 crate 如何协同工作。本文档面向：

- 集成引擎的 UI/前端开发者
- 扩展存储/索引/布局/派生状态子系统的贡献者

如果你只需要 API 级别的使用说明，请从工作空间的 `README.md` 和 `crates/*/README.md` 下的各 crate README 开始。

## 术语："工作空间" vs `Workspace`

本仓库里“工作空间”有两层含义：

- **Cargo workspace**：Rust monorepo 的工程组织方式（一个 `Cargo.toml` 管多 crate）。
- **`editor_core::Workspace`**：编辑器内核的**多 buffer** + **多 view（分屏）**模型。

本文大部分内容在讲 Cargo workspace 中各 crate 的内部设计；但 `Workspace` 也是完整编辑器宿主最常接触
的边界（tab/分屏/多文件操作等），因此也会在后文覆盖。

## 目标与非目标

### 目标

- **无头 / UI 无关**：引擎生成快照和状态；宿主负责渲染并将样式映射到视觉效果。
- **Unicode 感知基础**：
  - 编辑操作使用**字符偏移量**（Rust `char` 索引），而非字节偏移量
  - 布局使用**单元格宽度**（典型终端：1 或 2）处理 CJK/emoji
- **坐标转换**：
  - 字符偏移量 ⇄ 逻辑 `(line, column)`
  - 逻辑 ⇄ 视觉行（软换行、折叠）
  - 通过 `editor-core-lsp` 进行 UTF-16 转换用于 LSP
- **可组合的派生状态**：高亮/折叠/诊断是"派生元数据"，作为补丁（`ProcessingEdit`）应用，而非硬编码到核心中。

### 非目标（当前）

- 完整的 UI 渲染器、主题系统或 widget 工具包。
- 完全类型化的 LSP 框架（`editor-core-lsp` 有意使用 `serde_json::Value`）。
- Grapheme-cluster 感知的光标移动/选择（参见下面的"Unicode 模型"）。
- 完整的增量解析流水线。高亮集成设计为可替换的。

## 高层架构

核心引擎（`crates/editor-core`）以分层方式组织，从文本存储构建到 UI 快照：

```text
┌──────────────────────────────────────────────┐
│ Workspace（buffers + views，可选）           │  多 buffer/多 view 编排层
├──────────────────────────────────────────────┤
│ 状态 + 命令 (CommandExecutor/State)          │  公共编辑/查询接口
├──────────────────────────────────────────────┤
│ 快照 (HeadlessGrid)                          │  UI 读取 + 渲染
├──────────────────────────────────────────────┤
│ 样式 + 折叠 (IntervalTree/FoldingMgr)        │  派生元数据叠加层
├──────────────────────────────────────────────┤
│ 布局 (LayoutEngine)                          │  软换行 + 逻辑↔视觉
├──────────────────────────────────────────────┤
│ 行索引 (LineIndex, ropey)                    │  行访问 + 位置↔偏移量
├──────────────────────────────────────────────┤
│ 存储 (PieceTable)                            │  编辑 + 文本检索
└──────────────────────────────────────────────┘
```

"集成" crate（`editor-core-lsp`、`editor-core-sublime`、`editor-core-highlight-simple`）计算派生元数据和/或驱动外部协议。它们通过共享的派生状态接口将结果反馈到核心。

## 坐标模型

`editor-core` 需要多个坐标空间。一致地使用它们是正确 UI 行为的关键。

### 1) 字节偏移量（UTF-8）

- 在 `PieceTable` *缓冲区*（`Piece.start`、`Piece.byte_length`）内部使用。
- 不作为主要 API 坐标使用，因为字节在 Unicode 操作下不稳定。

### 2) 字符偏移量（Unicode 标量值）

大多数公共 API 使用**字符偏移量**（`usize`）：

- 偏移量计算整个文档中的 Rust `char`，包括换行符。
- 范围通常为半开区间：`[start, end)`。

权衡：用户感知的"字符"（grapheme cluster，如 `👨‍👩‍👧‍👦`）可能是多个 `char`。

### 3) 逻辑位置（行/列）

`Position { line, column }` 用于光标/选择 API。

- `line` 是逻辑行索引（从 0 开始）
- `column` 是逻辑行内的字符列（从 0 开始，以 `char` 为单位计数）

`LineIndex` 提供转换：

- `LineIndex::char_offset_to_position(char_offset) -> (line, column)`
- `LineIndex::position_to_char_offset(line, column) -> char_offset`

### 4) 视觉位置（软换行 + 折叠）

布局引入"视觉行"坐标：

- 软换行将单个逻辑行分割成多个视觉行。
- 折叠可以隐藏逻辑行，并可选地在折叠起始行附加占位符。

`LayoutEngine`（仅换行）和 `EditorCore`（换行 + 折叠）中存在转换：

- `LayoutEngine::logical_to_visual_line(logical_line)`
- `LayoutEngine::visual_to_logical_line(visual_line)`
- `EditorCore::logical_position_to_visual(...)`
- `EditorCore::visual_to_logical_line(visual_line)`

视觉 `x` 位置以**单元格**而非字符表示。

### 5) LSP UTF-16 位置（集成 crate）

Language Server Protocol 使用 UTF-16 code unit 表示 `Position.character`。

`editor-core-lsp` 提供 `LspCoordinateConverter` 和辅助工具来映射：

- 编辑器字符偏移量 / 位置
- LSP UTF-16 位置 / 范围

## 核心数据结构

### PieceTable（存储）

文件：`crates/editor-core/src/storage.rs`

存储层是经典的 **piece table**：

- `original_buffer`：初始文档的不可变字节
- `add_buffer`：仅追加的已插入文本字节
- `pieces: Vec<Piece>`：每个 piece 引用某个缓冲区的切片

每个 `Piece` 存储：

- `start` + `byte_length`（缓冲区内的字节范围）
- `char_count`（缓存以支持字符偏移操作）

编辑：

- 插入：
  - 将插入的字节追加到 `add_buffer`
  - 查找包含目标字符偏移量的 piece
  - 如果在中间插入则分割包含的 piece
  - 插入一个引用新 add-buffer 区域的新 `Piece`
- 删除：
  - 根据需要分割边界 piece 并移除受影响的 piece/范围

注意：

- 在*字符*偏移量处分割 piece 需要转换为字节偏移量（当前是对 piece 的 UTF-8 段的 O(n) 扫描）。
- 来自 add buffer 的相邻 piece 会合并以减少碎片。
- 简单的 GC 通过复制引用区域并重写 piece 起始位置来压缩 `add_buffer`。

### LineIndex（逻辑行访问）

文件：`crates/editor-core/src/line_index.rs`

行索引构建于 `ropey::Rope` 之上：

- 快速行访问（`rope.line(i)`）
- 高效的字符偏移量和行/列之间的转换

在当前实现中，许多编辑路径在变更后从完整文档文本重建 rope（简单且正确，但不是最增量的方法）。公共 API 仍然暴露增量 `insert/delete` 辅助工具以供将来优化。

存在两种偏移量转换风格：

- `char_offset_to_position` / `position_to_char_offset`：首选；与 rope 语义匹配，其中换行符是文本流中的一个字符。
- `line_to_offset` / `offset_to_line`：遗留辅助工具，将偏移量视为"不包括换行符"，主要在验证测试中使用。

### LayoutEngine（软换行）

文件：`crates/editor-core/src/layout.rs`

布局是一个**无头重排**引擎：

- 输入：逻辑行文本和 `viewport_width`（以单元格为单位）
- 输出：换行点（`WrapPoint { char_index, byte_offset }`）和 `visual_line_count`

`char_width(ch)` 使用 `unicode-width` crate：

- 宽 CJK/emoji → 通常为 `2`
- 组合标记 → 通常为 `0`

因为宽度是按 Unicode 标量值计算的，多码点 grapheme cluster 不会被视为换行或光标移动的单个单元。

引擎为换行的行提供坐标转换：

- `logical_position_to_visual(line, column) -> (visual_row, x_in_cells)`
- `logical_position_to_visual_allow_virtual(...)`：允许行尾之外的"虚拟空格"，由矩形选择/列编辑使用。

### IntervalTree 和样式层（派生样式）

文件：`crates/editor-core/src/intervals.rs`

样式表示为字符偏移量上的**区间**：

- `StyleId` 是不透明的 `u32` 标识符
- `Interval { start, end, style_id }` 使用半开字符范围 `[start, end)`

`IntervalTree` 实现为：

- 按 `start` 排序的向量
- 用于查询期间修剪的 `prefix_max_end` 数组

支持：

- 点查询："哪些样式应用于此偏移量？"
- 范围查询："哪些区间与此视口重叠？"

核心维护：

- `interval_tree`：基础样式区间
- `style_layers: BTreeMap<StyleLayerId, IntervalTree>`：按来源的叠加层（LSP 语义 token、Sublime 语法、诊断等）

快照从基础树和所有层合并样式，然后对每个单元格的 `StyleId` 列表进行排序和去重。

### FoldingManager（可见性）

文件：`crates/editor-core/src/intervals.rs`

折叠表示为基于行的区域：

- `FoldRegion { start_line, end_line, is_collapsed, placeholder }`
- `end_line` 是包含的

`FoldingManager` 存储一个排序的区域列表并提供：

- 切换/折叠/展开
- 当折叠隐藏内容时在逻辑行和视觉行之间映射

当区域折叠时，行 `(start_line + 1 ..= end_line)` 变为隐藏。

快照可选地使用内置的 `FOLD_PLACEHOLDER_STYLE_ID` 在折叠**起始**行附加区域的占位符。

当前限制：

- 折叠区域是基于行的，并且**不会在插入或删除换行符的文本编辑时自动移位**。预期用法是将折叠视为派生状态，并在编辑后从外部提供者（例如 LSP 折叠范围或 Sublime 语法折叠）刷新它们。

## 命令和状态层

### EditorCore（聚合模型）

文件：`crates/editor-core/src/commands.rs`（`pub struct EditorCore`）

`EditorCore` 聚合所有主要子系统：

- 文本：`PieceTable`、`LineIndex`
- 布局：`LayoutEngine`
- 派生元数据：`IntervalTree`、样式层、`FoldingManager`
- 选择状态：光标 + 选择
- 视口宽度

它提供样式化快照辅助工具：

- `EditorCore::get_headless_grid_styled(start_visual_row, count)`

这是主要的"UI 读取数据"方法：它应用换行 + 折叠并将样式合并到单元格中。

### CommandExecutor（变更）

文件：`crates/editor-core/src/commands.rs`（`pub struct CommandExecutor`）

编辑通过命令枚举应用：

- `EditCommand`：插入/删除/替换、多光标输入、撤销/重做、查找/替换辅助工具
- `CursorCommand`：移动、选择、多光标、矩形选择
- `ViewCommand`：视口宽度更改、请求无样式视口快照
- `StyleCommand`：临时基础样式和手动折叠切换

实现注意事项：

- 编辑命令更新 piece table，保持样式区间偏移量一致（插入/删除时移位），并根据需要重建 rope + 布局。
- 多光标输入通过在*原始*文档中计算所有编辑范围，然后按降序偏移量顺序应用更改（这样早期的编辑不会使后期的偏移量失效）。

#### 撤销/重做模型

撤销/重做在 `commands.rs` 中通过内部 `UndoRedoManager` 实现：

- 每个应用的编辑产生一个或多个 `TextEdit` 记录（deleted_text + inserted_text）。
- 编辑被分组为 `UndoStep { group_id, ... }`。
- 不包含换行符的纯插入可能会合并到当前"打开组"中，以产生典型的输入撤销行为。
- 跟踪"干净点"以支持更高层的 `is_modified`/保存提示。

### EditorStateManager（查询 + 通知）

文件：`crates/editor-core/src/state.rs`

`EditorStateManager` 包装 `CommandExecutor` 并添加：

- 单调递增的 `version`
- `is_modified` 跟踪 + `mark_saved()`
- 订阅回调（`subscribe`）用于变更通知
- 视口簿记（`scroll_top`、可选的视口高度）
- 结构化查询方法：
  - `get_document_state`、`get_cursor_state`、`get_viewport_state`、`get_style_state` 等

#### 派生状态接口

状态管理器也是派生元数据的"集成点"：

- `DocumentProcessor`（trait）：计算派生更新
- `ProcessingEdit`（枚举）：替换/清除样式层和折叠区域

处理器预期：

- 给定编辑器状态是确定性的
- 对编辑器没有副作用（它们返回编辑；宿主应用它们）

此模式允许多个独立集成共存：

- 语法高亮器可以填充 `StyleLayerId::SUBLIME_SYNTAX`
- LSP 会话可以填充 `StyleLayerId::SEMANTIC_TOKENS` 和折叠区域
- 诊断引擎可以填充 `StyleLayerId::DIAGNOSTICS`

### Workspace（多 buffer + 多 view）

文件：`crates/editor-core/src/workspace.rs`

`EditorStateManager` 是一个很方便的“单 buffer + 单 view”包装。但完整编辑器通常还需要：

- 多个打开的 buffer（tab）
- 同一 buffer 的多个 view（分屏）
- 工作空间级操作（例如跨 buffer 搜索、应用 LSP 的多文件编辑）

`editor_core::Workspace` 提供这层编排能力，同时保持 UI 无关。它把状态拆分为：

- **Buffer**（`BufferId`）：文档文本 + 撤销历史 + 与文本绑定的派生状态。
  内部实现上是一个 `CommandExecutor` 加上一些元数据（例如可选的 URI）。
- **View**（`ViewId`）：面向具体视口的状态，例如选择/光标、换行配置、滚动位置。

关键行为：

- `Workspace::execute(view_id, Command)` 总是**针对某个 view 执行命令**。
  - 光标/选择是 view 本地状态。
  - 文本编辑会修改底层 buffer。
  - 产生的 `TextDelta` 会广播给该 buffer 的所有 view（分屏保持一致）。
- 派生元数据存储在 buffer 级别，可通过 `Workspace::apply_processing_edits(buffer_id, edits)`
  应用，并通知该 buffer 的所有 view。
- 对于希望“每次 buffer 编辑只消费一次 delta”的增量消费者，可使用
  `Workspace::take_last_text_delta_for_buffer`。

概念上，“一个 `EditorStateManager`”可以视为“`Workspace` 里一个 buffer + 一个 view”；
`Workspace` 只是把身份（`BufferId`/`ViewId`）显式化，从而支持额外的 view 共享同一份 buffer 状态。

## 快照

文件：`crates/editor-core/src/snapshot.rs`

快照格式有意设计得小巧且对 UI 友好：

- `HeadlessGrid { lines, start_visual_row, count }`
- `HeadlessLine { logical_line_index, is_wrapped_part, cells }`
- `Cell { ch, width, styles }`

有两种快照路径：

1. `SnapshotGenerator`（仅文本）：
   - 拥有一个 `Vec<String>` 行 + 自己的 `LayoutEngine`
   - 生成无样式快照
   - 对测试和简单用法有用
2. `EditorCore::get_headless_grid_styled`（推荐用于真实 UI）：
   - 使用编辑器的实时 `LineIndex` + `LayoutEngine`
   - 合并样式并应用折叠

## 集成 crate

### editor-core-highlight-simple

路径：`crates/editor-core-highlight-simple/`

针对简单格式（JSON/INI 等）的轻量级基于正则表达式的高亮器：

- `RegexHighlighter` 逐行运行正则规则并以字符偏移量发出样式 `Interval`。
- `RegexHighlightProcessor` 实现 `DocumentProcessor` 并为 `StyleLayerId::SIMPLE_SYNTAX` 发出 `ProcessingEdit::ReplaceStyleLayer`。

### editor-core-sublime

路径：`crates/editor-core-sublime/`

实现 Sublime Text `.sublime-syntax` 模型的子集：

- 编译 YAML 语法定义
- 运行高亮引擎以生成：
  - 样式区间（字符偏移量）
  - 折叠区域（逻辑行范围）
- 暴露一个 `SublimeProcessor`（`DocumentProcessor`）输出：
  - `StyleLayerId::SUBLIME_SYNTAX`
  - 折叠编辑

这为许多语言提供"足够好"的高亮/折叠，无需 LSP。

### editor-core-lsp

路径：`crates/editor-core-lsp/`

提供运行时无关的 LSP 集成辅助工具：

- UTF-16 转换辅助工具（`LspCoordinateConverter`）
- 增量文本更改辅助工具（`DeltaCalculator`）
- 语义 token 解码到编辑器样式区间
- 工作空间/文本编辑解析 + 应用（基于 `serde_json::Value`）
- stdio JSON-RPC 客户端（`LspClient`）和更高级的会话（`LspSession`）

`LspSession` 可以用作 `DocumentProcessor`：

- 轮询服务器
- 使用 `ProcessingEdit` 更新编辑器派生状态（语义 token + 折叠范围等）

## TUI 演示应用

路径：`crates/tui-editor/`

`tui-editor` 是一个可运行的示例：

- 使用 `ratatui` 渲染 `HeadlessGrid`
- 通过 `EditorStateManager` 驱动编辑
- 可选地启用：
  - Sublime 语法高亮/折叠（如果 CWD 中存在匹配的 `.sublime-syntax`）
  - LSP 语义 token/折叠范围（stdio 服务器）

它旨在作为：

- 工作空间的功能集成测试
- UI 如何消费快照和应用派生状态的参考

如果你关心多 buffer/多 view 的接线方式，可以看 `editor-core` 的 workspace 示例（例如
`crates/editor-core/examples/multiview_workspace.rs`）。

## 已知限制 / 扩展点

- **Grapheme cluster**：光标移动/选择基于 `char`；如果需要 grapheme 感知的 UX，请使用 `unicode-segmentation` 或类似工具在 `editor-core` 之上实现。
- **Tab/控制字符**：布局测量每个 `char` 的宽度；宿主通常在渲染时实现 tab 扩展或通过转换快照。
- **折叠编辑**：基于行的折叠不会在换行符编辑时移位；将折叠视为派生状态，并在编辑后从外部源刷新。
- **增量性**：某些操作为了简单起见从完整文本重建派生结构。架构有意分层，以便内部组件可以随时间变得更增量，而不会破坏公共 API 形态。
