执行计划记录

当前状态：已读取 TODO.md，确认第一个未完成任务为 T10「优化列到字节转换」。最新提交 `d3aba06 [T09R] Record completion plan` 未明确提到与 T10 直接相关的未完成问题。

计划：
1. 检查 T10 范围文件：`commands.rs`、`comment_toggle.rs`、`unicode_segmentation.rs`，定位 `byte_offset_for_char_column`、`char_column_for_byte_offset` 与 ToggleComment indent 计算路径。
2. 将 ToggleComment 的缩进扫描改为单次 `char_indices` 同时得到字符列与字节偏移；若同一行仍有多次 char->byte 转换，添加局部批量转换或缓存，保持 public char column 语义不变。
3. 补充或调整测试，覆盖 CJK、emoji、tab、空白缩进，以及长行多选区 toggle comment 的性能/退化回归。
4. 按顺序运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test unicode_segmentation`、`cargo test -p editor-core`；若代码变更后需要全量验证，再运行 `cargo clippy --all-targets --all-features -- -D warnings` 和 `cargo test --all --all-targets`。
5. 验证通过后更新 TODO.md：给 T10 标题加 `[DONE]` 并写入完成记录；PLAN.md 仅在阶段计划变化时更新。
6. 检查 git 状态、diff 和近期提交，提交本次 T10 相关变更，然后停止，不进入 T10R。

进度日志：
- 已创建本计划文件。
- 已识别当前任务为 T10「优化列到字节转换」。
- 已完成核心代码初改：新增单次扫描缩进 helper，并让 line comment toggle 复用每行缩进扫描结果，避免重复 char 列到 byte offset 扫描。
- 已补充 `comment_toggle` 覆盖：CJK/emoji/tab/空白缩进，以及长行多选区 toggle comment 性能回归。
- 已完成验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test unicode_segmentation`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets` 均通过；未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`。
- 已更新 TODO.md，将 T10 标记为 `[DONE]` 并写入完成记录。下一步检查 diff/status 并提交本次 T10 变更。
