# SWIFT-GAPS.md: 剩余缺口

完整历史、已完成提交记录和旧矩阵已归档到 `docs/archive/2026-08-04-swift-gaps-1/SWIFT-GAPS.md`。

本文只保留尚未完成的目标和任务边界。执行顺序以 `PLAN.md` 为准：当前只剩阶段 15 的最终审计与收敛任务。完成项不再在本文重复记录。

## 阶段 15：最终审计与收敛

- 完成最终文档审计，更新 ABI draft、crate README、Swift package README 和 App 使用说明。
- 清理过渡 API、弃用路径、重复状态源、临时 helper 和 feature flag。
- 运行全量 Rust、Swift、AppKit、visual 和 opt-in smoke 验证，记录剩余已知限制。
- 确认 `SWIFT-GAPS.md` 只剩明确 out-of-scope 或 deferred 项。
