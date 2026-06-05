## 执行计划

1. 读取 `TODO.md`，按标题是否包含 `[DONE]` 判断第一个未完成任务，并核对任务要求、依赖和验证要求。
2. 检查最近提交和当前工作区状态，只用于判断是否存在与当前任务直接相关的未完成问题或必须一起提交的遗留改动。
3. 根据当前任务阅读最小必要代码与测试，确认实现边界，不做无关历史问题扫查。
4. 完整实现当前任务；如发现阻塞当前任务的缺失功能、规范不匹配或未计划失败测试，则按要求更新 `TODO.md` 加入最小前置任务并停止。
5. 运行格式化、lint、相关测试以及任务要求的验证；若失败，修复或按策略记录为前置任务。
6. 将当前任务标题标记为 `[DONE]`，更新完成记录；仅在阶段级计划变化时更新 `PLAN.md`。
7. 检查 diff，提交本次任务涉及的所有必要改动，然后停止，不继续下一个任务。

## 进度记录

- 已创建初始执行计划，下一步读取 `TODO.md` 确认第一个未完成任务。
- 已确认第一个未完成任务为 `T12 实现：限制 command_history 内存增长`。下一步按任务要求定向检查 `get_command_history` 消费者、最近提交和当前工作区状态。
- 定向检查结果：`get_command_history` 只出现在 `commands.rs`、测试和示例中；最近提交为 T11R，不含 T12 直接阻塞项；工作区未跟踪 `notification.sh`、`run_agent.sh` 非本任务改动，保持不动。
- 实现方案：将 `CommandExecutor` 的历史改为有界环形/队列语义，并在记录历史时把大文本命令转为摘要形式，保持 `get_command_history` 返回 `&[Command]` 的公开 API 形状。
- 已实现：`CommandExecutor` 默认保留最近 1000 条历史，支持 `set_command_history_limit(0)` 禁用；记录历史时对大文本字段做预览截断，避免保存完整大文本副本。新增 `command_history.rs` 覆盖容量裁剪、禁用历史和大 `InsertText` 摘要。
- 下一步运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、T12 指定测试和相关 crate 测试。
- `cargo clippy --all-targets -- -D warnings` 首次发现 `SearchOptions` 是 `Copy`，已将历史摘要构造中的 `clone()` 改为解引用复制；下一步重新格式化和验证。
- 已通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test command_executor_commands`、`cargo test -p editor-core --test command_history`、`cargo test -p editor-core`。
- 下一步运行 `cargo clippy --all-targets --all-features -- -D warnings` 和 `cargo test --all --all-targets`，并检查是否存在 fixture runner。
- 已通过：`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner。
- 下一步更新 `TODO.md`：将 T12 标记为 `[DONE]` 并写入完成记录，然后检查 diff 并提交。
- 已将 T12 在 `TODO.md` 标记为 `[DONE]` 并补充完成记录。下一步检查 `git status` / `git diff` / `git log`，仅提交本任务相关文件。
