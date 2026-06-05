# 当前执行计划

## 目标

- 以 `TODO.md` 为唯一任务来源，完成其中第一个标题未带 `[DONE]` 的任务。
- 完成一个任务后立即停止，不继续处理后续任务。

## 步骤

1. 读取 `TODO.md`，按文件顺序定位第一个未完成任务，并确认其依赖、验证要求和完成记录要求。
2. 检查最近提交信息；若它明确提到与当前任务直接相关的未完成问题，将该问题纳入当前任务或作为前置任务写入 `TODO.md`。
3. 读取当前任务涉及的代码、测试和文档，只做与当前任务直接相关的上下文调查。
4. 如果当前任务可直接完成，实施最小正确修改；如果存在阻塞当前任务的具体前置问题，更新 `TODO.md` 记录该前置任务并停止。
5. 运行要求的格式化、lint、目标测试和必要的完整验证；发现未排期的失败测试或 fixture 时，修复或将最小前置任务加入 `TODO.md`。
6. 将当前任务标题标记为 `[DONE]`，更新 `TODO.md` 的完成记录；仅当阶段级计划变化时才更新 `PLAN.md`。
7. 检查 `git status`、`git diff` 和最近提交，提交本次任务相关的全部变更。
8. 在最终回复中简要说明完成内容、验证结果和提交信息。

## 进度记录

- 已写入初始执行计划，下一步读取 `TODO.md` 定位首个未完成任务。
- 已读取 `TODO.md`，首个未完成任务为 `T09 实现：行级命令避免全文读取`。
- T09 范围限定在 `commands.rs`、`search.rs` 以及 `line_ops`、`comment_toggle`、`workspace_search_apply` 测试；下一步检查最近提交是否有与 T09 直接相关的未完成问题，并读取这些入口实现。
- 最近提交未提到与 T09 直接相关的未完成问题。
- 已定位并修改 T09 主问题：`DuplicateLines` 不再通过 `EditorCore::get_text()` 读取全文判断末尾换行，改为读取最后一个 char；`slice_text_for_lines` 改为按行范围计算 char offset 后用 `text_range` 读取受影响范围。
- 已补充行操作、注释切换和 workspace apply-text-edits 的 Unicode、末尾换行、多光标/空行相关回归测试；下一步运行定向检查和验证。
- 已运行并通过 T09 验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test workspace_search_apply`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 已确认仓库中不存在 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner。
- 已将 `TODO.md` 中 T09 标记为 `[DONE]` 并填写完成记录。
- 已提交 T09 任务变更：`a470582 [T09] Avoid full-text reads in line commands`；下一步停止，不进入 `T09R`。
