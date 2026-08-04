# SWIFT-GAPS.md: 剩余缺口

完整历史、已完成提交记录和旧矩阵已归档到 `docs/archive/2026-08-04-swift-gaps-1/SWIFT-GAPS.md`。

本文只保留尚未完成的目标和任务边界。执行顺序以 `PLAN.md` 为准：先收敛阶段 4，再按阶段 5 到阶段 15 逐步推进。完成项不再在本文重复记录。

## 阶段 4：WorkspaceEdit 剩余缺口

- 将 WorkspaceEdit owner store 继续收敛为真正 project-level 模型，覆盖跨 app session restore、workspace root 迁移和 core history retention 后的归属 reconciliation。
- 明确不能重跑的历史请求状态：源 tab 关闭、document URI 失效、workspace root 不匹配、server capability 变化、request 参数缺失或已过期。
- 完成 snippet completion 的 `additionalTextEdits` 与 snippet 主体编辑的统一 transaction / undo 语义。
- 支持跨文件 snippet `additionalTextEdits` 的 preview、apply、failure rollback 和 conflict summary。
- 扩展更深层 conflict 检测与解决语义：dirty/stale 版本、overlapping edits、resource dependency、打开/未打开文件混合失败和 secondary rollback failure。
- 补齐阶段 4 的 Rust、FFI、Swift wrapper、AppKit panel 和回归测试。

## 阶段 5：Core Workspace Ownership

- 将 AttoEditor 的 tabs、splits、project、session 和 dirty/close 语义继续迁移为 core workspace state 的 AppKit 投影。
- 剩余 Swift-only 状态必须分类为 UI 表现缓存或真正状态所有权；真正状态所有权应下沉到 `editor-core` / `editor-core-ui` / `MultiDocumentEditorUi`。
- 补齐 tab drag/drop、split drag/drop、更高层 close/move/session restore command、workspace root 变更、recent session 和 project/session 归属。
- 继续让迁移期测试同时断言 core snapshot、Swift wrapper query 和 AppKit projection，避免双事实源漂移。

## 阶段 6：Project / LSP Lifecycle Ownership

- 将 LSP start / restart / stop / shutdown 的实际执行 ownership 从 Swift/AppKit 过渡到 core-owned typed lifecycle。
- 完成 project-level LSP server ownership schema，覆盖 workspace roots、language metadata、server capability、workspaceFolders、root alias、shared session、manual/auto trigger 和 attempt id。
- 将恢复策略从 Swift dashboard 配置推进到 core 可解释、可执行或可校验的策略模型。
- 产品化 Project LSP Dashboard：server-level health、recent failures、stderr tail、trend、recovery policy、manual actions、export/clear/query 的一致展示。
- 明确跨独立 project session 的合并、隔离、去重和 shutdown 策略。

## 阶段 7：Result Panels 与 Workbench

- 完成跨 tab / project 的 result panels 和统一 dock/workbench 容器。
- 让 Locations、Symbols、Problems、Workspace Outline、Code Lens、Inlay Hints、Document Links、Document Colors、Hierarchy 等 result family 统一消费 lifecycle metadata、stale/error 状态、refresh 和 history/pin 策略。
- 补齐跨 result family 的刷新、过期、取消、超时、错误、空结果和 stale 展示策略。
- 将仍依赖独立 floating panel 或 feature-local polling 的路径迁移到统一 workbench 入口。

## 阶段 8：Command / Menu / Keymap / Sublime 行为

- 完成 Sublime-like command、menu、keymap、palette 行为矩阵。
- 补齐 Sublime keymap 文件兼容和 key conflict / context / selector 行为。
- 继续产品化 snippets、macros、build systems、package resource loading、quick panels、input panels、output panels。
- 扩展 command palette 覆盖和 App 主路径测试，避免命令只存在于内部 helper。

## 阶段 9：Settings Selector 与配置 UI

- 完成 Sublime settings selector grammar 的兼容边界。
- 建立 schema-aware settings UI，支持 user / workspace / runtime override 的可见、可编辑、可回滚状态。
- 将 runtime override 持久化策略、跨 schema 字段迁移和无效配置反馈产品化。
- 补齐 per-document / per-language / per-workspace settings 应用的测试。

## 阶段 10：Result Envelope、错误模型与 Host Capability

- 补齐剩余 JSON result envelope 覆盖，避免主路径依赖 raw JSON escape hatch。
- 统一 Rust、C ABI、Swift wrapper 和 App 层错误模型。
- 建立 host capability negotiation：功能可用性、版本、降级、unsupported reason 和 runtime feature flag 应一致可查。
- 清理或隔离过渡 raw JSON API，保留兼容路径但不作为完成标准。

## 阶段 11：Tree-sitter + LSP 语言体验

- 产品化 Tree-sitter + LSP 主路线的 highlighting、outline、folding、language mode 和降级体验。
- 明确 Tree-sitter、LSP semantic tokens、diagnostics、symbols、folding ranges 之间的优先级和 fallback。
- 补齐语言模式切换、server 不可用、parser 不可用、large file、binary/invalid UTF-8 等场景。

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
