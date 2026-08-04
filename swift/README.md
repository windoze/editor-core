# EditorCoreFFI (Swift wrapper)

这是一个从零重写的 Swift 包装层，目标是用 **SwiftPM** 以最小表面积、可靠的方式调用本仓库的 Rust C ABI：`crates/editor-core-ffi`。

当前策略是 **静态链接** Rust `staticlib` 到 Swift 可执行文件/测试里（不再 `dlopen/dlsym`）。

这带来的变化：

- 运行时不再依赖 `libeditor_core_ffi.dylib` / `libeditor_core_ui_ffi.dylib` 的查找路径；
- 需要在构建 SwiftPM 包之前，先用 Cargo 生成对应的 `.a` 产物（或在 CI 里缓存它们）。

## API 选择

新 Swift/App 集成优先使用 runtime negotiation 结果和对应的 typed result envelope。已经有
envelope 覆盖的 workspace file search/list、project file index、workspace file replacement 旧
raw JSON wrapper 仍保留以兼容既有调用方，但在 Swift 层标记为 deprecated；只有在运行时缺少相应
feature bit 且调用方明确接受旧错误形态时，才应作为 legacy fallback 使用。

## 目录结构

- `Sources/CEditorCoreFFI/`：C header module（转发到 `crates/editor-core-ffi/include/editor_core_ffi.h`）
- `Sources/CEditorCoreUIFFI/`：C header module（转发到 `crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h`）
- `Sources/EditorCoreFFI/`：Swift 封装（`EditorState`/`Workspace` 包装 + viewport blob 解析）。
- `Sources/EditorCoreFFIDemo/`：最小 CLI demo（验证加载与基础编辑）。
- `Sources/EditorCoreUI/`：AppKit 组件（自绘 + IME + 事件映射）。
- `Sources/EditCoreUIDemo/`：AppKit demo（使用 `EditCoreUI` 组合 editor + minimap + scrollbar）。
- `Tests/EditorCoreFFITests/`：Swift 侧集成测试。
- `Tests/EditorCoreUITests/`：AppKit 组件测试。

## 构建 Rust staticlib

### 自动构建（推荐）

`swift build` / `swift test` / `swift run` 会通过 SwiftPM build plugin 自动触发：

- `cargo build -p editor-core-ffi -p editor-core-ui-ffi --release`
- 产物输出到 SwiftPM 的 plugin 输出目录（位于 `swift/.build/plugins/outputs/` 下）

注意：SwiftPM 的 build tool plugin 默认运行在 sandbox 中（禁网）。而 `editor-core-ui-ffi` 依赖 `skia-bindings`，
首次构建时可能需要下载 Skia 相关依赖。

在本仓库的日常开发里，通常你已经在仓库根目录构建过 Rust（会生成 `target/debug/libeditor_core_ui_ffi.a`），
plugin 会优先复用该产物来避免在 sandbox 中联网下载。

如果你是全新 clone / `target/` 不存在，建议二选一：

- 先在仓库根目录执行一次：`cargo build -p editor-core-ui-ffi`（生成静态库供 plugin 复用）
- 或在首次构建时直接使用（允许 plugin 联网下载 Skia 依赖）：

```bash
swift build --disable-sandbox
```

或：

```bash
swift test --disable-sandbox
```

### 排错（必要时）

- 如果提示 `cargo: command not found`，请确认：
  - `cargo` 可用（例如 `which cargo` 能找到）
  - 以及 `~/.cargo/bin` 在 PATH 中
- 如果需要确认静态库是否生成，可在 `swift/` 下运行：
  - `find .build/plugins/outputs -name 'libeditor_core_*.a'`

## 运行 demo

```bash
cd swift
swift run EditorCoreFFIDemo
```

自绘 AppKit demo（Skia）：

```bash
cd swift
swift run EditCoreUIDemo
```

## 构建 AttoEditor.app（macOS）

AttoEditor 是一个 AppKit 应用（带 IPC/CLI 启动逻辑），默认的 SwiftPM `executable` 产物是一个裸二进制。
如果你需要一个可双击运行的 `.app` bundle，可以用脚本打包：

```bash
cd swift
scripts/build-attoeditor-app.sh
open .build/app-dist/AttoEditor.app
```

占位图标位于 `Sources/AttoEditor/AppBundle/AppIcon.icns`（可直接替换）。
`CFBundleIdentifier` 固定为 `codes.unwritten.attoeditor`（见 `Sources/AttoEditor/AppBundle/Info.plist`）。

### 当前 App 能力边界

AttoEditor 的长期事实源优先落在 core / `editor-core-ui`，Swift/AppKit 主要负责投影、焦点、面板和视觉状态：

- tabs、split panes、preview/pinned tab、session restore、dirty/save/reload、recent files/projects 和 workspace root 由 core-backed workflow 驱动；
- Quick Open、workspace search、replace-in-files 和 project file index 使用 core-owned workspace data source，并通过 runtime feature negotiation 在旧 runtime 上降级；
- Tree-sitter、Sublime syntax 和 LSP derived state 共同提供 highlighting、folding、outline、diagnostics、semantic tokens、hover、signature help、completion、code actions 和 WorkspaceEdit preview/history；
- Project LSP Dashboard 使用 core-owned project server schema、workspace folders、capabilities、session policy、recovery policy、attempt id、lifecycle events 和 process health log；
- Sublime-like chrome 覆盖 tab bar、sidebar、status bar、quick panel、completion popup、find/replace、split panes、minimap、gutter markers、overlay stacking 和 editor focus restore。

### CLI（`atto`）

AttoEditor 额外提供一个独立 CLI：`atto`，用于终端里打开文件/目录并通过 IPC 发送到主实例（支持 `-n/--new-window`、`-w/--wait`、`file:line:column`）。

开发态运行：

```bash
cd swift
swift run atto -- -n foo.rs:10:5
```

打包后的 `.app` 内也会包含该 CLI：

- `AttoEditor.app/Contents/MacOS/atto`

安装到 PATH（symlink 方式，要求 app 固定在该路径）：

```bash
ln -sf "/Applications/AttoEditor.app/Contents/MacOS/atto" /usr/local/bin/atto
```

如果希望 App 移动后仍可用，可安装 wrapper（会按 bundle id 定位 app）：

```bash
ln -sf "$(pwd)/scripts/atto" /usr/local/bin/atto
```

## 主题（Themes）

AttoEditor 支持通过 **JSON 主题文件**把 `StyleId` 映射为颜色与字体样式（bold/italic/underline/strikethrough）。

### 内置主题

内置主题随 app 一起分发（SwiftPM resources）：

- `Sources/AttoEditor/Resources/Themes/atto-dark.json`（`name = "Atto Dark"`）
- `Sources/AttoEditor/Resources/Themes/atto-light.json`（`name = "Atto Light"`）

### 自定义主题

自定义主题放在用户的 Application Support 目录（可在 Preferences 里一键打开）：

- `~/Library/Application Support/codes.unwritten.attoeditor/themes/*.json`

规则：

- 每个主题必须有唯一 `name`。
- 若自定义主题与内置主题同名，则 **自定义覆盖内置**。

### 当前主题设置

- 偏好设置（持久化）：AttoEditor Preferences -> Editor -> Theme
- 环境变量（可选，作为 fallback）：`ATTO_EDITOR_THEME=Atto Dark`

JSON schema 与实现规划见：`swift/theme.md`

## 运行测试

```bash
cd swift
swift test
```

### Visual baselines

视觉基线由 `Tests/AttoEditorTests/Resources/VisualBaselines/manifest.json` 声明，并覆盖窄窗口、多 pane、长文件、多 cursor、diagnostics、folding、semantic overlays、floating/persistent panels 和 WorkspaceEdit failure/preview 状态。

更新 checked-in PNG：

```bash
# from the repository root
swift/scripts/update-visual-baselines.sh
```

严格比对 checked-in PNG：

```bash
# from the repository root
swift/scripts/check-visual-baselines.sh
```

PR workflow 在仓库包含 `VisualBaselines/*.png` 时走 strict baseline 路径；没有 PNG 时只跑 smoke artifact capture。

### XCUIApplication smoke tests（可选）

`AttoEditorXCUIApplicationSmokeTests` 是 macOS 黑盒 UI 自动化入口。普通 `swift test`
默认只编译这些测试并跳过执行，因为 `XCUIApplication` 需要可访问 `testmanagerd` 的
本机 UI automation 环境。

本地运行：

```bash
cd swift
scripts/build-attoeditor-app.sh --debug --out /tmp/attoeditor-xcui
ATTO_XCUI_SMOKE_TESTS=1 \
ATTO_XCUI_APP_PATH=/tmp/attoeditor-xcui/AttoEditor.app \
swift test --filter AttoEditorXCUIApplicationSmokeTests
```

这些测试会为被测 app 注入独立 IPC socket/spool 路径，避免和当前用户正在运行的
AttoEditor 实例互相影响。
