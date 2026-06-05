# 执行计划

## 范围

- 本次调用只处理 `TODO.md` 中第一个标题未以 `[DONE]` 标记的任务。
- `TODO.md` 是任务排序、依赖、验收和完成记录的权威来源。
- `PLAN.md` 仅在阶段级计划、依赖或完成标准变化时更新。

## 初始步骤

1. 读取 `TODO.md`，按文档顺序识别第一个未完成任务。
2. 检查最近提交是否明确提到与该任务直接相关的未完成事项；若相关，将其纳入当前任务或作为前置任务记录到 `TODO.md`。
3. 读取当前任务涉及的源码、测试和文档，确认实现边界与验证要求。

## 执行步骤

1. 按当前任务要求实现最小且完整的修复或功能。
2. 若发现阻塞当前任务的规范不匹配、缺失能力或失败测试，优先修复；如无法在当前任务内正确完成，则在 `TODO.md` 添加最小前置任务并停止。
3. 更新或新增聚焦的回归测试，避免用 fixture-only hack 或范围收窄绕过真实问题。
4. 运行格式化、lint、目标测试，并按需要运行完整测试；若仅文档变更且已有可复用的绿色结果，则记录跳过原因。
5. 在 `TODO.md` 将当前任务标题加上 `[DONE]`，并填写完成记录、验证命令和结果。
6. 更新本文件记录关键进展。
7. 检查 git 状态和差异，提交本次任务相关的所有未提交更改。
8. 停止，不继续处理下一个任务。

## 当前状态

- 已创建执行计划。
- 已读取 `TODO.md`，第一个未完成任务是 `T09R Review：审查行级命令性能优化`。
- 本任务是 review 任务：只审查 T09 相关 diff，不主动重构；若发现明确缺陷、测试缺口或质量问题，再按最小范围修复或登记后续任务。
- 已检查最近提交：`a470582` 为 T09 实现提交，`a26aa94` 仅更新计划记录；未发现最新提交中直接声明的 T09 阻塞事项。
- 已审查 T09 代码改动：`slice_text_for_lines` 改为 char range 读取，duplicate-lines 末尾换行判断改为读取最后一个 char；剩余 `EditorCore::get_text()` 调用不在普通行级编辑路径。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core`。
- 已更新 `TODO.md`：将 T09R 标记为 `[DONE]` 并填写完成记录。
- 下一步：检查 diff 和 git 状态，提交 T09R review 变更。

## T09R 审查计划

1. 检查最近提交，确认 T09 相关改动范围以及是否存在直接相关的未完成事项。
2. 审查 `crates/editor-core/src/commands.rs`、`crates/editor-core/src/search.rs`、`crates/editor-core/tests/line_ops.rs`、`crates/editor-core/tests/comment_toggle.rs`、`crates/editor-core/tests/workspace_search_apply.rs` 中与 T09 相关的改动。
3. 重点确认行级命令不再读取全文 `get_text()`、末尾换行行为保持、多光标 selection 映射未退化、undo 删除范围准确、搜索全文读取路径与行编辑路径隔离。
4. 运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core`。
5. 若无问题，更新 `TODO.md` 将 T09R 标记为 `[DONE]` 并填写完成记录。
6. 检查 git 状态和 diff，提交本次 review 记录及相关变更后停止。
