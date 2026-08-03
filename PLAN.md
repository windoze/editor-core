# PLAN: 完整实现 SWIFT-GAPS.md

本文是执行 `SWIFT-GAPS.md` 中所有剩余目标的工程计划。目标不是一次性堆功能，而是把 Swift/AppKit/Skia 产品层、Swift FFI binding、`editor-core-ui`、`editor-core-ui-ffi`、`editor-core-ffi` 与 `editor-core-*` 的能力边界逐步收敛到同一个模型中，并在每个阶段留下可验证、可回滚、可审计的提交。

## 总目标

- Swift 产品层可以完整、类型化、可测试地使用 `editor-core-*` 已有能力。
- 多文档、tab、split、workspace、project、session、LSP lifecycle 等状态归属收敛到 `editor-core` / `editor-core-ui` 的 workspace / `MultiDocumentEditorUi` 模型。
- Swift/AppKit 层只负责平台 UI 表现、用户输入、菜单/keymap 接线、持久化桥接和命令转发，不再长期维护一套独立的 workspace/tab/session 事实源。
- LSP、Tree-sitter、derived-state、diagnostics、WorkspaceEdit、result panels、command/keymap 等能力从“能走 raw JSON”推进到“有稳定 ABI、Swift typed wrapper、App 主路径消费、测试覆盖”。
- 建立 macOS native UI 自动化、视觉回归和 renderer pixel 测试体系，服务 “Sublime Text 复刻” 的外观、布局和操作验收。
- `SWIFT-GAPS.md` 中只剩明确 out-of-scope 或 deferred 的项目；其中 Sublime syntax 扩展明确不在本轮目标内。

## 非目标

- 不扩展 `.sublime-syntax` 语法兼容能力。AttoEditor 的语言语义、结构化高亮和智能能力以 Tree-sitter 与 LSP 为主线；Sublime syntax 支持以现有 `editor-core-sublime` 为基线。
- 不在 Swift/AppKit 层扩展一套长期独立的 workspace、tab、session、project 或 multi-document 引擎。
- 不用 UI-only 状态绕过 core 已经可以拥有的编辑器状态、LSP 状态、derived-state 或 workspace 状态。
- 不把 raw JSON escape hatch 当作最终完成标准。raw JSON 可以作为兼容层保留，但主路径要有 typed API 和测试。
- 不把所有 Sublime 产品功能都算作 Rust core 缺口；需要区分 core 能力、binding 投影、App 产品化和测试体系。

## 当前基线

- `SWIFT-GAPS.md` 已记录当前 Swift 路径是“主流程可用、完整能力映射不足”，不是不可用。
- 已完成大量阶段：基础 JSON command dispatcher、Swift typed command convenience、App command palette/menu/keymap 起点、derived-state snapshot、LSP raw request/take、LSP result lifecycle、request lifecycle、diagnostics lifecycle、多文档 core mirror 起点、多个 LSP result family 的 typed payload wrapper 和 App 主路径消费。
- 当前仍有一组 semantic tokens 相关 WIP 改动在工作区中，尚未格式化、构建、测试、文档化或提交。该 WIP 属于后续“阶段 1”，不能混入本计划文档提交。
- 本文档提交后，后续每个实现阶段都应单独提交。阶段内可以有多次小提交，但阶段完成时必须有明确提交边界和验证记录。

## 执行原则

- 每个阶段先做小范围 audit，再改代码，再补测试，再更新文档，再提交。
- 优先沿用现有 crate/module/Swift wrapper 风格，避免为了拆阶段引入平行体系。
- ABI 变更必须同步更新 Rust FFI、C header、Swift wrapper、runtime feature flag 或 compatibility test。
- App 主路径必须消费 typed API；raw JSON helper 只保留给兼容、测试或 escape hatch。
- 新增状态事实源时优先放在 core / `editor-core-ui` / `MultiDocumentEditorUi`，Swift 只做 projection 和 UI binding。
- 对 UI 行为改动，至少补 AppKit component test；对可视外观、布局或 renderer 行为，补截图/pixel/AX 测试。
- 每个阶段提交前至少运行 targeted tests；跨 ABI 或 App 主路径阶段还要运行 Swift targeted tests；里程碑阶段运行更大的 test set。
- 每个提交都必须在本文件的对应阶段章节中注明所属任务、提交边界和验证记录；`SWIFT-GAPS.md` 只作为任务范围参考与 gap 状态审计，不作为提交索引或执行计划来源。

## 阶段 0: 基线冻结与缺口矩阵

### 目标

把 `SWIFT-GAPS.md` 中的剩余目标整理成可跟踪矩阵，避免后续实现时漏项或重复造模型。

### 主要交付

- 建立一张 “gap -> owner layer -> Rust API -> C ABI -> Swift typed API -> App consumer -> tests -> status” 矩阵，可放在 `SWIFT-GAPS.md` 或单独文档中。
- 标记已经完成但仍需复验的项目，例如阶段 148-160 的 LSP typed payload families。
- 标记必须迁移到 core workspace 模型的 Swift-only 过渡状态。
- 标记 out-of-scope 项：Sublime syntax 扩展不纳入验收。

### 验证

- `SWIFT-GAPS.md` 中每个 remaining gap 都能映射到后续某个阶段。
- 对已经完成的项目，能指向已有 tests 或提交记录。

### 提交

- `docs: map remaining swift gaps`
- 文档执行约束维护：声明后续提交归属必须记录在 `PLAN.md` 对应阶段章节，`SWIFT-GAPS.md` 仅保留为任务范围参考和 gap 状态审计；提交边界为文档规则更新，验证记录为 `git diff --check`。

## 阶段 1: Semantic Tokens typed payload 与主路径消费

### 目标

补齐 LSP typed payload family 中最后一个关键缺口：semantic tokens。完成后，Swift 侧可以类型化请求、获取、应用 semantic tokens full / delta / range result。

### 主要交付

- `editor-core-ui`：
  - 补齐 `textDocument/semanticTokens/full` manual request/take。
  - 补齐 `textDocument/semanticTokens/full/delta` manual request/take。
  - 补齐 `textDocument/semanticTokens/range` manual request/take。
  - 将 response method 正确映射到 result slot。
  - 对 `null`、full tokens、delta edits、range tokens、error/stale 情况保持现有 lifecycle/event 语义。
- `editor-core-ui-ffi`：
  - 新增 C ABI request/take 函数。
  - 更新 public header。
  - 补 runtime feature flag。
- Swift `EditorCoreUIFFI`：
  - 新增 `EcuLspSemanticTokensResult`、delta edit、shape enum、apply helper。
  - 新增 `EditorUI.lspRequestSemanticTokensFull` / `Delta` / `Range`。
  - 新增 typed take wrapper。
  - 保留 raw JSON take API。
- App：
  - 让 semantic tokens 刷新路径优先消费 typed payload。
  - full result 更新 baseline，delta result 可在 baseline 上应用，range result 可局部投影。
  - 失败、空结果和 server 不支持时有清晰降级。

### 验证

- Rust tests 覆盖 full / delta / range request/take、slot mapping、empty/error/stale。
- C ABI tests 覆盖 null pointer、empty result、JSON ownership。
- Swift tests 覆盖 typed decode、delta apply、raw JSON compatibility、runtime feature flag。
- App tests 覆盖 semantic tokens typed result 到 derived-state / highlighting store 的主路径。

### 提交

- `feat(swift): type semantic tokens lsp payloads`

## 阶段 2: LSP result family 完整性复验与统一错误展示

### 目标

把所有已完成 typed LSP result family 做一致性复验，并补齐用户可见错误、空结果、超时、取消和 stale 展示策略。

### 主要交付

- 建立 LSP result family coverage table，覆盖：
  - completion / completion resolve
  - locations: definition / declaration / type definition / implementation / references
  - prepare rename / rename
  - code action / code action resolve
  - document symbols / workspace symbols
  - signature help
  - hover
  - formatting / range formatting / on-type formatting
  - document color / color presentation
  - call hierarchy / type hierarchy
  - diagnostics pull / publish diagnostics projection
  - selection range
  - linked editing
  - code lens / code lens resolve
  - folding ranges
  - semantic tokens
  - inlay hints
  - document links
- 为每个 family 明确：
  - request API
  - take API
  - typed payload
  - App consumer
  - lifecycle events
  - empty/error/stale UI behavior
  - tests
- App 层统一 LSP result feedback：
  - status bar 短反馈。
  - command palette / quick panel 空结果提示。
  - result panel 中保留错误、取消、超时、stale 元数据。
  - 避免每个 feature 手写一套轮询和错误处理。

### 验证

- Swift typed payload tests 覆盖所有 result family 的 unknown enum fallback 和 raw payload preservation。
- App tests 覆盖 error/empty/timeout/cancel/stale 的统一反馈。
- `SWIFT-GAPS.md` 更新 result family coverage 状态。

### 提交

- `feat(swift): unify lsp result feedback`

## 阶段 3: 状态变更订阅与 event drain 模型

### 目标

补齐当前 “只能按 after sequence 轮询若干事件” 的不足，为 Swift/host 提供统一 state-change subscription / drain 模型，使 App 可以稳定消费 core state changes。

### 主要交付

- `editor-core-ui`：
  - 定义统一 `EditorUiStateEvent` 或等价 envelope。
  - 覆盖编辑文本、selection、viewport、layout、dirty、diagnostics、derived-state stale/refresh、LSP request/result lifecycle、workspace/tab changes。
  - 提供 bounded event log、latest sequence、drain after sequence。
  - 保留现有 family-specific events，并投影到统一事件流。
- `MultiDocumentEditorUi`：
  - 聚合 tab/view/workspace 级 state events。
  - 为事件附加 tab id、view id、pane index、document URI、workspace root metadata。
- FFI：
  - C ABI 提供 latest sequence / events JSON / drain API。
  - Swift wrapper 提供 typed event model。
- App：
  - 用统一 event stream 驱动 Problems、Outline、Symbols、Locations、status bar、dirty badges、tab badges、semantic highlighting refresh、minimap/gutter markers。
  - 减少 scattered polling。

### 验证

- Rust tests 覆盖 sequence 单调性、bounded retention、multi-document aggregation、unknown/future event compatibility。
- Swift tests 覆盖 typed event decode、after sequence、empty drain、runtime feature flags。
- App tests 覆盖由 event stream 驱动的 status bar、diagnostics panel、tab dirty marker。

### 提交

- `feat(ui): add unified state event stream`

## 阶段 4: Core-owned WorkspaceEdit 跨文件事务

### 目标

把 rename、code action、completion additional edits、formatting 和 resource operations 从 App 侧分散应用推进到 core workspace-owned transaction，覆盖打开/未打开文件、dirty、undo、snapshot 和失败回滚语义。

### 主要交付

- `editor-core` / workspace：
  - 定义 `WorkspaceEditTransaction`。
  - 支持 `changes`、`documentChanges`、`TextDocumentEdit`、version check。
  - 支持 `create` / `rename` / `delete` resource operations。
  - 支持 opened buffer、unopened local file、unsupported URI 的分流。
  - 定义 partial failure、atomic failure、preview-only、apply modes。
  - 定义 dirty state、undo grouping、snapshot version、conflict detection。
- `editor-core-ui`：
  - 提供 apply/preview WorkspaceEdit API。
  - 返回 typed summary：applied、skipped、failed、created、renamed、deleted、dirty documents、conflicts。
  - 将 transactions 纳入 state event stream。
- FFI / Swift：
  - 提供 typed `EcuWorkspaceEditTransactionResult`。
  - 让 rename/code action/completion/code lens command 等主路径调用 core-owned apply。
- App：
  - WorkspaceEdit preview panel 展示跨文件影响。
  - 用户确认后由 core transaction apply。
  - 失败或冲突时展示具体文档和原因。

### 验证

- Rust tests 覆盖 opened docs、unopened file URI、resource ops、version mismatch、partial failure、undo/dirty semantics。
- Swift tests 覆盖 typed summary decode 和 App 主路径调用。
- App tests 覆盖 rename/code action 跨文件 preview 和 apply。

### 提交

- `feat(core): own workspace edit transactions`
- 中间提交：`feat(ui): apply unopened workspace resource operations`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；把未打开本地文件的 `create` / `rename` / `delete` resource operations 纳入 `MultiDocumentEditorUi` transaction，并允许 create/rename 产生的新 URI 继续应用后续 text edits。
  - 提交边界：只扩展 Rust `MultiDocumentEditorUi` transaction 的 root-gated 本地文件 side effect、未打开源文件 rename 到已打开 target URI 的 conflict skip、C ABI JSON 路径测试和 Swift typed wrapper 端到端测试；不新增 ABI 函数；不把 AttoEditor rename/code action/completion 主路径切换到 core apply；不改变已打开 tab resource operation 的既有语义。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo test -p editor-core-ui-ffi`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAppliesUnopenedWorkspaceFileResourceOperations`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAppliesUnopenedWorkspaceFileTextEdits`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `git diff --check`
- 中间提交：`feat(ui): preserve workspace edit document change order`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 `MultiDocumentEditorUi` transaction 按 `WorkspaceEdit.documentChanges` 顺序交错执行 text edits 和 resource operations，而不是先执行全部 resource operations 再按 URI 批量执行 text edits。
  - 提交边界：只调整 Rust transaction 内部 step planning/apply 顺序，补 planned resource URI state 支持前序 create/delete/rename 对后续 resource operation 预检的影响，并覆盖 C ABI JSON 和 Swift typed wrapper 测试；不新增 ABI 函数；不引入 atomic rollback / undo grouping；不切换 AttoEditor App 主路径。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo test -p editor-core-ui-ffi`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAppliesWorkspaceEditDocumentChangesInOrder`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `git diff --check`
- 中间提交：`feat(ui): roll back workspace edit filesystem failures`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；为 root-gated 未打开本地文件 resource operations 增加运行时 filesystem error rollback 起点，避免前序 create / overwrite rename / delete 在后续本地 I/O 错误后留下已应用的磁盘副作用。
  - 提交边界：只在 `MultiDocumentEditorUi` apply 路径内记录未打开本地文件 resource operation 的文件系统补偿动作；create 会记录新路径和新建父目录，overwrite/delete 会用同目录临时 backup，rename 会记录反向 move；发生后续 fatal resource operation 错误时回滚这些文件系统副作用。本提交不实现打开 tab 的 undo 回滚、不回滚已应用 text edits、不提供完整 batch atomic apply mode、不切换 AttoEditor App 主路径。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_rolls_back_unopened_resource_operations_after_runtime_failure`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo test -p editor-core-ui-ffi`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIRollsBackUnopenedResourceOperationsAfterRuntimeFailure`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `git diff --check`
- 中间提交：`feat(ui): apply open-tab workspace resource files`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 `MultiDocumentEditorUi` 对已打开 tab 的本地 `file://` resource operations 在配置了 workspace root 时也执行 root-gated 文件系统副作用，从而为 AttoEditor App 主路径切到 core transaction 关闭最后一段 Swift-only resource operation side effect。
  - 提交边界：只扩展打开 tab 的 `create` / `rename` / `delete` resource operation apply：无 workspace roots 或非本地 URI 时保持既有 in-memory tab 语义；root 内本地路径会复用同一套 filesystem helper 和 rollback log，rename/delete/create overwrite 会更新磁盘，同时继续更新 core tab text/document URI/close state。本提交不切换 AttoEditor App 主路径，不新增 ABI 函数，不实现打开 tab undo 回滚或完整 batch atomic rollback。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_applies_open_tab_resource_operation_filesystem_side_effects`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo test -p editor-core-ui-ffi ffi_multi_document_applies_open_tab_resource_operation_filesystem_side_effects`
    - `cargo test -p editor-core-ui-ffi`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAppliesOpenTabResourceOperationFilesystemSideEffects`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `git diff --check`
- 中间提交：`feat(app): apply workspace edits via core transaction`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；把 AttoEditor `applyWorkspaceEditJSONToActiveTab` / rename / code action / completion additional edit 共享的 WorkspaceEdit App apply helper 主路径切到 `MultiDocumentEditorUI.applyWorkspaceEditTransaction(...)`，并把 Swift-only parser/apply 保留为 core multi-document model 不可用时的兼容 fallback。
  - 提交边界：只切换 App apply helper 的主路径；apply 前把打开 tab 的文本、URI、dirty 和 active view 差异同步到 core transaction，apply 后从 core snapshot/text/dirty/URI/close state 投影回 AppKit tabs；不新增 ABI 函数，不移除旧 Swift fallback，不实现 preview panel 产品化、打开 tab undo grouping、完整 batch atomic rollback 或更深层 conflict UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEdit`
    - `git diff --check`
- 中间提交：`feat(app): confirm workspace edit previews`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 AttoEditor App 在执行 core WorkspaceEdit transaction 前消费 core preview result，并对跨文档、未打开文件、resource operation 或 skipped/conflict 影响展示基础预览确认。
  - 提交边界：只新增 App 层 `AttoWorkspaceEditPreview` display model、同步 AppKit `NSAlert` 确认入口和测试决策 hook；取消时不执行 core apply、不推进 transaction event cursor；单个已打开文档普通 text edit 不弹确认。本提交不实现专用可导航 diff preview panel、打开 tab undo grouping、完整 batch atomic rollback 或更深层 conflict UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEdit`
    - `git diff --check`
- 中间提交：`feat(app): show workspace edit diff previews`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；把 AttoEditor 的 WorkspaceEdit confirmation 从基础 alert 推进到专用可导航 diff preview panel 起点，让跨文档、未打开文件、resource operation 和 skipped/conflict 影响在应用前可按文件查看。
  - 提交边界：只新增 App 层 preview section/diff display model、`AttoWorkspaceEditPreviewPanelController`、稳定 accessibility identifier 和确认入口替换；text edit diff 由 Swift 侧基于当前打开 tab 文本或本地文件文本生成，resource operation/skipped/unsupported 显示结构化详情。本提交不新增 ABI，不实现可筛选/可展开树形 diff、打开 tab undo grouping、完整 batch atomic rollback 或更深层 conflict UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEdit`
    - `git diff --check`
- 中间提交：`feat(ui): roll back unopened workspace text edits`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 `MultiDocumentEditorUi` 对未打开本地文件 text edits 也接入 WorkspaceEdit transaction 的 filesystem rollback log，避免 text edit 已写盘后后续 resource operation fatal error 留下半应用状态。
  - 提交边界：只扩展 root-gated 未打开本地文件 text edit 的 rollback 保护；写入前备份原文件，写入失败时局部恢复，后续 fatal resource operation 失败时随整批 rollback 恢复。本提交不新增 ABI，不改变 preview 语义，不实现打开 tab undo grouping、完整 batch atomic apply mode 或更深层 conflict UI。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_rolls_back_unopened_text_edits_after_runtime_failure`
    - `cargo test -p editor-core-ui-ffi ffi_multi_document_rolls_back_unopened_text_edits_after_runtime_failure`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIRollsBackUnopenedTextEditsAfterRuntimeFailure`
    - `git diff --check`
- 中间提交：`feat(ui): roll back open workspace tabs`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 `MultiDocumentEditorUi` 在 WorkspaceEdit resource operation 运行时 fatal failure 时恢复已经被同一事务修改过的打开 tab 状态，避免打开 tab text edit、rename URI 或 delete close 留下半应用状态。
  - 提交边界：只新增打开 tab rollback log，覆盖打开 tab text edit 前文本/dirty snapshot、create overwrite 文本替换、rename URI 变更、delete close/tab order/active/preview 状态恢复，并把 Rust/C ABI/Swift wrapper 的 fatal failure 回归路径补齐。本提交不新增 ABI，不改变 preview/skipped 语义，不实现用户可见 undo grouping、显式 atomic apply mode 或更深层 conflict UI。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_rolls_back_open_tabs_after_runtime_failure`
    - `cargo test -p editor-core-ui-ffi ffi_multi_document_rolls_back_open_tabs_after_runtime_failure`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIRollsBackOpenTabsAfterRuntimeFailure`
    - `git diff --check`
- 中间提交：`feat(ui): support atomic workspace edit apply`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；为现有 `MultiDocumentEditorUi` WorkspaceEdit JSON transaction API 增加兼容的显式 apply mode，使调用方可选择默认 `partial` 或 envelope 形式的 `atomic` preflight。
  - 提交边界：保留原始 LSP `WorkspaceEdit` 输入作为默认 partial；新增 `{"applyMode":"atomic","workspaceEdit":{...}}` envelope 解析和 result `apply_mode` 字段。atomic apply 在 preflight 已有 skipped/unsupported detail 时不修改任何 tab/文件，返回 `applied=false` 的结构化 result 并记录 transaction event。本提交不新增 C ABI 函数，不改变默认 partial 语义，不实现用户可见 undo grouping 或更深层 conflict UI。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_atomic_workspace_edit_preflight_skips_without_mutating`
    - `cargo test -p editor-core-ui-ffi ffi_multi_document_atomic_workspace_edit_preflight_skips_without_mutating`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAtomicWorkspaceEditPreflightSkipsWithoutMutating`
    - `git diff --check`
- 中间提交：`feat(app): group workspace edit projection undo`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 AttoEditor App 从 core transaction snapshot 投影回已打开 tab 时，为每个发生文本变化的打开 tab 封闭用户可见 undo group。
  - 提交边界：只调整 App 层 `syncAppTabsFromCoreWorkspaceEditTransaction` 使用的文本投影 helper 和旧 Swift fallback 的打开 tab 替换 helper；打开 tab 文本发生变化后显式调用 `EditorUI.endUndoGroup()`，使用户对该 tab 执行一次 Undo 可以回到 WorkspaceEdit 应用前文本。本提交不新增 ABI，不改变 core transaction result schema，不实现跨文件全局 undo command、未打开文件/resource operation 的用户级 undo，或更深层 conflict UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditOpenTabProjectionCreatesUndoGroups`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEdit`
    - `git diff --check`
- 中间提交：`feat(ui): roll back atomic workspace edit failures`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；把显式 `atomic` apply mode 从 preflight-only 扩展到 text edit apply 阶段的运行时失败回滚。
  - 提交边界：只在 `MultiDocumentEditorUi` transaction apply 内处理 atomic 模式下运行时新增的 skipped text edit/resource dependency detail；发生这类失败时复用已有 filesystem/open-tab rollback log 回滚已经应用的副作用，并返回 `applied=false`、edit/resource counts 为 0 的结构化 result。本提交不改变默认 partial 语义，不新增 ABI 函数，不实现跨文件用户级 undo command 或更深层 conflict UI。
  - 验证记录：
    - `cargo fmt --package editor-core-ui`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_atomic_workspace_edit_rolls_back_runtime_text_failure`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAtomicWorkspaceEditRollsBackRuntimeTextFailure`
    - `cargo test -p editor-core-ui-ffi`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `git diff --check`
- 中间提交：`feat(ui): preflight removed workspace edit dependencies`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 `MultiDocumentEditorUi` preview/atomic preflight 按 `WorkspaceEdit.documentChanges` 顺序识别“前序 delete/rename 移除 URI，后续 text edit 仍编辑同一 URI”的 resource-order dependency。
  - 提交边界：只在 Rust transaction plan 中补 ordered text edit dependency preflight，并通过现有 result schema 返回 `resource_operation_dependency_removed` skipped detail；默认 `partial` apply 运行时语义、ABI 函数集合和 AttoEditor App 主路径不变。本提交不实现跨文件用户级 undo command、全量 conflict UI 或完整 transaction-wide undo 语义。
  - 验证记录：
    - `cargo fmt --package editor-core-ui`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_atomic_workspace_edit_preflights_removed_text_edit_dependency`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAtomicWorkspaceEditPreflightsRemovedTextEditDependency`
    - `cargo test -p editor-core-ui-ffi`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `git diff --check`
- 中间提交：`feat(ui): order unsupported workspace edit dependencies`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；让 `MultiDocumentEditorUi` preview 按 `WorkspaceEdit.documentChanges` 顺序识别 unsupported resource operation 对后续 text edit 的依赖阻断，同时避免后置 unsupported operation 误标前序 text edit。
  - 提交边界：只精化 Rust transaction plan 的 text edit/resource operation dependency 判断，复用现有 `resource_operation_dependency_unsupported` / `resource_operation_dependency_skipped` result detail；默认 `partial` apply、ABI 函数集合和 AttoEditor App 主路径不变。本提交不实现跨文件用户级 undo command、全量 conflict UI 或完整 transaction-wide undo 语义。
  - 验证记录：
    - `cargo fmt --package editor-core-ui`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_previews_later_text_edit_blocked_by_unsupported_resource_operation`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIPreviewsOrderedUnsupportedWorkspaceEditDependency`
    - `cargo test -p editor-core-ui-ffi`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `git diff --check`
- 中间提交：`feat(ui): expose workspace edit resource summaries`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；把 `MultiDocumentEditorUi` WorkspaceEdit transaction result 从 resource operation 计数推进到 typed operation summary，供 Swift/App preview 与后续 conflict UI 直接消费。
  - 提交边界：只新增兼容 JSON 字段 `resource_operations`，包含 kind、uri/old_uri/new_uri、affected_uris、supported 和 applied；Swift typed wrapper 新增对应 decoder，Atto preview model 在缺少 Swift parser 时可用该 summary 计算 resource operation 数量和 affected URI。本提交不新增 ABI 函数，不改变 apply 语义，不实现跨文件用户级 undo command 或完整 transaction-wide undo。
  - 验证记录：
    - `cargo fmt --package editor-core-ui`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_applies_open_tab_resource_operations`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAppliesOpenTabResourceOperations`
    - `swift test --package-path swift --filter AttoWorkspaceEditSummaryTests.testWorkspaceEditPreviewUsesCoreResourceOperationSummary`
    - `cargo test -p editor-core-ui-ffi`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
    - `git diff --check`
- 中间提交：`feat(ui): expose workspace edit conflict summaries`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；把 dirty document 和 skipped blocker 从 raw skipped details 推进到 typed conflict summary，供 Swift/App preview panel 和后续更完整 conflict UI 消费。
  - 提交边界：只新增兼容 JSON 字段 `documents[].is_dirty`、`dirty_document_uris` 和 `conflicts`，其中 conflict 包含 kind、uri、reason、operation 和 message；Swift typed wrapper 新增对应 decoder，Atto preview/panel 将 typed conflicts 显示为独立 conflict 区块并避免和 skipped detail 重复展示。本提交不新增 ABI 函数，不改变 preview/apply 语义，不实现跨文件用户级 undo command 或完整 transaction-wide undo。
  - 验证记录：
    - `cargo fmt --package editor-core-ui`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_reports_workspace_edit_transaction_skipped_details`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIAtomicWorkspaceEditPreflightSkipsWithoutMutating`
    - `swift test --package-path swift --filter AttoWorkspaceEditSummaryTests.testWorkspaceEditPreviewListsTypedConflicts`
    - `cargo test -p editor-core-ui-ffi`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
    - `git diff --check`
- 中间提交：`feat(ui): undo workspace edit transactions`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；为最近一次成功的 `MultiDocumentEditorUi` WorkspaceEdit transaction 增加 core-owned 一次性 undo 起点，并通过 C ABI、Swift typed wrapper 和 AttoEditor App 投影同步入口暴露给上层。
  - 提交边界：只保留最近一次成功 transaction 的 open-tab/filesystem rollback record；新的 transaction 会丢弃旧 record，undo 成功或失败后该 record 都会被消费；可恢复打开 tab 文本/URI/close/order/dirty 状态和 root-gated 本地文件 text/resource operation 副作用，并返回 typed undo summary。本提交不实现多级 undo stack、redo、全局 AppKit 菜单命令、跨 transaction conflict resolution 或完整 transaction-wide undo 产品化 UI。
  - 验证记录：
    - `cargo fmt --package editor-core-ui --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_undoes_last_workspace_edit_transaction`
    - `cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIUndoesLastWorkspaceEditTransaction`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditTransactionUndoRestoresAppProjectionAndFiles`
    - `cargo test -p editor-core-ui --test multi_document_ui_tests workspace_edit`
    - `cargo test -p editor-core-ui-ffi workspace_edit`
    - `swift test --package-path swift --filter 'EditorCoreUIFFITests.testMultiDocumentEditorUI.*WorkspaceEdit'`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditApplicationMutatesTextAndDirtyState`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditPreviewConfirmationCanCancelCoreTransaction`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditOpenTabProjectionCreatesUndoGroups`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditResourceOperationsApplyToUnopenedLocalFiles`
    - `swift test --package-path swift --filter AttoWorkspaceEditSummaryTests`
    - `git diff --check`
- 中间提交：`feat(app): command workspace edit undo`
  - 所属任务：阶段 4 的 core-owned WorkspaceEdit 跨文件事务增量；把最近一次 core-owned WorkspaceEdit transaction undo 从测试 hook 推进到用户可触达的 AttoEditor command/menu/keymap 路径，并为该 ABI 能力补独立 feature flag。
  - 提交边界：新增 UI FFI feature bit `ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_UNDO`、Swift `EditorCoreUIFFIFeatures.multiDocumentWorkspaceEditTransactionUndo`、runtime optional feature gate、`workspace.undo_last_workspace_edit` command、Edit 菜单项和 `cmd+option+z` 默认 binding；命令调用既有 core undo wrapper 并同步 AppKit 投影。本提交不实现多级 undo/redo stack、不改变普通 editor undo、不新增 AppKit `UndoManager` 聚合，也不实现更深层 conflict UI。
  - 验证记录：
    - `cargo fmt --package editor-core-ui-ffi`
    - `cargo test -p editor-core-ui-ffi feature_flags`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testLoadsLibraryAndVersion`
    - `swift test --package-path swift --filter AttoRuntimeCompatibilityTests`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesMetadataAndAvailability`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesParameterSchemasAndMacroPolicies`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryDisablesCommandsForMissingOptionalRuntimeFeatures`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditTransactionUndoCommandRestoresAppProjectionAndFiles`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditTransactionUndoRestoresAppProjectionAndFiles`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testExecuteCommandUsesRegisteredCommandIDs`
    - `git diff --check`

## 阶段 5: 多文档、tab、split、project、session 完整迁移

### 目标

把 AttoEditor 现有 Swift-only tabs/splits/session 过渡层收敛为 core workspace / `MultiDocumentEditorUi` 的投影。

### 主要交付

- `MultiDocumentEditorUi`：
  - 完整 tab model：open、close、preview、pin、dirty、save、reload、move、activate。
  - 完整 pane/split model：split right/down、close pane、focus pane、move tab to pane、drag/drop tab to split、shared buffer view。
  - Workspace/project root model：root add/remove、active root、document URI mapping、recent files、open folders。
  - Session model：restore tabs、pane layout、active tab/view、preview/pin/dirty metadata、scroll/selection/folds/bookmarks where appropriate。
  - LSP session lifecycle 与 workspace roots 绑定。
- FFI / Swift：
  - `MultiDocumentEditorUI` typed APIs 覆盖上述语义。
  - App 不再维护长期事实源，只保留 view controllers 和 UI projection。
- App：
  - Tab bar、split view、open/recent/save/close/session restore 消费 core model。
  - dirty/close protection 由 core snapshot 决定。
  - Find in Files、workspace diagnostics、symbols、LSP lifecycle 使用 core workspace roots。

### 验证

- Rust tests 覆盖 tab/pane/project/session model。
- Swift tests 覆盖 `MultiDocumentEditorUI` typed wrapper。
- AppKit tests 覆盖 tab open/close/move/drag/split/restore/dirty close。
- 手工或自动截图验证常见布局。

### 提交

- `feat(app): project tabs and panes from core workspace`
- 中间提交：`feat(app): save sessions from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor session snapshot 保存路径优先消费 `MultiDocumentEditorUI.snapshot()` 中的 tab 顺序、active tab、preview、view count 和 active view index，而不是只从 Swift `tabs` 数组读取长期事实。
  - 提交边界：只调整 App session 保存投影和对应测试；保留 Swift 本地 fallback，用于 core multi-document runtime 不可用、core tab id 缺失或 core snapshot 读取失败时维持既有行为。本提交不改变 restore 语义、不新增 Rust/FFI ABI、不实现 pane layout tree、drag/drop split 或 session schema migration。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSessionSnapshotUsesCoreTabProjectionWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSessionRestoreRestoresSplitPanesIntoCoreMirror`
    - `git diff --check`
- 中间提交：`feat(app): project open files from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor opened-files/sidebar/tab-bar projection 在 core snapshot 可用时消费 `MultiDocumentEditorUI.snapshot()` 中的 tab order、active tab、preview 和 dirty 状态。
  - 提交边界：只复用 App 层 core tab projection helper，调整 `openFileURLs()`、`openFileItems()` 和 `refreshTabBar()` 的读取来源；保留 Swift 本地 fallback，且不改变 AppKit tab selection/content 切换、不新增 Rust/FFI ABI、不实现 drag/drop tab-to-split 或 pane layout tree。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSessionSnapshotUsesCoreTabProjectionWhenAvailable`
    - `git diff --check`
- 中间提交：`feat(app): project active tab from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor active-tab 查询在 core snapshot 可用时消费 `MultiDocumentEditorUI.snapshot()` 中的 active tab，而不是只读 Swift `selectedTabID`。
  - 提交边界：只调整 `activeTab` 读取路径，并让 command keymap context、窗口标题等既有 active-tab 消费者自然跟随 core active tab；保留 Swift `selectedTabID` fallback。本提交不自动切换 AppKit content view，不改变 tab selection command，不新增 Rust/FFI ABI，也不实现 pane layout tree。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testActiveTabProjectionUsesCoreActiveTabWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMoveTabCommandsReorderAppKitProjectionAndCoreMirror`
    - `git diff --check`
- 中间提交：`feat(app): project active content from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor AppKit content host 在刷新 tab projection 时同步到 core snapshot 中的 active tab。
  - 提交边界：只在 `refreshTabBar()` 已有 core snapshot projection 时同步 `selectedTabID`、content host、status observer、polling/status/window title 和 find state；不改变用户 select-tab command，不新增 Rust/FFI ABI，不实现 pane layout tree、drag/drop split 或 session schema migration。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRefreshTabBarProjectsAppKitContentToCoreActiveTab`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testActiveTabProjectionUsesCoreActiveTabWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMoveTabCommandsReorderAppKitProjectionAndCoreMirror`
    - `git diff --check`
- 中间提交：`feat(app): close tab groups from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor 的 Close Other Tabs / Close Tabs to Right 用户命令按 core tab snapshot 的 active tab 和 tab order 计算关闭目标。
  - 提交边界：新增 App 命令、File 菜单项和 AppKit group-close helper；关闭每个目标 tab 仍复用既有 `closeTab` dirty/save/cancel 保护路径。此提交不新增 Rust/FFI ABI，不实现拖拽 tab-to-split、pane layout tree 或 session schema migration。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCloseTabGroupCommandsUseCoreTabProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesMetadataAndAvailability`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesParameterSchemasAndMacroPolicies`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): close all tabs from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor 的 Close All Tabs 用户命令按 core tab snapshot 的 tab order 关闭所有 AppKit tab 投影。
  - 提交边界：新增 App 命令、File 菜单项和 `closeAllTabsForWindow()` helper；关闭每个目标 tab 仍复用既有 `closeTab` dirty/save/cancel 保护路径。此提交不新增 Rust/FFI ABI，不实现完整 close-all session schema migration、拖拽 tab-to-split 或 pane layout tree。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCloseAllTabsUsesCoreTabProjectionOrder`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCloseTabGroupCommandsUseCoreTabProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesMetadataAndAvailability`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesParameterSchemasAndMacroPolicies`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): select files from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor 的 opened-files/sidebar selection 和再次打开已投影文件时，按 core tab snapshot 的 `document_uri` 查找现有 AppKit tab。
  - 提交边界：新增 App 层 projected file lookup helper，并迁移 `selectFile(url:)` 与 `openFile(url:mode:)` 的 existing-tab 查找；保留 Swift 本地 fallback，不主动重写 `tab.fileURL`，不新增 Rust/FFI ABI，不实现 session schema migration、project root ownership 或 pane layout tree。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSelectAndOpenFileUseCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRefreshTabBarProjectsAppKitContentToCoreActiveTab`
    - `git diff --check`
- 中间提交：`feat(app): navigate opened files from core tabs`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor 用 `openFile(url:mode:location:)` 打开 core-projected existing tab 时，location navigation 的 URL 校验也按 core `document_uri` 投影执行。
  - 提交边界：新增 projected file URL helper，并只迁移 open-with-location 的 active-tab URL guard；不主动重写 `tab.fileURL`，不新增 Rust/FFI ABI，不改变 LSP location parser、jump history、session schema 或 pane layout tree。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileLocationUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSelectAndOpenFileUseCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable`
    - `git diff --check`
- 中间提交：`feat(app): search open tabs from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor 的 Find in Files opened scope 在使用 core `searchAllTabs` 匹配文本后，结果 URL 也按 core tab snapshot 的 `document_uri` 投影输出。
  - 提交边界：只迁移 opened-tab search 结果组装中的 URL 来源；保留 Swift 本地 URL fallback，不新增 Rust/FFI ABI，不改变 project-wide filesystem search、search panel UI、session schema、LSP location parser 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testFindInOpenTabsUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testFindInOpenTabsUsesCoreMirrorForUnsavedText`
    - `git diff --check`
- 中间提交：`feat(app): navigate lsp targets from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor 的 LSP location target navigation 在复用 core-projected existing tab 后，active-tab URL 校验也按 core `document_uri` 投影执行。
  - 提交边界：放宽 projected file URL helper 供 LSP location extension 复用，并只迁移 `navigateToLspTarget(_:)` 的 active-tab guard；不新增 Rust/FFI ABI，不改变 LSP result parser、location quick panel、jump history、session schema 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspTargetNavigationUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileLocationUsesCoreDocumentURIProjection`
    - `git diff --check`
- 中间提交：`feat(app): preview workspace edits from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor WorkspaceEdit diff preview 的 text provider 在 URI 对应打开 tab 时，按 core `document_uri` 投影读取打开 tab 当前文本。
  - 提交边界：放宽 projected tab lookup helper 供 WorkspaceEdit preview 复用，并只迁移 `workspaceEditPreviewText(for:)` 的打开 tab 查找；不改变 WorkspaceEdit apply/transaction 语义、resource operation 执行、preview panel UI、session schema 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditPreviewTextUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditPreviewConfirmationCanCancelCoreTransaction`
    - `git diff --check`
- 中间提交：`feat(app): apply workspace edits from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor 在 WorkspaceEdit core transaction apply 前同步打开 tab 文本/dirty/active-view 时，保留 core tab snapshot 里已有的 `document_uri` 投影。
  - 提交边界：只调整 `syncOpenTabsToCoreBeforeWorkspaceEditApply(...)` 的 document URI/title 同步来源；core snapshot 已有有效 file URI 时保留 core URI，缺失时继续回退 Swift 本地 `tab.fileURL`。不改变 WorkspaceEdit transaction planner/apply/undo 语义、resource operation 执行、preview panel UI、session schema 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditApplyPreservesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditApplicationMutatesAlreadyOpenCrossFileTab`
    - `git diff --check`
- 中间提交：`feat(app): project document symbols from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor Document Symbols 和 Workspace Outline 在构造 symbol target / outline document key 时，使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 document-symbol result handling 和 workspace-outline upsert 的 document URI/file URL 来源；不改变 LSP request/poll lifecycle、workspace symbol result parsing、symbol panel UI、core document-symbol ABI 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDocumentSymbolsUseCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceOutlinePanelAggregatesDocumentSymbolSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): apply inlay hint edits from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 resolved inlay hint 携带的 `textEdits` 在包装成 WorkspaceEdit 并应用时，使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 `consumeResolvedInlayHint(...)` 中生成 WorkspaceEdit JSON 和 apply context 的 document URI 来源；不改变 inlay hint request/resolve lifecycle、command payload 执行、tooltip/preview UI、WorkspaceEdit transaction 语义或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testResolvedInlayHintUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testTypedAuxiliaryResultSummariesUseTypedPayload`
    - `git diff --check`
- 中间提交：`feat(app): apply rename edits from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor rename request/result context 在应用 WorkspaceEdit 时使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 `RenameRequestContext.documentURI` 的来源，包括实际 rename 请求和测试 hook；不改变 prepareRename/rename request lifecycle、WorkspaceEdit transaction/apply/undo 语义、rename UI 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRenameResultUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRenameResultRecordsLspResultEvent`
    - `git diff --check`
- 中间提交：`feat(app): project command contexts from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor keymap dynamic context 和 toggle comment 语言配置使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 command/keymap 文档身份派生字段（syntax/selector/file name/file extension）和 `toggle_comment` comment config 的 file URL 来源；不改变 keymap resolver 语义、菜单/command registry、真实保存路径、syntax detection、open-file language configuration、session schema 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testKeymapContextUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testToggleLineCommentUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testKeymapDynamicContextDispatchesActiveEditorBindings`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testToggleLineCommentUsesFileLanguageDefault`
    - `git diff --check`
- 中间提交：`feat(app): project active problems from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor active Problems/diagnostics snapshot、lifecycle scope 和 active diagnostic display title 使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 active diagnostics/Problems 里的 tab URL 输入、lifecycle scope/title 和 active diagnostic title 文件名；不改变 workspace diagnostics store schema、diagnostic parsing、marker projection math、Problems panel UI、navigation behavior、真实保存路径、session schema 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testActiveProblemsUseCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProblemsPanelUsesDerivedDiagnosticsAndRefreshesWithStatusUpdate`
    - `git diff --check`
- 中间提交：`feat(app): project code lens titles from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor Code Lens actions quick panel/current-line action title 使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 Code Lens action display title 中的 file name/line/column location 来源；不改变 code lens request/refresh/resolve lifecycle、decorations snapshot、command execution、inline click behavior、quick panel filtering、真实保存路径、session schema 或真实 `tab.fileURL` 同步策略。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCodeLensActionTitlesUseCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCodeLensAtCursorFiltersActionsToCurrentLine`
    - `git diff --check`
- 中间提交：`feat(app): project window titles from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor window title 的 active document display name 使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 `updateWindowTitle()` 中的文件名展示来源；不改变 dirty marker 判断、真实保存路径、tab bar/opened-files title、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWindowTitleUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testActiveTabProjectionUsesCoreActiveTabWhenAvailable`
    - `git diff --check`
- 中间提交：`feat(app): project status metadata from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor status bar 的 file size 和 Rust/LSP relevance 判断使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 `updateStatusBar()` 中 file-size lookup 与 “Rust file should show LSP status” 的文档 URL 来源；不改变 active derived-state/diagnostics 统计、LSP status snapshot/formatting、语言选择、真实保存路径、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoStatusBarSelectionTests.testStatusBarMetadataUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoStatusBarSelectionTests.testStatusBarShowsSelectionRangeAndSize`
    - `git diff --check`
- 中间提交：`feat(app): project language config from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor indentation/comment language configuration application 使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 `applyLanguageConfiguration(for:)`、split pane creation 和 WorkspaceEdit/resource-operation 后 pane refresh 中的 language configuration file URL 来源；不改变 syntax engine selection、用户显式 language override、真实保存路径、WorkspaceEdit apply/resource-operation 语义、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLanguageIndentationConfigUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileAppliesLanguageIndentationConfig`
    - `git diff --check`
- 中间提交：`feat(app): project core tab titles from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor core tab title sync 使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 `updateCoreTabTitle(_:)` 中 display title 的文件名来源；不改变真实保存路径、`updateCoreTabDocumentURI(_:)` 的真实 URI 同步、tab bar/opened-files projection、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCoreTabTitleUpdateUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable`
    - `git diff --check`
- 中间提交：`feat(app): project close callbacks from core uris`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 AttoEditor close-tab notification/callback URL 使用 core tab snapshot 的 `document_uri` 投影。
  - 提交边界：只迁移 `closeTab(id:)` 中传给 `onDidCloseFile` 的 URL 来源；不改变 dirty close confirmation、真实保存路径、core close command、tab removal、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCloseTabCallbackUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCloseAllTabsUsesCoreTabProjectionOrder`
    - `git diff --check`
- 中间提交：`feat(app): project workspace edit close callbacks`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；让 WorkspaceEdit core transaction / undo 导致的 removed-tab close callback URL 使用 apply/undo 前的 core tab snapshot `document_uri` 投影。
  - 提交边界：只在 core WorkspaceEdit apply/undo 前缓存 tab id 到 projected URL，并将其用于 `syncAppTabsFromCoreWorkspaceEditTransaction(...)` 中 removed tabs 的 `onDidCloseFile` URL；不改变 WorkspaceEdit transaction planner/apply/undo、resource operation 文件系统副作用、dirty close confirmation、真实保存路径、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditRemovedTabCallbackUsesCoreDocumentURIProjection`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceEditResourceOperationDeletesOpenCleanTab`
    - `git diff --check`
- 中间提交：`feat(app): persist pane layout snapshots`
  - 所属任务：阶段 5 的多文档/tab/split/project/session 迁移增量；为 AttoEditor session tab snapshot 增加可选 pane layout descriptor，并让 snapshot/restore 优先按 core-projected view count 与 active view index 生成和消费该布局字段。
  - 提交边界：只新增 Swift session `paneLayout` 编码模型和 restore 优先级；保留旧 `paneCount` / `activePaneIndex` 作为兼容 fallback，不改变真实 pane UI 结构、core `MultiDocumentEditorUi` view model、Rust/FFI ABI、session 文件路径或 workspace/project ownership。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSessionSnapshotUsesCoreTabProjectionWhenAvailable`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSessionRestoreRestoresSplitPanesIntoCoreMirror`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSessionRestorePrefersPaneLayoutSnapshotOverLegacyPaneCount`
    - `swift test --package-path swift --filter AttoSessionStoreTests.testLoadAcceptsLegacyTabSnapshotWithoutPaneLayout`
    - `git diff --check`

## 阶段 6: LSP workspace lifecycle 与 project-level 语言能力

### 目标

让 LSP session、workspace folders、capabilities、refresh、index-like derived state 与 project model 一起工作，而不是仅 active editor 单点工作。

### 主要交付

- Workspace-root aware LSP lifecycle：
  - server start/stop/restart。
  - workspace folders didChange。
  - document open/change/save/close notifications。
  - capability registration / dynamic capabilities。
  - server health/error/status events。
- Project-level commands：
  - workspace symbols。
  - workspace diagnostics。
  - references / implementations / hierarchy across files。
  - code actions spanning files。
- Derived-state refresh：
  - diagnostics, semantic tokens, folding, inlay hints, code lens, document links 按 document/workspace lifecycle 正确 stale/refresh。
- App：
  - Status bar 和 panels 显示 server 状态、workspace root、capabilities。
  - 对 unsupported capability 明确降级。

### 验证

- Rust tests 覆盖 workspace folder lifecycle、document notifications、server capability mapping。
- Swift tests 覆盖 typed status/capability events。
- App tests 覆盖 project open 后 server 状态和 workspace-level commands。

### 提交

- `feat(lsp): bind workspace lifecycle to projects`
- 中间提交：`feat(ui): bind lsp workspace folders to roots`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 `EditorUi::lsp_enable_stdio(...)` 从传入 root URI 派生 LSP `WorkspaceFolder`，并同时写入 initialize params 的 `workspaceFolders` 与 `LspClient` 响应 `workspace/workspaceFolders` 的 root 列表。
  - 提交边界：只补单 root LSP workspace folder 投影，不改变 Swift `lspEnable(...)` API、AttoEditor LSP command discovery、共享 LSP session key、`MultiDocumentEditorUi` 多 root ABI、workspace folder didChange、project open/close lifecycle 或 server restart 策略。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_enable_stdio_projects_root_uri_to_workspace_folders`
    - `cargo test -p editor-core-ui lsp_request_events_record_start_completion_and_result_sequence`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ui): notify lsp workspace folder changes`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把 headless `LspSession::did_change_workspace_folders(...)` 链接到 `EditorUi`、C ABI 和 Swift typed wrapper，并让 `LspClient` 的 `workspace/workspaceFolders` 响应列表随 didChange 更新。
  - 提交边界：只新增 JSON control-plane ABI `editor_core_ui_ffi_editor_ui_lsp_did_change_workspace_folders_json(...)` 和 Swift `lspDidChangeWorkspaceFolders(added:removed:)` wrapper；不改变 LSP server start/restart、shared-session key、多 root project ownership、AttoEditor project-open flow、`MultiDocumentEditorUi` root ABI 或自动 workspace folder diff 策略。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_did_change_workspace_folders_notifies_and_updates_workspace_response`
    - `cargo test -p editor-core-ui-ffi ffi_lsp_request_definition_errors_when_lsp_disabled`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testEditorUILSPResultEventsWrapperStartsEmpty`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): project workspace root changes to lsp`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 core-owned `MultiDocumentEditorUi` workspace root 列表在更新时返回 LSP `WorkspaceFolder` added/removed diff，并让 AttoEditor 的 workspace root 变更用该 diff 通知当前 active LSP session。
  - 提交边界：新增 `MultiDocumentEditorUi::set_workspace_roots_with_change(...)`、C ABI `editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_json(...)`、Swift `MultiDocumentEditorUI.setWorkspaceRootsReturningChange(_:)` 和 AttoEditor active-editor didChange 接线；保留既有 `setWorkspaceRoots(_:)` 兼容 API，不新增多 root project selector、不改变 server start/restart/shared-session 策略、不实现 project close/open 批量 LSP session 管理。
  - 验证记录：
    - `cargo test -p editor-core-ui --test multi_document_ui_tests multi_document_ui_tracks_workspace_roots`
    - `cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCoreMultiDocumentMirrorTracksTabsAndPanes`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceRootChangeNotifiesOpenTabLspWorkspaceFolders`（阶段 250 后由 open-tab fan-out 覆盖原 active-tab 用例）
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): broadcast workspace root changes to lsp tabs`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把阶段 249 的 core-owned workspace root diff 从 active editor 单点通知扩展为对所有已打开且 LSP 已启用的 tab 逐一发送 `workspace/didChangeWorkspaceFolders`。
  - 提交边界：只调整 AttoEditor root-change notification fan-out 和对应假 LSP AppKit 测试；仍按 tab 去重，不按 split pane 重复通知；不改变 Rust/FFI ABI、不新增 project selector、不实现 LSP server restart/shared-session root-set ownership 或 project open/close 批量启动停止策略。
  - 验证记录：
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceRootChangeNotifiesOpenTabLspWorkspaceFolders`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): notify lsp document save close`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把 headless `LspSession` 的 `textDocument/didSave` / `textDocument/didClose` 通知暴露到 `EditorUi`、C ABI、Swift typed wrapper，并让 AttoEditor 保存 tab / 关闭 tab 的主路径通知对应 LSP session。
  - 提交边界：只新增 didSave/didClose document lifecycle control-plane 接线和保存/关闭 hook；didSave 的 text payload 可为空但 AttoEditor 保存路径会传入保存后的文本；不新增 didOpen 多文档打开生命周期、不改变 didChange fan-out、不实现 project open/close 批量 LSP session 管理、server restart/shared-session root-set ownership 或更高层 project selector。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_document_lifecycle_notifications_are_exposed`
    - `cargo test -p editor-core-ui-ffi ffi_lsp_request_definition_errors_when_lsp_disabled`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testEditorUILSPResultEventsWrapperStartsEmpty`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSaveAndCloseNotifyLspDocumentLifecycle`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): notify lsp document open`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把 headless `LspSession::open_document(...)` 的 `textDocument/didOpen` 暴露到 `EditorUi`、C ABI 和 Swift typed wrapper，并让 AttoEditor 打开没有自身 LSP session 的新 tab 时通知其它已打开且 LSP 已启用的 tab session。
  - 提交边界：只新增 didOpen document lifecycle control-plane 接线、open-tab fan-out，以及这类无自身 LSP tab 后续 didSave/didClose 对既有 sessions 的闭环通知；新 tab 自身已经启用 LSP 时仍由 `lspEnable(...)` 的既有启动路径发送 didOpen，避免对共享 session 重复 didOpen；不改变 didChange flush 语义、不新增 project open/close 批量 LSP session 管理、server restart/shared-session root-set ownership 或更高层 project selector。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_document_lifecycle_notifications_are_exposed`
    - `cargo test -p editor-core-ui-ffi ffi_lsp_request_definition_errors_when_lsp_disabled`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testEditorUILSPResultEventsWrapperStartsEmpty`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenSaveAndCloseNotifyExistingLspSessions`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): notify lsp document changes`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把 extra document 的 `textDocument/didChange` 从 headless `LspSession` 暴露到 `EditorUi`、C ABI 和 Swift typed wrapper，并让 AttoEditor 对无自身 LSP session 的 tab 编辑通知其它已打开且 LSP 已启用的 tab session。
  - 提交边界：只新增 full-document text didChange control-plane API 和 App 编辑 hook fan-out；range/UTF-16 计算由 Rust `DeltaCalculator` 的 per-document mirror 完成，避免 Swift 侧维护 LSP 文本镜像。新 tab 自身已经启用 LSP 时继续走既有 `EditorUi` 增量 didChange；不新增 project open/close 批量 LSP session 管理、server restart/shared-session root-set ownership、更高层 project selector 或跨 session 去重策略。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_document_lifecycle_notifications_are_exposed`
    - `cargo test -p editor-core-ui-ffi ffi_lsp_request_definition_errors_when_lsp_disabled`
    - `cargo test -p editor-core-lsp close_document_drops_its_pending_requests`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testEditorUILSPResultEventsWrapperStartsEmpty`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenSaveAndCloseNotifyExistingLspSessions`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(lsp): dedupe workspace folder changes`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 `LspSession::did_change_workspace_folders(...)` 在 Rust LSP client 持有的 workspace folder set 上计算有效 diff，避免 AttoEditor 对多个共享同一 `SharedLspSession` 的 tab fan-out root change 时，同一个 server 收到重复 `workspace/didChangeWorkspaceFolders`。
  - 提交边界：只在 headless LSP client/session 层过滤已存在的 added folder 和已不存在的 removed folder，并保持 `workspace/workspaceFolders` response 列表与实际变更一致；不改变 Swift fan-out 入口、不新增 shared-session identity ABI、不实现 server restart、project open/close 批量 session 管理或 root-set ownership 的完整策略。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_did_change_workspace_folders_notifies_and_updates_workspace_response`
    - `cargo test -p editor-core-ui-ffi ffi_lsp_request_definition_errors_when_lsp_disabled`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ui): expose lsp workspace folders in status`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把 Rust LSP client 当前持有的 `workspace_folders` 投影到 `LspSessionStatus` / `EditorUi.lsp_status_json()`，并让 Swift typed `EcuLspStatusSnapshot` 与 AttoEditor status bar 可显示 workspace root 和 compact capabilities。
  - 提交边界：只扩展既有 status JSON / Swift typed snapshot / App status formatter；不新增 C ABI 函数，不改变 LSP enable 或 workspace folder didChange 控制面，不实现 project open/close 批量 LSP session 管理、server restart/shared-session root-set ownership、多 root selector 或完整状态订阅模型。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_status_reports_current_workspace_folders`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreLSPStatusSnapshotTests`
    - `swift test --package-path swift --filter AttoLspStatusFormatterTests`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ui): emit lsp status state events`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把阶段 255 的 LSP status snapshot 纳入统一 `EditorUiStateEvent`，让 Swift/App 可通过 state event stream 订阅 enable/disable、workspace folder didChange 和部分 polling failure 的 LSP status 变化。
  - 提交边界：只新增 `lsp_status_changed` state event kind、`lsp` family 和可选 `lsp_status` payload，并补 Swift typed decode；不新增 C ABI 函数，不改变现有 `state_events_json` ABI，不实现完整低层 `lsp_fail(...)` 覆盖、server progress 去重、server process health event、project-level status 聚合消费或 UI panel 自动刷新。
  - 验证记录：
    - `cargo test -p editor-core-ui editor_ui_state_events_project_lsp_request_and_result_events`
    - `cargo test -p editor-core-ui lsp_status_reports_current_workspace_folders`
    - `cargo test -p editor-core-ui poll_processing_reports_lsp_failure_without_applied_success`
    - `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFILSPEventTypesTests`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): consume lsp status state events`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 AttoEditor active state/event drain 缓存 `lsp_status_changed` 的 typed status payload，并让 status bar 优先使用 event-derived status 显示 server/workspace root/capabilities。
  - 提交边界：只扩展 AttoEditor active UI 投影缓存和 status bar rendering fallback；真实 LSP status 仍来自 Rust `EditorUiStateEvent` / `EcuLspStatusSnapshot`。不新增 Rust/FFI ABI，不改变 LSP session ownership、workspace folder didChange、server restart、project open/close 批量启停或 project-level status panel。
  - 验证记录：
    - `swift test --package-path swift --filter AttoStatusBarSelectionTests.testStatusBarConsumesLspStatusStateEvent`
    - `swift test --package-path swift --filter AttoStatusBarSelectionTests.testStatusBarConsumesActiveDerivedDiagnostics`
    - `git diff --check`
- 中间提交：`feat(ui): emit lsp sync failure status events`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续补齐阶段 256 的 LSP status state event 覆盖，让低层 LSP sync / on-type formatting / result-derived apply failure 也在写入 `lsp_status_json()` 失败状态时同步发出 `lsp_status_changed`。
  - 提交边界：只在 Rust `EditorUiDoc` 增加 doc-lock 内可用的 failure + status event helper，并切换 didChange flush、refresh processing、on-type formatting request/response/apply、slot result apply 和 derived-state apply 的失败路径；不新增 C ABI/Swift wrapper 字段，不改变 `state_events_json` schema，不实现 server progress/activity 去重、server process health event、project-level status panel 或 project open/close 批量 LSP session 管理。
  - 验证记录：
    - `cargo test -p editor-core-ui flush_did_change_failure_records_lsp_status_event`
    - `cargo test -p editor-core-ui on_type_formatting_response_error_records_lsp_status`
    - `cargo test -p editor-core-ui poll_processing_reports_lsp_failure_without_applied_success`
    - `cargo test -p editor-core-ui lsp_status_reports_current_workspace_folders`
    - `cargo test -p editor-core-ui editor_ui_state_events_project_lsp_request_and_result_events`
    - `cargo test -p editor-core-ui`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): drain project lsp status events`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 AttoEditor project-level LSP lifecycle drain 同时消费 `MultiDocumentEditorUI.stateEvents(...)` 中的 `lsp_status_changed`，并把 failed status 投入 project LSP event store，供后续项目级 status panel / feedback UI 按 cursor 消费。
  - 提交边界：只扩展 Swift/App 层事件消费和测试：新增 project LSP error event source `.status`、`coreLspStateEventCursor`、status failure recorder，以及 MultiDocument nested `lspStatus` typed decode 覆盖；不新增 Rust/C ABI，不改变 `MultiDocumentEditorUi` state event schema，不把 status failure 误投到 Locations/Symbols panel，不实现完整 project status panel UI、server progress/activity/process health monitor、server restart 或 project open/close 批量 LSP session 管理。
  - 验证记录：
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspPanelRecordsStatusFailures`
    - `swift test --package-path swift --filter EditorCoreUIFFILSPEventTypesTests.testMultiDocumentStateEventsExposeTypedKindsAndNestedPayloads`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspPanelErrorEventStoreBoundsAndFiltersBySequence`
    - `git diff --check`
- 中间提交：`feat(app): show project lsp status events`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把阶段 259 的 project LSP event store 暴露为用户可打开的轻量 status events 面板，并接入 command registry 与 Go 菜单。
  - 提交边界：只新增 Swift/App 级 `lsp.show_project_lsp_status` 命令、菜单项、`AttoEditor.LSP.ProjectStatusEvents` command-palette panel 和测试；面板展示 project LSP event store 中的 request/result/status 错误事件，不新增 Rust/C ABI，不改变 core event schema，不实现 server progress/activity/process health monitor、server restart、project open/close 批量 LSP session 管理或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspStatusEventsPanelShowsRecordedFailures`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspPanelRecordsStatusFailures`
    - `git diff --check`
- 中间提交：`feat(ui): emit lsp activity status events`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续补齐 server progress/activity 可观测性，让 LSP `$/progress` 导出的 client-side activity/state 变化进入统一 `lsp_status_changed` state event stream。
  - 提交边界：只在 `EditorUi` 侧记录最近一次 LSP status event signature，并在 `poll_processing()` 后对变化后的 status 发出去重的 `lsp_status_changed`；payload 复用既有 `lsp_status` shape，不新增 Rust/C ABI 或 Swift wrapper 字段，不改变 project-level event store/panel 行为，不实现 server process health monitor、server restart、project open/close 批量 LSP session 管理、完整 progress history 或 dashboard 级健康视图。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_progress_activity_emits_deduped_status_events`
    - `cargo test -p editor-core-ui lsp_status_reports_current_workspace_folders`
    - `cargo test -p editor-core-ui poll_processing_reports_lsp_failure_without_applied_success`
    - `cargo test -p editor-core-ui editor_ui_state_events_project_lsp_request_and_result_events`
    - `cargo test -p editor-core-ui`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ui): expose lsp process health status`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续补齐 server process health 可观测性，让 LSP 子进程退出状态进入既有 `lsp_status_json()` / `lsp_status_changed` payload，并提供 Swift typed `process` accessor。
  - 提交边界：只新增 `LspClient` 非阻塞 exit-status probe、`LspSessionStatus.process`、UI status JSON 的 `process` 字段和 Swift `EcuLspProcessStatus` decode；当进程已退出时，既有 status event stream 会发去重的 failed `lsp_status_changed`。不新增 C ABI 函数，不改变 existing `state_events_json` ABI，不实现 server restart、自动 session teardown/recovery、project open/close 批量 LSP session 管理、stderr capture 或 dashboard 级健康视图。
  - 验证记录：
    - `cargo test -p editor-core-lsp session_status_reports_exited_server_process`
    - `cargo test -p editor-core-ui lsp_process_exit_emits_failed_status_event`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreLSPStatusSnapshotTests`
    - `swift test --package-path swift --filter EditorCoreUIFFILSPEventTypesTests.testMultiDocumentStateEventsExposeTypedKindsAndNestedPayloads`
    - `cargo test -p editor-core-lsp`
    - `cargo test -p editor-core-ui`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): restart active lsp server`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；补齐 AttoEditor active tab 的手动 LSP server restart 起点，让 Swift/App 侧能复用打开文档时保存的 LSP 启动配置重新启用当前 tab 的 LSP session。
  - 提交边界：只新增 Swift/App 级 `lsp.restart_server` 命令、Go 菜单项、tab 级 LSP launch config 保存、active tab restart helper 和测试；启动参数仍来自既有 `AttoLspRegistry` / Rust 文件环境变量兼容路径，restart 仍通过既有 `EditorUI.lspEnable/lspDisable` binding 完成。不新增 Rust/C ABI，不改变 `editor-core-ui` LSP session ownership，不实现 project-level 批量 restart、shared-session root-set ownership 策略、自动恢复、stderr capture 或 dashboard 级 server health UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartLspServerRequiresSavedLaunchConfig`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartLspServerRestartsActiveTabSession`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `swift test --package-path swift --filter AttoLspResultFeedbackTests`
    - `git diff --check`
- 中间提交：`feat(app): restart project lsp servers`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 263 active-tab restart 基础上补齐 project-level 手动批量 restart 入口，让 AttoEditor 可按 core workspace tab 投影重启所有已保存 launch config 的打开文档 LSP session。
  - 提交边界：只新增 Swift/App 级 `lsp.restart_project_servers` 命令、Go 菜单项、core-projected tabs lifecycle helper、批量 restart helper 和测试；遍历来源优先使用 `MultiDocumentEditorUI` snapshot 投影，启动参数仍由 Swift UI 投影保存并通过既有 `EditorUI.lspEnable/lspDisable` binding 执行。不新增 Rust/C ABI，不改变 `editor-core-ui` LSP session ownership，不实现 shared-session root-set ownership 策略、project open/close 自动启停、自动恢复、stderr capture 或 dashboard 级 server health UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartProjectLspServersRequiresConfiguredTabs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartProjectLspServersRestartsConfiguredOpenTabs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartLspServerRestartsActiveTabSession`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`fix(app): release lsp sessions when closing tabs`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；补齐 project/window close 停止侧的 App 起点，关闭拥有自身 LSP session 的 tab 时释放该 editor view 的 LSP handle，并避免 Swift 侧手动 didClose 与 Rust `lsp_reset()` 的 didClose 重复发送。
  - 提交边界：只调整 AttoEditor close-tab 路径和测试；owned-session tab 关闭时走 `EditorUI.lspDisable()`，由 Rust `lsp_reset()` 负责当前文档 didClose 与 handle release；非 owned-session tab 仍按既有逻辑通知其它 open LSP sessions。不会新增 Rust/C ABI，不实现 graceful shutdown API、shared-session root-set 完整 ownership、project open 自动批量启动、stderr capture 或 dashboard 级 server health UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCloseAllTabsReleasesOwnedLspSessionsWithoutDuplicateDidClose`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSaveAndCloseNotifyLspDocumentLifecycle`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testOpenSaveAndCloseNotifyExistingLspSessions`
    - `git diff --check`
- 中间提交：`fix(ui): gracefully exit shared lsp sessions`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；补齐阶段 265 后 shared LSP session 最后一个 handle 释放时的 Rust 停止侧起点，让最后一次 `Arc<SharedLspSession>` drop 通过既有 `LspSession::exit()` 路径发送 `shutdown` / `exit` 并回收子进程。
  - 提交边界：只在 `editor-core-ui` 的 shared-session wrapper 上增加 drop-time graceful exit，并新增 fake LSP server 回归测试捕获 `shutdown` 与 `exit`；不新增 Rust/C ABI 或 Swift API，不改变 `EditorUI.lspDisable()` 调用形状，不实现 host-visible 显式 shutdown API、shared-session root-set 完整 ownership、project open 自动批量启动、stderr capture、server process history 或 dashboard 级 server health UI。
  - 验证记录：
    - `cargo test -p editor-core-lsp session_exit_accepts_responsive_shutdown`
    - `cargo test -p editor-core-ui lsp_disable_gracefully_exits_last_shared_session`（受限未完成：sandbox 内 `skia-bindings` 需要访问 GitHub 下载，提升权限请求被审批层拒绝）
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ui): expose lsp shutdown control`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把阶段 266 的 graceful shutdown 从 drop-time fallback 提升为 host-visible 控制面，让 Rust `EditorUi`、C ABI 和 Swift `EditorUI` wrapper 可以显式关闭当前 LSP session，并返回是否实际关闭了一个 live session。
  - 提交边界：新增 `EditorUi::lsp_shutdown() -> Result<bool, UiError>`、C ABI `editor_core_ui_ffi_editor_ui_lsp_shutdown(...)` 和 Swift `EditorUI.lspShutdown() throws -> Bool`；显式 shutdown 会 best-effort 发送当前文档 `didClose`，再通过 shared session 的 `shutdown()` 调用既有 `LspSession::exit()`，最后清理当前 view 的 LSP 状态；shared-session pool 会跳过已经被 shutdown/take 的 dead handle，避免同 key 后续 enable 复用不可用 session。本提交不改变 `lspDisable()` 的兼容行为，不新增 App command/menu，不实现 shared-session root-set 完整 ownership、project open 自动批量启动、stderr capture、server process history 或 dashboard 级 server health UI。
  - 验证记录：
    - `cargo build -p editor-core-ui-ffi --release`
    - `cargo test -p editor-core-lsp session_exit_accepts_responsive_shutdown`
    - `cargo test -p editor-core-ui lsp_shutdown_gracefully_exits_active_session --release`
    - `cargo test -p editor-core-ui lsp_disable_gracefully_exits_last_shared_session --release`
    - `cargo test -p editor-core-ui-ffi ffi_lsp_shutdown_returns_false_when_lsp_disabled --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testEditorUILSPResultEventsWrapperStartsEmpty`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ui): update shared lsp root aliases`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；推进 shared-session root-set ownership，使 `workspace/didChangeWorkspaceFolders` 成功后，Rust `SharedLspSession` 会同步维护 root alias 并更新 shared-session pool。
  - 提交边界：`SharedLspSession` 现在保存 `cmd` / `args` / root alias set；workspace folder added 会登记同一 shared server 的新 root key，removed 会移除指向该 shared server 的旧 root key；同 root key 已存在其它 alive session 时不会覆盖。后续新 tab 用新 root `lspEnable` 会复用已经接收 didChange 的 shared session，避免同 project root-set 变化后启动第二个 server。本提交不改变 Swift/API 形状，不新增 App command/menu，不实现完整 project open 自动批量 LSP 启动、跨独立 project 的 session 合并策略、stderr capture、server process history 或 dashboard 级 server health UI。
  - 验证记录：
    - `cargo test -p editor-core-ui lsp_workspace_folder_change_updates_shared_session_root_alias --release`
    - `cargo test -p editor-core-ui lsp_did_change_workspace_folders_notifies_and_updates_workspace_response --release`
    - `cargo build -p editor-core-ui-ffi --release`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(app): auto-start project lsp servers on root change`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；补齐 project/workspace root 变更和 session restore 后的 App 侧批量 LSP 启动起点，让 AttoEditor 使用 core-projected open tabs 遍历已打开文档，并对尚未启用但可从现有 launch config / registry / env 解析启动参数的 tab 自动启用 LSP。
  - 提交边界：只新增 Swift/App 层 `startProjectLspServersForOpenTabs()` helper、workspace root 更新/session restore 后的自动调用、测试用 LSP environment provider 和手动语言选择后的自动启动抑制标记；启动仍通过既有 `EditorUI.lspEnable(...)`，tab/URI 遍历来源优先使用 `MultiDocumentEditorUI` snapshot 投影。本提交不新增 Rust/C ABI，不把 Swift 启动参数持久化为 core-owned schema，不实现跨独立 project session 合并、stderr capture、server process history、自动崩溃恢复或 dashboard 级 server health UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceRootChangeAutoStartsConfiguredOpenTabLsp`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceRootChangeNotifiesOpenTabLspWorkspaceFolders`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartProjectLspServersRestartsConfiguredOpenTabs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartLspServerRequiresSavedLaunchConfig`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testSessionRestoreRestoresSplitPanesIntoCoreMirror`
- 中间提交：`feat(ui): expose lsp stderr tail status`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；补齐 server process health 可观测性的 stderr 起点，让 LSP 子进程 stderr 的 bounded tail 进入 `LspSessionStatus` / `EditorUi.lsp_status_json()` / Swift typed `EcuLspProcessStatus`。
  - 提交边界：只在 `editor-core-lsp` 的 `LspClient` 内部为 piped stderr 启动后台 tail reader，`EditorUi::lsp_enable_stdio(...)` 改为 pipe stderr，并在既有 process status JSON 增加兼容字段 `stderr_tail`；Swift typed wrapper 新增可选 `stderrTail` decode。本提交不新增 C ABI 函数，不改变 request/event schema 的主结构，不实现持久在线 stderr log、server process history、自动崩溃恢复或 dashboard 级 server health UI。
  - 验证记录：
    - `cargo test -p editor-core-lsp session_status_reports_stderr_tail`
    - `cargo test -p editor-core-lsp session_status_reports_exited_server_process`
    - `cargo test -p editor-core-ui lsp_status_reports_stderr_tail --release`
    - `cargo test -p editor-core-ui lsp_process_exit_emits_failed_status_event --release`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreLSPStatusSnapshotTests.testDecodesReadyStatusWithCapabilities`
    - `swift test --package-path swift --filter EditorCoreLSPStatusSnapshotTests.testDecodesFailedStatusWithMinimalServer`
- 中间提交：`feat(app): show lsp stderr in project status events`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 AttoEditor project LSP status events 消费 `EcuLspProcessStatus.stderrTail`，把失败状态的 stderr tail 附加到 bounded project status event message 中。
  - 提交边界：只扩展 Swift/App 层 `recordProjectLspStatusFailure(...)` 的 message 组装，并补项目级 status event store/panel 测试；不新增 Rust/C ABI，不改变事件 store schema，不改变 status event drain cursor，不实现持久化 stderr log、独立进程历史表、自动崩溃恢复或 dashboard 级 server health UI。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspPanelRecordsStatusFailures`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspStatusEventsPanelShowsRecordedFailures`
- 中间提交：`feat(app): track lsp process health history`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 AttoEditor project LSP lifecycle drain 把带 `process` payload 的 `lsp_status_changed` 状态快照记录到 bounded project LSP process health history 中。
  - 提交边界：只新增 Swift/App 层内存 `AttoProjectLspProcessHealthEventStore`、状态事件消费接线和测试访问器；历史条目保存 server、status、detail、tab/view 来源和 typed `EcuLspProcessStatus`。不新增 Rust/C ABI，不改变 `MultiDocumentEditorUi` state event schema，不改变 project status events panel，不实现持久化 stderr/process log、独立 dashboard UI、自动崩溃恢复或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthEventStoreBoundsAndFiltersBySequence`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthRecordsStatusSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): show lsp process health panel`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把阶段 272 的 bounded project LSP process health history 暴露为用户可打开的轻量面板。
  - 提交边界：只新增 Swift/App 级 `lsp.show_project_lsp_health` 命令、Go 菜单项、`AttoEditor.LSP.ProjectProcessHealth` command-palette panel 和测试；面板展示最近 process health snapshots 的 server、availability/state、process state、pid、exit/signal、scope 和 detail/stderr 摘要。不新增 Rust/C ABI，不改变 health history store schema，不实现持久化 stderr/process log、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthPanelShowsRecordedStatusSnapshots`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspStatusEventsPanelShowsRecordedFailures`
    - `git diff --check`
- 中间提交：`feat(app): persist lsp process health log`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把 project LSP process health history 从纯内存推进到 App 级 JSONL 持久化日志起点，并让 health 面板在内存为空时回退展示当前 workspace root 的最近持久化记录。
  - 提交边界：新增纯 Foundation `AttoProjectLspProcessHealthLogStore`，默认写入 Application Support 下的 `logs/lsp-process-health.jsonl`；日志记录包含 workspace root URI、server、availability/state、tab/view 来源、detail、process state/pid/exit/signal/stderr tail 和记录时间。Swift/App 仍只做持久化桥接，workspace root 作为 core/project 身份元数据写入，不新增 Swift workspace ownership，不新增 Rust/C ABI，不改变 state event schema，不实现日志轮转/清理、复杂查询 UI、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreAppendsAndLoadsRecentWorkspaceEntries`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthPanelFallsBackToPersistedLog`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthRecordsStatusSnapshots`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthPanelShowsRecordedStatusSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): bound lsp process health log`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 274 的 JSONL process health log 基础上补 retention/清理起点，避免日志无限增长。
  - 提交边界：`AttoProjectLspProcessHealthLogStore` 新增 `maxPersistedEntries`，默认保留最近 2000 条 JSONL 记录；每次 append 后按全局最新行清理旧记录，`loadRecent(...)` 继续按 workspace root URI 过滤。不新增 Rust/C ABI，不改变日志记录 schema、不新增 UI、不实现按 workspace 独立配额、大小/时间轮转、导出/查询 UI、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreRetainsLatestEntries`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreAppendsAndLoadsRecentWorkspaceEntries`
    - `git diff --check`
- 中间提交：`feat(app): show lsp process health log`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 274/275 的 JSONL process health log 基础上补显式查询 UI 起点。
  - 提交边界：新增 Swift/App 级 `lsp.show_project_lsp_health_log` 命令、Go 菜单项和 `AttoEditor.LSP.ProjectProcessHealthLog` command-palette panel；该面板始终按当前 workspace root URI 查询 persisted log，不依赖内存 history 为空的 fallback 条件。不新增 Rust/C ABI，不改变日志记录 schema、不改变既有 health 面板行为、不实现导出、清空、复杂查询/filter DSL、按 workspace 独立配额、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthLogPanelShowsPersistedLog`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): clear lsp process health log`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 274-276 的 JSONL process health log 基础上补当前 workspace root 的清空入口。
  - 提交边界：`AttoProjectLspProcessHealthLogStore` 新增 `clear(workspaceRootURL:)`，只移除匹配当前 workspace root URI 的可解析记录并保留其他 root 记录；AttoEditor 新增 Swift/App 级 `lsp.clear_project_lsp_health_log` 命令和 Go 菜单项。该提交不新增 Rust/C ABI，不改变日志记录 schema、不清空内存 process health history、不实现导出、确认弹窗、复杂查询/filter DSL、按 workspace 独立配额、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreClearsWorkspaceEntries`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testClearProjectLspProcessHealthLogClearsCurrentWorkspaceOnly`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): export lsp process health log`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 274-277 的 JSONL process health log 基础上补当前 workspace root 的导出入口。
  - 提交边界：`AttoProjectLspProcessHealthLogStore` 新增按 workspace root URI 过滤的 JSONL export API，可返回字符串或写入目标文件；AttoEditor 新增 Swift/App 级 `lsp.export_project_lsp_health_log` 命令、Go 菜单项和 Save Panel 入口。该提交不新增 Rust/C ABI，不改变日志记录 schema、不实现确认弹窗、复杂查询/filter DSL、按 workspace 独立配额、大小/时间轮转、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreExportsWorkspaceEntries`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testExportProjectLspProcessHealthLogExportsCurrentWorkspaceOnly`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): confirm lsp process health log clear`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 277 的 clear command 基础上补当前 workspace root 日志清空前确认。
  - 提交边界：AttoEditor 的 `clearProjectLspProcessHealthLog(...)` 在默认命令路径上先检查当前 workspace 是否有可清空记录，再弹出 AppKit warning alert；测试路径可注入 confirmation provider 或跳过确认以避免阻塞。该提交不新增 Rust/C ABI，不改变日志记录 schema、不实现复杂查询/filter DSL、按 workspace 独立配额、大小/时间轮转、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testClearProjectLspProcessHealthLogClearsCurrentWorkspaceOnly`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testClearProjectLspProcessHealthLogCanBeCancelledByConfirmation`
    - `git diff --check`
- 中间提交：`feat(app): retain lsp process health log per workspace`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 275 的 JSONL retention 起点基础上，把 process health log retention 从全局最近 N 行推进到按 workspace root URI 独立保留最近 N 条。
  - 提交边界：`AttoProjectLspProcessHealthLogStore.append(...)` 写入后按可解析记录的 `workspaceRootURI` 分桶保留最近 `maxPersistedEntries` 条，无法解析的旧行仍保留；单 workspace 的既有 retention 行为保持兼容。本提交不新增 Rust/C ABI，不改变日志记录 schema、不实现复杂查询/filter DSL、大小/时间轮转、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreRetainsLatestEntries`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreRetainsLatestEntriesPerWorkspace`
    - `git diff --check`
- 中间提交：`feat(app): rotate lsp process health log`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 274-280 的 JSONL process health log 基础上补大小与时间维度的轮转清理。
  - 提交边界：`AttoProjectLspProcessHealthLogStore` 新增 `maxLogFileBytes` 和 `maxEntryAge` 配置，append 后先按最新记录时间裁掉过期可解析记录，再按 workspace root URI 做条数 retention，最后按文件大小预算保留最新 JSONL 行；默认配置不改变日志 schema，不新增 Rust/C ABI，不实现复杂查询/filter DSL、自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreRetainsLatestEntries`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreRetainsLatestEntriesPerWorkspace`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStorePrunesEntriesOlderThanMaxAge`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStorePrunesOldestLinesBySizeBudget`
    - `git diff --check`
- 中间提交：`feat(app): filter lsp process health log`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 276 的显式 log 查询面板基础上补 store-backed filter DSL。
  - 提交边界：`AttoProjectLspProcessHealthLogStore` 新增 `queryRecent(...)` 与 `AttoProjectLspProcessHealthLogFilter`，支持 free text 以及 `server:` / `state:` / `availability:` / `process:` / `pid:` / `exit:` / `signal:` / `detail:` / `stderr:` / `tab:` / `view:` / `since:` / `until:`；`AttoEditor.LSP.ProjectProcessHealthLog` 面板输入变化时重新查询 store，并关闭 palette 自身 fuzzy filtering。本提交不新增 Rust/C ABI，不改变日志 schema、不实现自动崩溃恢复、更深层 core-owned LSP ownership schema 或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests.testProjectLspProcessHealthLogStoreQueriesWorkspaceEntriesWithFieldFilters`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthLogPanelUsesFieldFilterQuery`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthLogPanelShowsPersistedLog`
    - `git diff --check`
- 中间提交：`feat(app): auto-restart exited lsp servers`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；在阶段 262-282 的 process health 可观测性、restart command 和 log 基础上补自动崩溃恢复起点。
  - 提交边界：AttoEditor 在记录 process health status 时，如果事件带 core tab id、status/process 明确为 failed/exited、tab 仍打开且保存了 LSP launch config，则复用现有 `restartLspServer(...)` pipeline 自动重启该 tab 的 LSP session；同一 tab 在收到新的 healthy running status 前只自动尝试一次，避免崩溃循环。本提交不新增 Rust/C ABI，不改变 core LSP ownership schema、不实现跨 project recovery policy、指数退避、用户配置项或完整 dashboard 级健康视图。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthAutoRestartsExitedConfiguredTab`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartLspServerRestartsActiveTabSession`
    - `git diff --check`
- 中间提交：`feat(app): show lsp project health dashboard`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把 project LSP status failures、process health history 和 persisted process health log fallback 汇总到一个用户可打开的 dashboard 起点。
  - 提交边界：新增 Swift/App 级 `lsp.show_project_lsp_dashboard` 命令、Go 菜单项、`AttoEditor.LSP.ProjectDashboard` command-palette panel 和测试；dashboard 复用已有 status/process health/log store，不新增 Rust/C ABI，不改变日志 schema、不新增 Swift workspace ownership，不实现分组表格、趋势图、恢复策略配置、跨 project dashboard 或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): back off lsp auto restart`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把阶段 283 的 failed/exited 自动恢复起点推进为有界退避策略。
  - 提交边界：AttoEditor 现在按 core tab id 记录自动恢复 attempts 与 `nextAllowedAt`，默认最多 3 次，并按 5s/10s/20s 退避；healthy running status 会清除该 tab 的 recovery state。该提交不新增 Rust/C ABI，不改变 core LSP ownership schema、不实现跨 project recovery policy、用户配置项或完整 dashboard 产品化。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspAutoRestartUsesBackoffAndResetsAfterHealthyStatus`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspProcessHealthAutoRestartsExitedConfiguredTab`
    - `git diff --check`
- 中间提交：`feat(app): summarize lsp project health dashboard`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化阶段 284 的 project health dashboard 起点，让用户打开面板后先看到 project-level 摘要。
  - 提交边界：`AttoEditor.LSP.ProjectDashboard` 面板新增 summary 行，汇总 status failure 数、内存 process health 数、当前 workspace persisted log 数和 active recovery retry 状态；空 dashboard 仍保持不打开并 beep。本提交不新增 Rust/C ABI，不改变日志 schema、不新增跨 project dashboard、分组表格、趋势图、恢复策略配置或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): configure lsp auto restart`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；把阶段 285 的自动恢复退避策略从硬编码推进到用户可配置的 Preferences 策略。
  - 提交边界：`AttoPreferences` 新增 LSP auto-restart enabled、max attempts、base delay seconds 三个 stored/env/default 偏好；Preferences 窗口 Editor 页新增 LSP recovery 控件；AttoEditor 自动恢复路径改为按这些偏好决定是否重启、最大尝试次数和退避基准。该提交不新增 Rust/C ABI，不改变 core LSP ownership schema、不实现跨 project/per-server recovery policy、dashboard 内联配置或完整 dashboard 产品化。
  - 验证记录：
    - `swift test --package-path swift --filter AttoPreferencesTests.testLspAutoRestartDefaultsEnvStoredAndClamping`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspAutoRestartCanBeDisabledByPreferences`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspAutoRestartUsesBackoffAndResetsAfterHealthyStatus`
    - `git diff --check`
- 中间提交：`feat(app): show lsp recovery policy in dashboard`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，让阶段 287 的自动恢复配置在同一个健康排查入口可见。
  - 提交边界：`AttoEditor.LSP.ProjectDashboard` 在 summary 行后新增 Recovery Policy 行，展示当前生效的 LSP auto-restart 开关、最大尝试次数和退避基准；测试覆盖自定义 preferences 下 dashboard 行内容。该提交不新增 Rust/C ABI，不改变日志 schema、不实现 dashboard 内联编辑、分组/趋势、跨 project/per-server recovery policy 或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): group lsp dashboard by server`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，把 status/health/log 明细前面的概览推进为 server-level 分组摘要。
  - 提交边界：`AttoEditor.LSP.ProjectDashboard` 在 Recovery Policy 后新增按 LSP server 聚合的 Server 行，汇总该 server 的内存 health events、persisted logs、failed 计数和最新 process state；明细行、日志 schema、Rust/C ABI 和恢复执行策略保持不变。本提交不实现真正趋势图、跨 project dashboard、per-server recovery policy、dashboard 内联编辑或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): summarize lsp dashboard trends`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，把阶段 289 的分组摘要推进到基础时间窗口趋势摘要。
  - 提交边界：`AttoEditor.LSP.ProjectDashboard` 在 Recovery Policy 后新增 Trend 行，基于当前 workspace persisted process-health logs 的最新记录时间，展示最近 1 小时和 24 小时的 log/failed 计数；测试覆盖 dashboard trend 行内容。该提交不新增 Rust/C ABI，不改变日志 schema、不实现真正图表、跨 project dashboard、per-server recovery policy、dashboard 内联编辑或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): toggle lsp recovery from dashboard`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，把阶段 288 的 Recovery Policy 可见性推进到可直接执行的内联恢复配置起点。
  - 提交边界：`AttoEditor.LSP.ProjectDashboard` 在 Recovery Policy 后新增 Recovery Action 行，可直接从 dashboard 启用/禁用全局 LSP auto-restart，并写回 `AttoPreferences`；测试覆盖 command palette 选中 action 后偏好变化和状态反馈。该提交不新增 Rust/C ABI，不改变日志 schema、不实现 per-server recovery policy、max attempts/base delay 的 dashboard 内联编辑、真正图表、跨 project dashboard 或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): tune lsp recovery from dashboard`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，把阶段 291 的内联恢复配置从开关扩展到重试次数和退避基准。
  - 提交边界：`AttoEditor.LSP.ProjectDashboard` 的 Recovery Action 现在提供 max attempts +1/-1 和 base delay +1s/-1s 操作，直接写回 `AttoPreferences` 并显示状态反馈；测试覆盖 dashboard command 对 max attempts 和 base delay 的实际修改。该提交不新增 Rust/C ABI，不改变日志 schema、不实现 per-server recovery policy、自由输入/完整设置表单、真正图表、跨 project dashboard 或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `git diff --check`
- 中间提交：`feat(app): disable lsp recovery per server`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，把阶段 292 的 dashboard 内联恢复配置扩展到 server-level auto-restart 禁用列表。
  - 提交边界：`AttoPreferences` 新增按 server name / command 归一化的 LSP auto-restart disabled server keys；AttoEditor 自动恢复路径在全局 auto-restart 开启时也会跳过已禁用 server；`AttoEditor.LSP.ProjectDashboard` 的 Server 行展示 recovery enabled/disabled，并新增 server-level Recovery Action 切换该 server 的 auto-restart。该提交不新增 Rust/C ABI，不改变日志 schema、不实现 per-server max attempts/base delay、自由输入/完整设置表单、真正图表、跨 project dashboard 或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoPreferencesTests.testLspAutoRestartServerDisableListNormalizesAndToggles`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspAutoRestartCanBeDisabledForServerByPreferences`
    - `git diff --check`
- 中间提交：`feat(app): tune lsp recovery per server`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，把阶段 293 的 server-level auto-restart 策略从禁用列表扩展到 per-server max attempts 和 base delay。
  - 提交边界：`AttoPreferences` 新增按 server name / command 归一化的 LSP auto-restart max attempts / base delay override；AttoEditor 自动恢复路径优先读取 server-specific effective policy；`AttoEditor.LSP.ProjectDashboard` 的 Server 行展示该 server 的实际 max attempts/base delay，并新增 server-level Recovery Action 调整这两个值。该提交不新增 Rust/C ABI，不改变日志 schema、不实现自由输入/完整设置表单、真正图表、跨 project dashboard 或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoPreferencesTests.testLspAutoRestartServerPolicyOverridesNormalizeAndClamp`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspAutoRestartUsesServerSpecificBackoffPolicy`
    - `git diff --check`
- 中间提交：`feat(app): reset lsp recovery server policy`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；继续产品化 project LSP health dashboard，为阶段 293 的 per-server recovery override 增加回到全局策略的明确操作。
  - 提交边界：`AttoPreferences` 新增 server-level recovery policy override 检测和 reset API，可一次清理该 server 的 auto-restart disabled/max attempts/base delay override；`AttoEditor.LSP.ProjectDashboard` 的 Server 行标注 global/custom policy，并新增 Reset recovery policy action。该提交不新增 Rust/C ABI，不改变日志 schema、不实现自由输入/完整设置表单、真正图表、跨 project dashboard 或更深层 core-owned LSP ownership schema。
  - 验证记录：
    - `swift test --package-path swift --filter AttoPreferencesTests.testLspAutoRestartServerPolicyOverridesNormalizeAndClamp`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspDashboardPanelShowsStatusAndHealthSnapshots`
    - `git diff --check`
- 中间提交：`feat(ui): store project lsp server configs`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；为更深层 core-owned project/LSP ownership schema 建立最小承载点，把 project-level LSP launch metadata 放入 `MultiDocumentEditorUi` 而不是只留在 Swift tab 投影里。
  - 提交边界：`MultiDocumentEditorUi` 新增 project LSP server config store 和 snapshot 字段；C ABI 新增 `editor_core_ui_ffi_multi_document_set_project_lsp_servers_json(...)` / `editor_core_ui_ffi_multi_document_project_lsp_servers_json(...)`；Swift wrapper 新增 `EcuProjectLspServerConfig`、`setProjectLspServers(...)`、`projectLspServers()` 和 snapshot decode。该提交只建立 core-owned launch metadata round-trip，不改变 AttoEditor 实际 server start/restart 路径，不实现 typed lifecycle 启停、跨独立 project session 合并或完整 dashboard 产品化。
  - 验证记录：
    - `cargo build -p editor-core-ui-ffi --release`
    - `cargo test -p editor-core-ui --release multi_document_tracks_project_lsp_server_configs`
    - `cargo test -p editor-core-ui-ffi --release ffi_multi_document_exposes_tab_preview_split_and_search`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`
    - `git diff --check`
- 中间提交：`feat(app): mirror lsp launch configs to core`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；让 AttoEditor App 开始消费上一提交新增的 core-owned project LSP launch metadata store，把 Swift tab 投影中已有的 `lspServerConfig` 同步到 `MultiDocumentEditorUI.projectLspServers`。
  - 提交边界：只新增 App 层 metadata projection：打开/关闭 tab、session restore、workspace root 变更、project auto-start、restart 成功/失败恢复和显式切换到非 LSP 语言时，会把当前打开 tabs 的 launch config 写入 `MultiDocumentEditorUI.setProjectLspServers(...)`；args 仍按既有 LSP FFI 规则做 whitespace split，workspace root 使用当前 core workspace root。该提交不改变实际 LSP 启动/停止/restart 路径，不实现 typed lifecycle 启停、跨独立 project session 合并、更深层 ownership schema 或 dashboard 产品化。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspLaunchConfigsSyncToCoreProjectStore`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testWorkspaceRootChangeAutoStartsConfiguredOpenTabLsp`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testRestartProjectLspServersRestartsConfiguredOpenTabs`
    - `git diff --check`
- 中间提交：`feat(ui): store tab language metadata`
  - 所属任务：阶段 6 的 LSP workspace lifecycle 与 project-level 语言能力增量；为后续 core-owned project LSP typed lifecycle plan 补齐每个 open tab 的语言身份，让 `MultiDocumentEditorUi` 不只知道 document URI，也能知道该文档应匹配哪个 language id。
  - 提交边界：`MultiDocumentEditorUi` 新增 tab-level `language_id` metadata、query/set API 和 snapshot 字段；C ABI/header 新增 `editor_core_ui_ffi_multi_document_tab_language_id(...)` / `editor_core_ui_ffi_multi_document_set_tab_language_id(...)` 与 feature bit；Swift wrapper 新增 `EcuMultiDocumentTabSnapshot.languageId`、`tabLanguageId(...)`、`setTabLanguageId(...)`；AttoEditor 在 tab 语言配置应用时把归一化 language key 同步到 core tab。该提交不改变 LSP server 启动/停止/restart 行为，不实现 project server start plan、typed lifecycle 启停、跨独立 project session 合并或 dashboard 产品化。
  - 验证记录：
    - `cargo test -p editor-core-ui --release multi_document_tracks_tab_language_metadata`
    - `cargo test -p editor-core-ui-ffi --release ffi_multi_document_exposes_tab_preview_split_and_search`
    - `cargo test -p editor-core-ui-ffi --release ffi_feature_flags_include_semantic_tokens_requests`
    - `cargo build -p editor-core-ui-ffi --release`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testLoadsLibraryAndVersion`
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testProjectLspLaunchConfigsSyncToCoreProjectStore`
    - `cargo fmt --check`
    - `git diff --check`

## 阶段 7: Result panels 与持久工作台视图

### 目标

把 Problems、Outline、Symbols、Locations、References、Hierarchy、Code Lens、Document Links、Colors、Inlay Hints 等从零散 popup/quick panel 推进到统一持久工作台视图。

### 主要交付

- Core/UI model：
  - 定义 panel data sources 和 history entries。
  - 每个 result item 保留 URI、range、severity/kind、source、request sequence、stale/error metadata。
  - 支持 refresh、pin result、clear stale、jump navigation。
- App：
  - Problems panel：workspace + active doc + stale status。
  - Outline/Symbols panel：Tree-sitter/LSP sources 可区分。
  - Locations/References panel：保留历史查询。
  - Hierarchy panel：可展开、刷新、跳转。
  - Code Lens / Inlay Hint / Document Links / Colors：有可见状态和操作入口。

### 验证

- Swift tests 覆盖 panel model projection。
- AppKit tests 覆盖 panels 展示、过滤、跳转、stale/error 状态。
- UI screenshot tests 覆盖 panel 布局。

### 提交

- `feat(app): add persistent lsp workbench panels`
- 中间提交：`feat(app): add code lens workbench panel`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把 Code Lens 从状态栏数量和 transient command palette 操作推进到可保持打开、可过滤、可键盘执行的持久 panel。
  - 提交边界：新增 `AttoCodeLensPanelController`，为 Code Lens panel 提供稳定 AppKit identifiers、filter/search、row selection、Enter 执行和关闭行为；AttoEditor 新增 `lsp.show_code_lens_panel` command、Go 菜单入口、VC 测试钩子，并在 Code Lens refresh 后同步更新已打开的持久 panel。该提交不改变 LSP Code Lens request/resolve 协议、renderer inline decorations、executeCommand 语义，也不实现统一多 panel dock/workbench 容器。
  - 验证记录：
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testCodeLensPanelExposesStableIdentifiersAndFiltersRows`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCodeLensPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): add inlay hints workbench panel`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把 Inlay Hints 从 inline decorations、hover/click resolve 和 refresh HUD 推进到可保持打开、可过滤、可键盘 resolve 的持久 panel。
  - 提交边界：新增 `AttoLspInlayHintParser` 从 active decorations 提取 inlay hint items，新增 `AttoInlayHintPanelController` 提供稳定 AppKit identifiers、filter/search、row selection、Enter resolve 和关闭行为；AttoEditor 新增 `lsp.show_inlay_hints_panel` command、Go 菜单入口、VC 测试钩子，并在 Inlay Hints refresh 后同步更新已打开的持久 panel。该提交不改变 LSP inlayHints / resolve 请求协议、不改变 renderer inline virtual text，也不实现跨 tab/project Inlay Hints history 或统一 dock/workbench 容器。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspInlayHintResolverTests.testParserProjectsInlayHintDecorations`
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testInlayHintPanelExposesStableIdentifiersAndFiltersRows`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testInlayHintPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): add document links workbench panel`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把 Document Links 从 underline/hit-test/Cmd-click 和 refresh HUD 推进到可保持打开、可过滤、可键盘 open/resolve 的持久 panel。
  - 提交边界：新增 `AttoLspDocumentLinkParser` 从 active decorations 提取 document link items，新增 `AttoDocumentLinkPanelController` 提供稳定 AppKit identifiers、filter/search、row selection、Enter open/resolve 和关闭行为；AttoEditor 新增 `lsp.show_document_links_panel` command、Go 菜单入口、VC 测试钩子，并在 Document Links refresh 后同步更新已打开的持久 panel。该提交不改变 LSP documentLink / resolve 请求协议、不改变 renderer underline/hit-test，也不实现跨 tab/project Document Links history 或统一 dock/workbench 容器。
  - 验证记录：
    - `swift test --package-path swift --filter AttoLspDocumentLinkParserTests.testParserProjectsDocumentLinkDecorations`
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testDocumentLinkPanelExposesStableIdentifiersAndFiltersRows`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDocumentLinkPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): add document colors workbench panel`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把 Document Colors 从 transient command palette / color picker 结果推进到可保持打开、可过滤、可键盘请求 color presentations 的持久 panel。
  - 提交边界：新增 `AttoDocumentColorPanelController` 展示 swatch、稳定 AppKit identifiers、filter/search、row selection、Enter 请求 color presentations 和关闭行为；AttoEditor 新增 `lsp.show_document_colors_panel` command、Go 菜单入口、VC 测试钩子，并让已有 document color 结果在持久 panel 打开时同步更新。该提交不改变 LSP documentColor / colorPresentation 请求协议、不改变既有 `lsp.document_colors` quick palette 和 `lsp.pick_document_color` picker 语义，也不实现跨 tab/project Colors history 或统一 dock/workbench 容器。
  - 验证记录：
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testDocumentColorPanelExposesStableIdentifiersAndFiltersRows`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDocumentColorPanelUsesDocumentColorResults`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): add hierarchy workbench panel`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把 Call/Type Hierarchy 的 children 结果从 transient quick panel 推进到可重新打开、可保持打开、可过滤、可键盘跳转的持久 result panel 起点。
  - 提交边界：新增 `AttoHierarchyPanelController` 提供稳定 AppKit identifiers、filter/search、row selection、Enter 跳转和关闭行为；AttoEditor 新增最近一次 hierarchy result snapshot、`lsp.show_hierarchy_panel` command、Go 菜单入口和 VC 测试钩子，并让已有 hierarchy quick result flow 在产生结果时同步更新已打开的持久在线 panel。该提交不改变 LSP call/type hierarchy prepare/children 请求协议、不移除既有 quick panel，也不实现真正树状展开、children refresh、跨 tab/project Hierarchy history 或统一 dock/workbench 容器。
  - 验证记录：
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testHierarchyPanelExposesStableIdentifiersAndFiltersRows`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testHierarchyPanelUsesLastHierarchyResults`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): add lsp workbench panel index`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；建立跨 result family 的统一 LSP Workbench 入口，把各独立持久在线 panel 先编排到一个可过滤、可键盘打开的目录面板。
  - 提交边界：新增 `AttoLspWorkbenchPanelController`，汇总 Problems、Workspace Problems、Locations、Symbols、Workspace Outline、Code Lens、Inlay Hints、Document Links、Document Colors 和 Hierarchy 的当前状态/数量/可用性；AttoEditor 新增 `lsp.show_workbench_panel` command、Go 菜单入口、VC 测试钩子和具体 panel 打开分发。该提交不把各 panel 迁入真正内嵌 dock，不改变具体 LSP request/result 协议，也不实现 pin/history/stale/error 的统一数据模型。
  - 验证记录：
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testLspWorkbenchPanelExposesStableIdentifiersAndFiltersRows`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testMainMenuItemsUseCommandIDsAndResolvedKeymap`
    - `git diff --check`
- 中间提交：`feat(app): show lsp workbench lifecycle status`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；让统一 LSP Workbench 入口继续消费 Locations/Symbols 已有 lifecycle entry，把独立持久在线 panel 中的 Fresh/Stale/Error 状态推进到跨 result family 目录层。
  - 提交边界：只更新 Workbench 的 Locations/Symbols 行状态文本，展示结果数量、Fresh/Stale/Error、Result sequence、family 和 title，并让 visible Workbench 在当前 Locations/Symbols entry 被标记 stale/error 时同步刷新。该提交不引入统一 pin/history 数据模型，不改变 Locations/Symbols result store 语义，不迁移到真正内嵌 dock，也不实现跨 tab/project result history。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelShowsLifecycleStateForLocationsAndSymbols`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `git diff --check`
- 中间提交：`feat(app): show workbench diagnostics lifecycle`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把 Workbench 的 Problems / Workspace Problems 行接到已有 diagnostics lifecycle entry，继续把 stale metadata 从独立 Problems/status 路径推进到统一 result family 目录层。
  - 提交边界：只更新 Workbench 的 Problems / Workspace Problems 行状态文本，在已有 diagnostics lifecycle entry 存在时展示结果数量、Fresh/Stale、Result sequence、family 和 title，并让 visible Workbench 在 status update 记录新 diagnostics lifecycle 后同步刷新。该提交不改变 diagnostics store schema，不新增统一 pin/history 数据模型，不实现所有 result family 的统一 stale/error schema，也不迁移到真正内嵌 dock。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelShowsDiagnosticsLifecycleState`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelShowsLifecycleStateForLocationsAndSymbols`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `git diff --check`
- 中间提交：`feat(app): split workbench symbols outline entries`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；修正统一 LSP Workbench 中 Symbols 与 Workspace Outline 共用 `lspSymbolResultStore` 带来的入口污染，让两个 result family 在 Workbench 层按 lifecycle entry 明确分流。
  - 提交边界：Workbench 的 Symbols 行只消费最近的非 Workspace Outline symbol lifecycle entry；Workspace Outline 行消费 Outline entry 并显示结果数量、Fresh/Stale/Error、Result sequence、family 和 title；从 Workbench 打开 Symbols 时也会打开该非 Outline entry。该提交不改变 `lsp.show_symbols_panel` 的直接命令语义，不新增独立 Outline store lifecycle schema，不实现统一 pin/history 数据模型或真正内嵌 dock。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelKeepsSymbolsAndWorkspaceOutlineEntriesSeparate`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelShowsLifecycleStateForLocationsAndSymbols`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `git diff --check`
- 中间提交：`feat(app): show workbench color lifecycle`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；让统一 LSP Workbench 的 Document Colors 行消费已有 `document_colors` result event metadata，把颜色结果从简单 cached 数量推进到带 sequence/family/title 的 result family 状态。
  - 提交边界：Workbench 的 Document Colors 行在已有颜色结果和 `document_colors` event 时展示颜色数量、Fresh、Result sequence、family 和 title；没有结果仍显示 `request on open`，旧无 event 的缓存状态仍保留 cached fallback。该提交不改变 Document Colors request/result/picker/panel 语义，不消费 color presentation event，不新增统一 pin/history 数据模型或真正内嵌 dock。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelShowsDocumentColorLifecycleEvent`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `git diff --check`
- 中间提交：`feat(app): show workbench hierarchy lifecycle`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；让 Hierarchy result 写入已有 App 层 result event stream，并让统一 LSP Workbench 的 Hierarchy 行消费该 event metadata。
  - 提交边界：新增 `AttoLspResultLifecycleEvent.Payload.hierarchy`，`recordHierarchyPanelSnapshot(...)` 记录 `hierarchy` family event；Workbench 的 Hierarchy 行在已有 hierarchy result event 时展示结果数量、Fresh、Result sequence、family 和 title，旧无 event 的 snapshot 仍保留数量 fallback。该提交不改变 call/type hierarchy request/prepare/children 协议，不实现树状展开或 children refresh，也不新增统一 pin/history 数据模型或真正内嵌 dock。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testHierarchyPanelUsesLastHierarchyResults`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests`
    - `git diff --check`
- 中间提交：`feat(app): show workbench auxiliary lifecycle`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；让 Code Lens、Inlay Hints 和 Document Links 的成功结果写入已有 App 层 result event stream，并让统一 LSP Workbench 对应行消费该 event metadata。
  - 提交边界：新增 `AttoLspResultLifecycleEvent.Payload.codeLens` / `inlayHints` / `documentLinks`，在 Code Lens refresh 和 auxiliary refresh 成功消费结果时记录 `code_lens`、`inlay_hints`、`document_links` family event；Workbench 三行在已有 event 时展示数量、Fresh、Result sequence、family 和 title，旧的 decorations count fallback 保留。该提交不改变 code lens / inlay hints / document links 的 LSP request/resolve 协议，不改变 decorations schema，不新增统一 pin/history 数据模型或真正内嵌 dock。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCodeLensPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testInlayHintPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDocumentLinkPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests`
    - `git diff --check`
- 中间提交：`feat(app): mark workbench event results stale`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把统一 LSP Workbench 中 event-backed result family 的 Fresh 状态推进到可被当前文档编辑标记 Stale 的最小 lifecycle schema。
  - 提交边界：`AttoLspResultLifecycleEvent` 新增 `state`，`AttoLspResultEventStream` 可按 family 更新最近事件状态；Workbench event-backed 行使用 event state 显示 Fresh/Stale；`markCurrentLspResultPanelsStale(...)` 会同步标记 `code_lens`、`inlay_hints`、`document_links`、`document_colors` 和 `hierarchy` 最近事件。该提交不新增 error propagation、不改变 event payload/schema 语义、不新增 pin/history 模型、不迁移到真正内嵌 dock，也不改变具体 LSP result/decoration 协议。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCodeLensPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testInlayHintPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDocumentLinkPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests`
    - `git diff --check`
- 中间提交：`feat(app): show workbench event result errors`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；把统一 LSP Workbench 中 event-backed result family 的 lifecycle state 从 Fresh/Stale 推进到可显示 Error 的起点。
  - 提交边界：新增 `markCurrentLspEventResultError(...)`，按 family 将最近 result event 状态更新为 `.error(...)`；Code Lens refresh 和 Auxiliary refresh 的 unavailable/request failed/timeout/failed/result-error 分支会把 `code_lens`、`inlay_hints`、`document_links` 的最近 event 标为 Error；Document Colors 与 Hierarchy 先通过同一通用方法具备 Workbench error state 展示能力。该提交不改变 LSP request/resolve 协议，不新增 error event payload，不实现全部 document color/hierarchy 请求流的自动 error propagation，不新增 pin/history 模型或真正内嵌 dock。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCodeLensPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testInlayHintPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDocumentLinkPanelUsesDerivedDecorations`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelShowsDocumentColorLifecycleEvent`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testHierarchyPanelUsesLastHierarchyResults`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testLspWorkbenchPanelSummarizesResultFamilies`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests`
    - `git diff --check`
- 中间提交：`feat(app): route color hierarchy workbench errors`
  - 所属任务：阶段 7 的 Result panels 与持久工作台视图增量；补齐 Document Colors 与 Hierarchy 真实请求链路到统一 LSP Workbench event-backed Error 状态的自动传播。
  - 提交边界：Document Colors 的 unavailable、request failed、timeout 和 take failed 分支会把最近 `document_colors` event 标为 Error；Hierarchy 的 unavailable、position failed、prepare request failed、prepare timeout/take failed、children request failed 和 children timeout/take failed 分支会把最近 `hierarchy` event 标为 Error；对应测试从直接调用通用 helper 改为已有结果后走真实 disabled request 路径。该提交不改变 LSP request/resolve 协议，不新增 result payload 或 error event payload，不把 empty/no results 视为 Error，不消费 color presentation event，不新增 pin/history 模型或真正内嵌 dock。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(LspWorkbenchPanelShowsDocumentColorLifecycleEvent|HierarchyPanelUsesLastHierarchyResults|CodeLensPanelUsesDerivedDecorations|InlayHintPanelUsesDerivedDecorations|DocumentLinkPanelUsesDerivedDecorations|LspWorkbenchPanelSummarizesResultFamilies)'`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(LspWorkbenchPanelShowsLifecycleStateForLocationsAndSymbols|LspWorkbenchPanelShowsDiagnosticsLifecycleState)'`
    - `swift test --package-path swift --filter AttoLspResultLifecycleStoreTests`
    - `git diff --check`

## 阶段 8: Command、menu、keymap、palette 与 Sublime 行为矩阵

### 目标

补齐 Sublime-like 操作体验中的命令系统缺口，让命令从 id、参数、上下文、启用状态、key binding、menu、palette 到 App action 都有统一模型。

### 主要交付

- Command registry：
  - command id、title、category、arguments schema、enablement predicate、side effects、undo grouping。
  - core command、UI command、App/platform command 分层。
- Keymap：
  - default keymap。
  - user override。
  - context-specific bindings。
  - conflict diagnostics。
  - Sublime-compatible common command names where feasible。
- Menus/palette：
  - menu item 与 command id 绑定。
  - enabled/disabled 状态来自 command context。
  - command palette 支持 arguments、recent commands、fuzzy search、source category。
- Macro/plugin 起点：
  - 先支持 command sequence macro。
  - 定义插件能力边界和非目标。
- Sublime behavior matrix：
  - 记录常用编辑、选择、多光标、搜索、goto、fold、view、project 命令的支持状态。
  - 不包含 Sublime syntax 扩展。

### 验证

- Swift tests 覆盖 keymap parsing、conflict、command enablement。
- AppKit tests 覆盖菜单状态、palette 调用、快捷键分派。
- Regression tests 覆盖常用 Sublime-like editing commands。

### 提交

- `feat(app): unify commands keymaps and palette`
- 中间提交：`feat(app): show command palette categories`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；让主命令 palette 不只展示裸标题，也展示 command registry 中已有的来源分组，并让 fuzzy 搜索能匹配命令 title、group 和 id。
  - 提交边界：`AttoCommandPaletteController` 新增可选 `showsCommandGroups` 开关；主 command palette 开启后把 row 显示为 `Group - Title`，同时过滤时把 `title/group/id` 纳入搜索文本；LSP/Project/Quick Open 等复用同一 controller 的结果 palette 默认保持原有标题展示。本提交不改变 command registry schema、不实现 recent commands、不实现宏录制/回放、不改变 keymap resolver 或菜单 enablement。
  - 验证记录：
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testCommandPaletteShowsCommandGroupsAndFiltersByMetadata`
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testCommandPalettePanelExposesStableIdentifiers`
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testCommandPaletteSupportsInitialQueryAndDynamicReload`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesMetadataAndAvailability`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testDefaultCommandPaletteIncludesCoreEditorCommandIDs`
    - `git diff --check`
- 中间提交：`feat(app): order recent palette commands`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为主命令 palette 增加 bounded in-memory recent command ordering，让统一 command id 路径触发的命令能在下一次打开 command palette 时排在前面。
  - 提交边界：`AttoAppDelegate` 维护最近 command id 列表，命令通过统一 `executeCommand` / palette command wrapper 成功触发后会移动到最近列表顶部；主命令 palette 的 `defaultCommands()` 会把最近命令排在静态命令之前，重复触发会去重并移动到顶部，无效参数或未知/禁用命令不污染历史。本提交不做跨启动持久化、不改变 Quick Open/LSP result palette、不实现命令参数 prompt/replay、不实现宏录制/回放或插件命令入口。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandPaletteOrdersRecentCommandsFirst`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testExecuteCommandUsesRegisteredCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testExecuteCommandAcceptsTypedArgumentsForParameterizedCommands`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandRegistryCarriesMetadataAndAvailability`
    - `swift test --package-path swift --filter AttoAccessibilityIdentifierTests.testCommandPaletteShowsCommandGroupsAndFiltersByMetadata`
    - `git diff --check`
- 中间提交：`feat(app): persist recent palette commands`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；把主命令 palette recent command ordering 从单 delegate 内存状态推进到跨启动可恢复的持久状态。
  - 提交边界：新增 `AttoRecentCommandStore`，默认 App delegate 使用 `UserDefaults.standard` 保存最近 command id，测试构造 delegate 默认不读写全局 defaults；recent list 读取和保存都会去空、去重并限制最大数量；成功触发的统一 command id 路径仍是唯一写入点。本提交不持久化命令参数、不实现参数 prompt/replay、不改变 Quick Open/LSP result palette、不实现宏录制/回放或插件命令入口。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandPalettePersistsRecentCommandsAcrossDelegates`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandPaletteOrdersRecentCommandsFirst`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testExecuteCommandUsesRegisteredCommandIDs`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testExecuteCommandAcceptsTypedArgumentsForParameterizedCommands`
    - `git diff --check`
- 中间提交：`feat(app): replay recent palette arguments`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；把主命令 palette recent command 从仅恢复 command id 推进到可恢复最近一次 typed arguments，并让最近的参数化命令可从 palette 直接 replay。
  - 提交边界：`AttoRecentCommandStore` 持久化 recent command record，保留旧 command id defaults key 的读取兼容；统一 command wrapper 在成功执行后记录 normalized typed arguments；主 command palette 排序 recent commands 时会包装有参数的命令，palette 无显式参数触发时 replay 最近参数，直接 `executeCommand(id:)`、菜单和 keymap 无参数路径仍使用未 replay 的命令表，避免静默套用历史参数。本提交不实现通用参数 prompt UI、不实现宏录制/回放、不改变 Quick Open/LSP result palette、不实现 package/plugin command 入口。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandPaletteReplaysRecentCommandArguments|CommandPalettePersistsRecentCommandArgumentsAcrossDelegates|CommandPalettePersistsRecentCommandsAcrossDelegates|CommandPaletteOrdersRecentCommandsFirst|ExecuteCommandAcceptsTypedArgumentsForParameterizedCommands)'`
    - `git diff --check`
- 中间提交：`feat(app): prompt palette command arguments`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；让主命令 palette 能根据 command schema 为参数化命令打开通用参数表单，并把最近参数作为可编辑初始值。
  - 提交边界：`AttoCommandPaletteCommand` 增加参数 prompt 标志和 initial arguments；主 command palette 注入 `AttoCommandArgumentPrompt`，支持 string/integer/number/boolean/json 和 choices 的基础 AppKit 表单、schema 校验与错误重试；Quick Open/LSP result palette 等复用 controller 的非主 palette 默认不启用参数 prompt。最近参数 command 仍保留 `run()` replay 语义，但在主 command palette UI 中会先以最近参数预填表单。本提交不实现宏录制/回放、不实现 package/plugin command 入口、不做 Sublime overlay/panel 级参数 UI 复刻，也不改变菜单/keymap 无参数执行边界。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(AccessibilityIdentifierTests.test(CommandPalettePromptsForParameterizedCommands|CommandPaletteShowsCommandGroupsAndFiltersByMetadata|CommandPalettePanelExposesStableIdentifiers)|EditorCommandTests.test(CommandPaletteReplaysRecentCommandArguments|CommandPalettePersistsRecentCommandArgumentsAcrossDelegates))'`
    - `git diff --check`
- 中间提交：`feat(app): record command macros`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；开始消费 command registry 里的 `macroPolicy`，为统一 command id 路径提供基础 sequence macro 录制/回放。
  - 提交边界：AttoEditor App 新增 in-memory last macro buffer，`macro.toggle_recording` / `macro.replay_last` 命令、Tools 菜单和 `ctrl+q` / `ctrl+shift+q` 默认 keymap；录制只接收 `.recordable` 和带显式 typed arguments 的 `.recordableWithArguments` 命令，过滤 `.promptRequired` / `.notRecordable`，回放时不会递归录制。本提交不实现宏持久化文件、不实现命名/多宏管理、不实现 Sublime `.sublime-macro` 文件兼容、不实现 plugin/package command runtime，也不记录命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroRecordsAndReplaysCommandSequence|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testKeymapParsesSublimeStyleBindingsAndOverridesDefaults`
    - `git diff --check`
- 中间提交：`feat(app): persist last command macro`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；把 last command macro 从单次内存状态推进到 `.sublime-macro` 兼容文件，让 App 启动后可恢复最近一次录制的宏。
  - 提交边界：新增 `AttoMacroStore`，默认路径为用户 Application Support 下的 `Macros/Last Macro.sublime-macro`；停止录制时把 sanitized last macro 写为 Sublime 风格 JSON array，每项包含 `command` 和可选 `args`；App 默认 delegate 初始化时加载该文件，测试构造 delegate 继续通过注入 store 避免读写全局用户状态；JSON object/array/null 参数以 typed `.json` 形式回读，基础 string/integer/number/boolean 参数保持 typed 值。本提交不实现命名/多宏管理、导入导出 UI、完整 Sublime `.sublime-macro` 运行语义、plugin/package command runtime，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroPersistsSublimeMacroFileAcrossDelegates`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroRecordsAndReplaysCommandSequence|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies)'`
    - `swift test --package-path swift --filter AttoEditorCommandTests.testKeymapParsesSublimeStyleBindingsAndOverridesDefaults`
    - `git diff --check`
- 中间提交：`feat(app): save named command macros`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；在 last macro 持久化基础上提供命名 `.sublime-macro` 文件的保存、枚举和按名称回放起点。
  - 提交边界：`AttoMacroStore` 新增命名 macro 文件 URL 校验、保存、读取和名称列表；AttoEditor 新增 `macro.save_named` / `macro.replay_named` 参数化命令和 Tools 菜单入口，命令 palette 可通过 `name` 参数 prompt 保存当前 last macro 或选择已有命名 macro 回放；`macro.replay_named` 的 schema choices 来自当前宏目录，直接参数执行会拒绝未知命名宏。本提交不实现宏重命名/删除 UI、导入导出 UI、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroSavesAndReplaysNamedSublimeMacroFiles`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap|CommandMacroPersistsSublimeMacroFileAcrossDelegates|CommandMacroRecordsAndReplaysCommandSequence)'`
    - `git diff --check`
- 中间提交：`feat(app): manage named command macros`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；补齐命名 `.sublime-macro` 的基础重命名和删除入口，让多宏管理不再只能创建和回放。
  - 提交边界：`AttoMacroStore` 新增命名 macro 删除、重命名、not found 和 already exists 错误；AttoEditor 新增 `macro.rename_named` / `macro.delete_named` 参数化命令和 Tools 菜单入口，命令 palette 可选择已有宏名并输入新名称；相关命令在没有命名宏或正在录制时禁用。本提交不实现独立宏管理面板、删除确认 UI、导入导出 UI、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroRenamesAndDeletesNamedSublimeMacroFiles`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap|CommandMacroSavesAndReplaysNamedSublimeMacroFiles)'`
    - `git diff --check`
- 中间提交：`feat(app): import export command macros`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 补齐基础导入/导出入口，让外部 Sublime 风格宏文件能进入 AttoEditor 宏目录，也能从命名宏导出为文件。
  - 提交边界：`AttoMacroStore` 新增外部 `.sublime-macro` 路径校验、导入和导出；AttoEditor 新增 `macro.import_file` / `macro.export_named` 参数化命令和 Tools 菜单入口，command palette 参数表单可输入源/目标路径与命名宏名称，导入时会解码并重新写为 AttoEditor 兼容 JSON，导出时会把已有命名宏写到目标 `.sublime-macro` 文件。本提交不实现独立宏管理面板、原生 NSOpenPanel/NSSavePanel 文件选择流程、删除确认 UI、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroImportsAndExportsSublimeMacroFiles`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles)'`
    - `git diff --check`
- 中间提交：`feat(app): pick command macro files`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；把导入/导出宏的菜单和无参数命令路径从手填路径推进到原生文件选择流程。
  - 提交边界：`macro.import_file` 无参数执行时打开 `NSOpenPanel` 选择 `.sublime-macro` 文件，并用文件名作为默认宏名；`macro.export_named` 无参数执行时选择已有命名宏并打开 `NSSavePanel` 写出 `.sublime-macro`；保留参数化 command palette 路径用于显式路径和自动化；测试通过注入 selection provider 覆盖无参数分支。本提交不实现独立宏管理面板、删除确认 UI、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroImportExportUsesNativeFileSelectionProviders`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroImportsAndExportsSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): confirm command macro deletion`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 删除补上确认 UI，降低从 Tools 菜单或 command palette 误删宏文件的风险。
  - 提交边界：`macro.delete_named` 在真正删除前通过 AppKit warning alert 确认；测试路径可注入 confirmation provider 覆盖取消/确认两条路径。该提交不实现独立宏管理面板、批量删除、回收站/undo、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroRenamesAndDeletesNamedSublimeMacroFiles`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroImportExportUsesNativeFileSelectionProviders|CommandMacroImportsAndExportsSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): batch delete command macros`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 补齐批量删除 command/menu 起点，让多宏清理不需要逐个执行单宏删除。
  - 提交边界：新增 `macro.delete_named_batch` 参数化命令和 Tools 菜单入口，参数 `names` 使用 JSON string array；App 侧会去重并验证命名宏存在，复用删除确认 UI 一次确认后批量删除；`AttoMacroStore` 新增批量删除和名称归一化 helper。该提交不实现独立宏管理面板、回收站/undo、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroBatchDeletesNamedSublimeMacroFiles`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|CommandMacroImportExportUsesNativeFileSelectionProviders|CommandMacroImportsAndExportsSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): undo command macro deletion`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 删除补齐最近一次 undo 起点，降低单删或批量删除后的不可恢复风险。
  - 提交边界：删除前加载并保存最近一次被删除宏的 command sequence 快照；新增 `macro.undo_delete` 命令和 Tools 菜单入口，恢复时不覆盖之后新建的同名宏，恢复成功后清空 undo 记录；单宏删除和批量删除都会替换该最近一次 undo 记录。该提交不实现多级删除历史、跨启动回收站、独立宏管理面板、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|CommandMacroBatchDeletesNamedSublimeMacroFiles)'`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|CommandMacroImportExportUsesNativeFileSelectionProviders|CommandMacroImportsAndExportsSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): stack command macro deletion undo`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；把命名 `.sublime-macro` 删除 undo 从最近一次快照推进到 bounded 多级历史，让连续单删/批删可按后进先出顺序逐步恢复。
  - 提交边界：App delegate 将删除 undo 状态改为最多 20 条的 LIFO 栈，单宏删除和批量删除成功后 push 新记录，`macro.undo_delete` 成功恢复后只弹出最近记录，失败时保留历史以便用户处理冲突后重试。该提交不实现跨启动回收站、删除历史 UI、独立宏管理面板、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|CommandMacroBatchDeletesNamedSublimeMacroFiles)'`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|CommandMacroImportExportUsesNativeFileSelectionProviders|CommandMacroImportsAndExportsSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): persist command macro delete history`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；把命名 `.sublime-macro` 删除 undo 历史从 App 内存推进到宏目录持久化，让重启或重新创建 App delegate 后仍能恢复删除记录。
  - 提交边界：`AttoMacroStore` 新增隐藏 JSON 删除历史文件读写，保存 bounded undo stack 的宏名和 command sequence；App delegate 初始化时加载该历史，push/pop 后写回，空历史会移除文件；该 JSON 不使用 `.sublime-macro` 扩展，不污染命名宏列表。该提交不实现可浏览回收站 UI、删除历史选择/清理 UI、独立宏管理面板、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter AttoEditorCommandTests.testCommandMacroUndoDeleteHistoryPersistsAcrossDelegates`
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroUndoDeleteHistoryPersistsAcrossDelegates|CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|CommandMacroImportExportUsesNativeFileSelectionProviders|CommandMacroImportsAndExportsSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): browse command macro delete history`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 删除历史补齐可浏览入口，让用户可以查看持久化删除历史并选择恢复非最近一条记录。
  - 提交边界：新增 `macro.show_delete_history` 命令和 Tools 菜单入口，复用 command palette 以最近优先显示删除历史记录；选择记录会恢复该记录并从历史中移除，`macro.undo_delete` 仍保持恢复最近记录。该提交不实现独立宏管理面板、批量选择/清理删除历史、完整可视化回收站、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroDeleteHistoryPanelRestoresSelectedEntry|CommandMacroDeleteHistoryWithoutWindowDoesNotRestoreEntry|CommandMacroUndoDeleteHistoryPersistsAcrossDelegates|CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): clear command macro delete history`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 删除历史补齐显式清空入口，让用户可以主动移除持久化 restore 历史。
  - 提交边界：新增 `macro.clear_delete_history` 命令和 Tools 菜单入口；清空前通过独立 warning confirmation 确认，确认后清空内存 undo stack、移除持久化隐藏 JSON，并关闭已打开的删除历史 palette。该提交不实现独立宏管理面板、删除历史单条清理/批量选择管理、完整可视化回收站、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroClearDeleteHistoryClearsPersistentUndoStack|CommandMacroDeleteHistoryPanelRestoresSelectedEntry|CommandMacroDeleteHistoryWithoutWindowDoesNotRestoreEntry|CommandMacroUndoDeleteHistoryPersistsAcrossDelegates|CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): remove command macro delete history entries`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 删除历史补齐单条移除入口，让用户可以丢弃指定 restore 记录而不影响其他删除历史。
  - 提交边界：新增 `macro.remove_delete_history_entry` 参数化命令和 Tools 菜单入口；参数 `index` 使用最近优先的 1-based 删除历史索引，并通过当前历史生成 choices。移除前独立确认，确认后删除指定历史记录、持久化隐藏 JSON，并刷新或关闭已打开的删除历史 palette。该提交不实现独立宏管理面板、删除历史批量选择管理、完整可视化回收站、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroRemoveDeleteHistoryEntryRemovesPersistentSelectedRecord|CommandMacroClearDeleteHistoryClearsPersistentUndoStack|CommandMacroDeleteHistoryPanelRestoresSelectedEntry|CommandMacroDeleteHistoryWithoutWindowDoesNotRestoreEntry|CommandMacroUndoDeleteHistoryPersistsAcrossDelegates|CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): batch remove command macro delete history entries`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；为命名 `.sublime-macro` 删除历史补齐基于 command 参数的批量移除入口，让用户可以一次丢弃多条 restore 记录而保留未选记录。
  - 提交边界：新增 `macro.remove_delete_history_entries` 参数化命令和 Tools 菜单入口；参数 `indices` 使用最近优先的 1-based JSON 整数数组，会去重、校验范围并按内部 stack index 倒序移除。移除前独立确认，确认后持久化隐藏 JSON，并刷新或关闭已打开的删除历史 palette。该提交不实现独立宏管理面板、可视化删除历史批量选择、完整可视化回收站、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroRemoveDeleteHistoryEntriesRemovesPersistentSelectedRecords|CommandMacroRemoveDeleteHistoryEntryRemovesPersistentSelectedRecord|CommandMacroClearDeleteHistoryClearsPersistentUndoStack|CommandMacroDeleteHistoryPanelRestoresSelectedEntry|CommandMacroDeleteHistoryWithoutWindowDoesNotRestoreEntry|CommandMacroUndoDeleteHistoryPersistsAcrossDelegates|CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`
- 中间提交：`feat(app): manage command macro delete history visually`
  - 所属任务：阶段 8 的 Command、menu、keymap、palette 与 Sublime 行为矩阵增量；把命名 `.sublime-macro` 删除历史从 command 参数批量移除推进到可视化多选管理面板，让用户可以直接选择删除历史项并执行恢复、移除或清空。
  - 提交边界：新增 `macro.manage_delete_history` 命令和 Tools 菜单入口，打开独立 AppKit 删除历史管理面板；面板按最近优先列出持久化删除历史，支持多选移除、单选恢复和清空历史，并复用既有确认、持久化和 restore/remove/clear 逻辑；删除历史 palette 与管理面板在历史变更后同步刷新或关闭。该提交不实现完整命名宏管理面板、完整可视化回收站、完整 Sublime package/plugin command runtime、完整 `.sublime-macro` 扩展语义，也不捕获命令内部 modal prompt 产生的参数。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoEditorCommandTests.test(CommandMacroDeleteHistoryPanelSupportsVisualBatchRemovalAndRestore|CommandMacroRemoveDeleteHistoryEntriesRemovesPersistentSelectedRecords|CommandMacroRemoveDeleteHistoryEntryRemovesPersistentSelectedRecord|CommandMacroClearDeleteHistoryClearsPersistentUndoStack|CommandMacroDeleteHistoryPanelRestoresSelectedEntry|CommandMacroDeleteHistoryWithoutWindowDoesNotRestoreEntry|CommandMacroUndoDeleteHistoryPersistsAcrossDelegates|CommandMacroUndoDeleteUsesMultiLevelHistory|CommandMacroBatchDeletesNamedSublimeMacroFiles|CommandMacroRenamesAndDeletesNamedSublimeMacroFiles|DefaultCommandPaletteIncludesCoreEditorCommandIDs|CommandRegistryCarriesParameterSchemasAndMacroPolicies|MainMenuItemsUseCommandIDsAndResolvedKeymap)'`
    - `git diff --check`

## 阶段 9: 配置、偏好与 capability DTO 完整性

### 目标

让 Swift 可完整读取和设置 core/UI/App 需要的配置，并让能力协商有可审计 DTO，而不是 scattered flags。

### 主要交付

- Config DTO：
  - editor preferences：font、tab size、indent、wrap、rulers、minimap、gutter、line endings。
  - rendering preferences：theme、color scheme、DPI、ligatures where supported。
  - language preferences：Tree-sitter、LSP server config、format-on-save/on-type、semantic highlighting。
  - workspace preferences：exclude/include、search scope、recent/session。
- Capability DTO：
  - core features。
  - ui features。
  - ffi abi version。
  - LSP server capabilities。
  - platform/App capabilities。
- Persistence：
  - user settings。
  - workspace settings。
  - runtime overrides。
  - migration strategy。

### 验证

- Rust tests 覆盖 config parse/default/migration。
- Swift tests 覆盖 typed config round trip、unknown field compatibility。
- AppKit tests 覆盖 preference change 到 view/render/state 更新。

### 提交

- `feat(swift): type editor configuration and capabilities`
- 中间提交：`feat(app): snapshot editor configuration capabilities`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；为 Swift/App 现有偏好和运行时能力补一个可序列化、可 round-trip、可审计的 typed snapshot 起点。
  - 提交边界：新增 `AttoConfigurationSnapshot` / `AttoCapabilitySnapshot`，覆盖当前已落地的 editor/rendering/language/workspace 偏好、UI FFI runtime ABI/features、LSP server capability 摘要以及 platform/App capability；`AttoPreferences` 可生成当前有效配置 snapshot，runtime compatibility report 可生成 capability snapshot；JSON decode 默认忽略 unknown future fields。该提交不改变运行时应用偏好的行为，不新增 Rust/FFI ABI，不实现 Sublime settings scope/user-vs-workspace settings 合并、runtime overrides 持久化、完整 core/headless capability negotiation 或迁移策略。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(Preferences|RuntimeCompatibility)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): persist scoped editor settings`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把完整 snapshot 起点推进到可持久化的 partial settings overlay，让 user/workspace/runtime 三层设置可以按优先级合并。
  - 提交边界：新增 `AttoConfigurationSettings` partial DTO、`AttoConfigurationSettingsStore` 和 `AttoConfigurationResolution`；支持 user settings 默认路径、workspace `.attoeditor/settings.json` 路径、JSON 保存/加载、unknown future fields 兼容，以及 base → user → workspace → runtime 的合并顺序；字典型 comment/LSP server policy 会按 key 覆盖合并。该提交不改变 App 启动时的偏好加载行为，不实现 Sublime settings scope selector 规则、不接 Preferences UI、不实现迁移/损坏文件备份、不新增 Rust/FFI ABI，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|Preferences|RuntimeCompatibility)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): load scoped editor settings`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把阶段 9 已有 settings store 接入 AttoEditor App 的窗口创建和偏好重应用路径，让 user/workspace partial settings 参与实际 editor/rendering 配置。
  - 提交边界：`AttoAppDelegate` 在创建窗口和收到偏好变更时按 workspace root 读取 user settings 与 workspace `.attoeditor/settings.json`，生成 resolved `AttoConfigurationSnapshot`；`AttoWindowContext` 将该 snapshot 传入 `AttoEditorAreaViewController`；EditorArea 的新 editor chrome 与已打开 editor 偏好重应用改为消费 snapshot 中的 font、ligatures、wrap、auto-pairs 和 theme 字段。该提交不实现 Sublime settings scope selector 规则、不接 Preferences UI、不持久化 runtime overrides、不实现迁移/损坏文件备份、不新增 Rust/FFI ABI，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(EditorPreferencesApplication|ConfigurationSettings|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): apply runtime configuration overrides`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把 settings resolution 中已有的 runtime override 层接入 AttoEditor App 的实际窗口配置解析路径。
  - 提交边界：`AttoAppDelegate` 新增 process-local runtime `AttoConfigurationSettings` override 状态；创建窗口和偏好重应用时按 base → user → workspace → runtime 顺序解析 `AttoConfigurationSnapshot`，并立即更新已打开 editor 的 theme、font、ligatures、wrap 和 auto-pairs。该提交不实现 runtime override 的用户 UI 或持久化，不实现 Sublime settings scope selector 规则、不实现迁移/损坏文件备份、不新增 Rust/FFI ABI，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(EditorPreferencesApplication|ConfigurationSettings|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): back up corrupt editor settings`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；补齐 settings store 的损坏文件保护，避免无效 JSON 配置反复阻断 App settings 加载。
  - 提交边界：`AttoConfigurationSettingsStore.load(from:)` 在文件可读但 JSON/DTO decode 失败时，将原文件移动到同目录 `*.invalid` 备份路径，若备份已存在则使用递增后缀，然后返回 `nil` 让调用方继续按下层配置运行。该提交不实现 settings schema migration、不实现用户可见恢复 UI、不实现 Sublime settings scope selector 规则、不接 Preferences UI、不新增 Rust/FFI ABI，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|EditorPreferencesApplication|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): migrate legacy editor settings`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；补齐 settings store 的 schema migration 起点，让旧的未标注 schema version 的 settings 文件可以自动升级。
  - 提交边界：`AttoConfigurationSettings` decode 会把缺失 `schema_version` 的文件视为 legacy v0；`AttoConfigurationSettingsStore.load(from:)` 在读取到低于当前版本的 settings 时，先把原文件备份到 `*.v0.backup` 系列路径，再写回 current schema version 的 JSON，并返回迁移后的 typed settings。该提交只覆盖 v0 → current 的无字段重命名迁移，不实现跨 schema 字段语义转换、不实现用户可见恢复 UI、不实现 Sublime settings scope selector 规则、不接 Preferences UI、不新增 Rust/FFI ABI，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoConfigurationSettingsTests'`
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|EditorPreferencesApplication|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): configure default search options`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把已有 find/search typed options 纳入 Swift 配置 snapshot/settings，并让 AppKit find bar 消费 resolved configuration。
  - 提交边界：`AttoEditorPreferenceSnapshot` 与 `AttoEditorPreferenceSettings` 新增 `find_case_sensitive`、`find_whole_word`、`find_regex` 字段，继续兼容旧 JSON 缺省值；user/workspace/runtime settings resolution 可覆盖这些字段；`AttoEditorAreaViewController` 在 view load 和偏好重应用时同步 find bar 的 Aa/Word/Regex 状态。该提交不新增 Rust/FFI ABI，不实现 workspace Find in Files scope 配置、不实现自定义 word boundary 规则、不接 Preferences UI、不实现 runtime override UI/持久化，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|EditorPreferencesApplication|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): configure find-in-files scope`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把 Find in Files 默认搜索范围纳入 workspace configuration，并让侧栏搜索 UI 消费 resolved configuration。
  - 提交边界：`AttoWorkspacePreferenceSnapshot` 与 `AttoWorkspacePreferenceSettings` 新增 `find_in_files_default_scope` 字段，缺省为 `opened_files` 且兼容旧 snapshot JSON；`AttoFindInFilesViewController` 支持配置默认 `Opened` / `Folder` scope；`AttoWindowContext` 在窗口创建和偏好重应用时同步该 scope。该提交不新增 Rust/FFI ABI，不实现 workspace include/exclude glob、不改变 Find in Files 搜索算法、不实现自定义 word boundary 规则、不接 Preferences UI、不实现 runtime override UI/持久化，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|EditorPreferencesApplication|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): configure workspace search globs`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把 workspace Find in Files 的 include/exclude glob 纳入 workspace configuration，并让侧栏 workspace-scope 搜索消费 resolved configuration。
  - 提交边界：`AttoWorkspacePreferenceSnapshot` 与 `AttoWorkspacePreferenceSettings` 新增 `workspace_search_include_globs` / `workspace_search_exclude_globs` 字段，缺省为空数组且兼容旧 snapshot JSON；`AttoFindInFilesViewController` 在 Folder/workspace scope 下用这些 glob 过滤 `workspaceFilesProvider` 的 URL 集合，支持常见 `*`、`?`、`**` 和目录前缀写法；`AttoWindowContext` 在窗口创建和偏好重应用时同步 glob 配置。该提交不新增 Rust/FFI ABI，不改变文件索引策略、不实现 replace preview/apply、不实现自定义 word boundary 规则、不接 Preferences UI、不实现 runtime override UI/持久化，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|EditorPreferencesApplication|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): expose search defaults in preferences`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把已建模的默认 Find 选项和 Find in Files 默认 scope 接入全局 Preferences UI 与 base `AttoPreferences`。
  - 提交边界：`AttoPreferences` 新增默认 case-sensitive / whole-word / regex 和 Find in Files scope 的 UserDefaults/env/default 解析；`effectiveConfigurationSnapshot` 把这些值写入 `AttoConfigurationSnapshot`；Preferences Editor 页面新增 Search 分组，允许用户设置默认 Find 选项和 Find in Files 默认范围。该提交不新增 Rust/FFI ABI，不实现 workspace glob 的 Preferences UI、不实现自定义 word boundary 规则、不实现 workspace/project scoped settings 编辑 UI、不实现 runtime override UI/持久化，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoPreferencesTests'`
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|EditorPreferencesApplication|Preferences)Tests'`
    - `git diff --check`
- 中间提交：`feat(app): expose workspace search globs in preferences`
  - 所属任务：阶段 9 的配置、偏好与 capability DTO 完整性增量；把已建模的 workspace search include/exclude glob 接入全局 Preferences UI 与 base `AttoPreferences`。
  - 提交边界：`AttoPreferences` 新增 workspace search include/exclude glob 的 UserDefaults/env/default 解析、规范化和 UI 多行文本格式化；`effectiveConfigurationSnapshot` 把这些值写入 `AttoWorkspacePreferenceSnapshot`；Preferences Editor 页面 Search 分组新增 include/exclude glob 多行输入，并把页面滚动容器与文本框滚动容器分离，避免多行输入互相覆盖。该提交不新增 Rust/FFI ABI，不改变 Find in Files glob 匹配语义、不实现 workspace/project scoped settings 编辑 UI、不实现 runtime override UI/持久化、不实现自定义 word boundary 规则，也不完成 core/headless capability negotiation。
  - 验证记录：
    - `swift test --package-path swift --filter 'AttoPreferencesTests'`
    - `swift test --package-path swift --filter 'Atto(ConfigurationSettings|EditorPreferencesApplication|Preferences)Tests'`
    - `git diff --check`

## 阶段 10: ABI 版本、错误模型与兼容性门禁

### 目标

统一 FFI/Swift API 形态，降低后续扩展破坏 Swift runtime 的风险。

### 主要交付

- ABI versioning：
  - `abi_version` / feature flags / capability negotiation。
  - runtime mismatch diagnostic。
  - old Swift wrapper 对 new ABI unknown fields 的兼容策略。
- Error model：
  - 统一 `{ ok, value, error, version }` 或等价 envelope 的适用范围。
  - C ABI string ownership 与 error ownership 明确。
  - Swift typed `EcuError` 或 domain-specific error。
- JSON bridge：
  - headless/core/ui FFI 的 JSON command/result/error 风格一致。
  - 清理重复或历史遗留 helper。
- Docs：
  - 更新 `docs/abi-v1-draft.md`。
  - 更新 relevant crate README。

### 验证

- C ABI tests 覆盖 null pointer、invalid JSON、unknown version、feature flag。
- Swift tests 覆盖 runtime compatibility、error decoding、unknown future fields。
- `cargo test -p editor-core-ffi -p editor-core-ui-ffi`。

### 提交

- `feat(ffi): standardize abi capability errors`
- 中间提交：`feat(ffi): envelope ui command json results`
  - 所属任务：阶段 10 的 ABI 版本、错误模型与兼容性门禁增量；为 UI FFI JSON command dispatcher 增加兼容的结构化 result envelope 起点。
  - 提交边界：新增 `editor_core_ui_ffi_editor_ui_execute_command_envelope_json(...)` C ABI 和 `ECU_FEATURE_JSON_COMMAND_ENVELOPE` feature bit；legacy `editor_core_ui_ffi_editor_ui_execute_command_json(...)` 保持原来的 command-result JSON / null pointer + last_error 行为；Swift wrapper 新增 raw/typed envelope API 与 `EcuJSONCommandEnvelope` / `EcuJSONCommandError`；`docs/abi-v1-draft.md` 记录 envelope schema 和最新 feature bit。该提交不切换 App 主路径，不移除 legacy JSON API，不覆盖 headless `editor-core-ffi` command envelope，不统一所有 LSP/result JSON API，也不完成第三方 host 的完整 capability negotiation。
  - 验证记录：
    - `cargo build -p editor-core-ui-ffi --release`
    - `cargo test -p editor-core-ui-ffi --release ffi_editor_ui_execute_command_envelope_json_reports_success_and_errors`
    - `cargo test -p editor-core-ui-ffi --release ffi_feature_flags_include_semantic_tokens_requests`
    - `swift test --package-path swift --filter 'EditorCoreUIFFITests/test(LoadsLibraryAndVersion|ExecuteCommandEnvelopeJSONReportsSuccessAndError)'`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ffi): envelope headless command json results`
  - 所属任务：阶段 10 的 ABI 版本、错误模型与兼容性门禁增量；把兼容的结构化 result envelope 起点扩展到 headless `editor-core-ffi` JSON command bridge。
  - 提交边界：新增 `editor_core_ffi_editor_state_execute_envelope_json(...)` 和 `editor_core_ffi_workspace_execute_envelope_json(...)` C ABI；legacy `editor_core_ffi_editor_state_execute_json(...)` / `editor_core_ffi_workspace_execute_json(...)` 保持原来的 command-result JSON / null pointer + last_error 行为；Swift `EditorCoreFFI` 新增 raw/typed envelope API 与 `EcfJSONCommandEnvelope` / `EcfJSONCommandError` / `EcfJSONValue`；`docs/abi-v1-draft.md` 和 `crates/editor-core-ffi/README.md` 记录 headless envelope schema。该提交不新增 headless feature flags，不切换现有 typed convenience 主路径，不移除 legacy JSON API，不统一 LSP/helper JSON API，也不完成第三方 host 的完整 capability negotiation。
  - 验证记录：
    - `cargo test -p editor-core-ffi --test abi_v1 editor_state_execute_envelope_json_reports_success_and_errors`
    - `cargo test -p editor-core-ffi --test abi_v1 workspace_execute_envelope_json_reports_success_and_errors`
    - `swift test --package-path swift --filter 'EditorStateJSONCommandBridgeTests/testExecuteEnvelopeReportsSuccessParseAndCommandErrors'`
    - `swift test --package-path swift --filter 'WorkspaceAdditionalTests/testWorkspaceExecuteEnvelopeReportsSuccessParseAndCommandErrors'`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(ffi): expose headless feature flags`
  - 所属任务：阶段 10 的 ABI 版本、错误模型与兼容性门禁增量；为 headless `editor-core-ffi` 增加与 UI FFI 对齐的 feature flags / Swift runtime info 起点，便于 Swift 和第三方 host 在调用新增符号前做能力探测。
  - 提交边界：新增 `editor_core_ffi_feature_flags()` 和 `ecf_feature_flags()` C ABI；定义 append-only 的粗粒度 `ECF_FEATURE_*` bit，覆盖 JSON command dispatch、typed hot path、workspace typed API、viewport blob、processing edits、LSP helpers、Sublime processor、Tree-sitter processor 和 JSON command envelope；Swift `EditorCoreFFILibrary` 新增 `featureFlags`、`runtimeInfo()`、`EditorCoreFFIFeatures` 和 `EditorCoreFFIRuntimeInfo`。该提交不改变现有调用路径，不新增 UI FFI feature，不给每个 helper JSON 函数单独建 bit，也不完成完整第三方 capability negotiation schema。
  - 验证记录：
    - `cargo test -p editor-core-ffi --test abi_v1 feature_flags_and_alias_work`
    - `cargo test -p editor-core-ffi --test abi_v1 public_abi_scalar_signatures_are_fixed_width`
    - `swift test --package-path swift --filter 'FFILibrarySmokeTests'`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`test(ffi): cover command envelope future compatibility`
  - 所属任务：阶段 10 的 ABI 版本、错误模型与兼容性门禁增量；为 headless/UI Swift command envelope decoder 补齐 unknown future fields 和 unknown status 的兼容性回归测试。
  - 提交边界：只新增 Swift test coverage，断言 `EcfJSONCommandEnvelope` 与 `EcuJSONCommandEnvelope` 会忽略未来新增 top-level/error metadata 字段、保留未来 result payload 为 typed JSON value，并把未知 numeric status 解码为 `nil` 而不是失败或误映射。本提交不改变 Rust/C ABI，不新增 feature bit，不改变 envelope schema，也不扩展其他 JSON result 面。
  - 验证记录：
    - `swift test --package-path swift --filter 'EditorStateJSONCommandBridgeTests/testCommandEnvelopeDecodesFutureFieldsAndUnknownStatus'`
    - `swift test --package-path swift --filter 'EditorCoreUIFFITests/testExecuteCommandEnvelopeDecodesFutureFieldsAndUnknownStatus'`
    - `git diff --check`
- 中间提交：`feat(ffi): add headless runtime compatibility report`
  - 所属任务：阶段 10 的 ABI 版本、错误模型与兼容性门禁增量；在 Swift headless `EditorCoreFFI` 中补齐 runtime mismatch / missing feature diagnostic 起点，让 Swift 和第三方 host 能复用同一 compatibility report 评估 ABI version、required features 和 optional features。
  - 提交边界：新增 `EditorCoreFFIRuntimeFeature`、`EditorCoreFFIRuntimeCompatibilityReport` 和 `EditorCoreFFIRuntimeCompatibility`，提供默认 full-surface required feature 列表、可传入自定义 required/optional feature 集合的 evaluate API、load error/older ABI/missing required/missing optional diagnostic message。该提交不改变 C ABI，不新增 feature bit，不接入 AttoEditor App 启动逻辑，不替代 UI FFI 的 `AttoRuntimeCompatibility`。
  - 验证记录：
    - `swift test --package-path swift --filter 'EditorCoreFFIRuntimeCompatibilityTests'`
    - `git diff --check`
- 中间提交：`feat(ffi): expose runtime info json snapshots`
  - 所属任务：阶段 10 的 ABI 版本、错误模型与兼容性门禁增量；为 headless/UI C ABI 增加给第三方 C/非 Swift host 使用的一次性 runtime/capability snapshot。
  - 提交边界：新增 `editor_core_ffi_runtime_info_json()` 和 `editor_core_ui_ffi_runtime_info_json()`，返回包含 `kind`、`abi_version`、`version`、`feature_flags` 和 append-only `features[]` descriptors 的 JSON；Swift `EditorCoreFFILibrary` / `EditorCoreUIFFILibrary` 新增 raw `runtimeInfoJSON()` accessor；更新 C headers、ABI draft 和 crate README。该提交不改变既有 scalar `abi_version` / `feature_flags` API，不新增 feature bit，不替换 Swift typed `runtimeInfo()`，不定义完整外部 capability negotiation protocol。
  - 验证记录：
    - `cargo test -p editor-core-ffi --test abi_v1 runtime_info_json_reports_version_and_feature_descriptors`
    - `cargo test -p editor-core-ui-ffi --release ffi_runtime_info_json_reports_version_and_feature_descriptors`
    - `swift test --package-path swift --filter 'FFILibrarySmokeTests/testLoadsLibraryAndVersion'`
    - `swift test --package-path swift --filter 'EditorCoreUIFFITests/testLoadsLibraryAndVersion'`
    - `cargo fmt --check`
    - `git diff --check`
- 中间提交：`feat(swift): add ui ffi runtime compatibility report`
  - 所属任务：阶段 10 的 ABI 版本、错误模型与兼容性门禁增量；把 UI FFI runtime mismatch / missing feature diagnostic 从 AttoEditor app 内部下沉出一个 Swift wrapper 层可复用版本。
  - 提交边界：新增 public `EditorCoreUIFFIRuntimeFeature`、`EditorCoreUIFFIRuntimeCompatibilityReport` 和 `EditorCoreUIFFIRuntimeCompatibility`，覆盖 UI FFI 已知 feature、默认 full-surface required feature 列表、可传入自定义 required/optional feature 集合的 evaluate API、load error/older ABI/missing required/missing optional diagnostic message。该提交不改变 C ABI，不新增 feature bit，不接入或替换 AttoEditor `AttoRuntimeCompatibility` 启动路径，不完成完整外部 capability negotiation protocol。
  - 验证记录：
    - `swift test --package-path swift --filter 'EditorCoreUIFFIRuntimeCompatibilityTests'`
    - `git diff --check`

## 阶段 11: Tree-sitter 与 LSP 主路线产品化

### 目标

在不扩 Sublime syntax 的前提下，把 AttoEditor 的语言能力主线落实为 Tree-sitter + LSP。

### 主要交付

- Tree-sitter：
  - language detection。
  - parser lifecycle。
  - structural outline/folding/highlighting。
  - injection 或 mixed language 的可行边界。
- LSP：
  - semantic highlighting 与 Tree-sitter highlighting 的 merge/priority 策略。
  - diagnostics、symbols、formatting、inlay hints、code lens、document links、colors、hierarchy 的 consistent consumption。
- App：
  - source indicator：Tree-sitter / LSP / Sublime baseline。
  - unsupported language 降级。
  - settings 可控制 semantic highlighting、format-on-save、server config。
- Docs：
  - 明确 Sublime syntax 只作为 existing baseline，不作为后续扩展目标。

### 验证

- Renderer/derived-state tests 覆盖 Tree-sitter + semantic tokens merge。
- Swift/App tests 覆盖 language mode 切换和降级。
- Screenshot tests 覆盖高亮、folding、diagnostic overlay 不互相遮挡。

### 提交

- `feat(lang): productize treesitter and lsp path`

## 阶段 12: Workspace search、project index、recent 与 session

### 目标

补齐 Sublime-like project workflow：打开文件、最近文件、Find in Files、workspace search、session restore 都由 core workspace model 支撑。

### 主要交付

- Workspace search：
  - opened tabs scope。
  - project files scope。
  - include/exclude/glob。
  - case/regex/whole word。
  - streaming or bounded result model。
  - replace-in-files preview/apply 与 WorkspaceEdit transaction 对齐。
- Recent/session：
  - recent files。
  - recent projects。
  - last session restore。
  - unsaved buffer handling。
  - project root persistence。
- App：
  - Find in Files panel。
  - Go to File / recent files quick panel。
  - session restore UI。

### 验证

- Rust tests 覆盖 project search 和 replace preview/apply。
- Swift tests 覆盖 typed search result decoding。
- AppKit tests 覆盖 Find in Files panel、open result、replace preview。

### 提交

- `feat(workspace): add core project search and session`

## 阶段 13: macOS UI 自动化与视觉回归测试体系

### 目标

为 Sublime-like 外观、布局和操作能力建立可持续测试体系。因为 AttoEditor 是 native AppKit + Skia/Metal，不以 Playwright 作为主测试工具；Playwright 仅适合 web UI 或本地网页工具。

### 主要交付

- XCTest/AppKit component tests：
  - view controller lifecycle。
  - key events。
  - mouse events。
  - command routing。
  - panels/popups/menu states。
- Accessibility / UI automation：
  - 启动 native app。
  - 通过 AX 查询窗口、菜单、tab、panel、focused editor。
  - 执行打开、输入、选择、多光标、搜索、split、panel navigation。
- Screenshot baseline：
  - 固定字体、DPI、theme、window size。
  - baseline images。
  - tolerance/threshold。
  - diff artifact 输出。
- Renderer pixel tests：
  - Skia render output。
  - selection/cursor/gutter/minimap/diagnostics/semantic tokens。
  - light/dark theme。
- Layout assertions：
  - 文本不重叠。
  - panels 不遮挡主编辑区。
  - tab/title/status/minimap/gutter 尺寸稳定。
  - narrow/wide window responsive behavior。
- Test harness docs：
  - 本地运行方式。
  - CI 环境限制。
  - 如何更新 baseline。

### 验证

- 新增 targeted UI test suite 可以本地运行。
- 至少覆盖：
  - empty window。
  - open file。
  - type/edit/undo。
  - split pane。
  - tab switch。
  - command palette。
  - Problems/Outline/Locations panel。
  - diagnostics marker。
  - semantic highlighting。
- 生成截图 diff artifact。

### 提交

- `test(app): add native ui visual regression harness`

## 阶段 14: 外观、布局与 Sublime-like 操作打磨

### 目标

在测试体系保护下，修复和补齐实际视觉/交互差距，推进 Sublime Text 复刻目标。

### 主要交付

- Editor chrome：
  - tab bar。
  - status bar。
  - side bar / project tree。
  - command palette。
  - quick panels。
  - minimap。
  - gutter。
  - split panes。
- Editing interaction：
  - multi-cursor。
  - selection expansion。
  - line movement/duplication/deletion。
  - find/replace。
  - goto anything style flows。
  - keyboard focus and first responder behavior。
- Visual consistency：
  - themes。
  - font metrics。
  - cursor/selection rendering。
  - overlay positioning。
  - diagnostic/code lens/inlay hint decorations。

### 验证

- UI screenshot baselines cover each major layout.
- AppKit interaction tests cover command workflows.
- Manual smoke checklist for macOS app.

### 提交

- `feat(app): polish sublime-like editor workflows`

## 阶段 15: 文档、迁移清理与最终审计

### 目标

收尾全部 `SWIFT-GAPS.md` 项目，把完成证据写回文档，清理过渡 API 和重复模型。

### 主要交付

- 更新 `SWIFT-GAPS.md`：
  - 每个目标标记 complete / deferred / out-of-scope。
  - 每个 complete 项指向 API、tests、commit 或 docs。
  - Sublime syntax 非目标保持明确。
- 更新 ABI docs 和 crate README。
- 清理 Swift-only workspace/tab/session 过渡代码。
- 清理 deprecated raw-only APIs 或标记 deprecated。
- 建立 final coverage matrix。
- 运行最终验证命令。

### 验证

- `cargo fmt`
- `cargo test -p editor-core`
- `cargo test -p editor-core-ui`
- `cargo test -p editor-core-ui-ffi`
- `cargo test -p editor-core-ffi`
- `swift test --package-path swift`
- UI 自动化和 screenshot baseline suite。
- `SWIFT-GAPS.md` 无未归属目标。

### 提交

- `docs: close swift gaps audit`
- 维护性中间提交：`refactor(swift): split long editor integration files`
  - 所属任务：拆分过长 Swift 集成文件，降低后续执行本计划时在 AppKit controller、Swift FFI wrapper、Skia view 三个高频改动面上的冲突和审查成本。
  - 提交边界：只做结构性模块化拆分；将 `AttoEditorAreaViewController.swift`、`EditorUI.swift`、`EditorCoreSkiaView.swift` 按命令、LSP、编辑、渲染、输入、鼠标、tabs/panes、偏好设置等职责拆到同目录扩展文件；仅为跨文件 extension 调用放宽必要的 Swift 访问级别；不改变 ABI、Rust 代码或产品行为。
  - 验证记录：
    - `swift test --package-path swift --filter EditorCoreUIFFITests.testLoadsLibraryAndVersion`
    - `swift test --package-path swift --filter EditorCoreUIFFITests`
    - `swift test --package-path swift --filter EditorCoreUITests`
    - `swift test --package-path swift --filter AttoEditorTests`
    - `git diff --check`

## 常用验证命令

按阶段选择最小但充分的验证集合。跨 ABI 或 Swift wrapper 阶段不能只跑 Rust tests。

```sh
cargo fmt
cargo test -p editor-core
cargo test -p editor-core-ui
cargo test -p editor-core-ui-ffi
cargo test -p editor-core-ffi
swift test --package-path swift --filter EditorCoreUIFFITests
swift test --package-path swift --filter EditorCoreUITests
swift test --package-path swift --filter AttoEditorTests
swift test --package-path swift
```

当 SwiftPM 找不到新构建的 staticlib 或 cache stale 时，先执行：

```sh
cargo build -p editor-core-ffi -p editor-core-ui-ffi --release
swift package --package-path swift clean
```

UI/视觉阶段还需要：

```sh
swift test --package-path swift --filter AttoEditorUITests
swift test --package-path swift --filter AttoEditorVisualRegressionTests
```

具体 test target 名称以实际新增 harness 为准。

## 每阶段完成标准

- Rust core/UI 代码有 focused tests。
- FFI 变更同步 C header、Swift declaration、runtime compatibility tests。
- Swift wrapper 有 typed API，unknown future values 不会导致崩溃。
- App 主路径消费 typed API，而不是只保留 raw JSON。
- `SWIFT-GAPS.md` 或 coverage matrix 更新状态。
- 阶段提交只包含该阶段相关改动。
- 提交前确认没有混入无关 WIP。

## 最终完成标准

- `SWIFT-GAPS.md` 中所有目标都有明确结果：complete、deferred with reason 或 out-of-scope。
- Swift/AppKit 层可以通过稳定 typed binding 使用 `editor-core-*` 的主要 headless、UI、workspace、LSP、Tree-sitter、derived-state 和 rendering 能力。
- 多文档、tab、workspace、project/session 的长期状态归属在 core workspace / `MultiDocumentEditorUi`。
- LSP result/request/state lifecycle 有统一 event/subscription 模型。
- WorkspaceEdit 跨文件事务由 core workspace 拥有。
- App 的 Problems、Outline、Symbols、Locations、Hierarchy 等主要 result panels 消费 core/typed model。
- Command/menu/keymap/palette 有统一模型，并覆盖 Sublime-like 常用操作。
- macOS native UI 自动化、视觉回归和 renderer pixel tests 可以验证外观、布局和操作能力。
- Sublime syntax 扩展仍明确为非目标，只保留现有 `editor-core-sublime` baseline。
