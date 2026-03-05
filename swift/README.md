# EditorCoreFFI (Swift wrapper)

这是一个从零重写的 Swift 包装层，目标是用 **SwiftPM** 以最小表面积、可靠的方式调用本仓库的 Rust C ABI：`crates/editor-core-ffi`。

当前策略是 **静态链接** Rust `staticlib` 到 Swift 可执行文件/测试里（不再 `dlopen/dlsym`）。

这带来的变化：

- 运行时不再依赖 `libeditor_core_ffi.dylib` / `libeditor_core_ui_ffi.dylib` 的查找路径；
- 需要在构建 SwiftPM 包之前，先用 Cargo 生成对应的 `.a` 产物（或在 CI 里缓存它们）。

## 目录结构

- `Sources/CEditorCoreFFI/`：C header module（转发到 `crates/editor-core-ffi/include/editor_core_ffi.h`）
- `Sources/CEditorCoreUIFFI/`：C header module（转发到 `crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h`）
- `Sources/EditorCoreFFI/`：Swift 封装（`EditorState`/`Workspace` 包装 + viewport blob 解析）。
- `Sources/EditorCoreFFIDemo/`：最小 CLI demo（验证加载与基础编辑）。
- `Sources/EditorCoreAppKit/`：AppKit 组件（自绘 + IME + 事件映射）。
- `Sources/EditorCoreSkiaAppKitDemo/`：自绘 demo（Skia renderer）。
- `Tests/EditorCoreFFITests/`：Swift 侧集成测试。
- `Tests/EditorCoreAppKitTests/`：AppKit 组件测试。

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
swift run EditorCoreSkiaAppKitDemo
```

## 运行测试

```bash
cd swift
swift test
```
