# SWIFT-GAPS.md: 剩余缺口

完整历史、已完成提交记录和旧矩阵已归档到 `docs/archive/2026-08-04-swift-gaps-1/SWIFT-GAPS.md`。

本文只保留尚未完成的目标和任务边界。执行顺序以 `PLAN.md` 为准：当前按阶段 11 到阶段 15 逐步推进。完成项不再在本文重复记录。

## 阶段 11：Tree-sitter + LSP 语言体验

- 产品化 Tree-sitter + LSP 主路线的 highlighting、outline、folding、language mode 和降级体验。

## 阶段 12：Workspace Search、Project Index 与 Session Workflows

- 完成 core-backed workspace search、replace-in-files、project index、recent 和 session 工作流。
- 将 opened scope、workspace scope、ignored files、binary files、large files、result pagination 和 cancellation 纳入 core-owned 模型。
- 让 Find in Files、Quick Open、recent files/projects 和 session restore 消费同一套 core-backed 数据源。

## 阶段 13：Visual Baselines 与黑盒自动化

- 合入首批经批准的机器生成 PNG golden baselines。
- PNG 合入后启用 strict visual baseline PR 门禁。
- 继续扩展 visual fixtures：WorkspaceEdit rollback secondary failure、自身再次失败的极端路径、更多 conflict/failure 边界、跨 theme/window-size 的真实 baseline。
- 扩展 opt-in `XCUIApplication` smoke tests：外部真实语言服务器、多文件 workspace、多 root/project session、真实 server 错误/延迟/重启后的 Locations/Symbols/Workspace Outline panel 行为。

## 阶段 14：Sublime-like UI 打磨

- 在测试保护下打磨 Sublime-like chrome、minimap、gutter、overlay、focus 和编辑交互。
- 对 tab bar、sidebar、status bar、quick panel、completion popup、find/replace、split panes、minimap 和 gutter markers 建立稳定视觉验收。
- 确保布局在窄窗口、多 pane、长文件、多 cursor、diagnostics、folding、semantic overlays 下不重叠、不抖动。

## 阶段 15：最终审计与收敛

- 完成最终文档审计，更新 ABI draft、crate README、Swift package README 和 App 使用说明。
- 清理过渡 API、弃用路径、重复状态源、临时 helper 和 feature flag。
- 运行全量 Rust、Swift、AppKit、visual 和 opt-in smoke 验证，记录剩余已知限制。
- 确认 `SWIFT-GAPS.md` 只剩明确 out-of-scope 或 deferred 项。
