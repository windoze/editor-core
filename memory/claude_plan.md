# 当前执行计划

## 范围

- 仅处理 `TODO.md` 中第一个标题未带 `[DONE]` 的任务。
- `TODO.md` 是任务顺序、依赖、验证要求和完成记录的唯一依据。
- 本次选中的任务是 `T07R Review：审查 PieceTable 废弃迁移`；这是 review 任务，不主动重构，只有发现明确 bug、测试缺口或质量问题才修改代码或新增后续任务。
- 完成该任务后更新 `TODO.md`、提交并停止，不进入 `T08`。

## 步骤

1. 阅读 `TODO.md`，确认第一个未完成任务。
2. 检查最新提交，确认是否有与当前任务直接相关的未完成事项。
3. 定向审查 T07 diff 和当前代码中的 `PieceTable` / `piece_table` 使用点。
4. 核对 review 清单：主路径是否仍调用 `piece_table` 读写、兼容 API 是否标注、undo/redo 文本是否准确、`TextDelta` 字符数是否正确、release 主路径是否减少完整文本副本。
5. 按顺序运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core`。
6. 若出现未计划失败，先修复或在 `TODO.md` 加入最小必要前置/后续任务，不把 T07R 标记完成。
7. 若审查和验证通过，给 T07R 标题加 `[DONE]` 并填写完成记录。
8. 检查 diff/status/log，只提交本次任务相关文件，提交后停止。

## 进度记录

- 已初始化本次可公开执行计划。
- 已确认第一个未完成任务为 `T07R Review：审查 PieceTable 废弃迁移`。
- 最新提交为 `a6bbf6b [T07] Move PieceTable off main edit path`，未见与 T07R 直接相关的未完成事项。
- 已审查 T07 提交摘要和定向 `piece_table` 使用点；当前代码中 `PieceTable` 只出现在 deprecated 兼容模块、测试、deprecated root re-export 和 debug-only `piece_table_shadow`，未发现主编辑路径 `piece_table.insert/delete/get_text/get_range` 调用。
- 审查结论：未发现阻塞问题。deprecated `PieceTable` root re-export 已明确标注，`storage.rs` 说明为兼容层，undo/redo 与 `TextDelta` 计数读取 `EditorCore::char_count`，debug-only shadow 不进入 release 主路径。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core`。
- 已更新 `TODO.md`，将 T07R 标记为 `[DONE]` 并填写完成记录。
