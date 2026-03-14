# `tauri-editor`

基于 `editor-core` 的 **Tauri v2 + WebView（HTML/CSS/JS）** text-grid 渲染演示。

目标与设计原则请先读仓库根目录的 `tauri-editor.md`：
- 禁止 `contenteditable`
- 行级渲染（`<div class="row">` = gutter + `<div class="line">`，内容仍是 `<span>` runs）
- 从第一版开始支持 soft wrap（cells 坐标体系）
- viewport 虚拟化（composed rows：doc rows + above-line 虚拟行）
- 输入管线：`textarea#imeInput` 捕获 `beforeinput`（禁止 `contenteditable`）
- 剪贴板：Tauri 后端（`tauri-plugin-clipboard-manager`）

## 运行（本机）

该 crate 默认只包含纯 Rust 逻辑（方便 `cargo test`）。要运行 Tauri App 需要启用 feature：

```bash
cargo run -p tauri-editor --features tauri-app --bin tauri-editor -- path/to/file.rs
```

如果不传文件路径，会打开一个空文档。

### 为什么不需要 `devUrl`

`crates/tauri-editor/tauri.conf.json` **故意不设置** `build.devUrl`，这样 `cargo run`（debug）时
Tauri 会回退到 `tauri://localhost/index.html` 并直接加载 `ui/dist` 的静态资源，不需要额外起
前端 dev server。

## 目录结构

- `src/`
  - `backend.rs`：纯 Rust 的 `EditorBackend`（Workspace + 单 view），供 Tauri 命令层调用
  - `render_model.rs`：`ComposedGrid` → `ViewportSnapshot`（runs 压缩 + style-set interning + 每段携带 cells 宽度）
  - `composed_row_index.rs`：composed rows 总数与 doc↔composed 映射
  - `snapshot.rs`：Rust↔JS 传输结构（serde，runs 用 tuple 形式降低 JSON 开销）
- `src/bin/tauri-editor.rs`：Tauri v2 runnable binary（`tauri-app` feature）
- `ui/dist/`：无构建链的静态前端（`window.__TAURI__.core.invoke`）
- `tauri.conf.json`：Tauri 配置（`app.withGlobalTauri=true`，便于不用 npm 也能调用 `invoke`）

## 字体与宽字符（CJK/emoji）

该 demo 的坐标系以 **cells** 为核心（CJK 期望=2 cells）。不同平台的字体 fallback 可能导致
某些字符的实际像素宽度不等于 1/2 cells，从而出现 caret 落在 glyph 中间等错位问题。

当前实现会在前端对每个 run **按 cells 强制分配宽度**（并对宽字符 run 做边界切分），以保证
grid 对齐的可用性；若某些字体在 2 cells 宽度内绘制不下，可能会被裁剪。

建议：安装/选择“支持 CJK 的等宽字体”（例如 Sarasa Mono / Noto Sans Mono CJK 等），以获得更
理想的显示效果。

## 测试

```bash
cargo test -p tauri-editor
```

## 输入与快捷键（当前已支持）

- 如果启动后无法直接输入，先点击编辑区域让隐藏 `textarea#imeInput` 获取焦点（部分 WebView 会限制页面加载时的程序化 focus）。
- Debug 构建会尝试自动打开 Web Inspector（devtools），也可以按 `F12`、`Cmd+Opt+I`（macOS）或 `Ctrl/Cmd+Shift+I` 手动触发（macOS 仅 10.15+ 支持）。
- 如果按 `Cmd+Opt+I` 报 `webview.internal_toggle_devtools not allowed`，确认 `crates/tauri-editor/capabilities/default.json` 存在并包含 `core:default`（包含 `core:webview:allow-internal-toggle-devtools`）。
- 文字输入：`beforeinput: insertText`
- 删除：Backspace / Delete（`beforeinput: deleteContentBackward/Forward`；按 grapheme cluster 删除）
- 换行 / Tab：`beforeinput: insertLineBreak/insertTab`
- 选择：Shift+方向键、Shift+点击、鼠标拖拽选择
- 键盘导航：方向键/Home/End/PageUp/PageDown，移动/扩选后自动滚动保持光标可见
- 折叠：点击行号与正文之间的折叠 gutter（VS Code 风格 chevron；基于 `folding_manager.regions()`；Rust 优先来自 `editor-core-lsp`，无服务器则回退 `editor-core-treesitter`）
- IME：`compositionstart/update/end`（marked text 入内核；preedit 区域用 `IME_MARKED_TEXT` 下划线/背景渲染）
- 剪贴板：Copy/Cut/Paste（Ctrl/Cmd + C/X/V）
- Undo/Redo：Ctrl/Cmd + Z / Shift+Z（或 Ctrl+Y）
- 全选：Ctrl/Cmd + A

### 前端排查（无 Console 也能看）

前端提供一个左下角 `debugHud`（用于定位“输入事件/IPC 卡死”类问题），**默认关闭**。启用方式二选一：
- 运行时：`TAURI_EDITOR_DEBUG_HUD=1 cargo run -p tauri-editor --features tauri-app --bin tauri-editor -- <path>`
- 编译时：`cargo run -p tauri-editor --features tauri-app,debug-hud --bin tauri-editor -- <path>`

启用后显示：
- `focus=`：当前 `document.activeElement`
- `beforeinput=` / `input=`：是否观测到对应事件（用于判断 WebView 是否支持 `beforeinput`）
- `invoke=`：当前是否有后端命令调用卡住（例如 `insert_text 5000ms`）
- JS 异常会显示在 HUD，并通过 Tauri `frontend_log` 打到启动时的终端 stdout/stderr（即使 HUD 关闭也会打印 error 级别日志）
- minimap 刷新属于低优先级任务：走“后台 invoke（不阻塞编辑队列）+ idle debounce”，避免大文件时阻塞输入/点击。

## 语法高亮（当前已支持的最小集）

- JSON/INI：`editor-core-highlight-simple`（regex-based，style layer：`StyleLayerId::SIMPLE_SYNTAX`）
- Markdown：tauri-editor 内置的轻量 regex 高亮（标题/行内代码/link）
- Tree-sitter：`editor-core-treesitter`（Tree-sitter WASM + highlights/folds query，style layer：`StyleLayerId::TREE_SITTER`）
  - 默认会尝试读取 `../tree-sitter-grammars/treesitter/registry.json`（用于开发环境一次性启用多语言）。
  - 也可显式指定：`TAURI_EDITOR_TREESITTER_DIR=/path/to/treesitter`（该目录下需有 `registry.json`）。
  - 备注：并非所有语言包都提供 `folds.scm`；Rust 的 folds 在缺失时会使用内置回退 query。
- LSP：`editor-core-lsp`（若可启动语言服务器，例如 Rust 的 `rust-analyzer`；semantic tokens + diagnostics 等派生状态）

## Patch / 性能（当前实现）

- 行级 diff：viewport 更新时复用行 DOM，仅重建发生变化的行
- 合并 IPC：前端用 `get_frame` 一次拿到 `{ snapshot, cursor, selection }`
- 性能日志：`console.debug` 输出 frame/dom 耗时、行更新数量与输入延迟（约 1 次/秒）
- 右侧 UI：自绘滚动条（thumb 拖拽/点击）+ minimap（密度采样：按“非空白 cells / viewport_width”估算；用 bar 宽度表达密度避免“整块纯色”；点击/拖拽滚动定位）
