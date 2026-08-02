# Swift 绑定与 UI 集成缺口审计

审计日期：2026-08-01

本文记录当前 Swift 侧、FFI 层、`editor-core-ui` 适配层以及 AttoEditor App 层相对 `editor-core-*` 能力的功能缺口。这里的 “Swift UI” 指仓库中的 Swift/AppKit/Skia/Metal 集成，不是 Apple SwiftUI 框架。

本文关注的是“能否从 Swift 产品层完整使用 `editor-core-*` 能力”，不是评价 Rust core 自身是否完整。总体结论是：**当前 Swift 路径已经能支撑一个可用编辑器主流程，但还不是 `editor-core-*` 的完整能力投影**。尤其对于“复刻 Sublime Text”这个目标，缺口主要集中在命令面、LSP 产品化、派生状态产品化/消费、多文档/分屏归属、Sublime 兼容行为和视觉/交互测试体系。其中多文档、tab、workspace、project/session 的状态归属已经明确：后续应收敛到 `editor-core` / `editor-core-ui` 的 workspace 模型，Swift/AppKit 侧不再新开或扩展一套长期独立的 workspace/tab/session 模型。本文后续提到的 Sublime 兼容不包含 `.sublime-syntax` 语法定义扩展；AttoEditor 的语言语义、结构化高亮和智能能力重点走 Tree-sitter 与 LSP 路线，Sublime syntax 支持以现有 `editor-core-sublime` 能力为基线即可。因此，后续 Swift gaps 的验收口径不把“提高 Sublime syntax 覆盖率”列为待补功能。

## 范围

本次审计覆盖这些路径：

- `crates/editor-core/`：headless 编辑器核心能力。
- `crates/editor-core-ffi/`：headless core 的 C ABI / JSON command plane。
- `crates/editor-core-ui/`：Rust 侧带渲染、输入、LSP/Tree-sitter/Sublime 集成的 UI wrapper。
- `crates/editor-core-ui-ffi/`：`editor-core-ui` 的 C ABI。
- `swift/Sources/EditorCoreFFI/`：Swift headless FFI wrapper。
- `swift/Sources/EditorCoreUIFFI/`：Swift UI FFI wrapper，核心类型是 `EditorUI`。
- `swift/Sources/EditorCoreUI/`：AppKit view 层。
- `swift/Sources/AttoEditor/`：当前 macOS app 产品层。

本文不把所有未实现的 Sublime 产品功能都算作 Rust core 缺口；很多属于 App 层、命令系统、设置系统或插件/包生态缺口。Sublime syntax 兼容不列为后续扩展目标，因为这一部分没有稳定公开规范可作为实现和验收依据。

## 当前可用基线

Swift 侧已经具备以下基础能力：

- SwiftPM 包可构建，包含 `AttoEditor` executable。
- 当前 App 是 AppKit + Skia/Metal 自绘架构，不是 SwiftUI view tree。
- `EditorCoreFFI.EditorState` 和 `EditorCoreFFI.Workspace` 暴露了 headless core 的一部分 JSON command 能力。
- `EditorCoreUIFFI.EditorUI` 暴露了较完整的“编辑器视图主路径”API，包括打开文本、插入/删除、搜索替换、撤销重做、选择、鼠标输入、IME、渲染 RGBA/Metal、主题、Tree-sitter、Sublime syntax、部分 LSP、minimap、gutter、bookmark、jump history、document link hit-test 等。
- `EditorCoreUIFFI.MultiDocumentEditorUI` 已能访问 Rust `MultiDocumentEditorUi` 的基础 tab/preview/pin/close/split/search-all-tabs 模型，并能同步 tab 文本、保存/dirty 状态。
- AttoEditor 当前的 Swift tabs/splits 仍是过渡层；它们可以承载现有 UI 表现，但后续多文档、tab、workspace、session 语义应迁移为 core workspace state 的投影。
- `EditorCoreUI` / `AttoEditor` 已有 AppKit 组件级 XCTest，能用 `NSWindow`、`NSEvent` 和 view API 驱动交互。
- 2026-08-01 本地验证过：
  - `cargo test -p editor-core-lsp -p editor-core-ui -p editor-core-ui-ffi` 通过。
  - `swift test --package-path swift` 通过，206 个测试。
  - `swift test --filter AttoEditorTests` 通过，61 个测试。
  - `swift test --filter EditorCoreUITests` 通过，64 个测试。
  - `swift test --filter EditorCoreUIFFITests` 通过，46 个测试。

这说明当前 Swift 路径不是“不可用”，而是“主流程可用、完整能力映射不足”。

## 实现进度

- 2026-08-01 阶段 1 已完成：`editor-core-ui` 新增 `EditorUi.execute_command_json`，`editor-core-ui-ffi` 新增 `editor_core_ui_ffi_editor_ui_execute_command_json`，Swift `EditorCoreUIFFI.EditorUI` 新增 `executeCommandJSON(_:)`。
- 阶段 1 已让 Swift UI 层可通过 JSON 执行核心 edit/cursor/view/style 命令，并补上 `type_char`、IME coalescing replace、`apply_snippet`、snippet placeholder navigation、auto-pairs config、bracket highlight update/clear 等 UI command schema。
- 阶段 1 已用 Rust integration tests 和 Swift `EditorCoreUIFFITests` 覆盖 line commands、toggle comment、apply text edits、wrap/fold、snippet、auto-pairs。
- 阶段 1 尚未完成 App 层 command registry、菜单/keymap/command palette 接线，也尚未为所有命令提供 Swift typed convenience API。
- 2026-08-01 阶段 2 已完成：AttoEditor command palette 命令增加稳定 `id`，App 层新增一组 Sublime 基础编辑命令入口，`AttoEditorAreaViewController` 新增活动编辑器 JSON command 执行封装，并负责 dirty state、redraw、status bar 等副作用。
- 阶段 2 已覆盖 duplicate/delete/move lines、join/split line、indent/outdent、delete-to-prev-tab-stop、toggle line comment、fold selection、unfold、unfold all、wrap mode command palette 入口。
- 阶段 2 尚未完成主菜单接线、用户可配置 keymap、命令启用/禁用状态模型。
- 2026-08-01 阶段 3 已完成：Swift `EditorCoreUIFFI` 新增高频 command DTO 和 typed convenience API，内部统一走 `executeCommandJSON(_:)`。
- 阶段 3 已覆盖 replace coalescing、type char、insert newline with auto-indent、line commands、toggle comment、apply text edits、apply snippet、snippet placeholder navigation、move to/by、occurrence options、wrap mode/indent、indentation config、auto-pairs config、viewport query、fold/unfold、bracket highlight update/clear。
- 2026-08-01 阶段 4 已完成：AttoEditor 主菜单改为通过 command id 调用统一命令入口，新增 `AttoKeymap` 解析默认/用户 keymap，并让菜单快捷键使用同一组 command id。
- 阶段 4 已覆盖 P0 基础编辑命令、wrap/fold 命令、file/search/go/view/workbench 命令的菜单接线；其中常用命令已有默认 key binding，其余命令可通过 `~/Library/Application Support/codes.unwritten.attoeditor/keymap.json` 或 `ATTO_EDITOR_KEYMAP_PATH` 覆盖 key binding。
- 2026-08-01 阶段 5 已完成：Swift UI binding 新增派生状态 JSON snapshot API，覆盖 diagnostics、decorations、document symbols、folding regions、style intervals。
- 阶段 5 已新增 `EditorUI.diagnosticsJSON()`、`decorationsJSON()`、`documentSymbolsJSON()`、`foldingRegionsJSON()`、`styleIntervalsJSON(start:end:)`，并新增 `lspApplyDocumentSymbolsJSON(_:)` 让 Swift UI 可把 LSP `textDocument/documentSymbol` result 写入 core outline。
- 阶段 5 已用 Rust `cargo test -p editor-core-ui -p editor-core-ui-ffi` 和 Swift `swift test --filter EditorCoreUIFFITests` 覆盖，其中 Swift 新增测试验证 “LSP/processing 派生状态 -> Rust UI -> C ABI -> Swift” 的完整路径。
- 阶段 5 后续缺口中，Swift typed model、active-tab derived-state store、status bar 消费和 Problems quick panel 已在阶段 39-41 补齐，基础持久 Outline/Symbols panel 已在阶段 115 补齐，active-tab 持久 Problems panel 已在阶段 116 补齐，workspace Problems store/panel 已在阶段 117 补齐，active-tab minimap diagnostic markers 已在阶段 118 补齐，active-tab gutter diagnostic icons 已在阶段 119 补齐，workspace diagnostics 到已打开 tab 的 marker 聚合已在阶段 120 补齐，core-owned workspace diagnostics store 起点已在阶段 123 补齐，core-backed workspace diagnostic marker snapshot 起点已在阶段 124 补齐；仍缺 workspace/active diagnostics 统一 derived-state model、刷新/过期策略和更深层 typed model。
- 2026-08-01 阶段 6 第一部分已完成：Swift UI binding 新增一组 LSP interactive request/take raw result API，覆盖 declaration、type definition、implementation、references、completion、signature help、document symbols、workspace symbols。
- 阶段 6 第一部分在 Rust UI 内部把 hover/definition 的专用 result cache 泛化为按 LSP result slot 管理；document symbols response 会同步写入 core outline，供 `documentSymbolsJSON()` 读取。
- 2026-08-01 阶段 6 第二部分已完成：AttoEditor command palette 和 Go 菜单新增 LSP location commands，覆盖 go to definition/declaration/type definition/implementation/find references；cmd-click definition 也复用同一套 location request/poll/navigate 路径。
- 阶段 6 第二部分已让 references 多结果进入一个轻量可过滤结果 palette，单结果直接跳转；`AttoLspDefinitionParser` 新增多目标解析并补测试。阶段 57 已把 definition/declaration/type definition/implementation/references 的多结果处理统一到同一套 location results quick panel。
- 阶段 6 后续缺口中，基础持久在线 references/locations panel 已在阶段 114 补齐，locations/symbols result lifecycle store 起点已在阶段 121 补齐，locations/symbols history entry/envelope 元数据起点已在阶段 122 补齐；仍缺 LSP typed result model、覆盖所有 result family 的 lifecycle/event model 和项目级命令模型。
- 2026-08-01 阶段 7 第一部分已完成：AttoEditor 新增基础 `view.split_right` 命令，通过 `EditorUI.cloneView` 为当前 tab 创建共享 buffer 的第二个 AppKit pane；这部分是当前可用的过渡实现，不应继续扩展成 Swift 自有 workspace/tab 模型。
- 2026-08-01 阶段 7 架构决策已更新：多文档、tab、workspace、project/session 级状态应使用 `editor-core` / `editor-core-ui` 一侧的 `Workspace` / `MultiDocumentEditorUi` 模型作为单一所有权来源，Swift 侧只做 AppKit 表现、命令转发、用户交互和持久化桥接；后续不在 Swift/AppKit 层新开一套长期独立的 workspace/tab/session 模型，也不继续给 Swift-only tab state 增加 preview/pin/dirty/close/search-all-tabs 等长期语义。
- 阶段 7 第一部分已让 split pane 复用主编辑器 chrome/theme/preferences/LSP/hover/cmd-click hook，并新增 first-responder hook 跟踪 active pane；AttoEditor command palette、View 菜单和默认 keymap 已接入。
- 阶段 7 第二部分已完成基础 pane 操作命令：`view.focus_next_pane`、`view.focus_previous_pane`、`view.close_pane`，并用 AppKit 组件测试覆盖 active pane 对 close target 的影响。
- 阶段 7 后续缺口中，`MultiDocumentEditorUi` 基础 Swift FFI 投影已在阶段 80 补齐，AttoEditor tab/pane lifecycle 到 core multi-document mirror 的迁移起点已在阶段 81 补齐，编辑文本/dirty/search-all-tabs 基础同步已在阶段 83 补齐，Find in Files 的 opened scope 已在阶段 84 开始消费 core open-tab search，split pane 数量/active pane session restore 已在阶段 85 补齐，pane move 已在阶段 86 补齐，dirty/close/resource-operation 保护条件已在阶段 87 改为消费 core dirty snapshot，tab movement 已在阶段 88 接入 core tab order；仍缺完整 project/LSP lifecycle 迁移和拖拽 tab 到 split 等更高层 workspace 产品语义。
- 2026-08-01 阶段 8 已完成：AttoEditor 新增 LSP document/workspace symbols quick panel 主路径，命令 `lsp.document_symbols` / `lsp.workspace_symbols` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspSymbolParser`，覆盖 DocumentSymbol、SymbolInformation、WorkspaceSymbol 常见结果形态。
- 阶段 8 后续缺口中，基础错误/超时/空结果反馈已在阶段 68 补齐，最近结果 snapshot 和 reopen command 已在阶段 72 补齐，workspace symbol 增量查询面板已在阶段 93 补齐，workspace symbol kind 分组/稳定排序已在阶段 98 补齐，基础持久在线 Outline/Symbols panel 已在阶段 115 补齐，locations/symbols result lifecycle store 起点已在阶段 121 补齐，symbols history entry/envelope 元数据起点已在阶段 122 补齐；仍缺覆盖所有 LSP result 的更深层 lifecycle/event model。
- 2026-08-01 阶段 9 已完成：AttoEditor 新增 LSP signature help popup 主路径，命令 `lsp.signature_help` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspSignatureHelpFormatter`，覆盖 SignatureHelp、activeSignature、activeParameter、ParameterInformation string/range label 和 documentation 常见结果形态。
- 阶段 9 后续缺口中，trigger characters / 自动弹出已在阶段 18 补齐，active parameter 富格式高亮已在阶段 19 补齐，typed result model 和空结果/错误展示已在阶段 20 补齐。
- 2026-08-01 阶段 10 已完成：AttoEditor 新增 LSP completion popup 主路径，命令 `lsp.completion` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspCompletionParser` 和 caret-anchored completion list，覆盖 CompletionList/CompletionItem、TextEdit、InsertReplaceEdit insert range、additionalTextEdits、snippet insertion 和 fallback identifier-prefix replacement。
- 阶段 10 后续缺口中，rich documentation/detail preview 已在阶段 21 补齐，commitCharacters 提交行为已在阶段 22 补齐，server triggerCharacters 自动触发已在阶段 23 补齐，增量过滤已在阶段 24 补齐，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐；仍缺 core workspace-owned 跨文件事务和更完整的 typed result model。
- 2026-08-01 阶段 11 已完成：Swift UI binding 新增 rename / prepare rename / code action / code action resolve 的 raw async request/take API，覆盖 Rust `editor-core-lsp` 已有的 `textDocument/prepareRename`、`textDocument/rename`、`textDocument/codeAction` 和 `codeAction/resolve` 请求路径。
- 2026-08-01 阶段 11 第二部分已完成：Swift UI binding 新增 `lspApplyWorkspaceEditJSON(_:documentURI:)`，通过 UI FFI 把 `WorkspaceEdit` 中命中当前文档 URI 的 `TextEdit` 应用到当前 buffer，并返回 applied/skipped/documents summary，覆盖 rename/code action 返回 edit 后的当前文档应用基础链路。
- 2026-08-01 阶段 11 第三部分已完成：AttoEditor App 新增 `lsp.rename` 主路径，包含 command palette、Go 菜单、F2 keymap、rename 输入框、候选名预填、LSP rename request/poll，以及把返回的当前文档 WorkspaceEdit 应用到 active tab 并标记 dirty。
- 2026-08-01 阶段 11 第四部分已完成：Swift UI binding 新增 `workspace/executeCommand` raw request/take API；AttoEditor App 新增 `lsp.code_actions` 主路径，包含 command palette、Go 菜单、Cmd+. keymap、code action quick panel、`codeAction/resolve` 轮询、当前文档 WorkspaceEdit 应用和 command payload 执行。
- 阶段 11 后续缺口中，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，code action diagnostics context 已在阶段 26 补齐，code action kind/filter 产品化已在阶段 27 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，code action command payload 执行结果/错误展示已在阶段 48 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐；仍缺 core workspace-owned 跨文件事务，以及相关 typed result model。
- 2026-08-01 阶段 12 已完成：Swift UI binding 新增 `completionItem/resolve` raw request/take API；AttoEditor completion popup 在 commit 时会先请求 resolve，使用 resolved CompletionItem 中的 `textEdit` / `additionalTextEdits` / snippet payload，resolve 不可用或超时时回退到原始 completion item。
- 阶段 12 后续缺口中，rich documentation/detail preview 已在阶段 21 补齐，commitCharacters 提交行为已在阶段 22 补齐，server triggerCharacters 自动触发已在阶段 23 补齐，增量过滤已在阶段 24 补齐，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐；仍缺 core workspace-owned 跨文件事务和更完整的 typed result model。
- 2026-08-01 阶段 13 已完成：Swift UI binding 新增 LSP range/on-type formatting 的阻塞 turnkey API，覆盖 Rust `editor-core-lsp` 已有的 `textDocument/rangeFormatting` 和 `textDocument/onTypeFormatting` 请求路径，并复用 `editor-core-ui` 的 LSP `TextEdit` 应用逻辑。
- 阶段 13 已新增 `EditorUi.lsp_format_range(...)` / `lsp_format_on_type(...)`、C ABI `editor_core_ui_ffi_editor_ui_lsp_format_range` / `editor_core_ui_ffi_editor_ui_lsp_format_on_type`、Swift `EditorUI.lspFormatRange(...)` / `lspFormatOnType(...)`，以及 `EditorCoreSkiaView.formatRangeWithLSP(...)` / `formatOnTypeWithLSP(...)`。
- 阶段 13 已让 AttoEditor App 新增 `editor.format_selection` 主路径，接入 command palette、Edit 菜单和默认 keymap；选区为空时不向 LSP 发 range formatting 请求。
- 阶段 13 后续缺口中，按 server trigger characters 自动触发已在阶段 14 补齐，显式 formatting 错误展示和 typed outcome 已在阶段 60 补齐；formatting 本身仍是当前文档 `TextEdit` apply API，不走跨文件 `WorkspaceEdit` 产品路径。
- 2026-08-01 阶段 14 已完成：Rust UI `insert_text` 单字符 typing 路径会按 LSP server `documentOnTypeFormattingProvider` 宣告的 `firstTriggerCharacter` / `moreTriggerCharacter` 自动触发 `textDocument/onTypeFormatting`；粘贴和多字符 IME commit 仍保持批量插入语义，不触发 on-type formatting。
- 阶段 14 已用 fake LSP server 单测覆盖：单字符 paste 不触发、非 trigger typing 不触发、server trigger typing 会发送 `textDocument/onTypeFormatting` 并携带正确 `ch`。
- 阶段 14 后续缺口中，显式 formatting 错误展示和 formatting typed outcome 已在阶段 60 补齐；formatting 本身仍是当前文档 `TextEdit` apply API，不走跨文件 `WorkspaceEdit` 产品路径。
- 2026-08-01 阶段 15 已完成：Swift UI binding 新增 LSP folding ranges request/take/apply 通道，覆盖 Rust `editor-core-lsp` 已有的 `textDocument/foldingRange` 请求路径和 `ProcessingEdit::ReplaceFoldingRegions` 应用路径。
- 阶段 15 已新增 `EditorUi.lsp_request_folding_ranges()` / `lsp_apply_folding_ranges_json(...)`、C ABI `editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges` / `editor_core_ui_ffi_editor_ui_lsp_take_last_folding_ranges_json` / `editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json`、Swift `EditorUI.lspRequestFoldingRanges()` / `lspTakeLastFoldingRangesResultJSON()` / `lspApplyFoldingRangesJSON(_:)`。
- 阶段 15 已让手动 `textDocument/foldingRange` result 可以写入 core fold regions，并通过 `foldingRegionsJSON()` / typed `foldingRegionsSnapshot()` 被 Swift 读取；App 层 refresh/error UI、菜单入口和 status bar 折叠摘要已补齐；gutter fold marker 视觉回归 baseline 已在阶段 103 补齐。仍缺 result lifecycle model。
- 2026-08-01 阶段 16 已完成：Swift UI binding 新增高级 LSP raw request/take 覆盖，打通 Rust `editor-core-lsp` 已有的 code lens resolve、selection range、linked editing range、pull diagnostics、document color/color presentation、call hierarchy 和 type hierarchy 请求路径。
- 阶段 16 已新增 `EditorUi`、C ABI 和 Swift `EditorUI` 对应 API；这些能力目前仍停留在 raw JSON result 层，App 层 panel/popup/inline UI、typed model、错误展示和 cross-file/workspace 结果产品化仍未完成。
- 2026-08-01 阶段 17 已完成：AttoEditor App 的 `lsp.rename` 弹窗接入 `textDocument/prepareRename`，会优先使用 server 返回的 `placeholder` 或 `range` 文本作为默认 rename 名称；支持 LSP `Range`、`{ range, placeholder }` 和 `{ defaultBehavior: true }` 返回形态。
- 阶段 17 已新增 `AttoLspRenameSupport.DialogSeed` / `dialogSeed(...)`，按 LSP UTF-16 line/character range 从当前文档提取 rename 文本，并在 prepareRename 无响应或不可解析时回退到当前选区/identifier 逻辑；跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐；仍缺 core workspace-owned 跨文件事务和 rename typed result model。
- 2026-08-01 阶段 18 已完成：Rust UI `lsp_status_json()` 暴露 server `signatureHelpProvider.triggerCharacters` / `retriggerCharacters`，Swift `EditorCoreSkiaView` 新增 finalized commit text hook，AttoEditor 会在输入命中 server 声明的 signature help trigger/retrigger 字符时自动请求并弹出 signature help；粘贴/多字符 commit 和未声明能力的 server 不触发。
- 阶段 18 后续缺口中，active parameter 富格式高亮已在阶段 19 补齐，signature help typed result model 和空结果/错误展示已在阶段 20 补齐。
- 2026-08-01 阶段 19 已完成：`AttoLspSignatureHelpFormatter` 新增 signature help display model，携带 active parameter 的 UTF-16 highlight ranges；AttoEditor signature help popover 改为 attributed string 渲染，能同时高亮 signature label 中的 active parameter 和 `parameter:` 摘要行，覆盖 `ParameterInformation.label` string/range 两种形态。
- 阶段 19 后续缺口中，signature help typed result model 和空结果/错误展示已在阶段 20 补齐。
- 2026-08-01 阶段 20 已完成：`AttoLspSignatureHelpFormatter` 新增 typed SignatureHelp / Signature / Parameter / ParameterLabel 模型，display 层改为消费 typed model；AttoEditor 手动 signature help 请求会对 LSP 未启用、请求失败、取结果失败、超时和空结果展示 popover 文本，自动触发路径保持静默失败。
- 2026-08-01 阶段 21 已完成：AttoEditor completion parser 解析 CompletionItem `documentation` 和 `commitCharacters`，completion popup 增加右侧 detail/documentation preview，选中项变化时同步展示 kind/detail、documentation 和 server 声明的 commit characters。
- 2026-08-01 阶段 22 已完成：AttoEditor completion popup 在候选列表获得焦点时会识别当前选中 CompletionItem 的 `commitCharacters`；输入命中字符会先按现有 resolve/apply 路径提交候选，再把该字符通过 `commitText` 回放到编辑器，并继续复用 signature help trigger 逻辑。
- 2026-08-01 阶段 23 已完成：Rust UI `lsp_status_json()` 暴露 server `completionProvider.triggerCharacters` / `allCommitCharacters`，Swift 新增 completion trigger 解析器，AttoEditor 会在最终单字符输入命中 server 声明的 completion trigger characters 时自动请求并弹出 completion；粘贴、多字符 commit 和未声明能力的 server 不触发。
- 2026-08-01 阶段 24 已完成：AttoEditor completion popup 在打开后会保留 server 返回的完整候选集；普通文本输入和 Backspace 会转发到 editor buffer，并按当前 caret 相对原 replacement start 的 prefix 使用 LSP `filterText` / label 本地增量过滤候选，过滤为空或 caret 离开原 prefix range 时关闭 popup。
- 2026-08-01 阶段 25 已完成：AttoEditor 新增 `AttoWorkspaceEditApplyResult` typed summary，消费 Swift UI binding 返回的 `applied_uri` / `applied_edit_count` / `skipped_uris` / `documents`，rename/code action/completion 当前文档 WorkspaceEdit 应用后会在存在跨文件 skipped URI 时显示 HUD 摘要；WorkspaceEdit 完全不命中 active document 时也会显示受影响文件摘要后保持不应用。
- 2026-08-01 阶段 26 已完成：AttoEditor code action 请求不再固定发送空 `diagnostics` context；新增 `AttoLspCodeActionContext`，从当前 buffer diagnostics 生成 LSP `CodeActionContext`，按 code action selection/caret range 过滤，把 core char-offset range 转成 LSP UTF-16 `Diagnostic.range`，并保留 severity/code/source/message/relatedInformation/data 后发送给 `textDocument/codeAction`。
- 2026-08-01 阶段 27 已完成：AttoEditor code action 主路径新增 kind/filter 产品化入口；`lsp.quick_fix`、`lsp.refactor`、`lsp.source_actions`、`lsp.organize_imports`、`lsp.fix_all` 已接入 command palette 和 Go 菜单，请求时发送 LSP `CodeActionContext.only`，响应后再按 `kind` 精确或前缀匹配做客户端过滤。
- 2026-08-01 阶段 28 已完成：AttoEditor 为 snippet placeholder navigation 新增显式 App command id：`editor.snippet_next_placeholder` / `editor.snippet_prev_placeholder`，通过现有 UI JSON command dispatcher 调用 `snippet_next_placeholder` / `snippet_prev_placeholder`，并接入 command palette、Edit 菜单和命令注册测试；Tab/Backtab 仍保留为文本系统主路径。
- 2026-08-01 阶段 29 已完成：AttoEditor 为多光标 occurrence 操作新增显式 App command id：`editor.add_next_occurrence` / `editor.add_all_occurrences`，通过 UI JSON command dispatcher 调用 `add_next_occurrence` / `add_all_occurrences` 默认 options，并接入 command palette、Edit 菜单、默认 keymap 和命令注册测试。
- 2026-08-01 阶段 30 已完成：AttoEditor 为常用 selection / multicursor 操作新增稳定 App command id：`editor.select_word`、`editor.select_line`、`editor.expand_selection`、`editor.add_cursor_above`、`editor.add_cursor_below`，通过 UI JSON command dispatcher 调用对应 cursor command，并接入 command palette、Edit 菜单和命令注册测试；`editor.select_line` 已有默认 Cmd+L keymap。
- 2026-08-01 阶段 31 已完成：AttoEditor preferences 新增 `autoPairsEnabled` 持久化设置和 “Enable auto pairs” UI；新建 editor chrome 和已打开 panes 会从 `AttoPreferences.effectiveAutoPairsEnabled` 应用 `EditorUI.setAutoPairsEnabled(_:)`，并支持 `ATTO_EDITOR_AUTO_PAIRS` / `EDITOR_CORE_APPKIT_AUTO_PAIRS` 环境变量覆盖默认值。
- 2026-08-01 阶段 32 已完成：AttoEditor preferences 新增 `wrapMode` 持久化设置和 Word Wrap popup；新建 editor chrome 和已打开 panes 会从 `AttoPreferences.effectiveWrapMode` 应用 `EditorUI.setWrapMode(_:)`，并支持 `ATTO_EDITOR_WRAP_MODE` / `EDITOR_CORE_APPKIT_WRAP_MODE` 环境变量覆盖默认值。
- 2026-08-01 阶段 33 已完成：AttoEditor preferences 新增 `wrapIndent` 持久化设置和 Wrap Indent popup/fixed-cells 输入；新建 editor chrome 和已打开 panes 会从 `AttoPreferences.effectiveWrapIndent` 应用 `EditorUI.setWrapIndent(_:)`，并支持 `ATTO_EDITOR_WRAP_INDENT` / `EDITOR_CORE_APPKIT_WRAP_INDENT` 环境变量覆盖默认值。
- 2026-08-01 阶段 34 已完成：AttoEditor 新增基础语言配置表，按 syntax language id 或文件扩展名把 `EcuIndentationConfig` 应用到新打开 editor、手动语言切换和 split clone；toggle comment 也改为消费同一语言配置入口，避免 comment token 与 indentation language 推断分叉。
- 2026-08-01 阶段 35 已完成：AttoEditor command registry 新增基础 group / requiresEditor / isEnabled 元数据；菜单 validation、command palette disabled state 和 `executeCommand(id:)` 会共用同一套 command availability 规则，编辑器命令在没有 active editor 时不再静默 no-op。
- 2026-08-01 阶段 36 已完成：AttoEditor keymap 新增 arrow/navigation function-key token 解析，并为 `editor.move_lines_up` / `editor.move_lines_down` 建立 `super+ctrl+up/down` 默认绑定；Edit 菜单可通过同一 command id 显示并触发对应快捷键。
- 2026-08-01 阶段 37 已完成：AttoEditor 主菜单新增独立 Selection 菜单分组，`select word/line`、`expand selection`、`add cursor above/below` 和 occurrence 命令继续复用统一 command id、keymap 与菜单 validation 路径。
- 2026-08-01 阶段 38 已完成：AttoEditor toggle comment 不再只向 Rust core 传 line token；Swift 语言配置现在会向 `ToggleComment` command 传完整 `line` / `block_start` / `block_end` comment config，HTML/CSS/XML/Markdown 等 block-comment 语言可以走 core block comment 路径。
- 2026-08-01 阶段 39 已完成：Swift `EditorCoreUIFFI` 在现有 derived-state JSON snapshot 之上新增 typed snapshot API，覆盖 diagnostics、decorations、document symbols、folding regions 和 style intervals，App/测试层不再必须到处手写 JSON 字典解析。
- 2026-08-01 阶段 40 已完成：AttoEditor 新增 active-tab derived-state store，使用 Swift typed snapshots 缓存 diagnostics、decorations、document symbols、folding regions 和 style intervals；status bar 开始消费该 store 显示 Problems 数量，测试可通过同一 store 做结构化断言。
- 2026-08-01 阶段 41 已完成：AttoEditor 新增 `lsp.problems` 命令、Go 菜单入口和 Problems quick panel，直接消费 active derived-state store 的 typed diagnostics；无 panel window 时可跳转到第一个 diagnostic，测试覆盖命令注册、菜单入口和 diagnostic range 导航。
- 2026-08-01 阶段 42 已完成：AttoEditor code action diagnostics context 主路径改为消费 active derived-state store 的 typed `EcuDiagnosticsSnapshot`，`AttoLspCodeActionContext` 新增 typed diagnostics 输入并保留旧 JSON 兼容入口，减少 App 层手写 diagnostics JSON 解析。
- 2026-08-01 阶段 43 已完成：AttoEditor document symbols quick panel 在 LSP result 写入 core outline 后，优先从 active derived-state store 的 typed `EcuDocumentSymbolsSnapshot` 构建展示和导航项；raw result JSON parser 只作为兜底，测试覆盖 typed snapshot、嵌套 depth、kind label 和 UTF-16 column 转换。
- 2026-08-01 阶段 44 已完成：AttoEditor `lsp.workspace_symbols` App 命令改为先显示查询输入框，再发起 workspace/symbol 请求；原 `showWorkspaceSymbolsInActiveTab(query:)` 保留给程序化调用和测试，空 active editor 时不会弹框。
- 2026-08-01 阶段 45 已完成：AttoEditor 为主菜单、editor chrome、tab bar/tab chip、find/replace、status bar、sidebar、file/opened/search side panels、command/quick/LSP quick panels 和 completion popup 增加稳定 AppKit `identifier`；新增 `AttoAccessibilityIdentifierTests`，为后续 `XCUIApplication` 黑盒 smoke test 和视觉/布局自动化提供可定位的 UI 元素基线。
- 2026-08-01 阶段 46 已完成：AttoEditor 新增 `lsp.refresh_folding_ranges` App 命令和 View 菜单入口，可显式请求 `textDocument/foldingRange`、轮询结果并应用到 core fold regions；应用后刷新 active derived-state store，错误/超时/LSP 未启用会通过 editor popover 反馈，测试覆盖命令注册、菜单入口和 folding result 到 typed derived-state snapshot 的路径。
- 2026-08-01 阶段 47 已完成：AttoEditor App 层新增 `AttoWorkspaceEditParser`，`WorkspaceEdit` text edits 现在可以按 URI 应用到已打开 tab 或未打开但存在的本地 `file://` 文档；打开 tab 继续走 Rust UI FFI 以保留 undo/dirty/layout 语义，磁盘文件按 LSP UTF-16 坐标转换后原子写回。resource operations、非 file URI、缺失文件、重叠 edits 和 core workspace-owned 跨文件事务当时仍保留为 skipped/后续缺口。
- 2026-08-01 阶段 48 已完成：`editor-core-ui` 对 `workspace/executeCommand` result slot 改为返回 `{ result: ... }` / `{ error: ... }` envelope，不再丢弃 executeCommand 错误；AttoEditor code action command payload 会轮询执行结果并用 editor HUD 展示成功、错误或无结果反馈，新增 `AttoLspExecuteCommandFormatter` typed display helper 和测试。
- 2026-08-01 阶段 49 已完成：`SWIFT-GAPS.md` 明确 Sublime 兼容性不包含继续扩展 `.sublime-syntax`；AttoEditor 后续语言能力重点推进 Tree-sitter 与 LSP 路线，Sublime syntax 以现有 `editor-core-sublime` 行为作为基线，不建立新的 syntax 兼容矩阵或公开规范假设。
- 2026-08-01 阶段 50 已完成：AttoEditor 新增 `lsp.selection_range` App 命令和 Selection 菜单入口，可请求 `textDocument/selectionRange`，轮询 raw result 后用 `AttoLspSelectionRangeParser` typed candidate model 选择下一个严格包含当前选区的范围并应用到 active tab；LSP 未启用、请求失败、超时、空结果和应用失败会通过 editor HUD/蜂鸣反馈。
- 2026-08-01 阶段 51 已完成：AttoEditor 新增 `lsp.document_colors` App 命令和 Go 菜单入口，可请求 `textDocument/documentColor`，用带色块的 quick panel 展示颜色位置；选择颜色后会请求 `textDocument/colorPresentation`，展示 presentation 列表，并能把带 `textEdit` / `additionalTextEdits` 的 presentation 应用到当前文档。新增 `AttoLspDocumentColorParser` typed model，覆盖 LSP UTF-16 range、RGBA、presentation edit 解析和测试。
- 2026-08-01 阶段 52 已完成：AttoEditor 新增 `lsp.linked_editing` App 命令和 Selection 菜单入口，可请求 `textDocument/linkedEditingRange`，用 `AttoLspLinkedEditingParser` typed model 解析 linked ranges，并把结果应用成多个 selection ranges；当前基础同步编辑策略是复用 core multi-cursor/selection replacement，让用户在 linked ranges 被选中后直接输入即可同时替换这些范围。
- 2026-08-01 阶段 53 已完成：AttoEditor 新增 call/type hierarchy 基础 App 主路径，命令覆盖 `lsp.call_hierarchy_incoming`、`lsp.call_hierarchy_outgoing`、`lsp.type_hierarchy_supertypes`、`lsp.type_hierarchy_subtypes`，Go 菜单可触发 prepare hierarchy 请求、选择多个 prepare root、轮询 incoming/outgoing 或 supertypes/subtypes 结果，并用 quick panel 导航到对应 LSP target。新增 `AttoLspHierarchyParser` typed model，覆盖 prepare item、incoming/outgoing call、type hierarchy item、opaque `data` request payload 保留和测试。
- 2026-08-01 阶段 54 已完成：AttoEditor 新增 `lsp.code_lens_actions` App 命令和 Go 菜单入口，可从 active derived-state decorations snapshot 中读取 core 已渲染的 code lens decorations，展示 Code Lens Actions quick panel；选择 action 后若已有 command 则走统一 `workspace/executeCommand` 路径，若缺 command 则先请求 `codeLens/resolve` 再执行。新增 `AttoLspCodeLensParser` typed model，覆盖 decoration `data_json` 中原始 lens payload、resolved lens command 和 command JSON 保留。
- 2026-08-01 阶段 55 已完成：AttoEditor `WorkspaceEdit` App 应用路径新增本地未打开文件的 resource operations 支持，`AttoWorkspaceEditParser` 会把 `documentChanges` 中的 `create` / `rename` / `delete` 解析成 typed operations；应用层会在 workspace root 内对未打开的本地 `file://` 文件执行 create、rename、delete，并支持 create 后紧跟同文件 text edits。
- 2026-08-02 阶段 56 已完成：AttoEditor 新增 `lsp.workspace_diagnostics` App 命令和 Go 菜单入口，可主动请求 `workspace/diagnostic`、轮询 raw result，用 `AttoLspWorkspaceDiagnosticsParser` typed model 解析 workspace diagnostic report、relatedDocuments、resultId 和 LSP UTF-16 ranges，并用 quick panel 展示跨文件 diagnostics；无 panel window 时可直接跳转第一个 diagnostic。阶段 123 已把 workspace diagnostics 快照/`previousResultIds` 合并起点迁入 core-owned `MultiDocumentEditorUi` store。
- 2026-08-02 阶段 57 已完成：AttoEditor LSP location result 主路径不再只对 references 多结果展示 palette；definition、declaration、type definition、implementation 和 references 只要返回多个 target，都会进入统一 `AttoEditor.LSP.LocationResults` quick panel，并按请求类型显示对应 filter placeholder。单结果和无窗口 fallback 仍直接跳转。
- 2026-08-02 阶段 58 已完成：Swift UI binding 新增 `textDocument/codeLens` 手动 request/take 通道，`editor-core-ui` 会在手动 result slot 命中时同步更新 core code lens decorations 并保留 raw result；AttoEditor 新增 `lsp.refresh_code_lens` 命令和 Go 菜单入口，可主动刷新 code lens、轮询 processing、刷新 derived-state/status bar，并用 HUD 反馈刷新完成、无结果、失败或超时。
- 2026-08-02 阶段 59 已完成：AttoEditor `WorkspaceEdit` resource operations 现在也能作用于已打开 tab：`rename` 会更新 open tab URL 并让后续 text edits 命中新 URI，`delete` 会关闭干净 open tab，`create`/overwrite 可同步清空干净 open tab；dirty open tab 会被安全跳过并进入 WorkspaceEdit summary。
- 2026-08-02 阶段 60 已完成：Swift/App 显式 formatting 路径新增 `EditorCoreLSPFormattingResult` typed outcome，document/range/on-type formatting binding 可区分 applied、no edits、LSP unavailable 和 failed；AttoEditor 的显式 Format Document / Format Selection 现在会用 HUD 展示 no edits、不可用和错误原因，旧 Bool API 继续兼容。自动 on-type 异步 response error 仍需后续通过 Rust status/event 路径产品化。
- 2026-08-02 阶段 61 已完成：Rust UI 的自动 `textDocument/onTypeFormatting` 异步 response error 不再静默丢弃，会记录到 `lsp_status_json.detail`；AttoEditor 现有 status bar 路径会显示 `LSP: Failed` 并把 detail 写入日志。后续仍缺面向自动 on-type 错误的去重 HUD/event 通道。
- 2026-08-02 阶段 62 已完成：AttoEditor 新增可测试的 `AttoLspStatusFormatter`，统一解析 `lsp_status_json` 的 status bar 文案和 failure detail；`EditorCoreSkiaView` 的短 async processing poll window 即使没有 applied edits，也会在结束时通知宿主刷新 status，AttoEditor 会对新的 LSP failed detail 弹一次去重 HUD。
- 2026-08-02 阶段 63 已完成：AttoEditor LSP location 多结果新增可测试的 `LocationItem` 展示模型，quick panel 结果会按 workspace-relative 路径、行列位置稳定排序，并保留非 `file://` URI / workspace 外文件的显示兜底。阶段 71 已补最近一次 location/reference snapshot 和 reopen command，阶段 91 已补 bounded history，阶段 114 已补基础持久在线 Locations/References panel；后续仍缺更深层 result lifecycle model。
- 2026-08-02 阶段 64 已完成：Swift `EditorUI` 新增 `lspStatusSnapshot()` typed model，覆盖 availability/state/server/activity/detail 和 completion/signature/capability 摘要；AttoEditor status bar 现在消费 typed snapshot 而不是在 App 层直接解析 raw JSON。后续仍缺通用 LSP event stream、request lifecycle 和状态变更订阅模型。
- 2026-08-02 阶段 65 已完成：AttoEditor LSP capabilities 消费也迁到 typed `EcuLspStatusSnapshot`：semantic tokens engine selection、completion item resolve 支持判断，以及 completion/signature trigger characters 自动触发都不再在 App 行为路径直接解析 raw status JSON；JSON helper 仅保留兼容入口和测试覆盖。
- 2026-08-02 阶段 66 已完成：AttoEditor status bar 左侧 derived-state 摘要开始消费 typed `EcuFoldingRegionsSnapshot`，当 active tab 存在已折叠 region 时显示 `Folded: N`；`SWIFT-GAPS.md` 同步校准 folding 缺口，typed fold region model 不再列为缺失项。
- 2026-08-02 阶段 67 已完成：AttoEditor `lsp.refresh_folding_ranges` 会消费 typed `EcuLspStatusSnapshot.capabilities.foldingRanges`；当 active LSP server 明确未宣告 `textDocument/foldingRange` 时不再发请求，而是直接给出 unsupported 反馈。capabilities 暂缺时仍保留 best-effort 请求路径。
- 2026-08-02 阶段 68 已完成：AttoEditor document/workspace symbols 请求新增统一反馈文案；LSP 未启用、请求失败、poll/take 失败、超时和空结果都会通过 editor HUD 给出明确原因，不再只蜂鸣或静默取消。
- 2026-08-02 阶段 69 已完成：`editor-core-ui-ffi` 新增 UI ABI version 与 feature flags C ABI，Swift `EditorCoreUIFFILibrary` 暴露 `abiVersion`、`featureFlags` 和 `runtimeInfo()` typed facade，覆盖 JSON command dispatcher、typed derived snapshots、LSP interactive requests、LSP status snapshot、WorkspaceEdit application 等 coarse feature probes；SwiftPM Rust build plugin 改为显式 input/output `buildCommand`，避免 ABI/header 变更后继续链接旧 staticlib。
- 2026-08-02 阶段 70 已完成：AttoEditor 新增 `AttoRuntimeCompatibility` 启动期兼容性策略，启动时会读取 Swift UI FFI `runtimeInfo()` 并校验最低 UI ABI version 与当时定义的必需 feature flags；ABI 过低、读取失败或缺少基础必需能力时会在创建窗口前给出明确错误并退出。阶段 105 已把 LSP / WorkspaceEdit 能力改为可选 feature 并接入命令级降级。
- 2026-08-02 阶段 71 已完成：AttoEditor LSP definition/declaration/type definition/implementation/references 结果新增最近一次 `LspLocationResultSnapshot`，多结果 quick panel 和单结果导航都会记录排序后的 typed items；新增 `lsp.show_last_locations` command palette / Go 菜单入口，可重新打开最近一次 location/reference 结果面板或重新跳转单结果。阶段 91 已补 bounded in-memory history，阶段 114 已补基础持久在线 Locations/References panel；后续仍缺更细 result lifecycle。
- 2026-08-02 阶段 72 已完成：AttoEditor LSP document/workspace symbols 结果新增最近一次 `LspSymbolResultSnapshot`，结果 quick panel 会记录 typed symbols 与 placeholder；新增 `lsp.show_last_symbols` command palette / Go 菜单入口，可重新打开最近一次 symbols 结果。阶段 91 已补 bounded in-memory history，阶段 93 已补 workspace symbol 增量查询；后续仍缺完整持久 Outline/Symbols panel 和更深 result lifecycle。
- 2026-08-02 阶段 73 已完成：Rust `editor-core-ui`、C ABI 和 Swift `EditorUI` 新增 code lens view-point hit-test API，可从 above-line virtual text 精确返回原始 `CodeLens` JSON payload；`EditorCoreSkiaView` 新增 Cmd-click code lens host hook，AttoEditor 会解析命中的 lens 并复用现有 resolve / `workspace/executeCommand` 路径执行。测试覆盖 Rust FFI hit-test、Swift FFI hit-test 和 AppKit mouse event 的 Cmd-click 行为。阶段 94 已补当前行键盘定位命令，阶段 97 已补自动辅助刷新消费和状态栏数量反馈；后续仍缺通用 workspace command typed model。
- 2026-08-02 阶段 74 已完成：把超长 crate root 拆成 module，保持原有行为和 ABI 不变。`editor-core-ui` 拆出 `editor_ui.rs` / `tests.rs`，`editor-core-ui-ffi` 拆出 `editor_ui_abi.rs` / `tests.rs`，`editor-core-render-skia` 拆出 `tests.rs`，`editor-core-ffi` 拆出 `json_bridge.rs`；原四个 `lib.rs` 总行数从 28161 降到 8327。已验证 `cargo build -p editor-core-ui -p editor-core-ui-ffi -p editor-core-render-skia -p editor-core-ffi`、四个相关 Rust 测试目标和 Swift FFI smoke。
- 2026-08-02 阶段 75 已完成：继续拆 `editor-core-ui` 和 `editor-core-ui-ffi` 中阶段 74 后仍偏长的两个 implementation 文件，保持 Rust API、C ABI 和 Swift binding 行为不变。`editor-core-ui/src/editor_ui.rs` 将 LSP request/result、processing poll、Tree-sitter prefetch 和 LSP formatting/apply helper 拆入 `editor_ui/lsp.rs`，主文件从 5941 行降到 3869 行；`editor-core-ui-ffi/src/editor_ui_abi.rs` 拆成 `configuration.rs`、`editing.rs`、`lifecycle_theme_syntax.rs`、`lsp.rs`、`rendering_queries.rs`，入口文件降到 11 行。已验证 `cargo build -p editor-core-ui -p editor-core-ui-ffi`、`cargo test -p editor-core-ui --lib`、`cargo test -p editor-core-ui-ffi --lib` 和 `swift test --package-path swift --filter EditorCoreUIFFITests/testCodeLensHitTestReturnsPayloadJSON`。
- 2026-08-02 阶段 76 已完成：继续拆 `crates/editor-core-ui/src/editor_ui.rs`、`crates/editor-core-render-skia/src/lib.rs`、`crates/editor-core-ffi/src/lib.rs` 三个阶段 75 后仍偏长的文件，保持 Rust API、C ABI 和 Swift binding 行为不变。`editor_ui.rs` 拆出 selection、coordinate/hit-test、appearance/search、syntax、viewport、editing/input、rendering 子模块，root 降到 568 行；`editor-core-render-skia` 将 `SkiaRenderer`、font/shaping cache 和绘制 helper 拆入 `renderer.rs`，root 降到 333 行；`editor-core-ffi` 将 ABI 函数组拆成 `editor_state_abi.rs`、`workspace_abi.rs`、`lsp_abi.rs`、`processors_abi.rs`、`binary_abi.rs`，root 降到 717 行。已验证 `cargo build -p editor-core-ui-ffi -p editor-core-ffi`、`cargo test -p editor-core-ui --lib`、`cargo test -p editor-core-render-skia --lib`、`cargo test -p editor-core-ffi`，以及 Swift headless/UI FFI smoke。
- 2026-08-02 阶段 77 已完成：继续拆本轮指定的七个长文件，保持 Rust API、C ABI、Swift binding 和行为不变。`editor-core-render-skia/src/renderer.rs` 现在作为 53 行入口，拆出 `font`、`font_loading`、`geometry`、`drawing`、`style`、`decoration`、`headless`、`composed`、`metal`；`editor-core-ui/src/editor_ui/lsp.rs` 拆出 lifecycle、sync、processing、formatting、apply、requests，并把 requests 再按 common/navigation/completion/actions/document/hierarchy 分组；`editor-core-ui-ffi/src/editor_ui_abi/lsp.rs` 和 `editing.rs` 拆成 ABI 分组模块，LSP requests 再按 common/navigation/completion/actions/document/hierarchy_workspace 分组；`editor-core-ui/src/lib.rs` 拆出 JSON helper、shared LSP session/result slot、render helper 和 Tree-sitter worker；`editor-core-ffi/src/json_bridge.rs` 拆出 parse/value/input，input 再按 primitives/commands/processing 分组；`editor-core-ui/src/editor_ui/editing.rs` 拆成 text、movement、IME/mouse。已验证 `cargo build -p editor-core-ui -p editor-core-ui-ffi -p editor-core-render-skia -p editor-core-ffi`、`cargo test -p editor-core-render-skia --lib`、`cargo test -p editor-core-ui --lib`、`cargo test -p editor-core-ui-ffi --lib`、`cargo test -p editor-core-ffi`，以及 Swift smoke `TypedAPITests/testDocumentStatsAndVersionBump` 和 `EditorCoreUIFFITests/testCodeLensHitTestReturnsPayloadJSON`。
- 2026-08-02 阶段 78 已完成：补齐 headless FFI JSON command plane 相对 UI command JSON 的一批缺口，保持 C ABI 函数表不变，通过 JSON schema 扩展暴露 `type_char`、coalescing replace、`apply_snippet`、snippet placeholder navigation、`move_to_matching_bracket`、auto-pairs config/enabled 和 bracket-match highlight update/clear。Swift `EditorCoreFFI.EditorState` 新增对应 typed convenience API，并新增 `EcfTextEdit`、`EcfAutoPair`、`EcfAutoPairsConfig` DTO。已验证 `cargo test -p editor-core-ffi`、`swift test --package-path swift --filter EditorStateJSONCommandBridgeTests` 和 `swift test --package-path swift --filter TypedAPITests`。
- 2026-08-02 阶段 79 已完成：Swift `EditorCoreFFI.Workspace` 也补上阶段 78 新增 headless JSON command plane 的 typed convenience API，覆盖 `typeChar`、coalescing replace、`applySnippet`、snippet placeholder navigation、`moveToMatchingBracket`、auto-pairs config/enabled 和 bracket-match highlight update/clear。这个阶段只关闭单 view/headless workspace command wrapper 缺口；App 级 tab/split/session/project/LSP lifecycle ownership 仍必须迁移到 core-owned workspace 模型。已验证 `swift test --package-path swift --filter WorkspaceAdditionalTests`。
- 2026-08-02 阶段 80 已完成：`editor-core-ui-ffi` 新增 `MultiDocumentEditorUi` 基础 C ABI 和 feature flag，Swift `EditorCoreUIFFI.MultiDocumentEditorUI` 新增 typed wrapper，覆盖 open/open-preview、active tab、snapshot、set title、pin、close/close-others/close-right、split/view count/active view index 和 search-all-tabs。这个阶段让 core-owned 多文档模型第一次通过 Swift UI FFI 可达；AttoEditor 现有 Swift tabs/splits 迁移为该模型的 AppKit 投影仍未完成。已验证 `cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`、`cargo build -p editor-core-ui-ffi --release` 和 `swift test --package-path swift --filter EditorCoreUIFFITests/testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`。
- 2026-08-02 阶段 81 已完成：AttoEditor window/editor area 初始化 core `MultiDocumentEditorUI` mirror，并把 AppKit tab 的 open/open-preview reuse、select、pin、close、split/focus/close pane lifecycle 同步到 Rust `MultiDocumentEditorUi` snapshot；UI FFI/Swift wrapper 同时补上 close-view API，Atto 启动期 runtime feature gate 现在要求 multi-document UI。这个阶段仍是迁移期投影：实际编辑文本、dirty state、session restore、search-all-tabs 和 project/LSP lifecycle 还没有完全改为 core-owned。已验证 `cargo test -p editor-core-ui --test multi_document_ui_tests`、`cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`、`cargo build -p editor-core-ui-ffi --release`、`swift test --package-path swift --filter AttoEditorCommandTests/testCoreMultiDocumentMirrorTracksTabsAndPanes`、`swift test --package-path swift --filter EditorCoreUIFFITests/testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch`、`swift test --package-path swift --filter AttoRuntimeCompatibilityTests` 以及受影响 split/pane 测试。
- 2026-08-02 阶段 82 已完成：继续收尾阶段 77 后留下的薄入口文件和 `editor-core-ui` crate root，保持 Rust API、C ABI、Swift binding 和行为不变。`editor-core-ui/src/lib.rs` 现在只保留模块入口和 re-export，错误、主题/损坏矩形、内部 prelude、`EditorUi`/`EditorUiDoc`/IME/search/mouse/render cache 状态拆入 `lib/error.rs`、`lib/theme.rs`、`lib/prelude.rs`、`lib/state.rs`；`editor-core-render-skia/src/renderer.rs` 改为 `renderer/mod.rs`，`SkiaRenderer` / Metal state 拆入 `renderer/state.rs`；`editor_ui/lsp.rs`、`editor_ui/editing.rs`、`editor_ui_abi/lsp.rs`、`editor_ui_abi/editing.rs` 和 `editor-core-ffi/src/json_bridge.rs` 统一改成目录 `mod.rs` 入口。已验证 `cargo fmt`、`cargo build -p editor-core-render-skia -p editor-core-ui -p editor-core-ui-ffi -p editor-core-ffi`、`cargo test -p editor-core-render-skia -p editor-core-ui -p editor-core-ui-ffi -p editor-core-ffi` 和 `git diff --check`。
- 2026-08-02 阶段 83 已完成：`MultiDocumentEditorUi` 新增 tab 文本替换、文本读取、dirty 查询和 mark-saved API；UI FFI/header/Swift `MultiDocumentEditorUI` wrapper 暴露对应接口，snapshot 增加 `is_modified`。AttoEditor 在活动 tab 文本 mutation、保存和 WorkspaceEdit 打开 tab 文本替换/resource operation 后同步 core multi-document mirror，因此 core `searchAllTabs` 能搜到 AppKit 当前编辑文本，保存后 core dirty snapshot 也会清零。这个阶段仍是迁移期同步，不代表 session/project/LSP lifecycle 或关闭策略已经完全 core-owned。已验证 `cargo build -p editor-core-ui -p editor-core-ui-ffi`、`cargo test -p editor-core-ui --test multi_document_ui_tests`、`cargo test -p editor-core-ui-ffi ffi_multi_document_exposes_tab_preview_split_and_search`、`swift test --package-path swift --filter EditorCoreUIFFITests/testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch` 和 `swift test --package-path swift --filter AttoEditorCommandTests/testCoreMultiDocumentMirrorTracksEditedTextDirtyAndSearch`。
- 2026-08-02 阶段 84 已完成：AttoEditor Find in Files sidebar 的 `Opened` scope 现在优先通过 `AttoEditorAreaViewController.findInOpenTabs(query:)` 消费 core `MultiDocumentEditorUI.searchAllTabs`，因此可搜索未保存的 open-tab live 文本；`Folder` scope 仍保持 workspace file index + 磁盘搜索。已验证 `swift test --package-path swift --filter AttoEditorCommandTests/testFindInOpenTabsUsesCoreMirrorForUnsavedText`。
- 2026-08-02 阶段 85 已完成：AttoEditor session snapshot 为每个 tab 增加向后兼容的 `paneCount` / `activePaneIndex` 字段，restore 时复用 `EditorUI.cloneView` + core `MultiDocumentEditorUI.splitTab/setActiveViewIndex` mirror 路径重建 split pane 数量和 active pane。测试同时断言 AppKit editor view 数量、恢复后的 session snapshot 和 core multi-document snapshot 的 `viewCount/activeViewIndex`。已验证 `swift test --package-path swift --filter AttoEditorCommandTests/testSessionRestoreRestoresSplitPanesIntoCoreMirror`、`swift test --package-path swift --filter AttoEditorCommandTests/testSplitRightCreatesSharedDocumentPane` 和 `swift test --package-path swift --filter AttoEditorCommandTests/testPaneFocusAndCloseCommandsUseActivePane`。
- 2026-08-02 阶段 86 已完成：`MultiDocumentEditorUi` 新增同一 tab 内 view reorder API，UI FFI/header/Swift `MultiDocumentEditorUI` wrapper 暴露 `moveView`；AttoEditor 新增 `view.move_pane_left` / `view.move_pane_right` 命令、View 菜单和默认 keymap，执行时先移动 core multi-document view，再重排 AppKit panes。测试覆盖 Rust view-local selection identity、C ABI/Swift wrapper、Atto AppKit pane 顺序和 core snapshot active view index 同步。
- 2026-08-02 阶段 87 已完成：AttoEditor 新增 core-backed dirty 查询/同步 helper，关闭单 tab、关闭窗口前的保存全部、preview tab 复用、WorkspaceEdit create/rename/delete resource operation 等可能丢弃或覆盖用户内容的保护条件都会优先消费 `MultiDocumentEditorUI.isTabModified`；Swift `tab.isDirty` 保留为 AppKit 标题/tab bar 展示缓存，并用本地 `EditorUI.isModified` 做保守兜底。测试覆盖 Swift dirty cache 被故意置 stale false 时，core dirty snapshot 仍会阻止 WorkspaceEdit 删除打开 tab。
- 2026-08-02 阶段 88 已完成：`MultiDocumentEditorUi` 新增显式 `tab_order` 和 `move_tab_index`，`tab_ids()`、snapshot、search-all-tabs 和 close-tabs-to-right 都按 core tab order 工作；UI FFI/header/Swift `MultiDocumentEditorUI` wrapper 暴露 `moveTab`，SwiftPM C target stamp 已 bump。AttoEditor 新增 `file.move_tab_left` / `file.move_tab_right` 命令、File 菜单、默认 keymap 和多 tab availability，执行时先移动 core tab order，再重排 AppKit tabs。测试覆盖 Rust core order、C ABI、Swift wrapper、Atto AppKit open-file 顺序和 core snapshot 顺序同步。
- 2026-08-02 阶段 89 已完成：AttoEditor 新增用户可调用的 `go.line` 主路径，用 `EditorUI.moveTo(line:column:)` 执行 core logical `MoveTo`，支持 `line` / `line:column` / `line,column` 输入格式，并接入 command palette、Go 菜单和默认 `ctrl+g` keymap。测试覆盖命令注册、菜单/keymap 接线、输入解析和 caret 目标位置。
- 2026-08-02 阶段 90 已完成：AttoEditor 新增 `cursor.*` App command coverage matrix，覆盖 grapheme/word、visual row/page、visual line start/end、document start/end 以及对应 modify-selection 版本；命令通过 command palette 调用 Swift `EditorUI` typed FFI API，左右/按词移动复用 AppKit 文本命令的选区折叠语义。测试覆盖命令注册、active-editor availability 和 `executeCommand(id:)` 到 Swift editor API 的执行路径。
- 2026-08-02 阶段 91 已完成：AttoEditor 为 LSP location/reference 和 document/workspace symbol 结果新增 bounded in-memory result history，提供 `lsp.show_location_history` / `lsp.show_symbol_history` App 命令和 Go 菜单入口；历史面板可从最近结果列表重新打开已有 quick panel 或单结果导航。测试覆盖命令注册、菜单入口、history snapshot 顺序和历史面板 accessibility/row count。
- 2026-08-02 阶段 92 已完成：AttoEditor 的 LSP selection range 请求现在会发送所有 selections 的 active position，应用结果时按 LSP 返回顺序为每个 selection 选择下一层严格包含范围；可扩展的多光标 selection 会一起扩展，无法扩展的 selection 保持原样，primary selection index 保持不变。测试覆盖 parser per-position candidate chain 和 App 层多 selection apply。
- 2026-08-02 阶段 93 已完成：AttoEditor 的 `lsp.workspace_symbols` 入口从阻塞式 `NSAlert` 输入改为 command-palette 风格的增量查询面板；搜索文本变化会 debounce 后重新发起 `workspace/symbol` 请求，返回结果动态刷新面板，选择结果时记录最近 symbols snapshot/history 并跳转。`AttoCommandPaletteController` 新增初始查询、动态 reload、可关闭本地 fuzzy filter 和搜索文本回调能力，供服务端过滤型面板复用。
- 2026-08-02 阶段 94 已完成：AttoEditor 新增 `lsp.code_lens_at_cursor` 命令和 Go 菜单入口，可从当前 decorations snapshot 中按主光标所在 logical line 过滤 code lens actions，并用现有 Code Lens quick panel 展示当前行结果。测试覆盖命令注册、菜单入口和通过 `lspApplyCodeLensJSON` 写入 decorations 后的当前行过滤面板。
- 2026-08-02 阶段 95 已完成：`AttoLspLinkedEditingParser` 会在应用 linked editing ranges 前验证所有 ranges 当前文本一致，并在 LSP 返回 `wordPattern` 且 Swift 正则可编译时要求 range 文本完整匹配该模式；不一致或不匹配的结果不再转换成多光标 selections。测试覆盖 parser 层共享文本/wordPattern 拒绝逻辑和 App 层不改变原 selections。
- 2026-08-02 阶段 96 已完成：AttoEditor 为 linked editing 增加轻量 active session 生命周期。成功应用 linked ranges 后进入 session；文本变更后只有多光标数量仍匹配时继续保持 session；鼠标点击、光标导航、go-to-line 和其他非文本 selection 变化会退出 session。`EditorCoreSkiaView` / `EditCoreUI` 新增 selection-change hook，测试覆盖输入后的 session 延续和导航退出。
- 2026-08-02 阶段 97 已完成：AttoEditor status bar 的 active derived-state 摘要开始显示当前 code lens action 数量；由于 Rust UI 已在 LSP auxiliary refresh 中自动请求 code lens 并把结果应用为 decorations，App 层现在能通过既有 `updateStatusBar()` / async processing 回调消费自动刷新后的 code lens 状态。测试覆盖 `lspApplyCodeLensJSON` 后 derived snapshot 与状态栏 `Code Lens: N` 反馈。
- 2026-08-02 阶段 98 已完成：AttoEditor workspace symbols parser 新增统一 kind 分组/稳定排序策略，按 Types、Functions、Values、Other 分组，再按名称、容器、URI 和位置排序；普通 workspace symbol 结果、增量查询结果和历史 snapshot 都消费同一个排序入口，quick panel command 也带有同一 kind group 元数据。测试覆盖 parser 层排序 tie-break 和 App 层 snapshot 顺序。
- 2026-08-02 阶段 99 已完成：AttoEditor 新增 `lsp.pick_document_color` 命令和 Go 菜单入口；document color result 可进入直接 color picker 路径，单个颜色会直接打开 `NSColorPanel`，多个颜色先用色块 quick panel 选择目标，选中颜色变化后继续复用既有 `textDocument/colorPresentation` 请求和 apply 链路。测试覆盖命令/菜单注册，以及注入 picker 时的初始颜色和 range selection。
- 2026-08-02 阶段 100 已完成：AttoEditor 新增通用 `editor.apply_snippet` App command 和 Edit 菜单入口；命令可通过输入框接收 editor-core snippet 字符串，并应用到当前 primary selection range，继续使用既有 `EditorUI.applySnippet` 和 snippet placeholder session。测试覆盖命令/菜单注册、文本插入和 active snippet session。
- 2026-08-02 阶段 101 已完成：AttoEditor 的 `editor.add_next_occurrence` / `editor.add_all_occurrences` 命令从静态 JSON 默认参数改为调用 Swift typed API，并消费 Find bar 当前 case-sensitive / whole-word / regex search options。测试覆盖关闭 `Aa` 后 add-all occurrence 会按大小写不敏感选中所有匹配。
- 2026-08-02 阶段 102 已完成：AttoEditor comment toggle 新增用户语言级 comment configuration override，`AttoPreferences` 可按 normalized language key 存储 line/block comment token，`editor.toggle_line_comment` 会优先使用用户覆盖再回落到内置语言默认。测试覆盖 preferences 存取归一化/清除，以及 `.py` 文件按用户覆盖 token 注释。
- 2026-08-02 阶段 103 已完成：`editor-core-render-skia` 为 gutter fold marker 增加确定性像素回归覆盖，包含默认 triangle 样式 collapsed/expanded raster 差异、hidden marker 不绘制、composed grid 中 virtual line 不绘制而 document line 绘制 marker，以及 fold marker 状态变化时 partial-row redraw 与完整重绘一致。已验证 `cargo test -p editor-core-render-skia fold_marker --release`。
- 2026-08-02 阶段 104 已完成：AttoEditor command registry 新增基础 `AttoCommandSchema` 参数模型，覆盖 string/integer/number/boolean/json 参数、必填/默认值/空字符串/整数范围/choice 校验、宏录制策略和静态 editor-core JSON command payload 元数据；`executeCommand(id:arguments:)` 现在可通过 typed arguments 执行 `go.line`、`editor.apply_snippet`、`lsp.workspace_symbols` 和 `lsp.rename` 这类已有非弹窗执行路径的参数化命令。默认命令集新增重复 command id 冲突检测测试。
- 2026-08-02 阶段 105 已完成：AttoEditor runtime compatibility 将启动必需 feature 与可选 feature 拆分，`LSP interactive requests`、`LSP status snapshot` 和 `WorkspaceEdit application` 缺失时不再阻止基础编辑器启动，而是记录为 optional gap；`AttoCommandSchema.requiredRuntimeFeatures` 接入 command registry，菜单 validation、command palette disabled state 和 `executeCommand(id:)` 会统一禁用缺少 runtime 支持的 LSP/formatting/WorkspaceEdit 命令，同时保留基础编辑命令可用。测试覆盖 optional feature 报告和 active editor 下命令级降级。
- 2026-08-02 阶段 106 已完成：AttoEditor keymap 解析新增 Sublime 风格 `context` 条件过滤和确定性冲突解析。用户 keymap entry 现在支持 `equal` / `not_equal` / `regex_match` / `not_regex_match` 条件，`resolvedKeymap(...)` 会返回最终 bindings 与 conflicts，同一快捷键冲突时采用“后出现的匹配项获胜并移除旧 command binding”的规则，避免菜单层保留重复 shortcut。测试覆盖 context 匹配、regex 条件、用户条目互相冲突、用户条目 shadow 默认快捷键。
- 2026-08-02 阶段 107 已完成：AttoEditor keymap 用户条目支持解码 Sublime 风格 `args`，`AttoKeymapResolution` 会携带 command arguments，AppDelegate 的菜单/shortcut command 路径会在存在 args 时调用 `executeCommand(id:arguments:)`。测试覆盖 `go.line` 参数路由、`editor.apply_snippet` 参数解析和 nested JSON 参数保留。
- 2026-08-02 阶段 108 已完成：AttoEditor keymap 用户条目支持基础多键序列（chord）解析和 App 层 key-down dispatcher。多键序列不再占用菜单单键 shortcut，AppDelegate 会维护 pending prefix，完整序列命中后复用统一 command path 和 keymap `args`。测试覆盖 `["ctrl+k", "ctrl+g"]` 触发参数化 `go.line`。
- 2026-08-02 阶段 109 已完成：AttoEditor keymap chord dispatcher 新增 pending prefix 超时和 Escape 取消行为。prefix 成立时会启动短超时，命中、失败、超时或 Escape 都会清理 pending sequence，避免 chord prefix 永久吞键。测试覆盖手动过期和 Escape 取消后第二键不再触发命令。
- 2026-08-02 阶段 110 已完成：AttoEditor keymap chord prefix 现在会在状态栏左侧显示 `Keys: ...` 短提示，并在完整命中、失败、超时或 Escape 取消时清空，恢复原 derived-state 摘要。测试覆盖 prefix 提示出现、命中清空、手动过期清空和 Escape 清空。
- 2026-08-02 阶段 111 已完成：AttoEditor keymap 解析扩展 Sublime 风格键名和 context operator。键名新增字面 `+`、命名标点、forward delete / insert / begin / clear / help 等 token；context 新增 `regex_contains` / `not_regex_contains`，并让 `regex_match` / `not_regex_match` 按整串匹配语义与 contains 区分。测试覆盖扩展键名、function-key display text、缺失 context 不匹配、整串 regex match 和 contains/not-contains 差异。
- 2026-08-02 阶段 112 已完成：AttoEditor keymap context resolver 支持 Sublime 风格 `match_all` 多值上下文语义。`AttoKeymapContextValue` 新增 list 值，condition 在 list 上默认 any-match，`match_all: true` 时要求所有值都匹配；测试覆盖多 selection 风格的 `selection_empty` 和 selector regex 条件。
- 2026-08-02 阶段 113 已完成：AttoEditor App key-down dispatcher 现在会按 active editor 状态动态解析 keymap context，而不是只使用启动时空 context 的缓存结果。运行时 context 注入 `has_active_editor`、`selection_empty`、`num_selections`、`has_multiple_selections`、`selector`、`syntax`、`file_name`、`file_extension`、dirty/tab/pane 摘要；local key monitor 现在可按当前 context 触发单键 binding 和 chord，并使用同一动态 keymap 的 `args`。测试覆盖无 active editor 不命中、active `.swift` 非空选区命中、selector/file extension context 和动态 args 执行。
- 2026-08-02 阶段 114 已完成：AttoEditor 新增持久在线的 LSP Locations/References panel，和一次性 quick panel 分离。location/reference 结果现在会记录到可重复显示的 `AttoLspLocationPanelController`，panel 带过滤框、稳定 accessibility identifiers、可在打开状态下随新结果更新，并通过 `lsp.show_locations_panel` command / Go 菜单入口重新打开最后结果；测试覆盖 command 注册、panel identifiers/filtering、快照保持和新结果自动刷新。
- 2026-08-02 阶段 115 已完成：AttoEditor 新增持久在线的 LSP Outline/Symbols panel，复用现有 document/workspace symbols typed snapshot 和导航路径。symbol 结果现在可通过 `AttoLspSymbolPanelController` 以持久 panel 展示、过滤和打开；panel 带稳定 accessibility identifiers，可随新 document/workspace symbol 结果自动刷新，并通过 `lsp.show_symbols_panel` command / Go 菜单入口重新打开最后结果；测试覆盖 command/menu 注册、panel identifiers/filtering、快照保持和新结果自动刷新。
- 2026-08-02 阶段 116 已完成：AttoEditor 新增 active-tab 持久 Problems panel，复用 active derived-state store 的 typed diagnostics 和现有 diagnostic navigation 路径。`AttoProblemsPanelController` 提供可过滤、可重复显示的 panel，带稳定 accessibility identifiers；打开后会随 `updateStatusBar()` 的 derived-state refresh 自动刷新，并通过 `lsp.show_problems_panel` command / Go 菜单入口打开。测试覆盖 command/menu 注册、panel identifiers/filtering、diagnostic 打开和 diagnostics 刷新。
- 2026-08-02 阶段 117 已完成：AttoEditor 新增 workspace Problems store/panel。`AttoWorkspaceProblemsStore` 会缓存 `workspace/diagnostic` typed reports，合并 `full` / `unchanged` result 并为下一次请求提供 `previousResultIds`；workspace diagnostics result 会刷新持久在线 workspace Problems panel，并通过 `lsp.show_workspace_problems_panel` command / Go 菜单入口重新打开。阶段 123 已把该 store 的主路径改为消费 core-owned `MultiDocumentEditorUi` workspace diagnostics snapshot，Swift 本地缓存保留为迁移期 fallback。
- 2026-08-02 阶段 118 已完成：EditorCoreUI minimap 新增 diagnostic marker API 和绘制路径，AttoEditor 的 active derived diagnostics 会在 `updateStatusBar()` 刷新时同步成当前 tab 所有 panes 的 minimap markers。测试覆盖 marker logical-line 到 minimap rect 的映射，以及 active diagnostics 到 minimap markers 的 App 层投影；workspace diagnostics marker 聚合起点已在阶段 124 迁到 core-backed marker snapshot。
- 2026-08-02 阶段 119 已完成：EditorCoreUI 新增 gutter diagnostic marker API，并在 `EditorCoreSkiaView` 上用透明 overlay 绘制 active-tab diagnostics 的 gutter 图标；AttoEditor 会在 `updateStatusBar()` 刷新时把 active derived diagnostics 同步到当前 tab 所有 panes 的 gutter markers。测试覆盖 marker char-offset 到 gutter rect 的映射，以及 active diagnostics 到 gutter markers 的 App 层投影；workspace diagnostics marker 聚合起点已在阶段 124 迁到 core-backed marker snapshot。
- 2026-08-02 阶段 120 已完成：AttoEditor workspace diagnostics store 会把 `workspace/diagnostic` 结果投影到已打开 tab 的 minimap/gutter markers；active tab 合并 active derived diagnostics 与 workspace diagnostics，非 active open tabs 消费 workspace store。`full` report 更新或清空后会刷新 open-tab markers。当前仍是 App 层 workspace store 到 open-tab UI 的投影，core-owned project 级 Problems/marker 归属仍未完成。
- 2026-08-02 阶段 121 已完成：AttoEditor 新增通用 `AttoLspResultLifecycleStore`，把 locations/references 与 document/workspace symbols 的 current result、bounded history 和 reopen/persistent-panel refresh 逻辑统一到一个 lifecycle store 起点。当前仍只覆盖已有 locations/symbols 结果族，尚未形成所有 LSP result 的统一 envelope/event model。
- 2026-08-02 阶段 122 已完成：`AttoLspResultLifecycleStore` 的 history 从裸 snapshot 升级为 typed lifecycle entry，记录 sequence、family、title、recordedAt 和 snapshot；locations/references 与 document/workspace symbols 的 history palette 现在从 entry reopen，并保留 `current` / `history` 兼容投影。当前仍只覆盖已有 locations/symbols result family，尚未覆盖 completion、rename、code action、diagnostics、color、hierarchy 等所有 LSP result，也尚未形成 core-owned event stream。
- 2026-08-02 阶段 123 已完成：`MultiDocumentEditorUi` 新增 core-owned workspace diagnostics store，可解析并合并 LSP `workspace/diagnostic` 的 `full` / `unchanged` reports、`relatedDocuments`、diagnostic severity/code/source/message 和 `previousResultIds`；`editor-core-ui-ffi` / Swift `MultiDocumentEditorUI` 新增 apply/snapshot/previousResultIds/clear API 和 runtime feature flag。AttoEditor 的 `AttoWorkspaceProblemsStore` 现在优先消费 core-owned snapshot，Swift 本地 parser/store 只作为迁移期 fallback。阶段 124 已继续补齐 core-backed workspace diagnostic marker snapshot 起点；当前仍缺 workspace diagnostics 与 active derived diagnostics 的统一 derived-state model，以及更通用的 project/LSP event stream。
- 2026-08-02 阶段 124 已完成：`MultiDocumentEditorUi` workspace diagnostics store 新增 project-level marker snapshot，按 core-owned diagnostics 生成 URI、LSP 起点和 severity 归一化后的 marker projections；UI FFI / Swift `MultiDocumentEditorUI` 新增 marker snapshot JSON/API。AttoEditor workspace minimap/gutter marker 投影现在先消费 core-backed marker projections，再在 AppKit 层按当前 buffer 文本完成 UTF-16 到 char offset 转换。当前仍缺 workspace diagnostics 与 active-tab derived diagnostics 的统一 derived-state model、统一刷新/过期策略和更通用的 project/LSP event stream。

## 分层结论

### 1. Headless core 到 headless Swift FFI

`editor-core-ffi` 通过 JSON command plane 暴露了不少核心命令，Swift `EditorState.executeJSON(_:)` 和 `Workspace.executeJSON(viewId:commandJSON:)` 可以使用这条路径。阶段 78/79 已把 `type_char`、snippet、auto-pairs、bracket matching/highlights 和 coalescing replace 这批 view-local command 补成 `EditorState` / `Workspace` 两侧的 Swift typed convenience API。

主要问题：

- JSON 命令面不是 `editor-core` 全量枚举的一比一映射。
- 一些低频但对 Sublime 兼容很关键的命令没有进 `editor-core-ffi`。
- Swift headless wrapper 有 JSON escape hatch；高层 Swift 类型化 API 已覆盖主要基础编辑 command 缺口，但还不是 `editor-core` / workspace / LSP lifecycle 的全量 typed 投影。

### 2. `editor-core-ui` 到 Swift `EditorUI`

`editor-core-ui` 本身比 Swift `EditorUI` 暴露更多能力。阶段 1 已经补上 Swift UI 通用 JSON dispatcher，因此很多 core/FFI 已有能力现在可以到达 Swift `EditorUI`；阶段 3 已为高频命令补上 Swift typed convenience API；阶段 4 已把 P0 App 命令接入主菜单和默认/用户 keymap；阶段 5 已补上主要派生状态的 Swift JSON snapshot API。但 AttoEditor App 命令系统在启用状态、参数、上下文、LSP/项目命令覆盖和派生状态消费上仍未完整。

主要问题：

- UI 层 typed API 已覆盖 P0 高频命令，但仍不是 core 命令面的完整子集。
- 低频或尚未产品化能力仍只能通过 `executeCommandJSON(_:)` 使用。
- 部分能力 headless FFI、UI FFI 和 Swift typed API 的覆盖形态仍不一致。

### 3. Swift `EditorUI` 到 AttoEditor App

AttoEditor 已经可以编辑、搜索、替换、渲染、切换主题/语法、显示部分 LSP 派生信息。但 Sublime 复刻需要一个更完整的 App 级命令系统、keymap、command palette、设置系统、分屏/多文档模型和视觉回归测试。

主要问题：

- App 命令 palette 目前偏基础。
- 很多 Swift `EditorUI` 能力没有被产品层命令化。
- 一些 core 能力即便能通过低层 API 间接完成，也没有稳定 command id，难以做键盘绑定和 UI 自动化测试。

## 核心命令面缺口

下面的表格只列与 Swift 产品层相关的主要缺口，不代表 Rust core 缺功能。

| 能力 | Rust core | headless FFI JSON | Swift `EditorUI` / App | 缺口 |
| --- | --- | --- | --- | --- |
| `TypeChar` | 有 | 有 | Swift headless/UI 都有 typed `typeChar(_:)`；`insertText` 单字符也会在 Rust UI 内部走 typing 路径 | headless/UI JSON 覆盖已对齐；App 显式 command id 仍按产品需要评估。 |
| `ReplaceCoalescingUndo` / `ReplaceCoalescingUndoWithSelection` | 有 | 有 | Swift headless/UI 都有 typed `replaceCoalescingUndo` / `replaceCoalescingUndoWithSelection`；IME/marked text 路径内部也使用相关语义 | headless/UI command 覆盖已对齐。 |
| `ApplySnippet` | 有 | 有 | Swift headless/UI 都有 typed `applySnippet`；AttoEditor 有通用 `editor.apply_snippet` command/menu，Tab/Backtab 可在 snippet active 时切 placeholder；completion popup 可应用 snippet item | App 显式 command 已补齐；headless/UI command 覆盖已对齐。 |
| `SnippetNextPlaceholder` / `SnippetPrevPlaceholder` | 有 | 有 | Swift headless/UI 都有 typed `snippetNextPlaceholder` / `snippetPrevPlaceholder`，`insertTab` / `insertBacktab` 也内部支持；AttoEditor command palette 和菜单有 `editor.snippet_next_placeholder` / `editor.snippet_prev_placeholder` | App 显式 command 已补齐；headless/UI command 覆盖已对齐。 |
| duplicate lines | 有 | 有 | Swift 有 typed `duplicateLines()`；AttoEditor command palette、菜单和 keymap 有 `editor.duplicate_lines` | P0 接线和基础启用/禁用状态模型已补齐。 |
| delete lines | 有 | 有 | Swift 有 typed `deleteLines()`；AttoEditor command palette、菜单和 keymap 有 `editor.delete_lines` | P0 接线和基础启用/禁用状态模型已补齐。 |
| move lines up/down | 有 | 有 | Swift 有 typed `moveLinesUp()` / `moveLinesDown()`；AttoEditor command palette、菜单和默认 keymap 有 `editor.move_lines_up/down` | P0 菜单和 arrow-key 默认 keymap 接线完成。 |
| join lines | 有 | 有 | Swift 有 typed `joinLines()`；AttoEditor command palette、菜单和 keymap 有 `editor.join_lines` | P0 接线和基础启用/禁用状态模型已补齐。 |
| split line | 有 | 有 | Swift 有 typed `splitLine()`；AttoEditor command palette 和菜单有 `editor.split_line` | P0 菜单接线完成；可配置 keymap 可覆盖。 |
| toggle comment | 有 | 有 | Swift 有 typed `toggleComment(_:)`；AttoEditor command palette、菜单和 keymap 有 `editor.toggle_line_comment`，并按语言配置向 core 传 `line` / `block_start` / `block_end` comment config；用户可通过 preferences 按 language key 覆盖 line/block comment token | 基础 line/block comment config 桥接和用户 settings 覆盖已补齐。 |
| general `ApplyTextEdits` | 有 | 有 | Swift 有 typed `applyTextEdits(_:)`；Rust UI 也有 LSP text edit apply helper；completion popup 可应用 textEdit/additionalTextEdits | LSP code action、rename 等仍需要产品化接线。 |
| `DeleteToPrevTabStop` | 有 | 有 | Swift 有 typed `deleteToPrevTabStop()`；AttoEditor command palette 和菜单有 `editor.delete_to_prev_tab_stop` | P0 菜单接线完成；可配置 keymap 可覆盖。 |
| explicit indent/outdent commands | 有 | 有 | Swift 有 typed `indent()` / `outdent()`；Tab/Backtab 主路径可用；AttoEditor command palette 和菜单有 `editor.indent/outdent` | P0 菜单接线完成；Tab/Backtab 仍走文本系统主路径。 |
| `EndUndoGroup` | 有 | 有 | Swift 有 typed `endUndoGroup()` | App 层复合命令还未统一使用。 |
| logical `MoveTo` / `MoveBy` | 有 | 有 | Swift 有 typed `moveTo(line:column:)` / `moveBy(deltaLine:deltaColumn:)`；AttoEditor 已有 `go.line` 参数化 App command，接入 command palette、Go 菜单和默认 `ctrl+g` keymap | `MoveTo` 主路径已产品化；`MoveBy` 参数化用户命令仍按产品需要评估。 |
| visual movement commands | 有 | 有 | Swift 有 typed grapheme/word、visual row/page、line/document start/end 及 modify-selection wrapper；AttoEditor command palette 已有 `cursor.*` coverage matrix，直接调用 typed API | App command matrix 已补齐；未给每个低层 cursor command 增加默认菜单项/keymap，默认键盘主路径仍由 AppKit text system dispatch。 |
| selection / multicursor commands | 有 | 有 | Swift UI FFI 有 typed select word/line、expand selection、add cursor above/below，也可通过 UI JSON 调用；AttoEditor command palette 和 Selection 菜单有 `editor.select_word` / `editor.select_line` / `editor.expand_selection` / `editor.add_cursor_above` / `editor.add_cursor_below`；selection-modifying visual movement 通过 `cursor.select_*` command palette 覆盖；keymap 已支持 arrow/navigation function-key token | 常用 App command、Selection 菜单分组和 cursor selection movement matrix 已补齐；细粒度默认 keymap 仍走 AppKit 文本系统。 |
| `MoveToMatchingBracket` | 有 | 有 | Swift headless/UI 都有公开方法 | headless/UI command 覆盖已对齐。 |
| add occurrence options | 有 | 有 | Swift typed `addNextOccurrence(options:)` / `addAllOccurrences(options:)` 已支持 options；AttoEditor command palette、菜单和 keymap 有 `editor.add_next_occurrence` / `editor.add_all_occurrences`，并会消费 Find bar 当前 search options | App command/keymap 和 search-options 接线已补齐。 |
| `SetWrapMode` | 有 | 有 | Swift 有 typed `setWrapMode(_:)`；AttoEditor command palette、菜单和 keymap 有 wrap off/char/word；preferences 有持久化 wrap mode 并会应用到新建和已打开 editor | App settings 接线已补齐。 |
| `SetWrapIndent` | 有 | 有 | Swift 有 typed `setWrapIndent(_:)`；preferences 有持久化 wrap indent 并会应用到新建和已打开 editor | App settings 接线已补齐。 |
| `SetIndentationConfig` | 有 | 有 | Swift 有 typed `setIndentationConfig(_:)`；AttoEditor 会按 syntax language id 或文件扩展名应用基础语言 indentation config 到新建 editor、手动语言切换和 split clone | 基础语言配置接线已补齐；仍可继续扩展语言表和用户覆盖配置。 |
| `SetAutoPairsConfig` | 有 | 有 | Swift headless/UI 都有 typed config API；UI 也有 enabled bool | headless/UI command 覆盖已对齐。 |
| `SetAutoPairsEnabled` | 有 | 有 | Swift headless/UI 都有 bool API；AttoEditor preferences 有持久化开关并会应用到新建和已打开 editor | App settings 接线已补齐；headless/UI command 覆盖已对齐。 |
| fold / unfold / unfold all | 有 | 有 | Swift 有 typed `fold` / `unfold` / `unfoldAll`；AttoEditor command palette、菜单和 keymap 有 fold selection/unfold/unfold all；Swift UI binding 已可把 LSP folding ranges 应用到 core fold regions，AttoEditor refresh 命令会按 typed LSP folding capability 拦截 unsupported server；gutter fold marker 视觉回归 baseline 已补齐 | P0 接线完成；仍缺 result lifecycle model。 |
| bracket match highlight update/clear | 有 | 有 | Swift headless/UI 都有 typed `updateBracketMatchHighlights` / `clearBracketMatchHighlights`；Swift UI 另有 enabled bool 和内部更新 | headless/UI command 覆盖已对齐。 |

建议不要为每个低频命令都新增一个独立 C ABI 函数。更合理的方向是：

- 保留 `editor-core-ui-ffi` 的 UI command JSON dispatcher 作为低频命令和迁移期间的 escape hatch。
- Swift `EditorUI` 提供 typed convenience API，同时保留 JSON escape hatch。
- AttoEditor 建立 command registry，所有菜单、command palette、keymap、测试都走同一组 command id。

## LSP 功能缺口

`editor-core-lsp` 的能力面很大，但 Swift UI/App 目前只产品化了其中一部分。

当前 Swift UI/App 已覆盖或部分覆盖：

- LSP enable/status。
- hover。
- definition。
- declaration / type definition / implementation / references / completion / completion item resolve / signature help / prepare rename / rename / code action / code action resolve / code lens refresh / code lens resolve / document symbols / workspace symbols / folding ranges / selection range / linked editing range / pull diagnostics / document color / color presentation / call hierarchy / type hierarchy 的 Swift UI raw async request/take API。
- AttoEditor App command/menu 已覆盖 go to definition/declaration/type definition/implementation/find references，其中 references 多结果有轻量可过滤结果 palette。
- AttoEditor App command/menu 已覆盖 call hierarchy incoming/outgoing 和 type hierarchy supertypes/subtypes 的基础 quick panel 导航主路径。
- AttoEditor App command/menu 已覆盖 completion popup 主路径。
- AttoEditor App completion popup commit 路径已覆盖 `completionItem/resolve`，可把 resolved item 的 `textEdit`、`additionalTextEdits` 和 snippet payload 应用到当前文档；resolve 不可用或超时时会回退到原始 item。
- AttoEditor App command/menu 已覆盖 signature help popup 主路径。
- document formatting。
- diagnostics 派生状态应用。
- semantic tokens 到 style intervals 的应用。
- inlay hints。
- code lens 派生显示。
- AttoEditor App command/menu 已覆盖 active code lens actions quick panel；可消费 core code lens decorations 中保留的原始 lens JSON，必要时先 resolve 再执行 command；above-line code lens virtual text 也可通过 Cmd-click hit-test 直接执行。
- document links hit-test。
- document highlights。
- document symbols result 到 core outline 的应用和 JSON 导出。
- folding ranges result 到 core fold regions 的应用和 JSON 导出。
- workspace diagnostics raw result 已有 App quick panel 主路径和 typed parser，可展示跨文件 pull diagnostics 并跳转。
- WorkspaceEdit 中当前文档 `TextEdit` 的 Swift UI binding 应用，并返回跨 URI skip/summary 信息；AttoEditor App 层已能把同一 WorkspaceEdit 的 text edits 应用到已打开 tab 和未打开但存在的本地 `file://` 文档，也能对 workspace root 内打开或未打开的本地文件执行 `create` / `rename` / `delete` resource operations。
- AttoEditor App command/menu/keymap 已覆盖 `lsp.rename` 主路径，可输入新名称、请求 LSP rename，并把返回的 WorkspaceEdit text edits 应用到当前文档、已打开跨文件 tab 或未打开本地文件；打开 tab 与未打开本地文件的 create/rename/delete resource operations 也可应用。
- AttoEditor App command/menu/keymap 已覆盖 `lsp.code_actions` 主路径，可从 typed diagnostics snapshot 生成当前 diagnostics context、展示 code action quick panel、resolve action、应用 WorkspaceEdit text edits、展示跨文件 WorkspaceEdit 摘要，处理打开 tab 与未打开本地文件 resource operations，发起 `workspace/executeCommand` 并展示其成功/错误/无结果反馈；Quick Fix / Refactor / Source Action / Organize Imports / Fix All 已通过 `CodeActionContext.only` 和客户端 kind 前缀过滤产品化。
- Swift UI binding 已覆盖 document/range/on-type formatting 的阻塞请求和当前文档 `TextEdit` 应用；AttoEditor App command/menu 已覆盖 `editor.format_document`，command/menu/keymap 已覆盖 `editor.format_selection` 主路径。
- `LSPBridge` 中有若干 JSON/DTO 转换 helper。

仍缺产品化、结果 UI 或仍只停留在 raw API 的 LSP 能力：

- definition/declaration/type definition/implementation/references 多结果已有统一 quick panel，展示 item model、稳定排序、最近结果 snapshot、reopen command、bounded in-memory history command 和基础持久在线 Locations/References panel；locations/references 的 current/history 已迁入通用 lifecycle store，并开始记录 typed lifecycle entry/envelope 元数据。仍缺覆盖所有 result family 的 lifecycle/event model、项目级归属和更完整刷新/过期策略。
- completion popup 主路径、commit-time completion resolve、rich documentation/detail preview、commitCharacters 提交行为、server triggerCharacters 自动触发、本地增量过滤、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用，以及打开 tab / 本地未打开文件 resource operations 已有；仍缺 core workspace-owned 跨文件事务和完整 typed result model。
- signature help popup 主路径已有，并会按 server trigger/retrigger characters 自动弹出，active parameter 富格式高亮、typed result model 和手动请求空/错反馈已完成。
- rename 主路径已有 App 输入 UI、prepareRename range/placeholder 默认名、当前文档 WorkspaceEdit 应用、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用，以及打开 tab / 本地未打开文件 resource operations；仍缺 core workspace-owned 跨文件事务和 typed result model。
- code action 主路径已有 App quick panel、resolve、typed diagnostics context、kind/filter、当前文档 edit 应用、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations、command 执行和执行结果/错误 HUD；仍缺 core workspace-owned 跨文件事务和 typed result model。
- code lens refresh、code lens resolve、active code lens actions quick panel、当前行键盘定位命令、内联 Cmd-click hit-test、Rust/UI auxiliary 自动刷新消费、状态栏数量反馈和 workspace command execution 的 Swift UI/App 路径已有；仍缺通用 workspace command typed model。
- outline / document symbols 已有 quick panel 主路径，document symbols 展示已消费 typed derived-state snapshot，基础错误/超时/空结果反馈、最近结果 snapshot、reopen command、bounded in-memory history command 和基础持久 Outline/Symbols panel 已补齐；document/workspace symbols 的 current/history 已迁入通用 lifecycle store，并开始记录 typed lifecycle entry/envelope 元数据。仍缺覆盖所有 result family 的更深层 lifecycle/event model。
- workspace symbols 已有增量查询输入面板、quick panel 主路径、kind 分组/稳定排序、基础错误/超时/空结果反馈、最近结果 snapshot、reopen command、bounded in-memory history command 和基础持久结果 panel；symbol result current/history 已迁入通用 lifecycle store，并开始记录 typed lifecycle entry/envelope 元数据。仍缺完整结果模型和覆盖所有 result family 的更深层 lifecycle/event model。
- on-type formatting 已有 explicit binding、换行触发和 server trigger characters 自动触发路径；显式 Swift binding 的 `EditorCoreLSPFormattingResult` typed outcome 已完成，自动 on-type 异步 response error 已进入 LSP status/detail，AttoEditor 会刷新 status 并对新的 failure detail 弹一次去重 HUD；Swift 已有 typed `lspStatusSnapshot()`，AttoEditor 的 LSP status/capabilities 行为路径也已迁到 typed snapshot。后续仍缺更通用的 LSP event stream、request lifecycle 和状态变更订阅模型。
- semantic tokens refresh / delta 策略。
- folding ranges binding 已覆盖 request/take/apply 到 fold UI state，AttoEditor 已有显式 refresh 命令、typed capability gate、菜单入口、错误/超时反馈、typed fold snapshot、status bar 折叠摘要和 renderer 层 gutter fold marker 视觉回归 baseline；仍缺更完整的 result lifecycle model。
- selection range raw request/take 已有；App 层 `lsp.selection_range` expand-selection 主路径、typed candidate model 和多光标 selection range 策略已完成，仍缺更完整 result lifecycle model。
- linked editing raw request/take 已有；App 层 `lsp.linked_editing` 主路径、typed parser、wordPattern/shared-text 校验、基于 multi-cursor selections 的基础同步编辑策略和轻量 session 生命周期/退出条件已完成；仍缺更完整 result lifecycle model。
- document diagnostic pull / workspace diagnostic raw request/take 已有；active-tab Problems quick panel 和 active-tab 持久 Problems panel 已消费 typed diagnostics，workspace diagnostics 也已有基础 quick panel、typed parser、core-backed workspace Problems store/panel、`previousResultIds` 增量请求参数和 core-backed marker snapshot；仍缺 workspace diagnostics 与 active derived diagnostics 的统一 derived-state model、刷新/过期策略以及更完整 typed model。
- document color / color presentation raw request/take 已有；App 层 `lsp.document_colors` 主路径、色块 quick panel、直接 color picker、color presentation apply 和 typed parser 已完成；仍缺持久颜色面板、多文档/workspace 颜色聚合和更完整 result lifecycle model。
- call hierarchy raw request/take、基础 App 命令、prepare root 选择、incoming/outgoing quick panel 导航和 typed parser 已有；仍缺树状 hierarchy 持久面板、层级展开/刷新、跨文件结果聚合和更完整 result lifecycle model。
- type hierarchy raw request/take、基础 App 命令、prepare root 选择、supertypes/subtypes quick panel 导航和 typed parser 已有；仍缺树状 hierarchy 持久面板、层级展开/刷新、跨文件结果聚合和更完整 result lifecycle model。
- references/locations 已有 quick panel、history 和基础持久在线结果 panel；仍缺更深层 result lifecycle model。
- request cancellation、debounce、超时和错误展示策略。

其中一部分能力在 `EditorCoreFFI.LSPBridge` 中有数据转换函数，但这不等于 AttoEditor 已经有完整产品路径。完整路径至少需要：

- 从 Swift UI 发起请求。
- 管理 request id、取消、过期响应。
- 把响应路由到 popup、panel、inline UI 或 editor decorations。
- 对编辑操作应用 text edits / workspace edits。
- 覆盖 UI 自动化和回归测试。

## 派生状态缺口

`editor-core::ProcessingEdit` 支持多类派生状态：

- style layers。
- folding regions。
- diagnostics。
- decorations。
- document symbols。

Swift UI 当前可以应用多种派生状态，尤其是 LSP diagnostics、semantic tokens、inlay hints、code lens、document links、document highlights、document symbols，以及 Tree-sitter/Sublime 产生的样式信息。

阶段 5 已补齐 Swift UI binding 的主要可观测 JSON API，阶段 39 已在其上补齐基础 typed snapshot API：

- `EditorUI.diagnosticsJSON()` 获取当前 diagnostics 列表。
- `EditorUI.decorationsJSON()` 获取当前 decoration layers。
- `EditorUI.documentSymbolsJSON()` 获取当前 document symbols。
- `EditorUI.foldingRegionsJSON()` 获取当前 fold regions。
- `EditorUI.styleIntervalsJSON(start:end:)` 获取当前 style layers 的样式区间。
- `EditorUI.diagnosticsSnapshot()` 获取 typed diagnostics snapshot。
- `EditorUI.decorationsSnapshot()` 获取 typed decoration layers snapshot。
- `EditorUI.documentSymbolsSnapshot()` 获取 typed document symbols snapshot。
- `EditorUI.foldingRegionsSnapshot()` 获取 typed folding regions snapshot。
- `EditorUI.styleIntervalsSnapshot(start:end:)` 获取 typed style intervals snapshot。
- `EditorUI.lspApplyDocumentSymbolsJSON(_:)` 可把 LSP document symbols result 写入 core outline。
- `EditorUI.lspApplyFoldingRangesJSON(_:)` 可把 LSP folding ranges result 写入 core fold regions。

剩余缺口已经从“Swift binding 拿不到”转为 App 层消费、模型化和统一控制：

- Swift UI binding 已有 diagnostics、decorations、symbols、fold regions、style intervals 的基础 typed snapshot model；LSP 交互结果、WorkspaceEdit、hierarchy/color/linked-editing 等更深层结果仍需继续 typed model 化。
- App 层已有 active-tab derived-state store，status bar、Problems quick panel、active-tab 持久 Problems panel、core-backed workspace Problems store/panel、active-tab minimap diagnostic markers、active-tab gutter diagnostic icons、core-backed workspace diagnostic marker snapshot 到 open-tab markers 的投影、基础持久 Outline/Symbols panel 和测试断言可以消费 diagnostics/decorations/symbols/folds/styles 的 typed snapshots；仍缺 workspace/active diagnostics 统一 derived-state model 和刷新/过期策略。
- App 层还没有统一的派生状态刷新策略、过期响应处理、增量更新通知和错误展示。

这会影响 Sublime 复刻中的这些功能：

- active-tab 持久 Problems panel、core-backed workspace Problems store/panel 和 core-backed workspace marker snapshot 已补齐；仍缺 workspace/active diagnostics 统一模型。
- Outline / symbol list 基础持久 panel 已补齐；仍缺 project/workspace 级 outline store 和 result lifecycle。
- Goto symbol。
- active-tab minimap diagnostic markers、gutter diagnostic icons 和 core-backed workspace diagnostics markers 到 open-tab markers 的投影已补齐；仍缺 workspace/active diagnostics 统一刷新和过期模型。
- Fold commands。
- 视觉回归测试中的“结构化断言”。

## 多文档、tab、workspace 和分屏缺口

本节结论：**多文档、tab、workspace、project/session 的长期状态归属必须落在 `editor-core` / `editor-core-ui` 一侧的 workspace 模型上**。Swift/AppKit 层不应再新建或扩展第二套长期独立的 workspace/tab/session ownership；现有 Swift tabs/splits 只能作为迁移垫片存在。这个约束适用于 tab 生命周期、preview/pin、dirty/close 语义、split layout、跨 tab 搜索、session restore、project/workspace LSP lifecycle 和未来多窗口归属。

当前仓库里存在多个相关入口，但长期 ownership 应只有一套：

- `editor-core` 有 headless `Workspace`。
- `EditorCoreFFI.Workspace` 暴露了一部分 headless workspace 能力。
- `editor-core-ui` 有 `MultiDocumentEditorUi`，包含 tab、preview tab、pin、close、split、search all tabs 等能力。
- `EditorCoreUIFFI.MultiDocumentEditorUI` 已暴露 `MultiDocumentEditorUi` 的基础 Swift-facing wrapper。
- Swift `EditorUI.cloneView` 可以创建共享 buffer 的额外 view。
- AttoEditor App 当前仍在 Swift 层维护 tabs；每个 tab 持有一个或多个 `EditCoreUI` pane，基础 split-right 通过 `EditorUI.cloneView` 共享同一 buffer。这是已落地的过渡实现，不应继续演进成第二套 workspace ownership。

主要缺口：

- `editor-core` / `editor-core-ui` 侧 workspace / multi-document 模型还没有成为 Swift 产品层的单一状态源；这是后续多文档/tab/workspace 工作的首要架构缺口。
- `MultiDocumentEditorUi` 已通过 UI FFI/Swift 暴露基础 tab/preview/pin/close/split/search-all-tabs API；AttoEditor 已开始把 tab/pane lifecycle、tab order、活动文本、保存/dirty 状态同步到 core mirror，Find in Files opened scope 已消费 core open-tab search，session restore 会恢复 split pane 数量和 active pane 到 core snapshot，关闭/覆盖/删除保护条件也已优先消费 core dirty snapshot。仍缺 project/LSP lifecycle 等更高层 workspace 契约，以及完整 AttoEditor 迁移。
- `EditorCoreFFI.Workspace` 已覆盖一批 view-local headless command typed wrapper，包括 type-char、snippet、auto-pairs、bracket matching/highlights 和 coalescing replace；但还缺 App 级 open/close/select/pin/split/session/project/LSP lifecycle 契约。
- AttoEditor 当前 Swift tab 系统已经有迁移期 core multi-document mirror，但 AppKit tabs 仍是主要 UI 数据结构；后续应继续迁移为 core workspace state 的投影，而不是在 Swift 侧继续维护独立模型或给 Swift-only tab state 继续加语义。
- 新增 tab/workspace 功能时，缺口不应通过给 Swift `Tab` / `EditorArea` 增加新的 ownership 字段来补；如果 core workspace 还没有对应语义，应先补 Rust 侧 command/query/event，再补 FFI 和 Swift wrapper。
- Swift 侧仍需要 UI state，但只能保存表现层状态，例如当前 responder、panel 展开状态、AppKit selection/focus glue、窗口几何和临时 drag/drop 交互；文档集合、tab 顺序、active tab、split tree、dirty state、preview/pin、关闭策略和跨文档搜索结果归属应来自 core workspace。
- App 层已有基础 split-right、focus next/previous pane、close pane、move pane left/right、move tab left/right，并能在 session restore 中恢复 split pane 数量和 active pane；还没有拖拽 tab 到 split 等完整 split pane 产品语义。
- `cloneView` 是底层能力；当前已接入基础 split layout、active pane focus tracking、pane move、tab move 和 core-backed close/dirty 保护，但还不等于完整 tab drag/drop、关闭语义和 project/session 归属。
- workspace/project 级 LSP 同步、全局搜索、recent files、session restore 与 tab 模型之间缺统一归属；这个归属应收敛到 `editor-core` 一侧的 workspace 模型。

架构决策：

- 当前明确不采用 Swift-owned workspace/tab/split/project/session 模型作为长期方案。
- 当前目标是 core-owned workspace：多文档、tab、split、project、session、跨 tab search、preview/pin/dirty/close semantics 使用 `editor-core` / `editor-core-ui` 侧 `Workspace` / `MultiDocumentEditorUi` 作为所有权来源。
- 如果 `editor-core` / `editor-core-ui` 的 workspace 模型缺少某个 Sublime 级语义，应优先补 Rust 侧模型和命令/query，再通过 FFI/Swift wrapper 暴露；不应先在 Swift 侧局部实现一套 parallel state。
- Swift/AppKit 侧后续不新增新的 tab/workspace ownership 类型；确需临时 UI 适配时，类型命名、注释和测试都应明确它只是 core workspace command/query/event 的缓存或投影，并且不能成为 dirty state、active tab、tab order、split tree、project/session restore 的事实来源。
- Swift 层职责是把 core workspace state 投影成 AppKit UI，处理菜单、keymap、command palette、quick panel、弹窗、拖拽和持久化入口；它不应再新建一套长期独立的 workspace/tab model。
- 已存在的 Swift tabs/splits 代码应被视为迁移垫片：可以继续承载当前可用产品行为，但新增 workspace/tab 级能力时应优先补 core workspace API、FFI 和 Swift wrapper，让 Swift 驱动 core workspace，而不是继续扩大 Swift-only 状态。
- 产品行为的验收标准应从“Swift UI 看起来能切 tab”调整为“同一行为能通过 core workspace command/query 表达、通过 FFI/Swift wrapper 观察，并且 AppKit UI 只是该状态的投影”。这能防止 Swift 与 Rust 两边各自维护 active tab、dirty state、split tree 或 session restore 的分叉状态。

迁移时需要避免长期混用两个 ownership 来源。建议顺序是：先在 `editor-core` / `editor-core-ui` 明确 workspace/tab/split/session 的 Rust 侧语义，再定义 `Workspace` / `MultiDocumentEditorUi` 的 Swift-facing command/query/event API，然后迁移 tab open/select/close、split pane、preview/pin/dirty state、session restore、project roots、workspace LSP lifecycle 和 search-all-tabs，最后删除或降级 Swift 侧自有 tab/session 状态。

## AttoEditor App 命令系统缺口

为了复刻 Sublime Text，App 层需要的不只是底层编辑 API，还需要稳定的命令系统。

当前 App 命令 palette 主要覆盖：

- New。
- Open。
- Save。
- Format。
- Find / Replace。
- Toggle Sidebar。
- Toggle Minimap。
- Command Palette。
- Go to File。
- Find in Files。
- Preferences。
- Jump Back / Forward。
- Matching Bracket。
- LSP location commands。
- LSP document/workspace symbols quick panels。
- LSP completion popup。
- LSP signature help popup。

主要缺口：

- command registry 已有基础命令启用/禁用状态、分组元数据、参数 schema、runtime feature requirement、宏录制策略和静态 editor-core JSON payload 元数据；keymap 已有基础 context 条件过滤、快捷键冲突解析、`args` 执行路由和多键序列 dispatcher。仍缺更完整的插件/宏运行时、命令上下文模型和完整 Sublime keymap 语义矩阵。
- command palette、主菜单和 keymap 已覆盖一批 Sublime 基础编辑命令；LSP location、symbols quick panels、completion popup、signature help、rename 和 code action 主路径已接入，但更深层 LSP/项目级命令仍不完整。
- P0 菜单、command palette、keymap 和测试已开始统一使用 command id；基础参数化命令可通过 typed arguments 执行，但更深层的命令上下文、插件/宏回放策略和 keymap 冲突解析仍缺。
- 一些 core/LSP 命令仍没有 App 命令入口。
- 用户 keymap 文件已有基础 Sublime JSON、context 条件过滤和快捷键冲突解析，但还不是完整 Sublime keymap 兼容实现。
- 没有 Sublime 风格 settings scopes。
- 没有宏录制/回放。
- 没有 build systems。
- 没有 package/plugin command 入口。
- 命令是否启用、是否可见、当前参数、错误展示没有统一模型。

建议 App 层先建立命令注册表：

- 每个命令有稳定 id，例如 `editor.duplicate_lines`、`editor.toggle_line_comment`、`lsp.rename`。
- 命令声明 title、默认 key binding、是否需要 editor focus、是否支持 selection、多光标语义。
- 菜单、command palette、keymap 和 UI 测试都调用同一命令入口。
- 底层实现可以调用 typed Swift API，也可以调用 UI JSON command dispatcher。

## Sublime 兼容缺口

当前仓库已经有 Sublime 相关 crate 和 Swift/App 集成，但“复刻 Sublime Text”需要更宽的产品面。这里的 Sublime 兼容范围明确不包含继续扩展 `.sublime-syntax` 语法定义兼容性：AttoEditor 的主路线是 Tree-sitter + LSP，`editor-core-sublime` 现有 syntax 支持只作为已有文件/主题生态的基线能力保留，不作为 P0/P1/P2 的新增功能目标。后续 Sublime 兼容审计应聚焦 settings、keymap、theme、package resource、command/panel 行为和编辑器交互语义，而不是补齐未公开规范的 syntax 细节。

语法/语言能力路线边界：

- `editor-core-sublime` 当前已经支持的 Sublime syntax 加载和解析能力视为既有基线；Swift 路径只需要确保这条基线能力可达、可配置、不会回退。
- 不新增 Sublime syntax 覆盖率目标，不建立 `.sublime-syntax` 兼容矩阵，也不把未公开规范的 syntax 细节纳入 Swift gaps 验收。
- AttoEditor 后续新增的语言语义、结构化高亮、符号、诊断、导航和智能编辑能力优先经由 Tree-sitter 与 LSP 产品化。

已具备或部分具备：

- Sublime syntax 相关解析/加载路径，仅作为现有 `editor-core-sublime` 基线保留。
- Sublime/JSON theme 相关路径。
- Tree-sitter 语法高亮路径。
- 基础 tab、sidebar、minimap、find/replace。
- 部分 command palette。

非目标：

- 扩展 `.sublime-syntax` 兼容覆盖率，或把 Sublime syntax 当作 AttoEditor 后续语义/高亮主路线。
- 为没有公开规范文档的 Sublime syntax 细节建立新的兼容矩阵；已有 `editor-core-sublime` 行为作为当前基线即可。
- 围绕 Sublime syntax 细节追加新的 P0/P1/P2 缺口项；除非是现有 `editor-core-sublime` 基线能力在 Swift 路径上不可达，否则不作为本审计的待办。

仍需审计或补齐：

- `.sublime-color-scheme` 兼容覆盖率。
- `.tmTheme` 兼容覆盖率。
- Sublime settings scope 继承规则。
- keymap 文件已有基础 JSON 解析、`context` 条件过滤、快捷键冲突解析、`args` 执行路由、基础多键序列 dispatcher、prefix 状态栏提示、prefix 超时和 Escape 取消；键名兼容已覆盖常见 modifier、arrow/function key、命名标点、字面 `+`、forward delete / insert / begin / clear / help，context operator 已覆盖 `equal` / `not_equal` / `regex_match` / `not_regex_match` / `regex_contains` / `not_regex_contains` 和 `match_all` 多值上下文语义。App key-down dispatcher 已能注入 active editor、selection、selector、syntax、file name/extension、dirty、tab/pane 等基础动态 context 并按当前 context 触发单键 binding/chord/args。仍缺更完整 Sublime 命令上下文模型和更完整跨平台键名兼容矩阵。
- snippets。
- macros。
- build systems。
- projects/workspaces；产品层应消费 core-owned workspace，不应在 Swift 侧另建长期 workspace/project 模型。
- Goto Anything 语义。
- Goto Symbol / Goto Definition / Goto Reference 的 UI 行为。
- quick panel / input panel / output panel。
- multi-select 细节行为。
- command palette 命令全集。
- package discovery / package resource loading。
- status bar items。
- sidebar file operations。
- tab preview/pin/dirty state/close behavior 与 Sublime 一致性。

这些大多是产品兼容缺口，不一定要求 Rust core 改动，但需要 Swift App、FFI 和 core 能力共同支撑。

## 渲染与视觉测试缺口

现有 Swift 测试更偏组件级功能测试。对于复刻 Sublime，需要增加视觉和布局测试。

当前可做：

- AppKit view 实例化测试。
- 通过 `NSWindow` 包装 view。
- 发送 `NSEvent` 模拟键鼠。
- 调用 `renderRGBA` 或 view snapshot 获取像素输出。
- 对文本、选择、滚动、搜索等状态做结构化断言。

仍缺：

- Golden image 视觉回归测试。
- 固定字体、DPI、颜色空间、窗口尺寸、主题和内容 fixtures。
- layout invariants 测试，例如 gutter 宽度、line height、minimap 宽度、tab bar 高度、status bar 高度。
- Sublime 对照截图的区域级 diff。
- caret、selection、find highlight、diagnostic underline、inlay hint、fold marker 的像素级覆盖。
- 多窗口/分屏视觉回归。
- 黑盒 `XCUIApplication` 测试 target。
- 基础 menu item / AppKit view identifiers 已有；仍缺把这些 identifiers 接到黑盒 `XCUIApplication` smoke test 和视觉布局测试矩阵中。
- CI 上可重复的 macOS UI test 环境。

推荐测试分层：

- 结构化测试：断言 selection、viewport、line metrics、hit-test、command result。
- 渲染快照测试：固定 fixtures，比较 RGBA 或 PNG golden。
- AppKit 操作测试：用 `NSWindow` + `NSEvent` 覆盖快捷键、鼠标、IME、滚动。
- 黑盒 smoke test：启动 AttoEditor app，走菜单、command palette、打开保存文件。

## ABI 与 Swift API 设计缺口

当前 ABI/Swift API 的主要问题不是不能继续加函数，而是缺少统一扩展机制。

主要缺口：

- `editor-core-ffi` 和 `editor-core-ui-ffi` 命令覆盖面不一致。
- headless Swift 和 Swift UI 都已有 JSON command escape hatch，但两者覆盖面仍不完全一致。
- Swift `EditorUI` typed API 覆盖主路径，但不是完整 command API。
- LSP interactive request 已覆盖一批 raw JSON result API；LSP status/capabilities 已有 typed snapshot，但 request 返回值和事件仍缺统一 envelope。
- 长任务、异步请求、取消、错误、诊断日志没有统一 Swift 事件流。
- 配置 DTO 不完整，例如 wrap、indentation、comment、auto-pairs、word boundary、search options。
- headless Swift FFI 已有 ABI version；阶段 69 已补齐 UI FFI 的 ABI version / feature flags C ABI 和 Swift `runtimeInfo()` typed facade，阶段 80 已新增 multi-document UI feature flag，阶段 81 已把该 feature 纳入 AttoEditor 启动期必需能力；阶段 70 已补 AttoEditor 启动期最低 ABI/必需 feature compatibility gate，阶段 105 已补基础逐命令可选 feature 降级。后续仍缺更细粒度的逐面板降级策略和面向第三方 host 的 ABI capability negotiation。

建议演进方向：

- 继续使用 `editor_core_ui_ffi_editor_ui_execute_command_json(editor, command_json)` 作为 UI escape hatch。
- Swift `EditorUI.executeCommandJSON(_:)` 作为低频/迁移命令入口。
- 已有高频命令 typed convenience API；新增或低频命令按产品化需要继续补 typed API。
- FFI 返回统一 `{ ok, value, error, version }` 风格。
- Swift 层封装稳定 enum/struct，但保留 unknown command 的转发能力。
- LSP raw result API 后续应收敛到 typed model / result panel model，而不是让 App 层到处解析临时 JSON。
- App 命令系统只依赖 Swift command abstraction，不直接散落调用 FFI 函数。

## 优先级建议

### P0：先补命令通道和 Sublime 基础编辑命令

- 已完成：给 Swift UI 增加通用 command JSON dispatcher。
- 已完成：通过 `executeCommandJSON(_:)` 暴露 duplicate/delete/move lines、join/split line、toggle comment、fold/unfold、wrap mode、wrap indent、indentation config。
- 已完成：通过 `executeCommandJSON(_:)` 暴露 general `applyTextEdits`。
- 已完成：通过 `executeCommandJSON(_:)` 暴露 `applySnippet` 和 snippet placeholder navigation。
- 已完成：AttoEditor 为 snippet placeholder navigation 建立显式 command id，并接入 command palette 和 Edit 菜单。
- 已完成：AttoEditor 为 add next/all occurrence 建立显式 command id，并接入 command palette、Edit 菜单和默认 keymap。
- 已完成：AttoEditor 为 select word/line、expand selection、add cursor above/below 建立显式 command id，并接入 command palette 和 Edit 菜单。
- 已完成：AttoEditor preferences 已接入 auto-pairs enabled 开关，并应用到新建和已打开 editor。
- 已完成：AttoEditor preferences 已接入 wrap mode 开关，并应用到新建和已打开 editor。
- 已完成：AttoEditor preferences 已接入 wrap indent 设置，并应用到新建和已打开 editor。
- 已完成：AttoEditor 会按语言/扩展名应用基础 indentation config。
- 已完成：AttoEditor 会按语言/扩展名向 toggle comment 传完整 line/block comment config。
- 已完成：AttoEditor command registry 已接入基础 group/requiresEditor/isEnabled 元数据，菜单、palette 和 `executeCommand(id:)` 共用同一启用状态。
- 已完成：AttoEditor command registry 已接入基础参数 schema、宏录制策略、静态 editor-core JSON payload 元数据和 `executeCommand(id:arguments:)` typed arguments 路径；默认命令集已有重复 command id 检测测试。
- 已完成：AttoEditor command registry 已接入 runtime feature requirement，LSP/WorkspaceEdit 可选 feature 缺失时会按命令禁用相关菜单、palette 项和 `executeCommand` 路径，而基础编辑命令保持可用。
- 已完成：AttoEditor keymap 已支持 arrow/navigation function-key token，move lines up/down 已有默认 arrow-key 绑定。
- 已完成：AttoEditor keymap 已支持基础 `context` 条件过滤和快捷键冲突解析，`resolvedKeymap(...)` 可暴露 conflicts 供测试和后续 UI/诊断使用。
- 已完成：AttoEditor keymap 已支持用户条目 `args` 解码，并能通过菜单/shortcut command 路径调用 `executeCommand(id:arguments:)` 执行参数化命令。
- 已完成：AttoEditor keymap 已支持基础多键序列解析和 App 层 dispatcher，多键序列命中后复用统一 command id 和 typed arguments 执行路径。
- 已完成：AttoEditor keymap chord prefix 已支持超时清理和 Escape 取消，避免未完成 chord 长期拦截后续按键。
- 已完成：AttoEditor keymap chord prefix 已有状态栏可见提示，并会在命中、失败、超时或 Escape 后恢复状态栏左侧原摘要。
- 已完成：AttoEditor keymap 已补一批 Sublime 风格键名 token、字面 `+` 和 regex contains/full-match context operator 语义。
- 已完成：AttoEditor keymap context resolver 已支持 `match_all` 多值上下文语义。
- 已完成：AttoEditor App key-down dispatcher 已按 active editor 状态动态注入 keymap context，并能用当前 context 触发单键 binding、chord 和 keymap args。
- 已完成：AttoEditor command palette 已用 `cursor.*` 覆盖 grapheme/word、visual row/page、visual line/document start/end 及对应 modify-selection 视觉移动命令矩阵。
- 已完成：AttoEditor 主菜单已有独立 Selection 菜单分组，常用 selection/multicursor 命令复用统一 command id。
- 已完成：Swift UI binding 已为 derived-state snapshots 提供基础 typed model。
- 已完成：AttoEditor 已有 active-tab derived-state store，status bar 可显示 Problems 数量，测试可直接断言 active derived-state snapshot。
- 已完成：AttoEditor 已有 Problems quick panel 和 active-tab 持久 Problems panel，消费 active derived-state store 的 typed diagnostics 并支持跳转。
- 已完成：AttoEditor command palette 为一批 Sublime 基础编辑命令建立稳定 command id。
- 已完成：为高频命令补 typed Swift convenience API。
- 已完成：把 App command id 统一接入主菜单和初步用户可配置 keymap。
- 为这些命令补 AppKit 操作测试和结构化状态测试。

### P1：补 LSP 产品主路径

- completion commit-time resolve、rich documentation/detail preview、commitCharacters 提交行为、server triggerCharacters 自动触发、本地增量过滤、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用和打开 tab / 本地未打开文件 resource operations 已完成；仍缺 core workspace-owned 跨文件事务和更完整 typed result model。
- signature help server trigger/retrigger characters 自动触发、active parameter 富格式高亮、typed result model 和手动请求空/错反馈已完成。
- references/implementation/declaration/type definition 多结果 quick panel 已统一，展示 item model、稳定排序、最近结果 snapshot、reopen command、bounded in-memory history command、基础持久在线 Locations/References panel 和 typed lifecycle entry/envelope 元数据；仍缺覆盖所有 result family 的 lifecycle/event model、项目级归属和更完整刷新/过期策略。
- rename prepareRename range/placeholder、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用和打开 tab / 本地未打开文件 resource operations 已产品化；仍缺 core workspace-owned 跨文件事务和 typed result model。
- code action typed diagnostics context、kind/filter、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations 和 command payload 执行结果/错误展示已完成；仍缺 core workspace-owned 跨文件事务和 typed result model。
- document/workspace symbols 基础错误/超时/空结果反馈、最近结果 snapshot、reopen command、bounded in-memory history command、workspace symbols 增量查询面板、kind 分组/稳定排序、基础持久 Outline/Symbols panel、通用 lifecycle store 起点和 typed lifecycle entry/envelope 元数据已完成；仍缺覆盖所有 result family 的更深 result lifecycle/event model。
- range formatting Swift/App 主路径已完成；on-type formatting binding、换行触发、server trigger characters 自动触发路径、显式 Swift/App 错误展示和 formatting typed outcome 已完成；自动 on-type 异步 response error 已进入 LSP status/detail，并有 status refresh + 去重 HUD；Swift 已有 typed `lspStatusSnapshot()`，AttoEditor 的 LSP status/capabilities 行为路径也已迁到 typed snapshot。后续仍缺更通用的 LSP event stream、request lifecycle 和状态变更订阅模型。
- folding ranges request/take/apply 到 fold state、App refresh 命令、typed capability gate、错误反馈、typed fold snapshot、status bar 折叠摘要和 renderer 层 gutter fold marker 视觉回归 baseline 已完成；仍缺更完整的 result lifecycle model。
- code lens refresh/resolve、selection range、linked editing、diagnostics pull、document color/color presentation、call hierarchy、type hierarchy 的 raw request/take binding 已完成；code lens 已有手动刷新入口、HUD 反馈、active actions quick panel、当前行键盘定位命令、inline Cmd-click 执行路径、typed parser、自动辅助刷新消费和状态栏数量反馈，selection range 已有 App expand-selection 命令、typed candidate model 和多光标策略，linked editing 已有 App multi-cursor selection 主路径、wordPattern/shared-text 校验和轻量 session lifecycle，document color/color presentation 已有 App quick panel、直接 color picker 和 edit apply 主路径，call/type hierarchy 已有基础 quick panel 导航和 typed parser，diagnostics 已有 active-tab Problems quick panel、active-tab 持久 Problems panel、workspace diagnostics quick panel、core-backed workspace Problems store/panel 和 core-backed marker snapshot；仍缺 workspace/active diagnostics 统一 derived-state model。
- LSP result panels 和错误展示。

### P1：统一多文档和分屏架构

- 明确采用 core-owned workspace：`editor-core` / `editor-core-ui` 的 `Workspace` / `MultiDocumentEditorUi` 是多文档、tab、split、project/session 的状态来源。
- `MultiDocumentEditorUi` 基础 FFI/Swift 投影已完成，覆盖 open/select/close/pin/preview/split/view move/tab move/search-all-tabs、tab 文本同步、dirty/saved snapshot、workspace diagnostics store 和 workspace diagnostic marker snapshot；AttoEditor tab/pane lifecycle、tab order、编辑文本、workspace Problems snapshot 和 workspace markers 已开始同步到 core mirror，Find in Files opened scope 已改为 core open-tab search，split pane session restore、pane move、tab move 和 dirty/close/resource-operation 保护条件已同步到 core snapshot；仍缺 project/LSP lifecycle、workspace/active diagnostics 统一 derived-state model 等更高层 workspace API。
- 将 AttoEditor 现有 Swift tabs/splits 迁移为 core workspace state 的 AppKit 投影，而不是继续维护独立 workspace/tab/session model；新增字段时要区分“UI 表现缓存”和“文档/workspace 所有权状态”。
- 继续产品化 split panes：pane move 已按 core `MultiDocumentEditorUi` view reorder 语义接入；拖拽 tab 到 split 等仍缺。新增命令和状态归属必须先落在 core workspace 模型，然后通过 FFI/Swift wrapper 驱动 AppKit 表现。
- 继续收敛 session restore、preview tab、pin tab、dirty state、close semantics；dirty/close 保护条件和 tab movement 已经 core-backed，剩余重点是把更高层关闭命令、tab drag/drop 和 project/session 归属完全转为 core workspace command/query。
- 明确 project/workspace 与 LSP server lifecycle 由 core workspace 模型协调，Swift 只负责启动参数、UI 触发和展示。
- 建立迁移期测试：同一 tab/split/workspace 操作同时断言 core workspace snapshot、Swift wrapper query 和 AppKit 投影，避免两边状态漂移。

### P2：深化 Sublime 兼容

- settings scopes。
- 完整 Sublime keymap 文件兼容。
- snippets/macros/build systems。
- package resource loading。
- command palette 覆盖。
- quick panels/input panels/output panels。
- Sublime theme 兼容矩阵；syntax 部分不扩展，维持现有 `editor-core-sublime` 基线，新增语言能力优先走 Tree-sitter 和 LSP。

### P2：视觉回归和黑盒自动化

- 已完成：主菜单、核心 editor chrome、tab bar、find/replace、status bar、sidebar、quick panel 和 completion popup 已有基础稳定 AppKit identifiers，并有组件测试覆盖。
- 建立 golden screenshot 测试工具。
- 引入 fixtures，覆盖主题、字体、Unicode、多光标、折叠、diagnostics、minimap。
- 补 `XCUIApplication` smoke tests。
- 在 CI 上固定 macOS runner、字体、scale factor 和渲染后端。

## 建议的功能矩阵

建议新增一份机器可读或半机器可读矩阵，作为后续工作入口：

| Feature | Core | core FFI | UI Rust | UI FFI | Swift `EditorUI` | Atto command | Tests |
| --- | --- | --- | --- | --- | --- | --- | --- |
| duplicate line | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, command palette/menu/keymap | yes |
| toggle comment | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, command palette/menu/keymap + language comment settings override | yes |
| apply snippet | yes | yes, via JSON | yes | yes, via JSON | yes, typed + JSON | yes, generic apply-snippet command + completion apply + Tab/Backtab placeholder path + explicit placeholder commands | yes |
| add occurrence | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, command palette/menu/keymap + Find bar search options | yes |
| selection/multicursor | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, common commands in command palette/menu; select line has default keymap | yes |
| visual cursor movement | yes | yes | yes | yes, typed + JSON subset | yes, typed grapheme/word/row/page/line/doc + modify-selection | yes, `cursor.*` command palette matrix; default keyboard path remains AppKit text dispatch | yes |
| LSP completion | yes | partial helper | yes | yes, raw completion + resolve result | yes, raw completion + resolve result | yes, popup + auto trigger + incremental filter + commit-time resolve/current-doc/cross-file text edits apply | partial |
| LSP symbols | yes | partial helper | yes | yes, raw JSON result + typed document symbols snapshot | yes, raw JSON result + typed document symbols snapshot | yes, document symbols quick panel consumes typed snapshot; workspace symbols have incremental query panel + stable grouped sorting; last-result reopen + in-memory history commands exist | yes |
| LSP rename | yes | partial helper | partial | partial, raw request + current-doc WorkspaceEdit apply | partial, raw result + current-doc WorkspaceEdit apply | yes, prepareRename seed + input UI + menu/keymap + current-doc/cross-file text edits apply + opened/unopened local resource operations | partial |
| LSP code action | yes | partial helper | partial | partial, raw request/resolve + current-doc WorkspaceEdit apply + executeCommand result envelope | partial, raw result + typed diagnostics context + kind filters + current-doc WorkspaceEdit apply + executeCommand result envelope | yes, quick panel/menu/keymap/typed diagnostics context/kind-filter commands/current-doc/cross-file text edits apply + opened/unopened local resource operations + command result/error HUD | partial |
| LSP formatting | yes | partial helper | yes, document/range/on-type blocking apply + trigger-character auto path | yes, document/range/on-type blocking apply | yes, typed document/range/on-type helpers + formatting outcome | document + selection commands with no-edits/error HUD; on-type trigger-character auto path | partial |
| LSP folding ranges | yes | partial helper | yes, request/take + apply to fold regions | yes, raw request/take + apply JSON | yes, raw request/take + apply JSON | partial, refresh command applies ranges and fold commands use current state | yes |
| LSP advanced raw requests | yes | partial helper | yes, code lens refresh/resolve + selection/linked editing/diagnostics/color/hierarchy raw request/take + workspace diagnostics store/marker snapshot in `MultiDocumentEditorUi` | yes, raw request/take JSON + code lens view-point hit-test + multi-document workspace diagnostics snapshot/previousResultIds/marker ABI | yes, raw request/take JSON + code lens hit-test wrapper + `MultiDocumentEditorUI` workspace diagnostics snapshot/previousResultIds/marker wrapper | partial, code lens refresh/actions/current-line command/inline Cmd-click/status count + selection range multi-cursor expansion + linked editing wordPattern/session validation + document colors with direct picker/call hierarchy/type hierarchy/workspace diagnostics have App commands and quick panels; workspace Problems store/panel and workspace markers consume core-backed snapshots, while workspace/active diagnostics unified lifecycle remains missing | partial |
| split view | partial | no | yes | yes, clone view + move view | yes, clone view + AppKit split pane + move pane | yes, split/focus/move/close pane commands | yes |
| workspace tabs/splits | yes, headless `Workspace` | partial `Workspace` wrapper with view-local command conveniences | yes, `MultiDocumentEditorUi` | yes, `MultiDocumentEditorUi` ABI + close-view + move-view + move-tab + text/dirty sync | partial `MultiDocumentEditorUI` wrapper; Atto tab/pane lifecycle, tab move, pane move and edited text mirror core snapshot/search, but session/project/LSP ownership is still transitional | partial, transitional AppKit projection; new tab/workspace semantics must move to core-owned workspace first | partial |

这类矩阵应该作为 PR checklist 使用：新增 core 能力时，明确是否需要同步 FFI、Swift wrapper、App command 和测试。

## 相关源码入口

快速定位建议从这些文件开始：

- `docs/DESIGN.md`：headless core 设计目标、坐标/offset 约定、derived state 模型。
- `docs/abi-v1-draft.md`：ABI v1 设计方向。
- `crates/editor-core/src/model.rs`：`EditCommand`、`CursorCommand`、`ViewCommand`、`StyleCommand`。
- `crates/editor-core/src/processing.rs`：`ProcessingEdit` 派生状态。
- `crates/editor-core-ffi/src/lib.rs`：headless JSON command FFI。
- `crates/editor-core-ui/src/lib.rs`：Rust UI wrapper 主实现。
- `crates/editor-core-ui/src/multi_document.rs`：Rust UI 多文档模型。
- `crates/editor-core-lsp/src/editor.rs`：LSP 能力面。
- `swift/Sources/EditorCoreFFI/EditorState.swift`：headless Swift wrapper。
- `swift/Sources/EditorCoreFFI/Workspace.swift`：headless workspace Swift wrapper。
- `swift/Sources/EditorCoreFFI/LSPBridge.swift`：LSP DTO/JSON 转换 helper。
- `swift/Sources/EditorCoreUIFFI/EditorUI.swift`：Swift UI wrapper。
- `swift/Sources/EditorCoreUI/`：AppKit editor view 层。
- `swift/Sources/AttoEditor/AttoEditorAreaViewController.swift`：AttoEditor tab/editor area。
- `swift/Sources/AttoEditor/AttoAppDelegate.swift`：菜单、命令 palette 和 App lifecycle。
