执行计划记录

当前约束
- 只处理 TODO.md 中第一个标题未带 [DONE] 的任务，完成后停止。
- 不做开放式历史问题扫除；只处理阻塞当前任务或验证失败暴露出的未排期问题。
- 如遇到无法按规格完成的阻塞问题，最小化新增前置任务到 TODO.md，提交后停止。
- 不记录私有推理过程；本文件记录可审计的执行计划、决策和进度。

初始计划
1. 读取 TODO.md，识别第一个未完成任务及其验证要求、依赖和完成记录。
2. 查看最新提交信息，只判断是否有与当前任务直接相关的未完成事项。
3. 根据当前任务读取必要的代码、测试、文档上下文，避免无关 triage。
4. 实现当前任务；若发现规格阻塞，更新 TODO.md 加入最小前置任务并停止。
5. 按要求运行格式化、lint、相关测试，并在需要时运行完整测试套件。
6. 更新 TODO.md：将完成任务标题加 [DONE]，补充 completion record。
7. 检查 git diff/status，提交所有与本次任务相关的改动，然后停止。

进度
- 已创建执行计划记录，下一步读取 TODO.md 识别第一个未完成任务。
- 已读取 TODO.md；第一个未完成任务是 T08：在 diff-view projection 数据中加入 gutter 行号与 +/- 标记，新增 gutter 测试，不触碰 editor-core 通用 line mark 设施。
- 下一步检查最新提交是否有与 T08 直接相关的未完成事项，然后读取 `projection.rs` 与相关测试结构。
- 最新提交为 `[T07R] Record final plan status`，未提及与 T08 直接相关的未完成事项。
- 下一步读取 `projection.rs`、`style.rs` 及现有 projection/style 测试，确定最小数据结构改动。
- 已确认投影层当前 `RowSlot` 已承载 `side` / `logical_line` / `visual_in_logical` / `change` / `cells`，T08 可在此基础上最小新增 `Gutter` 数据，不需要改 `editor-core` 通用 decoration/line mark。
- 实施计划：新增 `Gutter { before_line, after_line, marker }`，给 `Line` 与 `Spacer` slot 挂载；unified context 填两侧 0-based 行号，side-by-side 各列只填本侧行号；Add/Remove 首段分别填 `+`/`-`，续段与 spacer 为空；新增 `tests/gutter.rs` 覆盖要求。
- 已实现初版：`RowSlot` 新增 gutter 数据，新增 gutter 专项测试，更新 smoke 构造。下一步按顺序运行 `cargo fmt`、lint 与测试。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test gutter`；`cargo test -p editor-core-diff-view`；`cargo test --all --all-targets`。
- 已确认仓库内无 `tools/run_fixtures.py`，无独立 fixture suite 可运行。
- 下一步更新 TODO.md，将 T08 标记为 `[DONE]` 并补充完成记录，然后检查 diff/status 并提交。
- 已更新 TODO.md：T08 标题已标记 `[DONE]`，完成记录包含实现摘要、后续通用 line mark 提取项、验证命令和 fixture suite 状态。
- 已检查 staged diff；`notification.sh` 与 `run_agent.sh` 为未跟踪且非本任务文件，不纳入提交。
- 已提交 T08 实现，提交为 `f8ccf46 [T08] Implement diff-view gutter data`。
- 本次任务完成后停止，不进入 T08R。
