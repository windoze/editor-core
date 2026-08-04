# Core Workspace Ownership Audit

日期：2026-08-04

本文对应 `PLAN.md` 阶段 5 的首个任务：梳理 AttoEditor 仍保留的 Swift-only
tab、split、session、project 状态，并分类为 UI cache 或待迁移事实源。

## 判定规则

- `editor-core` / `editor-core-ui` / `MultiDocumentEditorUI` 应拥有 workspace、tab、split、session
  和 project 的事实源。
- Swift/AppKit 可以长期持有 NSView、NSWindow、panel/controller、callback、focus、hover、临时选择、
  以及无法序列化到 core 的平台表现缓存。
- 如果 Swift 字段会影响恢复、关闭保护、dirty 判断、tab 顺序、project root、recent、search scope
  或 LSP/project 计划，它不是单纯 UI cache，必须有 core snapshot/command/query 对齐路径。
- 迁移期可以保留 Swift fallback，但新增行为必须优先写入 core，并通过 Swift wrapper 与 AppKit 投影读取。

## 已有 Core-Owned 起点

`MultiDocumentEditorUI` 已经暴露以下 workspace 投影和命令：

- Snapshot：`activeTabId`、`workspaceRoots`、`recentFiles`、`recentProjects`、
  `projectLspServers`、`tabs`。
- Tab snapshot：`id`、`title`、`documentURI`、`languageId`、`isPreview`、`isActive`、
  `isModified`、`viewCount`、`activeViewIndex`。
- Tab/view commands：open preview/pinned tab、close tab、move tab、pin tab、split view、move view、
  close view、set active tab/view、set title、set document URI、set language id、replace tab text、
  query dirty/text.
- Project/session support：workspace roots, recent files/projects, workspace file list, project file index,
  project LSP server configs.

AttoEditor already consumes these in several places:

- `makeSessionSnapshot()` first attempts a core-projected session snapshot.
- `openFileItems()`, `openFileURLs()`, `refreshTabBar()` and close/move helpers prefer core projection when available.
- split pane focus/move/close and tab move call core commands before updating the AppKit projection.
- dirty state combines core `isModified` with the local editor view state.
- recent files/projects and project file index use core when the runtime feature is present, with Swift fallback.

## Swift State Inventory

| Area | Swift state | Current role | Classification | Target owner |
| --- | --- | --- | --- | --- |
| Tab collection | `AttoEditorAreaViewController.tabs`, `selectedTabID` | AppKit tab objects plus order/selection fallback | Mixed | Core owns order and active tab; Swift keeps `coreTabID -> AttoEditorTab` projection cache |
| Tab identity | `AttoEditorTab.id`, `coreTabID` | AppKit identity and core routing handle | UI/projection cache | Swift keeps UUID for AppKit controls; core `tabId` remains fact handle |
| Document identity | `AttoEditorTab.fileURL`, `isUntitled` | File path, untitled save target and restore behavior | 待迁移事实源 | Core should own document URI/save target/untitled metadata; Swift only presents save panel |
| Preview/pin | `AttoEditorTab.isPreview` | Local fallback for preview replacement and tab display | Transitional fact cache | Core `isPreview`; Swift writes through `pinTab`/open-preview commands |
| Dirty | `AttoEditorTab.isDirty` | Local fallback combined with core `isModified` | Transitional fact cache | Core dirty/saved snapshot, with Swift only caching current view repaint state |
| Split panes | `AttoEditorTab.panes`, `activePaneIndex` | Holds `EditCoreUI` NSViews and mirrors core view count/order/active index | Mixed | Swift keeps view instances; core owns pane count/order/active view |
| Minimap | `EditCoreUI.showsMinimap`, `AttoTabSnapshot.showsMinimap` | Per-tab visual preference | UI/session cache | Swift/AppKit, unless core later owns editor view preferences |
| Language metadata | `syntaxLanguageId`, `languageSupportSource` | Drives syntax config and syncs core `languageId` | Mixed | Core owns normalized language id; Swift may cache detection source for UI |
| Project LSP tab metadata | `lspServerConfig`, `suppressesAutomaticLspStart` | Feeds project LSP server config/plan | 待迁移事实源 | Stage 6 core project/LSP lifecycle schema |
| Semantic token cache | `semanticTokensResultId`, `semanticTokensData` | Rendering/application cache for active editor state | UI/derived-state cache | Swift cache until semantic token storage is fully core-derived |
| Workspace root | `AttoWindowContext.workspaceRootURL`, `AttoEditorAreaViewController.workspaceRootURL` | App window root plus sync source for core workspace roots | Transitional fact cache | Core `workspaceRoots`; Swift window stores current projection/root picker state |
| Recent files | `AttoWindowContext.recentFiles` | Fallback MRU list | Transitional fact cache | Core `recentFiles`; Swift fallback removable after runtime baseline moves |
| Recent projects | session snapshot `recentProjectURIs` | Restores core recent projects | Core-backed persisted input | Core `recentProjects`; session stores serialized projection only |
| Project file index | `AttoWorkspaceFileIndex fileIndex` | Local fallback for file explorer/quick open | Transitional fallback | Core project file index/workspace file list |
| Session snapshot | `AttoSessionSnapshot`, `AttoWindowSnapshot`, `AttoTabSnapshot` | Disk persistence for window chrome, tabs, panes and unsaved text | Mixed | Swift persists window/sidebar/UI prefs; core owns tab/session facts and restore commands |
| Sidebar/window chrome | `sidebarSplitItem`, window frame, sidebar tab selection | Pure AppKit presentation | UI cache | Swift/AppKit |
| Panels and callbacks | result panels, preview/history panels, decision providers | Presentation and test seams | UI cache | Swift/AppKit |

## Migration Boundaries

### Keep in Swift/AppKit

- NSWindow, NSSplitViewController, NSView subclasses, panel controllers and command palette controllers.
- Focus, hover, transient status text, test decision providers and short-lived request contexts.
- Per-view visual preferences that do not change workspace semantics, such as minimap visibility and sidebar collapse.
- Derived rendering caches that can be rebuilt from core/editor snapshots.

### Move or Finish Moving to Core

- Tab order, active tab, close groups, preview replacement, pinning and selection.
- Pane count/order/active view, including drag/drop and move across panes.
- Document identity, untitled buffers, save target, dirty/saved state and reload/discard protection.
- Session restore semantics for tabs, panes, selected tab and unsaved buffers.
- Workspace root changes, recent files/projects and project file index ownership.
- Project-level LSP launch metadata and lifecycle ownership. The audit records the dependency here, but the
  implementation belongs to stages 5 and 6 according to `PLAN.md`.

## Next Stage 5 Tasks

1. Convert higher-level tab commands to core-first command/query paths:
   close active/all/other/right, select, pin preview, preview replacement and session restore.
2. Add consistency tests for each migrated command that assert:
   core snapshot, Swift wrapper query and AppKit projection.
3. Make drag/drop and split movement fail closed when the core command rejects the operation.
4. Continue dirty/save/reload/recent/root migration so data-loss decisions read a single core-backed state.
5. Keep Swift fallback paths only where runtime compatibility still requires them, and document each fallback.
