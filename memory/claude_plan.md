# 执行计划

## 当前约束

- `TODO.md` 是任务顺序、依赖、验证要求和完成记录的唯一权威来源。
- 本轮只处理 `TODO.md` 中第一个标题未带 `[DONE]` 的任务，完成后提交并停止。
- 不做开放式历史问题扫描；只处理会阻塞当前任务或验证失败暴露且未被显式排期的问题。
- 若遇到无法按规格完成的缺口，不采用 workaround；在 `TODO.md` 中插入最小必要前置任务，提交后停止。

## 初始步骤

1. 读取 `TODO.md`，确定第一个未完成任务及其验证要求。
2. 查看最近提交摘要，仅判断是否有与该任务直接相关的未完成事项。
3. 读取当前任务涉及的源码、测试和文档，确认最小实现边界。

## 执行步骤

1. 按当前任务要求实现最小正确改动。
2. 添加或更新聚焦回归测试；必要时同步文档或完成记录。
3. 先运行格式化，再运行 clippy，最后运行任务要求的相关测试；若观察到未排期测试/fixture 失败，修复或加入前置任务。
4. 将任务标题更新为 `[DONE] ...`，填写完成记录和验证结果。
5. 检查 git 状态、diff 和最近提交，提交本轮所有相关改动。
6. 停止，不进入下一个任务。

## 进度记录

- 已创建本计划文件；下一步读取 `TODO.md` 识别第一个未完成任务。
- 已读取 `TODO.md`，第一个未完成任务是 `T11 实现：IntervalTree 更新路径降本`。本轮只处理 T11，不进入 `T11R`。
- T11 范围：`intervals.rs`、`commands.rs`、`processing.rs`、`diagnostics.rs`，必要时新增 `interval_tree_updates.rs`；重点是批量编辑时避免每个 edit 对每个 style layer 反复全量更新，同时保持 interval 查询和 `prefix_max_end` 正确。
- 已检查当前更新入口，重复全量更新主要集中在 `commands.rs` 的多光标/批量文本变更循环中。执行方案：在 `intervals.rs` 新增批量 `IntervalTextEdit` 更新入口，按现有“删除后插入、按 pre-edit start 降序应用”的语义一次更新每棵树并重建一次 `prefix_max_end`；命令层改为先收集 interval delta，再对 base tree 和每个 style layer 各调用一次。
- 已实现批量 interval 更新入口，并将命令层文本变更路径改为统一收集 `IntervalTextEdit` 后批量更新 base/style layer trees；新增 `interval_tree_updates` 回归测试。
- 已通过验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test interval_tree_updates`、`cargo test -p editor-core --test diagnostics`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner。
- 下一步更新 `TODO.md` 将 T11 标记为 `[DONE]` 并记录完成内容，然后提交本轮改动。
- 已更新 `TODO.md`：T11 标题已加 `[DONE]`，状态改为 DONE，并记录实现与验证结果。下一步检查 git diff/status/log 后提交。
