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
