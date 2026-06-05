# 执行计划

> 说明：本文件记录可审计的执行计划与进度，不包含隐藏推理细节。

## 当前计划

1. 阅读 `TODO.md`，按文件顺序识别第一个标题未带 `[DONE]` 的任务。
2. 检查最近提交与当前任务是否直接相关；如存在阻塞当前任务的未完成事项，按要求纳入当前任务或在 `TODO.md` 中插入最小前置任务。
3. 阅读当前任务涉及的代码、测试、文档和计划上下文，避免做开放式历史问题扫描。
4. 完整实现第一个未完成任务，保持改动聚焦且不绕过规格要求。
5. 运行格式化、lint、相关测试以及必要的完整验证；发现未排期失败时，修复或在 `TODO.md` 中添加正确顺序的前置/后续任务。
6. 更新 `TODO.md`：仅在任务完成后给任务标题加 `[DONE]`，并填写完成记录；仅当阶段级计划变化时更新 `PLAN.md`。
7. 检查 git 状态、差异和最近提交，提交本次任务相关全部改动。
8. 完成一个任务后停止，不继续处理下一个任务。

## 进度记录

- 已写入初始执行计划，下一步读取 `TODO.md` 并识别第一个未完成任务。
- 已识别第一个未完成任务：`T13 实现：纯移动拆分 commands.rs`。
- 最近提交为 `T12R` 审查完成记录，未发现直接阻塞 T13 的未完成事项。
- T13 专项执行计划：先检查工作区状态和 `commands.rs` 当前结构；随后按纯移动原则拆出模型、undo、编辑、行操作、光标和渲染相关模块；每完成一个模块移动后运行 `cargo test -p editor-core`；最后运行 T13 指定的 `editor-core`、`editor-core-lsp`、`editor-core-ffi` 验证，以及格式化和 lint；完成后更新 `TODO.md` 并提交。
- 已完成 `model.rs` 纯移动切片：公开命令/坐标/配置模型已移出 `commands.rs` 并通过 `commands` 模块重新导出；`cargo test -p editor-core` 已通过。
- 已完成 `undo.rs` 纯移动切片：undo tree、内部 undo edit/step 和持久化快照类型已移出 `commands.rs`，公开快照类型继续通过 `commands` 重新导出；`cargo test -p editor-core` 已通过。
- 已完成 `render_grid.rs` 纯移动切片：styled viewport、minimap 和 composed viewport 快照方法已移出 `commands.rs`；`cargo test -p editor-core` 已通过。
- 已完成 `cursor_ops.rs` 纯移动切片：词边界配置/辅助函数、选择扩展、多光标查找与 cursor dispatch 已移出 `commands.rs`；`cargo test -p editor-core` 已通过。
- 已完成 `line_ops.rs` 纯移动切片：行块选择、Duplicate/Delete/Move/Join 和 ToggleComment 相关实现已移出 `commands.rs`；`cargo test -p editor-core` 已通过。
- 已补齐 `line_ops.rs`：将 `ToggleComment` 的 line/block 具体 helper 也移入该模块；`cargo test -p editor-core` 已通过。
- 已完成 `edit_ops.rs` 纯移动切片：undo/redo、插入/删除/替换、snippet、查找替换、批量 text ops 和低层文本变更同步 helper 已移出 `commands.rs`；`cargo test -p editor-core` 已通过。
- 已完成最终验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-lsp`、`cargo test -p editor-core-ffi`、`cargo test --all --all-targets` 均通过；未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner。
- 已将 `TODO.md` 中 T13 标记为 `[DONE]` 并写入完成记录；下一步提交本次任务相关改动后停止。
- 已识别本轮第一个未完成任务：`T13R Review：审查 commands.rs 纯移动拆分`。
- T13R 执行范围限定为审查 T13 diff、运行建议验证命令、更新 `TODO.md` 完成记录并提交；不进入 `T14`。
- 已完成 T13 静态审查：未发现混入业务逻辑改动、公开 re-export 缺失、过度 public 模块或跨 crate 引用破坏。
- 已运行并通过 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-lsp`、`cargo test -p editor-core-ffi`。
- 已将 `T13R` 在 `TODO.md` 中标记为 `[DONE]` 并写入完成记录。下一步提交本轮改动后停止。
