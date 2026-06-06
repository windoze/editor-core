执行计划（不包含私有推理过程）

1. 读取 TODO.md，按标题是否带有 [DONE] 找出第一个未完成任务，并只处理该任务。
2. 查看最近提交信息，判断是否有明确提到且与当前任务直接相关的未完成事项。
3. 阅读当前任务涉及的计划、源码和测试，确认要求、依赖与验证方式。
4. 以最小正确改动实现当前任务；若发现阻塞当前任务的真实前置问题，则更新 TODO.md 记录前置任务并停止。
5. 为改动添加或更新聚焦测试，执行格式化、clippy、相关测试以及必要的完整验证。
6. 将当前任务标题标记为 [DONE]，更新 TODO.md 完成记录；仅在阶段计划变化时更新 PLAN.md。
7. 检查 git diff/status，提交所有本次任务相关改动，然后停止，不进入下一个任务。

进度记录：已完成 T04R 审查并更新 TODO.md：未发现需要修复或新增前置任务的问题。验证通过 `cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-diff-view --test model_patch`、`cargo test -p editor-core-diff-view`。T04R 完成记录已提交为 `250fef2 [T04R] Review file patch diff model`；本轮停止，不进入 T05。
