## 执行计划

1. 读取 `TODO.md`，严格按标题是否带 `[DONE]` 判定第一个未完成任务。
2. 检查最新提交是否明确提到与该任务直接相关的未完成问题；如有，将其纳入当前任务或作为前置任务记录到 `TODO.md`。
3. 只围绕第一个未完成任务收集必要上下文，避免开放式历史问题排查。
4. 按任务要求实现最小且完整的代码、测试或文档变更；如果发现阻塞当前任务的真实缺陷或缺失能力，优先修复，或在 `TODO.md` 中插入最小前置任务后停止。
5. 运行要求的格式化、lint、目标测试和必要的完整验证；任何未排期的失败测试或 fixture 都必须修复或加入 `TODO.md` 的正确位置。
6. 完成后更新 `TODO.md`：在任务标题前加 `[DONE]`，并填写 completion record；仅在阶段计划实际变化时更新 `PLAN.md`。
7. 检查 git 状态和差异，提交本次任务相关的所有改动，然后停止，不继续下一个任务。

## 当前进度

- 已读取 `TODO.md`，确认第一个未完成任务为 `T08F 修复：补齐视觉行索引换行与折叠同步`。
- 已检查最近提交；最新提交为 `[T08R] Record completion plan`，未发现额外未记录的直接相关未完成事项。
- 已读取 T08F 相关入口，确认主要修改点：统一文本变更路径中的 folding line-delta、`VisualRowIndex` 批量行结构更新、TUI 直接 fold/unfold 后缓存失效、core/UI composed viewport 尾部起点优化，以及 `visual_row_index` 回归测试。
- 已完成实现：文本变更路径统一 folding line-delta，`VisualRowIndex` 支持批量结构更新，TUI 直接 fold/unfold 会失效缓存，core/UI composed viewport 起点避免从文档头扫描，并补充专项回归测试。
- 已完成验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test visual_row_index`、`cargo test -p editor-core --test visual_row_improvements`、`cargo test -p editor-core`、`cargo test --all --all-targets` 均通过。
- 已确认未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner。
- 已更新 `TODO.md`，将 `T08F` 标记为 `[DONE]` 并填写完成记录。
- 已检查最终 git status/diff；`notification.sh`、`run_agent.sh` 为未跟踪且非本任务文件，保持不纳入提交。
- 下一步：提交 T08F 改动后停止。
