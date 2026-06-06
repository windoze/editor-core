# 当前执行计划

## 目标

按 `TODO.md` 的权威顺序完成第一个未标记 `[DONE]` 的任务，完成后更新记录、验证并提交，然后停止。

## 步骤

1. 读取 `TODO.md`，按标题是否带 `[DONE]` 判定第一个未完成任务。
2. 查看该任务的依赖、验收标准、验证要求和完成记录；必要时查看最近提交是否直接提到与该任务相关的未完成问题。
3. 仅围绕当前任务检查相关代码、测试和文档，避免开放式历史问题排查。
4. 如果任务可直接完成，实施最小正确改动并补充或调整聚焦测试。
5. 按要求先运行格式化和 lint，再运行相关测试；如代码变更影响面较大，再运行完整测试套件。
6. 如发现阻塞当前任务的实现缺口或未排期失败，优先修复；若无法在当前任务内正确完成，则在 `TODO.md` 插入最小前置任务并提交后停止。
7. 完成后将当前任务标题前缀改为 `[DONE]`，更新完成记录；仅在阶段级计划变化时更新 `PLAN.md`。
8. 检查 git 状态和差异，提交本次任务相关全部变更，提交后停止。

## 约束

- 不输出隐藏推理过程，只记录可审计计划、决策和进展。
- 不跳到下一个任务，不用 workaround 代替规范实现。
- 不回退或覆盖非本次产生的用户变更。

## 进展

- 已建立初始执行计划，下一步读取 `TODO.md` 确定当前任务。
- 已读取 `TODO.md`，第一个未完成任务是 `T02 实现：固化 AlignUnit 与对齐算法（before + after 来源）`。
- 当前任务范围限定为 `crates/editor-core-diff-view/src/model.rs` 与新增 `crates/editor-core-diff-view/tests/alignment.rs`；下一步检查 `PLAN.md` §2.1、`editor-core-diff` 入口、当前占位实现和最近提交。
- 已实现 `AlignUnit` 的四种单元与 `align_before_after`，算法按 hunk 顺序补齐 hunk 外 context，并把连续非 context diff 行归并为 `Replace` / `Add` / `Remove`。
- 已新增 `alignment` 测试，覆盖无变更、纯增删、块级 replace、多处修改、首尾修改、末尾换行边界和 range 完整覆盖性质。
- 首次 `cargo clippy --all-targets --all-features -- -D warnings` 发现 `push_unit` 中嵌套 `if let` 需折叠；已按 clippy 建议改为 `if let` chain，下一步重新格式化并验证。
- 验证进展：`cargo fmt` 通过；`cargo clippy --all-targets --all-features -- -D warnings` 通过；`cargo test -p editor-core-diff-view --test alignment` 通过；`cargo test -p editor-core-diff-view` 通过；`cargo test --all --all-targets` 通过。
- 仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。下一步更新 `TODO.md` 的 T02 标题和完成记录，然后检查 diff 并提交。
- 已将 `TODO.md` 中 T02 标记为 `[DONE]` 并填写完成记录。下一步执行提交前检查：`git status`、`git diff`、`git log --oneline -10`。
- 已检查并暂存本任务相关文件：`TODO.md`、`model.rs`、`tests/alignment.rs`、`memory/claude_plan.md`；未跟踪的 `notification.sh` 和 `run_agent.sh` 非本任务产物，保持未暂存。下一步提交后停止。
- 本轮已读取 `TODO.md`，第一个未完成任务是 `T02R Review：审查对齐算法`。
- 最近提交为 `[T02] Implement diff-view alignment`，未提到与 T02R 直接相关的未完成问题。
- 已审查 `AlignUnit`、`align_before_after`、hunk 外 context 补齐、块级 `Replace` 归并、纯 `Add`/`Remove` 归类和 `alignment` 测试覆盖；未发现需要修复的问题。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test alignment`；`cargo test -p editor-core-diff-view`。
- 已更新 `TODO.md` 将 T02R 标记为 `[DONE]` 并填写 review 完成记录；`PLAN.md` 无阶段级变更，不更新。下一步提交本轮 review 记录。
