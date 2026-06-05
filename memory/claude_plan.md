执行计划记录

当前状态：已读取 TODO.md，确认第一个未完成任务为 T10R「审查列字节转换优化」。这是 review 任务，不主动重构；仅在发现明确 bug、测试缺口或质量问题时才修改代码或添加后续任务。

计划：
1. 检查最新提交记录，确认是否有与 T10R 直接相关的未完成事项需要纳入本 review。
2. 审查 T10 范围 diff 和相关文件：`crates/editor-core/src/commands.rs`、`crates/editor-core/tests/comment_toggle.rs`、`crates/editor-core/tests/unicode_segmentation.rs`。
3. 聚焦 T10R 审查点：char column 与 byte offset 是否混用；CJK/emoji/tab 前后注释插入/删除位置是否正确；tab 缩进是否仍按字符列处理；旧 helper 是否仍处于 O(n^2) 热路径；测试是否覆盖非 ASCII 缩进和 token 后空格删除。
4. 按任务建议运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test unicode_segmentation`；若发现未调度的失败，修复或在 TODO.md 中按顺序新增最小前置任务。
5. 若 review 未发现阻塞问题，更新 TODO.md：给 T10R 标题加 `[DONE]`，填写完成记录；PLAN.md 仅在阶段计划变化时更新。
6. 检查 git status、diff 和近期提交，提交本次 T10R review 变更，然后停止，不进入 T11。

进度日志：
- 已创建/更新本计划文件。
- 已识别当前任务为 T10R「审查列字节转换优化」。
- 已检查最新提交：`017c827 [T10] Optimize comment column conversion`，未发现与 T10R 直接相关的未完成事项提示。
- 已完成 T10 diff 与相关实现/测试审查，未发现需要立即修改代码或新增前置任务的阻塞问题。
- 已完成验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test unicode_segmentation` 均通过。
- 已更新 TODO.md，将 T10R 标记为 `[DONE]` 并写入完成记录。下一步检查 diff/status 并提交本次 review 变更。
