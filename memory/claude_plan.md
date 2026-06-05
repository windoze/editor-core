# 执行计划

> 说明：本文件记录可审计的执行计划与进度，不包含隐藏推理细节。

## 当前计划

1. 当前第一个未完成任务为 `T14 实现：收紧公开 API 和 EditorCore 字段`；本轮只完成 T14，不进入 T14R 或后续任务。
2. 在开始实现前检查最近提交，确认是否有直接阻塞 T14 的未完成事项；如有，按 `TODO.md` 规则添加最小前置任务并停止。
3. 只阅读 T14 范围文件及必要调用点，重点确认 `EditorCore` 公共字段、内部模块可见性、workspace/FFI/TUI 的直接字段访问。
4. 以最小破坏方式收紧最危险的公开面：文本存储、layout、folding/style 派生状态字段改为私有或受控访问；保留必要 facade re-export，并为外部迁移提供说明。
5. 更新 workspace、FFI、TUI 及测试中对已私有字段的访问，改用 getter 或受控 mutation API，避免绕过同步不变量。
6. 按要求运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-ffi`、`cargo test -p tui-editor` 或 `cargo check -p tui-editor`；若发现未排期失败，修复或更新 `TODO.md`。
7. 任务完成后把 `TODO.md` 的 T14 标题标记为 `[DONE]` 并写入完成记录；仅当阶段级计划变化时才更新 `PLAN.md`。
8. 检查 git 状态、差异和最近提交，提交本次任务相关全部改动，然后停止。

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
- 已识别本轮第一个未完成任务：`T14 实现：收紧公开 API 和 EditorCore 字段`。
- 本轮执行计划已更新：先检查最近提交和 T14 范围调用点，再实施最小 API 收紧、验证、更新 `TODO.md`、提交并停止。
- 最近提交为 `53e2a3a [T13R] Review commands module split`，未发现直接阻塞 T14 的未完成事项。
- 当前工作区存在未跟踪 `notification.sh`、`run_agent.sh`，与 T14 无关，本轮不触碰。
- 已将 `EditorCore` 的文本、layout、style、diagnostics、decorations、symbols、folding、cursor/selection、viewport 字段改为私有，并补充只读 getter 与受控 mutation API。
- 已把 `state`、`workspace`、TUI、FFI、LSP/Sublime/highlight-simple 调用点、示例和相关测试中的直接字段访问迁移到 getter 或受控 API；下一步格式化并运行编译检查以捕捉遗漏。
- 已将不需要对外开放的 `EditorCore` mutation helper 收紧为 `pub(crate)`；TUI 折叠操作改走 `EditorStateManager` 的受控 API，并通过 `cargo check -p editor-core-lsp -p editor-core-ffi -p tui-editor`。
- 已进一步将 `intervals` / `layout` 模块路径收紧为 crate 内部模块，并通过根级 re-export 暴露必要 facade；`line_index` 与 deprecated `storage` 路径保留给后续 T15/兼容清理。
- 模块可见性调整后已重新格式化并通过 `cargo check -p editor-core-lsp -p editor-core-ffi -p tui-editor`；下一步重新运行 clippy 与测试矩阵。
- 验证已通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-ffi`、`cargo test -p tui-editor`、`cargo test --all --all-targets`。
- 已确认不存在 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner，因此无可运行完整 fixture suite。
- 已将 `TODO.md` 中 T14 标记为 `[DONE]` 并写入完成记录；下一步检查 git diff/status/log，提交本轮相关改动后停止。
