本文件记录本次任务的可审计执行计划、关键决策和进度检查点。不会记录隐藏推理链。

## 当前执行计划

1. 已读取 `TODO.md`，按标题是否带 `[DONE]` 识别第一个未完成任务，不做开放式历史问题排查。
2. 当前任务为 `T21UR Review：审查 editor-core-ui panic 专项`；这是 review 任务，不主动重构，只审查 T21U diff、验证是否有明确缺陷或测试缺口。
3. 先检查最近提交和工作区状态，确认是否有与 T21UR 直接相关的未完成事项或未提交变更需要纳入本次 review。
4. 定向查看 T21U 涉及文件：`crates/editor-core-ui/src/lib.rs`、`crates/editor-core-ui/src/keybindings.rs` 以及相关测试，重点核对可恢复 UI/host 错误是否转为明确错误通道、processor 状态错误是否未被吞掉、剩余 panic/unwrap/expect 是否分类清楚、是否未混入 app/core 无关修改。
5. 运行任务建议验证，按要求先 `cargo fmt`，再 `cargo clippy --all-targets -- -D warnings`，再运行 `cargo test -p editor-core-ui`；若发现未调度失败测试，必须修复或在 `TODO.md` 中新增最小前置任务。
6. 若 review 未发现阻塞问题，将 `T21UR` 标题加 `[DONE]`、状态改为 DONE，并补充完成记录和验证结果；不更新 `PLAN.md`，除非发现阶段级计划变化。
7. 提交本次 review 相关变更，提交信息使用 `T21UR` 前缀；完成后停止，不进入 `T21A`。

## 进度

- 已确认第一个未完成任务为 `T21UR Review：审查 editor-core-ui panic 专项`。
- 已检查最近提交与工作区状态：`HEAD` 为 `[T21U] Harden editor-core-ui panic handling`，当前仅 `memory/claude_plan.md` 为本次修改；另有 `notification.sh`、`run_agent.sh` 未跟踪且与本任务无关，不修改、不提交。
- 已开始定向审查 T21U 的 UI panic/error-handling 改动和测试覆盖。
- 定向审查发现后续修复项：`poll_lsp_best_effort` 中 LSP-derived `apply_processing_edits` 错误被忽略，且部分路径会继续报告 `applied = true`；同时 T21U 对 `poll_processing` Tree-sitter worker-missing 错误路径缺少直接回归覆盖。计划在 `T21A` 前新增最小 `T21UF` / `T21UFR`，本次 review 不直接重构实现。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ui`。
- 已更新 `TODO.md`：`T21UR` 标题已加 `[DONE]`，状态改为 DONE，并记录审查结论；已在 `T21A` 前新增 `T21UF` / `T21UFR`，并将 `T21A` 依赖改为 `T21UFR`。
- 下一步检查 diff/status 后提交本次 review 变更。
