执行计划

1. 读取 `TODO.md`，只根据任务标题是否带有 `[DONE]` 判断完成状态，定位第一个未完成任务。
2. 查看该任务的依赖、验证要求和完成记录；必要时查看 `PLAN.md`、最近提交和相关源码，但不做开放式历史问题扫查。
3. 若任务存在必须先修复的具体阻塞项，则把最小必要前置任务写入 `TODO.md`，提交后停止；否则直接实现当前任务。
4. 以小而集中的补丁修改代码和测试，避免规避规范或弱化测试形状。
5. 按要求运行格式化、lint、目标测试和必要的完整测试；发现未排期失败时修复或将其排入 `TODO.md`。
6. 更新 `TODO.md`：将完成任务标题加 `[DONE]`，填写完成记录；仅当阶段级计划改变时更新 `PLAN.md`。
7. 检查 `git status`、`git diff`、最近提交，提交本次任务相关的全部变更，然后停止，不继续下一项任务。

进度记录

- 已创建初始执行计划，下一步读取 `TODO.md` 定位首个未完成任务。
- 已定位首个未完成任务：`T17R Review：审查 Undo coalescing 修正`。
- 本次只执行 T17R：审查 T17 diff，重点检查 coalescing 合并条件、时间窗口测试稳定性、多光标 undo 粒度、redo/clean state 和 IME/snippet 行为；随后运行 T17R 指定测试与 lint，最后更新 `TODO.md` 并提交。
- 已完成 T17 diff 初审：未发现明显需要阻塞 T17R 的问题；下一步运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings` 和 T17R 指定测试。
- 已完成验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test undo_coalescing`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test undo_tree`、`cargo test -p editor-core`、`cargo test -p editor-core-ui --test ime_undo_grouping_tests` 均通过。
- 已将 `TODO.md` 中 T17R 标记为 `[DONE]` 并填写完成记录；下一步检查 diff/status 并提交本次 review 记录。
