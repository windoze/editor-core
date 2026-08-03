# Swift 绑定与 UI 集成缺口审计

审计日期：2026-08-01

任务级执行声明（2026-08-02）：`SWIFT-GAPS.md` 所列全部目标属于同一个持续工程任务，后续实现、验证、文档更新和阶段提交均按照 `PLAN.md` 的执行计划推进；该声明覆盖整个 Swift gaps 实现任务，而不只是本文档维护任务。本文只记录 gap、完成证据、剩余风险和 out-of-scope 说明，不单独定义实施顺序。

本文记录当前 Swift 侧、FFI 层、`editor-core-ui` 适配层以及 AttoEditor App 层相对 `editor-core-*` 能力的功能缺口。这里的 “Swift UI” 指仓库中的 Swift/AppKit/Skia/Metal 集成，不是 Apple SwiftUI 框架。

本文关注的是“能否从 Swift 产品层完整使用 `editor-core-*` 能力”，不是评价 Rust core 自身是否完整。总体结论是：**当前 Swift 路径已经能支撑一个可用编辑器主流程，但还不是 `editor-core-*` 的完整能力投影**。尤其对于“复刻 Sublime Text”这个目标，缺口主要集中在命令面、LSP 产品化、派生状态产品化/消费、多文档/分屏归属、Sublime 兼容行为和视觉/交互测试体系。其中多文档、tab、workspace、project/session 的状态归属已经明确：后续应收敛到 `editor-core` / `editor-core-ui` 的 workspace 模型，Swift/AppKit 侧不再新开或扩展一套长期独立的 workspace/tab/session 模型。本文后续提到的 Sublime 兼容不包含 `.sublime-syntax` 语法定义扩展；AttoEditor 的语言语义、结构化高亮和智能能力重点走 Tree-sitter 与 LSP 路线，Sublime syntax 支持以现有 `editor-core-sublime` 能力为基线即可。因此，后续 Swift gaps 的验收口径不把“提高 Sublime syntax 覆盖率”列为待补功能。

## 执行计划

当前任务状态：`SWIFT-GAPS.md` 所列全部目标作为一个整体，统一按照 `PLAN.md` 中的阶段划分、提交边界、验证命令和完成标准推进。

`PLAN.md` 是后续工程实施、阶段排序、提交边界、验证命令和最终完成标准的唯一执行计划来源。所有后续提交都必须在 `PLAN.md` 的对应阶段章节中注明该提交所属任务、提交边界和验证记录；不得只在本文记录提交归属。本文继续作为缺口审计、任务范围参考与状态记录，不再承担独立排期、执行计划或提交索引职责；随着各阶段完成，需要同步更新对应 gap 的完成证据、剩余风险或 out-of-scope 说明。后续新增、调整或关闭目标时，也应先映射到 `PLAN.md` 的阶段计划，再回写到本文的 gap 状态。

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
- `EditorCoreUIFFI.MultiDocumentEditorUI` 已能访问 Rust `MultiDocumentEditorUi` 的基础 tab/preview/pin/close/split/search-all-tabs 模型，并能同步 tab 文本、保存/dirty 状态；AttoEditor session snapshot 保存路径、pane layout snapshot、opened-files/sidebar/tab-bar 投影、active-tab 读取、core tab title sync、close callback URL、WorkspaceEdit removed-tab callback URL、AppKit content host 投影、window title、status bar metadata、language configuration、tab group-close/close-all 命令、opened-files selection/open-existing 查找、open-with-location 导航校验、opened-scope Find in Files 结果 URL、LSP target navigation、WorkspaceEdit preview text lookup、WorkspaceEdit apply 前同步、Document Symbols / Workspace Outline URI 投影、resolved inlay hint text edit apply 以及 Code Lens action title 已开始优先消费 core tab snapshot 中的顺序、active tab、document URI、preview、dirty、view count 和 active view index。
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
- 阶段 5 后续缺口中，Swift typed model、active-tab derived-state store、status bar 消费和 Problems quick panel 已在阶段 39-41 补齐，基础持久 Outline/Symbols panel 已在阶段 115 补齐，active-tab 持久 Problems panel 已在阶段 116 补齐，workspace Problems store/panel 已在阶段 117 补齐，active-tab minimap diagnostic markers 已在阶段 118 补齐，active-tab gutter diagnostic icons 已在阶段 119 补齐，workspace diagnostics 到已打开 tab 的 marker 聚合已在阶段 120 补齐，core-owned workspace diagnostics store 起点已在阶段 123 补齐，core-backed workspace diagnostic marker snapshot 起点已在阶段 124 补齐，workspace/active diagnostics 统一 marker projection model 起点已在阶段 125 补齐，workspace/active diagnostics 状态栏摘要统一已在阶段 126 补齐，active-tab Problems quick/persistent list 的统一模型消费已在阶段 127 补齐，workspace 全局 Problems panel 已在阶段 128 补齐，diagnostics lifecycle entry 起点已在阶段 129 补齐，diagnostics events-after 查询已在阶段 130 补齐，diagnostics stale/refresh lifecycle metadata 已在阶段 131 补齐，App 层跨 result family event stream 起点已在阶段 132 补齐，code actions 已在阶段 133 接入该 event stream，completion results 已在阶段 134 接入该 event stream，rename results 已在阶段 135 接入该 event stream，document color / color presentation results 已在阶段 136 接入该 event stream，core-owned workspace diagnostics event stream 起点已在阶段 137 补齐，`EditorUi` core-owned LSP result slot event stream 起点已在阶段 138 补齐，MultiDocument/project 级 result event 聚合起点已在阶段 139 补齐，`EditorUi` core-owned LSP request lifecycle event stream 起点已在阶段 140 补齐，MultiDocument/project 级 request event 聚合起点已在阶段 141 补齐，显式 cancel/timeout lifecycle 已在阶段 142 补齐，on-type formatting request lifecycle 已在阶段 143 补齐，UI auxiliary derived-state request lifecycle 起点已在阶段 144 补齐，semantic/folding internal refresh request lifecycle 已在阶段 145 补齐，diagnostics notification/pull lifecycle 已在阶段 146 补齐，Swift LSP event metadata / workspace diagnostics 字段 typed accessor 已在阶段 147 补齐，completion result / resolve item payload typed wrapper 已在阶段 148 补齐，completion App 主路径 typed payload 消费已在阶段 149 补齐，location family result typed payload wrapper 和 App 主路径消费已在阶段 150 补齐，rename prepare/result typed payload wrapper 和 App 主路径消费已在阶段 151 补齐，code action result/resolve typed payload wrapper 和 App 主路径消费已在阶段 152 补齐，document/workspace symbols result typed payload wrapper 已在阶段 153 补齐，document color / color presentation result typed payload wrapper 已在阶段 154 补齐，call/type hierarchy result typed payload wrapper 已在阶段 155 补齐，document/workspace diagnostics pull result typed payload wrapper 和 workspace diagnostics App 主路径消费已在阶段 156 补齐，selection range result typed payload wrapper 已在阶段 157 补齐，linked editing result typed payload wrapper 已在阶段 158 补齐，code lens result/resolve typed payload wrapper 已在阶段 159 补齐，folding ranges typed payload wrapper 已在阶段 160 补齐，semantic tokens full/delta/range result typed payload wrapper、manual request/take ABI 和 App typed apply baseline 已在阶段 161 补齐；阶段 178 已补 `EditorUi` 级统一 state event drain 起点，阶段 179 已补 MultiDocument/project 级统一 state event 聚合起点，阶段 180 已补文本变更与 dirty 状态事件，阶段 181 已补 selection/caret 状态事件，阶段 182 已补 viewport 状态事件，阶段 183 已补 layout 状态事件，阶段 184 已补 derived-state changed/stale 状态事件，阶段 185 已补 AttoEditor active derived-state store 对统一 state-event cursor 的消费起点，阶段 186 已补 workspace Problems store 对 core-owned workspace diagnostics event cursor 的消费起点，阶段 187 已补 workspace diagnostic marker projection 对同一 cursor 的缓存刷新，阶段 188 已让 Locations/Symbols 持久在线 panel 消费 result lifecycle entry 而不是裸 snapshot，阶段 189 已把这些 lifecycle metadata 显示到持久在线 panel 的稳定 UI 文本，阶段 190 已给 Locations/Symbols lifecycle entry 增加 Fresh/Stale/Error 状态模型，持久在线 panel metadata 可显示状态，并在 active 文档编辑后把当前 Locations/Symbols 结果标成 `Stale: document edited`，新结果记录默认恢复 Fresh；阶段 191 已把 Locations/Symbols 显式 request feedback error 接到 panel current entry，阶段 192 已补 project-level request/result event cursor 的 panel error 聚合起点，阶段 193 已补 opened-document workspace outline store 与 panel command 起点，阶段 194 已补 core-owned workspace outline snapshot ABI/Swift wrapper 与 App 消费，阶段 195 已补打开 tab 的 core document URI metadata，阶段 196 已补 `MultiDocumentEditorUi` open-tab WorkspaceEdit transaction preview/apply 起点，阶段 197 已补 WorkspaceEdit transaction event cursor 起点，阶段 198 已补 open-tab resource operations transaction 起点，阶段 199 已补 skipped/conflict detail 起点，阶段 200 已补 open-tab TextDocumentEdit version check 起点，阶段 203 已补 root-gated 未打开本地文件 text edits，阶段 204 已补 root-gated 未打开本地文件 resource operations，阶段 205 已补 documentChanges 顺序保持 apply，阶段 206 已补未打开本地 resource operation 运行时 filesystem error rollback 起点，阶段 207 已补打开 tab 本地 resource operation 的 root-gated 文件系统副作用，阶段 208 已把 AttoEditor WorkspaceEdit App apply helper 主路径切到 core transaction，阶段 209 已补基础 preview/confirmation 起点，阶段 210 已补专用 diff preview panel 起点，阶段 211 已补未打开文件 text edit filesystem rollback，阶段 212 已补打开 tab transaction failure rollback，阶段 213 已补显式 atomic apply mode，阶段 214 已补打开 tab App 投影 undo grouping 起点，阶段 215 已补 atomic apply 运行时 text edit failure rollback，阶段 216 已补 WorkspaceEdit resource-order dependency preflight，阶段 217 已补 unsupported resource operation 的 ordered dependency preflight，阶段 218 已补 WorkspaceEdit resource operation typed summary，阶段 219 已补 WorkspaceEdit dirty/conflict typed summary，阶段 220 已补最近一次 WorkspaceEdit transaction undo 起点，阶段 221 已补用户级 command/menu/keymap 起点，阶段 222 已补 session snapshot 的 core tab projection 起点，阶段 223 已补 opened-files/sidebar/tab-bar 的 core tab projection 起点，阶段 224 已补 active-tab 查询的 core active tab projection 起点，阶段 225 已补 AppKit content host 的 core active tab projection 起点，阶段 226 已补 close-other/close-right tab group 命令的 core tab projection 起点，阶段 227 已补 close-all tab 命令的 core tab projection 起点，阶段 228 已补 opened-files selection/open-existing 的 core document URI projection 起点，阶段 229 已补 open-with-location 导航校验的 core document URI projection 起点。剩余缺口收窄为更完整跨 tab/project panel UI、更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
- 阶段 230 进一步补齐阶段 5 的 core document URI projection：opened-scope Find in Files 的结果 URL 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 231 进一步补齐阶段 5 的 core document URI projection：LSP location target navigation 已跟随 core tab snapshot 校验 active tab URL，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 232 进一步补齐阶段 5 的 core document URI projection：WorkspaceEdit diff preview 的 text provider 已跟随 core tab snapshot 查找打开 tab 当前文本，而不是只读取 Swift 本地 `tab.fileURL` 或 projected 文件磁盘内容。
- 阶段 233 进一步补齐阶段 5 的 core document URI projection：WorkspaceEdit core transaction apply 前的打开 tab 同步已保留 core tab snapshot 中已有的 `document_uri`，而不是无条件用 Swift 本地 `tab.fileURL` 覆盖。
- 阶段 234 进一步补齐阶段 5 的 core document URI projection：Document Symbols 的 symbol target URI 与 Workspace Outline document key 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 235 进一步补齐阶段 5 的 core document URI projection：resolved inlay hint 的 text edits 已在包装和应用 WorkspaceEdit 时跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 236 进一步补齐阶段 5 的 core document URI projection：rename request/result context 的 WorkspaceEdit document URI 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 237 进一步补齐阶段 5 的 core document URI projection：keymap dynamic context 和 toggle comment 语言配置已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 238 进一步补齐阶段 5 的 core document URI projection：active Problems/diagnostics snapshot、lifecycle scope 和 active diagnostic title 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 239 进一步补齐阶段 5 的 core document URI projection：Code Lens actions quick panel/current-line action title 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 240 进一步补齐阶段 5 的 core document URI projection：window title 的 active document display name 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 241 进一步补齐阶段 5 的 core document URI projection：status bar file size 和 Rust/LSP relevance 判断已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 242 进一步补齐阶段 5 的 core document URI projection：indentation/comment language configuration application 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 243 进一步补齐阶段 5 的 core document URI projection：core tab title sync 已跟随 core tab snapshot，而不是用 Swift 本地 `tab.fileURL` 覆盖已投影 title。
- 阶段 244 进一步补齐阶段 5 的 core document URI projection：close-tab notification/callback URL 已跟随 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 245 进一步补齐阶段 5 的 core document URI projection：WorkspaceEdit core transaction / undo removed-tab close callback URL 已跟随 apply/undo 前的 core tab snapshot，而不是只读取 Swift 本地 `tab.fileURL`。
- 阶段 246 进一步补齐阶段 5 的 pane layout/session schema migration 起点：session tab snapshot 已新增可选 `paneLayout` descriptor，并优先按 core-projected view count / active view index 写出和恢复，旧 `paneCount` / `activePaneIndex` 保留为兼容 fallback。
- 阶段 247 补齐阶段 6 的 LSP workspace lifecycle 起点：`EditorUi::lsp_enable_stdio(...)` 已把 root URI 投影为 LSP `workspaceFolders`，并用于 initialize params 与 `workspace/workspaceFolders` client response。
- 阶段 248 继续补齐阶段 6 的 LSP workspace lifecycle：`workspace/didChangeWorkspaceFolders` 已从 headless LSP session 暴露到 Rust UI、C ABI 和 Swift typed wrapper，并会同步更新后续 `workspace/workspaceFolders` response 列表。
- 阶段 249 继续补齐阶段 6 的 project root 到 LSP workspace lifecycle 接线：`MultiDocumentEditorUi` workspace roots 更新已返回 LSP `WorkspaceFolder` added/removed diff，Swift wrapper 可类型化消费，AttoEditor workspace root 变化会用 core diff 通知当前 active LSP session。
- 阶段 250 继续补齐阶段 6 的 root change fan-out：AttoEditor workspace root 变化现在会把 core diff 广播给所有已打开且 LSP 已启用的 tab，而不是只通知当前 active tab；split pane 不会重复通知。
- 阶段 251 继续补齐阶段 6 的 LSP document lifecycle：`textDocument/didSave` / `textDocument/didClose` 已从 headless LSP session 暴露到 Rust UI、C ABI 和 Swift typed wrapper，AttoEditor 保存 tab / 关闭 tab 时会通知对应 LSP session。
- 阶段 252 继续补齐阶段 6 的 LSP document lifecycle：`textDocument/didOpen` 已从 headless LSP session 暴露到 Rust UI、C ABI 和 Swift typed wrapper，AttoEditor 打开没有自身 LSP session 的新 tab 时会把新文档通知给其它已打开且 LSP 已启用的 tab session，并在后续保存/关闭时通知同一类既有 sessions。
- 阶段 253 继续补齐阶段 6 的 LSP document lifecycle：extra document 的 `textDocument/didChange` 已从 headless LSP session 暴露到 Rust UI、C ABI 和 Swift typed wrapper；AttoEditor 编辑没有自身 LSP session 的 tab 时，会把 full-document didChange 通知给其它已打开且 LSP 已启用的 tab session，range/UTF-16 计算由 Rust per-document mirror 完成。
- 阶段 254 继续补齐阶段 6 的 shared-session root-set 策略：`LspSession::did_change_workspace_folders(...)` 已基于 Rust LSP client 持有的 workspace folder set 过滤重复 root diff，避免多个 tab 共享同一个 `SharedLspSession` 时对同一 server 重复发送 `workspace/didChangeWorkspaceFolders`。
- 阶段 255 继续补齐阶段 6 的 LSP status 可观测性：`LspSessionStatus` / `EditorUi.lsp_status_json()` 已输出当前 LSP client-side `workspace_folders`，Swift `EcuLspStatusSnapshot` 已提供 typed `workspaceFolders`，AttoEditor status bar formatter 会显示 workspace root 与紧凑 capability 摘要，并用 tooltip 保留长状态文本。
- 阶段 256 继续补齐阶段 6 的 LSP status 订阅模型起点：`EditorUiStateEvent` 已新增 `lsp_status_changed` / `lsp_status` payload，LSP enable/disable、workspace folder didChange 和 polling failure 会把 typed status snapshot 投入统一 state event stream；Swift `EcuEditorUIStateEvent` 已可解码为 `EcuLspStatusSnapshot`。
- 阶段 257 继续补齐阶段 6 的 App status event 消费：AttoEditor active state/event drain 现在会缓存 `lsp_status_changed` 的 typed payload，状态栏优先使用该 event-derived status 显示 LSP server/root/capabilities，缺失时才回退到 `lspStatusSnapshot()` 轮询。
- 阶段 258 继续补齐阶段 6 的 LSP status failure event 覆盖：低层 LSP didChange sync、refresh processing、on-type formatting request/response/apply、result slot apply 和 derived-state apply 的失败路径现在会在写入 failed `lsp_status_json()` 的同时发出 `lsp_status_changed` state event，减少 Swift/App 只能靠轮询发现 failure detail 的路径。
- 阶段 259 继续补齐阶段 6 的 project-level status event 消费起点：AttoEditor project LSP lifecycle drain 现在会消费 core-owned `MultiDocumentEditorUI.stateEvents(...)` 中的 `lsp_status_changed`，并把 failed status 作为 `.status` 来源写入 project LSP event store，供后续项目级 status panel / feedback UI 按 cursor 消费。
- 阶段 260 继续补齐阶段 6 的 project-level status panel 起点：AttoEditor 新增 `lsp.show_project_lsp_status` 命令、Go 菜单项和 `AttoEditor.LSP.ProjectStatusEvents` 轻量面板，可展示 project LSP event store 中的 request/result/status 错误事件。
- 阶段 261 继续补齐阶段 6 的 server progress/activity 状态事件：`EditorUi` 现在会对 LSP `$/progress` 导出的 activity/state 变化发出去重的 `lsp_status_changed`，Swift/App 可通过既有 state event stream 看到 Indexing/Busy/Ready 等状态变化。
- 阶段 262 继续补齐阶段 6 的 server process health 状态事件：LSP 子进程的 running/exited、退出码和 signal 现在进入 `lsp_status_json()` / `lsp_status_changed` payload，Swift `EcuLspStatusSnapshot.process` 可 typed 读取，进程退出会发出去重的 failed status event。
- 阶段 263 继续补齐阶段 6 的 active-tab server restart 起点：AttoEditor 新增 `lsp.restart_server` 命令和 Go 菜单项，会复用打开文档时保存的 LSP launch config，通过既有 Swift `EditorUI.lspDisable/lspEnable` binding 重启当前 active tab 的 LSP session。
- 阶段 264 继续补齐阶段 6 的 project-level manual restart 起点：AttoEditor 新增 `lsp.restart_project_servers` 命令和 Go 菜单项，会按 core workspace tab 投影批量重启所有已保存 launch config 的打开文档 LSP session。
- 阶段 265 继续补齐阶段 6 的 close/project-close 停止侧起点：关闭拥有自身 LSP session 的 tab 时，AttoEditor 改为释放该 view 的 LSP handle，由 Rust `lsp_reset()` 负责 didClose，避免 Swift 手动 didClose 与 reset didClose 重复发送。
- 阶段 266 继续补齐阶段 6 的 shared-session graceful shutdown 起点：`SharedLspSession` 最后一个强引用释放时会调用既有 `LspSession::exit()`，让 responsive LSP server 走 `shutdown` / `exit` 停止路径，而不是只依赖进程终止 fallback。
- 阶段 267 继续补齐阶段 6 的 host-visible shutdown 控制面：Rust `EditorUi`、C ABI 和 Swift `EditorUI` wrapper 已新增显式 `lsp_shutdown` / `lspShutdown()` API，可主动关闭当前 LSP session 并返回是否实际关闭了 live session。
- 阶段 268 继续补齐阶段 6 的 shared-session root-set ownership：`SharedLspSession` 在 workspace folder didChange 成功后会同步维护 root alias，并把新 root key 登记到 shared-session pool，后续同 command/args + 新 root 的 tab 会复用既有 server。
- 阶段 269 继续补齐阶段 6 的 project open/root lifecycle：AttoEditor 在 workspace root 变更和 session restore 后，会基于 core-projected open tabs 自动批量启动可配置但尚未启用的 LSP session，并保留手动语言选择的自动启动抑制标记。
- 阶段 270 继续补齐阶段 6 的 server process health 可观测性：`LspClient` 现在会捕获 piped stderr 的 bounded tail，`LspSessionStatus` / `EditorUi.lsp_status_json()` 会在 `process.stderr_tail` 中输出，Swift `EcuLspProcessStatus.stderrTail` 可 typed 读取；仍缺持久在线 stderr log、进程历史和 dashboard 级健康视图。
- 阶段 271 继续补齐阶段 6 的 project-level process health 消费：AttoEditor project LSP status events 现在会把 failed status 的 `process.stderrTail` 附加到 bounded event message 中，`lsp.show_project_lsp_status` 面板可展示最近失败事件的 stderr 片段；仍缺持久化 stderr log、独立进程历史表、自动恢复和 dashboard 级健康视图。
- 阶段 272 继续补齐阶段 6 的 project-level process health history 起点：AttoEditor 现在会把带 `process` payload 的 `lsp_status_changed` 状态快照记录到 bounded `AttoProjectLspProcessHealthEventStore`，保留 server、status、detail、tab/view 来源和 typed `EcuLspProcessStatus`；仍缺持久化 stderr/process log、独立 dashboard UI、自动崩溃恢复和更深层 core-owned LSP ownership schema。
- 阶段 273 继续补齐阶段 6 的 project-level process health UI 起点：AttoEditor 新增 `lsp.show_project_lsp_health` 命令、Go 菜单项和 `AttoEditor.LSP.ProjectProcessHealth` 轻量面板，可展示 bounded process health history 中的 server、availability/state、pid、exit/signal、scope 和 detail/stderr 摘要；仍缺持久化 stderr/process log、自动崩溃恢复、更深层 core-owned LSP ownership schema 和完整 dashboard 级健康视图。
- 阶段 274 继续补齐阶段 6 的 project-level process health 持久化起点：AttoEditor 新增纯 Foundation `AttoProjectLspProcessHealthLogStore`，把 process health event 追加到 Application Support 下的 JSONL 日志，并让 `AttoEditor.LSP.ProjectProcessHealth` 面板在内存 history 为空时按当前 workspace root 回退展示最近持久化记录；仍缺日志轮转/清理、复杂查询 UI、自动崩溃恢复、更深层 core-owned LSP ownership schema 和完整 dashboard 级健康视图。
- 阶段 275 继续补齐阶段 6 的 process health log retention 起点：`AttoProjectLspProcessHealthLogStore` 现在默认只保留最近 2000 条 JSONL 记录，并在 append 时自动清理旧行；仍缺按 workspace 独立配额、大小/时间轮转、导出/查询 UI、自动崩溃恢复、更深层 core-owned LSP ownership schema 和完整 dashboard 级健康视图。
- 阶段 276 继续补齐阶段 6 的 process health log 查询 UI 起点：AttoEditor 新增 `lsp.show_project_lsp_health_log` 命令、Go 菜单项和 `AttoEditor.LSP.ProjectProcessHealthLog` 轻量面板，可显式按当前 workspace root 查询 persisted JSONL 记录；仍缺导出、清空、复杂查询/filter DSL、按 workspace 独立配额、自动崩溃恢复、更深层 core-owned LSP ownership schema 和完整 dashboard 级健康视图。
- 阶段 277 继续补齐阶段 6 的 process health log 清空起点：`AttoProjectLspProcessHealthLogStore` 现在可以按当前 workspace root URI 清除 persisted JSONL 记录，AttoEditor 新增 `lsp.clear_project_lsp_health_log` 命令和 Go 菜单项；仍缺导出、确认弹窗、复杂查询/filter DSL、按 workspace 独立配额、自动崩溃恢复、更深层 core-owned LSP ownership schema 和完整 dashboard 级健康视图。
- 阶段 278 继续补齐阶段 6 的 process health log 导出起点：`AttoProjectLspProcessHealthLogStore` 现在可以按当前 workspace root URI 导出 JSONL 记录，AttoEditor 新增 `lsp.export_project_lsp_health_log` 命令、Go 菜单项和 Save Panel 入口；后续阶段已补清空确认、按 workspace retention、大小/时间轮转、filter DSL、自动崩溃恢复起点和 dashboard 起点，仍缺更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 279 继续补齐阶段 6 的 process health log 清空确认：`lsp.clear_project_lsp_health_log` 默认命令路径现在会在当前 workspace 有可清空记录时弹出确认 alert，取消不会删除日志；后续阶段已补按 workspace retention、大小/时间轮转、filter DSL、自动崩溃恢复起点和 dashboard 起点，仍缺更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 280 继续补齐阶段 6 的 process health log retention：JSONL append 后现在按 `workspaceRootURI` 各自保留最近 `maxPersistedEntries` 条记录，避免一个 workspace 的高频事件挤掉其它 workspace 的日志；后续阶段已补大小/时间轮转、filter DSL、自动崩溃恢复起点和 dashboard 起点，仍缺更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 281 继续补齐阶段 6 的 process health log 大小/时间轮转：`AttoProjectLspProcessHealthLogStore` 现在支持 `maxLogFileBytes` 与 `maxEntryAge`，append 后会按过期时间、workspace 条数和文件大小预算依次清理；后续阶段已补 filter DSL、自动崩溃恢复起点和 dashboard 起点，仍缺更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 282 继续补齐阶段 6 的 process health log filter DSL：`AttoProjectLspProcessHealthLogStore.queryRecent(...)` 支持 free text 以及 server/state/availability/process/pid/exit/signal/detail/stderr/tab/view/since/until 字段过滤，`AttoEditor.LSP.ProjectProcessHealthLog` 面板会随输入变化重新查询 store；后续阶段已补自动崩溃恢复起点和 dashboard 起点，仍缺更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 283 继续补齐阶段 6 的自动崩溃恢复起点：AttoEditor 记录 failed/exited process health status 时，会对仍打开、带 core tab id 且保存了 launch config 的 tab 复用既有 restart pipeline 自动重启 LSP session；后续阶段已补退避和 dashboard 起点，仍缺更深层 core-owned LSP ownership schema、跨 project recovery policy、用户配置和完整 dashboard 产品化。
- 阶段 284 继续补齐阶段 6 的 project LSP health dashboard 起点：AttoEditor 新增 `lsp.show_project_lsp_dashboard` 命令、Go 菜单项和 `AttoEditor.LSP.ProjectDashboard` 轻量面板，汇总 project status failures、process health history，并在内存 health 为空时回退展示 persisted process health log；后续阶段已补 project-level summary 行，仍缺更深层 core-owned LSP ownership schema、跨 project dashboard、分组/趋势/恢复配置和完整 dashboard 产品化。
- 阶段 285 继续补齐阶段 6 的自动恢复退避策略：AttoEditor 现在按 core tab id 记录自动恢复 attempts 与 `nextAllowedAt`，默认最多 3 次并按 5s/10s/20s 退避；healthy running status 会重置该 tab recovery state。仍缺更深层 core-owned LSP ownership schema、跨 project recovery policy、用户配置和完整 dashboard 产品化。
- 阶段 286 继续补齐阶段 6 的 project LSP health dashboard summary：`AttoEditor.LSP.ProjectDashboard` 面板现在先展示 summary 行，汇总 status failure 数、内存 process health 数、当前 workspace persisted log 数和 active recovery retry 状态；仍缺更深层 core-owned LSP ownership schema、跨 project dashboard、分组/趋势/恢复配置和完整 dashboard 产品化。
- 阶段 287 继续补齐阶段 6 的自动恢复用户配置：`AttoPreferences` 现在提供 LSP auto-restart enabled、max attempts 和 base delay seconds 三个 stored/env/default 偏好，Preferences 窗口的 Editor 页新增 LSP recovery 控件，AttoEditor 自动恢复路径会按这些偏好决定是否重启、最多重试几次以及退避基准。仍缺更深层 core-owned LSP ownership schema、跨 project/per-server recovery policy、dashboard 内联配置和完整 dashboard 产品化。
- 阶段 288 继续补齐阶段 6 的 dashboard 恢复策略可见性：`AttoEditor.LSP.ProjectDashboard` 在 summary 后新增 Recovery Policy 行，展示当前生效的 LSP auto-restart 开关、最大尝试次数和退避基准，便于把阶段 287 的用户配置与 health/status 事件放在同一个排查入口里。仍缺 dashboard 内联编辑、分组/趋势、跨 project/per-server recovery policy、更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 289 继续补齐阶段 6 的 dashboard server 分组起点：`AttoEditor.LSP.ProjectDashboard` 现在会在 Recovery Policy 后按 LSP server 聚合 health events 与 persisted logs，展示每个 server 的 health/log 数、failed 数和最新 process state，让用户先看 server-level 汇总再看单条 status/health 明细。仍缺真正趋势图、跨 project dashboard、per-server recovery policy、dashboard 内联编辑、更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 290 继续补齐阶段 6 的 dashboard trend 起点：`AttoEditor.LSP.ProjectDashboard` 现在会基于当前 workspace persisted process-health logs 的最新记录时间，新增 Trend 行展示最近 1 小时和 24 小时的 log/failed 计数。仍缺真正趋势图/图表、跨 project dashboard、per-server recovery policy、dashboard 内联编辑、更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 291 继续补齐阶段 6 的 dashboard 内联恢复配置起点：`AttoEditor.LSP.ProjectDashboard` 现在在 Recovery Policy 后新增 Recovery Action 行，可直接从 dashboard 启用/禁用全局 LSP auto-restart，并把结果写回 `AttoPreferences`。仍缺 per-server recovery policy、max attempts/base delay 的 dashboard 内联编辑、真正趋势图/图表、跨 project dashboard、更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 292 继续补齐阶段 6 的 dashboard 恢复参数内联编辑起点：`AttoEditor.LSP.ProjectDashboard` 现在在 Recovery Action 中新增 max attempts +1/-1 和 base delay +1s/-1s 操作，可直接从 dashboard 调整全局 LSP auto-restart 重试次数与退避基准并写回 `AttoPreferences`。仍缺 per-server recovery policy、自由输入/更完整设置表单、真正趋势图/图表、跨 project dashboard、更深层 core-owned LSP ownership schema 和完整 dashboard 产品化。
- 阶段 297 继续补齐阶段 6 的 core-owned project LSP launch metadata 消费起点：`MultiDocumentEditorUi` 已有 project-level LSP server launch metadata store / FFI / Swift wrapper，AttoEditor 现在会在打开/关闭 tab、session restore、workspace root 变更、project auto-start/restart 和显式切换到非 LSP 语言时，把打开 tabs 的 `lspServerConfig` 投影同步到 `MultiDocumentEditorUI.setProjectLspServers(...)`。这仍只是 launch metadata projection，不改变实际 server 启停路径；剩余缺口仍是 typed lifecycle 启停、更深层 ownership schema、跨独立 project session 策略和完整 dashboard 产品化。
- 阶段 298 继续补齐阶段 6 的 core-owned open document language metadata：`MultiDocumentEditorUi` tab snapshot 现在包含 `language_id`，UI FFI/Swift wrapper 可 set/query tab language id，AttoEditor 会在语言配置应用时把归一化 language key 同步到 core tab。这样 core 后续可以用 open tab document URI + language id + project LSP server configs 生成 typed lifecycle plan；当前仍不改变实际 LSP server 启停路径。
- 阶段 299 继续补齐阶段 7 的持久 LSP workbench panel 起点：Code Lens 现在除了 inline decorations、quick panel 和状态栏数量外，也有 `AttoCodeLensPanelController` 持久 panel，可通过 `lsp.show_code_lens_panel` / Go 菜单打开，支持稳定 AppKit identifiers、过滤、键盘选择和 Enter 执行；Code Lens refresh 后会同步更新已打开的 panel。仍缺统一 dock/workbench 容器、跨 tab/project Code Lens history 和更完整跨 result family panel 编排。
- 阶段 300 继续补齐阶段 7 的持久 LSP workbench panel 起点：Inlay Hints 现在除了 inline virtual text、点击 resolve 和 refresh HUD 外，也有 `AttoInlayHintPanelController` 持久 panel，可通过 `lsp.show_inlay_hints_panel` / Go 菜单打开，支持稳定 AppKit identifiers、过滤、键盘选择和 Enter resolve；Inlay Hints refresh 后会同步更新已打开的 panel。仍缺统一 dock/workbench 容器、跨 tab/project Inlay Hints history 和更完整跨 result family panel 编排。
- 阶段 301 继续补齐阶段 7 的持久 LSP workbench panel 起点：Document Links 现在除了 underline/hit-test/Cmd-click 和 refresh HUD 外，也有 `AttoDocumentLinkPanelController` 持久 panel，可通过 `lsp.show_document_links_panel` / Go 菜单打开，支持稳定 AppKit identifiers、过滤、键盘选择和 Enter open/resolve；Document Links refresh 后会同步更新已打开的 panel。仍缺统一 dock/workbench 容器、跨 tab/project Document Links history 和更完整跨 result family panel 编排。
- 阶段 302 继续补齐阶段 7 的持久 LSP workbench panel 起点：Document Colors 现在除了 transient command palette、color presentation quick panel 和 color picker 外，也有 `AttoDocumentColorPanelController` 持久 panel，可通过 `lsp.show_document_colors_panel` / Go 菜单打开，支持稳定 AppKit identifiers、swatch、过滤、键盘选择和 Enter 请求 color presentations；已有 document color 结果会在持久 panel 打开时同步更新。仍缺统一 dock/workbench 容器、跨 tab/project Colors history 和更完整跨 result family panel 编排。
- 阶段 303 继续补齐阶段 7 的持久 LSP workbench panel 起点：Call/Type Hierarchy children 结果现在除了 transient quick panel 外，也会记录最近一次 hierarchy result snapshot，并可通过 `lsp.show_hierarchy_panel` / Go 菜单打开 `AttoHierarchyPanelController` 持久 panel，支持稳定 AppKit identifiers、过滤、键盘选择和 Enter 跳转；已有 hierarchy quick result flow 会同步更新已打开的 panel。仍缺真正树状展开、children refresh、统一 dock/workbench 容器、跨 tab/project Hierarchy history 和更完整跨 result family panel 编排。
- 阶段 304 继续补齐阶段 7 的跨 result family workbench 编排起点：新增 `AttoLspWorkbenchPanelController` 作为统一 LSP Workbench 入口，可通过 `lsp.show_workbench_panel` / Go 菜单打开，汇总 Problems、Workspace Problems、Locations、Symbols、Workspace Outline、Code Lens、Inlay Hints、Document Links、Document Colors 和 Hierarchy 的当前状态/数量/可用性，并支持过滤、键盘选择和 Enter 打开对应持久在线 panel。仍缺真正内嵌 dock/workbench 容器、统一 pin/history/stale/error 数据模型和跨 tab/project result history。
- 阶段 305 继续补齐阶段 7 的统一 LSP Workbench lifecycle metadata：Workbench 的 Locations/Symbols 行现在消费既有 `AttoLspResultLifecycleEntry`，在数量之外显示 Fresh/Stale/Error、Result sequence、family 和 title，并会在当前 entry 被标记 stale/error 时刷新已打开的 Workbench。仍缺真正内嵌 dock/workbench 容器、统一 pin/history 数据模型、所有 result family 的统一 stale/error schema 和跨 tab/project result history。
- 阶段 306 继续补齐阶段 7 的统一 LSP Workbench lifecycle metadata：Workbench 的 Problems / Workspace Problems 行现在消费已有 diagnostics lifecycle entry，在数量之外显示 Fresh/Stale、Result sequence、family 和 title，并会在 status update 记录新 diagnostics lifecycle 后刷新已打开的 Workbench。仍缺真正内嵌 dock/workbench 容器、统一 pin/history 数据模型、所有 result family 的统一 stale/error schema 和跨 tab/project result history。
- 阶段 307 继续补齐阶段 7 的统一 LSP Workbench lifecycle metadata：Workbench 现在会把 Symbols 与 Workspace Outline 在共享 `lspSymbolResultStore` 中的 lifecycle entry 分流，Symbols 行只显示最近的非 Outline symbols entry，Workspace Outline 行显示 Outline entry 的 lifecycle metadata，且从 Workbench 打开 Symbols 不再误开 Workspace Outline。仍缺真正内嵌 dock/workbench 容器、统一 pin/history 数据模型、所有 result family 的统一 stale/error schema 和跨 tab/project result history。
- 阶段 308 继续补齐阶段 7 的统一 LSP Workbench lifecycle metadata：Workbench 的 Document Colors 行现在消费已有 `document_colors` result event，在颜色数量之外显示 Fresh、Result sequence、family 和 title；无结果时仍显示 request-on-open，旧无 event 缓存路径保留 cached fallback。仍缺真正内嵌 dock/workbench 容器、统一 pin/history 数据模型、所有 result family 的统一 stale/error schema 和跨 tab/project result history。
- 阶段 309 继续补齐阶段 7 的统一 LSP Workbench lifecycle metadata：Hierarchy result 现在会写入 App 层 `hierarchy` result event，Workbench 的 Hierarchy 行会在数量之外显示 Fresh、Result sequence、family 和 title；旧无 event snapshot 路径保留数量 fallback。仍缺真正内嵌 dock/workbench 容器、统一 pin/history 数据模型、所有 result family 的统一 stale/error schema、真正树状展开/children refresh 和跨 tab/project result history。
- 阶段 310 继续补齐阶段 7 的统一 LSP Workbench lifecycle metadata：Code Lens、Inlay Hints 和 Document Links 的成功结果现在会写入 App 层 `code_lens` / `inlay_hints` / `document_links` result event，Workbench 对应行会在 decorations 数量之外显示 Fresh、Result sequence、family 和 title；旧无 event decorations 路径保留数量 fallback。仍缺真正内嵌 dock/workbench 容器、统一 pin/history 数据模型、所有 result family 的统一 stale/error schema 和跨 tab/project result history。
- 阶段 311 继续补齐阶段 7 的统一 LSP Workbench stale metadata：App 层 `AttoLspResultLifecycleEvent` 现在携带 `state`，`AttoLspResultEventStream` 可按 family 标记最近事件 stale，当前文档编辑会让 Workbench 的 Code Lens、Inlay Hints、Document Links、Document Colors 和 Hierarchy event-backed 行从 Fresh 变为 Stale。仍缺 error propagation、统一 pin/history 数据模型、真正内嵌 dock/workbench 容器和跨 tab/project result history。
- 阶段 312 继续补齐阶段 7 的统一 LSP Workbench error metadata：App 层已有通用 `markCurrentLspEventResultError(...)`，Workbench 的 event-backed 行可显示 Error；Code Lens、Inlay Hints 和 Document Links 的 refresh unavailable/request failed/timeout/failed/result-error 路径会把最近 result event 标为 Error，Document Colors 与 Hierarchy 已具备同一通用 error state 展示能力；后续阶段 313 补齐真实请求流自动 error propagation。仍缺统一 pin/history 数据模型、真正内嵌 dock/workbench 容器和跨 tab/project result history。
- 阶段 313 继续补齐阶段 7 的统一 LSP Workbench error metadata：Document Colors 的 unavailable/request failed/timeout/take failed 分支，以及 Hierarchy 的 unavailable/position failed/prepare request failed/prepare timeout/take failed/children request failed/children timeout/take failed 分支，现在会把最近 `document_colors` / `hierarchy` result event 标为 Error；测试已改为已有结果后走真实 disabled request 路径验证 Workbench error 自动传播。仍缺统一 pin/history 数据模型、真正内嵌 dock/workbench 容器和跨 tab/project result history。
- 阶段 314 开始推进阶段 8 的 command palette source category：主命令 palette 现在可显示 command registry 分组，row 文本为 `Group - Title`，并且 fuzzy 搜索会同时匹配 title、group 和 command id；LSP/Project/Quick Open 等 quick/result palette 默认保持原有标题展示。仍缺 recent commands、宏录制/回放、package/plugin command 入口和更完整 Sublime keymap 语义矩阵。
- 阶段 315 继续推进阶段 8 的 command palette recent commands：App 现在维护 bounded in-memory recent command id 列表，统一 `executeCommand` / palette command wrapper 成功触发命令后会移动到最近列表顶部；主命令 palette 会把这些最近命令排在静态命令之前，重复触发去重，无效参数或未知/禁用命令不污染历史。仍缺跨启动持久化、参数 prompt/replay、宏录制/回放、package/plugin command 入口和更完整 Sublime keymap 语义矩阵。
- 阶段 316 继续推进阶段 8 的 command palette recent commands：最近 command id 现在通过 `AttoRecentCommandStore` 持久化，默认 App delegate 使用 `UserDefaults.standard` 跨启动恢复，测试构造 delegate 默认不读写全局 defaults；recent list 读取/保存会去空、去重并限制最大数量。仍缺参数 prompt/replay、宏录制/回放、package/plugin command 入口和更完整 Sublime keymap 语义矩阵。
- 阶段 317 继续推进阶段 8 的 command palette recent commands：最近命令持久化从 command id 扩展为 command record，包含最近一次 normalized typed arguments；主命令 palette 中排在前面的 recent 参数化命令可在无显式参数触发时 replay 最近参数，而菜单、keymap 和直接 `executeCommand(id:)` 无参数路径仍不会静默套用历史参数。仍缺通用参数 prompt UI、宏录制/回放、package/plugin command 入口和更完整 Sublime keymap 语义矩阵。
- 阶段 318 继续推进阶段 8 的 command palette 参数体验：主命令 palette 现在会根据 `AttoCommandSchema` 为参数化命令打开通用参数表单，支持 string/integer/number/boolean/json 和 choices 的基础输入、schema 校验和错误重试；recent command record 中的最近参数会作为表单初始值，用户可直接确认 replay 或编辑后运行。Quick Open/LSP result palette 等非主 palette 默认不启用该 prompt。仍缺宏录制/回放、package/plugin command 入口、Sublime overlay/panel 级参数 UI 复刻和更完整 Sublime keymap 语义矩阵。
- 阶段 319 继续推进阶段 8 的宏能力起点：AttoEditor 现在消费 command registry 的 `macroPolicy`，提供 in-memory last macro 录制/回放、`macro.toggle_recording` / `macro.replay_last` 命令、Tools 菜单和 `ctrl+q` / `ctrl+shift+q` 默认 keymap；录制会保留可录制命令的 command id 和显式 typed arguments，并过滤 `.promptRequired` / `.notRecordable` 命令，回放时不会递归录制。仍缺宏持久化文件、命名/多宏管理、Sublime `.sublime-macro` 文件兼容、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 320 继续推进阶段 8 的宏持久化起点：AttoEditor 现在会把 last command macro 保存为 Sublime 风格 `.sublime-macro` JSON array，并在默认 App delegate 启动时从 Application Support 下的 `Macros/Last Macro.sublime-macro` 恢复；文件项使用 `command` 和可选 `args`，基础 typed arguments 可跨 delegate 回放。仍缺命名/多宏管理、导入导出 UI、完整 Sublime `.sublime-macro` 运行语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 321 继续推进阶段 8 的命名宏管理起点：`AttoMacroStore` 现在支持命名 `.sublime-macro` 文件保存、读取和名称枚举；AttoEditor 新增 `macro.save_named` / `macro.replay_named` 参数化命令和 Tools 菜单入口，command palette 可提示 `name` 参数，按名回放 schema choices 来自当前宏目录。仍缺宏重命名/删除 UI、导入导出 UI、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 322 继续推进阶段 8 的命名宏管理：`AttoMacroStore` 现在支持命名 `.sublime-macro` 删除和重命名；AttoEditor 新增 `macro.rename_named` / `macro.delete_named` 参数化命令和 Tools 菜单入口，command palette 可选择已有宏名并输入新名称，相关命令在没有命名宏或正在录制时禁用。仍缺独立宏管理面板、删除确认 UI、导入导出 UI、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 323 继续推进阶段 8 的命名宏导入/导出：`AttoMacroStore` 现在支持外部 `.sublime-macro` 路径校验、导入和导出；AttoEditor 新增 `macro.import_file` / `macro.export_named` 参数化命令和 Tools 菜单入口，command palette 可输入源/目标路径与宏名。仍缺独立宏管理面板、原生文件选择流程、删除确认 UI、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 324 继续推进阶段 8 的命名宏导入/导出体验：`macro.import_file` 无参数执行现在会打开原生 open panel 选择 `.sublime-macro` 文件并用文件名作为默认宏名；`macro.export_named` 无参数执行会选择已有命名宏并打开 save panel 写出 `.sublime-macro`。参数化 command palette 路径仍保留显式 path/name 输入。仍缺独立宏管理面板、删除确认 UI、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 325 继续推进阶段 8 的命名宏删除体验：`macro.delete_named` 现在会在真正删除 `.sublime-macro` 前弹出 warning 确认；测试路径可注入 confirmation provider 覆盖取消/确认。仍缺独立宏管理面板、批量删除、回收站/undo、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 326 继续推进阶段 8 的命名宏批量管理：`macro.delete_named_batch` 现在可通过 JSON string array 参数一次删除多个命名 `.sublime-macro`，Tools 菜单也有对应入口；App 会去重、验证命名宏存在，并复用删除确认 UI 一次确认后批量删除。仍缺独立宏管理面板、回收站/undo、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 327 继续推进阶段 8 的命名宏删除恢复：`macro.undo_delete` 现在可恢复最近一次单宏或批量删除的命名 `.sublime-macro`；删除前会保存 command sequence 快照，恢复时不会覆盖之后新建的同名宏，恢复成功后清空 undo 记录。仍缺独立宏管理面板、多级删除历史、跨启动回收站、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 328 继续推进阶段 8 的命名宏删除恢复：`macro.undo_delete` 现在使用最多 20 条的 LIFO 删除历史，连续单宏删除和批量删除可按后进先出顺序逐步恢复；恢复失败时会保留历史以便处理同名冲突后重试。仍缺独立宏管理面板、跨启动回收站、删除历史 UI、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 329 继续推进阶段 8 的命名宏删除恢复：删除 undo 历史现在持久化到宏目录下的隐藏 JSON 文件，重新创建 App delegate 或重启后仍可继续 `macro.undo_delete`；空历史会移除该文件，且它不会出现在命名宏列表中。仍缺独立宏管理面板、可浏览回收站/删除历史 UI、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 330 继续推进阶段 8 的命名宏删除历史 UI：`macro.show_delete_history` 现在提供可过滤的删除历史 palette，按最近优先显示单删/批删记录并允许选择恢复非最近记录；恢复成功会从历史中移除对应记录。仍缺独立宏管理面板、批量选择/清理删除历史、完整可视化回收站、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 331 继续推进阶段 8 的命名宏删除历史管理：`macro.clear_delete_history` 现在提供显式清空删除历史命令和 Tools 菜单入口；清空前会独立确认，确认后移除内存 undo stack 和持久化隐藏 JSON，并关闭已打开的删除历史 palette。仍缺独立宏管理面板、删除历史单条清理/批量选择管理、完整可视化回收站、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 332 继续推进阶段 8 的命名宏删除历史管理：`macro.remove_delete_history_entry` 现在提供按最近优先 1-based index 移除指定删除历史记录的命令和 Tools 菜单入口；参数 schema 会按当前历史生成 choices，移除前会独立确认，确认后持久化并刷新/关闭删除历史 palette。仍缺独立宏管理面板、删除历史批量选择管理、完整可视化回收站、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 333 继续推进阶段 8 的命名宏删除历史管理：`macro.remove_delete_history_entries` 现在提供基于 command 参数的批量移除删除历史命令和 Tools 菜单入口；`indices` 参数使用最近优先的 1-based JSON 整数数组，移除前会独立确认，确认后持久化并刷新/关闭删除历史 palette。仍缺独立宏管理面板、可视化删除历史批量选择、完整可视化回收站、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 334 继续推进阶段 8 的命名宏删除历史管理：`macro.manage_delete_history` 现在提供独立 AppKit 删除历史管理面板，可按最近优先查看删除历史、单选恢复、多选移除和清空历史，并复用既有确认、持久化与 restore/remove/clear 逻辑；已打开的删除历史 palette 与管理面板会在历史变更后同步刷新或关闭。仍缺完整命名宏管理面板、完整可视化回收站、完整 Sublime `.sublime-macro` 扩展语义、plugin/package command runtime，以及命令内部 modal prompt 参数捕获。
- 阶段 335 开始推进阶段 9 的配置/capability DTO：AttoEditor 现在有 `AttoConfigurationSnapshot` / `AttoCapabilitySnapshot`，可把当前有效 editor/rendering/language/workspace 偏好、UI FFI ABI/features、LSP capability 摘要和 platform/App capability 编码为 typed Codable snapshot；JSON decode 会忽略 unknown future fields，测试覆盖 round trip 与兼容性。仍缺 Sublime settings scope/user-vs-workspace settings 合并、runtime overrides、完整迁移策略和面向第三方 host 的完整 capability negotiation。
- 阶段 336 继续推进阶段 9 的 settings 持久化/合并：AttoEditor 现在有 `AttoConfigurationSettings` partial overlay、`AttoConfigurationSettingsStore` 和 `AttoConfigurationResolution`，可保存/加载 user settings 与 workspace `.attoeditor/settings.json`，并按 base → user → workspace → runtime 合并配置；comment/LSP server policy 字典按 key 覆盖合并，JSON decode 保持 unknown future fields 兼容。仍缺 Sublime settings scope selector 规则、App 启动加载接线、Preferences UI、迁移/损坏文件备份和完整 capability negotiation。
- 阶段 337 继续推进阶段 9 的 App settings 接线：AttoEditor App 创建窗口和偏好重应用路径现在会按 workspace root 读取 user settings 与 workspace `.attoeditor/settings.json`，生成 resolved `AttoConfigurationSnapshot` 并应用 theme、font、ligatures、wrap 和 auto-pairs 到新建/已打开 editor。仍缺 Sublime settings scope selector 规则、Preferences UI、runtime override UI/持久化、迁移/损坏文件备份和完整 capability negotiation。
- 阶段 338 继续推进阶段 9 的 runtime override 接线：AttoEditor App 的配置解析路径现在会消费 process-local runtime `AttoConfigurationSettings`，按 base → user → workspace → runtime 顺序生成 resolved snapshot，并可把 runtime override 变更重应用到已打开 editor。仍缺 runtime override 的用户 UI/持久化、Sublime settings scope selector 规则、Preferences UI、迁移/损坏文件备份和完整 capability negotiation。
- 阶段 339 继续推进阶段 9 的 settings 迁移/恢复起点：`AttoConfigurationSettingsStore` 现在会在 settings 文件可读但 JSON/DTO decode 失败时，把原文件移动到同目录 `*.invalid` 备份路径，已有备份时使用递增后缀，并返回 `nil` 让 App 继续用下层配置启动。仍缺 schema migration、用户可见恢复 UI、Sublime settings scope selector 规则、Preferences UI、runtime override UI/持久化和完整 capability negotiation。
- 阶段 340 继续推进阶段 9 的 settings schema migration 起点：缺失 `schema_version` 的 settings 文件现在按 legacy v0 解码，读取时会备份原文件到 `*.v0.backup` 系列路径并写回 current schema JSON。仍缺跨 schema 字段语义转换、用户可见恢复 UI、Sublime settings scope selector 规则、Preferences UI、runtime override UI/持久化和完整 capability negotiation。
- 阶段 341 继续推进阶段 9 的 find/search options 配置接线：`AttoConfigurationSnapshot` / `AttoConfigurationSettings` 现在覆盖 find bar 的默认 `find_case_sensitive`、`find_whole_word` 和 `find_regex` 搜索选项，user/workspace/runtime settings 可按既有顺序覆盖；AttoEditor App 创建窗口和偏好重应用路径会把 resolved configuration 同步到 Find/Replace bar 的 Aa、Word、Regex 状态。仍缺 workspace Find in Files scope 配置、自定义 word boundary 规则、Preferences UI、runtime override UI/持久化、Sublime settings scope selector 规则、跨 schema 字段语义迁移和完整 capability negotiation。
- 阶段 342 继续推进阶段 9 的 workspace search scope 配置接线：`AttoWorkspacePreferenceSnapshot` / `AttoWorkspacePreferenceSettings` 现在覆盖 Find in Files 的默认 `find_in_files_default_scope`，支持 `opened_files` 与 `workspace`，并在 AttoEditor 窗口创建和偏好重应用时同步到 Search 侧栏的 Opened/Folder scope 控件。仍缺 workspace include/exclude glob、自定义 word boundary 规则、Preferences UI、runtime override UI/持久化、Sublime settings scope selector 规则、跨 schema 字段语义迁移和完整 capability negotiation。
- 阶段 343 继续推进阶段 9 的 workspace search glob 配置接线：`AttoWorkspacePreferenceSnapshot` / `AttoWorkspacePreferenceSettings` 现在覆盖 `workspace_search_include_globs` / `workspace_search_exclude_globs`，AttoEditor 的 Find in Files Folder/workspace scope 会在 `workspaceFilesProvider` 结果上应用这些 glob，支持常见 `*`、`?`、`**`、目录前缀和文件名 pattern。仍缺自定义 word boundary 规则、Preferences UI、runtime override UI/持久化、Sublime settings scope selector 规则、跨 schema 字段语义迁移和完整 capability negotiation。
- 阶段 344 继续推进阶段 9 的 Preferences UI 起点：全局 `AttoPreferences` 现在可持久化默认 Find case-sensitive / whole-word / regex 选项和 Find in Files 默认 scope，支持 env fallback，并把这些值写入 `AttoConfigurationSnapshot`；Preferences Editor 页面新增 Search 分组，用户可直接设置这些默认搜索行为。仍缺 workspace glob 的 Preferences UI、workspace/project scoped settings 编辑 UI、自定义 word boundary 规则、runtime override UI/持久化、Sublime settings scope selector 规则、跨 schema 字段语义迁移和完整 capability negotiation。
- 2026-08-01 阶段 6 第一部分已完成：Swift UI binding 新增一组 LSP interactive request/take raw result API，覆盖 declaration、type definition、implementation、references、completion、signature help、document symbols、workspace symbols。
- 阶段 6 第一部分在 Rust UI 内部把 hover/definition 的专用 result cache 泛化为按 LSP result slot 管理；document symbols response 会同步写入 core outline，供 `documentSymbolsJSON()` 读取。
- 2026-08-01 阶段 6 第二部分已完成：AttoEditor command palette 和 Go 菜单新增 LSP location commands，覆盖 go to definition/declaration/type definition/implementation/find references；cmd-click definition 也复用同一套 location request/poll/navigate 路径。
- 阶段 6 第二部分已让 references 多结果进入一个轻量可过滤结果 palette，单结果直接跳转；`AttoLspDefinitionParser` 新增多目标解析并补测试。阶段 57 已把 definition/declaration/type definition/implementation/references 的多结果处理统一到同一套 location results quick panel。
- 阶段 6 后续缺口中，基础持久在线 references/locations panel 已在阶段 114 补齐，locations/symbols result lifecycle store 起点已在阶段 121 补齐，locations/symbols history entry/envelope 元数据起点已在阶段 122 补齐；多数 result family typed payload 已在阶段 148-161 和阶段 173-174 补齐；阶段 247 已补单 root LSP `workspaceFolders` initialize / client response 起点，阶段 248 已补手动 `workspace/didChangeWorkspaceFolders` 通知与 response 列表更新链路，阶段 249 已补 core-owned root diff 到 AttoEditor active LSP didChange 的接线，阶段 250 已把 root change fan-out 扩展到所有 open-tab LSP sessions，阶段 251 已补保存/关闭路径的 `textDocument/didSave` / `textDocument/didClose` 通知，阶段 252 已补打开路径的 `textDocument/didOpen` 通知，阶段 253 已补 extra document 的 `textDocument/didChange` 通知，阶段 254 已补 shared-session root change 重复通知去重，阶段 255 已补 status snapshot 到 Swift/App status bar 的 workspace root 与 capability 可观测性，阶段 256 已补 LSP status changed state event 起点，阶段 257 已让 AttoEditor status bar 消费 active `lsp_status_changed` event payload，阶段 258 已扩大低层 sync/on-type/result apply failure 的 status event 覆盖，阶段 259 已让 project-level lifecycle drain 消费 MultiDocument LSP status failure event，阶段 260 已提供 project LSP status events 轻量面板入口，阶段 261 已把 server progress/activity 当前状态变化纳入去重后的 `lsp_status_changed`，阶段 262 已把 server process running/exited health 纳入 status snapshot 和事件流，阶段 263 已提供 active-tab manual server restart 起点，阶段 264 已提供按 core workspace tab 投影执行的 project-level manual restart 起点，阶段 265 已补关闭 owned LSP tab 时释放 handle 且不重复 didClose 的停止侧起点，阶段 266 已补最后一个 shared LSP handle drop 时调用 graceful exit 的 Rust 起点，阶段 267 已补 Rust/C ABI/Swift wrapper 的显式 LSP shutdown API，阶段 268 已补 workspace folder didChange 后 shared-session root alias/pool 更新；阶段 6 的 document open/change/save/close control-plane 链路已有基础覆盖，status bar 已能展示 server 状态、workspace root、activity、process health 和 compact capabilities，Swift/App 可从统一 state event stream 订阅并消费更多 LSP status 变化。仍缺 project open 自动批量 LSP session 启动、更完整的 shared-session root-set ownership 策略、少数 raw-only family typed envelope、更完整 progress/activity 历史模型、完整 dashboard 级 project status panel 和项目级命令模型。
- 2026-08-01 阶段 7 第一部分已完成：AttoEditor 新增基础 `view.split_right` 命令，通过 `EditorUI.cloneView` 为当前 tab 创建共享 buffer 的第二个 AppKit pane；这部分是当前可用的过渡实现，不应继续扩展成 Swift 自有 workspace/tab 模型。
- 2026-08-01 阶段 7 架构决策已更新：多文档、tab、workspace、project/session 级状态应使用 `editor-core` / `editor-core-ui` 一侧的 `Workspace` / `MultiDocumentEditorUi` 模型作为单一所有权来源，Swift 侧只做 AppKit 表现、命令转发、用户交互和持久化桥接；后续不在 Swift/AppKit 层新开一套长期独立的 workspace/tab/session 模型，也不继续给 Swift-only tab state 增加 preview/pin/dirty/close/search-all-tabs 等长期语义。
- 阶段 7 第一部分已让 split pane 复用主编辑器 chrome/theme/preferences/LSP/hover/cmd-click hook，并新增 first-responder hook 跟踪 active pane；AttoEditor command palette、View 菜单和默认 keymap 已接入。
- 阶段 7 第二部分已完成基础 pane 操作命令：`view.focus_next_pane`、`view.focus_previous_pane`、`view.close_pane`，并用 AppKit 组件测试覆盖 active pane 对 close target 的影响。
- 阶段 7 后续缺口中，`MultiDocumentEditorUi` 基础 Swift FFI 投影已在阶段 80 补齐，AttoEditor tab/pane lifecycle 到 core multi-document mirror 的迁移起点已在阶段 81 补齐，编辑文本/dirty/search-all-tabs 基础同步已在阶段 83 补齐，Find in Files 的 opened scope 已在阶段 84 开始消费 core open-tab search，split pane 数量/active pane session restore 已在阶段 85 补齐，pane move 已在阶段 86 补齐，dirty/close/resource-operation 保护条件已在阶段 87 改为消费 core dirty snapshot，tab movement 已在阶段 88 接入 core tab order，session snapshot 已在阶段 222 优先消费 core tab snapshot，opened-files/sidebar/tab-bar 投影已在阶段 223 优先消费 core tab snapshot，active-tab 查询已在阶段 224 优先消费 core active tab，AppKit content host 已在阶段 225 跟随 core active tab projection，close-other/close-right tab group 命令已在阶段 226 使用 core tab projection，close-all tab 命令已在阶段 227 使用 core tab projection，opened-files selection/open-existing 查找已在阶段 228 使用 core document URI projection，open-with-location 导航校验已在阶段 229 使用 core document URI projection，opened-scope Find in Files 结果 URL 已在阶段 230 使用 core document URI projection，LSP target navigation 已在阶段 231 使用 core document URI projection，WorkspaceEdit preview text lookup 已在阶段 232 使用 core document URI projection，WorkspaceEdit apply 前同步已在阶段 233 保留 core document URI projection，Document Symbols / Workspace Outline 已在阶段 234 使用 core document URI projection，resolved inlay hint text edit apply 已在阶段 235 使用 core document URI projection，Code Lens action title 已在阶段 239 使用 core document URI projection，window title 已在阶段 240 使用 core document URI projection，status bar metadata 已在阶段 241 使用 core document URI projection，language configuration 已在阶段 242 使用 core document URI projection，core tab title sync 已在阶段 243 使用 core document URI projection，close callback URL 已在阶段 244 使用 core document URI projection，WorkspaceEdit removed-tab callback URL 已在阶段 245 使用 core document URI projection，pane layout snapshot 已在阶段 246 增加 session schema 起点；仍缺完整 project/LSP lifecycle 迁移、完整 pane layout tree/session schema migration 和拖拽 tab 到 split 等更高层 workspace 产品语义。
- 阶段 236 已让 rename WorkspaceEdit context 使用 core document URI projection，继续收敛 Swift-only tab/document identity；仍缺完整 project/LSP lifecycle 迁移、pane layout tree/session schema migration 和拖拽 tab 到 split 等更高层 workspace 产品语义。
- 阶段 237 已让 keymap dynamic context 与 toggle comment 语言配置使用 core document URI projection，继续减少 command/keymap 路径对 Swift-only `tab.fileURL` 的依赖。
- 阶段 238 已让 active Problems/diagnostics snapshot、lifecycle scope 和 active diagnostic title 使用 core document URI projection，继续减少 diagnostics UI 路径对 Swift-only `tab.fileURL` 的依赖。
- 阶段 239 已让 Code Lens action title 使用 core document URI projection，继续减少 LSP auxiliary UI 对 Swift-only `tab.fileURL` 的依赖。
- 阶段 240 已让 window title 使用 core document URI projection，继续减少 AppKit chrome 对 Swift-only `tab.fileURL` 的依赖。
- 阶段 241 已让 status bar file size 和 Rust/LSP relevance 判断使用 core document URI projection，继续减少 AppKit chrome/status UI 对 Swift-only `tab.fileURL` 的依赖。
- 阶段 242 已让 indentation/comment language configuration application 使用 core document URI projection，继续减少 editor chrome/pane refresh 对 Swift-only `tab.fileURL` 的依赖。
- 阶段 243 已让 core tab title sync 使用 core document URI projection，继续减少 core mirror display metadata 对 Swift-only `tab.fileURL` 的依赖。
- 阶段 244 已让 close-tab notification/callback URL 使用 core document URI projection，继续减少 AppKit/sidebar lifecycle event 对 Swift-only `tab.fileURL` 的依赖。
- 阶段 245 已让 WorkspaceEdit core transaction / undo removed-tab close callback URL 使用 core document URI projection，继续减少 transaction projection lifecycle event 对 Swift-only `tab.fileURL` 的依赖。
- 阶段 246 已让 session tab snapshot 写出并优先恢复 `paneLayout` descriptor，继续把 split/view session 表达从 Swift-only `paneCount` 过渡到可承接 core view/layout projection 的 schema。
- 2026-08-01 阶段 8 已完成：AttoEditor 新增 LSP document/workspace symbols quick panel 主路径，命令 `lsp.document_symbols` / `lsp.workspace_symbols` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspSymbolParser`，覆盖 DocumentSymbol、SymbolInformation、WorkspaceSymbol 常见结果形态。
- 阶段 8 后续缺口中，基础错误/超时/空结果反馈已在阶段 68 补齐，最近结果 snapshot 和 reopen command 已在阶段 72 补齐，workspace symbol 增量查询面板已在阶段 93 补齐，workspace symbol kind 分组/稳定排序已在阶段 98 补齐，基础持久在线 Outline/Symbols panel 已在阶段 115 补齐，locations/symbols result lifecycle store 起点已在阶段 121 补齐，symbols history entry/envelope 元数据起点已在阶段 122 补齐；仍缺覆盖所有 LSP result 的更深层 lifecycle/event model。
- 2026-08-01 阶段 9 已完成：AttoEditor 新增 LSP signature help popup 主路径，命令 `lsp.signature_help` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspSignatureHelpFormatter`，覆盖 SignatureHelp、activeSignature、activeParameter、ParameterInformation string/range label 和 documentation 常见结果形态。
- 阶段 9 后续缺口中，trigger characters / 自动弹出已在阶段 18 补齐，active parameter 富格式高亮已在阶段 19 补齐，typed result model 和空结果/错误展示已在阶段 20 补齐。
- 2026-08-01 阶段 10 已完成：AttoEditor 新增 LSP completion popup 主路径，命令 `lsp.completion` 已接入 command palette、Go 菜单和默认 keymap；新增 `AttoLspCompletionParser` 和 caret-anchored completion list，覆盖 CompletionList/CompletionItem、TextEdit、InsertReplaceEdit insert range、additionalTextEdits、snippet insertion 和 fallback identifier-prefix replacement。
- 阶段 10 后续缺口中，rich documentation/detail preview 已在阶段 21 补齐，commitCharacters 提交行为已在阶段 22 补齐，server triggerCharacters 自动触发已在阶段 23 补齐，增量过滤已在阶段 24 补齐，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐，阶段 196-221 已补 core transaction 起点、root-gated 本地文件覆盖、App apply helper 主路径、基础 preview/confirmation、专用 diff preview panel 起点和未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义和统一 feedback/状态订阅模型。
- 2026-08-01 阶段 11 已完成：Swift UI binding 新增 rename / prepare rename / code action / code action resolve 的 raw async request/take API，覆盖 Rust `editor-core-lsp` 已有的 `textDocument/prepareRename`、`textDocument/rename`、`textDocument/codeAction` 和 `codeAction/resolve` 请求路径。
- 2026-08-01 阶段 11 第二部分已完成：Swift UI binding 新增 `lspApplyWorkspaceEditJSON(_:documentURI:)`，通过 UI FFI 把 `WorkspaceEdit` 中命中当前文档 URI 的 `TextEdit` 应用到当前 buffer，并返回 applied/skipped/documents summary，覆盖 rename/code action 返回 edit 后的当前文档应用基础链路。
- 2026-08-01 阶段 11 第三部分已完成：AttoEditor App 新增 `lsp.rename` 主路径，包含 command palette、Go 菜单、F2 keymap、rename 输入框、候选名预填、LSP rename request/poll，以及把返回的当前文档 WorkspaceEdit 应用到 active tab 并标记 dirty。
- 2026-08-01 阶段 11 第四部分已完成：Swift UI binding 新增 `workspace/executeCommand` raw request/take API；AttoEditor App 新增 `lsp.code_actions` 主路径，包含 command palette、Go 菜单、Cmd+. keymap、code action quick panel、`codeAction/resolve` 轮询、当前文档 WorkspaceEdit 应用和 command payload 执行。
- 阶段 11 后续缺口中，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，code action diagnostics context 已在阶段 26 补齐，code action kind/filter 产品化已在阶段 27 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，code action command payload 执行结果/错误展示已在阶段 48 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐，code action result/resolve typed payload wrapper 和 App 主路径消费已在阶段 152 补齐，阶段 196-221 已补 core WorkspaceEdit transaction 起点、root-gated 本地文件覆盖、App apply helper 主路径、基础 preview/confirmation、专用 diff preview panel 起点和未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
- 2026-08-01 阶段 12 已完成：Swift UI binding 新增 `completionItem/resolve` raw request/take API；AttoEditor completion popup 在 commit 时会先请求 resolve，使用 resolved CompletionItem 中的 `textEdit` / `additionalTextEdits` / snippet payload，resolve 不可用或超时时回退到原始 completion item。
- 阶段 12 后续缺口中，rich documentation/detail preview 已在阶段 21 补齐，commitCharacters 提交行为已在阶段 22 补齐，server triggerCharacters 自动触发已在阶段 23 补齐，增量过滤已在阶段 24 补齐，跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐，阶段 196-221 已补 core transaction 起点、root-gated 本地文件覆盖、App apply helper 主路径、基础 preview/confirmation、专用 diff preview panel 起点和未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义和统一 feedback/状态订阅模型。
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
- 阶段 17 已新增 `AttoLspRenameSupport.DialogSeed` / `dialogSeed(...)`，按 LSP UTF-16 line/character range 从当前文档提取 rename 文本，并在 prepareRename 无响应或不可解析时回退到当前选区/identifier 逻辑；跨文件 WorkspaceEdit 摘要预览已在阶段 25 补齐，打开 tab / 本地 `file://` 文档 text edits 应用已在阶段 47 补齐，本地未打开文件的 resource operations 已在阶段 55 补齐，打开 tab 相关 resource operations 已在阶段 59 补齐，rename typed result model 已在阶段 151 补齐，阶段 196-221 已补 core WorkspaceEdit transaction 起点、root-gated 本地文件覆盖、App apply helper 主路径、基础 preview/confirmation、专用 diff preview panel 起点和未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
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
- 2026-08-01 阶段 41 已完成：AttoEditor 新增 `lsp.problems` 命令、Go 菜单入口和 Problems quick panel，最初直接消费 active derived-state store 的 typed diagnostics；无 panel window 时可跳转到第一个 diagnostic，测试覆盖命令注册、菜单入口和 diagnostic range 导航。阶段 127 已把 active-tab Problems quick/persistent list 改为消费 workspace/active diagnostics 统一模型。
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
- 2026-08-02 阶段 113 已完成：AttoEditor App key-down dispatcher 现在会按 active editor 状态动态解析 keymap context，而不是只使用启动时空 context 的缓存结果。运行时 context 注入 `has_active_editor`、`selection_empty`、`num_selections`、`has_multiple_selections`、`selector`、`syntax`、`file_name`、`file_extension`、dirty/tab/pane 摘要；阶段 237 已让 `selector` / `syntax` / file name / extension 跟随 core document URI projection。local key monitor 现在可按当前 context 触发单键 binding 和 chord，并使用同一动态 keymap 的 `args`。测试覆盖无 active editor 不命中、active `.swift` 非空选区命中、selector/file extension context、core-projected `.py` context 和动态 args 执行。
- 2026-08-02 阶段 114 已完成：AttoEditor 新增持久在线的 LSP Locations/References panel，和一次性 quick panel 分离。location/reference 结果现在会记录到可重复显示的 `AttoLspLocationPanelController`，panel 带过滤框、稳定 accessibility identifiers、可在打开状态下随新结果更新，并通过 `lsp.show_locations_panel` command / Go 菜单入口重新打开最后结果；测试覆盖 command 注册、panel identifiers/filtering、快照保持和新结果自动刷新。
- 2026-08-02 阶段 115 已完成：AttoEditor 新增持久在线的 LSP Outline/Symbols panel，复用现有 document/workspace symbols typed snapshot 和导航路径。symbol 结果现在可通过 `AttoLspSymbolPanelController` 以持久 panel 展示、过滤和打开；panel 带稳定 accessibility identifiers，可随新 document/workspace symbol 结果自动刷新，并通过 `lsp.show_symbols_panel` command / Go 菜单入口重新打开最后结果；测试覆盖 command/menu 注册、panel identifiers/filtering、快照保持和新结果自动刷新。
- 2026-08-02 阶段 116 已完成：AttoEditor 新增 active-tab 持久 Problems panel，复用 active derived-state store 的 typed diagnostics 和现有 diagnostic navigation 路径。`AttoProblemsPanelController` 提供可过滤、可重复显示的 panel，带稳定 accessibility identifiers；打开后会随 `updateStatusBar()` 的 derived-state refresh 自动刷新，并通过 `lsp.show_problems_panel` command / Go 菜单入口打开。测试覆盖 command/menu 注册、panel identifiers/filtering、diagnostic 打开和 diagnostics 刷新。
- 2026-08-02 阶段 117 已完成：AttoEditor 新增 workspace Problems store/panel。`AttoWorkspaceProblemsStore` 会缓存 `workspace/diagnostic` typed reports，合并 `full` / `unchanged` result 并为下一次请求提供 `previousResultIds`；workspace diagnostics result 会刷新持久在线 workspace Problems panel，并通过 `lsp.show_workspace_problems_panel` command / Go 菜单入口重新打开。阶段 123 已把该 store 的主路径改为消费 core-owned `MultiDocumentEditorUi` workspace diagnostics snapshot，Swift 本地缓存保留为迁移期 fallback。
- 2026-08-02 阶段 118 已完成：EditorCoreUI minimap 新增 diagnostic marker API 和绘制路径，AttoEditor 的 active derived diagnostics 会在 `updateStatusBar()` 刷新时同步成当前 tab 所有 panes 的 minimap markers。测试覆盖 marker logical-line 到 minimap rect 的映射，以及 active diagnostics 到 minimap markers 的 App 层投影；workspace diagnostics marker 聚合起点已在阶段 124 迁到 core-backed marker snapshot。
- 2026-08-02 阶段 119 已完成：EditorCoreUI 新增 gutter diagnostic marker API，并在 `EditorCoreSkiaView` 上用透明 overlay 绘制 active-tab diagnostics 的 gutter 图标；AttoEditor 会在 `updateStatusBar()` 刷新时把 active derived diagnostics 同步到当前 tab 所有 panes 的 gutter markers。测试覆盖 marker char-offset 到 gutter rect 的映射，以及 active diagnostics 到 gutter markers 的 App 层投影；workspace diagnostics marker 聚合起点已在阶段 124 迁到 core-backed marker snapshot。
- 2026-08-02 阶段 120 已完成：AttoEditor workspace diagnostics store 会把 `workspace/diagnostic` 结果投影到已打开 tab 的 minimap/gutter markers；active tab 合并 active derived diagnostics 与 workspace diagnostics，非 active open tabs 消费 workspace store。`full` report 更新或清空后会刷新 open-tab markers。当前仍是 App 层 workspace store 到 open-tab UI 的投影，core-owned project 级 Problems/marker 归属仍未完成。
- 2026-08-02 阶段 121 已完成：AttoEditor 新增通用 `AttoLspResultLifecycleStore`，把 locations/references 与 document/workspace symbols 的 current result、bounded history 和 reopen/persistent-panel refresh 逻辑统一到一个 lifecycle store 起点。当前仍只覆盖已有 locations/symbols 结果族，尚未形成所有 LSP result 的统一 envelope/event model。
- 2026-08-02 阶段 122 已完成：`AttoLspResultLifecycleStore` 的 history 从裸 snapshot 升级为 typed lifecycle entry，记录 sequence、family、title、recordedAt 和 snapshot；locations/references 与 document/workspace symbols 的 history palette 现在从 entry reopen，并保留 `current` / `history` 兼容投影。后续阶段已把更多 App result family 接入事件流，在阶段 138 补齐 `EditorUi` core-owned result slot event stream 起点，在阶段 139 补齐 MultiDocument/project 级 result 聚合起点，在阶段 140 补齐 `EditorUi` request lifecycle event stream 起点，在阶段 141 补齐 MultiDocument/project 级 request 聚合起点，在阶段 142 补齐显式 cancel/timeout lifecycle，并在阶段 143 补齐 on-type formatting request lifecycle；当前仍缺更完整 typed envelope。
- 2026-08-02 阶段 123 已完成：`MultiDocumentEditorUi` 新增 core-owned workspace diagnostics store，可解析并合并 LSP `workspace/diagnostic` 的 `full` / `unchanged` reports、`relatedDocuments`、diagnostic severity/code/source/message 和 `previousResultIds`；`editor-core-ui-ffi` / Swift `MultiDocumentEditorUI` 新增 apply/snapshot/previousResultIds/clear API 和 runtime feature flag。AttoEditor 的 `AttoWorkspaceProblemsStore` 现在优先消费 core-owned snapshot，Swift 本地 parser/store 只作为迁移期 fallback。阶段 124 已继续补齐 core-backed workspace diagnostic marker snapshot 起点；当前仍缺 workspace diagnostics 与 active derived diagnostics 的统一 derived-state model，以及更通用的 project/LSP event stream。
- 2026-08-02 阶段 124 已完成：`MultiDocumentEditorUi` workspace diagnostics store 新增 project-level marker snapshot，按 core-owned diagnostics 生成 URI、LSP 起点和 severity 归一化后的 marker projections；UI FFI / Swift `MultiDocumentEditorUI` 新增 marker snapshot JSON/API。AttoEditor workspace minimap/gutter marker 投影现在先消费 core-backed marker projections，再在 AppKit 层按当前 buffer 文本完成 UTF-16 到 char offset 转换。当前仍缺 workspace diagnostics 与 active-tab derived diagnostics 的统一 derived-state model、统一刷新/过期策略和更通用的 project/LSP event stream。
- 2026-08-02 阶段 125 已完成：AttoEditor 新增 `AttoDiagnosticsModel` 和 `AttoUnifiedDiagnosticsSnapshot`，把 active-tab diagnostics 与 core-backed workspace diagnostic marker projections 的 URI 过滤、UTF-16 坐标转换、severity 保留和去重逻辑集中到一个 typed model；`AttoEditorAreaViewController` marker 刷新路径改为消费该统一模型。
- 2026-08-02 阶段 126 已完成：`AttoDiagnosticsModel` 继续扩展为 workspace/active diagnostics 统一快照，除 marker projections 外还产出 `AttoUnifiedDiagnosticProblem` 列表和 `problemsStatusText`；AttoEditor status bar 现在用统一快照统计 active-tab diagnostics 与 core-backed workspace diagnostics，`workspace/diagnostic` 结果刷新也会同步刷新状态栏。阶段 127 已继续把 active-tab Problems list 接到同一统一快照。
- 2026-08-02 阶段 127 已完成：`AttoUnifiedDiagnosticProblem` 保留 active/workspace 原始 payload、code/source/severity 和导航目标；`AttoProblemsPanelController` 新增统一 problems 输入，同时保留旧 active/workspace API。AttoEditor active-tab Problems quick panel 与持久 Problems panel 现在消费同一份 workspace/active diagnostics 快照，会把当前文件的 workspace diagnostics 与 active diagnostics 合并展示、刷新和跳转，并过滤其它文件的 workspace diagnostics。阶段 238 已让该 active-tab URL 过滤、diagnostics lifecycle scope/title 和 active diagnostic title 跟随 core document URI projection。
- 2026-08-02 阶段 128 已完成：`AttoDiagnosticsModel.workspaceProblems(_:)` 新增 workspace-wide unified problem 投影，按 URI 保留跨文件同位置/同文案 diagnostics，不再在全局列表中误去重；AttoEditor workspace Problems panel 现在也消费 unified problems 输入，并继续保留 workspace target 导航、过滤和刷新行为。当前仍缺 diagnostics lifecycle/event、统一刷新/过期策略和更通用的 project/LSP event stream。
- 2026-08-02 阶段 129 已完成：AttoEditor 新增 `AttoDiagnosticsLifecycleSnapshot`，并复用 `AttoLspResultLifecycleStore` 记录 diagnostics active/workspace lifecycle entries；entry 现在带 sequence、family、title、recordedAt、scope、problems、marker projections 和 status text。`recordIfChanged` 会跳过连续相同 diagnostics snapshot，避免 viewport/status bar 重复刷新制造伪事件。阶段 130 已继续补齐按 sequence 增量查询。
- 2026-08-02 阶段 130 已完成：`AttoLspResultLifecycleStore` 新增 `latestSequence` 和 `entries(after:)`，AttoEditor diagnostics lifecycle 暴露按 sequence 增量查询能力；UI/后续刷新策略可以用 cursor 消费 diagnostics active/workspace events，而不必重复扫描整段 history。测试覆盖重复 status bar 刷新不产生新 diagnostics event，以及 workspace diagnostics 更新后只产生 workspace + active 两条增量事件。当前仍缺 core-owned / 跨 result family event stream、统一刷新/过期策略和 project/LSP 生命周期归属。
- 2026-08-02 阶段 131 已完成：`AttoDiagnosticsLifecycleSnapshot` 新增 `staleReason` / `isStale`，AttoEditor 会在 active tab 文本变化后把当前 diagnostics lifecycle 标记为 `document_edited` stale，并在后续 diagnostics snapshot 变化时清除；workspace diagnostics 发起 refresh 后会记录 `workspace_refresh_requested` stale lifecycle，结果落地后清除。测试覆盖 active diagnostics 编辑后 stale、收到新版 diagnostics 后恢复 fresh。当前仍缺 core-owned / 跨 result family event stream、统一 request lifecycle 和 project/LSP 生命周期归属。
- 2026-08-02 阶段 132 已完成：AttoEditor 新增 `AttoLspResultEventStream` 和 `AttoLspResultLifecycleEvent`，在 locations、symbols 和 diagnostics 三个已迁入 lifecycle store 的 result family 上生成统一全局 sequence 事件；事件保留 family/title/recordedAt/sourceSequence 和轻量 typed payload，可通过 cursor 增量消费跨 family 结果变化。测试覆盖 stream bounded history、locations/symbols/diagnostics record 点和 events-after 查询。阶段 138 已继续补齐 `EditorUi` core-owned result slot event stream，阶段 139 已继续补齐 MultiDocument/project 级 result 聚合起点，阶段 140 已继续补齐 `EditorUi` request lifecycle event stream 起点，阶段 141 已继续补齐 MultiDocument/project 级 request 聚合起点，阶段 142 已继续补齐显式 cancel/timeout lifecycle，阶段 143 已继续补齐 on-type formatting request lifecycle，阶段 156 已补齐 pull diagnostics typed envelope；当前仍缺更完整状态变更订阅模型。
- 2026-08-02 阶段 133 已完成：`AttoLspResultLifecycleEvent.Payload` 新增 `codeActions`，`AttoLspResultEventStream` 支持没有独立 source lifecycle store 的 result family；AttoEditor code action result 过滤后会记录 `code_actions` 事件，保留 `onlyKinds` 和 item count，并继续保持原 quick panel / single-result apply 行为。测试覆盖 raw code action result 到 command palette 和统一事件流的接线路径。阶段 138 已继续补齐 `EditorUi` core-owned result slot event stream，阶段 139 已继续补齐 MultiDocument/project 级 result 聚合起点，阶段 140 已继续补齐 `EditorUi` request lifecycle event stream 起点，阶段 141 已继续补齐 MultiDocument/project 级 request 聚合起点，阶段 142 已继续补齐显式 cancel/timeout lifecycle，阶段 143 已继续补齐 on-type formatting request lifecycle，阶段 156 已补齐 pull diagnostics typed envelope；当前仍缺其余 family typed payload 和状态变更订阅模型。
- 2026-08-02 阶段 134 已完成：`AttoLspResultLifecycleEvent.Payload` 新增 `completion`，AttoEditor completion result 展示 popup 时会记录 `completion` 事件，保留候选数量；completion request 主路径和测试注入路径共用 selection/fallback range context 构造。阶段 148 已补齐 Swift UIFFI completion result / resolve item typed payload wrapper，阶段 149 已把 completion App 主路径迁移到 typed payload，阶段 196-221 已补 core WorkspaceEdit transaction 起点、root-gated 本地文件覆盖、App apply helper 主路径、基础 preview/confirmation、专用 diff preview panel 起点和未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；当前仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
- 2026-08-02 阶段 135 已完成：`AttoLspResultLifecycleEvent.Payload` 新增 `rename`，AttoEditor rename result 会在 WorkspaceEdit 应用后记录 `rename` 事件，保留 newName、document/resource operation 数量和 applied 结果；poll 路径和测试注入路径共用同一 apply+record helper。测试覆盖 rename WorkspaceEdit 应用到当前文档并写入统一事件流。阶段 151 已补齐 rename typed result model，阶段 196-221 已补 core WorkspaceEdit transaction 起点、root-gated 本地文件覆盖、App apply helper 主路径、基础 preview/confirmation、专用 diff preview panel 起点和未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；当前仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义和 rename request lifecycle。
- 2026-08-02 阶段 136 已完成：`AttoLspResultLifecycleEvent.Payload` 新增 `documentColors` / `colorPresentations`，AttoEditor document color 和 color presentation result 展示路径会写入统一事件流，保留模式和候选数量。测试覆盖 document color result panel、color presentation result panel 和 events-after 查询。当前仍缺持久颜色面板、多文档/workspace 颜色聚合和统一 request lifecycle。
- 2026-08-02 阶段 137 已完成：`MultiDocumentEditorUi` 的 core-owned workspace diagnostics store 新增 bounded event stream，记录 `apply` / `clear` sequence、family、title、document/diagnostic/marker count，并通过 UI FFI 和 Swift `MultiDocumentEditorUI` 暴露 `latestEventSequence` 与 `events(after:)` 查询；新增 `workspaceDiagnosticsEvents` feature flag。测试覆盖 Rust core store、C ABI、Swift wrapper 和 runtime compatibility。阶段 138 已继续补齐 `EditorUi` core-owned LSP result slot event stream，阶段 139 已继续补齐 MultiDocument/project 级 result 聚合起点，阶段 140 已继续补齐 `EditorUi` request lifecycle event stream 起点，阶段 141 已继续补齐 MultiDocument/project 级 request 聚合起点，阶段 142 已继续补齐显式 cancel/timeout lifecycle，阶段 143 已继续补齐 on-type formatting request lifecycle，阶段 156 已补齐 pull diagnostics typed envelope；当前仍缺更完整状态变更订阅模型。
- 2026-08-02 阶段 138 已完成：`EditorUi` 新增 core-owned LSP result slot bounded event stream，所有经 `LspResultSlot::from_response_method` 进入 Rust UI 的 interactive result response 都会记录 sequence、family、slot、method、view id、request id、success/empty/error、result JSON 长度和轻量 error metadata；UI FFI / Swift `EditorUI` 新增 `lspResultEventsLatestSequence()`、`lspResultEventsJSON(after:)`、`lspResultEvents(after:)` 和 `lspResultEvents` feature flag。阶段 139 已继续补齐 MultiDocument/project 级 result event 聚合起点，阶段 140 已继续补齐 request start/completion/stale 起点，阶段 141 已继续补齐 MultiDocument/project 级 request 聚合起点，阶段 142 已继续补齐 request cancel/timeout 事件，阶段 143 已继续补齐 on-type request lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 139 已完成：`MultiDocumentEditorUi` 新增 core-owned LSP result event 聚合 store，可跨 tab / split view 汇总每个 `EditorUi` 的 result slot event，并保留 tab id、view index、view id、source sequence、family/slot/status/error metadata；UI FFI / Swift `MultiDocumentEditorUI` 新增 `lspResultEventsLatestSequence()`、`lspResultEventsJSON(after:)`、`lspResultEvents(after:)` 和 `multiDocumentLSPResultEvents` feature flag。阶段 140 已继续补齐 `EditorUi` request lifecycle event stream 起点，阶段 141 已继续补齐 MultiDocument/project 级 request 聚合起点，阶段 142 已继续补齐 request cancel/timeout 事件，阶段 143 已继续补齐 on-type request lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 140 已完成：`EditorUi` 新增 core-owned LSP request lifecycle bounded event stream，常规 interactive result request 发起时记录 `started/pending`，响应完成时记录 `completed/success|empty|error` 并关联 result event sequence，过期响应记录 `completed/stale`，slot 不匹配记录 `completed/mismatched`；UI FFI / Swift `EditorUI` 新增 `lspRequestEventsLatestSequence()`、`lspRequestEventsJSON(after:)`、`lspRequestEvents(after:)` 和 `lspRequestEvents` feature flag。阶段 141 已继续补齐 MultiDocument/project 级 request 聚合起点，阶段 142 已继续补齐显式 cancel/timeout lifecycle，阶段 143 已继续补齐 on-type request lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 141 已完成：`MultiDocumentEditorUi` 新增 core-owned LSP request lifecycle event aggregation store，可跨 tab / split view 汇总每个 `EditorUi` 的 request lifecycle events，并保留 tab id、view index、view id、source sequence、result sequence、family/slot/phase/status/error metadata；UI FFI / Swift `MultiDocumentEditorUI` 新增 `lspRequestEventsLatestSequence()`、`lspRequestEventsJSON(after:)`、`lspRequestEvents(after:)` 和 `multiDocumentLSPRequestEvents` feature flag。测试覆盖 Rust core 聚合、C ABI 空快照、Swift wrapper 空快照和 runtime compatibility。阶段 142 已继续补齐显式 cancel/timeout lifecycle，阶段 143 已继续补齐 on-type request lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 142 已完成：`EditorUi` request lifecycle events 新增显式 `canceled` / `timeout` completion 状态；Rust API 新增 `lsp_cancel_request(_:)` 和 `lsp_mark_request_timed_out(_:)`，前者会对已启用的 LSP session 尝试发送 `$/cancelRequest` 并记录本地 lifecycle，后者用于 host-side timeout 后关闭 pending request。UI FFI / Swift `EditorUI` 新增 `editor_core_ui_ffi_editor_ui_lsp_cancel_request`、`editor_core_ui_ffi_editor_ui_lsp_mark_request_timed_out`、`lspCancelRequest(_:)`、`lspMarkRequestTimedOut(_:)` 和 `lspRequestCancelTimeoutEvents` feature flag。测试覆盖 Rust core cancel/timeout 事件、C ABI unknown-request false path、Swift wrapper false path 和 runtime compatibility。阶段 143 已继续补齐 on-type request lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 143 已完成：on-type formatting 请求纳入 `EditorUi` core-owned request lifecycle event stream，发起时记录 `started/pending`，response 进入 `completed/success|empty|error|stale`，并复用阶段 142 的 cancel/timeout closure；事件使用 `family=formatting`、`slot=on_type_formatting`、`method=textDocument/onTypeFormatting`，MultiDocument/project request 聚合会自动包含这些事件。测试覆盖 on-type error、empty、stale 和 timeout lifecycle。阶段 144 已继续补齐 UI auxiliary derived-state request lifecycle；阶段 146 已继续补齐 diagnostics notification/pull lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 144 已完成：`EditorUi` 直接发起的 auxiliary derived-state LSP 请求纳入 core-owned request/result lifecycle，包括自动刷新路径中的 `textDocument/inlayHint`、`textDocument/codeLens` 和 `textDocument/documentLink`。这些请求现在发起时记录 `started/pending`，响应进入 `completed/success|empty|error|stale|mismatched`，并可通过既有 `EditorUI.lspRequestEvents(after:)`、`EditorUI.lspResultEvents(after:)` 和 MultiDocument/project 聚合 wrapper 在 Swift 侧观察；本阶段未新增 ABI 函数或 feature flag。测试覆盖 auxiliary refresh 产生 started event，以及 inlay/document links response 产生 request/result completion event 并清理 in-flight 状态。阶段 145 已继续补齐 `editor-core-lsp` 内部自动 semantic tokens / folding ranges refresh 的 request id/event 外显；阶段 146 已继续补齐 diagnostics refresh lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 145 已完成：`editor-core-lsp` 内部自动派生状态刷新新增 `LspEvent::DerivedRequest`，覆盖 `textDocument/semanticTokens/full`、`textDocument/semanticTokens/full/delta` 和 `textDocument/foldingRange` 的 `started/pending` 与 `completed/success|empty|error|stale` 生命周期；`EditorUi` 会把这些事件投影进既有 core-owned request lifecycle event stream，slot 为 `semantic_tokens_full`、`semantic_tokens_delta` 和 `folding_ranges`，Swift 侧可继续通过既有 `EditorUI.lspRequestEvents(after:)` / MultiDocument 聚合 wrapper 观察。本阶段未新增 ABI 函数或 feature flag。测试覆盖 folding 自动刷新 lifecycle，以及 semantic/folding derived request event 到 UI request events 的投影。阶段 146 已继续补齐 diagnostics 的 notification/pull refresh lifecycle；阶段 148-161 已继续补齐多数 typed payload，阶段 173-174 已补齐 inlay/document links manual typed wrapper 与 resolve wrapper；当前仍缺统一状态订阅和少数 raw-only family typed envelope。
- 2026-08-02 阶段 146 已完成：`publishDiagnostics` notification 现在也会由 `editor-core-lsp` 发出 `LspEvent::DerivedRequest`，以 `method=textDocument/publishDiagnostics`、`id=0` 表示无 JSON-RPC request id，并记录 `completed/success|empty|stale`；`EditorUi` 新增 `publish_diagnostics` slot，把该 notification update 投影到既有 request lifecycle event stream，且按 document URI 过滤，避免共享 LSP session 中其它文档的 diagnostics 污染当前 view。显式 `textDocument/diagnostic` / `workspace/diagnostic` pull request 原本已由 `DocumentDiagnostic` / `WorkspaceDiagnostic` slot 记录 started/completed；本阶段不新增 ABI 函数或 feature flag，Swift 继续通过既有 `EditorUI.lspRequestEvents(after:)` / MultiDocument 聚合 wrapper 观察。阶段 156 已补齐 pull diagnostics typed envelope；当前仍缺状态变更订阅模型。
- 2026-08-02 阶段 147 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspEventFamily`、`EcuLspResultSlot`、`EcuLspResultStatus`、`EcuLspRequestPhase`、`EcuLspRequestStatus`、workspace diagnostics report/operation typed enum，并为 `EditorUI` / `MultiDocumentEditorUI` 的 LSP result/request events、workspace diagnostics snapshot/events 提供 `familyKind`、`slotKind`、`phaseKind`、`statusKind`、`severityKind`、`reportKind`、`operationKind` accessor；原有 ABI JSON 和 raw string 字段保持兼容，未知未来值通过 `.unknown(raw)` 保留。测试覆盖单 editor 事件、multi-document 聚合事件、workspace diagnostics severity/report/operation typed 视图。当前仍缺每个 result family 的完整 payload typed envelope 和状态变更订阅模型。
- 2026-08-02 阶段 148 已完成：Swift `EditorCoreUIFFI` 新增 completion payload typed model，覆盖 `CompletionList` / `CompletionItem[]` / `null` 三种 result 形态、`CompletionItem` label/details/kind/tags/documentation/commitCharacters/textEdit/insert-replace edit/additional edits/command/data/raw payload，并新增 `EditorUI.lspTakeLastCompletionResult()` 与 `EditorUI.lspTakeLastCompletionItemResolveResult()` typed wrapper；原有 raw JSON take API 保持兼容。测试覆盖 CompletionList、数组 result、null result、resolve item insert-replace edit、unknown enum fallback 和无结果 wrapper。阶段 149 已把 completion App 主路径迁移到该 typed payload；当前仍缺其它 LSP result family 的 payload typed envelope 和状态变更订阅模型。
- 2026-08-02 阶段 149 已完成：AttoEditor completion request / completion item resolve poll path 改为消费 `EditorUI.lspTakeLastCompletionResult()` 与 `EditorUI.lspTakeLastCompletionItemResolveResult()`，`AttoLspCompletionParser` 新增 `EcuLspCompletionResult` / `EcuLspCompletionItem` typed 输入路径，并把 textEdit、InsertReplaceEdit insert range、additionalTextEdits、documentation、commitCharacters 和 raw resolve payload 从 typed DTO 投影到既有 UI item/application plan；旧 JSON helper 保留给测试和兼容入口。测试覆盖 typed result 直接输入、completion list 展示模型、application plan、resolve item raw payload 和 UIFFI typed wrapper。阶段 150-161 已继续补齐 location、rename、code action、symbols、color、hierarchy、diagnostics、selection range、linked editing、code lens、folding ranges 和 semantic tokens typed payload，阶段 196 已补 WorkspaceEdit open-tab transaction 起点；当前仍缺完整 core workspace-owned completion/WorkspaceEdit 事务和状态变更订阅模型。
- 2026-08-02 阶段 150 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspLocationResult` typed envelope，覆盖 `Location`、`LocationLink`、`Location[]`、`LocationLink[]`、mixed array 和 `null`，保留 raw payload，并提供可直接导航的 target 投影；`EditorUI` 新增 `lspTakeLastDefinitionResult()`、`lspTakeLastDeclarationResult()`、`lspTakeLastTypeDefinitionResult()`、`lspTakeLastImplementationResult()` 和 `lspTakeLastReferencesResult()` typed wrapper。AttoEditor definition/declaration/typeDefinition/implementation/references poll path 已改为消费 typed payload，`AttoLspDefinitionParser` 新增 typed 输入路径，旧 JSON helper 保留给测试和兼容入口。测试覆盖 location / location link / null 解码、无结果 wrapper、typed parser 和 App 主路径投影。阶段 151-161 已继续补齐 rename、code action、symbols、color、hierarchy、diagnostics、selection range、linked editing、code lens、folding ranges 和 semantic tokens typed payload；当前仍缺更完整状态变更订阅模型。
- 2026-08-02 阶段 151 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspPrepareRenameResult` 和 `EcuLspWorkspaceEdit` typed envelope，覆盖 prepareRename 的 `Range`、`{ range, placeholder }`、`{ defaultBehavior }`、`null`，以及 WorkspaceEdit 的 `changes`、`TextDocumentEdit`、`create` / `rename` / `delete` resource operations、change annotations 和 raw JSON 回写；`EditorUI` 新增 `lspTakeLastPrepareRenameResult()` 与 `lspTakeLastRenameResult()` typed wrapper。AttoEditor rename prepare/result poll path 已改为消费 typed payload，`AttoLspRenameSupport` 和 `AttoWorkspaceEditParser` 新增 typed 输入路径，旧 JSON helper 保留给测试和兼容入口；打开文档应用仍通过现有 Rust UI FFI JSON apply 保留 undo/dirty/layout 语义。测试覆盖 prepareRename typed seed、WorkspaceEdit typed parser、rename typed wrapper empty state 和 raw JSON 回写。阶段 152-161 已继续补齐 code action、symbols、color、hierarchy、diagnostics、selection range、linked editing、code lens、folding ranges 和 semantic tokens typed payload，阶段 196 已补 WorkspaceEdit open-tab transaction 起点；当前仍缺完整 core workspace-owned WorkspaceEdit 事务和状态变更订阅模型。
- 2026-08-02 阶段 152 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspCodeActionResult` / `EcuLspCodeAction` typed envelope，覆盖 `Command | CodeAction` 数组、`null`、resolve 单个 CodeAction、disabled reason、LSP range diagnostics、WorkspaceEdit、command、data 和 raw JSON 回写；`EditorUI` 新增 `lspTakeLastCodeActionResult()` 与 `lspTakeLastCodeActionResolveResult()` typed wrapper。AttoEditor code action request/resolve poll path 已改为消费 typed payload，`AttoLspCodeActionParser` 新增 typed 输入路径，应用 action 时优先使用 typed WorkspaceEdit，并继续保留旧 JSON helper 和 raw payload 回写给 resolve/executeCommand。测试覆盖 CodeAction/Command typed 解码、typed parser 投影、resolve action、无结果 wrapper 和 raw JSON 回写。阶段 153-161 已继续补齐 symbols、color、hierarchy、diagnostics、selection range、linked editing、code lens、folding ranges 和 semantic tokens typed payload，阶段 196 已补 WorkspaceEdit open-tab transaction 起点；当前仍缺完整 core workspace-owned WorkspaceEdit 事务和状态变更订阅模型。
- 2026-08-02 阶段 153 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspDocumentSymbolResult` / `EcuLspWorkspaceSymbolResult` typed envelope，覆盖 `DocumentSymbol[]`、`SymbolInformation[]`、mixed document result、`WorkspaceSymbol[]`、`null`、workspace symbol full `Location` 和 LSP 3.17 `{ uri }` location，并保留 raw JSON 回写；`EditorUI` 新增 `lspTakeLastDocumentSymbolsResult()` 与 `lspTakeLastWorkspaceSymbolsResult()` typed wrapper。AttoEditor document/workspace symbol poll path 和 workspace symbol 增量搜索 poll path 已改为消费 typed payload，`AttoLspSymbolParser` 新增 typed 输入路径，document symbols 仍优先把 raw result 写入 core outline 后消费 typed derived-state snapshot，失败时回退到 typed result 投影。测试覆盖 document/workspace symbol typed 解码、typed parser 投影、uri-only workspace target、无结果 wrapper、旧 JSON 兼容入口和 workspace symbols panel/history 行为。阶段 154-161 已继续补齐 document color / color presentation、hierarchy、diagnostics、selection range、linked editing、code lens、folding ranges 和 semantic tokens typed payload；当前仍缺状态变更订阅模型。
- 2026-08-02 阶段 154 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspDocumentColorResult` / `EcuLspColorPresentationResult` typed envelope，覆盖 `ColorInformation[]`、`ColorPresentation[]`、`null`、主 `textEdit` 和 `additionalTextEdits`；`EditorUI` 新增 `lspTakeLastDocumentColorResult()` 与 `lspTakeLastColorPresentationResult()` typed wrapper。AttoEditor document color 和 color presentation poll path 已改为消费 typed payload，`AttoLspDocumentColorParser` 新增 typed 输入路径，旧 JSON helper 保留给测试和兼容入口。测试覆盖 color typed 解码、typed parser 投影、无结果 wrapper、事件记录、presentation apply 和旧 JSON 兼容路径。阶段 155-161 已继续补齐 hierarchy、diagnostics、selection range、linked editing、code lens、folding ranges 和 semantic tokens typed payload；当前仍缺状态变更订阅模型。
- 2026-08-02 阶段 155 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspCallHierarchyPrepareResult` / `EcuLspCallHierarchyIncomingCallsResult` / `EcuLspCallHierarchyOutgoingCallsResult` / `EcuLspTypeHierarchyPrepareResult` / `EcuLspTypeHierarchyItemsResult` typed envelope，覆盖 prepare item 数组或单 item、incoming/outgoing call、supertypes/subtypes item 数组和 `null`，并保留 hierarchy item raw JSON 供后续 children request 复用；`EditorUI` 新增六个 hierarchy typed take wrapper。AttoEditor call/type hierarchy prepare 和 children poll path 已改为消费 typed payload，`AttoLspHierarchyParser` 新增 typed 输入路径，旧 JSON helper 保留给测试和兼容入口。测试覆盖 hierarchy typed 解码、无结果 wrapper、typed parser 投影和 raw request JSON 保留。阶段 156 已继续补齐 diagnostics pull typed payload；当前仍缺 hierarchy 树状持久面板、层级展开/刷新和跨文件结果聚合。
- 2026-08-02 阶段 156 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspDocumentDiagnosticResult` / `EcuLspWorkspaceDiagnosticResult` typed envelope，覆盖 `full` / `unchanged` document reports、workspace diagnostic report items、`relatedDocuments`、diagnostic severity/code/codeDescription/tags/relatedInformation/data/raw payload 和 `null`；`EditorUI` 新增 `lspTakeLastDocumentDiagnosticResult()` 与 `lspTakeLastWorkspaceDiagnosticResult()` typed wrapper。AttoEditor workspace diagnostics poll path 已改为消费 typed payload，`AttoLspWorkspaceDiagnosticsParser` 和 `AttoWorkspaceProblemsStore` 新增 typed 输入路径，core-backed workspace diagnostics store 仍通过 typed raw JSON 回写保持单一 ownership。测试覆盖 diagnostics typed 解码、无结果 wrapper、typed parser 投影、typed store apply 和 App typed workspace diagnostics 导航入口。阶段 157-161 已继续补齐 selection range、linked editing、code lens、folding ranges 与 semantic tokens typed payload；当前仍缺状态变更订阅模型。
- 2026-08-02 阶段 157 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspSelectionRangeResult` typed envelope，覆盖 `SelectionRange[]`、递归 parent chain、raw payload 和 `null`；`EditorUI` 新增 `lspTakeLastSelectionRangeResult()` typed wrapper。AttoEditor selection range poll path 已改为消费 typed payload，`AttoLspSelectionRangeParser` 新增 typed 输入路径，旧 JSON helper 保留给测试和兼容入口。测试覆盖 typed 解码、无结果 wrapper、typed parser 投影和 App typed selection range expansion。
- 2026-08-02 阶段 158 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspLinkedEditingRangeResult` typed envelope，覆盖 `LinkedEditingRanges`、`ranges`、`wordPattern`、raw payload 和 `null`；`EditorUI` 新增 `lspTakeLastLinkedEditingRangeResult()` typed wrapper。AttoEditor linked editing poll path 已改为消费 typed payload，`AttoLspLinkedEditingParser` 新增 typed 输入路径，旧 JSON helper 保留给测试和兼容入口。测试覆盖 typed 解码、无结果 wrapper、typed parser 投影和 App typed linked editing multi-cursor selection。
- 2026-08-02 阶段 159 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspCodeLensResult` / `EcuLspCodeLens` typed envelope，覆盖 `CodeLens[]`、`CodeLens` resolve、`Command`、`data`、raw payload、`null` 和 code lens refresh error envelope；`EditorUI` 新增 `lspTakeLastCodeLensResult()` 与 `lspTakeLastCodeLensResolveResult()` typed wrapper。AttoEditor code lens refresh/resolve poll path 已改为消费 typed payload，`AttoLspCodeLensParser` 新增 typed 输入路径，旧 JSON helper 保留给 decoration/hit-test 兼容入口。测试覆盖 typed 解码、无结果 wrapper、typed parser 投影、UTF-16 range 转换和 App typed refresh summary。
- 2026-08-02 阶段 160 已完成：Swift `EditorCoreUIFFI` 新增 `EcuLspFoldingRangeResult` / `EcuLspFoldingRange` typed envelope，覆盖 `FoldingRange[]`、`startCharacter` / `endCharacter`、`kind`、`collapsedText`、raw payload 和 `null`；`EditorUI` 新增 `lspTakeLastFoldingRangesResult()` 与 `lspApplyFoldingRanges(_:)` typed wrapper。AttoEditor folding ranges poll/apply path 已改为消费 typed payload，旧 JSON helper 保留给兼容入口并先 decode 到 typed result。测试覆盖 typed 解码、无结果 wrapper、typed apply 到 fold regions snapshot，以及 App typed folding ranges refresh 到 derived-state store。
- 2026-08-02 阶段 161 已完成：Swift UI binding 新增 LSP semantic tokens full / delta / range manual request/take API，`editor-core-ui-ffi` 暴露对应 C ABI 和 `lspSemanticTokensRequests` runtime feature flag；Swift `EditorCoreUIFFI` 新增 `EcuLspSemanticTokensResult` / `EcuLspSemanticTokensEdit` typed envelope，覆盖 `null`、full/range `{ data, resultId }`、delta `{ edits, resultId }` 和 delta baseline application。AttoEditor 新增 typed semantic tokens apply helper，active tab 保存 `resultId` / token data baseline，full/range 替换 baseline，delta 基于 baseline 应用并刷新 style intervals。测试覆盖 Rust UI/FFI、Swift typed decode/delta apply/typed editor apply、disabled LSP request/take、runtime compatibility 和 App typed semantic tokens 到 derived-state store 的主路径；当前仍缺状态变更订阅模型和完整 core workspace-owned WorkspaceEdit 事务。

## 阶段 162: LSP result family 覆盖矩阵基线

本节对应 `PLAN.md` 阶段 2 的审计部分，只记录覆盖基线，不代表本节本身已经完成统一反馈实现。后续阶段 2 的代码目标是把这些 family 的空结果、错误、取消、超时和 stale 展示策略统一到 App 层，同时避免每个功能继续各自手写轮询、HUD、popover 或 quick panel 的失败路径。

| LSP family | request / take | Swift typed payload | App consumer | lifecycle / events | 阶段 2 后续缺口 |
| --- | --- | --- | --- | --- | --- |
| hover | 已有 raw request/take | 阶段 164 已补 public `EcuLspHoverResult` wrapper，覆盖 MarkupContent、MarkedString、range 和 raw payload | hover popover 主路径已有，阶段 164 已改为消费 typed result；JSON formatter 入口保留兼容 | result/request events 已覆盖 | 自动 hover 仍保持低噪声；若后续增加显式 hover command，再接入统一 empty/error/timeout/stale feedback |
| completion / completion resolve | 已有 request/take | 已有 `EcuLspCompletionResult` / typed resolve item | completion popup、resolve、commit characters、trigger characters、增量过滤已消费 typed payload；阶段 168 已让显式 completion 命令的 unavailable/request failed/failed/timeout/empty 接入统一 feedback，自动 trigger 保持低噪声 | result/request events 已覆盖 | 阶段 196 已补 open-tab WorkspaceEdit transaction 起点；跨文件 additional edits 后续交给完整 core-owned WorkspaceEdit transaction；状态订阅驱动 completion stale/metadata |
| signature help | 已有 raw request/take | 阶段 165 已补 public `EcuLspSignatureHelpResult` wrapper，覆盖 SignatureInformation、ParameterInformation、documentation、active index 和 raw payload | 手动/自动 signature popup 已有，阶段 165 已改为消费 typed result；手动空/错反馈接入统一 feedback，自动触发保持静默失败策略 | result/request events 已覆盖 | 后续由状态订阅驱动 stale/refresh metadata；自动触发继续保持低噪声 |
| definition / declaration / type definition / implementation / references | 已有 request/take | 已有 `EcuLspLocationResult` | location quick panel、history、persistent panel、cmd-click 已消费 typed payload；阶段 166 已让显式 location 命令的 unavailable/request failed/failed/timeout/empty 接入统一 feedback，Cmd-click 保持低噪声 | result/request events 已覆盖，MultiDocument 聚合已有 | 补项目级 freshness/ownership；后续由状态订阅驱动 stale/refresh metadata |
| prepare rename / rename | 已有 request/take | 已有 `EcuLspPrepareRenameResult` / `EcuLspWorkspaceEdit` | rename 输入、typed seed、WorkspaceEdit apply/summary 已消费 typed payload；阶段 170 已让显式 rename 的 unavailable/request failed/failed/timeout/empty 接入统一 feedback；阶段 236 已让 WorkspaceEdit context 使用 core document URI projection | result/request events 已覆盖 | WorkspaceEdit 应迁到 core-owned 跨文件事务；冲突展示后续与 core transaction/state subscription 对齐 |
| code action / code action resolve / execute command | 已有 request/take/resolve/executeCommand | code action typed 已有；executeCommand result 仍偏 raw/result envelope | quick panel、kind filter、resolve、command 执行和 HUD 已有；阶段 170 已让显式 code action / resolve 的 unavailable/request failed/failed/timeout/empty 接入统一 feedback | result/request events 已覆盖 | typed workspace command/result model；WorkspaceEdit 事务化；executeCommand result 继续收敛到统一 lifecycle/feedback |
| document symbols / workspace symbols | 已有 request/take | 已有 symbols typed payload | quick panel、incremental workspace symbol panel、outline/persistent panel 已消费 typed payload；阶段 167 已让显式 symbols 命令的 unavailable/request failed/failed/timeout/empty 接入统一 feedback | result/request events 和 history entry 已有 | 状态订阅驱动 outline/symbols refresh 与 stale 展示 |
| formatting / range formatting / on-type formatting | document/range/on-type blocking apply 已有；on-type async lifecycle 已有 | 已有 `EditorCoreLSPFormattingResult` outcome，但不是通用 LSP payload envelope | document/selection format command 和 on-type trigger path 已有；阶段 172 已让显式 Format Document / Format Selection 的 unavailable/failed/no-edits/empty-selection 接入统一 feedback | on-type request lifecycle 已覆盖，status/detail 可记录异步失败 | 格式化 edit apply 后续纳入 core-owned WorkspaceEdit/current-document transaction 语义；自动 on-type formatting 继续走低噪声 status/event |
| document color / color presentation | 已有 request/take | 已有 color typed payload | color quick panel、direct color picker、presentation apply 已消费 typed payload；阶段 169 已让显式 document color / color presentation 的 unavailable/request failed/failed/timeout/empty/apply failed 接入统一 feedback | result/request events 已覆盖 | 持久颜色面板、多文档/workspace 聚合；状态订阅驱动 stale/metadata |
| call hierarchy / type hierarchy | 已有 prepare/children request/take | 已有 hierarchy typed payload | 基础 quick panel 导航和 children request 已消费 typed payload；阶段 171 已让显式 call/type hierarchy 的 unavailable/request failed/failed/timeout/empty 接入统一 feedback | result/request events 已覆盖 | 持久树状面板、展开/刷新、跨文件聚合；状态订阅驱动 stale/metadata |
| diagnostics pull / publish diagnostics projection | pull request/take 已有；publish notification projection 已有 | pull diagnostics typed payload 已有；publish 走 derived-state/workspace store projection | Problems quick/persistent/workspace panel、markers、status summary 已消费 unified model；阶段 163 已让 workspace diagnostics 显式请求/空结果/超时进入统一 feedback 起点 | diagnostics lifecycle、workspace diagnostics events、request/result events 已覆盖；阶段 178 已提供 `EditorUi` state events 起点，阶段 179 已提供 MultiDocument state events 聚合起点 | 状态订阅模型继续补非 LSP 事件和 App 统一消费；统一 feedback 中继续保留 pull error/partial result 元数据 |
| selection range | 已有 request/take | 已有 selection range typed payload | expand-selection 主路径已消费 typed payload；阶段 163 已接入统一 feedback 起点 | result/request events 已覆盖 | 多光标 session state 后续由状态订阅驱动，继续补 event-driven feedback |
| linked editing | 已有 request/take | 已有 linked editing typed payload | linked editing multi-cursor/session 主路径已消费 typed payload；阶段 163 已接入统一 feedback 起点 | result/request events 已覆盖 | session lifecycle 与状态订阅统一，继续补 event-driven feedback |
| code lens / code lens resolve | 已有 request/take/resolve | 已有 code lens typed payload | refresh、actions quick panel、inline Cmd-click、status count 已消费 typed payload/derived decorations；阶段 163 已让 refresh 显式反馈进入统一 feedback 起点 | auxiliary refresh lifecycle 和 result/request events 已覆盖 | 持久 panel/history、workspace command typed result 和 event-driven feedback |
| folding ranges | 已有 request/take/apply | 已有 folding range typed payload 和 typed apply wrapper | refresh command、fold state、status bar、gutter marker 已消费 typed payload；阶段 163 已接入统一 feedback 起点 | manual request 与 internal refresh lifecycle 已覆盖 | 状态订阅驱动 folds stale/refresh，继续补 event-driven feedback |
| semantic tokens full / delta / range | 阶段 161 已补 manual request/take | 阶段 161 已补 semantic tokens typed payload 和 delta baseline apply | typed apply helper 与 active-tab baseline 已有；阶段 163 已让 typed apply 空结果/错误进入统一 feedback 起点 | internal refresh lifecycle 已有，manual request 进入 result/request events | 状态订阅驱动语义高亮 refresh/stale；baseline ownership 后续与 workspace/document state 对齐 |
| inlay hints / inlay hint resolve | 阶段 173 已补 manual request/take；阶段 174 已补 `inlayHint/resolve` request/take；自动 auxiliary refresh 与 apply JSON / decorations snapshot 已有 | 阶段 173 已补 public `EcuLspInlayHintResult` wrapper；阶段 174 已补 resolved single `EcuLspInlayHint` take wrapper | renderer inlay、hit-test/caret point 和 status 派生消费已有；阶段 175 已补显式 refresh command/menu/HUD 主路径；阶段 177 已补 inline virtual text Cmd-click resolve/show/apply 主路径 | auxiliary refresh lifecycle 已覆盖，manual request/resolve 进入 result/request events；阶段 178 可通过 `EditorUI.stateEvents(after:)` 同 cursor drain | 仍缺状态订阅驱动 stale/refresh 的 App 消费迁移，以及 panel/history metadata |
| document links / document link resolve | 阶段 173 已补 manual request/take；阶段 174 已补 `documentLink/resolve` request/take；自动 auxiliary refresh、apply JSON 和 hit-test 已有 | 阶段 173 已补 public `EcuLspDocumentLinkResult` wrapper；阶段 174 已补 resolved single `EcuLspDocumentLink` take wrapper | underline/rendering、hit-test/open URL 主路径已有；阶段 175 已补显式 refresh command/menu/HUD 主路径；阶段 176 已补 unresolved document link 的 Cmd-click resolve 后打开主路径 | auxiliary refresh lifecycle 已覆盖，manual request/resolve 进入 result/request events；阶段 178 可通过 `EditorUI.stateEvents(after:)` 同 cursor drain | 仍缺状态订阅驱动 stale/refresh 的 App 消费迁移，以及更完整的 link resolve lifecycle/panel metadata |

阶段 174 之后，LSP typed payload 的剩余重点不再是“能否从 Swift 拿到大多数 result family”，而是三件事：少数 raw-only family 的 typed envelope 上提、所有 family 共享统一 feedback/lifecycle UI、以及把 WorkspaceEdit/状态变更订阅这类跨 family 事实源继续迁到 core/workspace 侧。

## 阶段 163: LSP result feedback 起点

2026-08-02 阶段 163 已完成统一 feedback 的 App 层起点：AttoEditor 新增 `AttoLspResultFeedback`，把 LSP 显式命令常见的 unavailable、request failed、failed、timeout、empty 和 refreshed 文案统一成 `{ statusText, detailText }`，`AttoEditorAreaViewController.presentLspResultFeedback(...)` 会同时写入 transient status bar 短反馈并复用既有 popover 展示详细信息。

本阶段已迁移这些用户可见路径：folding ranges refresh/apply、semantic tokens typed apply、selection range、linked editing、code lens refresh、workspace diagnostics 的空结果/失败/超时/不可用反馈。测试新增 `AttoLspResultFeedbackTests`，并用 `AttoEditorCommandTests/testUnifiedLspFeedbackUpdatesTransientStatusForEmptyFoldingRanges` 验证 App 主路径会写入 transient status。

阶段 163 仍只是统一 feedback 的第一步：hover、signature help、completion、location、symbols、rename/code action、document color、hierarchy 等路径当时仍有各自的 popup/panel/formatter 逻辑；阶段 164-174 已继续迁移 hover typed payload、signature help、location、symbols、completion、document color / color presentation、rename/code action、call/type hierarchy、显式 formatting 命令反馈，以及 inlay hints / document links 的 manual typed request/take/resolve wrapper。阶段 175 已继续把 inlay hints、document links 的显式 refresh 行为接入同一个 feedback sink；阶段 176 已把 unresolved document link 的 Cmd-click resolve/open 接入同一反馈体系；阶段 177 已把 inlay hint Cmd-click resolve/show/apply 接入同一反馈体系；阶段 178 已提供 `EditorUi` 级统一 state event drain 起点；阶段 179 已提供 MultiDocument/project 级 state event 聚合起点。下一步应继续让非 LSP 状态事件和 App 消费迁移驱动 feedback 的生命周期、stale/refresh 展示和 result panel metadata。

## 阶段 164: Hover typed payload wrapper

2026-08-02 阶段 164 已补齐 hover result 的 Swift typed payload 起点：`EditorCoreUIFFI` 新增 `EcuLspHoverResult` / `EcuLspHoverContent`，覆盖 LSP `Hover | null`、`MarkupContent`、`MarkedString` 字符串/语言对象、可选 `range` 和 raw payload preservation；`EditorUI.lspTakeLastHoverResult()` 复用既有 `lspTakeLastHoverResultJSON()` C ABI escape hatch 做 typed decode，因此不需要扩大 C ABI 表面。

AttoEditor hover formatter 和 hover popover 轮询路径已改为消费 typed result，原有 JSON formatter 入口保留给兼容和测试。自动 hover 的失败、空结果和超时仍按低噪声策略取消 popover，不弹出统一错误提示；后续如果增加显式 hover command，再把显式命令接入 `AttoLspResultFeedback`。

## 阶段 165: Signature help typed payload wrapper

2026-08-02 阶段 165 已补齐 signature help result 的 Swift typed payload：`EditorCoreUIFFI` 新增 `EcuLspSignatureHelpResult`、`EcuLspSignatureInformation`、`EcuLspParameterInformation` 和 `EcuLspParameterLabel`，覆盖 LSP `SignatureHelp | null`、active signature/parameter、signature-level active parameter、string / UTF-16 range 参数 label、string / MarkupContent documentation、unknown parameter label fallback 和 raw payload preservation；`EditorUI.lspTakeLastSignatureHelpResult()` 复用既有 `lspTakeLastSignatureHelpResultJSON()` C ABI escape hatch 做 typed decode。

AttoEditor `AttoLspSignatureHelpFormatter` 已改为直接消费 UIFFI typed result，原 JSON formatter/parse 入口作为兼容包装保留。手动 signature help 的 unavailable、request failed、failed、timeout 和 empty 路径已接入 `AttoLspResultFeedback` 的统一 status/detail 文案，并继续用 signature popover 在 caret 附近显示详细信息；自动 trigger path 仍保持静默失败策略，避免输入过程中弹出噪声。

## 阶段 166: Location result feedback unification

2026-08-02 阶段 166 已把 locations family 的显式用户命令接入统一 feedback：definition、declaration、type definition、implementation 和 references 共享 `AttoLspResultFeedback` 的 unavailable、request failed、failed、timeout 和 empty 文案，`requestLspLocation(...)` 的上下文新增 `showFeedback` 标志，菜单/command palette 主路径会写入 transient status 并展示 detail popover，Cmd-click definition 仍保持低噪声，不把自动式导航探测变成打扰式错误弹窗。

本阶段还让空 typed/JSON location result 统一走同一 feedback sink，因此 `showLspLocationResultJSONInActiveTab("[]", kind: .definition)` 这类 App 测试入口也会得到 `Definition: no results` 的 status 反馈。后续 locations family 的剩余工作转为项目级 freshness/ownership、状态订阅驱动 stale/refresh metadata，以及跨 workspace/multi-document 聚合的一致性。

## 阶段 167: Symbols result feedback unification

2026-08-02 阶段 167 已把 document symbols / workspace symbols 的显式用户命令接入统一 feedback：`AttoLspResultFeedback` 新增 document/workspace symbols feature，`requestLspSymbols(...)`、`promptWorkspaceSymbolsInActiveTab(...)` 和空 typed/JSON result 入口的 unavailable、request failed、failed、timeout、empty 路径统一写入 transient status 并复用 detail popover。

本阶段删除了旧的 `AttoLspSymbolRequestFeedback` 专用 helper，让 symbols 与 locations、signature help、folding ranges、semantic tokens、selection range、linked editing、code lens refresh、workspace diagnostics 共享同一个反馈模型。workspace symbols 仍保留 query-aware 空结果详情，例如 `No workspace symbols match "App".`；status bar 统一为 `Workspace symbols: no results`。后续 symbols family 的剩余工作转为状态订阅驱动 outline/symbols refresh 与 stale metadata；opened-document workspace outline store 起点已在阶段 193 补齐，并在阶段 194 下沉为 core-owned workspace outline snapshot/API。

## 阶段 168: Completion result feedback unification

2026-08-02 阶段 168 已把显式 `lsp.completion` 命令接入统一 feedback：`AttoLspResultFeedback` 新增 completion feature，显式 completion 的 LSP disabled、request failed、take failed、timeout 和 empty result 会写入 transient status 并复用 detail popover；空 typed/JSON result 测试入口也会得到 `Completion: no results`。

本阶段为 completion request context 增加 `showFeedback` 标志，菜单/command palette 显式触发开启统一反馈，server trigger characters 自动触发仍传 `showFeedback: false` 并保持静默失败策略，避免输入过程中弹出噪声。completion family 的剩余工作集中在 completion additional edits / resolve 产生的跨文件 WorkspaceEdit 由 core-owned transaction 统一处理，以及后续状态订阅模型中的 stale/metadata。

## 阶段 169: Document color feedback unification

2026-08-02 阶段 169 已把 document color / color presentation 的显式用户路径接入统一 feedback：`AttoLspResultFeedback` 新增 document colors 和 color presentations feature，document color 请求的 unavailable、request failed、take failed、timeout、empty result，以及 color presentation 请求的 encode failure、request failed、take failed、timeout、empty result 和 apply failed 都会写入 transient status 并复用 detail popover。

本阶段保留现有 color quick panel、direct color picker、presentation apply 和跨 family result event 行为不变，只把分散的 `showWorkspaceEditPopover(text: ...)` 用户反馈收敛到同一个 feedback sink。`NSColorPanel` 连续颜色变化仍传 `showFeedback: false`，避免拖动颜色时产生噪声。后续 color family 的剩余工作转为持久颜色面板、多文档/workspace 颜色聚合，以及状态订阅驱动 stale/metadata。

## 阶段 170: Rename and code action feedback unification

2026-08-02 阶段 170 已把显式 rename 与 code action 用户路径接入统一 feedback：`AttoLspResultFeedback` 新增 rename、code actions 和 code action resolve feature。显式 rename 的 LSP disabled、request failed、take failed、timeout、空 WorkspaceEdit / 无法解码结果会写入 transient status 并复用 detail popover；prepareRename 仍保留失败时回退本地候选名的低摩擦行为。

本阶段还让 code action / resolve 的 LSP disabled、request failed、take failed、timeout、empty result、disabled action 和 resolve 后无可应用 edit/command 走同一个 feedback sink。既有 quick panel、kind filter、WorkspaceEdit apply summary、executeCommand result HUD 和 result lifecycle event 行为不变；剩余工作转为 core-owned WorkspaceEdit 跨文件事务、executeCommand typed result model，以及由状态订阅驱动的 stale/metadata 展示。

## 阶段 171: Hierarchy feedback unification

2026-08-02 阶段 171 已把显式 call hierarchy / type hierarchy 用户路径接入统一 feedback：`AttoLspResultFeedback` 新增 call hierarchy 和 type hierarchy feature，prepare 请求和 children 请求的 LSP disabled、position failed、request failed、take failed、timeout 与 empty result 都会写入 transient status 并复用 detail popover。

本阶段保留现有 prepare root 选择、single-root 自动进入 children 请求、children quick panel 导航和 typed payload parser 行为不变，只把原本静默或仅 beep 的失败/空结果路径接入统一 feedback。后续 hierarchy family 的剩余工作仍是持久树状面板、层级展开/刷新、跨文件/workspace 聚合，以及状态订阅驱动 stale/metadata。

## 阶段 172: Formatting feedback unification

2026-08-02 阶段 172 已把显式 Format Document / Format Selection 用户路径接入统一 feedback：`AttoLspResultFeedback` 新增 format document 和 format selection feature，`EditorCoreLSPFormattingResult` 的 unavailable、failed、no edits，以及 Format Selection 空选区都会写入 transient status 并复用 detail popover。

本阶段不改变现有 document/range/on-type formatting ABI，也不改变成功应用时的编辑、dirty、layout 和 status bar 更新语义。自动 on-type formatting 仍保持低噪声 status/event 路径；剩余工作是把 formatting edit apply 继续收敛到 core-owned WorkspaceEdit/current-document transaction 语义，并由状态订阅驱动 stale/metadata。

## 阶段 173: Auxiliary LSP typed request wrappers

2026-08-02 阶段 173 已补齐 inlay hints / document links 的手动 request/take Swift UI binding：`EditorUi` 新增 `lsp_request_inlay_hints(start_offset, end_offset)`、`lsp_take_last_inlay_hints_result_json()`、`lsp_request_document_links()` 和 `lsp_take_last_document_links_result_json()`；`editor-core-ui-ffi` 新增对应 C ABI 和 `ECU_FEATURE_LSP_AUXILIARY_REQUESTS` feature bit；Swift `EditorUI` 新增 raw request/take 与 typed take wrapper。

Swift typed payload 新增 `EcuLspInlayHintResult` / `EcuLspDocumentLinkResult`，覆盖 LSP `InlayHint[] | null`、`DocumentLink[] | null`、string 与 label-part inlay labels、inlay kind unknown fallback、tooltip string/MarkupContent/raw fallback、text edits、unresolved document link data、error envelope 和 raw payload preservation。本阶段不改变自动 auxiliary refresh、renderer decorations、document link hit-test/open URL 主路径，也不引入 App 显式刷新 UI；阶段 174 已继续补齐 `inlayHint/resolve` / `documentLink/resolve` slot/ABI。

## 阶段 174: Auxiliary LSP resolve wrappers

2026-08-02 阶段 174 已补齐 `inlayHint/resolve` 与 `documentLink/resolve` 的 UI slot、C ABI 和 Swift typed wrapper：`LspResultSlot` 新增 `InlayHintResolve` / `DocumentLinkResolve`，method/slot/family/title 映射进入 request/result lifecycle；`EditorUi` 新增 `lsp_request_inlay_hint_resolve(...)`、`lsp_take_last_inlay_hint_resolve_result_json()`、`lsp_request_document_link_resolve(...)` 和 `lsp_take_last_document_link_resolve_result_json()`；`editor-core-ui-ffi` 新增对应 C ABI 与 `ECU_FEATURE_LSP_AUXILIARY_RESOLVE_REQUESTS` feature bit。

Swift `EditorUI` 新增 raw request/take 与 typed take wrapper，resolved payload 分别解码为单个 `EcuLspInlayHint` 和 `EcuLspDocumentLink`；`EcuLspResultSlot` typed accessor 也新增 `inlayHintResolve` / `documentLinkResolve`，避免 lifecycle event 在 Swift 侧退回 unknown slot。本阶段不改变自动 decorations、document link hit-test/open URL 或 App 显式 UI；剩余工作是为 explicit auxiliary refresh/resolve 增加用户入口，并接入统一 feedback 与状态订阅驱动的 stale/refresh metadata。

## 阶段 175: Auxiliary LSP refresh UI

2026-08-02 阶段 175 已补齐 inlay hints / document links 的显式刷新 App 主路径：AttoEditor 新增 `lsp.refresh_inlay_hints` 和 `lsp.refresh_document_links` command palette 入口、Go 菜单项和 `AttoEditorAreaViewController` 刷新方法。刷新路径复用阶段 173-174 的 Swift typed request/take wrapper：inlay hints 使用当前文档全文 char range 请求，document links 使用 document-level 请求；结果返回后通过既有 `lspApplyInlayHintsJSON(...)` / `lspApplyDocumentLinksJSON(...)` 写入 decorations，并刷新 derived-state、layout 和 status。

本阶段还把两个 family 的 unavailable、request failed、failed、timeout、empty 和 refreshed 反馈接入 `AttoLspResultFeedback`，补充了 command/menu、LSP disabled、typed result summary 和反馈文案测试。阶段 176-177 已继续补齐 document link / inlay hint 的 explicit resolve UI；剩余工作不再是“显式 refresh/resolve 不可达”，而是状态订阅驱动 stale/refresh metadata，以及把这些 auxiliary result 的 panel/history/metadata 与后续统一 lifecycle UI 对齐。

## 阶段 176: Document link resolve-on-click UI

2026-08-02 阶段 176 已补齐 unresolved document link 的 App 可操作 resolve 主路径：`EditorCoreSkiaView` 新增 `onDocumentLinkClick` host hook，Cmd-click 命中文档链接时若 payload 已有 `target` 继续直接打开，若没有 target 则把原始 `DocumentLink` JSON 交给 host。AttoEditor 现在在该 hook 中发起 `documentLink/resolve`，轮询 Swift typed `EcuLspDocumentLink` resolve result，并在 resolved payload 含 target 后复用原有 URL opener 打开链接。

本阶段还把 document link resolve 的 unavailable、request failed、failed、timeout 和 resolved-without-target 接入 `AttoLspResultFeedback`，并补充 EditorCoreUI unresolved link host delegation 测试与 AttoEditor LSP-disabled resolve feedback 回归测试。阶段 177 已继续补齐 inlay hint resolve 的用户可见消费；剩余 auxiliary resolve 缺口主要是状态订阅驱动 stale/metadata 和 panel/history 对齐。

## 阶段 177: Inlay hint resolve-on-click UI

2026-08-02 阶段 177 已补齐 inlay hint 的 App 可操作 resolve 主路径：`EditorUi` / UI FFI / Swift `EditorUI` 新增 view-point inlay hint hit-test API，可从 inline virtual text 命中处返回原始 `InlayHint` JSON；`EditorCoreSkiaView` 新增 `onInlayHintClick` host hook，Cmd-click 命中 inlay hint 时会交给 host。

AttoEditor 现在在该 hook 中发起 `inlayHint/resolve`，轮询 Swift typed `EcuLspInlayHint` resolve result，并把 resolved tooltip / label-part tooltip 展示为 HUD；resolved `textEdits` 会包装为当前文档 WorkspaceEdit 并复用现有 WorkspaceEdit 应用路径；label part command 会复用现有 `workspace/executeCommand` 路径。本阶段还把 inlay hint resolve 的 unavailable、request failed、failed、timeout 和 resolved-without-action 接入 `AttoLspResultFeedback`，并补充 Rust UI/FFI hit-test、EditorCoreUI host delegation、Atto helper 和 AttoEditor LSP-disabled feedback 回归测试。剩余 auxiliary 缺口不再是 explicit resolve UI，而是统一状态订阅、stale/refresh metadata、panel/history/lifecycle 整合，以及完整 core-owned WorkspaceEdit transaction 收敛。

## 阶段 178: EditorUi unified state events 起点

2026-08-02 阶段 178 已建立单 `EditorUi` 级统一 state event drain 起点：Rust `EditorUiDoc` 新增 bounded `EditorUiStateEvent` log，现有 LSP request lifecycle event 与 LSP result slot event 在记录时同步投影到统一流，并保留 `kind`、family/title/view/source sequence 以及 typed nested `lsp_request` / `lsp_result` payload。

UI FFI 新增 `editor_core_ui_ffi_editor_ui_state_events_latest_sequence` 与 `editor_core_ui_ffi_editor_ui_state_events_json`，feature bit 为 `ECU_FEATURE_EDITOR_UI_STATE_EVENTS`；Swift `EditorUI` 新增 `stateEventsLatestSequence()`、`stateEventsJSON(after:)` 和 typed `stateEvents(after:)`，并在 runtime compatibility optional feature 中声明该能力。本阶段还补充 Rust unified-order 测试、C ABI 空 snapshot 测试和 Swift typed decode / wrapper smoke tests。阶段 179 已继续补齐 MultiDocument/project 级聚合，阶段 180 已补齐文本变更与 dirty 事件，阶段 181 已补齐 selection/caret 事件，阶段 182 已补齐 viewport 事件，阶段 183 已补齐 layout 事件，阶段 184 已补齐 derived-state changed/stale 事件；阶段 185 已让 AttoEditor active derived-state store 与 status bar 主路径消费统一 state-event cursor；剩余状态订阅工作主要是 panels/project-level result lifecycle 从 family-specific polling 继续迁移。

## 阶段 179: MultiDocument unified state events 起点

2026-08-02 阶段 179 已把统一 state events 从单 `EditorUi` 推进到 `MultiDocumentEditorUi` / project 级聚合：Rust 新增 `MultiDocumentStateEventStore`，按 tab order 与 view index 从每个 `EditorUi.state_events_after(...)` 增量拉取事件，并为每条事件附加 `tab_id`、`view_index`、`view_id`、`source_sequence`、kind/family/title 与 nested `EditorUiStateEvent` payload。

UI FFI 新增 `editor_core_ui_ffi_multi_document_state_events_latest_sequence` 与 `editor_core_ui_ffi_multi_document_state_events_json`，feature bit 为 `ECU_FEATURE_MULTI_DOCUMENT_STATE_EVENTS`；Swift `MultiDocumentEditorUI` 新增 `stateEventsLatestSequence()`、`stateEventsJSON(after:)` 和 typed `stateEvents(after:)`，并把该能力加入 AttoEditor runtime optional feature。测试覆盖 Rust 跨 tab 聚合顺序、C ABI 空 snapshot、Swift wrapper smoke 和 typed decode。阶段 180 已让编辑文本与 dirty 状态进入统一流，阶段 181 已让 selection/caret 状态进入统一流，阶段 182 已让 viewport 状态进入统一流，阶段 183 已让 layout 状态进入统一流，阶段 184 已让 derived-state changed/stale 状态进入统一流；剩余状态订阅工作不再是“缺少 project 级统一 cursor 起点”，而是让 AttoEditor active status 主路径和后续 panels/project-level result lifecycle 消费该统一流。

## 阶段 180: Text / dirty state events

2026-08-02 阶段 180 已把文本变更和 dirty 状态翻转纳入统一 state event：Rust `EditorUiStateEvent` 新增 typed `text` 与 `dirty` payload，`text_changed` 事件携带 `text_version`、`char_len` 和 `is_modified`，`dirty_changed` 事件携带最新 dirty 布尔值；事件源接在 core edit/save 与 text delta drain 路径上，避免 Swift 侧另建编辑状态事实源。

Swift `EditorCoreUIFFI` 新增 `EcuEditorUITextStateEvent` 与 `EcuEditorUIDirtyStateEvent`，`EcuEditorUIStateEventKind` 新增 `textChanged` / `dirtyChanged`，event family typed accessor 新增 `document`。MultiDocument/project 级 state event 聚合自动透传这些 payload，并保留 tab/view context。测试覆盖 Rust 单编辑器事件顺序、MultiDocument 聚合、Swift typed decode 和真实 FFI wrapper 的 `insertText` / `markSaved` 路径。阶段 181 已继续补齐 selection/caret state event，阶段 182 已继续补齐 viewport state event，阶段 183 已继续补齐 layout state event，阶段 184 已继续补齐 derived-state changed/stale state event；阶段 185 已让 AttoEditor active derived-state store 与 status bar 主路径消费统一 state-event cursor；剩余缺口继续收窄为 panels/project-level result lifecycle 的统一消费迁移。

## 阶段 181: Selection state events

2026-08-02 阶段 181 已把 selection/caret 状态变化纳入统一 state event：Rust `EditorUiStateEvent` 新增 typed `selection` payload，`selection_changed` 事件携带 `view_version`、primary caret 的 line/column/char offset、primary selection index、selection count、是否存在非空 selection，以及每个 selection 的 normalized start/end 和 anchor/active offset。事件源接在 `EditorUi::exec_core` 的 edit/cursor command 路径上，比较时忽略 `view_version`，只有实际 caret/selection 形状变化才记录事件。

Swift `EditorCoreUIFFI` 新增 `EcuEditorUIPositionStateEvent`、`EcuEditorUISelectionRangeStateEvent` 和 `EcuEditorUISelectionStateEvent`，`EcuEditorUIStateEventKind` 新增 `selectionChanged`。MultiDocument/project 级 state event 聚合自动透传 selection payload 并保留 tab/view context。阶段 182 已继续补齐 viewport state event，阶段 183 已继续补齐 layout state event，阶段 184 已继续补齐 derived-state changed/stale state event；阶段 185 已让 AttoEditor active derived-state store 与 status bar 主路径消费统一 state-event cursor；剩余缺口继续收窄为 panels/project-level result lifecycle 的统一消费迁移。

## 阶段 182: Viewport state events

2026-08-02 阶段 182 已把 viewport 状态变化纳入统一 state event：Rust `EditorUiStateEvent` 新增 typed `viewport` payload，`viewport_changed` 事件携带 `view_version`、viewport width/height、`scroll_top`、smooth-scroll `sub_row_offset`、overscan rows、visible/prefetch visual-line ranges 和 total visual-line count。事件源覆盖 `set_viewport_px` 的 resize 宽高同步、smooth scroll state、row/pixel scroll helper、caret-visible 自动滚动，以及会改变 viewport/layout projection 的 core view/edit/fold command 路径；记录时比较完整 viewport payload，忽略只作为 source metadata 的版本差异。

Swift `EditorCoreUIFFI` 新增 `EcuEditorUIViewportRangeStateEvent` 和 `EcuEditorUIViewportStateEvent`，`EcuEditorUIStateEventKind` 新增 `viewportChanged`。MultiDocument/project 级 state event 聚合自动透传 viewport payload 并保留 tab/view context。测试覆盖 Rust 单编辑器 resize/scroll/view command 事件、MultiDocument 聚合、Swift typed decode 和真实 FFI wrapper 的 `setViewportPx` / `setSmoothScrollState` 路径。阶段 183 已继续补齐 layout state event，阶段 184 已继续补齐 derived-state changed/stale state event；阶段 185 已让 AttoEditor active derived-state store 与 status bar 主路径消费统一 state-event cursor；剩余缺口继续收窄为 panels/project-level result lifecycle 的统一消费迁移。

## 阶段 183: Layout state events

2026-08-02 阶段 183 已把 Rust UI render/layout 配置变化纳入统一 state event：`EditorUiStateEvent` 新增 typed `layout` payload，`layout_changed` 事件携带 output width/height px、scale、font size、line height、cell width、padding、gutter width、tab width 和 text vertical align。事件源覆盖 `set_render_config`、`set_render_metrics`、`set_text_vertical_align`、`set_tab_width`、`set_gutter_width_cells` 和 `set_viewport_px`，并通过前后 layout snapshot 比较避免重复事件。

Swift `EditorCoreUIFFI` 新增 `EcuEditorUILayoutStateEvent`，`EcuEditorUIStateEventKind` 新增 `layoutChanged`。MultiDocument/project 级 state event 聚合自动透传 layout payload 并保留 tab/view context。测试覆盖 Rust 单编辑器 metrics/align/tab width 事件、MultiDocument 聚合、Swift typed decode 和真实 FFI wrapper 的 render metrics / vertical align / tab width 路径。阶段 184 已继续补齐 derived-state changed/stale state event；阶段 185 已让 AttoEditor active derived-state store 与 status bar 主路径消费统一 state-event cursor；剩余缺口继续收窄为 panels/project-level result lifecycle 的统一消费迁移。

## 阶段 184: Derived-state changed/stale state events

2026-08-02 阶段 184 已把派生状态变化与过期纳入统一 state event：Rust `EditorUiStateEvent` 新增 typed `derived_state` payload，`derived_state_changed` 事件在 processing edits 成功应用后记录，携带 status/reason、当前 `text_version`、edit count 和受影响 family；family 覆盖 `style_intervals`、`folding_regions`、`diagnostics`、`decorations` 和 `document_symbols`。`derived_state_stale` 事件在已有派生状态后发生文本版本递增时记录，用于提示 Swift/App 层当前 snapshot 需要刷新。

事件源覆盖 LSP diagnostics / document symbols / folding ranges / inlay hints / code lens / document links、Tree-sitter/Sublime processing edits，以及 Swift-facing 手动 apply 派生状态 API；LSP enable/reset 的内部清理仍保持静默，避免把 lifecycle reset 伪装成用户可见派生状态刷新。Swift `EditorCoreUIFFI` 新增 `EcuEditorUIDerivedStateEvent`，`EcuLspEventFamily` 新增 `derivedState`，`EcuEditorUIStateEventKind` 新增 `derivedStateChanged` / `derivedStateStale`。MultiDocument/project 级 state event 聚合自动透传 derived-state payload 并保留 tab/view context。测试覆盖 Rust 单编辑器 changed/stale 顺序、MultiDocument 聚合、Swift typed decode 和真实 FFI wrapper 的 diagnostics apply + text edit 路径。剩余状态订阅缺口不再是缺少 derived-state changed/stale 事件，而是 AttoEditor active status/diagnostic marker 主路径已开始消费统一 state-event cursor；剩余是 panels/project-level result lifecycle 继续迁移和整合。

## 阶段 185: AttoEditor active derived-state state-event cursor

2026-08-02 阶段 185 已让 AttoEditor active-tab derived-state store 开始消费 `EditorUI.stateEvents(after:)` 统一 cursor：`AttoDerivedStateStore` 现在按 active editor identity 维护 state-event sequence，只有初次加载、收到 `derivedStateChanged`，或收到会影响 fold/viewport projection 的 `viewportChanged` 时才重新读取 diagnostics/decorations/symbols/folds/styles snapshots；收到 `derivedStateStale` 时保留当前 snapshot 并标记 `activeIsStale`，为后续 stale UI 和 panel lifecycle 提供状态源。`stateEvents` 不可用或失败时仍回退到直接读取 typed snapshots，保证旧 runtime / 失败路径有兼容行为。

AttoEditor `updateStatusBar()`、active Problems snapshot、minimap/gutter diagnostic marker 主路径继续通过 `derivedStateStore.active` 取数，但刷新触发已经从无条件 family-specific snapshot polling 收敛为 state-event cursor 驱动。测试覆盖真实 AppKit controller：LSP diagnostics apply 后 status bar drain 到 `derivedStateChanged` 并刷新 snapshot；无新 state event 的重复 status update 不再重复刷新 snapshots；文本编辑后的 `derivedStateStale` 会被 store 捕获并标记 stale。阶段 186-188 已继续迁移 workspace Problems/marker 与 Locations/Symbols 持久在线 panel 的消费模型；剩余缺口是把 stale/error 状态产品化展示，并补齐更完整 project-level result lifecycle/panel 整合。

## 阶段 186: Workspace Problems workspace-diagnostics event cursor

2026-08-02 阶段 186 已让 AttoEditor workspace Problems store 开始消费 `MultiDocumentEditorUI.workspaceDiagnosticsEvents(after:)` 这个 core-owned workspace diagnostics event cursor：`AttoWorkspaceProblemsStore` 现在维护 workspace diagnostics event sequence、最近 drain 到的 event payload 和 core snapshot cache，只有初次读取、收到 workspace diagnostics event，或显式 apply/clear 后才刷新 core-owned workspace diagnostics snapshot；无新事件的重复 Problems/status 查询会复用缓存，不再每次直接轮询 core snapshot。

本阶段保留旧 runtime / 失败路径的 fallback snapshot 行为，并继续让 `apply(resultJSON:)` / typed `apply(result:)` 通过 core-owned workspace diagnostics store 更新 previous result ids、diagnostics 和 Problems panel 输入。测试覆盖直接绕过 store 更新 core diagnostics 后，store 能通过 event cursor 刷新到最新 diagnostics；无新 event 的重复 snapshot 读取不会增加 core snapshot refresh 计数。阶段 187 已继续补齐 marker projection 的同源 cursor 缓存刷新，阶段 188 已把 Locations/Symbols 持久在线 panel 接到 lifecycle entry，阶段 193-194 已补 Workspace Outline store 与 core-owned snapshot/API 起点；剩余缺口进一步收窄为 stale/error 状态产品化展示，以及更完整 project-level result lifecycle/panel 整合。

## 阶段 187: Workspace diagnostic marker projection event cursor

2026-08-02 阶段 187 已让 AttoEditor workspace diagnostic marker projections 复用 `AttoWorkspaceProblemsStore` 的 workspace diagnostics event cursor：store 现在同时维护 Problems snapshot cache 和 marker projection cache，收到 workspace diagnostics event 时会让两类 cache 一起失效；marker/status 路径只有初次读取、收到新 diagnostics event 或显式 apply/clear 后才读取 core marker snapshot，无新事件的重复 marker 查询会直接复用缓存。

本阶段继续保留本地 fallback diagnostics 到 marker projection 的路径，避免旧 runtime 或 core marker snapshot 失败时丢失基础 marker 展示。测试覆盖初次 marker 读取、无新事件重复读取不刷新、直接 core diagnostics 更新后 marker projection 通过 event cursor 刷新到新位置/严重级别，以及重复读取继续命中缓存。阶段 188 已把 Locations/Symbols 持久在线 panel 接到 lifecycle entry，阶段 193-194 已补 Workspace Outline store 与 core-owned snapshot/API 起点；剩余状态订阅缺口不再包括 workspace Problems/marker 的基础 cursor 消费，也不再包括 Locations/Symbols panel 的 active-edit stale 展示，而是集中在更完整 project-level result lifecycle/error 聚合。

## 阶段 188: Locations/Symbols panels consume lifecycle entries

2026-08-02 阶段 188 已让 AttoEditor 持久在线 Locations/References panel 与 Outline/Symbols panel 消费 `AttoLspResultLifecycleEntry`，而不是只保存裸 result snapshot。`AttoLspLocationPanelController` 与 `AttoLspSymbolPanelController` 现在都维护当前 lifecycle entry，因此 panel 层可以直接读取 sequence、family、title、recordedAt 和 snapshot；AreaViewController 的 show/update 路径也改为把 lifecycle store 产生的 entry 传给 panel。

本阶段不改变 quick panel、history panel、导航、过滤或已有 panel 外观，只把持久在线 panel 的数据归属接到既有 lifecycle store。测试覆盖 Locations/Symbols panel 初次打开和新结果自动刷新时，panel 当前 entry 的 sequence/family/title/snapshot 与 lifecycle store 一致。剩余工作是把这些 lifecycle metadata 继续产品化为 project/workspace 级 outline/symbol store、跨 result family 的统一 panel event cursor，以及 project-level error 聚合。

## 阶段 189: Persistent LSP panel lifecycle metadata UI

2026-08-02 阶段 189 已把 Locations/References panel 与 Outline/Symbols panel 持有的 lifecycle metadata 显示为稳定 UI 文本：两个 panel 都新增 metadata label，并带有稳定 accessibility identifier。阶段 190 后，真实 App lifecycle entry 显示 `Fresh | Result #sequence | family | title` 或 `Stale: ... | Result #sequence | family | title`，旧 snapshot-only 测试/兼容路径显示 `Fresh | Snapshot | title`。这让持久在线 panel 不再只隐式保存 metadata，而是有可见、可测试的 lifecycle 状态承载位。

本阶段不改变 panel 列表、过滤、导航或 history 行为，只为后续 stale/error 状态、project-level refresh metadata 和 panel event cursor 展示提供 UI 锚点。测试覆盖 controller 级稳定 identifier 与 snapshot metadata 文本，以及真实 Locations/Symbols App 路径在新结果自动刷新时 metadata label 随 lifecycle entry sequence/title 同步更新。阶段 190 已继续接入 active-edit stale 状态；阶段 191 已接入 active App request feedback error 状态，阶段 192 已接入 project-level error 聚合起点，阶段 193 已让 Workspace Outline App projection 复用这条 metadata UI，阶段 194 已让 Workspace Outline 优先消费 core-owned snapshot；剩余工作是补更完整跨 tab/project panel UI。

## 阶段 190: Persistent LSP panel lifecycle state UI

2026-08-02 阶段 190 已给 `AttoLspResultLifecycleEntry` 增加 Fresh/Stale/Error 状态模型，并让 Locations/References panel 与 Outline/Symbols panel metadata label 显示状态前缀。新记录的 Locations/Symbols result 默认是 Fresh；当 active 文档文本变化时，AttoEditor 会把当前 Locations/Symbols lifecycle entry 原地标为 `Stale: document edited`，同步更新已打开的持久在线 panel，并保留原 sequence/family/title/snapshot 归属；后续新结果会以 Fresh 状态记录并刷新 panel。

本阶段覆盖的是 stale 状态的产品化和 Error 状态的模型/UI 承载位。测试覆盖 lifecycle store 状态更新与 history 同步、snapshot 兼容 metadata 文本、Locations panel 与 Symbols panel 在文档编辑后从 Fresh 变为 Stale、以及新结果刷新后恢复 Fresh。阶段 191 已继续把 Locations/Symbols request feedback error 接到 panel current entry；阶段 192 已补 project-level error 聚合起点；阶段 193-194 已补 Workspace Outline store 与 core-owned snapshot/API 起点。剩余工作是继续推进更完整 project-level result lifecycle/panel UI 整合。

## 阶段 191: Persistent LSP panel request error state

2026-08-02 阶段 191 已把 Locations/References 与 Outline/Symbols 的现有 request feedback error 接到持久在线 panel lifecycle entry：当显式 location/symbol request 发现 LSP unavailable、request 发起失败、轮询超时或 take result 失败时，AttoEditor 会把当前对应 result entry 原地标为 `Error: <feature>: <status>`，并同步刷新已打开 panel 的 metadata label。现有 HUD/status feedback 仍保持原样，panel error 状态只复用同一个 `AttoLspResultFeedback.Message.statusText`，避免另起一套错误文案。

本阶段覆盖的是 active App 路径中的 current Locations/Symbols panel error 状态；不改变 quick panel、history、导航或 result event stream ABI。测试覆盖已有 Locations panel / Symbols panel 在 fresh result 后触发 LSP unavailable request，current entry 保持原 sequence/snapshot 并转为 Error metadata。阶段 192 已继续补 project-level request/result event cursor 的错误聚合起点；阶段 193-194 已补 Workspace Outline store 与 core-owned snapshot/API 起点。阶段 196 已补 open-tab WorkspaceEdit transaction 起点；剩余工作是把完整 core-owned WorkspaceEdit transaction 继续收敛。

## 阶段 192: Project LSP panel error event aggregation

2026-08-02 阶段 192 已在 AttoEditor App 层增加 project-level LSP panel error event 聚合起点：`AttoProjectLspPanelErrorEventStore` 以 bounded history 记录从 `MultiDocumentEditorUI.lspRequestEvents(after:)` 和 `lspResultEvents(after:)` drain 到的 Locations/Symbols 相关 error/timeout 事件，保留 source sequence、tab/view context、family、slot、method、request id、status 和 panel message。`AttoEditorAreaViewController.updateStatusBar()` 现在会推进 core request/result event cursor，把 `locations` family 或 definition/declaration/typeDefinition/implementation/references slot 映射到 Locations panel，把 `symbols` family 或 document/workspace symbols slot 映射到 Symbols panel，并把对应 current lifecycle entry 原地更新为 Error。

本阶段不改变 Rust ABI 或 Swift UIFFI wrapper；它消费阶段 139/141 已有的 MultiDocument project-level event 聚合。测试覆盖 project-level error event store 的 bounded/history 行为，以及 App 层 synthetic project event 对 Locations/Symbols 持久在线 panel current entry 和 metadata label 的 Error 更新。阶段 193-194 已补 Workspace Outline store 与 core-owned snapshot/API 起点，阶段 196 已补 open-tab WorkspaceEdit transaction 起点；剩余工作是把 project-level error 聚合继续产品化为跨 tab/project panel UI，并完成 core-owned WorkspaceEdit 跨文件事务。

## 阶段 193: Workspace outline store projection

2026-08-02 阶段 193 已在 AttoEditor App 层增加 opened-document workspace outline store 起点：`AttoWorkspaceOutlineStore` 以打开文档为单位保存 document symbols projection，记录 tab/core tab context、document URI/path/title、symbol count，并把多文档 symbols 聚合为一个 `Workspace Outline` snapshot。`showDocumentSymbolResultJSONInActiveTab` 和 typed document symbols result 主路径都会写入该 store；新增 `lsp.show_workspace_outline_panel` command 与 Go 菜单入口，复用现有 Symbols panel 显示 `Workspace Outline`，并继续使用 lifecycle metadata label、过滤、导航和 panel row accessibility。

本阶段不新增 Rust ABI，也不把 Swift store 作为长期 workspace 事实源；它是对当前已打开文档 document-symbol snapshots 的 App projection，为后续 core-owned workspace outline API / MultiDocument event cursor 消费提供产品锚点。测试覆盖 workspace outline store 的聚合、更新、移除、清空，以及真实 App 路径从两个 document symbol results 聚合到 workspace outline panel 的 metadata/row 展示。阶段 194 已把 outline snapshot 下沉到 core workspace / `MultiDocumentEditorUi`，阶段 195 已补打开 tab 的 core document URI metadata，阶段 196 已补 open-tab WorkspaceEdit transaction 起点；剩余工作是继续补更完整跨 tab/project panel UI、project/session/root 归属下沉与完整 core-owned WorkspaceEdit transaction。

## 阶段 194: Core-owned workspace outline snapshot

2026-08-02 阶段 194 已把 Workspace Outline 的状态归属继续下沉到 `MultiDocumentEditorUi`：Rust 层新增 `workspace_outline_snapshot()` / `workspace_outline_snapshot_json()`，按 tab order 聚合每个 tab active view 的 document symbols，保留 tab id、view index、tab title、递归 symbol count 和原始 document symbol tree；同时新增 `apply_tab_document_symbols_json(tab_id, json)`，让 App 的 document symbols 主路径可以把结果同步写入 core multi-document model。`editor-core-ui-ffi` 新增对应 C ABI、public header 和 `workspaceOutlineSnapshot` feature bit；Swift `EditorCoreUIFFI` 新增 `EcuWorkspaceOutlineSnapshot` / `EcuWorkspaceOutlineDocument` 与 `MultiDocumentEditorUI.workspaceOutlineSnapshot()` / `applyTabDocumentSymbolsJSON(...)` typed wrapper。

AttoEditor 的 `AttoWorkspaceOutlineStore` 现在优先读取 core-owned workspace outline snapshot；阶段 194 初始落地时仍用 Swift fallback 保存的 `coreTabID -> fileURL/text` 映射补足 file URI/path 导航信息，阶段 195 已继续把打开 tab 的 document URI 下沉到 core，Swift fallback 仍保留用于旧 runtime 以及当前 core 尚未拥有的 path/text 映射。测试覆盖 Rust MultiDocument snapshot、C ABI smoke、Swift typed wrapper/runtime feature、Atto runtime compatibility，以及真实 App Workspace Outline panel 在 core-backed 路径下保持 metadata/row 展示。阶段 196 已补 open-tab WorkspaceEdit transaction 起点；剩余工作是更完整的跨 tab/project panel UI、project/session 归属继续下沉，以及完整 core-owned WorkspaceEdit transaction。

## 阶段 195: Core-owned tab document URI metadata

2026-08-02 阶段 195 已把打开 tab 的文档 URI 元数据下沉到 `MultiDocumentEditorUi`：Rust `TabEntry` 新增 `document_uri`，并提供 `tab_document_uri(tab_id)` / `set_tab_document_uri(tab_id, uri)`；MultiDocument snapshot 和 Workspace Outline snapshot 现在都会输出 `document_uri`。`editor-core-ui-ffi` 新增 tab document URI getter/setter C ABI、public header 声明和 `multiDocumentTabDocumentURI` feature bit；Swift `EditorCoreUIFFI.MultiDocumentEditorUI` 新增 `tabDocumentURI(tabId:)` / `setTabDocumentURI(_:tabId:)` typed wrapper，`EcuMultiDocumentTabSnapshot` 和 `EcuWorkspaceOutlineDocument` 也新增 `documentURI` 字段。

AttoEditor 在打开 normal/preview tab 时同步 core tab title 与 document URI；保存、Save As 成功后和 WorkspaceEdit resource operation 变更打开 tab URL 后也会刷新 core URI。`AttoWorkspaceOutlineStore` 现在优先使用 core outline snapshot 自带的 `documentURI`，仅在旧 runtime 或 core 未提供 URI 时回退到 Swift 侧 `coreTabID -> fileURL/text` 映射。测试覆盖 Rust URI 元数据与 outline JSON、C ABI getter/setter/snapshot/outline、Swift wrapper/runtime feature、Atto runtime compatibility、App 打开/preview/pin core mirror URI，以及 WorkspaceEdit rename 打开 tab 后的 core URI 更新。阶段 196 已继续补齐 open-tab WorkspaceEdit transaction 起点；剩余工作是把该起点扩展为完整 core-owned 跨文件事务，并继续补 project/session/root 级归属。

## 阶段 196: MultiDocument WorkspaceEdit transaction 起点

2026-08-02 阶段 196 已把 WorkspaceEdit preview/apply 的第一层 ownership 下沉到 `MultiDocumentEditorUi`：Rust `editor-core-ui` 新增 `preview_workspace_edit_transaction(...)` / `apply_workspace_edit_transaction(...)` 及 JSON 变体，按 core-owned tab `document_uri` 解析 LSP `WorkspaceEdit`，对已打开且无 overlapping edits 的 tab 应用 `TextEdit`，preview 不修改 buffer，apply 会通过每个 tab 的 `EditorUi.lsp_apply_workspace_edit_json(...)` 保留已有 undo/dirty/layout 语义。

`editor-core-ui-ffi` 新增 multi-document WorkspaceEdit transaction C ABI、public header 声明和 `multiDocumentWorkspaceEditTransaction` feature bit；Swift `EditorCoreUIFFI.MultiDocumentEditorUI` 新增 `EcuWorkspaceEditTransactionResult` / `EcuWorkspaceEditTransactionDocument` typed wrapper 和 preview/apply API。返回 JSON 继续兼容 `AttoWorkspaceEditApplyResult` 的核心字段（`applied`、`applied_uri`、`applied_edit_count`、`skipped_uris`、`documents`），并额外提供 `mode`、`applied_uris`、`unsupported_operation_uris`、`is_open`、`tab_id`，供 App 主路径消费和 preview panel 使用。

本阶段明确仍不是完整 `PLAN.md` 阶段 4 终态：未打开本地文件、`create` / `rename` / `delete` resource operations、非 `file://` URI、version mismatch、atomic rollback、undo grouping、conflict detail、state-event transaction entry 和 rename/code action/completion/formatting App 主路径切换在阶段 196 当时仍需后续阶段完成。阶段 198 已继续补齐已打开 core tab 的 resource operations 起点；阶段 208 已把 AttoEditor WorkspaceEdit App apply helper 主路径切到 core transaction。测试覆盖 Rust MultiDocument preview/apply、C ABI smoke、Swift typed wrapper/runtime feature 与 skipped/unsupported summary。

## 阶段 197: WorkspaceEdit transaction event cursor

2026-08-02 阶段 197 已给阶段 196 的 core-owned open-tab WorkspaceEdit transaction 增加事件流起点：`MultiDocumentEditorUi` 会在 apply transaction 后记录 bounded `WorkspaceEditTransactionEvent`，包含 sequence、operation 和完整 `WorkspaceEditTransactionResult`；Rust API 新增 `workspace_edit_transaction_events_latest_sequence()`、`workspace_edit_transaction_events_after(...)` 和 JSON 变体。

`editor-core-ui-ffi` 新增 transaction events latest/json C ABI、public header 声明和 `multiDocumentWorkspaceEditTransactionEvents` feature bit；Swift `EditorCoreUIFFI.MultiDocumentEditorUI` 新增 `EcuWorkspaceEditTransactionEvent` / `EcuWorkspaceEditTransactionEventsSnapshot` typed wrapper 与 cursor API；AttoEditor runtime compatibility 把该能力列为 optional feature。测试覆盖 Rust event snapshot/JSON、C ABI smoke、Swift wrapper/runtime feature。

本阶段仍是专用 transaction event cursor，不代表完整统一 `MultiDocumentStateEvent` transaction envelope 已完成；阶段 198 已先把已打开 core tab 的 resource operations 纳入该 cursor 记录的 transaction result，阶段 204 已继续把 root-gated 未打开本地文件 resource operations 纳入同一 transaction result，阶段 208 已让 App apply helper 主路径产生该 transaction event。后续还需要把 undo grouping/conflict detail 和更完整 project/workspace lifecycle 统一到同一个事件模型。

## 阶段 198: Open-tab WorkspaceEdit resource operations

2026-08-02 阶段 198 已把 WorkspaceEdit `documentChanges` 中作用于已打开 core tab 的 resource operations 纳入 `MultiDocumentEditorUi` transaction：`rename` 会更新 core tab 的 `document_uri`，并允许后续 `TextDocumentEdit(newUri)` 命中同一个 tab；干净 open tab 的 `delete` 会关闭 core tab；干净 open tab 的 `create` + `overwrite` 会清空 tab 文本并 mark saved。preview 会模拟 rename/delete 后的 URI 映射和 open-tab 状态，避免把可应用的后续 text edits 误判为 skipped。

transaction result 新增 `applied_resource_operation_count`，Rust JSON、C ABI JSON 和 Swift `EcuWorkspaceEditTransactionResult.appliedResourceOperationCount` 均暴露该字段；transaction event cursor 继续记录完整 result，因此资源操作 apply 也会进入事件流。测试覆盖 Rust MultiDocument open-tab rename/delete/create-overwrite transaction、C ABI summary 字段，以及 Swift wrapper 对 resource operation count 和 rename 后 text edit 的读取。

本阶段仍不是完整 core-owned 跨文件 WorkspaceEdit transaction：阶段 204 已继续补齐 root-gated 未打开磁盘文件的 resource operations，但非 open-tab 目标 overwrite/replace 的产品语义、更深层 conflict/atomic 诊断、atomic rollback、undo grouping、filesystem side effect 的事务化回滚，以及 AttoEditor rename/code action/completion 主路径切换仍按 `PLAN.md` 后续阶段推进。阶段 199 已继续补齐 skipped/conflict detail 起点，阶段 200 已补齐 open-tab TextDocumentEdit version check 起点。

## 阶段 199: WorkspaceEdit transaction skipped detail

2026-08-02 阶段 199 已给 `MultiDocumentEditorUi` WorkspaceEdit transaction result 增加机器可读 `skipped_details`：每条 detail 包含 `uri`、`reason`、`operation` 和 `message`。该字段保留现有 `skipped_uris` / `unsupported_operation_uris` 兼容字段，同时为 preview panel、App 主路径消费、transaction event 消费和后续 atomic/conflict UI 提供稳定原因模型。

本阶段覆盖的 reason 包括未打开文档 text edits（`document_not_open`）、overlapping text edits（`overlapping_text_edits`）、text edit apply 返回未应用（`text_edit_apply_failed`）、resource operation 目标/源未打开、dirty open tab、target exists、target overwrite 暂不支持等。Swift `EcuWorkspaceEditTransactionResult` 新增 `skippedDetails` typed 字段，并对新字段提供默认值 decode，以便旧 runtime 缺字段时仍能保持基本兼容。

本阶段仍不实现真实 filesystem side effect、atomic rollback 或 undo grouping，也不把 App rename/code action/completion 主路径切到 core transaction；它只补齐“为什么这次 transaction 不能完整应用”的结构化反馈。阶段 200 已继续补齐 open-tab TextDocumentEdit version check 起点。测试覆盖 Rust MultiDocument detail reason、C ABI JSON 字段和 Swift typed detail decode。

## 阶段 200: Open-tab TextDocumentEdit version check

2026-08-02 阶段 200 已把 LSP `TextDocumentEdit.textDocument.version` 校验纳入 `MultiDocumentEditorUi` WorkspaceEdit transaction：Rust 侧复用 `editor-core-lsp::workspace_edit_expected_versions(...)` 解析 version constraint，并通过 `EditorUi.text_version()` 获取 open tab 当前文本版本；preview/apply 在 expected 与 actual 不一致时跳过该 URI 的 text edits，返回 `version_mismatch` skipped detail，不再把 stale edit 应用到已经变化的 open tab。

`WorkspaceEditTransactionDocument` 新增 `expected_version`、`actual_version` 和 `version_mismatch`，Swift `EcuWorkspaceEditTransactionDocument` 暴露为 `expectedVersion`、`actualVersion`、`versionMismatch`，并提供默认值 decode 以兼容旧 runtime。测试覆盖 Rust MultiDocument stale version preview/apply 跳过、Swift typed 字段 decode 和 apply 后文本保持不变。

本阶段的 version check 仅覆盖 core-owned open tab text edits；未打开磁盘文件、跨文件 filesystem side effect、atomic rollback、undo grouping，以及 App rename/code action/completion 主路径切换仍按 `PLAN.md` 后续阶段推进。阶段 201 已把该 open-tab version preflight 接入 AttoEditor WorkspaceEdit App 主路径，先关闭 stale edit 绕过 Swift fallback 的风险。

## 阶段 201: AttoEditor WorkspaceEdit core preflight

2026-08-02 阶段 201 已让 AttoEditor App 的 WorkspaceEdit 应用主路径在进入 Swift fallback 前调用 `MultiDocumentEditorUI.previewWorkspaceEditTransaction(...)`，消费 core transaction 的 `skippedDetails`。当前只把已打开 core tab 的 `text_edit` / `version_mismatch` 作为 hard block，避免 stale `TextDocumentEdit` 绕过阶段 200 的 version check 继续由 Swift fallback 应用到可见编辑器。

本阶段不把 rename/code action/completion 的完整 WorkspaceEdit apply 切到 core transaction，也不接管未打开文件和 resource operations；这些仍保留现有 Swift fallback，用于维持当前产品能力。测试覆盖打开 tab 收到 stale versioned WorkspaceEdit 时不修改编辑器文本、不写磁盘、不标 dirty。

## 阶段 202: Core-owned workspace root metadata

2026-08-02 阶段 202 已把 workspace root URI 元数据下沉到 `MultiDocumentEditorUi`：Rust model 新增 `set_workspace_roots(...)` / `workspace_roots()`，FFI multi-document snapshot 输出 `workspace_roots`，并新增 `editor_core_ui_ffi_multi_document_set_workspace_roots_json(...)` 与 `multiDocumentWorkspaceRoots` feature bit；Swift `EcuMultiDocumentSnapshot.workspaceRoots` 和 `MultiDocumentEditorUI.setWorkspaceRoots(_:)` 提供 typed wrapper。

AttoEditor 在初始化 core multi-document model 后会同步当前 `workspaceRootURL`，并在 `setWorkspaceRootURL(...)` 时继续刷新 core-owned root metadata。这个阶段不直接启用 core 磁盘写入；它先建立后续未打开文件 WorkspaceEdit text edits / resource operations 的 workspace-root gate，避免 core transaction 在没有项目边界的情况下写任意 `file://` URI。测试覆盖 Rust root 去重、C ABI feature/snapshot、Swift typed wrapper/runtime feature，以及 App core mirror 的 root 初始化与切换同步。

## 阶段 203: Root-gated unopened file text edits

2026-08-02 阶段 203 已把 `MultiDocumentEditorUi` WorkspaceEdit transaction 从打开 tab text edits 扩展到受 workspace root 约束的未打开本地文件 text edits。Rust transaction preview/apply 现在会读取 core-owned `workspace_roots`：未配置 root 时保持旧的 `document_not_open` 行为；配置 root 后，仅允许 existing regular local `file://` 文件且 canonical path 位于某个 canonical workspace root 内时进入 apply 计划。

本阶段新增的 skipped reason 包括 `unsupported_uri`、`file_not_found`、`file_not_regular_file`、`workspace_roots_unavailable`、`document_outside_workspace`、`version_unavailable` 和 `resource_operation_dependency_unsupported`。未打开文件 text edits 仍拒绝 versioned `TextDocumentEdit`，因为没有 open core document version 可校验；preview 只做路径/文件边界判断，不写文件；apply 会按 LSP UTF-16 range 转换到 core char/byte offset 并写回 UTF-8 文本文件。

测试覆盖 Rust `MultiDocumentEditorUi` root 内未打开文件 apply、root 外 skip、versioned unopened skip、C ABI transaction smoke 和 Swift `MultiDocumentEditorUI` typed wrapper 端到端路径。本阶段仍不是完整 core-owned 跨文件 WorkspaceEdit transaction：阶段 204 已继续补齐 root-gated 未打开文件 resource operations；filesystem atomic rollback、undo grouping、批量失败回滚、更深层 conflict 检测、preview panel 产品化，以及 AttoEditor rename/code action/completion 主路径完全切换仍按 `PLAN.md` 后续阶段推进。

## 阶段 204: Root-gated unopened file resource operations

2026-08-02 阶段 204 已把 `MultiDocumentEditorUi` WorkspaceEdit transaction 从未打开本地文件 text edits 扩展到 root-gated 未打开本地文件 resource operations。Rust transaction preview/apply 现在能在 core-owned `workspace_roots` 边界内处理 `documentChanges` 的 `create` / `rename` / `delete`：`create` 会创建父目录并写入空文件，`rename` 会在目标目录缺失时创建父目录并移动源文件或目录，`delete` 会删除文件，目录删除要求 LSP `recursive: true`。所有路径都必须是本地 `file://` URI，且现有路径或最近存在祖先的 canonical path 必须位于 canonical workspace root 内；root 外、缺失 root、非本地 URI、parent traversal、目录非递归删除、以及未打开源文件 rename 到已打开 target URI 等情况会作为 skipped detail 返回。

本阶段也把 resource operation 与后续 text edits 的依赖接到 transaction plan：`create` 和 `rename` 产生的新 URI 可以在同一个 WorkspaceEdit 中继续接受未打开文件 text edits；被 `delete` 或 `rename(oldUri)` 移除且没有重新产生的 URI 会跳过后续 text edits，返回 `resource_operation_dependency_removed`。preview 仍保持无副作用；apply 会先执行支持的 resource operations，再对计划内的打开 tab 或未打开本地文件应用 text edits，并把 resource operation count、applied URIs、skipped details 写入 transaction result 和 transaction event cursor。

测试覆盖 Rust `MultiDocumentEditorUi` root 内 create+text edit、rename+text edit、delete、root 外 create skip、目录非递归 delete skip、未打开源文件 rename 到已打开 target URI 的 conflict skip；C ABI JSON 路径覆盖未打开本地文件 create/rename/delete 和 root 外 skipped detail；Swift `MultiDocumentEditorUI` typed wrapper 端到端覆盖 preview 无副作用、apply count、applied/skipped URIs 和磁盘结果。本阶段仍不是 `PLAN.md` 阶段 4 终态：filesystem atomic rollback、undo grouping、批量失败回滚、更深层 conflict 检测、preview panel 产品化，以及 AttoEditor rename/code action/completion 主路径完全切换到 core transaction 仍需后续阶段完成。

## 阶段 205: WorkspaceEdit documentChanges order-preserving apply

2026-08-02 阶段 205 已让 `MultiDocumentEditorUi` WorkspaceEdit transaction 在 apply 时按 `documentChanges` 原始顺序交错执行 TextDocumentEdit 和 resource operations，不再先执行全部 resource operations 再按 URI 批量应用 text edits。打开 tab 的 text edits 也改为直接按当前 step 的 `LspTextEdit` 列表调用 `EditorUi` apply，而不是把整个 WorkspaceEdit 再交给单文档 apply helper，避免同一 URI 的 edits 被重复或跨 rename/delete 乱序应用。

本阶段同时给 preview/support 计划增加轻量 planned resource URI state：前序 `create` / `rename` / `delete` 会影响后续 resource operation 的“路径是否存在”预检，因此 `create -> text edit -> rename -> text edit` 这类合法顺序不会再被误判为 rename source missing。plan 也会同时考虑初始 open-tab URI 映射和 resource operation 模拟后的 URI 映射，保证 rename 前旧 URI 的 TextDocumentEdit 与 rename 后新 URI 的 TextDocumentEdit 都能命中同一个 core tab。apply 侧的 resource operation dependency 现在按 step 向后传播，后续失败/跳过的 resource operation 不会回溯阻塞已经位于其之前的 text edit。

测试覆盖 Rust 打开 tab `text edit old -> rename -> text edit new` 顺序 apply、未打开本地文件 `create -> text edit -> rename -> text edit` 顺序 apply，以及“前置 text edit + 后续 skipped resource operation”不回滚/不误挡的 partial-order 行为；C ABI JSON 和 Swift `MultiDocumentEditorUI` typed wrapper 也覆盖未打开本地文件顺序事务。本阶段仍不是 `PLAN.md` 阶段 4 终态：filesystem atomic rollback、undo grouping、批量失败回滚、更深层 conflict 检测、preview panel 产品化，以及 AttoEditor rename/code action/completion 主路径完全切换到 core transaction 仍需后续阶段完成。

## 阶段 206: WorkspaceEdit filesystem failure rollback 起点

2026-08-02 阶段 206 已为 `MultiDocumentEditorUi` WorkspaceEdit transaction 的 root-gated 未打开本地文件 resource operations 增加运行时 filesystem error rollback 起点。apply 过程中会记录 create / rename / delete 的文件系统补偿动作：新建文件和新建父目录在失败回滚时移除；overwrite create、overwrite rename 和 delete 会先把既有目标移动到同目录临时 backup；rename 成功后会记录反向 move。后续支持的 resource operation 如果遇到 fatal I/O 错误，transaction 会撤销这些已记录的未打开本地文件副作用，再把错误通过 Rust、C ABI 和 Swift wrapper 抛出。

本阶段覆盖的失败模型是“已经进入 apply、并且 resource operation 运行时抛出错误”的补偿回滚；preview-time skipped/conflict 仍按 skipped detail 返回，text edits 的 apply 失败仍保持 partial/skipped 语义。本阶段也不会回滚已应用的打开 tab 编辑或关闭/重命名 tab 状态，不提供完整 batch atomic apply mode，也不等同于 undo grouping。也就是说，阶段 206 只把最危险的磁盘副作用从“失败后可能残留”推进到“未打开本地 resource operation 可补偿回滚”的起点；完整 `PLAN.md` 阶段 4 终态仍包括 undo grouping、批量失败回滚、更深层 conflict 检测、preview panel 产品化和 AttoEditor App 主路径完全切换。

测试覆盖 Rust `MultiDocumentEditorUi` 的 `create -> overwrite rename -> failing create` 场景：后续 create 因父路径是普通文件而报错，前序新建文件/父目录被移除，overwrite rename 的源文件和被覆盖目标文件内容恢复，transaction event 不记录失败 apply。Swift `MultiDocumentEditorUI` typed wrapper 端到端测试覆盖同一错误通过 FFI 抛出，并验证磁盘状态恢复。

## 阶段 207: Open-tab local resource filesystem side effects

2026-08-02 阶段 207 已把 `MultiDocumentEditorUi` WorkspaceEdit transaction 中“已打开 tab 的本地 resource operation”从纯 core tab 状态更新推进到 root-gated 文件系统副作用。现在当 `workspace_roots` 可解析且打开 tab 的 `document_uri` 是 root 内本地 `file://` 路径时，打开 tab 的 `create` / `rename` / `delete` 会复用与未打开文件相同的 filesystem helper 和 rollback log：`rename` 会移动磁盘文件并更新 core tab document URI，后续 TextDocumentEdit 继续命中重命名后的 tab；`delete` 会移除磁盘文件并关闭 clean core tab；`create` + overwrite 会清空磁盘文件并把 clean open tab 文本替换为空且 mark saved。

本阶段保留无 workspace root 或非本地 URI 的既有 in-memory open-tab resource operation 行为，避免破坏已有无 root 测试和非文件 URI 场景。它为 AttoEditor App 后续把 WorkspaceEdit apply 主路径切到 core transaction 做准备：core transaction 现在同时覆盖未打开本地文件和打开本地 tab 的 resource operation 磁盘副作用。阶段 207 当时仍不是完整 `PLAN.md` 阶段 4 终态：打开 tab 文本/关闭/URI 状态仍没有 undo grouping，完整 batch atomic rollback、preview panel 产品化和更深层 conflict 检测仍需后续阶段完成；阶段 208 已继续完成 App apply helper 主路径切换。

测试覆盖 Rust `MultiDocumentEditorUi` 的 root-gated open-tab rename/delete/create overwrite 磁盘副作用和原有无 root in-memory 行为；C ABI 直接测试同一路径；Swift `MultiDocumentEditorUI` typed wrapper 端到端验证磁盘 old->renamed、delete 移除、overwrite 清空，以及 core tab text/document URI/close state 同步。

## 阶段 208: AttoEditor WorkspaceEdit core transaction 主路径

2026-08-02 阶段 208 已把 AttoEditor 的 `applyWorkspaceEditJSONToActiveTab` / `applyWorkspaceEditToActiveTab` 主路径切到 `MultiDocumentEditorUI.applyWorkspaceEditTransaction(...)`。rename、code action 和 completion additional edits 共享的 WorkspaceEdit apply helper 会先把当前打开 tab 的文本、document URI、dirty state 和 active view 差异同步到 core multi-document model，再由 core transaction 统一处理打开 tab、未打开本地文件、`TextDocumentEdit` version check 和 root-gated `create` / `rename` / `delete` resource operations。

apply 后，AttoEditor 会从 core snapshot 拉回 AppKit 投影：已被 core resource operation 关闭的 tab 会从 App tabs 中移除；被 rename 的 tab 会更新 `fileURL` / document URI；打开 tab 文本会从 core tab text 全量刷新回对应 `EditorUI`，dirty / preview 状态也以 core snapshot 为准。旧的 Swift parser/apply 路径仍保留为 `coreDocuments` 不可用时的 fallback，不再作为正常 App 主路径。

测试覆盖 App 层 WorkspaceEdit text edits、打开跨文件 tab、未打开本地文件 resource operations、打开 tab rename/delete/create overwrite、dirty open tab delete 保护、Swift dirty cache stale 时的 core dirty 保护，以及 stale `TextDocumentEdit.version` 不会被 App fallback 绕过。每个相关 App 测试都断言 core WorkspaceEdit transaction event cursor 前进，证明主路径经过 core transaction。

阶段 208 仍不是 `PLAN.md` 阶段 4 终态：当前 AppKit 投影使用全量文本刷新，不等同于打开 tab undo grouping；preview/confirmation UI、text edits 与打开 tab 状态变更的完整 batch atomic rollback，以及更深层 conflict UI 仍需后续阶段补齐。阶段 209 已继续补齐基础 preview/confirmation 起点。

## 阶段 209: WorkspaceEdit core preview confirmation 起点

2026-08-02 阶段 209 已让 AttoEditor 在执行 core-owned WorkspaceEdit transaction 前消费 `MultiDocumentEditorUI.previewWorkspaceEditTransaction(...)`，并把 core preview result 和已解析的 WorkspaceEdit 合并成 `AttoWorkspaceEditPreview` display model。该 model 会列出计划影响的文档、edit 数量、resource operation 数量、open/unopened 状态，以及 core 返回的 skipped/conflict detail。

App 主路径现在会在跨文档、未打开文件、resource operation 或 skipped/conflict 影响出现时展示同步 AppKit 确认 UI；用户选择 Apply 后才调用 `applyWorkspaceEditTransaction(...)`，选择 Cancel 时不执行 core apply，也不会推进 WorkspaceEdit transaction event cursor。单个已打开文档的普通 text edit 不弹确认，保持高频补全/轻量编辑路径不被额外打断。

测试覆盖 preview display model、单文档免确认、resource operation preview 文案、skipped detail 文案，以及 App 层取消确认时编辑器文本、磁盘文件和 core transaction event cursor 均不变化。本阶段当时仍不是完整 preview panel 产品化：阶段 210 已继续把基础确认 alert 推进为专用可导航 diff preview panel 起点；打开 tab undo grouping、完整 batch atomic rollback 和更深层 conflict UI 仍需后续阶段补齐。

## 阶段 210: WorkspaceEdit 专用 diff preview panel 起点

2026-08-02 阶段 210 已把 AttoEditor 的 WorkspaceEdit 确认入口从基础 `NSAlert` 推进到专用 `AttoWorkspaceEditPreviewPanelController`。该 panel 使用稳定 accessibility identifier，左侧按受影响文件/resource operation/skipped/unsupported section 导航，右侧显示 text edit 的行级 diff、resource operation 参数、skipped reason/message 或 unsupported 说明。

`AttoWorkspaceEditPreview` 现在携带 `Section` detail model；`AttoWorkspaceEditPreviewDetailBuilder` 会基于已解析 WorkspaceEdit、core preview result、当前打开 tab 文本或本地文件文本生成 per-file diff。App 主路径在执行 core transaction 前填充这些 sections，测试 hook 仍优先返回 apply/cancel，避免自动化测试弹出 modal UI。

测试覆盖 text edit diff section、resource operation section，以及 App 取消确认路径中捕获的 preview 已包含按文件 diff sections。本阶段仍不是 `PLAN.md` 阶段 4 终态：panel 还不是可筛选/可展开树形 diff，也没有把打开 tab undo grouping、完整 batch atomic rollback 和更深层 conflict UI 一起补齐。

## 阶段 211: 未打开 WorkspaceEdit text edit filesystem rollback

2026-08-02 阶段 211 已让 `MultiDocumentEditorUi` 的 root-gated 未打开本地文件 text edits 接入与 resource operations 相同的 filesystem rollback log。对未打开文件应用 text edit 时，core transaction 会在写入前备份原文件；如果写入本身失败，会立即局部恢复；如果后续 resource operation 发生 fatal runtime failure，则随整批 rollback 恢复这些已写入的未打开文件。

该阶段补齐的是 batch atomic rollback 的一个关键缺口：此前 create/rename/delete resource operations 的磁盘副作用可以回滚，但已经成功写盘的未打开文件 text edits 不会随同恢复，可能留下半应用 WorkspaceEdit。现在 Rust core、C ABI 和 Swift wrapper 都覆盖了 “text edit 写入后，后续 create 因路径冲突失败，目标文件恢复原文，transaction event cursor 不前进” 的回归路径。

本阶段当时仍不是 `PLAN.md` 阶段 4 终态：打开 tab 的文本修改和 tab/resource 状态变更仍没有统一 rollback/undo grouping；阶段 212 已继续补齐 fatal failure 下的打开 tab 状态 rollback，阶段 213 已继续补齐显式 atomic apply mode；完整 undo grouping 和更深层 conflict UI 仍需后续阶段补齐。

## 阶段 212: 打开 tab WorkspaceEdit transaction failure rollback

2026-08-02 阶段 212 已让 `MultiDocumentEditorUi` 在 WorkspaceEdit resource operation 发生运行时 fatal failure 时恢复已经被同一 transaction 修改过的打开 tab 状态。新的打开 tab rollback log 会在第一次修改前记录文本和 dirty 状态，在 rename 前记录 document URI，在 delete close 前记录 tab entry、tab order、active tab 和 preview tab 指针；fatal failure 时与 filesystem rollback 一起执行恢复。

该阶段覆盖的半应用路径包括：打开 tab text edit 已经应用后，后续本地文件 create 因路径冲突失败；打开 tab rename 已经改过 URI 或磁盘路径后失败；打开 tab delete 已经关闭 tab 后失败。Rust core、C ABI 和 Swift wrapper 都新增了同一条回归测试，断言失败后 tab 文本、dirty 状态、document URI、被关闭 tab、active tab、磁盘文件和 transaction event cursor 都回到事务前状态。

本阶段仍不是 `PLAN.md` 阶段 4 终态：当前 rollback 是 transaction fatal failure 的内部补偿日志，不等同于用户可见 undo grouping；conflict 检测/展示，以及更完整的 preview tree/filter UI 仍需后续阶段补齐。

## 阶段 213: WorkspaceEdit 显式 atomic apply mode 起点

2026-08-03 阶段 213 已为 `MultiDocumentEditorUi` 的 WorkspaceEdit transaction JSON API 增加兼容 envelope：原始 LSP `WorkspaceEdit` 输入仍按默认 `partial` apply mode 执行；调用方也可以传入 `{"applyMode":"atomic","workspaceEdit":{...}}`，要求 apply 前先完成 preflight。transaction result 新增 `apply_mode` 字段，Swift `EcuWorkspaceEditTransactionResult.applyMode` 会 typed 解码该字段，并对旧 JSON 缺字段时默认 `partial`。

atomic apply mode 的当前语义是：如果 preflight 已发现任何 skipped/unsupported detail，apply 不会修改任何打开 tab 或本地文件，而是返回 `applied=false`、`apply_mode="atomic"`、`applied_edit_count=0`、`applied_resource_operation_count=0` 的结构化 result，并记录一次 transaction event。默认 partial 路径保持不变，仍允许可应用部分先落地、skipped detail 作为结构化反馈返回。

测试覆盖 Rust core、C ABI JSON 和 Swift wrapper：同一个 WorkspaceEdit 中包含一个可应用的打开 tab text edit 和一个会因 dirty open tab 被 skipped 的 delete operation；atomic apply 后两个 tab 文本/dirty 状态均保持原样，transaction event 记录 atomic result。本阶段仍不是 `PLAN.md` 阶段 4 终态：阶段 214 已继续补齐打开 tab App 投影 undo grouping 起点；更深层 conflict 检测/展示，以及更完整的 preview tree/filter UI 仍需后续阶段补齐。

## 阶段 214: 打开 tab WorkspaceEdit App 投影 undo grouping 起点

2026-08-03 阶段 214 已让 AttoEditor App 在从 core WorkspaceEdit transaction snapshot 投影回已打开 tab 时，为发生文本变化的打开 tab 显式封闭 `EditorUI` undo group。core transaction 主路径仍由 `MultiDocumentEditorUI.applyWorkspaceEditTransaction(...)` 执行；Swift/AppKit 层只在同步 core snapshot 到当前 UI editor buffer 后调用 `endUndoGroup()`，避免 WorkspaceEdit 投影与后续用户输入继续合并。

本阶段同时让旧 Swift fallback 的打开 tab 全量替换 helper 采用同样的 undo group 边界，保证迁移期主路径和 fallback 对用户可见 undo 行为一致。测试覆盖两个已打开 tab 被同一个跨文件 WorkspaceEdit 修改后，用户分别在每个 tab 执行一次 Undo 都能回到 WorkspaceEdit 应用前文本。

本阶段仍不是 `PLAN.md` 阶段 4 终态：它只覆盖打开 tab 的 App 投影 undo group，不实现跨文件全局 undo command，不为未打开本地文件 text edit 或 resource operation 提供用户级 undo，也不完成更深层 conflict 检测/展示。

## 阶段 215: WorkspaceEdit atomic apply 运行时失败回滚

2026-08-03 阶段 215 已把显式 `atomic` apply mode 从 preflight-only 推进到 text edit apply 阶段的运行时失败回滚。若 atomic transaction 在 preflight 后先应用了部分打开 tab 或 root-gated 本地文件副作用，随后又因运行时 text edit 失败产生新的 skipped detail，`MultiDocumentEditorUi` 会复用已有 filesystem/open-tab rollback log 回滚已应用副作用，并返回 `applied=false`、`applied_edit_count=0`、`applied_resource_operation_count=0` 的结构化 result。

测试覆盖一个 atomic WorkspaceEdit 先修改已打开 tab，再尝试编辑 workspace root 内未打开但不是 UTF-8 的本地文件；未打开文件读取失败后，打开 tab 文本会恢复到事务前内容，坏文件字节保持不变，transaction event 记录 atomic result 且 `applied_uris` 为空。Swift wrapper 通过 `MultiDocumentEditorUI.applyWorkspaceEditTransaction(...)` 覆盖同一场景。

本阶段仍不是 `PLAN.md` 阶段 4 终态：它不改变默认 partial apply 语义，不新增 ABI 函数，不提供跨文件用户级 undo command，也不完成更深层 conflict 检测/展示。

## 阶段 216: WorkspaceEdit resource-order dependency preflight

2026-08-03 阶段 216 已让 `MultiDocumentEditorUi` 的 WorkspaceEdit transaction plan 按 `WorkspaceEdit.documentChanges` 顺序提前识别 resource operation 与 text edit 的删除依赖：如果前序 `delete` 或 `rename` 已移除某个 URI，而后续 `TextDocumentEdit` 仍编辑同一 URI，preview 和 atomic preflight 会返回 `resource_operation_dependency_removed` skipped detail。

这补齐了阶段 215 后的一个重要 atomic 缺口：此前同类依赖只在 apply 运行时被 `runtime_removed_text_edit_uris` 捕获，atomic mode 可能先执行删除/rename 再回滚；现在 preview 结果已经能暴露该冲突，atomic apply 会在修改任何打开 tab 或本地文件前返回 `applied=false`、edit/resource counts 为 0 的结构化 result。默认 `partial` apply 仍保持既有运行时语义和结构化 skipped feedback。

测试覆盖 Rust core 和 Swift wrapper：同一个 atomic WorkspaceEdit 先 `delete` 已打开 clean tab 的 URI，再对同一 URI 追加 text edit；preview 能看到 `resource_operation_dependency_removed`，apply 不关闭 tab、不改文本、不增加 applied counts。该阶段仍不新增 ABI 函数，也不完成全量 conflict UI、跨文件用户级 undo command 或完整 transaction-wide undo 语义。

## 阶段 217: WorkspaceEdit ordered unsupported dependency preflight

2026-08-03 阶段 217 已把 `MultiDocumentEditorUi` transaction plan 中 unsupported resource operation 对 text edit 的影响从全局 URI 标记收敛为 `WorkspaceEdit.documentChanges` 顺序语义：前序 unsupported resource operation 会阻断后续命中同一 URI 的 text edit，并在 preview 中返回 `resource_operation_dependency_unsupported`；后置 unsupported resource operation 不再让前序 text edit 的 preview 误报 dependency block。

这让 preview/conflict detail 更贴近实际 partial apply 行为：默认 partial 路径中，先出现的 text edit 仍可在后续 resource operation skipped 时落地；如果 unsupported resource operation 在前，后续 text edit 会在 apply 时返回 `resource_operation_dependency_skipped` 并保持文本不变。atomic apply 仍会因为同一 transaction 已存在 skipped detail 而在 preflight 阶段拒绝修改。

测试覆盖 Rust core 和 Swift wrapper：同一个 WorkspaceEdit 中，`create` 已打开 URI 因 `resource_operation_create_exists` 被跳过后，后续 text edit 会在 preview 中标出 ordered dependency；反向顺序的既有 partial 测试也新增断言，确认前序 text edit 不再被 preview 误标为 `resource_operation_dependency_unsupported`。该阶段仍不新增 ABI 函数，也不完成全量 conflict UI、跨文件用户级 undo command 或完整 transaction-wide undo 语义。

## 阶段 218: WorkspaceEdit resource operation typed summary

2026-08-03 阶段 218 已把 `MultiDocumentEditorUi` 的 WorkspaceEdit transaction result 从 resource operation 计数推进到 typed operation summary。Rust result JSON 新增兼容字段 `resource_operations`，每项包含 `kind`、`uri` / `old_uri` / `new_uri`、`affected_uris`、`supported` 和 `applied`；preview result 会列出计划中的 resource operations，apply result 会标记真实已经应用的 resource operations，atomic rollback 结果会清理 applied 标记，避免把已回滚副作用误报为 applied。

Swift `EcuWorkspaceEditTransactionResult` 已新增 `resourceOperations` typed decoder，缺字段时默认空数组以兼容旧 JSON。AttoEditor 的 `AttoWorkspaceEditPreview` 在没有 Swift parser 结果时也能消费 core result 中的 resource operation summary，计算 resource operation 数量和 affected URIs，避免 preview 只能依赖 `applied_resource_operation_count` 或 Swift-side parser。

测试覆盖 Rust core、Swift UIFFI wrapper 和 Atto preview model：打开 tab rename/create/delete transaction 的 preview 会返回 supported-but-not-applied 的 resource operation summary，apply 后会返回 applied resource operation summary；Swift wrapper 能 typed 读取 rename 的 old/new/affected URI 和 applied flag；Atto preview model 能仅凭 core `resource_operations` 生成 resource operation summary 和 confirmation。该阶段仍不新增 ABI 函数，也不完成全量 conflict UI、跨文件用户级 undo command 或完整 transaction-wide undo 语义。

## 阶段 219: WorkspaceEdit dirty/conflict typed summary

2026-08-03 阶段 219 已把 `MultiDocumentEditorUi` 的 WorkspaceEdit transaction result 从 raw skipped details 进一步推进到 dirty/conflict typed summary。Rust result JSON 新增兼容字段 `documents[].is_dirty`、`dirty_document_uris` 和 `conflicts`；每个 conflict 包含 `kind`、`uri`、`reason`、`operation` 和 `message`，会把 dirty open tab、version mismatch、overlapping edits、resource dependency、resource target conflict、workspace boundary、missing resource、unsupported URI 和 apply failure 等既有 skipped reason 归类为稳定 kind。

Swift `EcuWorkspaceEditTransactionResult` 已新增 `dirtyDocumentURIs` 和 `conflicts` typed decoder，`EcuWorkspaceEditTransactionDocument` 也新增 `isDirty`，缺字段时全部使用默认值以兼容旧 JSON。AttoEditor 的 WorkspaceEdit preview/panel 已开始消费 typed conflicts：summary 文本会把这些 blocker 显示在独立 `Conflicts` 区块，detail panel 会生成 conflict section，并避免同一个 blocker 作为 skipped detail 重复展示；dirty 文档也会在文件行和 detail subtitle 中显示。

测试覆盖 Rust core、Swift UIFFI wrapper 和 Atto preview model：dirty open tab 的 resource operation 会出现在 `dirty_document_uris`、`documents[].is_dirty` 和 `conflicts.kind == "dirty_document"`；version mismatch、overlapping text edit 和 missing document 会被归类为对应 conflict kind；Swift wrapper 能 typed 读取 dirty/conflict 字段；Atto preview model 能展示 conflict summary 和 detail section。本阶段仍不新增 ABI 函数，也不改变 WorkspaceEdit preview/apply 语义；剩余缺口仍包括更完整 conflict UI、跨文件用户级 undo command 和完整 transaction-wide undo。

## 阶段 220: WorkspaceEdit transaction-wide undo 起点

2026-08-03 阶段 220 已为 `MultiDocumentEditorUi` 最近一次成功的 WorkspaceEdit transaction 增加 core-owned 一次性 undo 起点。Rust UI 层会在 apply 成功后保留同一 transaction 的 open-tab rollback log 和 filesystem rollback log；新的 transaction 会先丢弃旧 undo record，undo 成功或失败后该 record 都会被消费，避免上层误以为已有多级 undo stack。

该 undo 起点覆盖已打开 tab 和 root-gated 本地文件两类副作用：打开 tab 可恢复文本、dirty 状态、document URI、被关闭 tab、tab order、active tab 和 preview tab；文件系统可恢复未打开本地文件 text edits，以及 create/rename/delete/overwrite 等 resource operation 产生的本地文件副作用。`editor-core-ui-ffi` 已新增 undo JSON ABI，Swift `MultiDocumentEditorUI` 已新增 `EcuWorkspaceEditTransactionUndoResult` typed wrapper，AttoEditor App 也已有测试入口可在 core undo 后把 AppKit tab 投影同步回当前 UI。

测试覆盖 Rust core、C ABI、Swift UIFFI wrapper 和 AttoEditor App 投影：同一 WorkspaceEdit 修改打开 tab 与未打开文件后，undo 会恢复 tab 文本/dirty 状态和磁盘文件；第二次 undo 返回 no-op summary；App 层测试断言 core undo 后当前 editor 文本、未打开文件内容和窗口 dirty dot 都恢复。本阶段仍不是完整用户级 WorkspaceEdit undo 产品化：它只提供最近一次 transaction 的一次性 core-owned undo，不提供多级 undo/redo stack、全局 AppKit Undo 菜单命令、跨 transaction conflict resolution 或专用 undo UI；剩余缺口收窄为更完整 conflict UI、跨文件用户级 undo command 和多级/global transaction-wide undo 语义。

## 阶段 221: WorkspaceEdit undo command/menu/keymap 起点

2026-08-03 阶段 221 已把最近一次 core-owned WorkspaceEdit transaction undo 从测试入口推进到用户可触达的 AttoEditor command 路径。UI FFI 新增 `ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_UNDO` feature bit，Swift `EditorCoreUIFFIFeatures` 和 AttoEditor runtime compatibility optional feature list 已同步该能力，`workspace.undo_last_workspace_edit` command 会在 runtime 不支持该 bit 时禁用。

App 层新增 `Workspace: Undo Last Workspace Edit` command、Edit 菜单项 `Undo Last Workspace Edit` 和默认 `cmd+option+z` binding；命令调用既有 `MultiDocumentEditorUI.undoLastWorkspaceEditTransaction()` wrapper，再把 core state 同步回 AppKit tab 投影。这让跨文件 WorkspaceEdit 的最近一次撤销可通过统一 command/menu/keymap 路径触达，而不是只靠测试 hook 或内部 helper。

测试覆盖 feature flag、runtime optional feature 报告、command registry metadata/schema、runtime gate、菜单 key equivalent，以及通过 `AttoAppDelegate.executeCommand(id: "workspace.undo_last_workspace_edit")` 恢复打开 tab 文本、窗口 dirty 状态和未打开文件内容。本阶段仍不是多级/global transaction undo 终态：命令只消费最近一次 core undo record，不接入 AppKit `UndoManager` 多级栈，不提供 redo，也不解决跨 transaction conflict resolution；剩余缺口收窄为更完整 conflict UI 和多级/global transaction-wide undo/redo 语义。

## 阶段 222: Session snapshot core tab projection 起点

2026-08-03 阶段 222 已让 AttoEditor session snapshot 保存路径优先消费 `MultiDocumentEditorUI.snapshot()`。保存时的 tab 顺序、active tab、preview 状态、pane/view 数量和 active pane/view index 现在来自 core `MultiDocumentEditorUi` snapshot；Swift 侧 `tabs` 数组只继续提供 AppKit-only 信息，例如文件对应的 `EditCoreUI`、minimap 偏好和 core 不可用时的兼容 fallback。

该阶段是阶段 5 “多文档、tab、split、project、session 完整迁移”的小步收敛：Swift/AppKit 仍负责 view controller 和 UI projection，但 session 持久化中最容易形成长期事实源的 tab/order/active-view 状态已开始以 core workspace snapshot 为准。若 core runtime 不可用、tab 没有 core id，或 core snapshot 读取失败，保存路径会回退到原有 Swift-only snapshot，避免破坏现有启动与兼容行为。

测试覆盖 AppKit tabs 与 core snapshot 人为产生顺序/active view 分歧时，`makeSessionSnapshot()` 会按 core tab order、active tab 和 active view index 写出 session；既有 session restore split-pane 测试继续确认恢复后的 pane count/active pane 会同步回 core mirror。本阶段仍不实现 pane layout tree、拖拽 tab 到 split、完整 project/session schema migration 或 LSP lifecycle 与 workspace roots 的完整下沉。

## 阶段 223: Opened-files/sidebar/tab-bar core projection 起点

2026-08-03 阶段 223 已把 AttoEditor opened-files/sidebar/tab-bar 相关投影切到同一套 core tab snapshot helper。`openFileURLs()`、`openFileItems()` 和 `refreshTabBar()` 在 `MultiDocumentEditorUI.snapshot()` 可用且所有 AppKit tab 都有 core tab id 时，会按 core tab order 输出文件列表，并使用 core active tab、preview 和 dirty 状态生成 selected id、tab chip title、sidebar/opened-file item。

这让 opened files 侧栏、tab bar 刷新回调、recent/open-file 枚举与阶段 222 的 session 保存使用同一事实源，减少 Swift `tabs` 数组继续承担长期 tab/order/dirty 语义的范围。core 不可用、core tab id 缺失、重复或 snapshot 读取失败时仍回退到原有 Swift projection，保持兼容。

测试覆盖 core snapshot 与 Swift 本地 tab 数组人为分歧时，`openFileItems()` 和 `refreshTabBar()` 通过 `onOpenFilesChanged` 发出的顺序、selected tab 和 dirty title 都以 core snapshot 为准。本阶段仍不改变实际 AppKit content selection 切换，不实现 drag/drop tab-to-split、pane layout tree 或完整 project/session schema migration。

## 阶段 224: Active-tab core projection 起点

2026-08-03 阶段 224 已让 AttoEditor 的 `activeTab` 查询优先消费 core `MultiDocumentEditorUi` snapshot 中的 active tab。core snapshot 可用且 AppKit tab/core tab id 映射完整时，command keymap context、窗口标题、状态栏等既有 active-tab 消费路径会自然跟随 core active tab；core 不可用或映射不完整时仍回退到 Swift `selectedTabID`。

这进一步减少 Swift `selectedTabID` 作为长期事实源的范围，使阶段 223 中 tab-bar/opened-files 已经展示出来的 core active tab 与命令上下文、窗口标题保持一致。本阶段刻意不自动切换 AppKit content view，也不改变用户选择 tab 的命令路径；这些仍留给后续 AppKit projection 收敛。

测试覆盖 Swift 本地 selected tab 与 core active tab 人为分歧时，`activeTab`、`keymapContextForActiveState()` 的 `file_name` / `file_extension` 和窗口标题都按 core active tab 生成。本阶段仍不实现 pane layout tree、AppKit content selection projection、拖拽 tab-to-split 或完整 project/session schema migration。

## 阶段 225: AppKit active content core projection 起点

2026-08-03 阶段 225 已让 `refreshTabBar()` 在已有 core tab snapshot projection 时同步 AppKit content host 到 core active tab。若 core active tab 与 Swift `selectedTabID` 分歧，AttoEditor 会更新 `selectedTabID`、展示对应 tab 的 `EditCoreUI` content、切换 status observer、刷新 always-poll processing、status bar、window title 和 find state。

这补上阶段 224 后的一个直接分叉：此前 command context 和窗口标题可以跟随 core active tab，但编辑区内容仍可能停留在旧的 Swift selected tab。现在 tab-bar/opened-files projection、active-tab 查询和 AppKit content host 在刷新路径上使用同一个 core active tab 事实源。core snapshot 不可用或映射不完整时仍保持原有 Swift projection。

测试覆盖 Swift selected tab 与 core active tab 人为分歧时，`refreshTabBar()` 会把 content host 从旧 tab 的 editor view 切到 core active tab 的 editor view，并更新 `selectedTabID`。本阶段仍不实现 pane layout tree、拖拽 tab-to-split 或完整 project/session schema migration。

## 阶段 226: Tab group close core projection 起点

2026-08-03 阶段 226 已新增 `file.close_other_tabs` 和 `file.close_tabs_to_right` 用户命令，并把 File 菜单和 command palette 接到对应 AppKit 方法。关闭目标不再按 Swift `tabs` 数组直接推断，而是优先使用 core `MultiDocumentEditorUi.snapshot()` 中的 active tab 与 tab order；core projection 不可用时仍回退 Swift 顺序。

实现上，App 先按 core projection 计算 group-close 目标，再逐个复用既有 `closeTab` 路径，因此 dirty/save/cancel 保护语义保持不变。`closeActiveTab()` 也改为使用 core-backed `activeTab`，避免 core active tab 与 Swift `selectedTabID` 暂时分歧时关闭错误文档。

测试覆盖 core tab order 被人为调整、Swift 本地数组仍保持原始打开顺序时，Close Tabs to Right 只关闭 core active tab 右侧的 tab，随后 Close Other Tabs 只保留 core active tab，并验证 AppKit opened-files projection 与 core snapshot 保持一致。本阶段仍不实现拖拽 tab-to-split、pane layout tree、完整 close-all/restore schema 迁移或 project/LSP lifecycle 归属下沉。

## 阶段 227: Close-all core projection 起点

2026-08-03 阶段 227 已新增 `file.close_all_tabs` 用户命令，并把 File 菜单和 command palette 接到 `closeAllTabsForWindow()`。Close All Tabs 的关闭目标顺序优先来自 core `MultiDocumentEditorUi.snapshot()` 中的 tab order；core projection 不可用时回退 Swift 顺序。

实现继续复用阶段 226 的 group-close helper，因此每个 tab 的 dirty/save/cancel 保护仍走既有 `closeTab` 路径。测试通过人为移动 core tab order 后断言 `onDidCloseFile` 通知顺序跟随 core snapshot，并验证 AppKit tab 列表、opened-files projection 和 core snapshot 都清空。

本阶段补齐的是用户级 close-all 操作入口和 core order projection 起点，仍不等于完整 session schema migration、pane layout tree、tab drag/drop split 或 project/LSP lifecycle 归属下沉。

## 阶段 228: Opened-files selection core URI projection 起点

2026-08-03 阶段 228 已让 `selectFile(url:)` 和 `openFile(url:mode:)` 的 existing-tab 查找优先使用 core `MultiDocumentEditorUi.snapshot()` 中的 `document_uri` 投影。这样 opened-files/sidebar 已经展示 core URI 时，用户选择该条目或再次打开同一投影文件，会命中现有 AppKit tab，而不是只按 Swift `tab.fileURL` 查找。

实现新增 App 层 projected file lookup helper：core projection 完整时按 projected file URL 匹配，core snapshot 不可用或映射不完整时回退 Swift 本地 `tabs`。本阶段不主动重写 `tab.fileURL`，因此仍保留现有 WorkspaceEdit projection/apply 路径负责真正的本地 URL 同步。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，`openFileItems()` 显示新 URI，`selectFile(newURL)` 可以选中原 tab，`openFile(newURL)` 不会创建重复 tab，且 core snapshot tab 数保持不变。本阶段仍不实现 session schema migration、project root ownership、pane layout tree 或 drag/drop split。

## 阶段 229: Open-with-location core URI projection 起点

2026-08-03 阶段 229 已让 `openFile(url:mode:location:)` 在打开 core-projected existing tab 后，用同一套 core `document_uri` projection 校验 active tab URL，再执行行列导航。此前阶段 228 已能按 core URI 找到并选中 tab，但 location guard 仍比较 Swift 本地 `tab.fileURL`，在 URI 分歧时会跳过导航。

实现新增 projected file URL helper：core projection 完整时读取当前 tab 在 snapshot 中的 projected URL，否则回退 Swift 本地 URL。该 helper 只用于 open-with-location 的 active-tab guard，不改变 LSP location parser、jump history 或真实 `tab.fileURL` 同步策略。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，用新 URL 和 `line:column` 打开文件会复用原 tab，并把 caret 移到请求的 zero-based line/column。本阶段仍不实现 project root ownership、session schema migration、pane layout tree 或 drag/drop split。

## 阶段 230: Opened-scope search core URI projection 起点

2026-08-03 阶段 230 已让 `findInOpenTabs(query:)` 在消费 core `searchAllTabs` 匹配结果时，同步使用 core tab snapshot 的 `document_uri` 投影作为 SearchResult URL。此前 opened scope 的文本匹配已经来自 core mirror，但结果 URL 仍取 Swift 本地 `tab.fileURL`，在 core URI 与 Swift 本地 URL 分歧时会把旧路径带到 Find in Files 面板。

实现上只在 opened-tab search 结果组装前构建 `coreTabID -> projected file URL` 映射；core projection 不完整或不可用时继续回退 Swift 本地 URL。该阶段不改变 project-wide filesystem search、search panel UI、session schema、LSP location parser 或真实 `tab.fileURL` 同步策略。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，未保存文本仍由 core open-tab search 命中，并且返回结果 URL 使用 core-projected 路径。本阶段仍不实现 project root ownership、pane layout tree、drag/drop split 或跨项目 search index。

## 阶段 231: LSP target navigation core URI projection 起点

2026-08-03 阶段 231 已让 `navigateToLspTarget(_:)` 在打开或复用 LSP target URI 对应 tab 后，用 core tab snapshot 的 `document_uri` 投影校验 active tab URL。此前 `openFile(url:mode:)` 已能按 core URI 复用 existing tab，但 LSP target navigation 的后续 guard 仍比较 Swift 本地 `tab.fileURL`，在 URI 分歧时会跳过 caret 移动。

实现上把 projected file URL helper 从 `Tabs.swift` 文件私有放宽到 `AttoEditorAreaViewController` 扩展可复用，并只迁移 LSP location navigation 的 active-tab guard。该阶段不改变 LSP result parser、location quick panel、jump history、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，LSP target 指向新 URI 会复用原 tab，并把 caret 移到目标 LSP UTF-16 line/character。本阶段仍不实现 project root ownership、pane layout tree、drag/drop split 或完整 project/LSP lifecycle 迁移。

## 阶段 232: WorkspaceEdit preview text core URI projection 起点

2026-08-03 阶段 232 已让 WorkspaceEdit diff preview 的 `workspaceEditPreviewText(for:)` 按 core tab snapshot 的 `document_uri` 投影查找打开 tab。此前 preview text provider 只比较 Swift 本地 `tab.fileURL`，当 core URI 已投影为新路径时，会跳过打开 tab 的未保存文本并读取 projected 文件磁盘内容。

实现上把 projected tab lookup helper 从 `Tabs.swift` 文件私有放宽到 `AttoEditorAreaViewController` 扩展可复用，并只迁移 WorkspaceEdit preview 的打开 tab 文本查找。该阶段不改变 WorkspaceEdit apply/transaction 语义、resource operation 执行、preview panel UI、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径，且打开 tab 有未保存文本时，`workspaceEditPreviewText(for: projectedURI)` 返回打开 tab 当前文本，而不是 projected 文件磁盘内容。本阶段仍不实现 project root ownership、pane layout tree、drag/drop split 或完整 WorkspaceEdit conflict UI。

## 阶段 233: WorkspaceEdit apply core URI projection 保留

2026-08-03 阶段 233 已让 `syncOpenTabsToCoreBeforeWorkspaceEditApply(...)` 在同步打开 tab 文本、dirty 状态和 active view 到 core transaction 前，保留 core tab snapshot 中已有的 `document_uri` 投影。此前该同步路径会无条件把 core `document_uri` 写回 Swift 本地 `tab.fileURL`，导致后续 WorkspaceEdit target URI 即使已由 core 投影为新路径，也可能被当作未打开文件处理。

实现新增一个很窄的同步 URL helper：core snapshot 已有有效 file URI 时用该 URI 设置 core tab title/document URI；缺失或不可解析时回退 Swift 本地 `tab.fileURL`。该阶段不改变 WorkspaceEdit transaction planner/apply/undo 语义、resource operation 执行、preview panel UI、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，WorkspaceEdit changes 指向新 URI 会命中打开 tab 并更新 in-memory editor text，而不是修改 projected 文件磁盘内容。本阶段仍不实现 project root ownership、pane layout tree、drag/drop split、多级/global transaction-wide undo 或更深层 conflict UI。

## 阶段 234: Document Symbols core URI projection 起点

2026-08-03 阶段 234 已让 Document Symbols result handling 在构造 symbol target URI 时使用 core tab snapshot 的 `document_uri` 投影，并让 Workspace Outline 的 document key/upsert file URL 同步使用同一 projected URL。此前 Document Symbols 和 Workspace Outline 仍从 Swift 本地 `tab.fileURL` 派生 URI，导致 core URI 已投影后，symbols target 和 outline document key 仍指向旧路径。

实现上只在 document-symbol result/JSON 两条处理路径中计算一次 projected document URI，并把 `updateWorkspaceOutline(...)` 的 file URL 来源改为 `projectedFileURL(for:)`。该阶段不改变 LSP request/poll lifecycle、workspace symbol parsing、symbol panel UI、core document-symbol ABI、workspace outline store schema 或真实 `tab.fileURL` 同步策略。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，Document Symbols result snapshot 的 symbol target URI 与 Workspace Outline snapshot 的 document URI / symbol target URI 都使用 core-projected 路径。本阶段仍不实现 project root ownership、pane layout tree、drag/drop split 或完整 project/LSP lifecycle 迁移。

## 阶段 235: Resolved inlay hint edit core URI projection 起点

2026-08-03 阶段 235 已让 resolved inlay hint 携带的 `textEdits` 在包装成 WorkspaceEdit 并应用时使用 core tab snapshot 的 `document_uri` 投影。此前 `consumeResolvedInlayHint(...)` 直接用 Swift 本地 `tab.fileURL.absoluteString` 生成 WorkspaceEdit 和 apply context，core URI 已投影后可能把 edit 应用到旧路径语义。

实现上只在 `consumeResolvedInlayHint(...)` 中计算一次 projected document URI，并同时用于 `AttoLspInlayHintResolver.workspaceEditJSON(...)` 与 `applyWorkspaceEditJSONToActiveTab(...)` 的 context。该阶段不改变 inlay hint request/resolve lifecycle、command payload 执行、tooltip/preview UI、WorkspaceEdit transaction 语义、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，resolved inlay hint text edit 会命中打开 tab 的 in-memory editor text，而不是修改 projected 文件磁盘内容。本阶段仍不实现 project root ownership、pane layout tree、drag/drop split 或完整 project/LSP lifecycle 迁移。

## 阶段 236: Rename WorkspaceEdit context core URI projection 起点

2026-08-03 阶段 236 已让 `RenameRequestContext.documentURI` 在实际 rename 请求和测试 hook 中使用 core tab snapshot 的 `document_uri` 投影。此前该 context 仍来自 Swift 本地 `tab.fileURL.absoluteString`，core URI 已投影后，rename result 的 WorkspaceEdit context 仍可能携带旧路径语义。

实现上只迁移 rename request/result context 的 document URI 来源，不改变 prepareRename/rename request lifecycle、polling、rename dialog、WorkspaceEdit transaction/apply/undo 语义、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为旧路径、core `document_uri` 已改为新路径时，rename result WorkspaceEdit 指向 projected URI 会命中打开 tab 的 in-memory editor text，而不是修改 projected 文件磁盘内容。本阶段仍不实现 project root ownership、pane layout tree、drag/drop split、完整 project/LSP lifecycle 迁移、更深层 conflict 检测/展示或多级/global transaction-wide undo 语义。

## 阶段 237: Command/keymap context core URI projection 起点

2026-08-03 阶段 237 已让 AttoEditor 的 keymap dynamic context 和 `toggle_comment` 语言配置使用 core tab snapshot 的 `document_uri` 投影。此前 `keymapContextForActiveState()` 的 `syntax` / `selector` / `file_name` / `file_extension` 和 `toggleLineCommentInActiveTab()` 的 comment config 仍从 Swift 本地 `tab.fileURL` 派生，core URI 已投影后，用户 keymap context 和注释语言判断仍可能落在旧路径语义。

实现上只迁移 command/keymap 文档身份派生字段和 `toggle_comment` comment config 的 file URL 来源，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变 keymap resolver/context operator 语义、菜单/command registry、真实保存路径、syntax detection、open-file language configuration、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `.txt`、core `document_uri` 已投影为 `.py` 时，keymap context 的 file name、extension、syntax 和 selector 都跟随 projected URI，且 toggle comment 使用 Python `#` line comment config。本阶段仍不实现完整 Sublime keymap 语义矩阵、插件/宏运行时、project root ownership、pane layout tree 或完整 project/LSP lifecycle 迁移。

## 阶段 238: Active Problems core URI projection 起点

2026-08-03 阶段 238 已让 AttoEditor 的 active Problems/diagnostics snapshot、diagnostics lifecycle scope/title 和 active diagnostic display title 使用 core tab snapshot 的 `document_uri` 投影。此前 `unifiedDiagnosticsSnapshot(...)` 用 Swift 本地 `tab.fileURL` 过滤 workspace diagnostics/markers，`recordActiveDiagnosticsLifecycle(...)` 和 active diagnostic title 也从本地文件名派生，core URI 已投影后，当前文件 Problems panel 可能漏掉 URI 指向 projected 文档的 workspace diagnostics，并把 lifecycle scope 记录到旧路径。

实现上只迁移 active diagnostics/Problems 中的 tab URL 输入、lifecycle scope/title 和 active diagnostic display title 文件名，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变 workspace diagnostics store schema、diagnostic parsing、marker projection math、Problems panel UI、navigation behavior、真实保存路径、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `diagnostics-local.swift`、core `document_uri` 已投影为 `diagnostics-projected.swift` 时，active diagnostics lifecycle scope/title 使用 projected URL，active Problems snapshot 同时包含 active diagnostic 和 projected URI 的 workspace diagnostic，marker projections 保持正确，Problems panel 也显示这两个问题。本阶段仍不实现完整 project/LSP lifecycle 迁移、更深层 diagnostics stale/refresh 策略、pane layout tree、drag/drop split 或全局 transaction undo 语义。

## 阶段 239: Code Lens title core URI projection 起点

2026-08-03 阶段 239 已让 AttoEditor Code Lens actions quick panel/current-line action title 使用 core tab snapshot 的 `document_uri` 投影。此前 `displayTitle(for:in:)` 从 Swift 本地 `tab.fileURL.lastPathComponent` 派生 file name，core URI 已投影后，Code Lens action title 仍显示旧路径文件名。

实现上只迁移 Code Lens action display title 中的 file name/line/column location 来源，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变 code lens request/refresh/resolve lifecycle、decorations snapshot、command execution、inline click behavior、quick panel filtering、真实保存路径、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `lens-local.swift`、core `document_uri` 已投影为 `lens-projected.swift` 时，current-line Code Lens quick panel 的唯一 action title 显示 `lens-projected.swift:2:1`，且不包含旧本地文件名。本阶段仍不实现更完整 code lens lifecycle/persistent panel、project-level Code Lens 聚合、pane layout tree 或完整 project/LSP lifecycle 迁移。

## 阶段 240: Window title core URI projection 起点

2026-08-03 阶段 240 已让 AttoEditor window title 的 active document display name 使用 core tab snapshot 的 `document_uri` 投影。此前 `updateWindowTitle()` 从 Swift 本地 `tab.fileURL.lastPathComponent` 派生标题文件名，core URI 已投影后，窗口标题仍可能显示旧路径文件名。

实现上只迁移 `updateWindowTitle()` 中的文件名展示来源，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变 dirty marker 判断、真实保存路径、tab bar/opened-files title、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `title-local.txt`、core `document_uri` 已投影为 `title-projected.txt` 时，window title 显示 `AttoEditor — title-projected.txt`。本阶段仍不实现完整 project/session/root 归属、pane layout tree、drag/drop split 或全量 AppKit chrome projection 清理。

## 阶段 241: Status bar metadata core URI projection 起点

2026-08-03 阶段 241 已让 AttoEditor status bar 的 file size 和 Rust/LSP relevance 判断使用 core tab snapshot 的 `document_uri` 投影。此前 `updateStatusBar()` 从 Swift 本地 `tab.fileURL` 读取文件大小，并用本地扩展名判断是否应该为 Rust 文件显示 LSP 状态；core URI 已投影后，状态栏 metadata 仍可能展示旧路径文件大小，或因为旧扩展名不是 `.rs` 而隐藏 LSP 状态。

实现上只迁移 `updateStatusBar()` 中 file-size lookup 与 “Rust file should show LSP status” 的文档 URL 来源，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变 active derived-state/diagnostics 统计、LSP status snapshot/formatting、语言选择、真实保存路径、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `status-local.txt`、core `document_uri` 已投影为 `status-projected.rs` 时，status bar file-size label 使用 projected 文件大小，并且 Rust/LSP relevance 判断会显示 LSP label。本阶段仍不实现完整 project/LSP lifecycle 迁移、全量 AppKit chrome projection 清理、pane layout tree 或拖拽 tab 到 split。

## 阶段 242: Language configuration core URI projection 起点

2026-08-03 阶段 242 已让 AttoEditor indentation/comment language configuration application 使用 core tab snapshot 的 `document_uri` 投影。此前 `applyLanguageConfiguration(for:)`、split pane creation 和 WorkspaceEdit/resource-operation 后 pane refresh 仍从 Swift 本地 `tab.fileURL` 推断语言；core URI 已投影后，缩进触发、缩进宽度和 comment config application 仍可能沿用旧扩展名语义。

实现上只迁移 language configuration file URL 来源，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变 syntax engine selection、用户显式 language override、真实保存路径、WorkspaceEdit apply/resource-operation 语义、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `indent-local.txt`、core `document_uri` 已投影为 `indent-projected.js` 时，重新应用 language configuration 后自动换行缩进使用 JavaScript 的 2 空格配置。本阶段仍不实现完整 project/LSP lifecycle 迁移、pane layout tree/session schema migration、拖拽 tab 到 split 或所有 editor chrome refresh 路径清理。

## 阶段 243: Core tab title sync core URI projection 起点

2026-08-03 阶段 243 已让 AttoEditor core tab title sync 使用 core tab snapshot 的 `document_uri` 投影。此前 `updateCoreTabTitle(_:)` 从 Swift 本地 `tab.fileURL.lastPathComponent` 派生 core tab display title；core URI 已投影后，后续保存或 resource-operation refresh 可能把 core title 覆盖回旧路径文件名。

实现上只迁移 `updateCoreTabTitle(_:)` 中 display title 的文件名来源，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变真实保存路径、`updateCoreTabDocumentURI(_:)` 的真实 URI 同步、tab bar/opened-files projection、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `title-local-tab.txt`、core `document_uri` 已投影为 `title-projected-tab.txt` 时，调用 `updateCoreTabTitle(_:)` 后 core snapshot tab title 保持 projected 文件名。本阶段仍不实现完整 project/session/root 归属、pane layout tree/session schema migration 或拖拽 tab 到 split。

## 阶段 244: Close callback core URI projection 起点

2026-08-03 阶段 244 已让 AttoEditor close-tab notification/callback URL 使用 core tab snapshot 的 `document_uri` 投影。此前 `closeTab(id:)` 在移除 AppKit tab 后传给 `onDidCloseFile` 的 URL 仍来自 Swift 本地 `tab.fileURL`；core URI 已投影后，opened-files/sidebar 或上层 lifecycle consumer 可能收到旧路径关闭事件。

实现上只迁移 `closeTab(id:)` 中传给 `onDidCloseFile` 的 URL 来源，统一复用 `projectedFileURL(for:)` 的 core snapshot 优先、Swift 本地 fallback 策略。该阶段不改变 dirty close confirmation、真实保存路径、core close command、tab removal、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `close-local.txt`、core `document_uri` 已投影为 `close-projected.txt` 时，关闭 clean tab 后 `onDidCloseFile` 收到 projected URL。本阶段仍不实现完整 project/session/root 归属、pane layout tree/session schema migration、拖拽 tab 到 split 或全量 sidebar lifecycle 迁移。

## 阶段 245: WorkspaceEdit removed-tab callback core URI projection 起点

2026-08-03 阶段 245 已让 WorkspaceEdit core transaction / undo 导致的 removed-tab close callback URL 使用 apply/undo 前 core tab snapshot 的 `document_uri` 投影。此前 `syncAppTabsFromCoreWorkspaceEditTransaction(...)` 在 core transaction 已经移除 tab 后只能从 Swift 本地 `tab.fileURL` 生成 `onDidCloseFile` URL；core URI 已投影后，WorkspaceEdit delete / close 类 resource operation 可能给 opened-files/sidebar lifecycle consumer 发送旧路径关闭事件。

实现上在 core WorkspaceEdit apply/undo 前缓存 tab id 到 projected URL，并将其用于 removed tabs 的 `onDidCloseFile` URL。该阶段不改变 WorkspaceEdit transaction planner/apply/undo、resource operation 文件系统副作用、dirty close confirmation、真实保存路径、session schema、真实 `tab.fileURL` 同步策略或 Rust/FFI ABI。

测试覆盖 Swift 本地 `tab.fileURL` 仍为 `delete-local-open.txt`、core `document_uri` 已投影为 `delete-projected-open.txt` 时，WorkspaceEdit core transaction 删除 projected URI 会移除打开 tab，`onDidCloseFile` 收到 projected URL，且只删除 projected 文件。本阶段仍不实现完整 project/session/root 归属、pane layout tree/session schema migration、拖拽 tab 到 split 或更深层 WorkspaceEdit conflict UI。

## 阶段 246: session pane layout descriptor 起点

2026-08-03 阶段 246 已为 AttoEditor session tab snapshot 增加可选 `paneLayout` descriptor。此前 session 只保存 `paneCount` 和 `activePaneIndex` 两个 Swift-only 扁平字段，只能表达当前过渡实现中的线性 split pane 数量，不能作为后续 pane layout tree / core view projection 的结构化承载点。

实现上新增 Swift `AttoPaneLayoutSnapshot`，当前写出 horizontal split + leaf children 的最小布局树；`makeSessionSnapshot()` 在 core projection 可用时用 core tab snapshot 的 `view_count` / `active_view_index` 生成 `paneLayout`，本地 fallback 则用 Swift pane 数组生成同形结构。`restoreSession(...)` 优先消费 `paneLayout` 的 flattened pane count 和 active pane index，旧 `paneCount` / `activePaneIndex` 保留为兼容 fallback。

本阶段不改变真实 AppKit pane UI 结构、不新增 Rust/FFI ABI、不声明完整 split tree 已完成，也不改变 session 文件路径、workspace/project ownership 或 `MultiDocumentEditorUi` view model。后续仍需让 core workspace 表达 pane layout tree、保存 splitter orientation/比例、支持拖拽 tab 到 split，并完成旧 session 文件的显式 schema migration 策略。

## 阶段 247: LSP workspaceFolders root 投影起点

2026-08-03 阶段 247 已让 `EditorUi::lsp_enable_stdio(...)` 从传入的 root URI 派生 LSP `WorkspaceFolder`，并同时写入 initialize params 的 `workspaceFolders` 与 `LspClient` 用来响应 server `workspace/workspaceFolders` 请求的 root 列表。此前 UI 层只把 root 写入 `rootUri`，但 `workspace_folders` 一直为空；会导致依赖 `workspace/workspaceFolders` 的 LSP server 看不到当前 workspace root。

实现上新增 `default_workspace_folders(root_uri)`，单 root 情况下生成 `{ "uri": root_uri, "name": last_path_segment }`；空 root URI 保持空数组。测试通过 fake LSP server 捕获 initialize request，并主动发起 `workspace/workspaceFolders` server request，断言 initialize params 和 client response 都包含同一个 root。

本阶段不改变 Swift `EditorUI.lspEnable(...)` API、不新增多 root ABI、不改变共享 LSP session key、不实现 `workspace/didChangeWorkspaceFolders`、project open/close lifecycle、server restart 策略或 App 层 project selector。后续仍需把 `MultiDocumentEditorUi` / project roots 与 LSP session lifecycle 完整绑定，并补动态 workspace folder 变更事件。

## 阶段 248: LSP workspaceFolders didChange 手动链路

2026-08-03 阶段 248 已把 headless `LspSession::did_change_workspace_folders(...)` 链接到 Rust UI、C ABI 和 Swift typed wrapper。此前 headless 层虽然能发送 `workspace/didChangeWorkspaceFolders`，但 Swift/UI binding 不能调用；同时通知发出后，`LspClient` 内部用于响应 server `workspace/workspaceFolders` 的列表不会更新，server 后续查询仍可能看到旧 workspace root。

实现上 `LspClient` 新增 workspace folder change apply 逻辑，按 URI 移除 removed folders 并替换/追加 added folders；`LspSession::did_change_workspace_folders(...)` 在成功发送通知后更新该列表。Rust UI 新增 `lsp_did_change_workspace_folders_json(...)`，C ABI 新增 `editor_core_ui_ffi_editor_ui_lsp_did_change_workspace_folders_json(...)`，Swift 新增 `EcuLspWorkspaceFolder` 和 `EditorUI.lspDidChangeWorkspaceFolders(added:removed:)`。

测试覆盖 fake LSP server 在 didChange 后再请求 `workspace/workspaceFolders` 时收到更新后的 root 列表；FFI/Swift wrapper 覆盖 LSP 未启用时的统一错误路径。本阶段仍不实现自动 project/root diff、server restart 策略、`MultiDocumentEditorUi` roots 到 active LSP session 的批量传播，或 AttoEditor project-open / project-close lifecycle 的产品级接线。

## 阶段 249: core workspace roots diff 驱动 active LSP didChange

2026-08-03 阶段 249 已把 `MultiDocumentEditorUi` 的 workspace roots 更新扩展为可返回 LSP `WorkspaceFolder` diff。新增 `set_workspace_roots_with_change(...)` 保持原有去重/跳过空 root 行为，同时按旧 root 顺序生成 removed folders、按新 root 顺序生成 added folders；folder name 由 root URI 最后一段派生，形状与 LSP `WorkspaceFolder` 一致。

C ABI 新增 `editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_json(...)`，Swift `MultiDocumentEditorUI` 新增 `EcuWorkspaceRootsChange` 和 `setWorkspaceRootsReturningChange(_:)` typed wrapper；既有 `setWorkspaceRoots(_:)` 兼容保留。AttoEditor 的 `syncCoreWorkspaceRoots()` 现在优先消费 core 返回的 diff，并在 active editor 的 LSP session 已启用时调用 `EditorUI.lspDidChangeWorkspaceFolders(added:removed:)`。

测试覆盖 Rust core root diff、C ABI JSON shape、Swift wrapper decode、AttoEditor root snapshot 兼容，以及一个假 LSP server 端到端用例：active editor 启用 LSP 后切换 workspace root，会捕获到 `workspace/didChangeWorkspaceFolders`，并同时包含 added root 和 removed root。本阶段仍不实现多 root project selector、project open/close 批量 LSP session 管理、server restart 策略或 shared LSP session root-set ownership。

## 阶段 250: workspace root change 广播到 open-tab LSP sessions

2026-08-03 阶段 250 已把 AttoEditor workspace root 变化的 LSP didChange 接线从 active tab 单点扩展为 open-tab fan-out。`syncCoreWorkspaceRoots()` 仍然只消费 `MultiDocumentEditorUi` 返回的 core-owned root diff；当 diff 非空时，会遍历当前 `tabs`，对每个 LSP 已启用的 tab 调用 `EditorUI.lspDidChangeWorkspaceFolders(added:removed:)`。

fan-out 的粒度是 tab，不是 pane。split panes 共享同一 tab 的 core document/view family，因此不会因为同一 tab 有多个 pane 而重复发送 workspace folder didChange。通知失败仍按 tab 做 best-effort 记录，不阻塞其他 tab。

测试把 AppKit 层假 LSP server 端到端用例扩展为两个已打开 tab：两个 tab 分别启用独立 fake LSP server，切换 workspace root 后两个 server 都能捕获到 `workspace/didChangeWorkspaceFolders`，并同时包含 added root 与 removed root。本阶段仍不实现 server restart、shared LSP session root-set ownership、多 root project selector，或 project open/close 时的批量 LSP 启停策略。

## 阶段 255: LSP status workspace root/capabilities 可观测性

2026-08-03 阶段 255 已把 LSP client 当前持有的 `workspace_folders` 纳入 `LspSessionStatus` 和 `EditorUi.lsp_status_json()`。此前 Swift/App 侧虽然能发送 `workspace/didChangeWorkspaceFolders`，但 `lspStatusSnapshot()` 只能看到 server/state/capabilities，无法从同一条 typed status 通道确认当前 LSP session 认定的 workspace root。

Swift `EcuLspStatusSnapshot` 新增 `workspaceFolders` typed 字段，并对缺失旧 JSON 保持空数组兼容。AttoEditor status bar formatter 现在会把第一个 workspace folder 显示为 `@ root`，多 root 用 `+N` 表示，同时对已知 capabilities 给出紧凑摘要；状态栏 label 会中间截断并把完整状态放入 tooltip，避免长 root/capability 文本破坏布局。

本阶段不新增 C ABI 函数，不改变 LSP enable / didChange workspace folders 控制面，不实现 project open/close 批量 LSP session 管理、server restart、shared-session root-set ownership 或完整状态订阅模型。它只把已经由 Rust LSP client 持有的 workspace folder set 通过现有 status 通道投影到 Swift/App 主路径。

## 阶段 256: LSP status state event 起点

2026-08-03 阶段 256 已把 LSP status 纳入统一 `EditorUiStateEvent` 起点：Rust `EditorUiStateEvent` 新增 `lsp_status` payload，事件 `kind` 为 `lsp_status_changed`，`family` 为 `lsp`。payload 复用阶段 255 的 status snapshot shape，因此包含 availability/state/detail/server/workspace_folders/capabilities 等字段。

当前触发点覆盖 LSP enable 成功/失败、disable、`workspace/didChangeWorkspaceFolders` 成功后、以及 `poll_lsp_best_effort` 中可从 `EditorUi.view_id` 归属的 session/poll/auxiliary failure。Swift `EcuEditorUIStateEvent` 新增 `lspStatus: EcuLspStatusSnapshot?`，`EcuEditorUIStateEventKind` / `EcuLspEventFamily` 新增 typed case，让 App 后续可以从统一 state event stream 订阅 LSP status，而不是只轮询 `lspStatusSnapshot()`。

本阶段仍不是完整状态订阅模型：尚未覆盖所有低层 `lsp_fail(...)` call site、server progress/activity 变化去重、server process exit health event、project-level 多 tab 聚合消费或 UI panel 自动刷新策略。它的边界是建立统一 state event 中的 typed LSP status payload 和首批生命周期/失败触发点；阶段 258 已继续扩大低层 failure 覆盖。

## 阶段 257: AttoEditor status bar 消费 LSP status event

2026-08-03 阶段 257 已让 AttoEditor 的 active state/event drain 消费阶段 256 的 `lsp_status_changed` payload。`AttoDerivedStateStore` 现在会缓存 active editor 最近一次 `EcuLspStatusSnapshot`，`updateStatusBar()` 优先用这份 event-derived status 渲染 LSP server 状态、workspace root 与 compact capabilities；只有没有事件 payload 时才回退到 `EditorUI.lspStatusSnapshot()`。

本阶段不新增 App 自有 LSP ownership，也不改变 LSP enable/disable、workspace folder didChange 或 shared session 策略。Swift 缓存只用于 active UI 投影，真实 status 仍来自 Rust `EditorUiStateEvent` / `EcuLspStatusSnapshot`。测试覆盖 fake LSP server 启用后，状态栏刷新会消费 `.lspStatusChanged`，缓存 typed workspace root，并在 LSP status label 中显示 `Ready` 和当前 root。

本阶段仍不实现 project-level 多 tab status 面板、server progress/activity 去重、server process health monitor、完整 failure event coverage 或 project open/close 批量 LSP session 管理。

## 阶段 258: LSP sync failure status event 覆盖

2026-08-03 阶段 258 已继续扩大 `lsp_status_changed` 的 failure 触发面。`EditorUiDoc` 新增 doc-lock 内可用的 failure + status event helper，低层 didChange sync、refresh processing、on-type formatting request/response/apply、slot result apply 和 derived-state apply 的失败路径现在会在保留原有 failed `lsp_status_json()` 行为的同时写入统一 state event stream。

本阶段不新增 C ABI、Swift wrapper 字段或 App 自有状态；Swift/App 继续通过已有 `state_events_json` / `EcuEditorUIStateEvent.lspStatus` 消费。测试覆盖 didChange sync failure 和 on-type formatting response error 都能产生 `lsp_status_changed` payload，并复验 polling failure、workspace folder status 和 request/result state event 语义。

本阶段仍不实现 server progress/activity 去重、server process health monitor、project-level 多 tab status 聚合面板、project open/close 批量 LSP session 管理或 shared-session root-set 完整 ownership 策略。

## 阶段 259: Project-level LSP status event 消费起点

2026-08-03 阶段 259 已让 AttoEditor 的 project LSP lifecycle drain 同时消费 core-owned `MultiDocumentEditorUI.stateEvents(...)`。当聚合事件为 `lsp_status_changed` 且 typed `EcuLspStatusSnapshot` 处于 failed 状态时，App 会把它以 `.status` 来源写入 `AttoProjectLspPanelErrorEventStore`，保留 tab id、view index、view id、source sequence 和 formatter 生成的用户可读错误消息。

本阶段复用已有 MultiDocument state event ABI 和 Swift typed decode，不新增 Rust/C ABI；`EcuMultiDocumentStateEvent` 的 nested `stateEvent.lspStatus` decode 已补测试。当前 `.status` 来源只进入 project LSP event store，供后续项目级 status panel / feedback UI 按 cursor 消费，不会误改 Locations/Symbols panel 的 result state。

本阶段仍不实现完整 project-level status panel UI、server progress/activity 去重、server process health monitor、project open/close 批量 LSP session 管理、server restart 或 shared-session root-set 完整 ownership 策略。

## 阶段 260: Project-level LSP status events 面板入口

2026-08-03 阶段 260 已把阶段 259 的 project LSP event store 暴露为用户可打开的轻量面板。AttoEditor 新增 `lsp.show_project_lsp_status` 命令、Go 菜单项和 `AttoEditor.LSP.ProjectStatusEvents` command-palette panel；打开时会先 drain core request/result/state events，然后展示 request、result 和 status 来源的 project LSP 错误事件。

本阶段的面板是可过滤的事件列表，保留 source sequence、tab/view scope 和用户可读错误消息，适合阶段 6 后续继续扩展为 dashboard 级 server health/status UI。测试覆盖命令注册、菜单接入、空事件时不展示、记录 failure 后可打开面板并显示 status event。

本阶段仍不实现 server progress/activity 去重、server process health monitor、server restart、project open/close 批量 LSP session 管理或完整 dashboard 级 project status panel。

## 阶段 261: LSP progress/activity status event 覆盖

2026-08-03 阶段 261 已把 LSP `$/progress` 导出的当前 activity/state 变化纳入统一 `lsp_status_changed` state event stream。`EditorUiDoc` 现在记录最近一次 LSP status event signature；显式 enable/disable/failure/status 事件会更新该 signature，`poll_processing()` 在处理 LSP server message 后会读取新的 `lsp_status_json()` shape，并且只在 status JSON 发生变化时记录新的 `lsp_status_changed`。

这让 Swift/App 可以沿用阶段 256-260 已建立的 state event stream、typed `EcuLspStatusSnapshot` decode 和 project-level drain 路径看到 server 当前 activity，例如 `$/progress` begin 触发的 `Indexing` state、message 和 percentage。测试覆盖 server progress begin 之后只产生一个 activity status event，后续无变化的 poll 不会重复发同一 status。

本阶段不新增 Rust/C ABI 或 Swift wrapper 字段，也不改变 project status events 面板行为；它只补齐当前 activity/status 的订阅事件。仍未实现 server process health monitor、server restart、project open/close 批量 LSP session 管理、更完整的 progress/activity 历史与聚合模型，或 dashboard 级 project status panel。

## 阶段 262: LSP process health status event 覆盖

2026-08-03 阶段 262 已把 LSP 子进程健康状态纳入既有 status snapshot 和 state event stream。`LspClient` 新增非阻塞 exit-status probe，`LspSessionStatus` 新增 `process` snapshot，包含 pid、`running` / `exited`、exit code 和 Unix signal；`EditorUi.lsp_status_json()` 会输出同名 `process` 字段。

当 status probe 发现 LSP 子进程已退出时，UI status 会把 `availability` / `state` 映射为 `failed`，`detail` 包含退出码或 signal，并通过阶段 261 已建立的 status signature 去重逻辑发出一次 `lsp_status_changed`。Swift `EcuLspStatusSnapshot` 新增 typed `process: EcuLspProcessStatus?`，project-level nested state event decode 也能读取同一字段。

本阶段不新增 C ABI 函数，不改变 `state_events_json` 结构，只扩展既有 `lsp_status` payload 的兼容字段。它不实现 server restart、自动 session teardown/recovery、project open/close 批量 LSP session 管理、stderr capture、完整 process history 或 dashboard 级健康视图。

## 阶段 263: Active-tab LSP server restart 起点

2026-08-03 阶段 263 已为 AttoEditor 补齐 active tab 的手动 LSP server restart 入口。打开文档时，Swift/App 会把通过 `AttoLspRegistry` 或 Rust 文件环境变量兼容路径推导出的 LSP launch config 保存在 tab 的 UI 投影缓存里；`lsp.restart_server` 命令和 Go 菜单项会复用这份配置，对当前 active tab 执行既有 `lspDisable()` / `lspEnable(...)` 链路，并重新应用语言配置、processing poll 和 status bar 更新。

本阶段不新增 Rust/C ABI，也不改变 `editor-core-ui` 的 LSP session ownership。它只把已有 Swift binding 能力产品化为 active-tab 手动操作；如果当前文档没有保存的 LSP server config，会走统一 `AttoLspResultFeedback` 的 unavailable 文案。测试覆盖命令注册、菜单接入、无配置反馈，以及 fake LSP server 被重启后同一文档重新发送 `textDocument/didOpen`。

本阶段仍不实现 project-level 批量 restart、shared-session root-set 完整 ownership 策略、自动 session recovery、stderr capture、server process history 或 dashboard 级 server health UI。

## 阶段 264: Project-level LSP server restart 起点

2026-08-03 阶段 264 已在阶段 263 的 active-tab restart 基础上新增 project-level 手动批量 restart 入口。AttoEditor 新增 `lsp.restart_project_servers` 命令和 Go 菜单项；执行时会优先读取 `MultiDocumentEditorUI` 的 core workspace tab snapshot 投影，按 core tab 顺序找到当前 AppKit tab，并对所有已保存 LSP launch config 的打开文档逐个执行既有 `lspDisable()` / `lspEnable(...)` restart 链路。

本阶段继续保持启动参数由 Swift/AppKit UI 投影缓存负责，实际 LSP session 操作仍走现有 Swift `EditorUI` binding；没有新增 Rust/C ABI，也没有把 project/server ownership 重新放回 Swift 自有 workspace model。无可重启配置时会走统一 unavailable 反馈；部分失败时会汇总失败文档并走统一 failed 反馈。测试覆盖无配置反馈、两个打开 tab 的 fake LSP server 批量重启，以及命令 palette / Go 菜单入口。

本阶段仍不实现 shared-session root-set 完整 ownership 策略、project open/close 自动批量启停、自动 session recovery、stderr capture、server process history 或 dashboard 级 server health UI。

## 阶段 265: Close-tab LSP session release 起点

2026-08-03 阶段 265 已补齐 close/project-close 停止侧的 App 起点。`closeTab(id:)` 现在会区分 owned LSP session 与非 owned document projection：如果被关闭 tab 自己拥有 LSP session，AttoEditor 不再先手动发送 `textDocument/didClose`，而是直接调用 `EditorUI.lspDisable()`，由 Rust `EditorUiDoc.lsp_reset()` 负责当前文档 didClose 与该 view 的 shared-session handle release；如果被关闭 tab 没有 own LSP session，则继续通知其它 open LSP sessions 关闭该 projected document。

这个调整避免了阶段 264 后 close-all 路径里 Swift didClose 与 Rust reset didClose 的重复发送，并让关闭所有 tab / window/project close 的停止侧至少能释放每个打开文档对应的 LSP handle。测试覆盖两个拥有 own LSP session 的 tab 执行 close-all 时，每个 fake server 只收到一次 `textDocument/didClose`，对应 `EditorUI.lspIsEnabled()` 变为 false，AppKit tabs 与 core workspace tabs 都清空。

本阶段仍不新增 Rust/C ABI，也不实现 graceful shutdown API；当前 Rust `lsp_disable()` 仍是 doc/session handle reset，最后一个 shared-session handle drop 后由 `LspClient` Drop 终止进程。剩余缺口仍包括 project open 自动批量 LSP 启动、shared-session root-set 完整 ownership 策略、stderr capture、server process history 和 dashboard 级 server health UI。

## 阶段 266: Shared LSP session graceful shutdown 起点

2026-08-03 阶段 266 已补齐 shared LSP session 停止侧的 Rust 起点。`SharedLspSession` 现在在最后一个强引用释放时取得内部 `LspSession` 并调用既有 `LspSession::exit()`，因此 responsive server 会先收到 `shutdown` request，在响应后收到 `exit` notification，再由底层 client 等待或回退到终止进程。

这个调整把阶段 265 的 close/project-close handle release 从“只释放 view handle，最后依赖 client drop 终止进程”推进到“最后一个 shared-session handle drop 也走 graceful exit”。回归测试新增 fake LSP server 捕获 stdin，验证 `EditorUi.lsp_disable()` 后最终能看到 `shutdown` 与 `exit`。同时，底层 `editor-core-lsp` 已有 `session_exit_accepts_responsive_shutdown` 测试覆盖 `LspSession::exit()` 对 responsive server 的标准行为。

本阶段仍不新增 Rust/C ABI 或 Swift wrapper API，也不改变 Swift `EditorUI.lspDisable()` 形状。剩余缺口包括 host-visible 显式 shutdown API、shared-session root-set 完整 ownership 策略、project open 自动批量 LSP 启动、stderr capture、server process history 和 dashboard 级 server health UI。

## 阶段 267: Host-visible LSP shutdown 控制面

2026-08-03 阶段 267 已把阶段 266 的 graceful shutdown 从 drop-time fallback 推进到 Swift 可主动调用的控制面。Rust `EditorUi` 新增 `lsp_shutdown() -> Result<bool, UiError>`；C ABI 新增 `editor_core_ui_ffi_editor_ui_lsp_shutdown(...)`，通过 `out_shutdown` 返回是否实际关闭了 live session；Swift `EditorUI` 新增 `lspShutdown() throws -> Bool` typed wrapper。

显式 shutdown 的语义是：对当前文档 best-effort 发送 `textDocument/didClose`，随后通过 shared session 的 `shutdown()` 调用既有 `LspSession::exit()`，让 responsive server 走 `shutdown` / `exit`，最后清理当前 view 的 LSP 状态并发出 status state event。disabled/no-op 场景返回 `false`，便于 host 区分“没有 active session”和“确实关闭了 session”。shared-session pool 也会跳过已经被 shutdown/take 的 dead handle，避免同 key 后续 enable 复用不可用 session。

本阶段仍不把 LSP ownership 迁回 Swift。它只暴露停止控制面，不新增 App command/menu，也不实现 shared-session root-set 完整 ownership、project open 自动批量 LSP 启动、stderr capture、server process history 或 dashboard 级 server health UI。

## 阶段 268: Shared LSP root alias ownership 起点

2026-08-03 阶段 268 已补齐 shared LSP session root-set ownership 的一个关键断点。此前 shared-session pool key 仍只包含启动时的 root URI：server 已经通过 `workspace/didChangeWorkspaceFolders` 接收 root B 后，pool 仍只登记 root A，后续用同 command/args + root B 打开的 tab 会启动第二个 server。

本阶段让 `SharedLspSession` 保存 `cmd` / `args` / root alias set，并在 `EditorUi.lsp_did_change_workspace_folders_json(...)` 成功后同步更新 shared-session pool：added root 会登记到同一 shared server，removed root 会移除指向该 shared server 的旧 key；如果同 root key 已有其它 alive session，则不会覆盖。回归测试覆盖 root A 启动、didChange 到 root B、随后 root B 文档启用 LSP 时复用同一 server，日志里只出现一次 `initialize`。

本阶段仍不改变 Swift/API 形状，也不把独立 project 的 session 合并策略产品化。剩余缺口包括 project open 自动批量 LSP session 启动、更完整的 shared-session root-set ownership 策略、stderr capture、server process history 和 dashboard 级 server health UI。

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

- definition/declaration/type definition/implementation/references 多结果已有统一 quick panel，展示 item model、稳定排序、最近结果 snapshot、reopen command、bounded in-memory history command 和基础持久在线 Locations/References panel；locations/references 的 current/history 已迁入通用 lifecycle store，已接入 App 层跨 family event stream，持久在线 panel 也已开始消费 lifecycle entry。仍缺项目级归属、跨 tab/project panel UI 和更完整刷新/过期策略。
- completion popup 主路径、commit-time completion resolve、rich documentation/detail preview、commitCharacters 提交行为、server triggerCharacters 自动触发、本地增量过滤、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations、App 层跨 family event stream 接入、Swift UIFFI completion result / resolve item typed payload wrapper、completion App 主路径 typed payload 消费，以及阶段 196-221 core WorkspaceEdit transaction 起点、root-gated 本地文件覆盖、App apply helper 主路径、基础 preview/confirmation、专用 diff preview panel 起点和未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点已完成；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
- signature help popup 主路径已有，并会按 server trigger/retrigger characters 自动弹出，active parameter 富格式高亮、typed result model 和手动请求空/错反馈已完成。
- rename 主路径已有 App 输入 UI、prepareRename range/placeholder 默认名、prepare/result typed payload wrapper、当前文档 WorkspaceEdit 应用、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations、App 层跨 family event stream 接入和阶段 196-221 core WorkspaceEdit transaction 起点/root-gated 本地文件覆盖/App apply helper 主路径/基础 preview confirmation/专用 diff preview panel 起点/未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义和 request lifecycle。
- rename WorkspaceEdit context 已在阶段 236 改为使用 core tab snapshot 的 `document_uri` 投影，避免 core URI 已投影时继续把 Swift 本地 `tab.fileURL` 当作 LSP document identity。
- code action 主路径已有 App quick panel、resolve、typed diagnostics context、result/resolve typed payload wrapper、App 主路径 typed payload 消费、kind/filter、当前文档 edit 应用、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations、command 执行、执行结果/错误 HUD、App 层跨 family event stream 接入和阶段 196-221 core WorkspaceEdit transaction 起点/root-gated 本地文件覆盖/App apply helper 主路径/基础 preview confirmation/专用 diff preview panel 起点/未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
- code lens refresh、code lens resolve、active code lens actions quick panel、当前行键盘定位命令、内联 Cmd-click hit-test、Rust/UI auxiliary 自动刷新消费、状态栏数量反馈和 workspace command execution 的 Swift UI/App 路径已有；仍缺通用 workspace command typed model。
- outline / document symbols 已有 quick panel 主路径，document/workspace symbols result typed payload wrapper 和 App 主路径消费已完成，document symbols 展示可消费 typed derived-state snapshot，基础错误/超时/空结果反馈、最近结果 snapshot、reopen command、bounded in-memory history command 和基础持久 Outline/Symbols panel 已补齐；document/workspace symbols 的 current/history 已迁入通用 lifecycle store，已接入 App 层跨 family event stream，持久在线 panel 也已开始消费 lifecycle entry；opened-document workspace outline store、`Workspace Outline` panel command、core-owned workspace outline snapshot ABI/Swift wrapper 与 App 消费起点、打开 tab 的 core document URI metadata 已补齐。仍缺跨 tab/project panel UI、project/session/root 归属下沉和更完整刷新/过期策略。
- workspace symbols 已有增量查询输入面板、quick panel 主路径、typed payload poll path、kind 分组/稳定排序、基础错误/超时/空结果反馈、最近结果 snapshot、reopen command、bounded in-memory history command 和基础持久结果 panel；symbol result current/history 已迁入通用 lifecycle store，并已接入 App 层跨 family event stream。仍缺覆盖所有 result family 的更深层 lifecycle/event model。
- on-type formatting 已有 explicit binding、换行触发和 server trigger characters 自动触发路径；显式 Swift binding 的 `EditorCoreLSPFormattingResult` typed outcome 已完成，自动 on-type 异步 response error 已进入 LSP status/detail，AttoEditor 会刷新 status 并对新的 failure detail 弹一次去重 HUD；Swift 已有 typed `lspStatusSnapshot()`、LSP request/result event stream 和 metadata typed accessor，AttoEditor 的 LSP status/capabilities 行为路径也已迁到 typed snapshot。后续仍缺状态变更订阅模型和更完整 request/result payload envelope。
- semantic tokens full/delta 自动刷新 lifecycle 已进入 core-owned request events；manual full/delta/range request/take ABI、Swift typed result envelope、delta baseline application 和 App typed apply baseline 已完成，仍缺统一状态订阅模型对语义高亮刷新/过期的更完整驱动。
- folding ranges binding 已覆盖 request/take/apply 到 fold UI state，AttoEditor 已有显式 refresh 命令、typed capability gate、菜单入口、错误/超时反馈、typed fold snapshot、status bar 折叠摘要、renderer 层 gutter fold marker 视觉回归 baseline，以及自动 refresh request lifecycle；仍缺更完整的 result lifecycle model。
- selection range raw request/take、Swift UIFFI typed result wrapper 和 App 主路径 typed payload 消费已完成；App 层 `lsp.selection_range` expand-selection 主路径、typed candidate model 和多光标 selection range 策略已完成，仍缺更完整 result lifecycle model。
- linked editing raw request/take、Swift UIFFI typed result wrapper 和 App 主路径 typed payload 消费已完成；App 层 `lsp.linked_editing` 主路径、typed parser、wordPattern/shared-text 校验、基于 multi-cursor selections 的基础同步编辑策略和轻量 session 生命周期/退出条件已完成；仍缺更完整 result lifecycle model。
- document diagnostic pull / workspace diagnostic raw request/take 已有；active-tab Problems quick panel、active-tab 持久 Problems panel 和 workspace Problems panel 已消费 unified diagnostics problem model，workspace diagnostics 也已有基础 quick panel、typed parser、core-backed workspace Problems store、`previousResultIds` 增量请求参数、core-backed marker snapshot、workspace/active marker unified model、统一状态栏摘要、lifecycle entry 起点、按 sequence 增量事件查询、基础 stale/refresh lifecycle metadata、App 层跨 family event stream 接入、core-owned workspace diagnostics event stream 起点、`EditorUi` core-owned result slot event stream 起点、MultiDocument/project 级 result event 聚合起点、`EditorUi` request lifecycle event stream 起点、MultiDocument/project 级 request event 聚合起点、显式 cancel/timeout lifecycle、on-type formatting request lifecycle、workspace Problems store 对 core-owned workspace diagnostics event cursor 的消费起点、marker projection 对同一 cursor 的缓存刷新，以及阶段 238 active Problems core document URI projection；仍缺 pull/publish 统一 feedback/metadata 消费和更完整 project-level panel lifecycle。
- document color / color presentation raw request/take、typed result wrapper 和 App 主路径 typed payload 消费已完成；App 层 `lsp.document_colors` 主路径、色块 quick panel、直接 color picker、color presentation apply、typed parser 和跨 family event stream 接入已完成；仍缺持久颜色面板、多文档/workspace 颜色聚合和更完整 result lifecycle model。
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

- Swift UI binding 已有 diagnostics、decorations、symbols、fold regions、style intervals 的基础 typed snapshot model，也已有 LSP request/result/workspace diagnostics event metadata typed accessor、completion result/resolve item typed payload wrapper、location family result typed payload wrapper、rename/WorkspaceEdit typed payload wrapper、code action result/resolve typed payload wrapper、document/workspace symbols result typed payload wrapper、document color/color presentation result typed payload wrapper、call/type hierarchy typed payload wrapper、document/workspace diagnostics pull typed payload wrapper、selection range result typed payload wrapper、linked editing typed payload wrapper、code lens result/resolve typed payload wrapper、folding ranges result typed payload wrapper 和 semantic tokens full/delta/range typed payload wrapper。
- App 层已有 active-tab derived-state store，status bar、Problems quick panel、active-tab 持久 Problems panel、core-backed workspace Problems store/panel、active-tab minimap diagnostic markers、active-tab gutter diagnostic icons、core-backed workspace diagnostic marker snapshot 到 open-tab markers 的投影、workspace/active marker unified model、workspace/active diagnostics 统一状态栏摘要、active-tab 与 workspace Problems list 统一模型消费、active Problems core document URI projection、diagnostics lifecycle entry 起点、diagnostics events-after 查询、diagnostics stale/refresh lifecycle metadata、跨 result family event stream 起点、core-owned workspace diagnostics event stream 起点、`EditorUi` core-owned result slot event stream 起点、MultiDocument/project 级 result event 聚合起点、`EditorUi` request lifecycle event stream 起点、MultiDocument/project 级 request event 聚合起点、显式 cancel/timeout lifecycle、on-type formatting request lifecycle、UI auxiliary derived-state request lifecycle、semantic/folding internal refresh request lifecycle、Swift 事件 metadata typed accessor、completion Swift UIFFI typed payload wrapper 与 App 主路径消费、location family typed payload wrapper 与 App 主路径消费、rename/WorkspaceEdit typed payload wrapper 与 App 主路径消费、code action typed payload wrapper 与 App 主路径消费、document/workspace symbols typed payload wrapper 与 App 主路径消费、document color/color presentation typed payload wrapper 与 App 主路径消费、call/type hierarchy typed payload wrapper 与 App 主路径消费、workspace diagnostics pull typed payload wrapper 与 App 主路径消费、selection range typed payload wrapper 与 App 主路径消费、linked editing typed payload wrapper 与 App 主路径消费、code lens typed payload wrapper 与 App 主路径消费、folding ranges typed payload wrapper 与 App 主路径消费、semantic tokens typed apply baseline、基础持久 Outline/Symbols panel 和测试断言可以消费 diagnostics/decorations/symbols/folds/styles 的 typed snapshots。
- App 层已有 request lifecycle/event stream 起点，diagnostics notification/pull refresh lifecycle 已补齐，Swift 侧可 typed 读取 family/slot/phase/status/operation/severity 等事件元数据；阶段 178 已提供单 `EditorUi` unified state event drain 起点，阶段 179 已提供 MultiDocument/project unified state event 聚合起点，阶段 180 已补文本变更与 dirty 状态事件，阶段 181 已补 selection/caret 状态事件，阶段 182 已补 viewport 状态事件，阶段 183 已补 layout 状态事件，阶段 184 已补 derived-state changed/stale 状态事件，阶段 185 已让 AttoEditor active status/diagnostic marker 主路径开始消费统一 state-event cursor，阶段 186 已让 workspace Problems store 开始消费 core-owned workspace diagnostics event cursor，阶段 187 已让 workspace marker projection 复用该 cursor 缓存刷新，阶段 188 已让 Locations/Symbols 持久在线 panel 消费 lifecycle entry，阶段 189 已把 panel lifecycle metadata 显示为稳定 UI 文本，阶段 190 已补 Locations/Symbols panel 的 Fresh/Stale/Error 状态模型与 active 文档编辑后的 stale 展示，阶段 191 已补 active App request feedback error 到 current panel entry 的接线。project-level result lifecycle/panel error 聚合起点、opened-document workspace outline store 起点和 core-owned workspace outline snapshot/API 起点已补齐；剩余更完整跨 tab/project panel UI 仍未完全统一。

这会影响 Sublime 复刻中的这些功能：

- active-tab 持久 Problems panel、core-backed workspace Problems store/panel、core-backed workspace marker snapshot、workspace/active marker unified model、统一状态栏摘要、active-tab/workspace Problems list 统一模型消费、diagnostics lifecycle entry 起点、diagnostics events-after 查询、diagnostics stale/refresh lifecycle metadata、App 层跨 family event stream 接入、core-owned workspace diagnostics event stream 起点、`EditorUi` core-owned result slot event stream 起点、MultiDocument/project 级 result event 聚合起点、`EditorUi` request lifecycle event stream 起点、MultiDocument/project 级 request event 聚合起点、显式 cancel/timeout lifecycle、on-type formatting request lifecycle、UI auxiliary derived-state request lifecycle、semantic/folding internal refresh request lifecycle、Swift event metadata typed accessor、pull diagnostics typed payload envelope、单 `EditorUi` unified state event drain 起点、MultiDocument/project unified state event 聚合起点、文本/dirty/selection/viewport/layout/derived-state changed/stale state event、workspace Problems store 对 core-owned workspace diagnostics event cursor 的消费起点、workspace marker projection 对同一 cursor 的缓存刷新、Locations/Symbols 持久在线 panel 对 lifecycle entry 的消费、panel lifecycle metadata 稳定 UI 文本、active 文档编辑后的 stale 状态展示、active App request feedback error 到 current panel entry 的接线，以及 opened-document workspace outline store / core-owned workspace outline snapshot 起点已补齐；仍缺更完整跨 tab/project panel UI。
- Outline / symbol list 基础持久 panel 已补齐，并已开始消费 result lifecycle entry、显示 lifecycle metadata、active 文档编辑后的 stale 状态，以及 active request feedback error 状态；opened-document workspace outline store、core-owned workspace outline snapshot 和 project-level error lifecycle 聚合起点已补齐，仍缺更完整跨 tab/project panel UI。
- Goto symbol。
- active-tab minimap diagnostic markers、gutter diagnostic icons、core-backed workspace diagnostics markers 到 open-tab markers 的投影、workspace/active marker unified model、基础 stale/refresh lifecycle metadata、diagnostics notification/pull request lifecycle、Swift diagnostics event/report/severity typed accessor、pull diagnostics typed payload envelope、`EditorUi` unified state events、MultiDocument/project unified state events 和文本/dirty/selection/viewport/layout/derived-state changed/stale state event 已补齐；active status/diagnostic marker 主路径已开始消费统一 state-event cursor，workspace Problems store 和 workspace marker projection 已开始消费 core-owned workspace diagnostics event cursor，Locations/Symbols 持久在线 panel 已开始消费 lifecycle entry、显示 lifecycle metadata，并能在 active 文档编辑后展示 stale 状态和 active request feedback error 状态；opened-document workspace outline store 与 core-owned workspace outline snapshot 起点已补齐，仍缺更完整跨 tab/project panel UI。
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

- command registry 已有基础命令启用/禁用状态、分组元数据、参数 schema、runtime feature requirement、宏录制策略和静态 editor-core JSON payload 元数据；主 command palette 已开始展示 source category，可按 title/group/id fuzzy 搜索，并已有可跨启动恢复的 bounded recent command ordering、最近参数 replay、基础通用参数 prompt，以及 last / named macro 录制、保存、回放和 `.sublime-macro` 兼容持久化起点；keymap 已有基础 context 条件过滤、快捷键冲突解析、`args` 执行路由、多键序列 dispatcher，以及阶段 237 补齐的 core-projected document URI context 起点。仍缺更完整的插件/宏运行时、命令上下文模型、Sublime overlay/panel 级参数 UI 和完整 Sublime keymap 语义矩阵。
- command palette、主菜单和 keymap 已覆盖一批 Sublime 基础编辑命令；LSP location、symbols quick panels、completion popup、signature help、rename 和 code action 主路径已接入，但更深层 LSP/项目级命令仍不完整。
- P0 菜单、command palette、keymap 和测试已开始统一使用 command id；基础参数化命令可通过 typed arguments 执行，但更深层的命令上下文、插件/宏回放策略和 keymap 冲突解析仍缺。
- 一些 core/LSP 命令仍没有 App 命令入口。
- 用户 keymap 文件已有基础 Sublime JSON、context 条件过滤和快捷键冲突解析，但还不是完整 Sublime keymap 兼容实现。
- 没有 Sublime 风格 settings scopes。
- 已有 last macro 录制/回放、命名 `.sublime-macro` 保存、按名回放、重命名、删除、批量删除、跨启动多级删除 undo、可浏览删除历史 palette、可视化删除历史管理面板、单条/批量/全部清理删除历史、基础导入/导出入口、原生文件选择流程和删除确认 UI，但还没有完整命名宏管理面板、完整可视化回收站、完整 Sublime `.sublime-macro` 扩展语义或 plugin/package command runtime。
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
- keymap 文件已有基础 JSON 解析、`context` 条件过滤、快捷键冲突解析、`args` 执行路由、基础多键序列 dispatcher、prefix 状态栏提示、prefix 超时和 Escape 取消；键名兼容已覆盖常见 modifier、arrow/function key、命名标点、字面 `+`、forward delete / insert / begin / clear / help，context operator 已覆盖 `equal` / `not_equal` / `regex_match` / `not_regex_match` / `regex_contains` / `not_regex_contains` 和 `match_all` 多值上下文语义。App key-down dispatcher 已能注入 active editor、selection、selector、syntax、file name/extension、dirty、tab/pane 等基础动态 context 并按当前 context 触发单键 binding/chord/args；selector、syntax、file name/extension 已在阶段 237 跟随 core document URI projection。仍缺更完整 Sublime 命令上下文模型和更完整跨平台键名兼容矩阵。
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
- LSP interactive request 已覆盖一批 raw JSON result API；LSP status/capabilities 已有 typed snapshot，`EditorUi` request lifecycle event stream 起点、Swift event metadata typed accessor、completion result/resolve item typed payload wrapper、location family result typed payload wrapper、rename/WorkspaceEdit typed payload wrapper、code action result/resolve typed payload wrapper、symbols/color/hierarchy/diagnostics/selection range/linked editing/code lens/folding ranges/semantic tokens typed payload wrapper 已补齐。
- 长任务、异步请求、取消、错误、诊断日志没有统一 Swift 事件流。
- 配置 DTO 已有 `AttoConfigurationSnapshot` / `AttoCapabilitySnapshot` 起点，覆盖当前有效 editor/rendering/language/workspace 偏好、UI FFI ABI/features、LSP capability 摘要和 platform/App capability；`AttoConfigurationSettings` 已提供 user/workspace/runtime partial overlay 合并和 settings JSON store 起点；AttoEditor App 创建窗口和偏好重应用路径已消费 user/workspace/runtime settings 的 resolved snapshot；损坏 settings 文件会备份为 `*.invalid` 后被忽略；legacy v0 settings 会备份并写回 current schema；Find bar 默认大小写、整词和 regex 搜索选项、Find in Files 默认 scope、workspace search include/exclude glob 已纳入配置并应用到 Swift UI；全局 Preferences UI 已覆盖默认 Find 选项、Find in Files 默认 scope 和 workspace search include/exclude glob。但 Sublime settings scope selector、workspace/project scoped settings 编辑 UI、runtime override UI/持久化、跨 schema 字段语义迁移、自定义 word boundary 规则等仍不完整。
- headless Swift FFI 已有 ABI version；阶段 69 已补齐 UI FFI 的 ABI version / feature flags C ABI 和 Swift `runtimeInfo()` typed facade，阶段 80 已新增 multi-document UI feature flag，阶段 81 已把该 feature 纳入 AttoEditor 启动期必需能力；阶段 70 已补 AttoEditor 启动期最低 ABI/必需 feature compatibility gate，阶段 105 已补基础逐命令可选 feature 降级；阶段 10 已为 UI FFI JSON command dispatcher 增加 `{ ok, value, error, version }` envelope API 和 Swift typed wrapper 起点。后续仍缺 headless/UI 全面一致的 JSON envelope 覆盖、更细粒度的逐面板降级策略和面向第三方 host 的 ABI capability negotiation。

建议演进方向：

- 继续使用 `editor_core_ui_ffi_editor_ui_execute_command_json(editor, command_json)` 作为 UI escape hatch。
- Swift `EditorUI.executeCommandJSON(_:)` 作为低频/迁移命令入口。
- 已有高频命令 typed convenience API；新增或低频命令按产品化需要继续补 typed API。
- FFI 返回统一 `{ ok, value, error, version }` 风格；UI command JSON 已有兼容 envelope 起点，后续继续扩到 headless/core 与其他 JSON 结果面。
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
- 已完成：AttoEditor 会按语言/扩展名向 toggle comment 传完整 line/block comment config；阶段 237 已让该语言/扩展名来源跟随 core document URI projection。
- 已完成：AttoEditor command registry 已接入基础 group/requiresEditor/isEnabled 元数据，菜单、palette 和 `executeCommand(id:)` 共用同一启用状态。
- 已完成：AttoEditor command registry 已接入基础参数 schema、宏录制策略、静态 editor-core JSON payload 元数据和 `executeCommand(id:arguments:)` typed arguments 路径；默认命令集已有重复 command id 检测测试。
- 已完成：AttoEditor command registry 已接入 runtime feature requirement，LSP/WorkspaceEdit 可选 feature 缺失时会按命令禁用相关菜单、palette 项和 `executeCommand` 路径，而基础编辑命令保持可用。
- 已完成：AttoEditor 已有 `AttoConfigurationSnapshot` / `AttoCapabilitySnapshot` typed DTO 起点，可审计当前有效偏好、UI FFI runtime ABI/features、LSP capability 摘要和 platform/App capability，并支持 Codable round trip 与 unknown future fields 兼容。
- 已完成：AttoEditor 已有 `AttoConfigurationSettings` partial settings overlay 和 store 起点，支持 user settings、workspace `.attoeditor/settings.json`、runtime overrides 的 typed 合并顺序和 JSON 保存/加载测试。
- 已完成：AttoEditor App 创建窗口和偏好重应用路径已按 workspace root 读取 user/workspace settings，并把 resolved `AttoConfigurationSnapshot` 应用到 theme、font、ligatures、wrap 和 auto-pairs。
- 已完成：AttoEditor App 配置解析路径已支持 process-local runtime settings override，并能把 runtime override 变更重应用到已打开 editor。
- 已完成：AttoEditor settings store 已有损坏 JSON/DTO 文件备份起点，会把无法 decode 的 settings 文件移动到 `*.invalid` 备份路径并继续使用下层配置。
- 已完成：AttoEditor settings store 已有 legacy v0 schema migration 起点，会把缺失 `schema_version` 的 settings 备份到 `*.v0.backup` 并写回 current schema JSON。
- 已完成：AttoEditor 主命令 palette 已开始展示 command registry 分组，并能按命令 title、group 和 command id 搜索；LSP/Project/Quick Open 等结果 palette 仍保持原有简洁标题。
- 已完成：AttoEditor 主命令 palette 已有 bounded in-memory recent command ordering，统一 command id 路径成功触发的命令会在下一次打开 palette 时排到前面。
- 已完成：AttoEditor 主命令 palette 的 recent command ordering 已通过 `AttoRecentCommandStore` 跨启动持久化，默认 App 启动可恢复最近命令顺序。
- 已完成：AttoEditor 主命令 palette 的 recent command record 已持久化最近一次 typed arguments，palette 触发最近参数化命令时可 replay 参数；菜单、keymap 和直接无参数 command 执行路径不复用历史参数。
- 已完成：AttoEditor 主命令 palette 已接入基础通用参数 prompt，按 command schema 渲染参数表单并预填最近参数；Quick Open/LSP result palette 默认保持无参数 prompt 行为。
- 已完成：AttoEditor 已有 in-memory last macro 录制/回放起点，`macro.toggle_recording` / `macro.replay_last` 接入 command palette、Tools 菜单和默认 keymap，并按 `macroPolicy` 过滤可录制命令。
- 已完成：AttoEditor last macro 会保存/加载 `.sublime-macro` 兼容文件，默认路径位于用户 Application Support 下的 `Macros/Last Macro.sublime-macro`，可跨 App delegate / App 启动恢复最近一次录制的 command sequence。
- 已完成：AttoEditor 已有命名 `.sublime-macro` 保存和按名称回放起点，`macro.save_named` / `macro.replay_named` 接入 command palette 与 Tools 菜单，按名回放 prompt choices 来自当前宏目录。
- 已完成：AttoEditor 已有命名 `.sublime-macro` 重命名和删除起点，`macro.rename_named` / `macro.delete_named` 接入 command palette 与 Tools 菜单，并按当前宏目录动态启用和提供 choices。
- 已完成：AttoEditor 已有命名 `.sublime-macro` 基础导入/导出入口，`macro.import_file` / `macro.export_named` 接入 command palette 与 Tools 菜单，导入会验证并重写为兼容 JSON，导出会写出目标 `.sublime-macro` 文件。
- 已完成：AttoEditor 命名 `.sublime-macro` 导入/导出的无参数命令和菜单路径已有原生文件选择流程，导入使用 open panel，导出使用 save panel；参数化路径仍可显式输入 path/name。
- 已完成：AttoEditor 命名 `.sublime-macro` 删除已有确认 UI，`macro.delete_named` 删除前会弹出 warning alert；测试路径可注入 provider 覆盖取消/确认。
- 已完成：AttoEditor 命名 `.sublime-macro` 已有批量删除起点，`macro.delete_named_batch` 可通过 JSON string array 参数一次删除多个命名宏，并复用删除确认 UI。
- 已完成：AttoEditor 命名 `.sublime-macro` 已有多级删除 undo 起点，`macro.undo_delete` 可按后进先出顺序恢复连续单宏或批量删除的 command sequence，恢复时不会覆盖之后新建的同名宏。
- 已完成：AttoEditor 命名 `.sublime-macro` 删除 undo 历史会持久化到宏目录隐藏 JSON 文件，跨 App delegate / App 重启仍可继续恢复，且不会污染命名宏列表。
- 已完成：AttoEditor 命名 `.sublime-macro` 删除历史已有可浏览 palette，`macro.show_delete_history` 可查看持久化删除记录并选择恢复非最近记录。
- 已完成：AttoEditor 命名 `.sublime-macro` 删除历史已有显式清空入口，`macro.clear_delete_history` 会在确认后清空内存 undo stack 和持久化隐藏 JSON。
- 已完成：AttoEditor 命名 `.sublime-macro` 删除历史已有单条移除入口，`macro.remove_delete_history_entry` 可按最近优先的 1-based index 丢弃指定 restore 记录并持久化。
- 已完成：AttoEditor 命名 `.sublime-macro` 删除历史已有批量移除入口，`macro.remove_delete_history_entries` 可按最近优先的 1-based JSON index 数组丢弃多条 restore 记录并持久化。
- 已完成：AttoEditor 命名 `.sublime-macro` 删除历史已有可视化管理面板，`macro.manage_delete_history` 可打开 AppKit 面板进行单选恢复、多选移除和清空历史，并与删除历史 palette 同步刷新或关闭。
- 已完成：AttoEditor keymap 已支持 arrow/navigation function-key token，move lines up/down 已有默认 arrow-key 绑定。
- 已完成：AttoEditor keymap 已支持基础 `context` 条件过滤和快捷键冲突解析，`resolvedKeymap(...)` 可暴露 conflicts 供测试和后续 UI/诊断使用。
- 已完成：AttoEditor keymap 已支持用户条目 `args` 解码，并能通过菜单/shortcut command 路径调用 `executeCommand(id:arguments:)` 执行参数化命令。
- 已完成：AttoEditor keymap 已支持基础多键序列解析和 App 层 dispatcher，多键序列命中后复用统一 command id 和 typed arguments 执行路径。
- 已完成：AttoEditor keymap chord prefix 已支持超时清理和 Escape 取消，避免未完成 chord 长期拦截后续按键。
- 已完成：AttoEditor keymap chord prefix 已有状态栏可见提示，并会在命中、失败、超时或 Escape 后恢复状态栏左侧原摘要。
- 已完成：AttoEditor keymap 已补一批 Sublime 风格键名 token、字面 `+` 和 regex contains/full-match context operator 语义。
- 已完成：AttoEditor keymap context resolver 已支持 `match_all` 多值上下文语义。
- 已完成：AttoEditor App key-down dispatcher 已按 active editor 状态动态注入 keymap context，并能用当前 context 触发单键 binding、chord 和 keymap args；阶段 237 已让文档身份相关 context 跟随 core document URI projection。
- 已完成：AttoEditor command palette 已用 `cursor.*` 覆盖 grapheme/word、visual row/page、visual line/document start/end 及对应 modify-selection 视觉移动命令矩阵。
- 已完成：AttoEditor 主菜单已有独立 Selection 菜单分组，常用 selection/multicursor 命令复用统一 command id。
- 已完成：Swift UI binding 已为 derived-state snapshots 提供基础 typed model。
- 已完成：AttoEditor 已有 active-tab derived-state store，status bar 可显示 Problems 数量，测试可直接断言 active derived-state snapshot。
- 已完成：AttoEditor 已有 Problems quick panel 和 active-tab 持久 Problems panel，消费 workspace/active diagnostics 统一模型并支持 active/workspace 跳转；阶段 238 已让 active Problems 的当前文档 URI 过滤、lifecycle scope/title 和 active diagnostic title 跟随 core document URI projection；阶段 239 已让 Code Lens action title 跟随 core document URI projection。
- 已完成：AttoEditor command palette 为一批 Sublime 基础编辑命令建立稳定 command id。
- 已完成：为高频命令补 typed Swift convenience API。
- 已完成：把 App command id 统一接入主菜单和初步用户可配置 keymap。
- 为这些命令补 AppKit 操作测试和结构化状态测试。

### P1：补 LSP 产品主路径

- completion commit-time resolve、rich documentation/detail preview、commitCharacters 提交行为、server triggerCharacters 自动触发、本地增量过滤、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations、App 层跨 family event stream 接入、Swift UIFFI completion result / resolve item typed payload wrapper、completion App 主路径 typed payload 消费和阶段 196-221 core WorkspaceEdit transaction 起点/root-gated 本地文件覆盖/App apply helper 主路径/基础 preview confirmation/专用 diff preview panel 起点/未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点已完成；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
- signature help server trigger/retrigger characters 自动触发、active parameter 富格式高亮、typed result model 和手动请求空/错反馈已完成。
- references/implementation/declaration/type definition 多结果 quick panel 已统一，展示 item model、稳定排序、最近结果 snapshot、reopen command、bounded in-memory history command、基础持久在线 Locations/References panel、typed lifecycle entry/envelope 元数据、location family typed payload wrapper/App 主路径消费和 App 层跨 family event stream 接入；持久在线 panel 已开始消费 lifecycle entry、显示 lifecycle metadata，并能在 active 文档编辑后展示 stale 状态和 active request feedback error 状态。仍缺项目级归属、跨 tab/project panel UI 和更完整刷新/过期策略。
- rename prepareRename range/placeholder、prepare/result typed payload wrapper、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations、App 层跨 family event stream 接入和阶段 196-221 core WorkspaceEdit transaction 起点/root-gated 本地文件覆盖/App apply helper 主路径/基础 preview confirmation/专用 diff preview panel 起点/未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点已产品化；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义和 request lifecycle。
- code action typed diagnostics context、result/resolve typed payload wrapper、App 主路径 typed payload 消费、kind/filter、跨文件 WorkspaceEdit 摘要预览、打开 tab / 本地 `file://` 文档 text edits 应用、打开 tab / 本地未打开文件 resource operations、command payload 执行结果/错误展示、App 层跨 family event stream 接入和阶段 196-221 core WorkspaceEdit transaction 起点/root-gated 本地文件覆盖/App apply helper 主路径/基础 preview confirmation/专用 diff preview panel 起点/未打开文件 text edit rollback、open-tab rollback、atomic apply mode、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点已完成；仍缺更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。
- document/workspace symbols result typed payload wrapper、App 主路径 typed payload 消费、基础错误/超时/空结果反馈、最近结果 snapshot、reopen command、bounded in-memory history command、workspace symbols 增量查询面板、kind 分组/稳定排序、基础持久 Outline/Symbols panel、通用 lifecycle store 起点、typed lifecycle entry/envelope 元数据和 App 层跨 family event stream 接入已完成；持久在线 panel 已开始消费 lifecycle entry、显示 lifecycle metadata，并能在 active 文档编辑后展示 stale 状态和 active request feedback error 状态；opened-document workspace outline store、`Workspace Outline` panel command、core-owned workspace outline snapshot ABI/Swift wrapper、App 消费起点和打开 tab 的 core document URI metadata 已完成。仍缺跨 tab/project panel UI、project/session/root 归属下沉和更完整刷新/过期策略。
- range formatting Swift/App 主路径已完成；on-type formatting binding、换行触发、server trigger characters 自动触发路径、显式 Swift/App 错误展示、formatting typed outcome 和 core-owned request lifecycle event 已完成；自动 on-type 异步 response error 已进入 LSP status/detail，并有 status refresh + 去重 HUD；Swift 已有 typed `lspStatusSnapshot()`、LSP event metadata typed accessor 和 pull diagnostics typed payload envelope，AttoEditor 的 LSP status/capabilities 行为路径也已迁到 typed snapshot。后续仍缺状态变更订阅模型。
- folding ranges request/take/apply 到 fold state、typed result wrapper、App typed payload 消费、App refresh 命令、typed capability gate、错误反馈、typed fold snapshot、status bar 折叠摘要和 renderer 层 gutter fold marker 视觉回归 baseline 已完成；仍缺更完整的 result lifecycle model。
- code lens refresh/resolve、selection range、linked editing、diagnostics pull、document color/color presentation、call hierarchy、type hierarchy、inlay hints、document links 的 raw request/take binding 已完成；code lens 已有 typed payload wrapper、App typed payload 消费、手动刷新入口、HUD 反馈、active actions quick panel、当前行键盘定位命令、action title core document URI projection、inline Cmd-click 执行路径、typed parser、自动辅助刷新消费、状态栏数量反馈和持久 Code Lens panel，inlay hints / document links 已有 typed payload/resolve wrapper、自动 decorations/hit-test 主路径、显式 refresh command/menu/HUD、apply-to-decoration 主路径、document link unresolved Cmd-click resolve/open 主路径和 inlay hint inline virtual text Cmd-click resolve/show/apply 主路径，且 inlay hints 与 document links 已有持久 panel，selection range 已有 typed payload wrapper、App typed payload 消费、App expand-selection 命令、typed candidate model 和多光标策略，linked editing 已有 typed payload wrapper、App typed payload 消费、App multi-cursor selection 主路径、wordPattern/shared-text 校验和轻量 session lifecycle，document color/color presentation 已有 typed payload wrapper、App typed payload 消费、quick panel、直接 color picker、edit apply 主路径、App 层跨 family event stream 接入和持久 Document Colors panel，call/type hierarchy 已有 typed payload wrapper、App typed payload 消费、基础 quick panel 导航、typed parser 和最近结果持久 Hierarchy panel，diagnostics 已有 pull typed payload wrapper、workspace diagnostics App typed payload 消费、active-tab Problems quick panel、active-tab 持久 Problems panel、workspace diagnostics quick panel、core-backed workspace Problems store/panel、core-backed marker snapshot、workspace/active marker unified model、统一状态栏摘要、active-tab/workspace Problems list 统一模型消费、lifecycle entry、events-after 查询、stale/refresh lifecycle metadata、App 层跨 family event stream 接入、core-owned workspace diagnostics event stream 起点、workspace Problems store event cursor 消费起点、workspace marker projection event cursor 缓存刷新、`EditorUi` core-owned result slot event stream 起点、MultiDocument/project 级 result event 聚合起点、`EditorUi` request lifecycle event stream 起点、MultiDocument/project 级 request event 聚合起点、显式 cancel/timeout lifecycle、on-type formatting request lifecycle、UI auxiliary derived-state request lifecycle、semantic/folding internal refresh request lifecycle、diagnostics notification/pull lifecycle、Swift 事件元数据 typed accessor、`EditorUi` unified state event drain 起点、MultiDocument/project unified state event 聚合起点和文本/dirty/selection/viewport/layout/derived-state changed/stale state event，semantic tokens 已有 typed result payload wrapper 和 App typed apply baseline；active status/diagnostic marker 主路径、workspace Problems store 和 workspace marker projection 已开始消费对应 core-owned event cursor，Locations/Symbols 持久在线 panel 已开始消费 lifecycle entry、显示 lifecycle metadata，并能在 active 文档编辑后展示 stale 状态和 active request feedback error 状态，opened-document workspace outline store 与 core-owned workspace outline snapshot 起点已补齐，跨 result family 的统一 LSP Workbench panel 入口已补齐，且 Problems/Workspace Problems、Locations/Symbols、Workspace Outline、Code Lens、Inlay Hints、Document Links、Document Colors 与 Hierarchy 行已开始显示或分流 lifecycle metadata/stale/error 状态，其中 event-backed Code Lens/Inlay Hints/Document Links/Document Colors/Hierarchy 行已能随当前文档编辑显示 Stale，Code Lens/Inlay Hints/Document Links refresh 失败以及 Document Colors/Hierarchy 请求流失败也会进入 Error 状态；仍缺更完整跨 tab/project panel UI。
- LSP result panels 和错误展示。

### P1：统一多文档和分屏架构

- 明确采用 core-owned workspace：`editor-core` / `editor-core-ui` 的 `Workspace` / `MultiDocumentEditorUi` 是多文档、tab、split、project/session 的状态来源。
- `MultiDocumentEditorUi` 基础 FFI/Swift 投影已完成，覆盖 open/select/close/pin/preview/split/view move/tab move/search-all-tabs、tab 文本同步、dirty/saved snapshot、tab document URI 与 language id metadata、workspace diagnostics store、workspace diagnostic marker snapshot、workspace diagnostics event stream 起点、MultiDocument/project 级 result event 聚合起点和 MultiDocument/project 级 request event 聚合起点；AttoEditor tab/pane lifecycle、tab order、编辑文本、语言 metadata、workspace Problems snapshot、workspace markers、workspace/active diagnostics 状态栏摘要、active-tab/workspace Problems list、diagnostics lifecycle entry、events-after 查询、stale/refresh lifecycle metadata 和 App 层跨 family event stream 起点已开始同步到 core-backed 投影，Find in Files opened scope 已改为 core open-tab search，split pane session restore、pane move、tab move 和 dirty/close/resource-operation 保护条件已同步到 core snapshot；`EditorUi` 已有 core-owned result slot event stream 起点、request lifecycle event stream 起点、显式 cancel/timeout lifecycle、on-type formatting request lifecycle、UI auxiliary derived-state request lifecycle、semantic/folding internal refresh request lifecycle、Swift event metadata typed accessor 和 pull diagnostics typed payload envelope；workspace root 变更和 session restore 后已能基于 core-projected open tabs 自动批量启动可配置但尚未启用的 LSP session，LSP process status 已包含 running/exited/exit code/signal 和 bounded stderr tail，project status events 面板可展示 failed status 的 stderr tail，Swift/App 侧已有 bounded project LSP process health history、轻量 health 面板、dashboard 起点和 summary/recovery policy/inline recovery action/server grouping/trend summary、JSONL 持久化日志、按 workspace retention、大小/时间轮转、filter DSL、显式 log 查询面板、当前 workspace 清空入口/确认、当前 workspace 导出入口和 failed/exited 可配置自动重启/退避/参数调整起点，并可在 dashboard 中按 server 禁用/启用 auto-restart、调整 max attempts/base delay、重置回全局策略；`MultiDocumentEditorUi` 也已有 project-level LSP server launch metadata store / FFI / Swift wrapper 起点，AttoEditor 已开始把打开 tabs 的 `lspServerConfig` 同步到该 core store；仍缺完整 core-owned project/LSP ownership schema、typed lifecycle 启停、跨独立 project session 策略和完整 dashboard 产品化。
- 将 AttoEditor 现有 Swift tabs/splits 迁移为 core workspace state 的 AppKit 投影，而不是继续维护独立 workspace/tab/session model；新增字段时要区分“UI 表现缓存”和“文档/workspace 所有权状态”。
- 继续产品化 split panes：pane move 已按 core `MultiDocumentEditorUi` view reorder 语义接入；拖拽 tab 到 split 等仍缺。新增命令和状态归属必须先落在 core workspace 模型，然后通过 FFI/Swift wrapper 驱动 AppKit 表现。
- 继续收敛 session restore、preview tab、pin tab、dirty state、close semantics；dirty/close 保护条件和 tab movement 已经 core-backed，剩余重点是把更高层关闭命令、tab drag/drop 和 project/session 归属完全转为 core workspace command/query。
- 明确 project/workspace 与 LSP server lifecycle 由 core workspace 模型协调，Swift 只负责启动参数、UI 触发和展示；当前 root diff、workspaceFolders 通知、shared root alias、project restart/shutdown/close、root 变更/session restore 后的自动启动、stderr tail 状态、项目级失败事件展示、bounded 进程健康历史、轻量 health 面板、dashboard 起点和 summary/recovery policy/inline recovery action/server grouping/trend summary、JSONL 持久化日志、按 workspace retention、大小/时间轮转、filter DSL、显式 log 查询面板、当前 workspace 清空入口/确认、当前 workspace 导出入口、failed/exited 可配置自动重启/退避/参数调整起点、dashboard 内 server-level auto-restart 禁用/max/base 调整/reset 入口、core-owned project LSP server launch metadata store + App projection 同步，以及 core tab language metadata 已有起点，剩余重点是把 typed lifecycle 启停、更深层 ownership、恢复策略和健康视图继续下沉/产品化。
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
| LSP completion | yes | partial helper | yes | yes, raw completion + resolve result | yes, raw completion + resolve result + typed CompletionList/CompletionItem wrapper | yes, popup + auto trigger + incremental filter + typed payload poll path + commit-time resolve/current-doc/cross-file text edits apply | partial |
| LSP symbols | yes | partial helper | yes | yes, raw JSON result + typed document symbols snapshot | yes, raw JSON result + typed document/workspace symbols wrapper + typed document symbols snapshot | yes, document/workspace symbols typed payload poll path; document symbols quick panel consumes typed snapshot; workspace symbols have incremental query panel + stable grouped sorting; last-result reopen + in-memory history commands exist | yes |
| LSP rename | yes | partial helper | partial | partial, raw request + current-doc WorkspaceEdit apply | partial, raw result + typed prepareRename/WorkspaceEdit wrapper + current-doc WorkspaceEdit apply | yes, prepareRename typed seed + input UI + menu/keymap + typed payload poll path + current-doc/cross-file text edits apply + opened/unopened local resource operations | partial |
| LSP code action | yes | partial helper | partial | partial, raw request/resolve + current-doc WorkspaceEdit apply + executeCommand result envelope | partial, raw result + typed result/resolve wrapper + typed diagnostics context + kind filters + current-doc WorkspaceEdit apply + executeCommand result envelope | yes, quick panel/menu/keymap/typed payload poll path/typed diagnostics context/kind-filter commands/current-doc/cross-file text edits apply + opened/unopened local resource operations + command result/error HUD | partial |
| LSP formatting | yes | partial helper | yes, document/range/on-type blocking apply + trigger-character auto path | yes, document/range/on-type blocking apply | yes, typed document/range/on-type helpers + formatting outcome | document + selection commands with no-edits/error HUD; on-type trigger-character auto path | partial |
| LSP folding ranges | yes | partial helper | yes, request/take + apply to fold regions | yes, raw request/take + apply JSON | yes, raw request/take + typed result wrapper + typed apply wrapper + apply JSON | yes, typed payload poll path + refresh command applies ranges and fold commands use current state | yes |
| LSP advanced raw requests | yes | partial helper | yes, code lens refresh/resolve + selection/linked editing/diagnostics/color/hierarchy raw request/take + semantic tokens full/delta/range request/take + inlay/document links manual request/take/resolve + workspace diagnostics store/marker snapshot/event stream in `MultiDocumentEditorUi` + per-`EditorUi` LSP result slot event stream + multi-document LSP result event aggregation + per-`EditorUi` request lifecycle event stream + multi-document LSP request event aggregation + explicit request cancel/timeout lifecycle + on-type formatting request lifecycle + UI auxiliary derived-state request lifecycle + semantic/folding internal refresh request lifecycle + diagnostics notification/pull lifecycle + multi-document WorkspaceEdit open-tab transaction preview/apply | yes, raw request/take JSON + semantic tokens full/delta/range request/take ABI + inlay/document links request/take/resolve ABI + code lens/inlay hint/document link view-point hit-test + multi-document workspace diagnostics snapshot/previousResultIds/marker/events ABI + per-`EditorUi` LSP result events ABI + multi-document LSP result events ABI + per-`EditorUi` request events ABI + multi-document LSP request events ABI + request cancel/timeout lifecycle ABI + multi-document WorkspaceEdit transaction/undo ABI | yes, raw request/take JSON + code lens hit-test wrapper + inlay hint/document link hit-test wrapper + code lens typed result/resolve wrapper + inlay/document links typed result/resolve wrapper + location family typed result wrapper + rename/WorkspaceEdit typed result wrapper + selection range typed result wrapper + linked editing typed result wrapper + document color/color presentation typed result wrapper + call/type hierarchy typed result wrapper + diagnostics pull typed result wrapper + folding ranges typed result wrapper + semantic tokens typed result wrapper + LSP/workspace diagnostics event metadata typed accessor + `MultiDocumentEditorUI` workspace diagnostics snapshot/previousResultIds/marker/events/result-events/request-events/workspace-edit-transaction/undo wrapper + `EditorUI.lspResultEvents(after:)` / `lspRequestEvents(after:)` / `lspCancelRequest(_:)` / `lspMarkRequestTimedOut(_:)` wrapper | partial, definition/declaration/typeDefinition/implementation/references consume typed location payload; rename consumes typed prepare/result payload; code lens consumes typed payload; selection range consumes typed payload; linked editing consumes typed payload; document colors consume typed payload; call/type hierarchy consumes typed payload; workspace diagnostics consume typed payload; folding ranges consume typed payload; semantic tokens consume typed payload/apply baseline; code lens actions/current-line command/inline Cmd-click/status count; inlay/document links 的自动 decorations、document link open URL、手动 typed payload、resolve payload、显式 refresh command/menu/HUD 和 apply-to-decoration 路径已可达；document links 的 unresolved link Cmd-click resolve/open 主路径已可达；inlay hints 的 inline virtual text Cmd-click resolve/show/apply 主路径已可达；workspace Problems store/panel, workspace markers, workspace/active diagnostics status summary, active-tab/workspace Problems list, lifecycle entry, events-after query, App-level cross-family event stream, core-owned workspace diagnostics event stream, workspace Problems store and marker projection event cursor consumption, Locations/Symbols persistent panels consuming lifecycle entries, showing lifecycle metadata, stale state after active document edits and active request feedback error state, per-`EditorUi` result slot event stream, multi-document result event aggregation, per-`EditorUi` request lifecycle events, multi-document request event aggregation, explicit cancel/timeout lifecycle, on-type formatting request lifecycle, UI auxiliary derived-state request lifecycle, semantic/folding internal refresh request lifecycle, diagnostics notification/pull lifecycle and WorkspaceEdit transaction consume core-backed snapshots/events for open tabs and root-gated unopened local files; AttoEditor WorkspaceEdit apply helper now uses the core transaction path with a basic preview confirmation, dedicated diff preview panel start, unopened-file text edit rollback, open-tab rollback, atomic apply mode, atomic runtime failure rollback, resource-order dependency preflight, ordered unsupported dependency preflight, resource operation typed summary, dirty/conflict typed summary, open-tab projection undo grouping, and one-shot transaction undo command; still missing cross-tab/project panel UI plus deeper conflict semantics and multi-level/global transaction-wide undo semantics | partial |
| split view | partial | no | yes | yes, clone view + move view | yes, clone view + AppKit split pane + move pane | yes, split/focus/move/close pane commands | yes |
| workspace tabs/splits | yes, headless `Workspace` | partial `Workspace` wrapper with view-local command conveniences | yes, `MultiDocumentEditorUi` | yes, `MultiDocumentEditorUi` ABI + close-view + move-view + move-tab + text/dirty sync | partial `MultiDocumentEditorUI` wrapper; Atto tab/pane lifecycle, tab move, pane move and edited text mirror core snapshot/search, but session/project/LSP ownership is still transitional | partial, transitional AppKit projection; new tab/workspace semantics must move to core-owned workspace first | partial |

阶段 221 后，矩阵中 `WorkspaceEdit` 的 core transaction 起点已从 open-tab 覆盖扩展到 root-gated 未打开本地文件 text edits/resource operations，并按 `documentChanges` 顺序交错应用 text edits 与 resource operations；未打开本地 resource operation、未打开文件 text edit 和打开 tab 状态变更的 fatal failure 已有补偿回滚起点，打开 tab 的本地 resource operation 也已开始由 core transaction 执行 root-gated 文件系统副作用；AttoEditor 的 WorkspaceEdit apply helper 主路径也已切到 `MultiDocumentEditorUI.applyWorkspaceEditTransaction(...)`，并有基础 preview confirmation、专用 diff preview panel 起点、atomic runtime failure rollback、resource-order dependency preflight、ordered unsupported dependency preflight、resource operation typed summary、dirty/conflict typed summary、打开 tab App 投影 undo grouping 起点、最近一次 transaction undo 起点和用户级 command/menu/keymap 起点。仍未完成的是更深层 conflict 检测/展示和多级/global transaction-wide undo 语义。

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
