# 当前执行计划

## 范围

- 仅处理 `TODO.md` 中第一个标题未带 `[DONE]` 的任务。
- 不做开放式历史问题排查；只有阻塞当前任务、破坏当前任务指定行为，或由当前任务直接引入的问题才纳入本次范围。
- 如遇无法按规格完成的具体阻塞项，先把最小必要前置任务写入 `TODO.md` 并提交，然后停止。

## 步骤

1. 阅读 `TODO.md`，确认第一个未完成任务及其依赖、验证要求、完成记录格式。
2. 检查最新提交信息；如果其明确提到与当前任务直接相关的未完成问题，将其纳入当前任务或作为前置任务记录到 `TODO.md`。
3. 阅读当前任务涉及的代码、测试和文档，只收集完成该任务所需的上下文。
4. 按任务要求做最小正确实现；编辑前后持续更新本文件，记录关键进度和计划变化。
5. 运行相关的格式化、lint 和测试；按要求先 `cargo fmt`，再 `cargo clippy --all-targets -- -D warnings`，最后运行必要的测试套件。
6. 若发现未计划的测试或 fixture 失败，修复它，或在 `TODO.md` 中加入最小必要前置/后续任务，且不把当前任务标记为完成。
7. 完成后在 `TODO.md` 的任务标题前加 `[DONE]`，更新完成记录；仅当阶段计划本身变化时才更新 `PLAN.md`。
8. 检查工作区状态与 diff，提交本次任务涉及的所有未提交文件，提交信息包含任务编号和清晰说明。
9. 提交后停止，不继续下一个任务。

## 当前状态

- 已读取 `TODO.md`。
- 第一个未完成任务：`T07 实现：废弃并移出主路径的 PieceTable`。
- T07 范围文件：`crates/editor-core/src/storage.rs`、`crates/editor-core/src/commands.rs`、`crates/editor-core/src/lib.rs`、`crates/editor-core/tests/text_buffer_single_source.rs`、`crates/editor-core/tests/undo_redo.rs`、`crates/editor-core/tests/line_ops.rs`。
- T07 验证要求：`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core`，并按全局要求先运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`。
- 最新提交：`d58e7c0 [T06R] Review layout text cache removal`，未发现与 T07 直接相关的未完成问题。
- 发现必要额外范围：`crates/editor-core/src/workspace.rs` 仍通过公开 `EditorCore.piece_table` 读取 buffer 字符数和 range；TUI、示例、集成测试和 `state.rs` 文档示例也有直接字段访问。已把原因写入 `TODO.md` 的 T07 执行备注。
- 已开始代码迁移：`EditorCore.piece_table` 已改为 debug-only 私有 `piece_table_shadow`，并新增 `EditorCore::text_range`；多数命令读路径已批量改为 `TextBuffer`/`LineIndex`。
- 已清除主路径中的 `self.editor.piece_table.*` 读写；`PieceTable` 现仅用于 debug shadow、兼容 re-export/模块和旧验证测试。
- 已迁移 `workspace.rs`、TUI 复制逻辑、state 文档示例、state example、integration test 的直接字段访问。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test text_buffer_single_source`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core`、`cargo test --all --all-targets`、`cargo test -p editor-core --doc`。
- 未找到 `tools/run_fixtures.py` 或其它 `tools/**/*fixture*` fixture runner，因此无可运行的完整 fixture suite。
- 下一步：更新 `TODO.md` 的 T07 标题和完成记录，检查 diff/status 后提交。
