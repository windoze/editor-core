# AttoEditor Session Manager（Swift 侧实现规划）

目标：在 **不改 Rust 侧**（只做 Swift/AppKit 侧）的前提下，让用户 **双击 `AttoEditor.app`** 启动时能够恢复上一次退出时的工作状态（窗口/工作目录/打开的文件/选中的 tab 等）。

本文只包含实现计划与设计要点，不包含具体代码。

---

## 约束与前提

- **只做 Swift 侧**：不引入 Rust 内核的“会话/工作区”概念变更；所有持久化、恢复逻辑都在 `Sources/AttoEditor/` 下完成。
- 当前 AttoEditor 的 UI 组织：
  - `AttoAppDelegate`：窗口集合、菜单动作、IPC open request 处理。
  - `AttoWindowContext`：一个窗口（workspace root、sidebar、editor area、recent files）。
  - `AttoEditorAreaViewController`：tab 管理 + 每个 tab 的 `EditCoreUI`（editor view + minimap + LSP/Tree-sitter 等）。
- 当前 bundle id：`codes.unwritten.attoeditor`（用于配置目录与 IPC 命名空间）。

---

## 需求定义（MVP → 增量）

### MVP（第一版就要稳定做到）

1. 启动 `.app` 时，若存在 session 文件：
   - 恢复上次的 **窗口列表**（至少 1 个）。
   - 每个窗口恢复：
     - `workspaceRootURL`（文件树根目录）
     - window frame（位置/大小）
     - sidebar 是否折叠
     - 打开的文件 tab 列表（仅恢复“磁盘上仍存在的文件”）
     - 当前选中的 tab
2. 退出（或窗口/标签变化）后能自动保存 session，避免只在 `applicationWillTerminate` 才保存导致 crash 丢状态。
3. 与现有 IPC/CLI 逻辑不冲突：
   - 如果 cold start 过程中已经因为 `AttoIpcServer.processSpool()` 创建了窗口/打开文件，则 **不再额外 restore**（避免打开两套窗口）。

### 第二阶段（可选，但推荐尽早做）

- 每个 tab 额外恢复：
  - minimap 是否开启（`EditCoreUI.showsMinimap`）
  - primary caret 位置（建议用 `line/column` 或 `char offset`，并做 clamp）
  - 视口滚动位置（如果 UI 层能拿到可靠 API）
- 恢复 `recentFiles`（每窗口的最近文件列表）

### 暂不做（明确 non-goals，避免 scope creep）

- 恢复未保存的 buffer 内容（需要持久化全文/增量，体积与性能风险大；可作为未来第三阶段）
- 恢复 LSP/Tree-sitter 的派生状态（这些应由现有逻辑重新计算）
- iCloud/跨设备同步

---

## 存储位置与文件结构

与 Tree-sitter registry 复用同一配置根目录（保持一致性）：

- 配置根目录：`~/Library/Application Support/codes.unwritten.attoeditor/`
  - 可直接复用 `AttoTreeSitterRegistry.defaultPaths().configRoot`
- session 文件建议路径：
  - `configRoot/session.json`
  - 或版本化：`configRoot/sessions/session-v1.json`

写入策略：

- 使用 `Data.write(options: [.atomic])` 原子写入，避免写到一半崩溃导致文件损坏。
- 读取失败（JSON decode error）时，将旧文件 rename 为 `session.json.corrupt-<timestamp>`，然后当作“无 session”继续启动。

---

## 数据模型（Codable + schema version）

新增文件（建议）：

- `Sources/AttoEditor/AttoSessionModels.swift`
- `Sources/AttoEditor/AttoSessionStore.swift`
- `Sources/AttoEditor/AttoSessionManager.swift`

### 顶层

```swift
struct AttoSessionSnapshot: Codable {
  var schemaVersion: Int  // e.g. 1
  var savedAt: Date
  var activeWindowIndex: Int?
  var windows: [AttoWindowSnapshot]
}
```

### Window

```swift
struct AttoWindowSnapshot: Codable {
  var workspaceRootPath: String
  var frame: AttoWindowFrameSnapshot?   // x/y/w/h（可选，失败则用默认 sizing）
  var sidebarCollapsed: Bool
  var selectedTabIndex: Int?
  var tabs: [AttoTabSnapshot]
  var recentFilePaths: [String]?
}
```

window frame 建议只存数字（避免依赖 `NSRect` 的 Codable 表现）：

```swift
struct AttoWindowFrameSnapshot: Codable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double
}
```

### Tab

```swift
struct AttoTabSnapshot: Codable {
  var filePath: String
  var isPreview: Bool
  var showsMinimap: Bool?
  var caret: AttoCaretSnapshot?
}

struct AttoCaretSnapshot: Codable {
  var line1: Int
  var column1: Int
}
```

注意点：

- `filePath` 一律存 **绝对路径**（恢复时再做 `standardizedFileURL`）。
- caret 采用 `(line1, column1)` 更稳定（文件内容变更时可做 clamp）；如果未来需要更精确可改用 `charOffset` 但要做上限保护。

---

## SessionStore（纯 I/O 层）

`AttoSessionStore` 只负责：

- 解析/生成 session 文件路径
- `load() -> AttoSessionSnapshot?`
- `save(snapshot:)`

要求：

- 允许注入 `FileManager` 与 base directory（便于测试用临时目录）。
- 读写不要阻塞主线程：I/O 在后台队列完成。
- 只在 main 线程采集 UI 状态；采集完成后把 snapshot 交给后台编码/写盘。

---

## SessionManager（与 AppDelegate/UI 集成）

### 恢复时机（建议规则）

在 `AttoAppDelegate.applicationDidFinishLaunching` 中：

1. 若当前 `windows` 已非空（说明可能已被 IPC spool request 提前创建窗口/打开文件），则跳过 restore。
2. 若 `createDefaultWindowOnLaunch == false`（internal server no-default-window），默认也跳过 restore（避免 CLI 拉起 server 时突然恢复一堆旧窗口）。未来可加开关控制。
3. 否则尝试 `store.load()`：
   - 成功：按 snapshot 创建窗口 + 打开 tabs + 选中 tab + focus active window
   - 失败：fallback 到现有逻辑（打开默认窗口）

可选：提供环境变量/偏好开关：

- `ATTOEDITOR_DISABLE_SESSION_RESTORE=1`：强制不 restore
- `ATTOEDITOR_DISABLE_SESSION_SAVE=1`：强制不写 session（便于排错）

### 保存时机（建议规则）

核心目标：**“频繁变动 → 防抖保存”**，避免每个事件都写盘。

实现方式：

- `AttoSessionManager.scheduleSave(reason:)`：触发一次 debounce（比如 1s）
- `AttoSessionManager.saveNow(reason:)`：在退出时同步采集 + 异步写盘（或在退出前等待写完）

建议挂钩点（Swift/UI 侧事件）：

- 窗口级：
  - 创建窗口 / 关闭窗口（`AttoAppDelegate.createWindow` / `AttoWindowContext.onWindowWillClose`）
  - window move/resize（`NSWindowDelegate.windowDidMove`/`windowDidResize`，在 `AttoWindowContext` 里实现后回调）
  - workspace root 变更（`AttoWindowContext.setWorkspaceRootURL`）
  - sidebar toggle（`AttoWindowContext.toggleSidebar` 或 `AttoAppDelegate.toggleSidebarMenuClicked`）
- tab 级：
  - open file / close tab / select tab（`AttoEditorAreaViewController` 内部）
  - minimap toggle（`toggleMinimapForActiveTab`）

为了避免 controller 之间强耦合，推荐加一个统一回调：

- 在 `AttoEditorAreaViewController` 增加：
  - `var onSessionStateChanged: (() -> Void)?`
  - 在 open/close/select/minimap 等关键路径调用一次（不带具体原因也可以）
- 在 `AttoWindowContext` 增加：
  - `var onSessionStateChanged: (() -> Void)?`
  - 在 workspaceRoot、sidebar、window move/resize 等路径调用
- `AttoAppDelegate` 在创建 `AttoWindowContext` 时统一把回调绑定到 `sessionManager.scheduleSave(...)`

### 采集（capture）与恢复（restore）接口

建议在 UI 组件上提供“面向 session 的最小 API”，避免 SessionManager 直接访问私有数组：

在 `AttoEditorAreaViewController` 增加：

- `func makeSessionSnapshot() -> AttoEditorAreaSnapshot`
  - 包含 tabs 顺序、selectedTabIndex、每 tab 的 filePath/isPreview/showsMinimap/caret
- `func restoreSession(_ snapshot: AttoEditorAreaSnapshot)`
  - 以“批量恢复模式”打开 tabs：
    - 先按 snapshot 顺序 `openFile(url:mode:)`
    - 最后再 select 指定 tab
    - caret/minimap 等在 tab 创建后再设置

在 `AttoWindowContext` 增加：

- `func makeSessionSnapshot() -> AttoWindowSnapshot`
- `func applySessionSnapshot(...)`（可选；也可由 AppDelegate 统一处理）

---

## 与现有默认启动逻辑的交互

当前 `applicationDidFinishLaunching` 会：

- 创建默认窗口（`defaultRepoRootURL()`）
- 打开一个 demo Rust 文件（仅在 `createDefaultWindowOnLaunch == true` 且存在时）

引入 session restore 后，建议调整为：

- 如果 restore 成功：**跳过默认窗口与 demo 文件**
- 如果 restore 失败：保持现有行为（但 `.app` 情况下 default root 已改为 Home）

---

## 测试计划（Swift 侧）

新增测试文件建议：

- `Tests/AttoEditorTests/AttoSessionStoreTests.swift`
  - JSON encode/decode roundtrip
  - schemaVersion 不匹配时的行为（返回 nil + rename corrupt）
  - 自定义 baseDir（临时目录）读写
- `Tests/AttoEditorTests/AttoSessionSnapshotMigrationTests.swift`（可选）

手动测试清单：

1. 启动 `.app` → 打开文件 A/B → 调整窗口大小 → 退出 → 再启动 `.app` 应恢复 A/B + frame。
2. 删除某个已记录文件 → 再启动应跳过该 tab（不 crash）。
3. CLI 场景：`AttoEditor <file>` 冷启动后只打开该文件，不额外恢复旧窗口（默认策略）。

---

## 实施步骤（建议拆分 PR / 里程碑）

### 里程碑 1：只恢复“窗口 + workspace root + tab 列表”

1. 引入 `AttoSessionSnapshot/AttoWindowSnapshot/AttoTabSnapshot`（schemaVersion=1）。
2. 实现 `AttoSessionStore`（路径、load/save、corrupt 处理）。
3. 在 `AttoAppDelegate.applicationDidFinishLaunching` 集成 restore：
   - 优先 restore
   - restore 成功则不创建默认窗口/不打开 demo
4. 在关键 UI 事件中挂钩 `scheduleSave`（open/close/select/tab、workspaceRoot、window close）。

### 里程碑 2：完善体验

1. 保存/恢复 window frame、sidebar collapsed、minimap。
2. 保存/恢复 primary caret（line/col）。
3. 增加 “disable restore/save” 环境变量开关。

### 里程碑 3（未来可选）

- 未保存 buffer 的 crash-safe 恢复（需要单独评估：体积、性能、隐私、清理策略）。

