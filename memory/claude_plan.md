# 执行计划

说明：我不能记录私密推理过程，但会在这里持续记录可审阅的执行计划、关键决策、进度和验证结果。

1. 读取 `TODO.md`，按文件顺序找到第一个标题未以 `[DONE]` 标记的任务。
2. 检查该任务的依赖、验收标准、验证要求和完成记录，并查看最近提交是否明确提到与该任务直接相关的未完成事项。
3. 读取与当前任务相关的源码、测试、文档和计划文件，确认需要修改的最小范围。
4. 按当前任务要求实现或修复；如果发现阻塞该任务的真实前置问题，则只在 `TODO.md` 中加入最小前置任务并停止。
5. 为实现补充或调整聚焦测试，不使用规避、弱化 fixture 或任务私有特例。
6. 运行格式化、lint、目标测试以及必要的完整测试/fixture 验证；若发现未被明确排期的失败测试或 fixture，修复或将其排入 `TODO.md`。
7. 更新 `TODO.md`：在当前任务标题前加 `[DONE]`，补全完成记录；仅当阶段级计划改变时更新 `PLAN.md`。
8. 检查 git 状态和差异，提交本任务涉及的全部未提交文件，然后停止，不推进下一项任务。

当前状态：已读取 `TODO.md`，第一个未完成任务是 `T22R Review：审查阶段性全量收口`。下一步检查最近提交与 T22/T22R 相关上下文，然后执行 review 范围验证。

进度更新：已检查最新提交 `[T22] Complete phase validation sweep`，该提交只修改 `TODO.md` 和 `memory/claude_plan.md`，未包含源码或测试文件改动，也未声明与 T22R 直接相关的未完成问题。下一步按 review 要求重新运行验证命令。

验证进度：`cargo fmt` 已运行完成。
验证进度：`cargo clippy --all-targets -- -D warnings` 已通过。
验证进度：`cargo test` 已通过。
验证进度：`cargo clippy --all-targets --all-features -- -D warnings` 已通过；已确认未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner。

完成记录更新：已将 `T22R Review：审查阶段性全量收口` 标记为 `[DONE]`，记录 review 结论和验证命令。下一步检查 git diff/status 并提交本任务变更。

最终收口：本次重新读取完整 `TODO.md` 后，确认所有任务标题均已标记 `[DONE]`，没有第一个未完成任务。最近提交为 `[T22R] Review phase validation sweep`，未声明与最终收口直接相关的未完成问题。

最终验证：已运行并通过 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，无可运行的完整 fixture runner。

提交准备：`notification.sh` 和 `run_agent.sh` 是既有未跟踪文件，不属于本次收口变更，将保持不动。本次仅提交 `memory/claude_plan.md` 的最终收口记录，然后创建 `v0.1.0` 标签。
