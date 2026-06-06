# 执行计划

说明：本文件记录可审计的执行计划和进度，不包含私有推理链。

## 当前步骤

1. 读取 `TODO.md`，按顺序识别第一个标题未带 `[DONE]` 的任务。
2. 检查该任务的正文、依赖、验证要求和完成记录；必要时查看最新提交是否直接提到与该任务相关的未完成问题。
3. 在不进行开放式历史问题扫查的前提下，读取与当前任务直接相关的代码和测试。
4. 实施当前任务；如发现阻塞当前任务的具体缺口，则在 `TODO.md` 中加入最小必要前置任务并停止。
5. 按要求运行格式化、lint、相关测试；如有未排期失败，修复或排入 `TODO.md`。
6. 更新 `TODO.md`：完成时在任务标题前加 `[DONE]` 并填写完成记录；仅在阶段计划改变时更新 `PLAN.md`。
7. 检查 git 状态和 diff，提交本次任务相关变更。
8. 完成一个任务后停止，不继续下一个任务。

## 进度记录

- 初始化：已创建本执行计划。
- 已识别首个未完成任务：`T01R Review：审查 crate 骨架`。
- 已检查最新提交 `64ad58c [T01] Add editor-core-diff-view crate skeleton`，未发现提交信息中直接提到与 T01R 相关的未完成问题。
- 已检查 T01 范围文件：workspace 成员、crate 依赖、模块占位、re-export 与 smoke test 均限定在骨架范围内；当前无审查发现。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo build -p editor-core-diff-view`、`cargo test -p editor-core-diff-view`。
- 已将 `TODO.md` 中 `T01R Review：审查 crate 骨架` 标记为 `[DONE]`，完成记录写明无审查发现及验证命令；full test 因本次未改代码而复用 T01 已记录的绿色结果。
- 已提交 T01R review 文档变更：`a3e0c72 [T01R] Review diff-view crate skeleton`。
- 当前任务完成，停止，不进入 T02。
