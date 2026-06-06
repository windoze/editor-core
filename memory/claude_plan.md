执行计划（非私有推理记录）

1. 读取 `TODO.md`，按文件顺序定位第一个标题未带 `[DONE]` 的任务，并核对任务正文、依赖、验证要求和完成记录。
2. 检查最近提交是否明确提到与该任务直接相关的未完成事项；只在它阻塞当前任务时纳入当前工作或补充为前置任务。
3. 阅读当前任务涉及的代码、测试和文档，确认最小但完整的实现范围；不做开放式历史问题扫查。
4. 若发现当前任务存在具体阻塞且不能按规格完成，更新 `TODO.md` 添加最小前置任务并停止；否则直接实现当前任务。
5. 按需新增或调整测试，先运行针对性验证，再按要求运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`，最后运行相关完整测试；若只改文档则复用最近绿色结果并记录原因。
6. 更新 `TODO.md`：将完成任务标题加 `[DONE]`，补充完成记录和实际验证命令；仅在阶段计划确实变化时更新 `PLAN.md`。
7. 检查工作区差异，提交本次任务相关全部变更，提交信息包含任务编号和简要说明。
8. 完成一个任务后停止，不继续处理下一项。

进度记录

- 已创建初始执行计划，下一步读取 `TODO.md` 确认首个未完成任务。
- 已读取 `TODO.md`，首个未完成任务为 `T07R Review：审查 diff 样式`。
- 下一步检查最近提交与 T07 涉及文件，重点审查 StyleId 命名段、Add/Remove/Spacer/Context 样式叠加、是否误做行内 diff，以及 `editor-core` 改动是否最小。
- 已检查最近提交 `d86f00b [T07] Implement diff semantic styles` 与 T07 涉及文件；当前未发现需修复问题。
- 下一步按顺序运行 `cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-diff-view --test style`、`cargo test -p editor-core`。
- 已完成验证：`cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-diff-view --test style`、`cargo test -p editor-core`、`cargo test -p editor-core-diff-view` 均通过。
- 已将 `T07R Review：审查 diff 样式` 标记为 `[DONE]` 并补充完成记录。下一步检查 diff 并提交本次审查记录。
