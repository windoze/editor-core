# PLAN: 剩余 Swift gaps 实施计划

完整历史计划和已完成提交记录已归档到 `docs/archive/2026-08-04-swift-gaps-1/PLAN.md`。

## TODO（未完成任务）

- [已完成] 阶段 4：完成 WorkspaceEdit conflict 检测、解决语义和跨请求/project 重试归属。
- [已完成] 阶段 5：完成 tab、split、project、session 和 LSP ownership 向 core workspace 模型迁移。
- [进行中] 阶段 6：完成 core-owned project/LSP lifecycle schema、server ownership、恢复策略和 dashboard 产品化。
- [已完成] 阶段 7：完成跨 tab/project result panels、统一 dock/workbench 容器和刷新/过期策略。
- [已完成] 阶段 8：完成 Sublime-like command/keymap 行为矩阵、keymap 文件兼容和 snippets/macros/build systems 边界。
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

- [ ] 将 LSP start/restart/stop/shutdown 的实际执行 ownership 下沉为 core-owned typed lifecycle。
  - [x] 让 core-owned start/stop/restart plan entries 显式携带 `operation` 字段，并同步 Rust、FFI JSON、Swift wrapper 和 ABI draft，作为统一 lifecycle action descriptor 的基础。
  - [x] 将 Swift Project LSP lifecycle outcome 记录收敛到统一 action descriptor，并让 auto-start、manual restart/shutdown、project restart/shutdown、auto-restart、tab close 和 language-change stop 复用 core plan entry 的 operation / workspace roots / active view metadata。
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
