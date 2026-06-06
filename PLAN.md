# editor-core-diff-view — 落地计划（v1）

> 状态：实施计划，2026-06-07。
> 设计依据见已归档的 `docs/DIFF_VIEW.md`（Diff View Design）。本文件把设计落到可执行的分阶段任务。

## 0. 本版范围决策（Open questions 已定）

设计文档遗留的三个 open question，本版（v1）一律按"先简化、后续版本再做"处理：

1. **不支持 folding。** Diff 视图内禁用折叠。理由：折叠会改变单侧的 visual row 数，破坏对齐；同步折叠（按 alignment unit 两侧一起折）留待后续版本。
   - 落地约束：view 层把 `ViewCommand` 中所有折叠相关命令归类为"拒绝"；projection 不把 `FoldingManager` 状态纳入输入。
2. **不做行内 diff（intra-line / word-char diff）。** 修改行只产出行级 Add/Remove 背景样式，不高亮行内具体改动字符。后续版本再补 word/char diff 作为一类 diff-semantic style。
3. **宽度变更时整体重算。** 宽度（含 splitter 拖拽推导出的 per-column width）变化时，整条 `rows` 轴 wholesale 重建（量级等同一次 resize reflow）。增量式 wrap/alignment 更新留待后续版本。
   - 落地约束：保留"width-independent vs width-dependent"的分层缓存（见 §3），但 width-dependent 部分不做增量 diff，直接全量重建。

这三条同时决定了 v1 的数据结构可以更简单：`AlignUnit` 不需要携带折叠状态；`RowSlot` 不需要 intra-line 区间；projection 不需要 dirty-range 追踪。

## 1. 新建 crate `editor-core-diff-view`

- 在 workspace `Cargo.toml` 的 `members` 中加入 `crates/editor-core-diff-view`。
- 依赖：
  - `editor-core`（path）— 复用 `SnapshotGenerator`、`Cell`、`StyleId`、`EditorCore`/`CommandExecutor`、`Command`/`*Command`。
  - `editor-core-diff`（path）— 复用 `diff_line_hunks`、`DiffLine`、`DiffLineKind`、`LineHunk`、`LineDiffConfig`。
- crate 定位：**纯 headless**，不含任何 rendering / scrolling / splitter 逻辑。
- 模块划分（建议）：
  - `model.rs` — `DiffModel`、`SideDoc`、`AlignUnit`、数据源构建。
  - `projection.rs` — `DiffMode`、`DiffProjection`、`Row`、`RowSlot`、`project_unified` / `project_side_by_side`。
  - `view.rs` — 单列 `DiffColumnView`、坐标映射、readonly 命令接口。
  - `style.rs` — diff-semantic `StyleId` 常量。
  - `lib.rs` — 重导出。

## 2. 第一阶段：固化 `AlignUnit` 与对齐算法（设计文档点名的 first step）

这是整个 crate 的基石，必须先定死，之后 model 与 view 才能并行开发。

### 2.1 `AlignUnit` 形状

```rust
/// 每个单元描述一段逻辑行在各侧之间的配对关系。
/// v1 仅支持两侧；类型上保留 N 侧扩展余地（用 per-side 的 line range 表达，不硬编码 left/right）。
enum AlignUnit {
    Context { sides: Vec<Range<usize>> },   // 各侧 1:1，长度相等
    Replace { sides: Vec<Range<usize>> },   // 修改块：各侧可不等长
    Add     { side: usize, lines: Range<usize> },  // 仅某侧存在
    Remove  { side: usize, lines: Range<usize> },  // 仅某侧存在
}
```

- 用 `Range<usize>`（逻辑行下标，0-based）表达各侧的行区间，对应 `DiffLine::before_line` / `after_line`。
- v1 `sides.len() == 2`；保留 `Vec` 以便三向合并扩展。

### 2.2 对齐算法（从 `file + patch` / `before + after` 归约到 `Vec<AlignUnit>`）

- 输入两种来源都先归约成 `diff_line_hunks` 的输出（`before+after` 直接跑；`file+patch` 先由 patch 重建另一侧文本，再跑或直接用 patch 的配对）。v1 先实现 **`before + after` 来源**，`file + patch` 作为同阶段第二个来源接入（两者产出同一个 `DiffModel`）。
- 遍历 `diff_line_hunks` 产出的 unified 顺序 `DiffLine` 序列：
  - 连续 `Context` → 合成 `Context` 单元。
  - 连续 `Remove` 紧跟连续 `Add`（或交错的修改块）→ 合成一个 `Replace` 单元，左侧取 remove 行区间、右侧取 add 行区间。
  - 纯 `Add` / 纯 `Remove`（无对侧配对）→ `Add` / `Remove` 单元。
- **`Replace` 块内左右行如何配对**：v1 采用**块级配对**（左整块 ↔ 右整块），不在块内做逐行最优匹配。块内不做行内 diff（见 §0.2），所以无需逐行配对，简化为"左 range vs 右 range，按 §4 的 max 规则补 spacer"。
- 覆盖整个文档：hunk 之外的大段未改区域也要生成 `Context` 单元（`diff_line_hunks` 只给 hunk，需在外层用整文件行数补齐 hunk 间的 context 段）。

### 2.3 验收

- 单测：无变更 → 全是 `Context` 单元且覆盖全文；纯增 / 纯删 / 修改块 / 文件首尾边界各一组用例。
- 性质测试：所有单元的各侧 range 按序拼接 == 该侧完整行序列（无重叠、无遗漏）。

## 3. 第二阶段：`DiffModel`（width-independent 真值）

```rust
struct SideDoc {
    // 用 editor-core 的文本/行机制承载逻辑行；不在此层做 wrap。
    // 建议内部持有该侧全文（供 SnapshotGenerator 按列宽 wrap）。
}
struct DiffModel {
    sides: Vec<SideDoc>,        // 2 = diff
    alignment: Vec<AlignUnit>,
}
```

- 构建入口：`DiffModel::from_before_after(before, after, LineDiffConfig)` 与 `DiffModel::from_file_and_patch(file, patch)`。
- **width-independent 缓存**（解析一次）：各侧逻辑行、alignment 配对、每行 change kind。
- 不含 spacer（spacer 是 presentation 产物，见 §4）。
- 每侧 change kind 的查询：projection 需要按逻辑行问"这行是 Context/Add/Remove"，由 `AlignUnit` 推导，建议在 model 上提供 `side_line_kind(side, logical_line) -> DiffLineKind`。

## 4. 第三阶段：`DiffProjection`（presentation，width-dependent）

```rust
enum DiffMode { Unified, SideBySide /* ThreeWay 后续 */ }
struct DiffProjection { columns: usize, rows: Vec<Row> }
struct Row { slots: Vec<RowSlot> }   // slots.len() == columns
enum RowSlot {
    Line { side: usize, logical_line: usize, visual_in_logical: usize, change: DiffLineKind },
    Spacer { change: DiffLineKind },
}
```

- 入口：`DiffProjection::build(model, mode, &per_column_widths) -> DiffProjection`。**宽度变化即整体重建**（§0.3），不做增量。
- 每侧 wrap 复用 `SnapshotGenerator`（`set_viewport_width` + `get_headless_grid`）按该列宽度求逻辑行 → visual segment 数。
- **对齐 = 每个 alignment unit 内各侧 visual row 数对齐**：
  1. 按序遍历 `AlignUnit`。
  2. 每侧逻辑行用该列宽 wrap，得 `nSide` 个 visual row。
  3. `max` across sides；不足的侧在该单元末尾补 `Spacer`。
- 模式差异：
  - `SideBySide`（columns==2）：各侧独立 wrap，按上面 max 规则补 spacer。
  - `Unified`（columns==1）：**不产生 spacer**；修改块按顺序展开（先 removed 行、后 added 行）于单列。窄屏/移动端默认。
- 验收单测：
  - 同一 `DiffModel` 在两种 mode 下产出不同 `rows`，且 Unified 无 `Spacer`。
  - SideBySide 下每个 unit 两列 row 数相等（含 spacer 后）。
  - 改变列宽 → row 数随 wrap 变化；两次相同宽度产出一致（确定性）。

## 5. 第四阶段：diff-semantic 样式 + gutter line mark

### 5.1 样式（`style.rs`）

- 在 `editor-core` 的 `StyleId`(u32) 命名空间里新增一段 diff 专用常量（沿用 `intervals.rs` 的 `0x0X00_000Y` 风格，挑一个未占用的高位段，如 `0x0900_xxxx`）：`DIFF_ADD_LINE_STYLE_ID`、`DIFF_REMOVE_LINE_STYLE_ID`、`DIFF_SPACER_STYLE_ID`。
  - 新常量加在 `crates/editor-core/src/intervals.rs`，与现有样式段并列。
- projection / view 把这些 StyleId 叠加进 `Cell.styles`。
- 语法高亮样式（LSP / tree-sitter）跟随各侧文档，view 投影时与 diff-semantic 样式 **叠加**（两类 style 并存）。
- v1 **不含** intra-line 高亮样式（§0.2）。

### 5.2 Gutter（line mark）

- 设计建议 line mark 做成 `editor-core` 的**通用 per-logical-line 能力**（与 `decorations.rs` 的 char-offset 锚定互为兄弟），断点 / git blame / fold 指示都能复用。
- **v1 范围裁剪**：通用 line mark 设施是较大改动。v1 先在 diff-view 内提供最小可用形态——projection 在 `Row`/`RowSlot` 上挂 diff 所需的 gutter 信息（`+`/`-` 标记 + 两侧行号 `before_line`/`after_line`），把"提取为 editor-core 通用 line mark"列为 §8 后续项。
  - 行号自然落地：左 gutter 显示 `before_line`，右显示 `after_line`。

## 6. 第五阶段：Views（每列一个，readonly 命令接口）

```rust
struct DiffColumnView { /* 引用 projection + 该侧 readonly EditorCore，column index */ }
```

- view 是 `rows[*].slots[i]` 的薄投影：每个 slot → cells / style / line-mark；`Spacer` 产出空行。
- 背后挂 **readonly `EditorCore`/`CommandExecutor`**（`crates/editor-core/src/commands.rs`）。
- **命令分类**：在 `editor-core` 的 `Command` 上加 `is_mutating()`（覆盖 `model.rs` 的 `EditCommand`/`CursorCommand`/`ViewCommand`/`StyleCommand`）；view 层拒绝 mutating 命令，而不是另立 enum。
  - 允许：cursor 移动、selection、scroll、find、go-to。
  - 拒绝：insert / delete / replace / undo / redo。
  - **v1 折叠归入拒绝**（§0.1）：`ViewCommand` 中折叠相关项一并归为 mutating/rejected。
- **两套坐标**：命令作用于各侧文档真实坐标（直接复用 editor 导航逻辑）；渲染/滚动用 unified row 轴。projection 提供双向映射 **per-side visual row ↔ unified row**。
  - 副作用：cursor 自然跳过 spacer（spacer 不属任何侧真实行序列）。
- 验收：mutating 命令被拒；navigation 命令在 readonly editor 上正常；上下移动时 cursor 跳过 spacer；映射往返一致。

## 7. 阶段顺序与并行点

1. §2 对齐算法 + `AlignUnit`（阻塞后续一切）。
2. 定型后，§3 `DiffModel` 与 §6 view 的 readonly 命令接口（含 `is_mutating()`）可并行。
3. §4 projection 依赖 §2/§3。
4. §5 样式/gutter、§6 view 投影依赖 §4。
5. 全程 headless，可纯单测驱动，无需 render 后端。

## 8. 明确推迟到后续版本（不在 v1）

- Folding（含同步折叠）。
- Intra-line / word-char diff 及其高亮样式。
- 宽度变更的增量 wrap/alignment 重算。
- ThreeWay（三向合并，columns==3）：类型保留余地，v1 不实现。
- 把 gutter line mark 提取为 `editor-core` 通用能力（v1 先在 diff-view 内最小实现）。
- `Replace` 块内逐行最优配对（v1 用块级配对）。

## 9. 相关 crate 复用清单（落地参照）

- `crates/editor-core-diff/src/lib.rs` — `diff_line_hunks` / `DiffLine{before_line,after_line,kind}` / `DiffLineKind` / `LineDiffConfig`。
- `crates/editor-core/src/snapshot.rs` — `SnapshotGenerator`（`set_viewport_width`/`get_headless_grid`）、`HeadlessLine`（`logical_line_index`/`visual_in_logical`）、`Cell{styles}`。
- `crates/editor-core/src/commands.rs` — `EditorCore` / `CommandExecutor`（readonly 子集）。
- `crates/editor-core/src/model.rs` — `Command` 及 `EditCommand`/`CursorCommand`/`ViewCommand`/`StyleCommand`（加 `is_mutating()`）。
- `crates/editor-core/src/intervals.rs` — `StyleId`(u32) 命名空间，新增 diff 样式段。
- `crates/editor-core/src/decorations.rs` — line mark 后续提取时的兄弟参照。
