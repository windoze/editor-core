# Swift 绑定与 UI 集成缺口审计

审计日期：2026-08-01

本文记录当前 Swift 侧、FFI 层、`editor-core-ui` 适配层以及 AttoEditor App 层相对 `editor-core-*` 能力的功能缺口。这里的 “Swift UI” 指仓库中的 Swift/AppKit/Skia/Metal 集成，不是 Apple SwiftUI 框架。

本文关注的是“能否从 Swift 产品层完整使用 `editor-core-*` 能力”，不是评价 Rust core 自身是否完整。总体结论是：**当前 Swift 路径已经能支撑一个可用编辑器主流程，但还不是 `editor-core-*` 的完整能力投影**。尤其对于“复刻 Sublime Text”这个目标，缺口主要集中在命令面、LSP 产品化、派生状态产品化/消费、多文档/分屏归属、Sublime 兼容行为和视觉/交互测试体系。其中多文档、tab、workspace、project/session 的状态归属已经明确：后续应收敛到 `editor-core` / `editor-core-ui` 的 workspace 模型，Swift/AppKit 侧不再新开或扩展一套长期独立的 workspace/tab/session 模型。

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

本文不把所有未实现的 Sublime 产品功能都算作 Rust core 缺口；很多属于 App 层、命令系统、设置系统或插件/包生态缺口。

## 当前可用基线

Swift 侧已经具备以下基础能力：

- SwiftPM 包可构建，包含 `AttoEditor` executable。
- 当前 App 是 AppKit + Skia/Metal 自绘架构，不是 SwiftUI view tree。
- `EditorCoreFFI.EditorState` 和 `EditorCoreFFI.Workspace` 暴露了 headless core 的一部分 JSON command 能力。
- `EditorCoreUIFFI.EditorUI` 暴露了较完整的“编辑器视图主路径”API，包括打开文本、插入/删除、搜索替换、撤销重做、选择、鼠标输入、IME、渲染 RGBA/Metal、主题、Tree-sitter、Sublime syntax、部分 LSP、minimap、gutter、bookmark、jump history、document link hit-test 等。
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
- 阶段 5 尚未完成 App 层统一 derived-state store、Problems/Outline 面板、minimap markers、gutter diagnostic icons、状态栏消费和更高层 Swift typed model。
- 2026-08-01 阶段 6 第一部分已完成：Swift UI binding 新增一组 LSP interactive request/take raw result API，覆盖 declaration、type definition、implementation、references、completion、signature help、document symbols、workspace symbols。
- 阶段 6 第一部分在 Rust UI 内部把 hover/definition 的专用 result cache 泛化为按 LSP result slot 管理；document symbols response 会同步写入 core outline，供 `documentSymbolsJSON()` 读取。
- 2026-08-01 阶段 6 第二部分已完成：AttoEditor command palette 和 Go 菜单新增 LSP location commands，覆盖 go to definition/declaration/type definition/implementation/find references；cmd-click definition 也复用同一套 location request/poll/navigate 路径。
- 阶段 6 第二部分已让 references 多结果进入一个轻量可过滤结果 palette，单结果直接跳转；`AttoLspDefinitionParser` 新增多目标解析并补测试。
- 阶段 6 尚未完成完整 references/locations panel、LSP typed result model 和更深层项目级命令模型。
- 2026-08-01 阶段 7 第一部分已完成：AttoEditor 新增基础 `view.split_right` 命令，通过 `EditorUI.cloneView` 为当前 tab 创建共享 buffer 的第二个 AppKit pane；这部分是当前可用的过渡实现，不应继续扩展成 Swift 自有 workspace/tab 模型。
- 2026-08-01 阶段 7 架构决策已更新：多文档、tab、workspace、project/session 级状态应使用 `editor-core` / `editor-core-ui` 一侧的 `Workspace` / `MultiDocumentEditorUi` 模型作为单一所有权来源，Swift 侧只做 AppKit 表现、命令转发、用户交互和持久化桥接；后续不在 Swift/AppKit 层新开一套长期独立的 workspace/tab/session 模型，也不继续给 Swift-only tab state 增加 preview/pin/dirty/close/search-all-tabs 等长期语义。
- 阶段 7 第一部分已让 split pane 复用主编辑器 chrome/theme/preferences/LSP/hover/cmd-click hook，并新增 first-responder hook 跟踪 active pane；AttoEditor command palette、View 菜单和默认 keymap 已接入。
- 阶段 7 第二部分已完成基础 pane 操作命令：`view.focus_next_pane`、`view.focus_previous_pane`、`view.close_pane`，并用 AppKit 组件测试覆盖 active pane 对 close target 的影响。
- 阶段 7 尚未完成 `MultiDocumentEditorUi` 的 Swift FFI 投影、AttoEditor 现有 Swift tabs/splits/session/search-all-tabs 向 core workspace 模型迁移、pane move、分屏布局 session restore、拖拽 tab 到 split、preview/pin/dirty/close semantics 统一。
- 2026-08-01 阶段 8 已完成：AttoEditor 新增 LSP document/workspace symbols quick panel 主路径，命令 `lsp.document_symbols` / `lsp.workspace_symbols` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspSymbolParser`，覆盖 DocumentSymbol、SymbolInformation、WorkspaceSymbol 常见结果形态。
- 阶段 8 尚未完成 symbols 的持久面板、workspace symbol 增量查询/输入面板、结果分组/排序策略和错误展示。
- 2026-08-01 阶段 9 已完成：AttoEditor 新增 LSP signature help popup 主路径，命令 `lsp.signature_help` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspSignatureHelpFormatter`，覆盖 SignatureHelp、activeSignature、activeParameter、ParameterInformation string/range label 和 documentation 常见结果形态。
- 阶段 9 后续缺口中，trigger characters / 自动弹出已在阶段 18 补齐，active parameter 富格式高亮已在阶段 19 补齐，typed result model 和空结果/错误展示已在阶段 20 补齐。
- 2026-08-01 阶段 10 已完成：AttoEditor 新增 LSP completion popup 主路径，命令 `lsp.completion` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspCompletionParser` 和 caret-anchored completion list，覆盖 CompletionList/CompletionItem、TextEdit、InsertReplaceEdit insert range、additionalTextEdits、snippet insertion 和 fallback identifier-prefix replacement。
- 阶段 10 后续缺口中，rich documentation/detail preview 已在阶段 21 补齐，commitCharacters 提交行为已在阶段 22 补齐，server triggerCharacters 自动触发已在阶段 23 补齐，增量过滤已在阶段 24 补齐，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐；仍缺跨文件 workspace edit 真正应用和更完整的 typed result model。
- 2026-08-01 阶段 11 已完成：Swift UI binding 新增 rename / prepare rename / code action / code action resolve 的 raw async request/take API，覆盖 Rust `editor-core-lsp` 已有的 `textDocument/prepareRename`、`textDocument/rename`、`textDocument/codeAction` 和 `codeAction/resolve` 请求路径。
- 2026-08-01 阶段 11 第二部分已完成：Swift UI binding 新增 `lspApplyWorkspaceEditJSON(_:documentURI:)`，通过 UI FFI 把 `WorkspaceEdit` 中命中当前文档 URI 的 `TextEdit` 应用到当前 buffer，并返回 applied/skipped/documents summary，覆盖 rename/code action 返回 edit 后的当前文档应用基础链路。
- 2026-08-01 阶段 11 第三部分已完成：AttoEditor App 新增 `lsp.rename` 主路径，包含 command palette、Go 菜单、F2 keymap、rename 输入框、候选名预填、LSP rename request/poll，以及把返回的当前文档 WorkspaceEdit 应用到 active tab 并标记 dirty。
- 2026-08-01 阶段 11 第四部分已完成：Swift UI binding 新增 `workspace/executeCommand` raw request/take API；AttoEditor App 新增 `lsp.code_actions` 主路径，包含 command palette、Go 菜单、Cmd+. keymap、code action quick panel、`codeAction/resolve` 轮询、当前文档 WorkspaceEdit 应用和 command payload 执行。
- 阶段 11 后续缺口中，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，code action diagnostics context 已在阶段 26 补齐，code action kind/filter 产品化已在阶段 27 补齐；仍缺跨文件 WorkspaceEdit 真正应用、执行结果/错误展示，以及相关 typed result model。
- 2026-08-01 阶段 12 已完成：Swift UI binding 新增 `completionItem/resolve` raw request/take API；AttoEditor completion popup 在 commit 时会先请求 resolve，使用 resolved CompletionItem 中的 `textEdit` / `additionalTextEdits` / snippet payload，resolve 不可用或超时时回退到原始 completion item。
- 阶段 12 后续缺口中，rich documentation/detail preview 已在阶段 21 补齐，commitCharacters 提交行为已在阶段 22 补齐，server triggerCharacters 自动触发已在阶段 23 补齐，增量过滤已在阶段 24 补齐，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐；仍缺跨文件 workspace edit 真正应用和更完整的 typed result model。
- 2026-08-01 阶段 13 已完成：Swift UI binding 新增 LSP range/on-type formatting 的阻塞 turnkey API，覆盖 Rust `editor-core-lsp` 已有的 `textDocument/rangeFormatting` 和 `textDocument/onTypeFormatting` 请求路径，并复用 `editor-core-ui` 的 LSP `TextEdit` 应用逻辑。
- 阶段 13 已新增 `EditorUi.lsp_format_range(...)` / `lsp_format_on_type(...)`、C ABI `editor_core_ui_ffi_editor_ui_lsp_format_range` / `editor_core_ui_ffi_editor_ui_lsp_format_on_type`、Swift `EditorUI.lspFormatRange(...)` / `lspFormatOnType(...)`，以及 `EditorCoreSkiaView.formatRangeWithLSP(...)` / `formatOnTypeWithLSP(...)`。
- 阶段 13 已让 AttoEditor App 新增 `editor.format_selection` 主路径，接入 command palette、Edit 菜单和默认 keymap；选区为空时不向 LSP 发 range formatting 请求。
- 阶段 13 尚未完成 on-type formatting 的完整产品触发策略（除 Rust UI 已有的换行触发路径外，还缺按 server trigger characters 自动触发）、格式化错误展示、跨文件 WorkspaceEdit 产品化和 typed result model。
- 2026-08-01 阶段 14 已完成：Rust UI `insert_text` 单字符 typing 路径会按 LSP server `documentOnTypeFormattingProvider` 宣告的 `firstTriggerCharacter` / `moreTriggerCharacter` 自动触发 `textDocument/onTypeFormatting`；粘贴和多字符 IME commit 仍保持批量插入语义，不触发 on-type formatting。
- 阶段 14 已用 fake LSP server 单测覆盖：单字符 paste 不触发、非 trigger typing 不触发、server trigger typing 会发送 `textDocument/onTypeFormatting` 并携带正确 `ch`。
- 阶段 14 尚未完成格式化错误展示、跨文件 WorkspaceEdit 产品化和 formatting typed result model。
- 2026-08-01 阶段 15 已完成：Swift UI binding 新增 LSP folding ranges request/take/apply 通道，覆盖 Rust `editor-core-lsp` 已有的 `textDocument/foldingRange` 请求路径和 `ProcessingEdit::ReplaceFoldingRegions` 应用路径。
- 阶段 15 已新增 `EditorUi.lsp_request_folding_ranges()` / `lsp_apply_folding_ranges_json(...)`、C ABI `editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges` / `editor_core_ui_ffi_editor_ui_lsp_take_last_folding_ranges_json` / `editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json`、Swift `EditorUI.lspRequestFoldingRanges()` / `lspTakeLastFoldingRangesResultJSON()` / `lspApplyFoldingRangesJSON(_:)`。
- 阶段 15 已让手动 `textDocument/foldingRange` result 可以写入 core fold regions，并通过 `foldingRegionsJSON()` 被 Swift 读取；仍缺 App 层 folding refresh/error UI 和 fold region typed model。
- 2026-08-01 阶段 16 已完成：Swift UI binding 新增高级 LSP raw request/take 覆盖，打通 Rust `editor-core-lsp` 已有的 code lens resolve、selection range、linked editing range、pull diagnostics、document color/color presentation、call hierarchy 和 type hierarchy 请求路径。
- 阶段 16 已新增 `EditorUi`、C ABI 和 Swift `EditorUI` 对应 API；这些能力目前仍停留在 raw JSON result 层，App 层 panel/popup/inline UI、typed model、错误展示和 cross-file/workspace 结果产品化仍未完成。
- 2026-08-01 阶段 17 已完成：AttoEditor App 的 `lsp.rename` 弹窗接入 `textDocument/prepareRename`，会优先使用 server 返回的 `placeholder` 或 `range` 文本作为默认 rename 名称；支持 LSP `Range`、`{ range, placeholder }` 和 `{ defaultBehavior: true }` 返回形态。
- 阶段 17 已新增 `AttoLspRenameSupport.DialogSeed` / `dialogSeed(...)`，按 LSP UTF-16 line/character range 从当前文档提取 rename 文本，并在 prepareRename 无响应或不可解析时回退到当前选区/identifier 逻辑；跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，仍缺跨文件 WorkspaceEdit 真正应用和 rename typed result model。
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
- 2026-08-01 阶段 26 已完成：AttoEditor code action 请求不再固定发送空 `diagnostics` context；新增 `AttoLspCodeActionContext`，从 Swift UI `diagnosticsJSON()` 读取当前 buffer diagnostics，按 code action selection/caret range 过滤，把 core char-offset range 转成 LSP UTF-16 `Diagnostic.range`，并保留 severity/code/source/message/relatedInformation/data 后发送给 `textDocument/codeAction`。
- 2026-08-01 阶段 27 已完成：AttoEditor code action 主路径新增 kind/filter 产品化入口；`lsp.quick_fix`、`lsp.refactor`、`lsp.source_actions`、`lsp.organize_imports`、`lsp.fix_all` 已接入 command palette 和 Go 菜单，请求时发送 LSP `CodeActionContext.only`，响应后再按 `kind` 精确或前缀匹配做客户端过滤。
- 2026-08-01 阶段 28 已完成：AttoEditor 为 snippet placeholder navigation 新增显式 App command id：`editor.snippet_next_placeholder` / `editor.snippet_prev_placeholder`，通过现有 UI JSON command dispatcher 调用 `snippet_next_placeholder` / `snippet_prev_placeholder`，并接入 command palette、Edit 菜单和命令注册测试；Tab/Backtab 仍保留为文本系统主路径。
- 2026-08-01 阶段 29 已完成：AttoEditor 为多光标 occurrence 操作新增显式 App command id：`editor.add_next_occurrence` / `editor.add_all_occurrences`，通过 UI JSON command dispatcher 调用 `add_next_occurrence` / `add_all_occurrences` 默认 options，并接入 command palette、Edit 菜单、默认 keymap 和命令注册测试。
- 2026-08-01 阶段 30 已完成：AttoEditor 为常用 selection / multicursor 操作新增稳定 App command id：`editor.select_word`、`editor.select_line`、`editor.expand_selection`、`editor.add_cursor_above`、`editor.add_cursor_below`，通过 UI JSON command dispatcher 调用对应 cursor command，并接入 command palette、Edit 菜单和命令注册测试；`editor.select_line` 已有默认 Cmd+L keymap。
- 2026-08-01 阶段 31 已完成：AttoEditor preferences 新增 `autoPairsEnabled` 持久化设置和 “Enable auto pairs” UI；新建 editor chrome 和已打开 panes 会从 `AttoPreferences.effectiveAutoPairsEnabled` 应用 `EditorUI.setAutoPairsEnabled(_:)`，并支持 `ATTO_EDITOR_AUTO_PAIRS` / `EDITOR_CORE_APPKIT_AUTO_PAIRS` 环境变量覆盖默认值。
- 2026-08-01 阶段 32 已完成：AttoEditor preferences 新增 `wrapMode` 持久化设置和 Word Wrap popup；新建 editor chrome 和已打开 panes 会从 `AttoPreferences.effectiveWrapMode` 应用 `EditorUI.setWrapMode(_:)`，并支持 `ATTO_EDITOR_WRAP_MODE` / `EDITOR_CORE_APPKIT_WRAP_MODE` 环境变量覆盖默认值。

## 分层结论

### 1. Headless core 到 headless Swift FFI

`editor-core-ffi` 通过 JSON command plane 暴露了不少核心命令，Swift `EditorState.executeJSON(_:)` 和 `Workspace.executeJSON(viewId:commandJSON:)` 可以使用这条路径。

主要问题：

- JSON 命令面不是 `editor-core` 全量枚举的一比一映射。
- 一些低频但对 Sublime 兼容很关键的命令没有进 `editor-core-ffi`。
- Swift headless wrapper 有 JSON escape hatch，但高层 Swift 类型化 API 不完整。

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
| `TypeChar` | 有 | UI JSON 有，headless FFI 缺 | Swift 有 typed `typeChar(_:)`，`insertText` 单字符也会在 Rust UI 内部走 typing 路径 | 仍缺 App command id；headless FFI 覆盖仍不一致。 |
| `ReplaceCoalescingUndo` / `ReplaceCoalescingUndoWithSelection` | 有 | UI JSON 有，headless FFI 缺 | Swift 有 typed `replaceCoalescingUndo` / `replaceCoalescingUndoWithSelection`；IME/marked text 路径内部也使用相关语义 | headless FFI 覆盖仍不一致。 |
| `ApplySnippet` | 有 | UI JSON 有，headless FFI 缺 | Swift 有 typed `applySnippet`；Tab/Backtab 可在 snippet active 时切 placeholder；completion popup 可应用 snippet item | headless FFI 覆盖仍不一致。 |
| `SnippetNextPlaceholder` / `SnippetPrevPlaceholder` | 有 | UI JSON 有，headless FFI 缺 | Swift 有 typed `snippetNextPlaceholder` / `snippetPrevPlaceholder`，`insertTab` / `insertBacktab` 也内部支持；AttoEditor command palette 和菜单有 `editor.snippet_next_placeholder` / `editor.snippet_prev_placeholder` | App 显式 command 已补齐；headless FFI 覆盖仍不一致。 |
| duplicate lines | 有 | 有 | Swift 有 typed `duplicateLines()`；AttoEditor command palette、菜单和 keymap 有 `editor.duplicate_lines` | P0 接线完成；仍缺启用/禁用状态模型。 |
| delete lines | 有 | 有 | Swift 有 typed `deleteLines()`；AttoEditor command palette、菜单和 keymap 有 `editor.delete_lines` | P0 接线完成；仍缺启用/禁用状态模型。 |
| move lines up/down | 有 | 有 | Swift 有 typed `moveLinesUp()` / `moveLinesDown()`；AttoEditor command palette、菜单有 `editor.move_lines_up/down` | P0 菜单接线完成；默认 keymap 仍未给 arrow-key 形式建模。 |
| join lines | 有 | 有 | Swift 有 typed `joinLines()`；AttoEditor command palette、菜单和 keymap 有 `editor.join_lines` | P0 接线完成；仍缺启用/禁用状态模型。 |
| split line | 有 | 有 | Swift 有 typed `splitLine()`；AttoEditor command palette 和菜单有 `editor.split_line` | P0 菜单接线完成；可配置 keymap 可覆盖。 |
| toggle comment | 有 | 有 | Swift 有 typed `toggleComment(_:)`；AttoEditor command palette、菜单和 keymap 有 `editor.toggle_line_comment` 并按文件类型选择基础 line token | 仍缺完整语言 comment config 桥接。 |
| general `ApplyTextEdits` | 有 | 有 | Swift 有 typed `applyTextEdits(_:)`；Rust UI 也有 LSP text edit apply helper；completion popup 可应用 textEdit/additionalTextEdits | LSP code action、rename 等仍需要产品化接线。 |
| `DeleteToPrevTabStop` | 有 | 有 | Swift 有 typed `deleteToPrevTabStop()`；AttoEditor command palette 和菜单有 `editor.delete_to_prev_tab_stop` | P0 菜单接线完成；可配置 keymap 可覆盖。 |
| explicit indent/outdent commands | 有 | 有 | Swift 有 typed `indent()` / `outdent()`；Tab/Backtab 主路径可用；AttoEditor command palette 和菜单有 `editor.indent/outdent` | P0 菜单接线完成；Tab/Backtab 仍走文本系统主路径。 |
| `EndUndoGroup` | 有 | 有 | Swift 有 typed `endUndoGroup()` | App 层复合命令还未统一使用。 |
| logical `MoveTo` / `MoveBy` | 有 | 有 | Swift 有 typed `moveTo(line:column:)` / `moveBy(deltaLine:deltaColumn:)`，也可通过 selection/conversion 间接达成 | 仍缺面向用户的参数化 App command。 |
| visual movement commands | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用，AppKit key handling 覆盖一部分 | 仍缺 App command coverage matrix。 |
| selection / multicursor commands | 有 | 有 | Swift UI FFI 有 typed select word/line、expand selection、add cursor above/below，也可通过 UI JSON 调用；AttoEditor command palette 和菜单有 `editor.select_word` / `editor.select_line` / `editor.expand_selection` / `editor.add_cursor_above` / `editor.add_cursor_below` | 常用 App command 已补齐；仍缺完整 Selection 菜单分组、arrow-key keymap 解析和所有视觉移动命令矩阵。 |
| `MoveToMatchingBracket` | 有 | headless FFI 缺 | Swift UI 有公开方法 | headless 和 UI command 面不一致。 |
| add occurrence options | 有 | 有 | Swift typed `addNextOccurrence(options:)` / `addAllOccurrences(options:)` 已支持 options；AttoEditor command palette、菜单和 keymap 有 `editor.add_next_occurrence` / `editor.add_all_occurrences` 默认 options 入口 | 默认 App command/keymap 已补齐；仍缺 settings/search-options 接线。 |
| `SetWrapMode` | 有 | 有 | Swift 有 typed `setWrapMode(_:)`；AttoEditor command palette、菜单和 keymap 有 wrap off/char/word；preferences 有持久化 wrap mode 并会应用到新建和已打开 editor | App settings 接线已补齐。 |
| `SetWrapIndent` | 有 | 有 | Swift 有 typed `setWrapIndent(_:)` | 仍缺 settings 接线。 |
| `SetIndentationConfig` | 有 | 有 | Swift 有 typed `setIndentationConfig(_:)` | 仍缺语言配置接线。 |
| `SetAutoPairsConfig` | 有 | UI JSON 有，headless FFI 缺 | Swift 有 typed `setAutoPairsConfig(_:)`；也有 enabled bool | headless 和 UI command 面仍不一致。 |
| `SetAutoPairsEnabled` | 有 | UI JSON 有，headless FFI 缺 | Swift UI 有 bool，也可通过 `executeCommandJSON` 调用；AttoEditor preferences 有持久化开关并会应用到新建和已打开 editor | App settings 接线已补齐；headless 和 UI command 面仍不一致。 |
| fold / unfold / unfold all | 有 | 有 | Swift 有 typed `fold` / `unfold` / `unfoldAll`；AttoEditor command palette、菜单和 keymap 有 fold selection/unfold/unfold all；Swift UI binding 已可把 LSP folding ranges 应用到 core fold regions | P0 接线完成；仍缺 App 层 folding refresh/error UI 和 typed model。 |
| bracket match highlight update/clear | 有 | UI JSON 有，headless FFI 缺 | Swift UI 有 enabled bool 和内部更新，也有 typed `updateBracketMatchHighlights` / `clearBracketMatchHighlights` | headless 和 UI command 面仍不一致。 |

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
- declaration / type definition / implementation / references / completion / completion item resolve / signature help / prepare rename / rename / code action / code action resolve / code lens resolve / document symbols / workspace symbols / folding ranges / selection range / linked editing range / pull diagnostics / document color / color presentation / call hierarchy / type hierarchy 的 Swift UI raw async request/take API。
- AttoEditor App command/menu 已覆盖 go to definition/declaration/type definition/implementation/find references，其中 references 多结果有轻量可过滤结果 palette。
- AttoEditor App command/menu 已覆盖 completion popup 主路径。
- AttoEditor App completion popup commit 路径已覆盖 `completionItem/resolve`，可把 resolved item 的 `textEdit`、`additionalTextEdits` 和 snippet payload 应用到当前文档；resolve 不可用或超时时会回退到原始 item。
- AttoEditor App command/menu 已覆盖 signature help popup 主路径。
- document formatting。
- diagnostics 派生状态应用。
- semantic tokens 到 style intervals 的应用。
- inlay hints。
- code lens 派生显示。
- document links hit-test。
- document highlights。
- document symbols result 到 core outline 的应用和 JSON 导出。
- folding ranges result 到 core fold regions 的应用和 JSON 导出。
- WorkspaceEdit 中当前文档 `TextEdit` 的 Swift UI binding 应用，并返回跨 URI skip/summary 信息。
- AttoEditor App command/menu/keymap 已覆盖 `lsp.rename` 主路径，可输入新名称、请求 LSP rename 并应用当前文档 WorkspaceEdit。
- AttoEditor App command/menu/keymap 已覆盖 `lsp.code_actions` 主路径，可携带当前 diagnostics context、展示 code action quick panel、resolve action、应用当前文档 edit、展示跨文件 WorkspaceEdit 摘要并发起 `workspace/executeCommand`；Quick Fix / Refactor / Source Action / Organize Imports / Fix All 已通过 `CodeActionContext.only` 和客户端 kind 前缀过滤产品化。
- Swift UI binding 已覆盖 document/range/on-type formatting 的阻塞请求和当前文档 `TextEdit` 应用；AttoEditor App command/menu 已覆盖 `editor.format_document`，command/menu/keymap 已覆盖 `editor.format_selection` 主路径。
- `LSPBridge` 中有若干 JSON/DTO 转换 helper。

仍缺产品化、结果 UI 或仍只停留在 raw API 的 LSP 能力：

- declaration/type definition/implementation 的多结果导航 UI 仍较基础。
- references 结果列表已有轻量 palette，但还不是完整结果面板。
- completion popup 主路径、commit-time completion resolve、rich documentation/detail preview、commitCharacters 提交行为、server triggerCharacters 自动触发、本地增量过滤和跨文件 WorkspaceEdit 摘要预览已有；仍缺 completion/code action 中的完整跨文件 WorkspaceEdit 应用。
- signature help popup 主路径已有，并会按 server trigger/retrigger characters 自动弹出，active parameter 富格式高亮、typed result model 和手动请求空/错反馈已完成。
- rename 主路径已有 App 输入 UI、prepareRename range/placeholder 默认名、当前文档 WorkspaceEdit 应用和跨文件 WorkspaceEdit 摘要预览；仍缺跨文件真正应用和 typed result model。
- code action 主路径已有 App quick panel、resolve、diagnostics context、kind/filter、当前文档 edit 应用、跨文件 WorkspaceEdit 摘要预览和 command 执行；仍缺跨文件真正应用、执行结果/错误展示和 typed result model。
- code lens resolve 和 workspace command execution 的 Swift UI binding 已有；仍缺 App 层 code lens action UI、执行结果/错误展示和 typed model。
- outline / document symbols 已有 quick panel 主路径，但还缺持久 Outline panel。
- workspace symbols 已有 quick panel 主路径，但还缺增量查询/输入面板和完整结果模型。
- on-type formatting 已有 explicit binding、换行触发和 server trigger characters 自动触发路径；仍缺错误展示和 typed result model。
- semantic tokens refresh / delta 策略。
- folding ranges binding 已覆盖 request/take/apply 到 fold UI state；仍缺 App 层 refresh/error UI、折叠范围可视化和 typed model。
- selection range raw request/take 已有；仍缺 App 层 expand-selection 产品化和 typed model。
- linked editing raw request/take 已有；仍缺联动编辑 UI、编辑同步策略和 typed model。
- document diagnostic pull / workspace diagnostic raw request/take 已有；仍缺 Problems panel 增量刷新、workspace 级归属和 typed model。
- document color / color presentation raw request/take 已有；仍缺色块 UI、color picker、编辑应用和 typed model。
- call hierarchy raw request/take 已有；仍缺 hierarchy panel、导航 UI 和 typed model。
- type hierarchy raw request/take 已有；仍缺 hierarchy panel、导航 UI 和 typed model。
- references/locations 结果列表 UI。
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

阶段 5 已补齐 Swift UI binding 的主要可观测 API：

- `EditorUI.diagnosticsJSON()` 获取当前 diagnostics 列表。
- `EditorUI.decorationsJSON()` 获取当前 decoration layers。
- `EditorUI.documentSymbolsJSON()` 获取当前 document symbols。
- `EditorUI.foldingRegionsJSON()` 获取当前 fold regions。
- `EditorUI.styleIntervalsJSON(start:end:)` 获取当前 style layers 的样式区间。
- `EditorUI.lspApplyDocumentSymbolsJSON(_:)` 可把 LSP document symbols result 写入 core outline。
- `EditorUI.lspApplyFoldingRangesJSON(_:)` 可把 LSP folding ranges result 写入 core fold regions。

剩余缺口已经从“Swift binding 拿不到”转为 App 层消费、模型化和统一控制：

- Swift 侧目前仍以 JSON snapshot 为主，缺少 diagnostics、decorations、symbols、fold regions、style intervals 的高层 typed model。
- App 层没有一个统一的 derived-state store，供 outline、problems panel、minimap markers、gutter icons、status bar、测试断言共同使用。
- App 层还没有统一的派生状态刷新策略、过期响应处理、增量更新通知和错误展示。

这会影响 Sublime 复刻中的这些功能：

- Problems panel。
- Outline / symbol list。
- Goto symbol。
- Minimap 标记。
- Gutter diagnostic icons。
- Fold commands。
- 视觉回归测试中的“结构化断言”。

## 多文档、tab、workspace 和分屏缺口

本节结论：**多文档、tab、workspace、project/session 的长期状态归属必须落在 `editor-core` / `editor-core-ui` 一侧的 workspace 模型上**。Swift/AppKit 层不应再新建或扩展第二套长期独立的 workspace/tab/session ownership；现有 Swift tabs/splits 只能作为迁移垫片存在。这个约束适用于 tab 生命周期、preview/pin、dirty/close 语义、split layout、跨 tab 搜索、session restore、project/workspace LSP lifecycle 和未来多窗口归属。

当前仓库里存在多个相关入口，但长期 ownership 应只有一套：

- `editor-core` 有 headless `Workspace`。
- `EditorCoreFFI.Workspace` 暴露了一部分 headless workspace 能力。
- `editor-core-ui` 有 `MultiDocumentEditorUi`，包含 tab、preview tab、pin、close、split、search all tabs 等能力。
- Swift `EditorUI.cloneView` 可以创建共享 buffer 的额外 view。
- AttoEditor App 当前仍在 Swift 层维护 tabs；每个 tab 持有一个或多个 `EditCoreUI` pane，基础 split-right 通过 `EditorUI.cloneView` 共享同一 buffer。这是已落地的过渡实现，不应继续演进成第二套 workspace ownership。

主要缺口：

- `editor-core` / `editor-core-ui` 侧 workspace / multi-document 模型还没有成为 Swift 产品层的单一状态源；这是后续多文档/tab/workspace 工作的首要架构缺口。
- `MultiDocumentEditorUi` 没有通过 FFI/Swift 暴露。
- `EditorCoreFFI.Workspace` 只暴露了部分 headless command 能力，还缺 App 级 open/close/select/pin/split/session/project/LSP lifecycle 契约。
- AttoEditor 当前 Swift tab 系统和 Rust UI multi-document 系统没有统一；后续应迁移为 core workspace state 的投影，而不是在 Swift 侧继续维护独立模型或给 Swift-only tab state 继续加语义。
- 新增 tab/workspace 功能时，缺口不应通过给 Swift `Tab` / `EditorArea` 增加新的 ownership 字段来补；如果 core workspace 还没有对应语义，应先补 Rust 侧 command/query/event，再补 FFI 和 Swift wrapper。
- Swift 侧仍需要 UI state，但只能保存表现层状态，例如当前 responder、panel 展开状态、AppKit selection/focus glue、窗口几何和临时 drag/drop 交互；文档集合、tab 顺序、active tab、split tree、dirty state、preview/pin、关闭策略和跨文档搜索结果归属应来自 core workspace。
- App 层已有基础 split-right、focus next/previous pane、close pane；还没有 pane move、拖拽 tab 到 split、layout restore 等完整 split pane 产品语义。
- `cloneView` 是底层能力；当前已接入基础 split layout 和 active pane focus tracking，但还不等于完整 tab movement、关闭语义、状态恢复。
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

- command registry 仍较轻量，还没有命令启用/禁用状态、参数模型和分组元数据。
- command palette、主菜单和 keymap 已覆盖一批 Sublime 基础编辑命令；LSP location、symbols quick panels、completion popup、signature help、rename 和 code action 主路径已接入，但更深层 LSP/项目级命令仍不完整。
- P0 菜单、command palette、keymap 和测试已开始统一使用 command id；更深层的命令上下文、参数化命令和冲突解析仍缺。
- 一些 core/LSP 命令仍没有 App 命令入口。
- 已有初步用户 keymap 文件，但还不是完整 Sublime keymap 兼容实现。
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

当前仓库已经有 Sublime 相关 crate 和 Swift/App 集成，但“复刻 Sublime Text”需要更宽的产品面。

已具备或部分具备：

- Sublime syntax 相关解析/加载路径。
- Sublime/JSON theme 相关路径。
- Tree-sitter 语法高亮路径。
- 基础 tab、sidebar、minimap、find/replace。
- 部分 command palette。

仍需审计或补齐：

- `.sublime-syntax` 兼容覆盖率。
- `.sublime-color-scheme` 兼容覆盖率。
- `.tmTheme` 兼容覆盖率。
- Sublime settings scope 继承规则。
- keymap 文件已有初步 JSON 解析；仍缺完整 Sublime keymap 条件、上下文和冲突解析。
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
- accessibility identifiers / menu item identifiers。
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
- LSP interactive request 已覆盖一批 raw JSON result API，但返回值和事件仍缺统一 envelope。
- 长任务、异步请求、取消、错误、诊断日志没有统一 Swift 事件流。
- 配置 DTO 不完整，例如 wrap、indentation、comment、auto-pairs、word boundary、search options。
- 缺 ABI version / feature probing 在 Swift 层的显式使用策略。

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
- 已完成：AttoEditor command palette 为一批 Sublime 基础编辑命令建立稳定 command id。
- 已完成：为高频命令补 typed Swift convenience API。
- 已完成：把 App command id 统一接入主菜单和初步用户可配置 keymap。
- 为这些命令补 AppKit 操作测试和结构化状态测试。

### P1：补 LSP 产品主路径

- completion commit-time resolve、rich documentation/detail preview、commitCharacters 提交行为、server triggerCharacters 自动触发、本地增量过滤和跨文件 WorkspaceEdit 摘要预览已完成；仍缺跨文件 WorkspaceEdit 真正应用和更完整 typed result model。
- signature help server trigger/retrigger characters 自动触发、active parameter 富格式高亮、typed result model 和手动请求空/错反馈已完成。
- references/implementation/declaration/type definition。
- rename prepareRename range/placeholder 和跨文件 WorkspaceEdit 摘要预览已产品化；仍缺跨文件 WorkspaceEdit 真正应用和 typed result model。
- code action diagnostics context、kind/filter 和跨文件 WorkspaceEdit 摘要预览已完成；仍缺跨文件 WorkspaceEdit 真正应用、执行结果/错误展示和 typed result model。
- document/workspace symbols 持久面板和 workspace 增量查询。
- range formatting Swift/App 主路径已完成；on-type formatting binding、换行触发和 server trigger characters 自动触发路径已完成，仍缺错误展示和 typed result model。
- folding ranges request/take/apply 到 fold state 已完成；仍缺 App 层 refresh/error UI、可视化和 typed model。
- code lens resolve、selection range、linked editing、diagnostics pull、document color/color presentation、call hierarchy、type hierarchy 的 raw request/take binding 已完成；仍缺 App 层 UI 和 typed model。
- LSP result panels 和错误展示。

### P1：统一多文档和分屏架构

- 明确采用 core-owned workspace：`editor-core` / `editor-core-ui` 的 `Workspace` / `MultiDocumentEditorUi` 是多文档、tab、split、project/session 的状态来源。
- 暴露 `MultiDocumentEditorUi` 到 FFI/Swift，并补齐 Swift-facing open/select/close/pin/preview/split/search-all-tabs/session API。
- 将 AttoEditor 现有 Swift tabs/splits 迁移为 core workspace state 的 AppKit 投影，而不是继续维护独立 workspace/tab/session model；新增字段时要区分“UI 表现缓存”和“文档/workspace 所有权状态”。
- 继续产品化 split panes：pane move、split layout restore、拖拽 tab 到 split，但新增命令和状态归属必须先落在 core workspace 模型，然后通过 FFI/Swift wrapper 驱动 AppKit 表现。
- 统一 session restore、preview tab、pin tab、dirty state、close semantics。
- 明确 project/workspace 与 LSP server lifecycle 由 core workspace 模型协调，Swift 只负责启动参数、UI 触发和展示。
- 建立迁移期测试：同一 tab/split/workspace 操作同时断言 core workspace snapshot、Swift wrapper query 和 AppKit 投影，避免两边状态漂移。

### P2：深化 Sublime 兼容

- settings scopes。
- 完整 Sublime keymap 文件兼容。
- snippets/macros/build systems。
- package resource loading。
- command palette 覆盖。
- quick panels/input panels/output panels。
- Sublime theme/syntax 兼容矩阵。

### P2：视觉回归和黑盒自动化

- 建立 golden screenshot 测试工具。
- 引入 fixtures，覆盖主题、字体、Unicode、多光标、折叠、diagnostics、minimap。
- 补 `XCUIApplication` smoke tests。
- 在 CI 上固定 macOS runner、字体、scale factor 和渲染后端。

## 建议的功能矩阵

建议新增一份机器可读或半机器可读矩阵，作为后续工作入口：

| Feature | Core | core FFI | UI Rust | UI FFI | Swift `EditorUI` | Atto command | Tests |
| --- | --- | --- | --- | --- | --- | --- | --- |
| duplicate line | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, command palette/menu/keymap | yes |
| toggle comment | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, command palette/menu/keymap | yes |
| apply snippet | yes | no | yes | yes, via JSON | yes, typed + JSON | partial, completion apply + Tab/Backtab placeholder path + explicit placeholder commands; no generic apply-snippet command | yes |
| add occurrence | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, default-options command palette/menu/keymap | yes |
| selection/multicursor | yes | yes | yes | yes, via JSON | yes, typed + JSON | yes, common commands in command palette/menu; select line has default keymap | yes |
| LSP completion | yes | partial helper | yes | yes, raw completion + resolve result | yes, raw completion + resolve result | yes, popup + auto trigger + incremental filter + commit-time resolve/current-doc apply | partial |
| LSP symbols | yes | partial helper | yes | yes, raw JSON result | yes, raw JSON result | yes, document/workspace symbols quick panels | yes |
| LSP rename | yes | partial helper | partial | partial, raw request + current-doc WorkspaceEdit apply | partial, raw result + current-doc WorkspaceEdit apply | yes, prepareRename seed + input UI + menu/keymap + current-doc apply | partial |
| LSP code action | yes | partial helper | partial | partial, raw request/resolve + current-doc WorkspaceEdit apply + executeCommand | partial, raw result + diagnostics context + kind filters + current-doc WorkspaceEdit apply + executeCommand | yes, quick panel/menu/keymap/diagnostics context/kind-filter commands/current-doc apply/cross-file summary | partial |
| LSP formatting | yes | partial helper | yes, document/range/on-type blocking apply + trigger-character auto path | yes, document/range/on-type blocking apply | yes, typed document/range/on-type helpers | document + selection commands; on-type trigger-character auto path | partial |
| LSP folding ranges | yes | partial helper | yes, request/take + apply to fold regions | yes, raw request/take + apply JSON | yes, raw request/take + apply JSON | partial, fold commands use current state | yes |
| LSP advanced raw requests | yes | partial helper | yes, code lens resolve + selection/linked editing/diagnostics/color/hierarchy raw request/take | yes, raw request/take JSON | yes, raw request/take JSON | no, needs product UI | partial |
| split view | partial | no | yes | yes, clone view | yes, clone view + AppKit split pane | yes, split/focus/close pane commands | yes |
| workspace tabs/splits | yes, headless `Workspace` | partial `Workspace` wrapper | yes, `MultiDocumentEditorUi` | no | no, current Swift tabs are migration shims; future ownership must be core workspace | partial, transitional AppKit projection; new tab/workspace semantics must move to core-owned workspace first | partial |

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
