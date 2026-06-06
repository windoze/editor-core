# Claude Plan

## 当前目标

- 当前第一个未完成任务：`T06R Review：审查 side-by-side 对齐`。
- 只完成该 review 任务；完成后更新 `TODO.md`、验证、提交，并停止。

## 执行计划

1. 查看最近提交信息，判断是否存在与 T06R 直接相关的未完成问题；只在其阻塞 review 时纳入处理或写入 `TODO.md` 前置任务。
2. 审查 T06 范围文件：`crates/editor-core-diff-view/src/projection.rs` 与 `crates/editor-core-diff-view/tests/projection_side_by_side.rs`。
3. 重点核对每个 `AlignUnit` 内 max 对齐、spacer 末尾补齐、不同列宽对齐、`Spacer.change` 语义、unified 路径未回退、未提前实现增量重算。
4. 如发现明确 bug、测试缺口或质量问题，先修复并补测试；如果存在无法在 review 内正确处理的阻塞问题，则把最小前置任务插入 `TODO.md`，提交后停止。
5. 按任务建议和通用清单运行验证：`cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-diff-view --test projection_side_by_side`、`cargo test -p editor-core-diff-view`。若无编译输出变化，可复用 T06 的全量绿色结果并记录原因。
6. 更新 `TODO.md`：将 T06R 标题标记为 `[DONE]`，补充完成记录和验证结果；除非阶段计划变化，不更新 `PLAN.md`。
7. 检查工作区差异，确保仅提交本任务需要的文件且不回退用户变更。
8. 创建清晰的 Git 提交，然后停止。

## 进度记录

- 已读取 `TODO.md`，确认第一个未完成任务为 `T06R Review：审查 side-by-side 对齐`。
- 已查看最近提交，`ba6885b [T06] Implement side-by-side projection` 与当前 review 直接相关；未发现额外未完成提交说明。
- 已审查 `projection.rs` 与 `projection_side_by_side.rs`：未发现 side-by-side 对齐、spacer 语义、unified 路径或增量重算方面的问题。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test projection_side_by_side`；`cargo test -p editor-core-diff-view`。
- 已更新 `TODO.md`，将 T06R 标记为 `[DONE]` 并写入完成记录；未修改 `PLAN.md`，因为阶段计划未变化。
- 下一步检查工作区差异并提交本次任务变更。
