# 当前执行计划

本文件记录本次调用的可执行计划、关键进展和验证结果。计划内容只包含可审计的决策依据和步骤，不包含隐藏推理链。

## 初始计划

1. 读取 `TODO.md`，按文件顺序找到第一个标题未以 `[DONE]` 标记的任务。
2. 检查最新提交信息是否明确提到与该任务直接相关的未完成问题；若存在，将其纳入当前任务或按要求补入 `TODO.md`。
3. 阅读当前任务涉及的代码、测试和文档，确认任务要求、依赖和验证条件。
4. 若任务可直接完成，实施最小正确修改；若发现必须先修复的具体阻塞项，则将最小前置任务写入 `TODO.md` 并停止。
5. 针对修改运行格式化、lint 和相关测试；若发现未计划的失败测试或 fixture，修复或按策略补入任务。
6. 完成后将当前任务标题加上 `[DONE]`，更新 completion record；仅在阶段计划改变时更新 `PLAN.md`。
7. 检查 git 状态与 diff，提交本次任务涉及的全部变更，然后停止，不继续下一个任务。

## 进展记录

- 已创建本次执行计划，下一步读取 `TODO.md` 识别第一个未完成任务。
- 已识别第一个未完成任务为 `T08 实现：视觉行映射索引增量化`。最新提交为 `[T07R] Review PieceTable migration`，未明确提到与 T08 直接相关的未完成问题。
- 当前执行将限制在 T08 范围内：先检查工作区状态，再阅读视觉行索引、布局和折叠相关入口，随后实现增量索引并补测试。
- 已阅读 T08 范围入口。当前 `VisualRowIndex` 位于 `commands.rs`，缓存会在编辑/折叠命令开始时直接失效，下一次 visual 查询会按全量 logical lines 重建。
- 修订实施步骤：新增 `visual_rows.rs`，用每行 visible visual-count + Fenwick tree 支持 `visual->logical` 和 `logical->visual`；编辑路径在 layout 更新后同步受影响行，折叠命令同步对应折叠区间；保留 view option/derived folding wholesale replacement 的全量失效。
- 已完成核心改动草稿：新增 `visual_rows.rs`，`commands.rs` 改用 Fenwick-backed `VisualRowIndex`；删除编辑/折叠命令开始时的无条件缓存失效；编辑路径会按文本变更同步索引结构和受影响行，折叠命令会同步对应折叠区间；新增 `visual_row_index` 集成测试草稿。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test visual_row_improvements`、`cargo test -p editor-core --test visual_row_index`、`cargo test -p editor-core`。
- 已运行并通过：`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 已确认不存在 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner，完整 fixture suite 无可运行入口。
- 已更新 `TODO.md` 的 T08 标题、状态和完成记录，并提交 T08 变更：`6a93fbb [T08] Incremental visual row index`。
- 本次调用到此停止，不继续执行 `T08R`。
执行计划更新：2026-06-05

当前目标：根据 `TODO.md` 的权威顺序，完成第一个标题未带 `[DONE]` 的任务，验证后记录完成状态并提交，然后停止。

约束：
- 不跳过任何未标记 `[DONE]` 的任务，包括 review 任务。
- 不做开放式历史问题扫查；只处理当前任务及其直接阻塞问题。
- 遇到阻塞当前任务的实现缺口或失败测试时，优先修复；若无法在本次完成，则在 `TODO.md` 中加入最小必要前置任务并提交后停止。
- 不修改或回退他人已有改动，除非它们直接冲突且用户明确要求。
- 代码改动后按要求运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、相关测试，必要时再跑完整测试。

步骤：
1. 读取 `TODO.md`，识别第一个标题未带 `[DONE]` 的任务及其验证要求。
2. 检查最近提交和当前工作区状态，确认是否有与该任务直接相关的未完成事项或未提交恢复状态。
3. 阅读当前任务涉及的代码、测试和文档，确定最小正确实现范围。
4. 实现任务；若发现直接阻塞的规范不匹配或缺失能力，先修复或按规则写入 `TODO.md` 为前置任务并停止。
5. 增加或更新聚焦回归测试，并运行格式化、lint、相关测试和必要的完整验证。
6. 更新 `TODO.md`：给已完成任务标题加 `[DONE]`，填写完成记录和验证结果；仅在阶段计划确实变化时更新 `PLAN.md`。
7. 复查 `git diff`、提交本次任务涉及的所有必要文件，提交后停止，不继续下一个任务。

进度：已完成 T08R 静态审查并更新 `TODO.md`。发现 T08 存在需要先修复的后续项：部分真实换行编辑路径没有在视觉行缓存同步前更新 folding line delta，新增测试也缺少多 fold、尾部空行/末尾换行、真实换行命令路径覆盖；TUI 直接 fold/unfold 和 virtual text composed viewport 仍有缓存/线性路径风险。已在 T09 前插入 `T08F` / `T08FR`。验证已通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test visual_row_improvements`、`cargo test -p editor-core --test visual_row_index`、`cargo test -p editor-core`。下一步复查 diff、提交本次 T08R 记录后停止。
