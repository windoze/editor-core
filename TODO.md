# DIFF-VIEW 执行 TODO

来源：`PLAN.md`（editor-core-diff-view 落地计划 v1）。本文件把方案拆成可执行任务，并为每个代码改动任务安排紧随其后的专项 review 任务。

设计依据见已归档的 `docs/DIFF_VIEW.md`。v1 范围决策（不做 folding、不做行内 diff、宽度变更整体重算）见 `PLAN.md` §0，所有任务都按该决策执行。

## 执行纪律

- 一次只执行一个实现任务。完成该任务的代码、测试和格式化后，必须先执行紧随其后的 `Review` 任务，再进入下一个实现任务。
- 不要把两个实现任务混在一个改动里。尤其不要把新建 crate 骨架、对齐算法、projection、view 命令接口混在一起。
- 执行每个任务前只需要先读该任务列出的文件和入口函数；不要进行全仓开放式搜索，除非任务中明确写了"需要全仓确认"。
- 不要修改未列入任务范围的文件。若发现必须修改额外文件，先在任务记录里说明原因，再继续。
- 保持 diff 最小。优先复用 `editor-core` / `editor-core-diff` 既有能力，不引入不必要的新抽象。
- `editor-core-diff-view` 是纯 headless crate：不得包含任何 rendering、scrolling、splitter、像素或字体逻辑。splitter 推导出的 per-column width 是合法 headless 输入，但 splitter 本身不进入该 crate。
- 公共坐标默认是 logical line index（0-based）和 char offset / Unicode scalar index，复用 `editor-core` 既有语义，不要把 byte offset 或视觉宽度混入对齐逻辑。
- v1 三条范围决策是硬约束：不实现 folding、不实现行内 diff、宽度变更整体重算。不得提前实现这些被推迟的能力，也不得为它们预留破坏 v1 简洁性的复杂结构。
- 类型上保留 N 侧扩展余地（用 per-side 集合表达，不硬编码 left/right），但 v1 只实现两侧；ThreeWay 不实现。
- 不要删除或回滚用户/其他 agent 的无关改动。禁止使用 `git reset --hard`、`git checkout --` 等破坏性命令。
- 每个实现任务都必须补充或更新针对性测试。若确实无法测试，需要在任务结果中说明不可测试原因和人工验证方式。
- Review 任务是代码审查任务，不主动重构。只有发现明确 bug、测试缺口或质量问题时，才提出修复建议或创建后续修复任务（沿用 `T##F` / `T##FR` 命名）。

## 通用检查清单

- 格式化：`cargo fmt`。
- 新 crate 测试：`cargo test -p editor-core-diff-view`。
- 受影响核心 crate 测试：`cargo test -p editor-core`（仅当任务改动 `editor-core`，如 `is_mutating` / diff 样式常量）。
- 全量收口：`cargo test --all --all-targets` 和 `cargo clippy --all-targets --all-features -- -D warnings`。

## 任务依赖概览

- T01 crate 骨架 → 阻塞后续全部。
- T02 `AlignUnit` + 对齐算法 → 阻塞 T03/T04/T05。
- T03 `DiffModel`（before+after）→ 阻塞 T04/T05。
- T04 `file + patch` 数据源 → 依赖 T03，可与 T05 并行。
- T05 projection 骨架 + `project_unified` → 依赖 T03。
- T06 `project_side_by_side`（spacer/max 对齐）→ 依赖 T05。
- T07 diff-semantic 样式 → 依赖 T05/T06。
- T08 gutter line mark（最小实现）→ 依赖 T05/T06。
- T09 `Command::is_mutating()`（editor-core）→ 独立，建议在 T10 前完成。
- T10 Views + readonly 命令 + 坐标映射 → 依赖 T05/T06/T09。

## 任务列表

### [DONE] T01 实现：搭建 `editor-core-diff-view` crate 骨架

状态：DONE

范围文件：

- `Cargo.toml`（workspace 根，`members`）
- `crates/editor-core-diff-view/Cargo.toml`，新增
- `crates/editor-core-diff-view/src/lib.rs`，新增
- `crates/editor-core-diff-view/src/model.rs`，新增（占位）
- `crates/editor-core-diff-view/src/projection.rs`，新增（占位）
- `crates/editor-core-diff-view/src/view.rs`，新增（占位）
- `crates/editor-core-diff-view/src/style.rs`，新增（占位）

已知入口：

- workspace 根 `Cargo.toml` 的 `[workspace].members` 与 `[workspace.package]`
- `crates/editor-core-diff/Cargo.toml` 作为新 crate 元数据风格参考
- `crates/editor-core/Cargo.toml` 的 path 依赖写法

实现要求：

1. 在 workspace `members` 中加入 `crates/editor-core-diff-view`，元数据（version/edition/license 等）沿用 `version.workspace = true` 等 workspace 继承风格。
2. 依赖只加 `editor-core`（path）和 `editor-core-diff`（path），不要引入渲染/字体/序列化等无关依赖；如确需 `serde`，按 `editor-core` 的 optional feature 风格加，并默认关闭。
3. `lib.rs` 声明 `model` / `projection` / `view` / `style` 四个模块并 re-export 计划中的公开类型名（此任务可先用空 struct/enum 占位，保证编译）。
4. crate 顶层 doc 注释写明：纯 headless，不含 rendering/scrolling/splitter；并链接 `PLAN.md`。
5. 不实现任何业务逻辑，只保证 crate 能编译、能被 workspace 识别。

测试要求：

1. `cargo build -p editor-core-diff-view`。
2. 加一个最小 smoke 测试（如 `assert!(true)` 或占位类型可构造），运行 `cargo test -p editor-core-diff-view`。
3. `cargo clippy -p editor-core-diff-view --all-targets -- -D warnings`。

验收标准：

- 新 crate 进入 workspace 且可编译。
- 模块划分与 `PLAN.md` §1 一致，无多余依赖。

完成记录：

- 2026-06-07：新增 `editor-core-diff-view` workspace crate，包含 `model` / `projection` / `view` / `style` 四个模块、计划公开类型的占位定义与最小 smoke test；crate 保持 headless，仅依赖 `editor-core` 和 `editor-core-diff` path 依赖。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo build -p editor-core-diff-view`；`cargo test -p editor-core-diff-view`；`cargo clippy -p editor-core-diff-view --all-targets -- -D warnings`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T01R Review：审查 crate 骨架

状态：DONE

审查范围：T01 的所有 diff。

审查重点：

1. workspace 成员、依赖是否最小且为 path 依赖，是否误引入无关 crate。
2. 模块划分是否与 `PLAN.md` §1 一致，re-export 是否合理、未过度 public。
3. crate 是否保持纯 headless（无 rendering/scrolling/splitter 痕迹）。
4. 占位类型是否会误导后续实现（命名、可见性）。
5. 是否混入业务逻辑而非纯骨架。

建议命令：

- `cargo build -p editor-core-diff-view`
- `cargo test -p editor-core-diff-view`

完成记录：

- 2026-06-07：已审查 T01 crate 骨架；未发现需修复问题。workspace 成员、path 依赖、模块划分、re-export、headless 约束与占位 smoke test 均符合 T01/T01R 要求，未混入业务逻辑或 rendering/scrolling/splitter 相关实现。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo build -p editor-core-diff-view`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次仅更新 review/TODO/计划文档，T01 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T02 实现：固化 `AlignUnit` 与对齐算法（before + after 来源）

状态：DONE

依赖：T01。这是 `PLAN.md` §2 点名的 first step，阻塞 T03/T04/T05。

范围文件：

- `crates/editor-core-diff-view/src/model.rs`
- `crates/editor-core-diff-view/tests/alignment.rs`，新增

已知入口：

- `editor_core_diff::diff_line_hunks`（`crates/editor-core-diff/src/lib.rs`）
- `editor_core_diff::{DiffLine, DiffLineKind, LineHunk, LineDiffConfig}`
- `DiffLine.before_line` / `DiffLine.after_line` / `DiffLine.kind`

实现要求：

1. 按 `PLAN.md` §2.1 定义 `AlignUnit`：`Context { sides: Vec<Range<usize>> }`、`Replace { sides: Vec<Range<usize>> }`、`Add { side, lines }`、`Remove { side, lines }`，用 0-based 逻辑行 `Range` 表达；v1 `sides.len() == 2`，但类型保留 N 侧余地，不硬编码 left/right。
2. 实现 `before + after` → `Vec<AlignUnit>` 的对齐算法：基于 `diff_line_hunks` 的 unified 顺序 `DiffLine` 序列，连续 Context 合成 `Context`，连续 Remove+Add 修改块合成 `Replace`，纯 Add/纯 Remove 合成 `Add`/`Remove`。
3. `Replace` 块内采用**块级配对**（左整块 range ↔ 右整块 range），不做块内逐行最优匹配（行内 diff 已推迟，见 §0.2）。
4. 必须覆盖整个文档：hunk 之外的大段未改区域要补成 `Context` 单元（`diff_line_hunks` 只给 hunk，需用两侧总行数补齐 hunk 间 context）。
5. 不引入 spacer（spacer 是 presentation 产物，属 projection 层）。

测试要求：

1. 无变更 → 全部 `Context` 且覆盖全文。
2. 纯增、纯删、单个修改块、多个分散修改块各一组用例。
3. 文件首行改动、末行改动、末尾有/无换行边界用例。
4. 性质测试：所有单元各侧 range 按序拼接 == 该侧完整逻辑行序列（无重叠、无遗漏、单调递增）。
5. 运行 `cargo test -p editor-core-diff-view --test alignment`。

验收标准：

- 对齐结果完整覆盖两侧全文且无重叠。
- `Replace` 配对策略明确（块级），并有测试固定。

完成记录：

- 2026-06-07：在 `model.rs` 中固化 `AlignUnit::{Context, Replace, Add, Remove}`，以 `Range<usize>` 表达 0-based 逻辑行区间，v1 使用两侧但 `Context` / `Replace` 保留 per-side `Vec` 扩展形状。
- 2026-06-07：新增 `align_before_after(before, after, LineDiffConfig)`，基于 `diff_line_hunks` 的 unified hunk 顺序生成完整 alignment：补齐 hunk 外 context，连续 context 合并为 `Context`，连续非 context diff 行归并为块级 `Replace` 或纯 `Add` / `Remove`，不引入 spacer 或行内 diff。
- 2026-06-07：新增 `tests/alignment.rs`，覆盖无变更、纯增、纯删、单个修改块、多个分散修改块、首行/末行改动、末尾有/无换行边界，并用性质检查验证每侧 range 按序拼接完整全文、无重叠、无遗漏。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test alignment`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T02R Review：审查对齐算法

状态：DONE

审查范围：T02 的所有 diff。

审查重点：

1. `AlignUnit` 是否保留 N 侧扩展余地、未硬编码 left/right。
2. hunk 间未改区域是否被正确补成 `Context`，是否存在行号 off-by-one。
3. `Replace`/`Add`/`Remove` 边界是否正确，连续修改块合并是否符合 unified 顺序。
4. 覆盖完整性性质测试是否真的验证拼接 == 全文（而非仅抽样）。
5. 是否误引入 spacer 或行内 diff 逻辑。

建议命令：

- `cargo test -p editor-core-diff-view --test alignment`
- `cargo test -p editor-core-diff-view`

完成记录：

- 2026-06-07：已审查 T02 对齐算法与测试；未发现需修复问题。`AlignUnit` 保留 per-side `Vec<Range<usize>>` 扩展形状，hunk 外 context 补齐、hunk 内 context/修改块边界、块级 `Replace` 配对、纯 `Add`/`Remove` 归类与完整覆盖性质测试均符合 T02/T02R 要求；未引入 spacer 或行内 diff 逻辑。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test alignment`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次 review 未改动编译输出，T02 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T03 实现：`DiffModel`（width-independent 真值，before + after 来源）

状态：DONE

依赖：T02。

范围文件：

- `crates/editor-core-diff-view/src/model.rs`
- `crates/editor-core-diff-view/tests/model.rs`，新增

已知入口：

- T02 的 `AlignUnit` 与对齐算法
- `editor_core_diff::{diff_line_hunks, LineDiffConfig}`
- `editor_core::snapshot::SnapshotGenerator`（后续 projection 用，model 层可仅持有文本/逻辑行）

实现要求：

1. 实现 `SideDoc`（承载一侧逻辑行/全文，供后续按列宽 wrap；不在此层做 wrap）与 `DiffModel { sides: Vec<SideDoc>, alignment: Vec<AlignUnit> }`。
2. 实现 `DiffModel::from_before_after(before, after, LineDiffConfig)`，内部复用 T02 算法。
3. 实现 width-independent 缓存：各侧逻辑行、alignment 配对、每行 change kind 一次解析后保存。
4. 提供 `side_line_kind(side, logical_line) -> DiffLineKind`，由 `AlignUnit` 推导，供 projection 查询。
5. `DiffModel` 不含 spacer、不含 wrap、不含任何 width 依赖。

测试要求：

1. `from_before_after` 在无变更、纯增/删、修改块下产出与 T02 一致的 `alignment`。
2. `side_line_kind` 对每侧每行返回正确 Context/Add/Remove。
3. 各侧逻辑行数与输入文本一致（含末尾换行边界）。
4. 运行 `cargo test -p editor-core-diff-view --test model`。

验收标准：

- `DiffModel` 是 width/mode 无关的真值，缓存内容完整。
- `side_line_kind` 与 alignment 一致。

完成记录：

- 2026-06-07：在 `model.rs` 中将 `SideDoc` / `DiffModel` 从占位类型替换为真实 width-independent 模型：`SideDoc` 缓存原文与不含 trailing LF 的逻辑行，`DiffModel::from_before_after` 复用 T02 alignment，并缓存每侧每行 `DiffLineKind`。
- 2026-06-07：新增 `DiffModel::{sides, side, alignment, side_line_kind}` 与 `SideDoc::{from_text, text, logical_lines, logical_line, line_count}` 查询接口；模型层不包含 spacer、wrap、rendering、scrolling 或 width 依赖。
- 2026-06-07：新增 `tests/model.rs`，覆盖无变更、纯增、纯删、修改块 alignment 一致性，`side_line_kind` 在 Context/Add/Remove/Replace 下的每侧结果，以及末尾换行边界和空文档逻辑行缓存；同步更新旧 smoke 测试以使用真实模型默认构造。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test model`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T03R Review：审查 `DiffModel`

状态：DONE

审查范围：T03 的所有 diff。

审查重点：

1. `DiffModel` 是否确实 width/mode 无关，未泄漏 wrap 或 spacer。
2. width-independent 缓存是否完整、是否有重复解析。
3. `side_line_kind` 推导是否覆盖所有 `AlignUnit` 变体与边界行。
4. `SideDoc` 是否为后续 `SnapshotGenerator` wrap 预留了干净接口。
5. 是否过度暴露内部字段。

建议命令：

- `cargo test -p editor-core-diff-view --test model`
- `cargo test -p editor-core-diff-view`

完成记录：

- 2026-06-07：已审查 T03 的 `DiffModel` / `SideDoc` 实现与模型测试；未发现需修复问题。模型保持 width/mode 无关，未泄漏 wrap、spacer、rendering、scrolling 或 width 依赖；缓存覆盖各侧逻辑行、alignment 与每行 `DiffLineKind`，`side_line_kind` 覆盖 T03 生成的 `Context` / `Add` / `Remove` / `Replace` 语义；公开接口未暴露可变内部状态。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test model`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次 review 未改动编译输出，T03 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T04 实现：`file + patch` 数据源归约到 `DiffModel`

状态：DONE

依赖：T03。可与 T05 并行。

范围文件：

- `crates/editor-core-diff-view/src/model.rs`
- `crates/editor-core-diff-view/tests/model_patch.rs`，新增

已知入口：

- `DiffModel::from_before_after`（T03，作为归约目标）
- T02 对齐算法

实现要求：

1. 实现 `DiffModel::from_file_and_patch(file, patch)`：`file` 提供全文，patch 提供配对与改动内容；用 patch 重建另一侧全文后归约到与 `from_before_after` **完全相同**的 `DiffModel`。
2. patch 已编码 add/remove/context 配对，优先直接利用，避免对全文重新跑 diff 算法（hunk 外大段未改区域仍由 `file` 补齐）。
3. 选定并固定 patch 文本格式（如 unified diff）；解析失败要返回明确错误而非 panic。
4. 两种数据源（before+after / file+patch）必须 reduce 到同一 `DiffModel` 形状。
5. 不硬编码 left/right；保持两侧抽象。

测试要求：

1. 同一改动分别用 before+after 与 file+patch 构建，断言 `alignment` 与各侧逻辑行一致。
2. patch 只含少量 context、hunk 外大段未改区域能正确补齐。
3. 畸形 patch 返回错误、不 panic。
4. 运行 `cargo test -p editor-core-diff-view --test model_patch`。

验收标准：

- file+patch 与 before+after 归约结果一致。
- patch 解析健壮，错误路径明确。

完成记录：

- 2026-06-07：新增 `DiffModel::from_file_and_patch(file, patch)`，固定支持单文件 unified diff，`file` 作为 before 侧，patch hunk 记录直接重建 after 侧全文并生成 alignment，不对重建后的全文重新运行 diff。
- 2026-06-07：新增 `PatchParseError`，解析/应用失败返回带行号和消息的明确错误；解析支持常见 unified diff 元数据、空 patch、hunk range、context/add/remove 行和 `\ No newline at end of file` 标记，并校验 patch 上下文/删除行必须匹配输入文件。
- 2026-06-07：新增 `tests/model_patch.rs`，覆盖 file+patch 与 before+after 归约结果一致、小 context 下 hunk 外未改区域补齐、空 patch、末尾无换行 marker（含 CRLF patch 行结束符）、hunk 计数畸形错误和非 diff 文本错误。
- 验证通过：`cargo fmt`；`cargo test -p editor-core-diff-view --test model_patch`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T04R Review：审查 file+patch 数据源

状态：DONE

审查范围：T04 的所有 diff。

审查重点：

1. file+patch 与 before+after 是否真正归约到同一 `DiffModel`（含 hunk 外区域）。
2. patch 解析是否健壮，越界/畸形/空 patch 是否安全。
3. 是否多余地对全文重跑 diff，违背"利用 patch 已有配对"的设计意图。
4. patch 格式假设是否在文档/注释中固定。
5. 是否引入 left/right 硬编码。

建议命令：

- `cargo test -p editor-core-diff-view --test model_patch`
- `cargo test -p editor-core-diff-view`

完成记录：

- 2026-06-07：已审查 T04 的 `DiffModel::from_file_and_patch`、unified diff 解析/应用逻辑与 `tests/model_patch.rs`；未发现需修复问题。file+patch 路径直接利用 hunk 记录重建 after 文本与 alignment，hunk 外未改区域由输入 file 补齐，错误路径返回 `PatchParseError` 而非 panic，未对重建后的全文重新运行 diff。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test model_patch`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次 review 未改动编译输出，T04 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T05 实现：`DiffProjection` 骨架 + `project_unified`

状态：DONE

依赖：T03。

范围文件：

- `crates/editor-core-diff-view/src/projection.rs`
- `crates/editor-core-diff-view/tests/projection_unified.rs`，新增

已知入口：

- `DiffModel` / `AlignUnit` / `side_line_kind`（T03）
- `editor_core::snapshot::SnapshotGenerator`（`set_viewport_width`、`get_headless_grid`）
- `editor_core::snapshot::HeadlessLine`（`logical_line_index`、`visual_in_logical`）
- `editor_core_diff::DiffLineKind`

实现要求：

1. 按 `PLAN.md` §4 定义 `DiffMode { Unified, SideBySide }`、`DiffProjection { columns, rows: Vec<Row> }`、`Row { slots: Vec<RowSlot> }`、`RowSlot::{ Line { side, logical_line, visual_in_logical, change }, Spacer { change } }`。
2. 实现入口 `DiffProjection::build(&DiffModel, DiffMode, &[usize] /* per-column widths */)`；**宽度变化即整体重建**，不做增量（§0.3）。
3. 实现 `project_unified`（columns==1）：按 alignment 顺序展开为单列；修改块按 unified 顺序（先 removed 行、后 added 行）排列；**不产生 Spacer**。
4. 每侧 wrap 复用 `SnapshotGenerator`（按该列宽 `set_viewport_width` 后 `get_headless_grid`），逻辑行的每个 wrap segment 占一个 `RowSlot::Line`，`visual_in_logical` 来自 `HeadlessLine`。
5. 不在此任务实现 side-by-side / spacer（留给 T06）。

测试要求：

1. Unified 下 `columns == 1`，`rows` 中不含任何 `Spacer`。
2. 修改块按"先删后增"顺序展开。
3. 同一 `DiffModel` 两次相同宽度 build 产出一致（确定性）；改变宽度后 wrap segment 数随之变化。
4. CJK/emoji 行 wrap 后 visual segment 数正确。
5. 运行 `cargo test -p editor-core-diff-view --test projection_unified`。

验收标准：

- Unified projection 正确、确定、无 spacer。
- wrap 完全复用 `SnapshotGenerator`，无自实现换行。

完成记录：

- 2026-06-07：在 `projection.rs` 中将 placeholder 替换为真实 `DiffMode` / `DiffProjection` / `Row` / `RowSlot` 数据结构，新增 `DiffProjection::build` 与 `project_unified`，统一按宽度整体重建；`SideBySide` 分支保留到 T06 实现。
- 2026-06-07：Unified projection 复用 `SnapshotGenerator::set_viewport_width` + `get_headless_grid` 计算各侧 wrap segment，按 alignment 顺序展开单列，Context 使用 after 侧展示，Replace 按先 Remove 后 Add 输出，不产生 `Spacer`。
- 2026-06-07：新增 `tests/projection_unified.rs`，覆盖单列无 spacer、修改块先删后增、相同宽度确定性、宽度变化触发 wrap row 数变化，以及 CJK/emoji 宽度下的 visual segment 序号。
- 验证通过：`cargo fmt`；`cargo test -p editor-core-diff-view --test projection_unified`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T05R Review：审查 projection 骨架与 unified

状态：DONE

审查范围：T05 的所有 diff。

审查重点：

1. Unified 是否确实 `columns==1` 且无 spacer；修改块顺序是否为先删后增。
2. wrap 是否完全复用 `SnapshotGenerator`，是否存在自实现换行或宽度计算。
3. `build` 是否为纯函数式整体重建，无残留增量状态。
4. `RowSlot::Line` 的 `visual_in_logical` / `logical_line` / `side` 是否准确。
5. 确定性与宽度敏感性是否有测试固定。

建议命令：

- `cargo test -p editor-core-diff-view --test projection_unified`
- `cargo test -p editor-core-diff-view`

完成记录：

- 2026-06-07：已审查 T05 的 `DiffProjection` / `Row` / `RowSlot` 数据结构、`DiffProjection::build`、`project_unified` 与 `tests/projection_unified.rs`；未发现需修复问题。Unified projection 保持 `columns == 1` 且不产生 `Spacer`，修改块按先 Remove 后 Add 展开，wrap 通过 `SnapshotGenerator::set_viewport_width` + `get_headless_grid` 取得 `logical_line` / `visual_in_logical`，`build` 为无增量状态的整体重建。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test projection_unified`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次 review 未改动编译输出，T05 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T06 实现：`project_side_by_side`（spacer + max 对齐）

状态：DONE

依赖：T05。

范围文件：

- `crates/editor-core-diff-view/src/projection.rs`
- `crates/editor-core-diff-view/tests/projection_side_by_side.rs`，新增

已知入口：

- T05 的 `DiffProjection::build` / `Row` / `RowSlot`
- `SnapshotGenerator`（按各列不同宽度 wrap）

实现要求：

1. 实现 `project_side_by_side`（columns==2）：按 `PLAN.md` §4 的对齐规则——每个 `AlignUnit` 内各侧用**该列宽度**独立 wrap 得 `nSide` 个 visual row，取 `max` across sides，较短侧在该单元末尾补 `Spacer`，保证下一个单元起点对齐。
2. `Spacer` 的 `change` 取所属单元的语义（如 Add 单元另一侧补 Add spacer），供宿主着色。
3. 两列宽度可不同（splitter 推导出的 per-column width 是合法输入），不同 wrap 数导致 spacer 是预期行为。
4. 不改动 T05 的 unified 路径。

测试要求：

1. 每个 alignment unit 内两列 row 数相等（含 spacer 后）；整条 `rows` 两列等长。
2. 一侧 wrap 多于另一侧时，短侧在单元末尾补 spacer 而非中间。
3. 两列不同宽度时对齐仍成立。
4. Add/Remove 单元在缺失侧整段补 spacer。
5. 运行 `cargo test -p editor-core-diff-view --test projection_side_by_side`。

验收标准：

- side-by-side 下所有列共享统一 row 轴且逐行对齐。
- spacer 仅出现在单元末尾，宽度差异下对齐稳定。

完成记录：

- 2026-06-07：在 `projection.rs` 中实现 `DiffMode::SideBySide` 路径，要求两列宽度输入，按两侧各自列宽复用 `SnapshotGenerator` wrap，并按每个 `AlignUnit` 内两侧 visual row 数取 `max` 后补齐到统一 row 轴。
- 2026-06-07：`Context` / `Replace` / `Add` / `Remove` 单元均按单元末尾补 `Spacer`；`Add` / `Remove` 缺失侧整段补对应 change 的 spacer，`Replace` 中 before 列使用 Remove 语义、after 列使用 Add 语义；未改动 T05 unified 路径。
- 2026-06-07：新增 `tests/projection_side_by_side.rs`，覆盖 Add/Remove 缺失侧 spacer、不同列宽下的 unit 末尾补齐、Replace 短侧 spacer change 语义，以及所有 projected row 均为两列。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test projection_side_by_side`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T06R Review：审查 side-by-side 对齐

状态：DONE

审查范围：T06 的所有 diff。

审查重点：

1. 每个 alignment unit 内 max 对齐与 spacer 末尾补齐是否正确。
2. 两列不同宽度下是否仍逐行对齐，是否存在错位累积。
3. `Spacer.change` 语义是否正确，供着色无歧义。
4. 是否影响或回退了 T05 unified 路径。
5. 是否提前实现了被推迟的增量重算。

建议命令：

- `cargo test -p editor-core-diff-view --test projection_side_by_side`
- `cargo test -p editor-core-diff-view`

完成记录：

- 2026-06-07：已审查 T06 的 `project_side_by_side` 实现与 `tests/projection_side_by_side.rs`；未发现需修复问题。每个 alignment unit 内按两侧 visual row 数取 `max` 后在单元末尾补 `Spacer`，不同列宽下对齐稳定，`Add` / `Remove` / `Replace` 的 `Spacer.change` 语义明确，T05 unified 路径未被回退，未引入增量重算逻辑。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test projection_side_by_side`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次 review 未改动编译输出，T06 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T07 实现：diff-semantic 样式常量与叠加

状态：DONE

依赖：T05/T06。

范围文件：

- `crates/editor-core/src/intervals.rs`
- `crates/editor-core-diff-view/src/style.rs`
- `crates/editor-core-diff-view/src/projection.rs` 或 `view.rs`（叠加点）
- `crates/editor-core-diff-view/tests/style.rs`，新增

已知入口：

- `editor_core::intervals` 的 `StyleId`（`pub type StyleId = u32`）与现有命名段（`0x0300_xxxx` … `0x0800_xxxx`）
- `editor_core::snapshot::Cell.styles: Vec<StyleId>`

实现要求：

1. 在 `editor-core` 的 `intervals.rs` 中新增一段未占用的 diff 专用 `StyleId` 常量（沿用 `0x0X00_000Y` 风格，建议 `0x0900_xxxx`）：至少 `DIFF_ADD_LINE_STYLE_ID`、`DIFF_REMOVE_LINE_STYLE_ID`、`DIFF_SPACER_STYLE_ID`；确认与现有段不冲突（此任务允许定向 grep `STYLE_ID` 确认）。
2. `style.rs` re-export / 封装这些常量，供 projection 与 view 使用。
3. 在 projection 或 view 投影时把 diff-semantic 样式叠加进 `Cell.styles`：Add/Remove 行整行背景、Spacer 标记。
4. **不实现行内/字符级高亮样式**（§0.2）；只做行级。
5. 语法高亮样式（若有）跟随各侧文档，与 diff-semantic 样式**叠加**而非互斥（v1 可只验证 diff-semantic 一类）。

测试要求：

1. Add 行携带 `DIFF_ADD_LINE_STYLE_ID`，Remove 行携带 `DIFF_REMOVE_LINE_STYLE_ID`，Spacer 携带 `DIFF_SPACER_STYLE_ID`，Context 行不携带 diff 背景。
2. 新增常量与既有 `STYLE_ID` 段不冲突。
3. 运行 `cargo test -p editor-core-diff-view --test style`。
4. 运行 `cargo test -p editor-core`（确认新增常量不破坏 core）。

验收标准：

- diff 背景/spacer 样式正确叠加到 cell。
- 不含行内 diff 样式，StyleId 命名段无冲突。

完成记录：

- 2026-06-07：在 `editor-core` 的 `StyleId` 命名空间新增 `0x0900_xxxx` diff 专用段：`DIFF_ADD_LINE_STYLE_ID`、`DIFF_REMOVE_LINE_STYLE_ID`、`DIFF_SPACER_STYLE_ID`，并从 `editor-core` 根模块导出，未与现有 `0x0300` / `0x0400` / `0x0700` / `0x0800` 段冲突。
- 2026-06-07：在 `editor-core-diff-view/src/style.rs` re-export diff 样式常量，并提供行级 diff 样式叠加辅助；projection 的 `RowSlot` 现在携带 `Cell` 数据，Add/Remove 行会在保留既有 `Cell.styles` 的基础上追加 diff 背景样式，Spacer 携带 spacer 样式，Context 行不追加 diff 背景；未实现行内/字符级 diff 样式。
- 2026-06-07：新增 `tests/style.rs`，覆盖 Add/Remove/Spacer/Context 样式、diff 样式与已有 cell style 的叠加关系，以及新增常量段不冲突；同步调整既有 projection/smoke 测试以适配 `RowSlot` 携带 cells。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test style`；`cargo test -p editor-core`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- 说明：首次运行 `cargo test -p editor-core` 时遇到 Rust 增量编译缓存缺失对象文件错误；已执行 `cargo clean -p editor-core` 清理受影响构建缓存后重跑同一测试并通过。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T07R Review：审查 diff 样式

状态：DONE

审查范围：T07 的所有 diff。

审查重点：

1. 新增 `StyleId` 段是否与既有命名段冲突，命名/取值是否规范。
2. Add/Remove/Spacer/Context 的样式叠加是否正确、是否漏标或多标。
3. 是否误实现了行内/字符级高亮（应推迟）。
4. diff-semantic 与语法高亮是否为叠加关系而非覆盖。
5. 对 `editor-core` 的改动是否最小、是否破坏既有测试。

建议命令：

- `cargo test -p editor-core-diff-view --test style`
- `cargo test -p editor-core`

完成记录：

- 2026-06-07：已审查 T07 的 diff-semantic 样式实现与测试；未发现需修复问题。新增 `StyleId` 使用 `0x0900_xxxx` diff 专用段且未与既有 core/render-skia 样式段冲突，`Add` / `Remove` / `Spacer` / `Context` 样式叠加符合 T07/T07R 要求，diff-semantic 样式追加到既有 `Cell.styles` 而非覆盖，未发现行内/字符级 diff 高亮实现。
- 2026-06-07：已确认 `editor-core` 改动仅新增并导出 diff 样式常量；`editor-core-diff-view` 改动集中在 projection slot cells 与 `style.rs` 辅助，未引入 rendering、scrolling、splitter 或其它 UI 逻辑。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test style`；`cargo test -p editor-core`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次 review 仅更新 `TODO.md` / `memory/claude_plan.md` 文档记录，T07 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T08 实现：gutter line mark（diff-view 内最小实现）

状态：DONE

依赖：T05/T06。

范围文件：

- `crates/editor-core-diff-view/src/projection.rs`
- `crates/editor-core-diff-view/tests/gutter.rs`，新增

已知入口：

- T05/T06 的 `Row` / `RowSlot`
- `editor_core_diff::DiffLine`（`before_line` / `after_line` 字段语义）
- `editor_core::decorations`（仅作"后续提取为通用 line mark"的兄弟参照，本任务不改它）

实现要求：

1. 按 `PLAN.md` §5.2 的 v1 裁剪：**不**改 `editor-core` 通用 line mark 设施，先在 diff-view 内提供最小 gutter 信息——projection 在 `Row`/`RowSlot` 上挂 diff 所需的 gutter 标记（`+`/`-`，spacer 无标记）与两侧行号。
2. 行号自然落地：左 gutter 显示 `before_line`，右 gutter 显示 `after_line`（来自各侧逻辑行 → `DiffLine` 的语义）；wrap 续段不重复显示行号（仅 segment 0 显示）。
3. gutter 信息是数据，不做任何渲染；宿主决定如何画。
4. 把"提取为 `editor-core` 通用 line mark 能力（断点/blame/fold 复用）"作为后续项记录在任务完成记录里，不在本任务实现。

测试要求：

1. Add 行右 gutter 有 `after_line` 且标 `+`；Remove 行左 gutter 有 `before_line` 且标 `-`；Context 行两侧均有行号、无 +/-。
2. Spacer 无行号、无 +/- 标记。
3. wrap 续段（`visual_in_logical > 0`）不重复行号。
4. 运行 `cargo test -p editor-core-diff-view --test gutter`。

验收标准：

- 每行 gutter 标记与行号正确，spacer/续段处理符合预期。
- 未触碰 `editor-core` 通用设施。

完成记录：

- 2026-06-07：在 `editor-core-diff-view` projection 层新增纯数据 `Gutter { before_line, after_line, marker }`，并挂载到 `RowSlot::Line` / `RowSlot::Spacer`；未修改 `editor-core` 通用 line mark / decoration 设施。
- 2026-06-07：Add 行首个 wrap segment 在 after gutter 暴露 0-based `after_line` 与 `+` 标记，Remove 行首个 wrap segment 在 before gutter 暴露 0-based `before_line` 与 `-` 标记，Context 在 side-by-side 各列暴露本侧行号，Unified context 暴露 before/after 两侧行号；Spacer 与 wrap 续段 gutter 保持为空。
- 2026-06-07：新增 `tests/gutter.rs`，覆盖 Add/Remove/Context 行号与标记、Spacer 无 gutter、wrap 续段不重复行号/标记，以及 unified context 双侧行号；同步更新 smoke 测试并 re-export `Gutter`。
- 后续项：把 diff-view 内最小 gutter line mark 提取为 `editor-core` 通用 line mark 能力（断点/blame/fold 复用）仍按 TODO 末尾“推迟到后续版本”执行，本任务未实现。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test gutter`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T08R Review：审查 gutter line mark

状态：DONE

审查范围：T08 的所有 diff。

审查重点：

1. 左右行号映射（before_line/after_line）是否正确，是否有 off-by-one。
2. spacer 与 wrap 续段是否正确地不显示行号/标记。
3. 是否越界改动了 `editor-core` 通用 line mark/decoration（v1 应只在 diff-view 内）。
4. gutter 是否保持纯数据、无渲染逻辑。
5. 后续"提取为通用能力"是否被清晰记录。

建议命令：

- `cargo test -p editor-core-diff-view --test gutter`
- `cargo test -p editor-core-diff-view`

完成记录：

- 2026-06-07：已审查 T08 的 gutter line mark 实现与 `tests/gutter.rs`；未发现需修复问题。`Gutter` 保持在 diff-view projection 层作为纯数据，Add/Remove/Context 行号与 `+`/`-` 标记符合 T08/T08R 要求，Spacer 与 wrap 续段不显示行号/标记。
- 2026-06-07：已确认 T08 未改动 `editor-core` 通用 line mark / decoration 设施；后续“提取为通用能力”已保留在 T08 完成记录与 TODO 末尾推迟项中。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test gutter`；`cargo test -p editor-core-diff-view`。
- Full test suite：本次 review 仅更新 `TODO.md` / `memory/claude_plan.md` 文档记录，T08 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [DONE] T09 实现：`Command::is_mutating()` 分类（editor-core）

状态：DONE

依赖：无（独立）。建议在 T10 前完成。

范围文件：

- `crates/editor-core/src/model.rs`
- `crates/editor-core/tests/command_is_mutating.rs`，新增

已知入口：

- `editor_core::model::Command`（`Edit` / `Cursor` / `View` / `Style`）
- `EditCommand`（`crates/editor-core/src/model.rs:212`）
- `CursorCommand`（`:422`）、`ViewCommand`（`:565`）、`StyleCommand`（`:639`）

实现要求：

1. 在 `Command` 上新增 `pub fn is_mutating(&self) -> bool`，覆盖 `Edit`/`Cursor`/`View`/`Style` 全部变体。
2. 归类原则（按 `PLAN.md` §6）：insert/delete/replace/undo/redo 等改变文本或历史的为 mutating；cursor 移动、selection、scroll、find、go-to 为非 mutating。
3. **v1 折叠归入 mutating/拒绝**（§0.1）：`ViewCommand` 中折叠相关项归为 mutating。
4. 不新增独立命令 enum，不改变既有命令语义；仅新增分类方法。
5. 该方法供 diff-view 的 readonly view 层使用（T10），但本任务只在 `editor-core` 内实现与测试。

测试要求：

1. 对每个 `EditCommand` 变体断言 `is_mutating()` 结果。
2. cursor/selection/scroll/find/go-to 断言为非 mutating。
3. 折叠相关 `ViewCommand` 断言为 mutating。
4. 运行 `cargo test -p editor-core --test command_is_mutating`。
5. 运行 `cargo test -p editor-core`。

验收标准：

- `is_mutating()` 覆盖全部命令变体且分类正确（含折叠归 mutating）。
- 未改变既有命令行为。

完成记录：

- 2026-06-07：在 `editor-core` 的 `Command` 上新增 `pub fn is_mutating(&self) -> bool`，通过私有 helper 显式覆盖 `EditCommand` / `CursorCommand` / `ViewCommand` / `StyleCommand` 全部现有变体，新增变体时会触发非 exhaustive 匹配检查。
- 2026-06-07：分类规则按 readonly diff-view 需求固化：所有 `EditCommand` 均为 mutating；cursor/selection/find/go-to 类 `CursorCommand` 为非 mutating；`ViewCommand` 中配置变更为 mutating，`ScrollTo` / `GetViewport` 为非 mutating；所有 style/folding/bracket-highlight `StyleCommand` 均为 mutating，折叠命令按 v1 决策归入拒绝类。
- 2026-06-07：新增 `crates/editor-core/tests/command_is_mutating.rs`，覆盖每个 `EditCommand` 变体、cursor/selection/scroll/find/go-to 非 mutating、View 配置与查询分类，以及 folding/style 命令 mutating。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core --test command_is_mutating`；`cargo test -p editor-core`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。

### [DONE] T09R Review：审查 `is_mutating` 分类

状态：DONE

审查范围：T09 的所有 diff。

审查重点：

1. 是否覆盖全部命令变体（含新增变体时的 exhaustive 匹配，避免遗漏）。
2. 折叠是否确实归为 mutating（符合 v1 决策）。
3. 边界命令（如带选择副作用的移动、scroll）分类是否合理。
4. 是否误新增独立命令 enum 或改动既有语义。
5. 测试是否逐变体覆盖而非抽样。

建议命令：

- `cargo test -p editor-core --test command_is_mutating`
- `cargo test -p editor-core`

完成记录：

- 2026-06-07：已审查 T09 的 `Command::is_mutating` 实现与 `command_is_mutating` 测试；未发现需修复问题。`EditCommand` / `CursorCommand` / `ViewCommand` / `StyleCommand` 分类均使用无通配符匹配覆盖全部现有变体，新增变体时会触发非 exhaustive 检查。
- 2026-06-07：已确认所有编辑命令归为 mutating，cursor/selection/scroll/find/go-to 类命令归为 readonly-safe，view 配置与 style/folding/bracket-highlight 命令归为 mutating，符合 T09/T09R 要求；未新增独立命令 enum，未改变既有命令语义。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core --test command_is_mutating`；`cargo test -p editor-core`。
- Full test suite：本次 review 未改动编译输出，T09 完成记录已有 `cargo test --all --all-targets` 绿色结果，未重新运行。

### [TODO] T10 实现：Views（每列一个）+ readonly 命令 + 坐标映射

状态：TODO

依赖：T05/T06/T09。

范围文件：

- `crates/editor-core-diff-view/src/view.rs`
- `crates/editor-core-diff-view/src/projection.rs`（如需补 per-side↔unified 映射）
- `crates/editor-core-diff-view/tests/view.rs`，新增

已知入口：

- `DiffProjection` / `Row` / `RowSlot`（T05/T06）
- `editor_core::commands::{EditorCore, CommandExecutor}`
- `editor_core::model::Command::is_mutating`（T09）
- `RowSlot::Spacer`（坐标映射跳过）

实现要求：

1. 实现 `DiffColumnView`：是 `rows[*].slots[i]`（该列）的薄投影，把每个 slot 翻译成 cells / style / line-mark；`Spacer` 产出空行。
2. 每个 view 背后挂一个 **readonly** `EditorCore`/`CommandExecutor`（该侧文档）；view 暴露与普通编辑器一致的命令接口，但用 `Command::is_mutating()` **拒绝** mutating 命令（含折叠），允许 cursor 移动/selection/scroll/find/go-to。
3. 实现 §6 的两套坐标：命令作用于**各侧文档真实坐标**（直接复用 editor 导航逻辑），渲染/滚动用 **unified row 轴**；projection 提供双向 **per-side visual row ↔ unified row** 映射。
4. 验证副作用：cursor 自然跳过 spacer（spacer 不属任何侧真实行序列）。
5. view 只提供数据；不管理 scrolling、layout、splitter。

测试要求：

1. mutating 命令（insert/delete/replace/undo/redo/折叠）被拒绝；navigation 命令在 readonly editor 上正常执行。
2. per-side visual row ↔ unified row 双向映射往返一致（含含 spacer 的列）。
3. "向下移动一行"在 spacer 处自动跳过，cursor 不落在 filler 行。
4. side-by-side 下两列各自的 view 投影与统一 row 轴一致。
5. 运行 `cargo test -p editor-core-diff-view --test view`。

验收标准：

- view 为只读、命令分类正确、坐标映射往返一致、cursor 跳过 spacer。
- view 不含 scrolling/layout/splitter 逻辑。

完成记录：

- 待填写。

### [TODO] T10R Review：审查 Views 与坐标映射

状态：TODO

审查范围：T10 的所有 diff。

审查重点：

1. mutating 命令（含折叠）是否被严格拒绝，navigation 子集是否完整可用。
2. per-side↔unified 双向映射是否往返一致，spacer 处是否正确跳过。
3. view 是否确实只读、只提供数据，无 scrolling/layout/splitter。
4. 是否复用了 editor 既有导航逻辑而非重写。
5. 含 spacer、wrap、CJK/emoji 的组合是否有测试覆盖。

建议命令：

- `cargo test -p editor-core-diff-view --test view`
- `cargo test -p editor-core-diff-view`

完成记录：

- 待填写。

## 推迟到后续版本（不在本 TODO）

以下来自 `PLAN.md` §8，v1 不实现，不要在上述任务中提前引入：

- Folding（含同步折叠）。
- 行内 / word-char diff 及其高亮样式。
- 宽度变更的增量 wrap/alignment 重算。
- ThreeWay（三向合并，columns==3）。
- 把 gutter line mark 提取为 `editor-core` 通用能力。
- `Replace` 块内逐行最优配对。
