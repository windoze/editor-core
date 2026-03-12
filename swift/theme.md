# 主题引擎（Theme Engine）规划（EditCoreUI / EditorCoreUI / AttoEditor）

> 目标：在 `EditCoreUI` / `EditorCoreUI` 及相关包中引入“主题引擎”，将 `StyleId` 映射为可视样式（颜色 + 字体样式），并在 `AttoEditor` 中暴露为可配置能力。
>
> 本文只做规划与接口/数据格式设计，不包含实现代码。

## 背景与现状

- `editor-core`（Rust）侧输出 `HeadlessGrid`，其中每个 cell 带一组 `StyleId`。
- Swift 侧（`EditorCoreUI`）已经有 `EditorCoreSkiaTheme`（`swift/Sources/EditorCoreUI/EditorCoreSkiaTheme.swift`），可以：
  - 设置编辑器基础颜色（背景/前景/选区/caret）。
  - 通过 `setStyleColors / setStyleFonts / setStyleTextDecorations` 将 `StyleId -> 样式` 下发给 Rust/Skia renderer。
  - 支持按 Tree-sitter capture 名称映射到稳定 `StyleId`（`treeSitterStyleId(forCapture:)`）。
- `AttoEditor` 当前在 `AttoAppDelegate` 里硬编码使用 `EditorCoreSkiaTheme.demoRustLspDark()`，无法选择/切换主题，也没有 JSON 主题文件的加载机制。

## 目标（MVP）

1. **主题定义以 JSON 文件存在**：
   - **内置主题**：随 `AttoEditor`（app package / app bundle）分发。
   - **自定义主题**：放在“应用偏好/配置目录”下（macOS：`~/Library/Application Support/codes.unwritten.attoeditor/themes/`）。
2. **主题必须有唯一名称**（`name` 字段）。
   - 若自定义主题与内置主题 **同名**，则 **自定义覆盖内置**（以 name 为 key）。
3. **应用设置指定当前使用的主题**：
   - `AttoEditor` 提供一个可持久化的 setting（`UserDefaults`）来保存“当前主题名”。
   - 当 setting 变化时，对已打开的编辑器视图应用新主题。
4. **核心能力：StyleId -> 可视样式**：
   - 至少覆盖 `foreground/background/bold/italic/underline/strikethrough` 等。
   - 与现有 `EditorCoreSkiaTheme.apply(to:)` 的下发方式一致。

## 非目标（暂不做，后续可扩展）

- 主题市场/在线下载、云同步。
- 文件系统 watch（自动热重载自定义主题）。
- 完整的 app chrome 全量主题化（tab bar / status bar / sidebar 等）；MVP 先保证编辑器区域（Skia renderer + minimap/scrollbar）可切换。
- 主题继承（`inherits`）与多层合并（可在 v2 扩展）。

## 总体方案

### 分层与职责

**EditorCoreUI（可复用层）**

- 提供 JSON schema（`ThemeDefinitionV1`）与解析/校验能力。
- 将 `ThemeDefinitionV1` 转换为运行时可应用的 `EditorCoreSkiaTheme`。
- 提供“主题加载器/注册表”基础设施（不绑定 AttoEditor 目录约定）：
  - `ThemeLoader.load(from url: URL) -> ThemeDefinitionV1`
  - `ThemeRegistry`：合并多个来源（bundle + filesystem），按 name 去重并提供列举/查询。

**AttoEditor（应用层）**

- 规定内置主题存放位置（bundle resources）与自定义主题目录（Application Support）。
- 增加偏好设置：当前主题名。
- 启动时加载主题列表与当前主题，并应用到所有窗口/标签页。
- Preferences UI：提供主题下拉选择（MVP），并可添加“打开主题目录”按钮方便用户编辑 JSON。

### 数据流（MVP）

1. App 启动：
   - 扫描内置主题（bundle）与自定义主题目录（Application Support）。
   - 合并为 `ThemeRegistry`（自定义覆盖内置）。
2. 读取 `AttoPreferences` 的当前主题名：
   - 若存在且能在 registry 找到：使用该主题。
   - 否则回退到默认主题（例如 `"Atto Dark"`）。
3. 对所有已创建的 `EditCoreUI` 实例调用 `applyTheme(resolvedTheme)`。
4. 用户在 Preferences 中切换主题名：
   - 更新 `UserDefaults` 并广播 `.attoPreferencesDidChange`。
   - `AttoAppDelegate` 收到通知后重新解析当前主题并应用到所有窗口/标签页。

## JSON 主题文件设计（v1）

### 文件位置约定

- **内置主题**（随 app 分发）：
  - 建议路径：`swift/Sources/AttoEditor/Resources/Themes/*.json`
  - SwiftPM 通过 target resources 打包进 bundle（需要在 `swift/Package.swift` 的 `AttoEditor` target 增加 `resources`）。
- **自定义主题**（用户可编辑）：
  - 目录：`~/Library/Application Support/codes.unwritten.attoeditor/themes/`
  - 文件名不作为唯一标识，**以 JSON 内 `name` 字段为准**。

### 顶层结构（建议）

```json
{
  "schema_version": 1,
  "name": "Atto Dark",
  "appearance": "dark",
  "editor": {
    "background": "#1E1E1EFF",
    "foreground": "#D4D4D4FF",
    "selection_background": "#264F78FF",
    "caret": "#AEAFADFF"
  },
  "chrome": {
    "gutter_background": "#252526FF",
    "gutter_foreground": "#858585FF",
    "gutter_separator": "#333333FF",
    "fold_marker_collapsed": "#6B6B6BFF",
    "fold_marker_expanded": "#A0A0A0FF",
    "minimap_background": null,
    "scrollbar_background": null,
    "scrollbar_foreground": null
  },
  "style_overrides": [
    {
      "style": { "builtin": "inlayHint" },
      "foreground": "#9AA0A6FF",
      "background": "#2A2A2AFF",
      "italic": true
    },
    {
      "style": { "reserved": "gutterForeground" },
      "foreground": "#7F848EFF"
    }
  ],
  "tree_sitter_capture_overrides": [
    { "capture": "comment", "foreground": "#6A9955FF", "italic": true },
    { "capture": "string", "foreground": "#CE9178FF" }
  ]
}
```

说明：
- `schema_version`：用于后续演进；v1 固定为 `1`。
- `name`：主题唯一名称（registry 的 key）。
- `appearance`：可选，`"light" | "dark" | "unspecified"`；MVP 可以只用于 UI 分组展示。
- `editor/chrome`：对应 `EditorCoreSkiaTheme` 的基础颜色字段；`minimap_background/scrollbar_*` 允许为 `null`，运行时使用现有推导逻辑（基于背景色 lightened/darkened）。
- `style_overrides`：核心部分：把“某个 style 选择器”映射到 `EditorCoreSkiaStyleSpec`。
- `tree_sitter_capture_overrides`：可选增强：按 capture 名配置样式，应用时由 `EditorUI.treeSitterStyleId(forCapture:)` 转换为稳定 `StyleId`。

### 颜色编码

建议支持两种输入（提高易用性）：

1. **Hex 字符串**：`#RRGGBB` 或 `#RRGGBBAA`（推荐统一写成 8 位，避免 alpha 误解）。
2. （可选）对象形式：`{"r":255,"g":255,"b":255,"a":255}`（便于程序生成）。

解析后统一落到 `EcuRgba8`。

### Style 选择器（v1）

为了让 JSON 既可读又能精确定位 `StyleId`，建议引入 one-of selector：

```json
{ "style": { "style_id": 134217729 } }
{ "style": { "style_id": "0x08000001" } }
{ "style": { "builtin": "inlayHint" } }
{ "style": { "reserved": "gutterBackground" } }
{ "style": { "lsp_semantic": { "token_type": "keyword", "modifiers": ["readonly"] } } }
```

- `style_id`：直接指定 `UInt32`（支持十进制或 `0x` hex 字符串）。
- `builtin/reserved`：映射到 `EditorCoreSkiaBuiltinStyleId` / `EditorCoreSkiaReservedStyleId` 的命名项（对用户更友好）。
- `lsp_semantic`：按 token type + modifiers 生成 style id（使用 `EditorCoreSkiaLspSemanticStyleId` 规则）。
  - 注意：tokenTypes/tokenModifiers 列表必须与 Rust 侧保持同步（见 `EditorCoreSkiaLspSemanticStyleId` 注释）。

MVP 实现优先级建议：
1) `style_id`（最直接）；
2) `builtin/reserved`（易用）；
3) `tree_sitter_capture_overrides`（已有机制，值高）；
4) `lsp_semantic`（对 LSP 主题很关键，但需要同步列表）。

### 样式规格（StyleSpec）

每条 override 支持以下字段（与 `EditorCoreSkiaStyleSpec` 对齐）：

- `foreground` / `background`（颜色）
- `bold` / `italic`（字体样式）
- `underline`（`"single" | "double" | "squiggly"`）
- `underline_color`（颜色，可选；未提供则跟随前景或 renderer 默认）
- `strikethrough`（bool）
- `strikethrough_color`（颜色，可选）

## 主题发现与覆盖规则

### 合并顺序

1. 加载内置主题（bundle）。
2. 加载自定义主题（Application Support）。
3. 合并为 `name -> ThemeDefinition`：
   - 若自定义与内置同名：自定义覆盖。
   - 若同一来源中出现同名：以“后加载者覆盖先加载者”（并记录日志，便于排查）。

### 名称归一化（建议）

为避免大小写导致重复项（例如 `Atto Dark` vs `atto dark`），registry 内部建议：
- key 统一使用 `name.lowercased()` 做索引；
- 保留原始 `name` 用于 UI 展示。

### 容错策略

- JSON 解析失败：记录日志并跳过该主题文件，不影响其它主题。
- 当前主题名找不到：回退到默认主题，并在 UI 中提示（例如在下拉列表里标记“missing”）。

## AttoEditor 设置与 UI 暴露

### Preferences（UserDefaults）

在 `AttoPreferences` 增加：

- `storedThemeName: String?`
- `effectiveThemeName: String`（stored ⟶ env ⟶ default）
  - 可选 env：`ATTO_EDITOR_THEME`
  - default：例如 `"Atto Dark"`（或根据系统外观自动选择 light/dark，后续可做）

新增 setter：

- `setThemeName(_ name: String?)`（传 `nil` 表示回到默认/跟随系统策略）

### Preferences 窗口

在 `AttoPreferencesEditorPageViewController`（或新增独立页面）加入：

- Theme 下拉框：数据源来自 `ThemeRegistry.availableThemes()`。
- “Open Themes Folder” 按钮：打开 `~/Library/Application Support/codes.unwritten.attoeditor/themes/`。
- （可选）“Reload Themes” 按钮：重新扫描目录并刷新下拉框。

### 应用到已打开窗口/标签页

推荐在 `AttoAppDelegate.preferencesDidChange` 中扩展：

- 除现有字体设置外，增加：
  - 重新 `resolve` 当前主题（从 registry 取 `effectiveThemeName`）。
  - 对所有窗口的所有 tabs 调用 `tab.editCore.applyTheme(resolvedTheme)`。
  - 同步更新 editor 容器外层背景（例如 `AttoEditorAreaViewController.view.layer?.backgroundColor`），避免亮/暗不一致。

并在：

- 创建新窗口（`createWindow(...)`）时使用“当前主题”，而不是硬编码 demo theme。

## 代码结构建议（实现时遵循）

> 这里列出建议的类型/文件位置，仅作为规划；最终以实现时的代码组织为准。

**EditorCoreUI**

- `swift/Sources/EditorCoreUI/Theme/ThemeDefinitionV1.swift`
  - `struct ThemeDefinitionV1: Codable`
  - `struct ThemeStyleOverrideV1: Codable`
  - `enum ThemeStyleSelectorV1: Codable`（one-of）
  - `struct ThemeColor: Codable`（支持 hex 或 rgba object）
- `swift/Sources/EditorCoreUI/Theme/ThemeLoader.swift`
  - `loadTheme(from url: URL) throws -> ThemeDefinitionV1`
- `swift/Sources/EditorCoreUI/Theme/ThemeRegistry.swift`
  - `init(builtinURLs: [URL], customURLs: [URL])`
  - `themesByName`（合并与覆盖）
  - `func theme(named:) -> ThemeDefinitionV1?`
  - `func availableThemeNames() -> [String]`
- `swift/Sources/EditorCoreUI/Theme/ThemeConversion.swift`
  - `ThemeDefinitionV1.toSkiaTheme() -> EditorCoreSkiaTheme`（或 `resolve(editor:)`，取决于是否需要 editor handle）

**AttoEditor**

- `swift/Sources/AttoEditor/AttoThemePaths.swift`
  - `builtinThemesURLs()`（Bundle.module）
  - `customThemesDirectoryURL()` / `customThemesURLs()`
- `swift/Sources/AttoEditor/AttoThemeManager.swift`
  - 维护 registry + 当前主题解析
  - 提供 `applyCurrentTheme(to:)` 方法（对窗口/编辑器批量应用）
- `swift/Sources/AttoEditor/AttoPreferences.swift`
  - 增加 themeName setting
- `swift/Sources/AttoEditor/AttoPreferencesEditorPageViewController.swift`
  - 增加 theme 选择 UI（或单独页面）

## 内置主题落地（MVP 交付物）

至少提供两套内置主题 JSON（用于验证 light/dark 切换）：

- `Atto Dark`（对齐当前 `demoRustLspDark` 的主要配色）
- `Atto Light`（对齐当前 `defaultLight` 的主要配色）

实现时建议先把现有 Swift 代码主题参数“翻译”成 JSON，确保视觉一致，再逐步扩展可配置项。

## 测试计划

优先在 Swift 侧加小而稳定的测试（不依赖 UI 渲染）：

- JSON decode：
  - 正常解析（hex、rgba object、可选字段缺失）。
  - 错误输入（非法 hex、未知 underline 值）应抛错或跳过并记录。
- 覆盖规则：
  - builtin + custom 同名：custom 生效。
  - name 大小写：按归一化规则去重。
- 选择与回退：
  - 选中不存在主题名：回退默认。

可选的集成测试（若成本可控）：
- 启动 `AttoEditor`/`EditCoreUIDemo`，应用主题后对关键颜色字段做断言（或 snapshot/黄金图，后续再评估）。

## 里程碑拆分（建议）

1. **Schema v1 + 解析**（EditorCoreUI）
2. **Registry + 覆盖语义**（EditorCoreUI）
3. **AttoEditor：内置主题资源 + 自定义目录扫描**
4. **AttoPreferences：themeName setting + 生效逻辑**
5. **AttoEditor：应用主题到所有 tabs + 新窗口**
6. **Preferences UI：下拉选择 + 打开目录**
7. **测试与文档补充**（README/示例主题）

