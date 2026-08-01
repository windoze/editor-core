# Swift 绑定与 UI 集成缺口审计

审计日期：2026-08-01

本文记录当前 Swift 侧、FFI 层、`editor-core-ui` 适配层以及 AttoEditor App 层相对 `editor-core-*` 能力的功能缺口。这里的 “Swift UI” 指仓库中的 Swift/AppKit/Skia/Metal 集成，不是 Apple SwiftUI 框架。

本文关注的是“能否从 Swift 产品层完整使用 `editor-core-*` 能力”，不是评价 Rust core 自身是否完整。总体结论是：**当前 Swift 路径已经能支撑一个可用编辑器主流程，但还不是 `editor-core-*` 的完整能力投影**。尤其对于“复刻 Sublime Text”这个目标，缺口主要集中在命令面、LSP 产品化、派生状态可观测性、多文档/分屏归属、Sublime 兼容行为和视觉/交互测试体系。

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
- `EditorCoreUI` / `AttoEditor` 已有 AppKit 组件级 XCTest，能用 `NSWindow`、`NSEvent` 和 view API 驱动交互。
- 2026-08-01 本地验证过：
  - `swift test --filter AttoEditorTests` 通过，35 个测试。
  - `swift test --filter EditorCoreUITests` 通过，64 个测试。

这说明当前 Swift 路径不是“不可用”，而是“主流程可用、完整能力映射不足”。

## 实现进度

- 2026-08-01 阶段 1 已完成：`editor-core-ui` 新增 `EditorUi.execute_command_json`，`editor-core-ui-ffi` 新增 `editor_core_ui_ffi_editor_ui_execute_command_json`，Swift `EditorCoreUIFFI.EditorUI` 新增 `executeCommandJSON(_:)`。
- 阶段 1 已让 Swift UI 层可通过 JSON 执行核心 edit/cursor/view/style 命令，并补上 `type_char`、IME coalescing replace、`apply_snippet`、snippet placeholder navigation、auto-pairs config、bracket highlight update/clear 等 UI command schema。
- 阶段 1 已用 Rust integration tests 和 Swift `EditorCoreUIFFITests` 覆盖 line commands、toggle comment、apply text edits、wrap/fold、snippet、auto-pairs。
- 阶段 1 尚未完成 App 层 command registry、菜单/keymap/command palette 接线，也尚未为所有命令提供 Swift typed convenience API。

## 分层结论

### 1. Headless core 到 headless Swift FFI

`editor-core-ffi` 通过 JSON command plane 暴露了不少核心命令，Swift `EditorState.executeJSON(_:)` 和 `Workspace.executeJSON(viewId:commandJSON:)` 可以使用这条路径。

主要问题：

- JSON 命令面不是 `editor-core` 全量枚举的一比一映射。
- 一些低频但对 Sublime 兼容很关键的命令没有进 `editor-core-ffi`。
- Swift headless wrapper 有 JSON escape hatch，但高层 Swift 类型化 API 不完整。

### 2. `editor-core-ui` 到 Swift `EditorUI`

`editor-core-ui` 本身比 Swift `EditorUI` 暴露更多能力。阶段 1 已经补上 Swift UI 通用 JSON dispatcher，因此很多 core/FFI 已有能力现在可以到达 Swift `EditorUI`；但 Swift typed convenience API 和 AttoEditor App 命令系统仍未完整接线。

主要问题：

- UI 层 typed API 仍不是 core 命令面的完整子集。
- 部分能力现在只能通过 `executeCommandJSON(_:)` 使用，还没有专门的 Swift typed API。
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
| `TypeChar` | 有 | UI JSON 有，headless FFI 缺 | `insertText` 单字符会在 Rust UI 内部走 typing 路径，Swift 可通过 `executeCommandJSON` 显式调用 | 仍缺 typed Swift API 和 App command id。 |
| `ReplaceCoalescingUndo` / `ReplaceCoalescingUndoWithSelection` | 有 | UI JSON 有，headless FFI 缺 | IME/marked text 路径内部使用相关语义，Swift 可通过 `executeCommandJSON` 显式调用 | 仍缺 typed Swift API；headless FFI 覆盖仍不一致。 |
| `ApplySnippet` | 有 | UI JSON 有，headless FFI 缺 | Swift 可通过 `executeCommandJSON` 调用；Tab/Backtab 可在 snippet active 时切 placeholder | 仍缺 completion UI 接线和 typed `applySnippet`。 |
| `SnippetNextPlaceholder` / `SnippetPrevPlaceholder` | 有 | UI JSON 有，headless FFI 缺 | Swift 可通过 `executeCommandJSON` 调用，`insertTab` / `insertBacktab` 也内部支持 | 仍缺 App command/keymap 绑定。 |
| duplicate lines | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 AttoEditor command。 |
| delete lines | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 AttoEditor command。 |
| move lines up/down | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 AttoEditor command。 |
| join lines | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 AttoEditor command。 |
| split line | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 AttoEditor command。 |
| toggle comment | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | App 层没有稳定命令入口，也缺语言 comment config 的完整桥接。 |
| general `ApplyTextEdits` | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用；Rust UI 也有 LSP text edit apply helper | LSP completion、code action、rename、format 仍需要产品化接线。 |
| `DeleteToPrevTabStop` | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 AttoEditor command。 |
| explicit indent/outdent commands | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用；Tab/Backtab 主路径可用 | 仍缺 typed Swift API 和 App command/keymap 表达。 |
| `EndUndoGroup` | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API；App 层复合命令还未统一使用。 |
| logical `MoveTo` / `MoveBy` | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用，也可通过 selection/conversion 间接达成 | 仍缺 typed Swift API 和可配置 key binding。 |
| visual movement commands | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用，AppKit key handling 覆盖一部分 | 仍缺 App command coverage matrix。 |
| `MoveToMatchingBracket` | 有 | headless FFI 缺 | Swift UI 有公开方法 | headless 和 UI command 面不一致。 |
| add occurrence options | 有 | 有 | Swift 可通过 `executeCommandJSON` 传 options；typed `addNextOccurrence()` / `addAllOccurrences()` 仍无 options | 仍缺 typed options API。 |
| `SetWrapMode` | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 settings 接线。 |
| `SetWrapIndent` | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 settings 接线。 |
| `SetIndentationConfig` | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和语言配置接线。 |
| `SetAutoPairsConfig` | 有 | UI JSON 有，headless FFI 缺 | Swift 可通过 `executeCommandJSON` 调用；也有 enabled bool | 仍缺 typed config API；headless 和 UI command 面仍不一致。 |
| `SetAutoPairsEnabled` | 有 | UI JSON 有，headless FFI 缺 | Swift UI 有 bool，也可通过 `executeCommandJSON` 调用 | headless 和 UI command 面仍不一致。 |
| fold / unfold / unfold all | 有 | 有 | Swift 可通过 `executeCommandJSON` 调用 | 仍缺 typed Swift API 和 AttoEditor command/keymap。 |
| bracket match highlight update/clear | 有 | UI JSON 有，headless FFI 缺 | Swift UI 有 enabled bool 和内部更新，也可通过 `executeCommandJSON` 显式调用 | headless 和 UI command 面仍不一致。 |

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
- format。
- diagnostics 派生状态应用。
- semantic tokens 到 style intervals 的应用。
- inlay hints。
- code lens 派生显示。
- document links hit-test。
- document highlights。
- `LSPBridge` 中有若干 JSON/DTO 转换 helper。

仍缺产品化或缺公开 API 的 LSP 能力：

- declaration。
- type definition。
- implementation。
- references。
- completion request、completion resolve、completion popup、commit characters、additional text edits、snippet insertion。
- signature help。
- rename / prepare rename。
- code action / code action resolve / execute command。
- code lens resolve / command execution。
- document symbols UI。
- workspace symbols UI。
- range formatting。
- on-type formatting。
- semantic tokens refresh / delta 策略。
- folding ranges request 到 fold UI 的完整通道。
- selection range。
- linked editing。
- document diagnostic pull / workspace diagnostic。
- document color / color presentation。
- call hierarchy。
- type hierarchy。
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

Swift UI 当前可以应用多种派生状态，尤其是 LSP diagnostics、semantic tokens、inlay hints、code lens、document links、document highlights，以及 Tree-sitter/Sublime 产生的样式信息。

缺口是可观测性和统一控制：

- `EditorUI` 没有统一 API 获取当前 diagnostics 列表。
- `EditorUI` 没有统一 API 获取当前 decorations。
- `EditorUI` 没有统一 API 获取当前 document symbols。
- `EditorUI` 没有统一 API 获取当前 fold regions。
- `EditorUI` 没有统一 API 获取当前 style layers 或样式区间。
- App 层没有一个统一的 derived-state store，供 outline、problems panel、minimap markers、gutter icons、status bar、测试断言共同使用。

这会影响 Sublime 复刻中的这些功能：

- Problems panel。
- Outline / symbol list。
- Goto symbol。
- Minimap 标记。
- Gutter diagnostic icons。
- Fold commands。
- 视觉回归测试中的“结构化断言”。

## 多文档、tab、workspace 和分屏缺口

当前仓库里存在多套相关模型：

- `editor-core` 有 headless `Workspace`。
- `EditorCoreFFI.Workspace` 暴露了一部分 headless workspace 能力。
- `editor-core-ui` 有 `MultiDocumentEditorUi`，包含 tab、preview tab、pin、close、split、search all tabs 等能力。
- Swift `EditorUI.cloneView` 可以创建共享 buffer 的额外 view。
- AttoEditor App 当前主要在 Swift 层维护 tabs，每个 tab 持有自己的编辑器实例。

主要缺口：

- `MultiDocumentEditorUi` 没有通过 FFI/Swift 暴露。
- AttoEditor 的 tab 系统和 Rust UI 的 multi-document 系统没有统一。
- App 层尚未产品化 split pane。
- `cloneView` 是底层能力，不等于完整 split layout、focus、tab movement、关闭语义、状态恢复。
- workspace/project 级 LSP 同步、全局搜索、recent files、session restore 与 tab 模型之间缺统一归属。

这里需要先做架构决策：

- 方案 A：多文档、tab、split、project、session 都由 Swift App 层拥有，Rust 只提供 per-buffer/per-view editor UI。
- 方案 B：把 `MultiDocumentEditorUi` 暴露到 Swift，Rust UI wrapper 拥有 tab/split/search all tabs 等模型。

当前状态更接近方案 A，但还保留了 Rust 侧 `MultiDocumentEditorUi` 未使用能力。长期混用会让功能覆盖、测试和状态同步变复杂。

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

主要缺口：

- 没有完整 command registry。
- command palette 覆盖面很窄。
- 菜单、快捷键、command palette、测试没有统一 command id。
- 很多 core 命令没有 App 命令入口。
- 没有 Sublime 风格可配置 keymap。
- 没有 Sublime 风格 settings scopes。
- 没有宏录制/回放。
- 没有 build systems。
- 没有 package/plugin command 入口。
- 命令是否启用、是否可见、当前参数、错误展示没有统一模型。

建议 App 层先建立命令注册表：

- 每个命令有稳定 id，例如 `editor.duplicateLine`、`editor.toggleComment`、`lsp.rename`。
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
- keymap 文件格式和冲突解析。
- snippets。
- macros。
- build systems。
- projects/workspaces。
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
- LSP 相关返回值和事件缺统一 envelope。
- 长任务、异步请求、取消、错误、诊断日志没有统一 Swift 事件流。
- 配置 DTO 不完整，例如 wrap、indentation、comment、auto-pairs、word boundary、search options。
- 缺 ABI version / feature probing 在 Swift 层的显式使用策略。

建议演进方向：

- 继续使用 `editor_core_ui_ffi_editor_ui_execute_command_json(editor, command_json)` 作为 UI escape hatch。
- Swift `EditorUI.executeCommandJSON(_:)` 作为低频/迁移命令入口。
- 常用命令再补 typed convenience API。
- FFI 返回统一 `{ ok, value, error, version }` 风格。
- Swift 层封装稳定 enum/struct，但保留 unknown command 的转发能力。
- App 命令系统只依赖 Swift command abstraction，不直接散落调用 FFI 函数。

## 优先级建议

### P0：先补命令通道和 Sublime 基础编辑命令

- 已完成：给 Swift UI 增加通用 command JSON dispatcher。
- 已完成：通过 `executeCommandJSON(_:)` 暴露 duplicate/delete/move lines、join/split line、toggle comment、fold/unfold、wrap mode、wrap indent、indentation config。
- 已完成：通过 `executeCommandJSON(_:)` 暴露 general `applyTextEdits`。
- 已完成：通过 `executeCommandJSON(_:)` 暴露 `applySnippet` 和 snippet placeholder navigation。
- 待完成：建立 Swift/App command registry。
- 待完成：为高频命令补 typed Swift convenience API。
- 为这些命令补 AppKit 操作测试和结构化状态测试。

### P1：补 LSP 产品主路径

- completion popup。
- signature help。
- references/implementation/declaration/type definition。
- rename。
- code action。
- document/workspace symbols。
- range/on-type formatting。
- folding ranges。
- linked editing。
- LSP result panels 和错误展示。

### P1：统一多文档和分屏架构

- 明确采用 Swift-owned tabs/splits 还是 Rust `MultiDocumentEditorUi`。
- 产品化 split panes。
- 统一 session restore、preview tab、pin tab、dirty state、close semantics。
- 明确 project/workspace 与 LSP server lifecycle 的归属。

### P2：深化 Sublime 兼容

- settings scopes。
- keymap 文件。
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
| duplicate line | yes | yes | partial | no | no | no | no |
| toggle comment | yes | yes | partial | no | no | no | no |
| apply snippet | yes | no | partial | no | no | no | no |
| LSP rename | yes | partial helper | partial | no | no | no | no |
| split view | partial | no | yes | no | low-level clone only | no | no |

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
