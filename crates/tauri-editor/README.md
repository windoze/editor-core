# `tauri-editor`

基于 `editor-core` 的 **Tauri v2 + WebView（HTML/CSS/JS）** text-grid 渲染演示。

目标与设计原则请先读仓库根目录的 `tauri-editor.md`：
- 禁止 `contenteditable`
- 行级渲染（`<div class="line">` + `<span>` runs）
- 从第一版开始支持 soft wrap（cells 坐标体系）
- viewport 虚拟化（composed rows：doc rows + above-line 虚拟行）

## 运行（本机）

该 crate 默认只包含纯 Rust 逻辑（方便 `cargo test`）。要运行 Tauri App 需要启用 feature：

```bash
cargo run -p tauri-editor --features tauri-app --bin tauri-editor -- path/to/file.rs
```

如果不传文件路径，会打开一个空文档。

## 目录结构

- `src/`
  - `backend.rs`：纯 Rust 的 `EditorBackend`（Workspace + 单 view），供 Tauri 命令层调用
  - `render_model.rs`：`ComposedGrid` → `ViewportSnapshot`（runs 压缩 + style-set interning）
  - `composed_row_index.rs`：composed rows 总数与 doc↔composed 映射
  - `snapshot.rs`：Rust↔JS 传输结构（serde，runs 用 tuple 形式降低 JSON 开销）
- `src/bin/tauri-editor.rs`：Tauri v2 runnable binary（`tauri-app` feature）
- `ui/dist/`：无构建链的静态前端（`window.__TAURI__.core.invoke`）
- `tauri.conf.json`：Tauri 配置（`app.withGlobalTauri=true`，便于不用 npm 也能调用 `invoke`）

## 测试

```bash
cargo test -p tauri-editor
```

