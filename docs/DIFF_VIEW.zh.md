# editor-core — Diff View 设计

> **状态：** 设计提案（尚未实现），截至 2026-06-06。
> 本文记录在 `editor-core` 之上构建 diff/merge 查看器的已对齐设计方向，计划在新 crate
> `editor-core-diff-view` 中实现。

本文说明 diff 查看器如何融入 `editor-core` 架构。读者对象：

- 实现 diff/merge 查看器的贡献者
- 集成它的 UI / 前端作者

它所依赖的引擎内部设计见 [`DESIGN.zh.md`](./DESIGN.zh.md)；行级 diff 原语见 `crates/editor-core-diff`。

## 设计原则

diff 查看器遵循 `editor-core` 一贯的哲学：

- **完全 headless / 与 UI 无关。** 引擎产出对齐好、带样式的网格数据；由宿主负责渲染并把样式映射成
  视觉效果。Skia/Swift/TUI 等前端都构建在引擎*外围*，而非内部。
- **抽象层中不出现 UI 概念。** headless 层没有 “splitter（分屏）” 这个概念——splitter 是 UI
  把多列并排摆放的动作。headless 层产出的是一根**对齐后的、多列的行轴**；有几列、怎么布局，是宿主的事。
- **soft wrap 是必备功能。** `editor-core` 刻意避免横向滚动条（在桌面和移动端体验都很差），所以
  diff 模式下 soft wrap 也必须工作。这是 side-by-side 对齐最主要的复杂度来源，本设计正面解决它，
  而不是关闭 wrap。

## 总体架构

diff 查看器是 headless 网格的**消费者 / 合成器**，而不是核心的新功能。核心抽象保持 “一个文件 →
一个 headless 网格” 不变；diff 查看器负责编排若干个这样的网格并加上对齐。

共三层，全部 headless，外加宿主的 render engine：

```
                         ┌───────────────────────────────────────────┐
                         │ DiffModel  (底层事实)                      │
   file + patch  ──────► │  - sides: Vec<SideDoc>                     │  与宽度无关
   (或 base + N 侧)      │  - alignment: Vec<AlignUnit>               │  与模式无关
                         │  - 无 spacer                               │  无 spacer
                         └────────────────────┬──────────────────────┘
                                              │ mode + 各列宽度
                                              ▼
                         ┌───────────────────────────────────────────┐
                         │ DiffProjection  (呈现层)                   │
                         │  - columns: usize                          │  依赖宽度
                         │  - rows: Vec<Row>  (统一行轴)              │  spacer/mark/style
                         │  - 生成 spacer + gutter mark + style       │  在此生成
                         └────────────────────┬──────────────────────┘
                                              │ 投影第 i 列
                                              ▼
                         ┌───────────────────────────────────────────┐
                         │ Views  (每列一个)                          │
                         │  - 对 rows[*].slots[i] 做薄投影            │  每个 view 背后
                         │  - 复用 editor 的只读命令接口             │  是只读 EditorCore
                         └────────────────────┬──────────────────────┘
                                              │ 只提供数据
                                              ▼
                         ┌───────────────────────────────────────────┐
                         │ Render engine (宿主)                       │
                         │  滚动 + 同步 + splitter 布局               │
                         └───────────────────────────────────────────┘
```

把这一切串起来的关键不变式：**所有列共享同一根统一视觉行轴**（`DiffProjection::rows`）。第 `i`
行在每一列里都画在相同的垂直位置。这让同步滚动变得轻而易举——render engine 只滚一根轴，每个
view 读取相同的 `[start, count)` 切片即可。

## 第一层：`DiffModel`（底层事实）

`DiffModel` 是 diff 事实本身，与视口宽度无关，也与呈现模式无关。它**不含任何 spacer 行**——
spacer 是呈现产物（见第二层）。

```rust
/// diff 的一侧（一个只读文档）。
struct SideDoc {
    // 由 editor-core 的 text/line/layout 机制承载（如 SnapshotGenerator）
    // 持有逻辑行；依赖宽度的换行在呈现层计算
}

/// 一段逻辑行在各侧之间如何对应。
enum AlignUnit {
    /// 各侧都存在的未改动行（跨侧 1:1）。
    Context { /* 各侧逻辑行范围 */ },
    /// 修改块：左侧为删除行，右侧为新增行。
    Replace { /* 左侧逻辑行范围, 右侧逻辑行范围 */ },
    /// 仅存在于 “after” 一侧的行。
    Add { /* 右侧逻辑行范围 */ },
    /// 仅存在于 “before” 一侧的行。
    Remove { /* 左侧逻辑行范围 */ },
}

struct DiffModel {
    sides: Vec<SideDoc>,        // 2 = diff，3 = 三方 merge
    alignment: Vec<AlignUnit>,  // 覆盖整个文档的有序对齐单元
}
```

### 数据来源：`file + patch`

主数据源是**一个文件加一个 patch**，而不是两份全文：

- patch 本身已编码了行配对（哪些行是 add/remove/context），因此无需再跑一次 diff 算法来构建
  `alignment`。
- patch 通常只携带每处改动周围的少量 context 行。要填充 patch hunk 之外的大段未改动区域，仍然需要
  完整的 `file`。即：**file 提供全文，patch 提供配对与改动内容。** 另一侧的全文通过 apply patch
  重建。

两点说明：

- `before + after`（两份全文）是另一种数据源；它需要跑 `editor-core-diff::diff_line_hunks` 来
  推导 `alignment`。两种来源最终都归约到同一个 `DiffModel`。
- **三方 merge 无法用单个 patch 表达。** 数据入口抽象为 “N 侧 + 它们的对齐关系”，`file + patch`
  是 2 侧的特例。不要把 “left/right” 写死进类型，给第三侧留出空间。

## 第二层：`DiffProjection`（呈现层）

给定一个 `DiffMode` 和各列宽度，呈现层产出**统一视觉行轴**。soft wrap、spacer 行、gutter mark
以及 diff 样式都在这一层落地。

```rust
enum DiffMode { Unified, SideBySide /*, ThreeWay */ }

struct DiffProjection {
    columns: usize,        // Unified = 1, SideBySide = 2, ThreeWay = 3
    rows: Vec<Row>,        // 统一视觉行轴（render engine 滚这个）
}

struct Row {
    slots: Vec<RowSlot>,   // slots.len() == columns
}

enum RowSlot {
    /// 来自某一侧文档的真实视觉行 segment。
    Line {
        side: usize,
        logical_line: usize,
        visual_in_logical: usize,   // 该逻辑行的第几个 soft-wrap 段
        change: DiffLineKind,       // Context / Add / Remove（来自 editor-core-diff）
    },
    /// 对齐占位行，任何一侧文档中都不存在。
    /// 仅在 SideBySide / ThreeWay 下产生；Unified 下绝不出现。
    Spacer { change: DiffLineKind },
}
```

### Unified 不是特例——它就是 `columns == 1`

同一份 `DiffModel`，用不同的 `DiffMode` + 列宽投影，得到不同的 `rows`。side-by-side、unified、
三方 merge 共用一套数据结构和一套滚动模型：

- **`SideBySide`**（`columns == 2`）：每侧独立换行；对每个对齐单元，取 `max(nLeft, nRight)` 个
  视觉行，在较短一侧末尾补 `Spacer`，使下一个单元的起点保持对齐。
- **`Unified`**（`columns == 1`）：不需要 spacer；修改块在单列中展开成顺序的行（先删除行、后新增
  行）。这是对 wrap 最友好的模式，建议在窄屏 / 移动端作为默认。
- **`ThreeWay`**（`columns == 3`）：与 side-by-side 相同，推广到三列。

### 对齐单位是逻辑行配对，不是视觉行

这是让 soft wrap 可解的核心思路。headless 层没有 “行高” 概念；一个逻辑行 wrap 成 N 段，就占
N 个视觉行。所以 “保持两侧对齐” 的含义就是**让每个对齐单元的视觉行数相等**：

1. 从 `alignment` 出发，遍历有序的 `AlignUnit`。
2. 对每个单元，用**该列的宽度**对各侧逻辑行换行，得到每侧 `nSide` 个视觉行。
3. 取各侧的 `max`；在较短侧的单元末尾补 `Spacer`。

各列宽度不同会产生不同的 wrap 行数，所以 spacer 很常见——这是 side-by-side + soft wrap 的固有
成本，不是设计缺陷。unified 模式完全规避了它。

### 重算分层（什么依赖宽度）

并非所有东西都依赖宽度；重算可以分阶段，避免无谓开销：

- **与宽度无关**（patch 解析一次，缓存）：各侧的逻辑行、对齐配对、每行的 change 类别。
- **依赖宽度**（宽度变化时重算）：各侧的 soft-wrap 布局，以及由各侧视觉行数推导出的 spacer 位置 /
  `rows` 轴。

splitter 拖动不进入 headless 层，但它派生出的**每列宽度是合法的 headless 输入**——与单 buffer 的
`viewport_width`（`crates/editor-core/src/snapshot.rs`）完全同类。拖动 splitter 等价于一次
resize 触发的 reflow：宿主用新宽度重新调用投影；对齐配对纹丝不动，只重建 wrap 与 `rows`。

### 两类样式

`Cell.styles`（`crates/editor-core/src/snapshot.rs`）承载二者的并集：

- **diff 语义样式**——新增/删除行背景、spacer 标记、行内（intra-line）高亮。它们依赖配对，在呈现层
  产出。（注意：`diff_line_hunks` 只到行级；行内高亮需要额外的 word/char diff。）
- **语法高亮样式**——来自 LSP / tree-sitter，per-side、per-file，跟随各侧文档。

view 投影时把两者叠加。

### 通过 line mark 实现 gutter

gutter（`+`/`-`/`~` 标记、行号）不是核心概念，也不涉及渲染。它由一个通用的、per-逻辑行的
**line mark** 抽象来喂数据：

- line mark 锚定到一个逻辑行，携带 id / payload；如何渲染由宿主决定。
- 它是 decoration 模型（`crates/editor-core/src/decorations.rs`）的兄弟：decoration 锚定到字符
  偏移、携带虚拟文本；line mark 锚定到逻辑行、给 gutter 喂数据。
- 建议：把 line mark 做成**核心的通用能力**（断点、git blame、折叠指示都能复用），diff 查看器是
  第一个 consumer。
- 对 diff 而言，呈现层按对齐单元把相应的 mark 挂到 `Row` / `RowSlot` 上。行号自然得到：左侧 gutter
  显示 `before_line`，右侧显示 `after_line`（即 `editor-core-diff` 中 `DiffLine` 的两个字段）。

## 第三层：Views（每列一个）

每个 view 是它那一列 `rows[*].slots[i]` 的薄投影器，把每个 slot 翻译成 cells / style /
line-mark（`Spacer` 产出空行）。

### 只读的 editor 命令接口

每个 view 背后是一个**只读的 `EditorCore` / `CommandExecutor`**（`crates/editor-core/src/commands.rs`）。
view 暴露与普通 editor 相同的命令接口，但限定为只读 / 导航子集：

- **放行：** 光标移动、选择、滚动、查找、跳转。
- **拒绝：** 插入、删除、替换、undo/redo。
- 建议：给 `Command` 加一个 `is_mutating()` 分类，由 view 层挡掉会修改文本的命令，而不是另立一套
  命令 enum。

收益：宿主的 keybinding → command 映射只写一套，既驱动普通 editor 也驱动 diff pane，交互体验一致。

### 两套坐标系：本侧 vs 统一

命令作用在**本侧文档的真实坐标**上（复用 editor 的全部导航逻辑，零改动）。渲染与滚动使用**统一
行轴**。呈现层提供 **本侧视觉行 ↔ 统一行** 的双向映射。

一个漂亮的副作用：**光标天然跳过 spacer。** spacer 不属于任何一侧的真实行序列，所以 “下移一行”
是在本侧真实视觉行上 +1，再映射回统一轴——光标永远不会停在占位行上。

## Render engine（宿主职责）

布局相关的、有状态的视觉部分都住在宿主里：

- **滚动与同步**——render engine 滚动统一的 `rows` 索引；每个 view 读取相同的 `[start, count)`，
  因此水平对齐自动成立。
- **splitter 布局**——把多列并排摆放、派生各列宽度、再把宽度回灌给投影。

view 只提供数据；它不管理滚动、布局或 splitter。

## 待定问题 / 后续工作

- **折叠（fold）。** 折叠不改文本（因此算 “只读”），但它会改变单侧的视觉行数——只折一侧而另一侧不折
  会破坏对齐。倾向于**第一版在 diff 查看器中禁用折叠**；联动折叠（按对齐单元两侧一起折）是后续
  工作，因为它会迫使呈现层的对齐算法把 “折叠” 也当作宽度之外的一个变量纳入考虑。
- **行内 diff。** `diff_line_hunks` 是行级的。要高亮修改行中具体变化的字符，需要额外的 word/char
  diff，作为 diff 语义样式呈现。
- **增量重算。** 第一版可以在宽度变化时整体重建 `rows`（与一次 resize reflow 同量级）。增量更新
  wrap / 对齐是后续优化。

## 与现有 crate 的关系

- `editor-core` —— 提供 per-side 的 text/line/layout/snapshot 机制（`SnapshotGenerator`、
  `Cell`、`StyleId`）以及只读命令引擎（`EditorCore`、`CommandExecutor`）。
- `editor-core-diff` —— 提供行级 diff 原语：`diff_line_hunks` 返回若干 `LineHunk`，其中的
  `DiffLine` 携带 `before_line` / `after_line` / `kind`（`crates/editor-core-diff/src/lib.rs`）。
- `editor-core-diff-view`（新）—— 本文描述的三层：`DiffModel`、`DiffProjection` 与各 view。
  headless；依赖上面两个 crate；不含任何渲染、滚动或 splitter 逻辑。

## 第一步实现

先定死 `AlignUnit` 的形态，以及两个投影构建函数 —— `project_unified` 与 `project_side_by_side`
—— 连同对齐算法（尤其是 `Replace` 块内左/右行如何配对）。这些定下来后，model 与 view 即可并行开发。
