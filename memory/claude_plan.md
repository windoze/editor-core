# 当前执行计划

## 约束理解
- `TODO.md` 是任务顺序和完成状态的唯一权威来源。
- 本轮只完成第一个标题未带 `[DONE]` 的任务，完成后提交并停止。
- 若遇到阻塞当前任务的规格缺口、测试失败或缺失前置条件，优先修复；如果不能在本轮完成，则把最小必要前置任务加入 `TODO.md`，提交后停止。
- `PLAN.md` 只在阶段级计划、依赖或完成标准变化时更新。
- 所有代码变更后按要求运行格式化、lint、测试；若仅文档变更且可复用已有绿色结果，则记录跳过原因。

## 执行步骤
1. 读取 `TODO.md`，按文档顺序定位第一个标题未带 `[DONE]` 的任务，并检查该任务的依赖、验证要求和完成记录。
2. 查看最新提交信息；仅当其明确提到与当前任务直接相关的未完成问题时，将其纳入当前任务或作为前置任务记录。
3. 按当前任务要求读取最小必要上下文，包括相关源码、测试、设计文档或已有实现。
4. 若任务可直接完成，实施最小正确变更；若发现具体阻塞，更新 `TODO.md` 记录前置任务并停止后续实现。
5. 为变更补充或调整聚焦测试，避免绕开规格缺口或夹具问题。
6. 运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`，再运行当前任务要求的相关测试；如需要且时间允许，运行完整验证。
7. 更新 `TODO.md`：完成时在任务标题前加 `[DONE]` 并填写完成记录；阻塞时保持原任务未完成并记录阻塞或新增前置任务。
8. 根据实际进度更新本计划文件。
9. 检查 `git status`、`git diff` 和最近提交，提交本轮所有应提交变更，提交信息包含任务标识和清晰描述。
10. 停止，不处理下一个任务。

## 当前状态
- 已定位首个未完成任务：`T04 实现：file + patch 数据源归约到 DiffModel`。
- 最近提交为 `T03R` review，未显式提到与 T04 直接相关的未完成问题。
- 工作区已有未跟踪文件 `notification.sh`、`run_agent.sh`，看起来与当前任务无关，本轮不会修改或提交它们。
- 已在 `model.rs` 中新增 unified diff patch 解析/应用路径，直接由 hunk 记录重建 after 侧与 alignment，未对全文重新运行 diff。
- 已新增 `tests/model_patch.rs`，覆盖 before+after 等价、小 context 补齐、空 patch、无末尾换行 marker、CRLF patch 行结束符和畸形 patch 错误。
- 已收紧 patch preamble 解析：空 patch 允许，常见 unified diff 元数据允许，其他非 diff 文本返回明确错误。
- 验证已通过：`cargo fmt`；`cargo test -p editor-core-diff-view --test model_patch`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- Fixture suite：仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。
- 已更新 `TODO.md` 标记 T04 完成并填写完成记录。
- 下一步检查最终差异并提交本轮相关文件；未跟踪的 `notification.sh`、`run_agent.sh` 继续保持不动。
