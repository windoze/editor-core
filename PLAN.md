# PLAN: Swift gaps 收口记录

完整历史计划和已完成提交记录已归档到 `docs/archive/2026-08-04-swift-gaps-1/PLAN.md`。

## 阶段状态

- [已完成] 阶段 4：完成 WorkspaceEdit conflict 检测、解决语义和跨请求/project 重试归属。
- [已完成] 阶段 5：完成 tab、split、project、session 和 LSP ownership 向 core workspace 模型迁移。
- [已完成] 阶段 6：完成 core-owned project/LSP lifecycle schema、server ownership、恢复策略和 dashboard 产品化。
- [已完成] 阶段 7：完成跨 tab/project result panels、统一 dock/workbench 容器和刷新/过期策略。
- [已完成] 阶段 8：完成 Sublime-like command/keymap 行为矩阵、keymap 文件兼容和 snippets/macros/build systems 边界。
- [已完成] 阶段 9：完成 settings selector、schema-aware settings UI、runtime override 持久化和跨 schema 字段迁移。
- [已完成] 阶段 10：完成剩余 JSON result envelope 覆盖、错误模型统一和 host capability negotiation。
- [已完成] 阶段 11：产品化 Tree-sitter + LSP 主路线的高亮、outline、folding、语言模式和降级体验。
- [已完成] 阶段 12：完成 core-backed workspace search、project index、replace-in-files、recent 和 session 工作流。
- [已完成] 阶段 13：合入首批经批准机器生成的 PNG baselines；CI 已具备 PNG 合入后自动 strict PR 门禁。
- [已完成] 阶段 14：在测试保护下打磨 Sublime-like chrome、minimap、gutter、overlay、focus 和编辑交互。
- [已完成] 阶段 15：完成最终文档审计、ABI/README 更新、过渡 API 清理和全量验证。

## 执行规则

- 严格按阶段顺序推进。阶段 4 未收敛前，不开始阶段 5 或后续实现；只有遇到明确阻碍且阻碍属于后续阶段时，才记录原因并做最小必要前置改动。
- 历史执行规则要求同一时间只保留一个活跃阶段；阶段内也应一次完成一个可提交的小任务，再开始下一项。
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
- [x] 让 WorkspaceEdit History / Preview / Conflict UI 消费 descriptor，支持保存/丢弃 conflict 后按 request owner 安全 rerun，并在不可 rerun 时禁用动作并显示原因。
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditRetryDescriptorTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test.*WorkspaceEdit.*SaveAndRetry'`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testWorkspaceEditPreviewDiscardAndRetryDecisionAppliesAfterReloadingTargetTab`
  - 验证：`cargo test -p editor-core-ui`
  - 验证：`cargo test -p editor-core-ui-ffi`
- [x] 为 snippet completion 建立单一 WorkspaceEdit transaction / undo 单元：`additionalTextEdits` 与 snippet 主体编辑必须一起 preview、apply、rollback、undo。
  - 验证：`cargo test -p editor-core snippets`
  - 验证：`cargo test -p editor-core-lsp test_apply_completion_item_groups_edits_into_single_undo_step`
  - 验证：`cargo test -p editor-core-ui multi_document_ui_applies_snippet_completion_workspace_edit_as_single_transaction`
  - 验证：`cargo test -p editor-core-ui`
  - 验证：`cargo test -p editor-core-ui-ffi`
  - 验证：`swift test --package-path swift --filter AttoLspCompletionParserTests`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test.*Completion.*'`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
- [x] 支持跨文件 snippet `additionalTextEdits` 的 transaction apply，并定义与 snippet placeholder session 的交互边界。
  - 验证：`cargo test -p editor-core-ui multi_document_ui_applies_cross_file_snippet_completion_workspace_edit_as_single_transaction`
  - 验证：`cargo test -p editor-core-ui multi_document_ui_rolls_back_cross_file_snippet_completion_after_runtime_failure`
  - 验证：`cargo test -p editor-core-ui`
  - 验证：`cargo test -p editor-core-ui-ffi`
  - 验证：`swift test --package-path swift --filter AttoLspCompletionParserTests`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test.*Completion.*'`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
- [x] 扩展 conflict 检测：dirty 与 stale version、overlapping edits、resource dependency、打开/未打开文件混合失败、unsupported URI、secondary rollback failure。
  - 验证：`cargo test -p editor-core-ui atomic_runtime_failure_result_reports_secondary_filesystem_rollback_failure`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`cargo test -p editor-core-ui`
  - 验证：`cargo test -p editor-core-ui-ffi`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
- [x] 扩展 conflict 解决 UI：open/save/discard/retry/rerun/reapply 的可用状态、分组文案和失败反馈。
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditRetryDescriptorTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/testWorkspaceEditHistoryPanel'`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
  - 验证：`cargo test -p editor-core-ui`
  - 验证：`cargo test -p editor-core-ui-ffi`
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`
- [x] 补齐 Rust、FFI、Swift wrapper、AppKit panel 和 targeted tests。
  - 验证：`cargo test -p editor-core-ui-ffi ffi_multi_document_atomic_workspace_edit_preflight_skips_without_mutating`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`cargo build -p editor-core-ui-ffi`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditTransactionWrapperTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
  - 验证：`cargo test -p editor-core-ui-ffi`
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`
- [x] 将 WorkspaceEdit owner store reconciliation 收敛为 project-level root / core history 边界，覆盖跨 app session restore、workspace root alias 和 history retention 后的归属匹配。
  - 验证：`cargo build -p editor-core-ui-ffi -p editor-core-ffi`
  - 验证：`cargo clean -p editor-core-ui-ffi && cargo build -p editor-core-ui-ffi`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditRequestOwnerStoreTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEditRetryDescriptorTests`
  - 验证：`swift test --package-path swift --filter AttoWorkspaceEdit`
  - 验证：`cargo test -p editor-core-ui-ffi`
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`

### 验证

- `cargo test -p editor-core-ui`
- `cargo test -p editor-core-ui-ffi`
- `swift test --package-path swift --filter 'AttoEditorCommandTests|AttoWorkspaceEdit'`
- 受影响的 AppKit panel 或 visual fixture targeted tests。

## 阶段 5：Core Workspace Ownership 迁移

### 目标

把 tabs、splits、project、session 和 LSP ownership 的事实源迁到 core workspace 模型，Swift/AppKit 只保留 projection 和 UI binding。

### 剩余任务

- [x] 梳理 AttoEditor 仍保留的 Swift-only tab/split/session/project 状态，分类为 UI cache 或待迁移事实源。
  - 产出：`docs/core-workspace-ownership-audit.md`
  - 验证：`git diff --check`
- [x] 将更高层 close/move/select/pin/preview/session restore command 转成 core workspace command/query。
  - [x] 将 close all / close other / close right 的高层 tab group command 改为 dirty/LSP preflight 后执行 core bulk close command，并同步 AppKit projection。
  - [x] 补 session restore 的 core snapshot / Swift wrapper / AppKit projection 一致性测试，确认 restoreSession 通过 core tab/view commands 重建 tabs/panes/selection。
  - [x] 将 move/select/pin/preview 高层 tab command 的回归覆盖收敛到 core workspace command 测试，验证 core snapshot、Swift wrapper 和 AppKit projection 一致。
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceCommandTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceSessionRestoreTests`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/testSession(SnapshotRestoresUnsavedUntitledBuffers|RestoreRestoresSplitPanesIntoCoreMirror|RestorePrefersPaneLayoutSnapshotOverLegacyPaneCount)'`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testCloseTabGroupCommandsUseCoreTabProjection`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testCloseAllTabsReleasesOwnedLspSessionsWithoutDuplicateDidClose`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testCloseAllTabsUsesCoreTabProjectionOrder`
  - 验证：`git diff --check`
- [x] 补齐 tab drag/drop、split drag/drop、pane move、tab move 与 core snapshot 的一致性。
  - [x] 将 split/pane focus/move/close 与 tab drag reorder 的 core snapshot / Swift wrapper / AppKit projection 回归拆到独立 core workspace drag projection 测试。
  - [x] tab move command 回归已收敛到 core workspace command 测试。
  - [x] 设计并实现 drag tab to split / split drag/drop 入口；当前代码只发现 tab bar reorder drag 和命令式 split/pane move。
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceDragDropEntryTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceDragProjectionTests`
  - 验证：`git diff --check`
- [x] 将 dirty state、close prompt、save-all、reload、recent session 和 root change 继续收敛到 core-backed 工作流。
  - [x] 将 dirty close prompt、open-file dirty projection、reload、save active、save-all 的 core-backed 回归拆到独立 dirty state 测试。
  - [x] 将 workspace root session snapshot、recent files、recent projects 的 core-backed 回归拆到独立 recent/root 测试。
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceDirtyStateTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceRecentRootTests`
- [x] 建立迁移期测试：同一操作同时断言 core snapshot、Swift wrapper 和 AppKit projection。
  - [x] 已按职责拆为 core workspace command / session restore / drag projection / dirty state / recent-root focused tests，避免继续扩张 `AttoEditorCommandTests.swift`。
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceCommandTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceSessionRestoreTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceDragProjectionTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceDirtyStateTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceRecentRootTests`

## 阶段 6：Project / LSP Lifecycle 产品化

### 目标

完成 core-owned project/LSP lifecycle schema、server ownership、恢复策略和 dashboard 产品化。

### 剩余任务

- [x] 将 LSP start/restart/stop/shutdown 的实际执行 ownership 下沉为 core-owned typed lifecycle。
  - [x] 让 core-owned start/stop/restart plan entries 显式携带 `operation` 字段，并同步 Rust、FFI JSON、Swift wrapper 和 ABI draft，作为统一 lifecycle action descriptor 的基础。
  - [x] 将 Swift Project LSP lifecycle outcome 记录收敛到统一 action descriptor，并让 auto-start、manual restart/shutdown、project restart/shutdown、auto-restart、tab close 和 language-change stop 复用 core plan entry 的 operation / workspace roots / active view metadata。
  - [x] 移除 Swift/AppKit 在 core plan 缺失或构建失败时直接执行 project LSP start/restart/stop/shutdown 的 fallback；项目级与单 tab 生命周期操作必须匹配 core typed plan entry 才会执行。
  - 验证：`cargo test -p editor-core-ui project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`swift test --package-path swift --filter EditorCoreUIFFITests/testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testProjectLspLaunchConfigsSyncToCoreProjectStore`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(WorkspaceRootChangeAutoStartsConfiguredOpenTabLsp|ClosingConfiguredProjectLspTabRecordsStopOutcome|PlainTextSyntaxSwitchRecordsProjectLspStopOutcome)'`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ProjectLspAutoRestartUsesCoreRestartPlanRoot|RestartLspServerInActiveTabUsesCoreRestartPlanRoot|RestartLspServerRestartsActiveTabSession|ShutdownLspServerStopsActiveSessionAndRecordsOutcome|ShutdownProjectLspServersStopsConfiguredOpenTabsAndRecordsOutcomes|RestartProjectLspServersRestartsConfiguredOpenTabs)'`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ShutdownLspServerInActiveTabRequiresCoreStopPlanMatch|ShutdownLspServerRequiresRunningSession|ShutdownProjectLspServersRequiresRunningConfiguredTabs)'`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testProjectLspProcessHealthAutoRestartsExitedConfiguredTab`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ProjectLspAutoStartUsesCoreStartPlanLanguageFilter|WorkspaceRootChangeAutoStartsConfiguredOpenTabLsp|RestartLspServerInActiveTabUsesCoreRestartPlanRoot|RestartLspServerInActiveTabRecordsSkippedWhenCorePlanDoesNotMatch|ShutdownLspServerInActiveTabRequiresCoreStopPlanMatch|ShutdownProjectLspServersStopsConfiguredOpenTabsAndRecordsOutcomes|RestartProjectLspServersRestartsConfiguredOpenTabs)'`
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`
- [x] 完成 project LSP server schema：workspace roots、language metadata、capabilities、workspaceFolders、root alias、shared session、attempt id。
  - [x] 为 project LSP server config、start/stop/restart plan、lifecycle outcome/event 增加 typed `workspace_folders` descriptor（`uri` / `name` / `root_alias`），并保持 `workspace_roots` 兼容字段可互相派生。
  - [x] 为 project LSP server config、start/stop/restart plan、lifecycle outcome/event 增加 normalized `language_name` metadata，并在缺省时回退到 `language_id`。
  - [x] 为 project LSP server config、start/stop/restart plan、lifecycle outcome/event 增加 typed `server_capabilities` JSON object，缺省 `{}`，并拒绝非 object 输入。
  - [x] 为 project LSP server config、start/stop/restart plan、lifecycle outcome/event 增加 `shared_session` schema flag，缺省 `true`。
  - [x] 为 project LSP start/stop/restart plan entries 增加 core 生成的 proposed `attempt_id`，并让 Swift action descriptor 用它记录 requested/started/stopped outcomes。
  - 验证：`cargo test -p editor-core-ui project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`swift test --package-path swift --filter EditorCoreUIFFITests/testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`
  - 验证：`swift test --package-path swift --filter 'EditorCoreUIFFITests/testProjectLsp(ServersEnvelopeReportsSuccess|LifecycleEnvelopeReportsPlansEventsAndErrors)'`
  - 验证：`swift test --package-path swift --filter 'EditorCoreUIFFITests/testProjectLspLifecycleEnvelopeDecodesFutureFieldsAndUnknownStatus|AttoLspResultLifecycleStoreTests/testProjectLspLifecycleEventStoreBoundsAndFiltersBySequence'`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ProjectLspLaunchConfigsSyncToCoreProjectStore|ShutdownLspServerStopsActiveSessionAndRecordsOutcome)'`
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`
- [x] 让 auto-start、manual restart/shutdown、project restart/shutdown、auto-restart 和 user stop 共享同一 core plan/execution/outcome 模型。
  - [x] 将 Swift Project LSP 配置同步与 lifecycle 执行从 `Persistence.swift` 拆到 `ProjectLspConfig` / `ProjectLspLifecycle` extension，保留所有路径共用 core start/stop/restart plan entry、`AttoProjectLspLifecycleAction` 和 requested/terminal outcome 写回模型。
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testProjectLspLaunchConfigsSyncToCoreProjectStore`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(WorkspaceRootChangeAutoStartsConfiguredOpenTabLsp|ClosingConfiguredProjectLspTabRecordsStopOutcome|PlainTextSyntaxSwitchRecordsProjectLspStopOutcome|ProjectLspAutoRestartUsesCoreRestartPlanRoot|RestartLspServerInActiveTabUsesCoreRestartPlanRoot|RestartLspServerRestartsActiveTabSession|ShutdownLspServerStopsActiveSessionAndRecordsOutcome|ShutdownProjectLspServersStopsConfiguredOpenTabsAndRecordsOutcomes|RestartProjectLspServersRestartsConfiguredOpenTabs|ProjectLspProcessHealthAutoRestartsExitedConfiguredTab)'`
- [x] 将 recovery policy 变为 core 可解释、可执行或可校验的策略。
  - [x] 为 project LSP server config、start/stop/restart plan、lifecycle outcome/event 增加 typed `recovery_policy`（`enabled` / `max_attempts` / `base_delay_millis`），缺省保持现有 auto-restart 行为，并在 core 侧 clamp 到可执行范围。
  - [x] Swift wrapper 新增 `EcuProjectLspRecoveryPolicy`，并让 AppKit lifecycle action descriptor、outcome 和 event projection 携带同一策略。
  - [x] AttoEditor 将 auto-restart preferences 投影到 core project LSP config，并让 auto-restart 执行路径消费 core restart plan entry 上的 recovery policy；运行时 server-name override 仍作为更具体的用户覆盖。
  - [x] 将自动恢复执行逻辑拆到 `AttoEditorAreaViewController+ProjectLspRecovery.swift`，避免继续扩张 `ProjectLspLifecycle.swift`。
  - 验证：`cargo test -p editor-core-ui project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`swift test --package-path swift --filter EditorCoreUIFFITests/testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`
  - 验证：`swift test --package-path swift --filter 'EditorCoreUIFFITests/testProjectLsp(ServersEnvelopeReportsSuccess|LifecycleEnvelopeReportsPlansEventsAndErrors|LifecycleEnvelopeDecodesFutureFieldsAndUnknownStatus)'`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ProjectLspLaunchConfigsSyncToCoreProjectStore|ProjectLspAutoRestartUsesServerSpecificBackoffPolicy|ProjectLspAutoRestartCanBeDisabledByPreferences|ProjectLspAutoRestartCanBeDisabledForServerByPreferences|ProjectLspAutoRestartUsesBackoffAndResetsAfterHealthyStatus|ProjectLspProcessHealthAutoRestartsExitedConfiguredTab|ProjectLspAutoRestartUsesCoreRestartPlanRoot)'`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(WorkspaceRootChangeAutoStartsConfiguredOpenTabLsp|ClosingConfiguredProjectLspTabRecordsStopOutcome|PlainTextSyntaxSwitchRecordsProjectLspStopOutcome|ProjectLspAutoRestartUsesCoreRestartPlanRoot|RestartLspServerInActiveTabUsesCoreRestartPlanRoot|RestartLspServerRestartsActiveTabSession|ShutdownLspServerStopsActiveSessionAndRecordsOutcome|ShutdownProjectLspServersStopsConfiguredOpenTabsAndRecordsOutcomes|RestartProjectLspServersRestartsConfiguredOpenTabs|ProjectLspProcessHealthAutoRestartsExitedConfiguredTab)'`
  - 验证：`swift test --package-path swift --filter AttoLspResultLifecycleStoreTests/testProjectLspLifecycleEventStoreBoundsAndFiltersBySequence`
  - 验证：`cargo fmt --check`
- [x] 产品化 Project LSP Dashboard：server health、events、stderr tail、trend、recovery policy、manual actions、query/export/clear。
  - [x] Dashboard 汇总 status failures、core lifecycle events/attempts、process health、persisted logs、active recovery retry state，并展示 server-level health/log failed 计数、stderr tail、趋势窗口和 manual recovery actions。
  - [x] Dashboard server 行和 lifecycle 行展示 core lifecycle event 携带的 typed `recovery_policy`，让执行时使用的恢复策略能在排障入口中直接审计。
  - [x] Process health log 面板保留 field filter query，并提供当前 workspace 的 clear/export 操作；Dashboard 继续复用同一日志和事件模型。
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ProjectLspDashboardPanelShowsStatusAndHealthSnapshots|ProjectLspDashboardShowsCoreRecoveryPolicyFromLifecycleEvents|ProjectLspProcessHealthLogPanelUsesFieldFilterQuery|ClearProjectLspProcessHealthLogClearsCurrentWorkspaceOnly|ExportProjectLspProcessHealthLogExportsCurrentWorkspaceOnly)'`
- [x] 明确跨独立 project session 的合并、隔离、去重和 shutdown 策略。
  - [x] 为 project LSP server config、start/stop/restart plan、lifecycle outcome/event 增加 typed `session_policy`（`scope` / `merge_strategy` / `deduplicate` / `shutdown_policy`）和 plan/outcome/event `session_key`。
  - [x] `shared_session=true` 归一化为 workspace-scoped shared policy（按 server + workspace roots 合并、可去重、last-document shutdown）；`shared_session=false` 归一化为 document-scoped isolated policy（按 document 隔离、不去重、document-close shutdown）。
  - [x] Swift wrapper、AttoEditor lifecycle action descriptor 和 Project LSP events 展示消费同一 session policy/key，旧 `shared_session` 字段保持兼容。
  - 验证：`cargo test -p editor-core-ui project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi project_lsp`
  - 验证：`cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`swift test --package-path swift --filter EditorCoreUIFFITests/testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`
  - 验证：`swift test --package-path swift --filter 'EditorCoreUIFFITests/testProjectLsp(ServersEnvelopeReportsSuccess|LifecycleEnvelopeReportsPlansEventsAndErrors|ServersEnvelopeDecodesFutureFieldsAndUnknownStatus|LifecycleEnvelopeDecodesFutureFieldsAndUnknownStatus)'`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ProjectLspLaunchConfigsSyncToCoreProjectStore|ShutdownLspServerStopsActiveSessionAndRecordsOutcome|ProjectLspDashboardShowsCoreRecoveryPolicyFromLifecycleEvents)'`
  - 验证：`swift test --package-path swift --filter AttoLspResultLifecycleStoreTests/testProjectLspLifecycleEventStoreBoundsAndFiltersBySequence`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(WorkspaceRootChangeAutoStartsConfiguredOpenTabLsp|ClosingConfiguredProjectLspTabRecordsStopOutcome|PlainTextSyntaxSwitchRecordsProjectLspStopOutcome|ProjectLspAutoRestartUsesCoreRestartPlanRoot|RestartLspServerInActiveTabUsesCoreRestartPlanRoot|RestartLspServerRestartsActiveTabSession|ShutdownLspServerStopsActiveSessionAndRecordsOutcome|ShutdownProjectLspServersStopsConfiguredOpenTabsAndRecordsOutcomes|RestartProjectLspServersRestartsConfiguredOpenTabs|ProjectLspProcessHealthAutoRestartsExitedConfiguredTab)'`
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`

## 阶段 7：Result Panels 与 Workbench

### 目标

完成跨 tab/project result panels、统一 dock/workbench 容器和刷新/过期策略。

### 剩余任务

- [x] 建立统一 dock/workbench 容器，减少 feature-local floating panel。
  - [x] 新增嵌入 editor area 的 LSP Workbench Dock，复用现有 result family item、lifecycle metadata、stale/error、history/pin 和 jump target summary。
  - [x] 新增 `lsp.show_workbench_dock` command、主菜单入口和稳定 accessibility identifiers；现有 floating panel 保留为兼容入口，后续 feature-local panel 可逐步迁移到 dock。
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/testLspWorkbench(DockSummarizesResultFamiliesInline|PanelSummarizesResultFamilies)'`
  - 验证：`swift test --package-path swift --filter AttoLspWorkbenchDockViewTests/testDockViewExposesStableIdentifiersAndFiltersRows`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testMainMenuItemsUseCommandIDsAndResolvedKeymap`
  - 验证：`swift test --package-path swift --filter Workbench`
- [x] 让 Locations、Symbols、Problems、Workspace Outline、Code Lens、Inlay Hints、Document Links、Document Colors、Hierarchy 统一消费 lifecycle metadata。
  - [x] 新增共享 `AttoLspResultMetadataText` 和 `AttoEditorAreaViewController+LSPResultMetadata`，统一 `count | state | Result # | family | title` 文案生成。
  - [x] Locations、Symbols/Workspace Outline、Workbench 和 Problems 面板统一复用 lifecycle entry metadata；Code Lens、Inlay Hints、Document Links、Document Colors、Hierarchy 通过 result event metadata 传入各自面板。
  - [x] Problems / Workspace Problems 新增稳定 metadata accessibility identifiers，并保留 controller 直用时的 fallback 文案。
  - 验证：`swift test --package-path swift --filter AttoAccessibilityIdentifierTests/testLspLocationPanelExposesStableIdentifiersAndFiltersRows`
  - 验证：`swift test --package-path swift --filter AttoAccessibilityIdentifierTests/testLspSymbolPanelExposesStableIdentifiersAndFiltersRows`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testWorkspaceOutlinePanelAggregatesDocumentSymbolSnapshots`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testHierarchyPanelUsesLastHierarchyResults`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testDocumentLinkPanelUsesDerivedDecorations`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testInlayHintPanelUsesDerivedDecorations`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testCodeLensPanelUsesDerivedDecorations`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testDocumentColorPanelUsesDocumentColorResults`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test.*ProblemsPanel'`
  - 验证：`swift test --package-path swift --filter AttoAccessibilityIdentifierTests/testProblemsPanelExposesStableIdentifiersAndFiltersRows`
  - 验证：`swift test --package-path swift --filter AttoAccessibilityIdentifierTests/testWorkspaceProblemsPanelExposesStableIdentifiersAndFiltersRows`
  - 验证：`swift test --package-path swift --filter Workbench`
- [x] 完成跨 tab/project 的 result ownership、history、pin、refresh、cancel、timeout、stale 和 error 行为。
  - [x] 为 result lifecycle entry/event 增加 owner descriptor，并让 Workbench 与 result panel 的 current result 按 active tab / current workspace 过滤；history count 保留跨 tab 可见。
    - 验证：`swift test --package-path swift --filter AttoLspResultOwnerLifecycleTests`
    - 验证：`swift test --package-path swift --filter AttoEditorLspWorkbenchOwnershipTests/testLspWorkbenchCurrentResultsFollowActiveTabOwnership`
    - 验证：`swift test --package-path swift --filter Workbench`
  - [x] 补齐 history / pin 在跨 tab/project restore 后的 owner 归属、jump target、selection restore 和 stale/error metadata fallback。
    - 验证：`swift test --package-path swift --filter AttoEditorLspWorkbenchOwnershipTests`
    - 验证：`swift test --package-path swift --filter Workbench`
  - [x] 统一 refresh / cancel / timeout / error 策略，并覆盖 active tab、workspace、空结果和 stale 展示路径。
    - [x] 让 Document Colors refresh 的空结果记录 fresh empty lifecycle，清理 stale/error current state，并在 Workbench 中显示 `0 colors`。
      - 验证：`swift test --package-path swift --filter AttoEditorLspWorkbenchRefreshTests`
    - [x] 抽出 event-backed result 的 refresh/cancel/timeout/error 标记 helper，减少 Code Lens / Inlay Hints / Document Links / Document Colors / Hierarchy 的重复分支。
      - [x] 先覆盖 Code Lens / Inlay Hints / Document Links / Document Colors 的 refresh failure / timeout / result-error 写入路径。
        - 验证：`swift test --package-path swift --filter AttoEditorLspWorkbenchRefreshTests`
        - 验证：`swift test --package-path swift --filter Workbench`
      - [x] 再覆盖 Hierarchy prepare / children refresh 的 failure / timeout / result-error 写入路径。
        - 验证：`swift test --package-path swift --filter Hierarchy`
        - 验证：`swift test --package-path swift --filter AttoEditorLspWorkbenchRefreshTests`
        - 验证：`swift test --package-path swift --filter Workbench`
    - [x] 覆盖 active tab 与 workspace diagnostics refresh 的空结果、stale 清理和 error metadata 策略。
      - 验证：`swift test --package-path swift --filter AttoEditorLspWorkbenchRefreshTests`
      - 验证：`swift test --package-path swift --filter Diagnostics`
      - 验证：`swift test --package-path swift --filter Workbench`
- [x] 补齐 keyboard navigation、focus restore、selection restore 和 panel persistence。
  - [x] 先补 Workbench History / Problems panel 的 selection restore 与空结果键盘保护。
    - 验证：`swift test --package-path swift --filter AttoAccessibilityIdentifierTests`
    - 验证：`swift test --package-path swift --filter Workbench`
  - [x] 再补 Workbench floating panel / dock 的 focus restore 与可见性持久化。
    - 验证：`swift test --package-path swift --filter Workbench`
- [x] 拆分继续增长的 Workbench/AppKit 测试文件。
  - 验证：`swift test --package-path swift --filter AttoAccessibilityIdentifierTests`
  - 验证：`swift test --package-path swift --filter Workbench`

## 阶段 8：Command / Keymap / Sublime 行为

### 目标

完成 Sublime-like command/keymap 行为矩阵、keymap 文件兼容和 snippets/macros/build systems 边界。

### 剩余任务

- [x] 建立 command/menu/keymap/palette 行为矩阵，并标出 App 主路径和测试覆盖。
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testCommandSurfacesReferenceRegisteredCommandIDs`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testMainMenuItemsUseCommandIDsAndResolvedKeymap`
- [x] 补齐 Sublime keymap 文件解析、context、selector、conflict 和 fallback 行为。
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testSublimeKeymap`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testKeymap`
- [x] 产品化 snippets、macros、build systems、package resources、quick panels、input panels、output panels。
  - [x] 建立 build/package/panel 的 command/menu/palette 边界和可发现反馈，保留 snippets/macros 现有产品化路径。
    - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testSublimeBoundaryCommandsExposeDiscoverableFeedback`
    - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testMainMenuItemsUseCommandIDsAndResolvedKeymap`
  - [x] 增加 `.sublime-build` discovery/run/cancel/output panel、package resource open 和 Sublime quick panel 主路径；input panel 在未引入 package/plugin host 前提供明确边界反馈。
    - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testSublime`
    - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testPackageResourceCommandOpensSingleResource`
- [x] 确保新增命令都有 palette/menu/keymap 入口、可发现反馈和测试。
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testRegisteredCommandsHaveDiscoverableSurfacePolicy`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testCommandSurfacesReferenceRegisteredCommandIDs`

## 阶段 9：Settings Selector 与配置 UI

### 目标

完成 settings selector、schema-aware settings UI、runtime override 持久化和跨 schema 字段迁移。

### 剩余任务

- [x] 补齐 Sublime settings selector grammar 的兼容范围和测试。
  - 验证：`swift test --package-path swift --filter AttoConfigurationSettingsTests/testScopedSettingsSupportSublimeSelectorGrammar`
  - 验证：`swift test --package-path swift --filter AttoConfigurationSettingsTests/testScopedSettingsMatchGlobFileExtensionAndBareLanguageSelectors`
  - 验证：`swift test --package-path swift --filter AttoConfigurationSettingsTests/testSettingsResolutionAppliesMatchingScopedSettings`
- [x] 建立 schema-aware settings UI，展示 effective value、source、override 和 validation error。
  - 交付：Preferences 增加 Settings 页，按当前 schema 展示全局 effective value、source、user/workspace/runtime override、scoped override 摘要和 validation error。
  - 验证：`swift test --package-path swift --filter AttoSettingsSchemaPageTests`
- [x] 持久化 runtime overrides，并定义 user/workspace/runtime 的合并和回滚行为。
  - 交付：runtime overrides 启动时从 `runtime-overrides.json` 加载，设置后自动保存；合并顺序为 base preferences -> user settings -> workspace settings -> runtime overrides；清空 runtime overrides 会删除持久化文件并回滚到 user/workspace 生效值。
  - 验证：`swift test --package-path swift --filter AttoRuntimeConfigurationSettingsTests`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(CommandRegistry|CommandSurfaces|RegisteredCommands|DefaultCommandPalette)'`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testMainMenuItemsUseCommandIDsAndResolvedKeymap`
- [x] 完成跨 schema 字段迁移和无效配置降级反馈。
  - 交付：旧 settings 字段别名会迁移并写回当前 schema；settings store 暴露 load outcome，Settings 页和 AppDelegate 会在 invalid settings 被备份并降级到 fallback 配置时反馈状态。
  - 验证：`swift test --package-path swift --filter AttoConfigurationSettingsMigrationFeedbackTests`
  - 验证：`swift test --package-path swift --filter 'AttoConfigurationSettingsMigrationFeedbackTests|AttoConfigurationSettingsTests|AttoConfigurationSettingsSelectorTests|AttoSettingsSchemaPageTests|AttoRuntimeConfigurationSettingsTests|AttoEditorSettingsCommandTests|AttoEditorPreferencesApplicationTests'`

## 阶段 10：Result Envelope、错误模型与 Host Capability

### 目标

完成剩余 JSON result envelope 覆盖、错误模型统一和 host capability negotiation。

### 剩余任务

- [x] 找出仍只走 raw JSON 的主路径并补 typed result envelope。
  - 交付：为 workspace file list、project file index refresh/snapshot/query 和 workspace file replacement 增加 UI FFI `_envelope_json` 导出、Swift typed envelope wrapper、append-only capability bit 和 ABI 文档；旧 raw JSON API 保留为兼容入口。
  - 验证：`cargo test -p editor-core-ui-ffi --lib`
  - 验证：`cargo build -p editor-core-ui-ffi`
  - 验证：`swift test --package-path swift --filter 'EditorCoreUIFFIWorkspaceFileTests|EditorCoreUIFFIRuntimeSmokeTests|EditorCoreUIFFIRuntimeCompatibilityTests|AttoRuntimeCompatibilityTests'`
  - 验证：`swift test --package-path swift --filter 'testMultiDocumentWorkspaceFile|testMultiDocumentProjectFileIndex|testLoadsLibraryAndVersion|testRuntimeInfoJSONDescriptorsCoverKnownFeatures'`
- [x] 统一 Rust、C ABI、Swift wrapper 和 App 层错误模型。
  - 交付：补齐 UI FFI `EcuStatus` C ABI 枚举和 Rust 单一映射源，使 `EcfStatus` / `EcuStatus` 共享数值与 JSON `error.code` label；Swift headless/UI wrapper 暴露统一 `abiLabel`，App 可见错误描述携带 ABI 符号与共享 label；更新 ABI 文档。
  - 验证：`cargo test -p editor-core-ui-ffi ffi_status_labels_match_shared_error_model`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`swift test --package-path swift --filter EditorCoreFFIErrorModelTests`
  - 验证：`cargo test -p editor-core-ui-ffi --lib`
- [x] 建立 host capability negotiation：feature availability、version、unsupported reason、runtime feature flag。
  - 交付：为 headless/UI Swift wrapper 增加 per-feature runtime negotiation 结果，统一 `available` / `unsupported` / `version_mismatch` / `runtime_unavailable` 状态；每个结果携带 runtime version、minimum ABI、runtime feature mask、请求 feature flag、descriptor 和 unsupported reason；Atto App 层 runtime report 接入同一 negotiation 模型；更新 ABI 文档。
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`swift test --package-path swift --filter 'EditorCoreFFIRuntimeCompatibilityTests|EditorCoreUIFFIRuntimeCompatibilityTests'`
  - 验证：`swift test --package-path swift --filter AttoRuntimeCompatibilityTests`
- [x] 清理或隔离过渡 raw JSON API。
  - 交付：保留 C ABI/raw Swift 兼容入口，但将 workspace file search/list、project file index 和 workspace file replacement 的旧 raw/decoded Swift wrapper 标为 deprecated；新增 envelope value typed helper，并把 Atto App 与相关测试迁移到 envelope 主路径。
  - 验证：`swift test --package-path swift --filter 'testMultiDocumentWorkspaceFile|testMultiDocumentProjectFileIndex'`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testQuickOpenUsesCoreWorkspaceFileListWhenAvailable`
  - 验证：`git diff --check`

## 阶段 11：Tree-sitter + LSP 语言体验

### 目标

产品化 Tree-sitter + LSP 主路线的高亮、outline、folding、语言模式和降级体验。

### 剩余任务

- [x] 明确 Tree-sitter highlighting、LSP semantic tokens、diagnostics、symbols、folding ranges 的优先级和 fallback。
  - [x] 新增 `AttoLanguageExperiencePolicy`，用可测试模型定义 highlighting、semantic tokens、diagnostics、symbols、folding 的主来源与 fallback：LSP semantic tokens / LSP diagnostics-symbols-folding、Tree-sitter highlighting/folds、Sublime baseline 和 plain text/unavailable。
  - [x] 状态栏 language source tooltip 展示当前 feature 归属和 fallback 链路；tab 记录 LSP、Tree-sitter、Sublime 降级原因，LSP semantic tokens 缺失时显示 Tree-sitter fallback 是否生效。
  - 验证：`swift test --package-path swift --filter AttoLanguageSourceIndicatorTests`
  - 验证：`swift test --package-path swift --filter AttoStatusBarSelectionTests/testStatusBarShowsLanguageSourceIndicator`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(ProjectLspAutoStartUsesCoreStartPlanLanguageFilter|ShutdownLspServerInActiveTabRequiresCoreStopPlanMatch)'`
  - 验证：`git diff --check`
- [x] 产品化 language mode 切换、parser/server 不可用、大文件、binary/invalid UTF-8 的降级体验。
  - [x] 新增 `AttoDocumentLoadPolicy`，统一检测大文件、binary NUL 和 invalid UTF-8；打开/重载时按结果降级到 Plain Text，禁用 LSP、Tree-sitter、Sublime 和 language mode selector，并把原因暴露到 status bar tooltip。
  - [x] parser/server 不可用路径保留 Plain Text fallback，并将 No LSP server、Tree-sitter parser unavailable、No Sublime syntax fallback 的原因传到 tab/status bar。
  - 验证：`swift test --package-path swift --filter AttoDocumentLoadPolicyTests`
  - 验证：`swift test --package-path swift --filter AttoLanguageFallbackExperienceTests`
  - 验证：`git diff --check`
- [x] 补齐 outline、folding、高亮、diagnostics 和 status bar 的跨语言测试。
  - [x] 新增 `AttoLanguageCrossLanguageExperienceTests`，用 Rust/LSP semantic、Swift/LSP + Tree-sitter fallback、Markdown/Sublime baseline 三种语言来源覆盖 diagnostics、folding、semantic highlighting、document symbols/workspace outline 和 status bar tooltip。
  - 验证：`swift test --package-path swift --filter AttoLanguageCrossLanguageExperienceTests`
  - 验证：`git diff --check`

## 阶段 12：Workspace Search / Project Index / Session

### 目标

完成 core-backed workspace search、project index、replace-in-files、recent 和 session 工作流。

### 剩余任务

- [x] 将 workspace search、replace-in-files 和 project index 统一到 core-backed 数据源。
  - [x] Find in Files workspace scope 使用 core workspace search envelope；Replace in Files 使用 core workspace file replacement WorkspaceEdit envelope；Quick Open/project file list 使用 core project file index / workspace file list。
  - [x] Find in Files workspace provider 改为显式 `.results` / `.unavailable` / `.failed`，旧 runtime 仅在 unavailable 时 fallback，本机 core search 失败时不再悄悄混用 Swift 本地逐文件搜索。
  - 验证：`swift test --package-path swift --filter AttoFindInFilesWorkspaceSearchProviderTests`
  - 验证：`swift test --package-path swift --filter 'AttoEditorCommandTests/test(FindInWorkspaceFilesUsesCoreWorkspaceSearch|QuickOpenUsesCoreWorkspaceFileListWhenAvailable)'`
  - 验证：`swift test --package-path swift --filter testFindInFilesWorkspaceReplaceUsesCoreWorkspaceEditTransaction`
- [x] 支持 ignored files、binary files、large files、pagination、cancellation 和 result refresh。
  - [x] 新增 core-owned `WorkspaceFileScanOptions` / `WorkspaceFileScanSummary`，workspace file list/search/replacement 共用 ignore walker、include/exclude globs、分页 offset/max、二进制/invalid UTF-8 跳过、大文件跳过和取消预算。
  - [x] 新增 UI FFI scan-options envelope 入口和 feature bit，Swift wrapper 解码 `scan` summary；旧 include/exclude/max envelope 保持兼容。
  - [x] Find in Files、Replace in Files 和 Quick Open/project file list 在新 runtime 上优先消费 scan-options envelope，旧 runtime 保留原 envelope fallback。
  - 验证：`cargo check -p editor-core-ui-ffi`
  - 验证：`cargo test -p editor-core-ui multi_document_workspace_file_search_uses_core_scan_policy`
  - 验证：`cargo test -p editor-core-ui-ffi ffi_multi_document_workspace_file_scan_options_report_summary`
  - 验证：`cargo test -p editor-core-ui-ffi ffi_feature_flags_include_semantic_tokens_requests`
  - 验证：`cargo test -p editor-core-ui-ffi ffi_runtime_info_json_reports_version_and_feature_descriptors`
  - 验证：`cargo build -p editor-core-ui-ffi --release`
  - 验证：`swift test --package-path swift --filter testMultiDocumentWorkspaceFileScanOptionsExposeSummary`
  - 验证：`swift test --package-path swift --filter EditorCoreUIFFIRuntimeCompatibilityTests`
  - 验证：`swift test --package-path swift --filter AttoRuntimeCompatibilityTests`
  - 验证：`swift test --package-path swift --filter testLoadsLibraryAndVersion`
  - 验证：`swift test --package-path swift --filter testRuntimeInfoJSONDescriptorsCoverKnownFeatures`
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`
- [x] 让 Find in Files、Quick Open、recent files/projects 和 session restore 消费同一套 core-backed 数据源。
  - [x] 新增 `AttoWorkspaceDataSource`，集中封装 core-backed workspace 文件列表/查询、recent files/projects、session workspace root 与本地 fallback，窗口上下文只保留 provider wiring 和 UI cache 同步。
  - [x] Find in Files workspace 文件 provider、Quick Open、recent files/projects 和 session snapshot/restore 都通过同一 data source 读取 core-backed 状态。
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceRecentRootTests`
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testQuickOpenUsesCoreWorkspaceFileListWhenAvailable`
  - 验证：`swift test --package-path swift --filter AttoFindInFilesWorkspaceSearchProviderTests`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceSessionRestoreTests`
  - 验证：`git diff --check`

## 阶段 13：Visual Baselines 与黑盒自动化

### 目标

合入首批经批准机器生成的 PNG baselines，并让 CI 在 PNG 合入后自动执行 strict PR 门禁。

### 剩余任务

- [x] 生成、审核并提交首批 PNG golden baselines。
  - [x] 通过 `swift/scripts/update-visual-baselines.sh` 生成 39 个 manifest 声明的 PNG baselines。
  - [x] 修复 visual snapshot harness：PNG 读回保留写出的 RGBA bytes，AppKit capture 额外合成 `EditorCoreSkiaView` 的 CPU raster，避免 Metal-backed editor 正文在基线中空白。
  - [x] 抽样审核 editor chrome、floating popup 和 WorkspaceEdit 失败摘要 PNG，确认正文/浮层/状态内容可见且 strict 可重复。
  - 验证：`swift test --package-path swift --filter AttoEditorVisualSnapshotHarnessTests`
  - 验证：`swift/scripts/update-visual-baselines.sh`
  - 验证：`swift/scripts/check-visual-baselines.sh`
  - 验证：`git diff --check`
- [x] PNG 合入后确认 strict visual baseline PR 门禁默认生效。
  - [x] `.github/workflows/visual-baselines.yml` 的 PR 条件会在检测到任意 checked-in `VisualBaselines/*.png` 后跳过 smoke，改跑 `swift/scripts/check-visual-baselines.sh`。
  - [x] 本地检测命令已返回 `has_png=true`，当前 39 个 PNG baseline 会触发 strict PR 路径。
  - 验证：`baseline_png="$(find swift/Tests/AttoEditorTests/Resources/VisualBaselines -type f -name '*.png' -print -quit)"; test -n "$baseline_png"`
  - 验证：`swift/scripts/check-visual-baselines.sh`
  - 验证：`git diff --check`
- [x] 扩展 WorkspaceEdit rollback secondary failure、更多 conflict/failure 边界和跨 theme/window-size fixtures。
  - [x] 新增 light+narrow 二次 rollback failure preview baseline，覆盖 `secondary_rollback_failure`、`blocks_atomic_apply` 和人工恢复建议元数据。
  - [x] 新增 dark+wide 混合冲突 preview baseline，覆盖 dirty document、version mismatch 和 overlapping text edits 的 atomic apply 阻断路径。
  - 验证：`swift test --package-path swift --filter AttoEditorVisualBaselineManifestTests`
  - 验证：`swift/scripts/update-visual-baselines.sh`
  - 验证：`swift/scripts/check-visual-baselines.sh`
  - 验证：`git diff --check`
- [x] 扩展 opt-in `XCUIApplication` smoke tests：真实 LSP server、多文件 workspace、多 root/project session、server 错误/延迟/重启后的 panels。
  - [x] 新增真实 Python LSP fixture：记录 `initialize` / `workspaceFolders` / `didOpen` / request events，支持多文档 symbol、delayed workspace symbol、JSON-RPC error 和重启进程计数。
  - [x] 新增多文件 workspace 黑盒场景：目录窗口通过 Quick Open 打开两份 `.rs` 文件，真实 `documentSymbol` 聚合进 Workspace Outline，并通过 Workspace Symbol Search 发出真实 `workspace/symbol`。
  - [x] 新增多 root/project session 黑盒场景：两个 project root 各自启动真实 LSP session，覆盖 delayed workspace symbol、`documentSymbol` server error、Project Status Events panel 和手动 restart lifecycle。
  - 验证：`swift test --package-path swift --filter AttoEditorXCUIApplicationSmokeTests`
  - 验证：`swift/scripts/build-attoeditor-app.sh --debug --out /tmp/attoeditor-xcui-advanced`
  - 受限验证：`ATTO_XCUI_SMOKE_TESTS=1 ATTO_XCUI_APP_PATH=/tmp/attoeditor-xcui-advanced/AttoEditor.app swift test --package-path swift --filter testRealLspServerMulti` 当前 SwiftPM unit-test 环境返回 `Device is not configured for UI testing`，无法实际执行 `XCUIApplication`。

## 阶段 14：Sublime-like UI 打磨

### 目标

在测试保护下打磨 Sublime-like chrome、minimap、gutter、overlay、focus 和编辑交互。

### 剩余任务

- [x] 打磨 tab bar、sidebar、status bar、quick panel、completion popup、find/replace、split panes、minimap 和 gutter marker。
  - [x] tab chip 增加最大宽度和中间截断；status bar 右侧状态、语言选择和文件信息在窄窗口下保持边界稳定。
  - [x] find/replace 搜索和替换字段改为 min/preferred/max 宽度约束，clear action 使用图标按钮并补齐 toggle tooltips。
  - [x] quick panel 和 completion popup 根据窗口/屏幕可见区域收缩，并同步 table column、completion list 和 preview 宽度。
  - [x] 新增阶段 14 chrome polish layout 测试，覆盖窄 editor area、浮层 panel、窗口级 sidebar + minimap + gutter marker 组合边界。
  - 验证：`swift test --package-path swift --filter AttoEditorChromePolishLayoutTests`
  - 验证：`swift test --package-path swift --filter AttoEditorVisualLayoutTests`
  - 验证：`swift test --package-path swift --filter EditorCoreSkiaMinimapTests`
  - 验证：`swift test --package-path swift --filter EditorCoreSkiaViewGutterWidthTests`
- [x] 覆盖窄窗口、多 pane、长文件、多 cursor、diagnostics、folding、semantic overlays 的布局与视觉测试。
  - [x] 新增 `editor-chrome-dark-long-file-minimap-overlays` visual baseline，覆盖 96 行长文件、collapsed fold、multi-cursor selection、diagnostic marker 和 minimap density。
  - [x] 新增 `AttoEditorVisualBaselineCoverageTests`，显式断言 manifest 至少覆盖窄窗口、多 pane、长文件、多 cursor、diagnostics、folding 和 semantic overlays。
  - [x] 重新生成并 strict 校验受 chrome layout clamp 影响的 editor chrome / completion popup PNG baselines。
  - 验证：`swift test --package-path swift --filter AttoEditorVisualBaselineCoverageTests`
  - 验证：`swift test --package-path swift --filter AttoEditorVisualBaselineManifestTests/testVisualBaselineManifestDeclaresRunnableFixtures`
  - 验证：`swift/scripts/update-visual-baselines.sh`
  - 验证：`swift/scripts/check-visual-baselines.sh`
  - 验证：`git diff --check`
- [x] 修复 focus、keyboard navigation、selection、hover、scroll、overlay stacking 的产品细节。
  - [x] completion popup 显式 dismiss 后恢复触发它的 editor view 焦点；窗口自然失焦路径不抢回焦点。
  - [x] 新增 AppKit interaction regression，覆盖 completion popup child-window stacking、dismiss 后移除和 editor focus restore。
  - [x] 复跑 keyboard navigation、selection、hover、command-hover 和 keyboard-scroll focused tests，确认底层编辑交互不回退。
  - 验证：`swift test --package-path swift --filter AttoEditorInteractionPolishTests`
  - 验证：`swift test --package-path swift --filter AttoEditorChromePolishLayoutTests`
  - 验证：`swift test --package-path swift --filter EditorCoreSkiaViewKeyboardScrollTests`
  - 验证：`swift test --package-path swift --filter EditorCoreSkiaViewNavigationTests`
  - 验证：`swift test --package-path swift --filter EditorCoreSkiaViewHoverTests`
  - 验证：`swift test --package-path swift --filter EditorCoreSkiaViewCommandHoverTests`
  - 验证：`git diff --check`

## 阶段 15：最终审计与全量验证

### 目标

完成最终文档审计、ABI/README 更新、过渡 API 清理和全量验证。

### 剩余任务

- [x] 更新 `docs/abi-v1-draft.md`、crate README、Swift package README 和 App 使用说明。
  - [x] 根 README 补齐 `editor-core-ui` / `editor-core-ui-ffi` workspace crate 描述。
  - [x] `swift/README.md` 补充 AttoEditor 当前 core-owned App 能力边界、visual baseline 更新/strict 校验入口和 strict PR 语义。
  - [x] `docs/abi-v1-draft.md` 与 `crates/editor-core-ui-ffi/README.md` 补充 Swift/AppKit runtime negotiation、core-owned workspace facts、legacy fallback 和 host-only UI contract。
  - [x] `SWIFT-GAPS.md` 移除已完成阶段 14，仅保留阶段 15 剩余边界。
  - 验证：阶段 15 文档审计关键词检查通过，覆盖旧阶段、旧 UI 名称和开放状态词。
  - 验证：`git diff --check`
- [x] 清理过渡 API、重复状态源、临时 helper、旧 feature flag 和未使用测试 fixture。
  - [x] 移除 `MultiDocumentEditorUI` 中已迁移到 envelope 主路径、且无调用点的 deprecated Swift workspace-file raw/decoded convenience wrappers；底层 C ABI legacy JSON 符号继续保留为运行时兼容入口。
  - [x] 审计 visual fixture / PNG baseline 与 manifest 的双向引用，确认没有未使用或缺失资源。
  - 验证：`ruby -rjson -e 'root="swift/Tests/AttoEditorTests/Resources"; manifest=JSON.parse(File.read(File.join(root,"VisualBaselines/manifest.json"))); fixtures=manifest.fetch("cases").flat_map{|c| [c["fixture"], c["activeFixture"], *(c["additionalFixtures"]||[])]}.compact.uniq; baselines=manifest.fetch("cases").map{|c| c.fetch("baseline")}.uniq; actual_fixtures=Dir[File.join(root,"VisualFixtures","*")].select{|p| File.file?(p)}.map{|p| p.sub(root+"/","")}.sort; actual_baselines=Dir[File.join(root,"VisualBaselines","*.png")].select{|p| File.file?(p)}.map{|p| p.sub(root+"/","")}.sort; abort("visual resource mismatch") unless (actual_fixtures-fixtures).empty? && (fixtures-actual_fixtures).empty? && (actual_baselines-baselines).empty? && (baselines-actual_baselines).empty?'`
  - 验证：`! rg -n "@available\(\*, deprecated" swift/Sources/EditorCoreUIFFI/MultiDocumentEditorUI.swift`
  - 验证：`swift test --package-path swift --filter MultiDocumentWorkspaceFile`
  - 验证：`swift test --package-path swift --filter AttoCoreWorkspaceRecentRootTests`
  - 验证：`git diff --check`
- [x] 运行全量 Rust、Swift、AppKit、visual 和 opt-in smoke 验证。
  - [x] 修复未保存 untitled session 恢复路径：`openFile(..., isUntitled: true)` 现在通过空文本创建内存文档，不再尝试读取不存在的占位文件。
  - [x] `swift test --package-path swift --list-tests` 枚举 947 个 Swift 测试；当前 AppKit-heavy 单进程 `swift test --package-path swift` 仍会触发 XCTest `signal 11`，因此用小批次和单测尾部分片覆盖同一 test list。
  - 验证：`cargo test`
  - 受限验证：`swift test --package-path swift` 已尝试；当前环境中全量单一 XCTest 进程以 `xctest ... exited with unexpected signal code 11` 退出。
  - 验证：`ruby ... target/swift-split-tests-small` 分片运行 `swift test --package-path swift --list-tests` 的完整列表；非 command 批次和 `AttoEditorCommandTests` 前 28 个小块通过，失败批次后的 command 测试降到单测粒度后全部通过。
  - 验证：`swift test --package-path swift --filter AttoEditorCommandTests/testSessionSnapshotRestoresUnsavedUntitledBuffers`
  - 验证：`swift test --package-path swift --filter AttoSessionStoreTests`
  - 验证：`swift/scripts/check-visual-baselines.sh`
  - 验证：`swift/scripts/build-attoeditor-app.sh --debug --out /tmp/attoeditor-final-xcui`
  - 受限验证：`ATTO_XCUI_SMOKE_TESTS=1 ATTO_XCUI_APP_PATH=/tmp/attoeditor-final-xcui/AttoEditor.app swift test --package-path swift --filter AttoEditorXCUIApplicationSmokeTests` 在当前 SwiftPM unit-test bundle 中返回 `Device is not configured for UI testing`。
  - 验证：`swift test --package-path swift --filter AttoEditorXCUIApplicationSmokeTests` 默认 opt-in smoke 跳过并通过。
  - 验证：`cargo fmt --check`
  - 验证：`git diff --check`
- [x] 将仍未完成的内容明确标为 out-of-scope 或 deferred，并从本计划中移除。
  - [x] `SWIFT-GAPS.md` 只保留 SwiftPM 单进程 XCTest `signal 11` 和 opt-in `XCUIApplication` UI-test runner 两个 deferred/out-of-scope 项。
  - [x] `PLAN.md` 顶部阶段状态全部收敛为 `[已完成]`，不再保留开放状态项。
  - 验证：`ruby -e 'blocked=["TO"+"DO","待"+"办","进"+"行中","当前只"+"剩阶段","尚未"+"完成的目标","阶段 15："+"最终审计与收敛"]; files=%w[PLAN.md SWIFT-GAPS.md]; hits=files.flat_map{|f| text=File.read(f); blocked.select{|s| text.include?(s)}.map{|s| "#{f}:#{s}"}}; abort(hits.join("\n")) unless hits.empty?'`
  - 验证：`git diff --check`
