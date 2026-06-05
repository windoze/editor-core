执行计划

1. 读取 `TODO.md`，按文档顺序确认第一个标题未带 `[DONE]` 的任务，并检查该任务的依赖、验证要求和完成记录。
2. 查看最近提交信息，仅在其明确提到与当前任务直接相关的未完成问题时，将其纳入当前任务或作为前置项记录到 `TODO.md`。
3. 根据当前任务定位相关代码、测试和文档，先理解现有实现边界，避免假设或绕过规范要求。
4. 若发现当前任务被具体缺陷、缺失功能或失败测试阻塞，则优先修复；如无法在本次正确完成，则在 `TODO.md` 插入最小必要前置任务并停止。
5. 以小而聚焦的补丁实现当前任务，不修改无关文件，不回退已有用户改动。
6. 运行必要的格式化、lint 和测试；先运行有针对性的验证，再按任务要求运行更完整验证。
7. 若验证暴露未被安排的失败测试或 fixture，立即修复或在 `TODO.md` 明确排入当前任务之前的前置项。
8. 完成后在 `TODO.md` 将当前任务标题加 `[DONE]`，更新完成记录；仅在阶段级计划变化时更新 `PLAN.md`。
9. 检查 git 状态和差异，提交本次任务相关全部改动，提交信息包含任务编号和简要说明。
10. 提交后停止，不推进下一个任务。

进度记录

- 已建立本次执行计划；下一步读取 `TODO.md` 确认首个未完成任务。
- 已读取 `TODO.md`，确认首个未完成任务为 `T17 实现：Undo coalescing 粒度修正`；`T17R` 及后续任务暂不执行。
- 下一步检查最新提交是否明确提到与 T17 直接相关的未完成问题，然后读取 T17 范围内的 undo/edit 实现与测试。
- 最新提交为 `[T16FR] Review FFI ABI conversion fix`，未发现直接指向 T17 的未完成问题。
- 工作区已有未跟踪 `notification.sh`、`run_agent.sh`，与 T17 无关，本次不会修改。
- T17 实现方案：在 `UndoRedoManager` 的 open group 中保存 group id、最后一次插入摘要、selection 快照、编辑种类和时间戳；`push_step` 仅在纯插入、无换行、selection 连续、每个插入位置相邻且未超过 timeout 时复用 group，否则开启新 group 或结束 group。
- 为稳定测试 timeout 行为，将提供受控 timeout 配置；集成测试用零 timeout 验证不会合并，避免真实 sleep。
- 已修改 undo coalescing 状态、公开 timeout 配置入口和相关文档注释，并新增 `crates/editor-core/tests/undo_coalescing.rs` 覆盖连续插入、零 timeout、显式结束、非相邻插入、光标移动、换行和多光标连续输入。
- 下一步执行 `cargo fmt`，然后按要求运行 clippy 与 T17 相关测试。
- `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、T17 定向测试和 `cargo test -p editor-core` 已通过。
- `cargo test --all --all-targets` 失败于 `editor-core-ui/tests/ime_undo_grouping_tests.rs` 的 4 个 IME undo grouping 测试；这是 T17 对 replacement coalescing 收紧后直接触发的相关回归，接下来需修复 IME 显式 coalescing 语义，同时保持普通 typing 的严格合并边界。
- 已将 undo coalescing 分为普通插入模式与显式 composition/replacement 模式：普通 typing 仍要求纯插入、无换行、selection 连续、相邻且未超时；`ReplaceCoalescingUndo*` 仅在显式模式下合并，并要求下一次替换正好覆盖上一次插入的 composition 范围，避免与普通 typing 混合。
- 修复后验证通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test undo_coalescing`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test undo_tree`、`cargo test -p editor-core-ui --test ime_undo_grouping_tests`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 已检查 fixture runner：未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`。
- 已将 `TODO.md` 中 T17 标记为 `[DONE]` 并补充完成记录；下一步检查 diff/status 并提交本任务改动。
