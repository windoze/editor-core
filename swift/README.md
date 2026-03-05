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

在仓库根目录：

```bash
MACOSX_DEPLOYMENT_TARGET=13.0 cargo build -p editor-core-ffi -p editor-core-ui-ffi
```

生成路径（macOS debug 默认）：

```text
target/debug/libeditor_core_ffi.a
target/debug/libeditor_core_ui_ffi.a
```

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
