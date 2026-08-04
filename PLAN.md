# PLAN: 剩余 Swift gaps 实施计划

完整历史计划和已完成提交记录已归档到 `docs/archive/2026-08-04-swift-gaps-1/PLAN.md`。

## TODO（未完成任务）

- [进行中] 阶段 4：完成 WorkspaceEdit conflict 检测、解决语义和跨请求/project 重试归属。
- [待办] 阶段 5：完成 tab、split、project、session 和 LSP ownership 向 core workspace 模型迁移。
- [待办] 阶段 6：完成 core-owned project/LSP lifecycle schema、server ownership、恢复策略和 dashboard 产品化。
- [待办] 阶段 7：完成跨 tab/project result panels、统一 dock/workbench 容器和刷新/过期策略。
- [待办] 阶段 8：完成 Sublime-like command/keymap 行为矩阵、keymap 文件兼容和 snippets/macros/build systems 边界。
- [待办] 阶段 9：完成 settings selector、schema-aware settings UI、runtime override 持久化和跨 schema 字段迁移。
- [待办] 阶段 10：完成剩余 JSON result envelope 覆盖、错误模型统一和 host capability negotiation。
- [待办] 阶段 11：产品化 Tree-sitter + LSP 主路线的高亮、outline、folding、语言模式和降级体验。
- [待办] 阶段 12：完成 core-backed workspace search、project index、replace-in-files、recent 和 session 工作流。
- [待办] 阶段 13：合入首批经批准机器生成的 PNG baselines；CI 已具备 PNG 合入后自动 strict PR 门禁。
- [待办] 阶段 14：在测试保护下打磨 Sublime-like chrome、minimap、gutter、overlay、focus 和编辑交互。
- [待办] 阶段 15：完成最终文档审计、ABI/README 更新、过渡 API 清理和全量验证。

## 执行规则

- 严格按阶段顺序推进。阶段 4 未收敛前，不开始阶段 5 或后续实现；只有遇到明确阻碍且阻碍属于后续阶段时，才记录原因并做最小必要前置改动。
- 同一时间只把一个阶段标为 `[进行中]`。阶段内也应一次完成一个可提交的小任务，再开始下一项。
- 每完成一个任务就提交一次。提交前更新本文件中对应任务状态，并记录验证命令。
- 不在本文保留已完成提交流水；需要查历史时看归档目录。
- 实现时保持模块边界清晰，控制单个文件长度。文件继续膨胀时，优先拆成职责明确的新模块或测试文件。
- Swift/AppKit 只能长期持有 UI 表现缓存；workspace、tab、session、LSP lifecycle、WorkspaceEdit transaction 等事实源应优先归属 core / `editor-core-ui`。

## 阶段 4：WorkspaceEdit conflict / retry owner 收敛

### 目标

收尾 core-owned WorkspaceEdit transaction 的剩余语义：跨请求/project 的 request/conflict owner、snippet transaction/undo 合并、更深层 conflict 检测和解决 UI。

### 剩余任务

- [x] 为 WorkspaceEdit request retry owner 增加 typed descriptor，记录 request kind、label、workspace root、document URI、tab/source 信息、原始请求参数摘要和失效原因。
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditRetryDescriptorTests`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testWorkspaceEditHistoryPanelRerunsRecordedRequestOwner`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
  - 验证：`cargo test -p editor-core-ui`
  - 验证：`cargo test -p editor-core-ui-ffi`
- [x] 将 request/conflict owner 从当前 session-local closure cache 推进到 project/session 可恢复或可共享的 store；历史 transaction 即使没有可执行闭包，也应能展示归属和不可重跑原因。
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditRetryDescriptorTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testWorkspaceEditHistoryPanelRerunsRecordedRequestOwner`
  - 验证：`cargo test -p editor-core-ui`
  - 验证：`cargo test -p editor-core-ui-ffi`
- [ ] 让 WorkspaceEdit History / Preview / Conflict UI 消费 descriptor，支持保存/丢弃 conflict 后按 request owner 安全 rerun，并在不可 rerun 时禁用动作并显示原因。
- [ ] 为 snippet completion 建立单一 WorkspaceEdit transaction / undo 单元：`additionalTextEdits` 与 snippet 主体编辑必须一起 preview、apply、rollback、undo。
- [ ] 支持跨文件 snippet `additionalTextEdits` 的 transaction apply，并定义与 snippet placeholder session 的交互边界。
- [ ] 扩展 conflict 检测：dirty 与 stale version、overlapping edits、resource dependency、打开/未打开文件混合失败、unsupported URI、secondary rollback failure。
- [ ] 扩展 conflict 解决 UI：open/save/discard/retry/rerun/reapply 的可用状态、分组文案和失败反馈。
- [ ] 补齐 Rust、FFI、Swift wrapper、AppKit panel 和 targeted tests。

### 验证

- `cargo test -p editor-core-ui`
- `cargo test -p editor-core-ui-ffi`
- `swift test --package-path swift --filter 'AttoEditorCommandTests|AttoWorkspaceEdit'`
- 受影响的 AppKit panel 或 visual fixture targeted tests。

## 阶段 5：Core Workspace Ownership 迁移

### 目标

把 tabs、splits、project、session 和 LSP ownership 的事实源迁到 core workspace 模型，Swift/AppKit 只保留 projection 和 UI binding。

### 剩余任务

- [ ] 梳理 AttoEditor 仍保留的 Swift-only tab/split/session/project 状态，分类为 UI cache 或待迁移事实源。
- [ ] 将更高层 close/move/select/pin/preview/session restore command 转成 core workspace command/query。
- [ ] 补齐 tab drag/drop、split drag/drop、pane move、tab move 与 core snapshot 的一致性。
- [ ] 将 dirty state、close prompt、save-all、reload、recent session 和 root change 继续收敛到 core-backed 工作流。
- [ ] 建立迁移期测试：同一操作同时断言 core snapshot、Swift wrapper 和 AppKit projection。

## 阶段 6：Project / LSP Lifecycle 产品化

### 目标

完成 core-owned project/LSP lifecycle schema、server ownership、恢复策略和 dashboard 产品化。

### 剩余任务

- [ ] 将 LSP start/restart/stop/shutdown 的实际执行 ownership 下沉为 core-owned typed lifecycle。
- [ ] 完成 project LSP server schema：workspace roots、language metadata、capabilities、workspaceFolders、root alias、shared session、attempt id。
- [ ] 让 auto-start、manual restart/shutdown、project restart/shutdown、auto-restart 和 user stop 共享同一 core plan/execution/outcome 模型。
- [ ] 将 recovery policy 变为 core 可解释、可执行或可校验的策略。
- [ ] 产品化 Project LSP Dashboard：server health、events、stderr tail、trend、recovery policy、manual actions、query/export/clear。
- [ ] 明确跨独立 project session 的合并、隔离、去重和 shutdown 策略。

## 阶段 7：Result Panels 与 Workbench

### 目标

完成跨 tab/project result panels、统一 dock/workbench 容器和刷新/过期策略。

### 剩余任务

- [ ] 建立统一 dock/workbench 容器，减少 feature-local floating panel。
- [ ] 让 Locations、Symbols、Problems、Workspace Outline、Code Lens、Inlay Hints、Document Links、Document Colors、Hierarchy 统一消费 lifecycle metadata。
- [ ] 完成跨 tab/project 的 result ownership、history、pin、refresh、cancel、timeout、stale 和 error 行为。
- [ ] 补齐 keyboard navigation、focus restore、selection restore 和 panel persistence。
- [ ] 拆分继续增长的 Workbench/AppKit 测试文件。

## 阶段 8：Command / Keymap / Sublime 行为

### 目标

完成 Sublime-like command/keymap 行为矩阵、keymap 文件兼容和 snippets/macros/build systems 边界。

### 剩余任务

- [ ] 建立 command/menu/keymap/palette 行为矩阵，并标出 App 主路径和测试覆盖。
- [ ] 补齐 Sublime keymap 文件解析、context、selector、conflict 和 fallback 行为。
- [ ] 产品化 snippets、macros、build systems、package resources、quick panels、input panels、output panels。
- [ ] 确保新增命令都有 palette/menu/keymap 入口、可发现反馈和测试。

## 阶段 9：Settings Selector 与配置 UI

### 目标

完成 settings selector、schema-aware settings UI、runtime override 持久化和跨 schema 字段迁移。

### 剩余任务

- [ ] 补齐 Sublime settings selector grammar 的兼容范围和测试。
- [ ] 建立 schema-aware settings UI，展示 effective value、source、override 和 validation error。
- [ ] 持久化 runtime overrides，并定义 user/workspace/runtime 的合并和回滚行为。
- [ ] 完成跨 schema 字段迁移和无效配置降级反馈。

## 阶段 10：Result Envelope、错误模型与 Host Capability

### 目标

完成剩余 JSON result envelope 覆盖、错误模型统一和 host capability negotiation。

### 剩余任务

- [ ] 找出仍只走 raw JSON 的主路径并补 typed result envelope。
- [ ] 统一 Rust、C ABI、Swift wrapper 和 App 层错误模型。
- [ ] 建立 host capability negotiation：feature availability、version、unsupported reason、runtime feature flag。
- [ ] 清理或隔离过渡 raw JSON API。

## 阶段 11：Tree-sitter + LSP 语言体验

### 目标

产品化 Tree-sitter + LSP 主路线的高亮、outline、folding、语言模式和降级体验。

### 剩余任务

- [ ] 明确 Tree-sitter highlighting、LSP semantic tokens、diagnostics、symbols、folding ranges 的优先级和 fallback。
- [ ] 产品化 language mode 切换、parser/server 不可用、大文件、binary/invalid UTF-8 的降级体验。
- [ ] 补齐 outline、folding、高亮、diagnostics 和 status bar 的跨语言测试。

## 阶段 12：Workspace Search / Project Index / Session

### 目标

完成 core-backed workspace search、project index、replace-in-files、recent 和 session 工作流。

### 剩余任务

- [ ] 将 workspace search、replace-in-files 和 project index 统一到 core-backed 数据源。
- [ ] 支持 ignored files、binary files、large files、pagination、cancellation 和 result refresh。
- [ ] 让 Find in Files、Quick Open、recent files/projects 和 session restore 消费同一套 core-backed 数据源。

## 阶段 13：Visual Baselines 与黑盒自动化

### 目标

合入首批经批准机器生成的 PNG baselines，并让 CI 在 PNG 合入后自动执行 strict PR 门禁。

### 剩余任务

- [ ] 生成、审核并提交首批 PNG golden baselines。
- [ ] PNG 合入后确认 strict visual baseline PR 门禁默认生效。
- [ ] 扩展 WorkspaceEdit rollback secondary failure、更多 conflict/failure 边界和跨 theme/window-size fixtures。
- [ ] 扩展 opt-in `XCUIApplication` smoke tests：真实 LSP server、多文件 workspace、多 root/project session、server 错误/延迟/重启后的 panels。

## 阶段 14：Sublime-like UI 打磨

### 目标

在测试保护下打磨 Sublime-like chrome、minimap、gutter、overlay、focus 和编辑交互。

### 剩余任务

- [ ] 打磨 tab bar、sidebar、status bar、quick panel、completion popup、find/replace、split panes、minimap 和 gutter marker。
- [ ] 覆盖窄窗口、多 pane、长文件、多 cursor、diagnostics、folding、semantic overlays 的布局与视觉测试。
- [ ] 修复 focus、keyboard navigation、selection、hover、scroll、overlay stacking 的产品细节。

## 阶段 15：最终审计与全量验证

### 目标

完成最终文档审计、ABI/README 更新、过渡 API 清理和全量验证。

### 剩余任务

- [ ] 更新 `docs/abi-v1-draft.md`、crate README、Swift package README 和 App 使用说明。
- [ ] 清理过渡 API、重复状态源、临时 helper、旧 feature flag 和未使用测试 fixture。
- [ ] 运行全量 Rust、Swift、AppKit、visual 和 opt-in smoke 验证。
- [ ] 将仍未完成的内容明确标为 out-of-scope 或 deferred，并从本计划中移除。
