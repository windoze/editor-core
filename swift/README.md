# EditorCoreFFI (Swift wrapper)

这是一个从零重写的 Swift 包装层，目标是用 **SwiftPM** 以最小表面积、可靠的方式调用本仓库的 Rust C ABI：`crates/editor-core-ffi`。

当前策略是 **运行时动态加载** `libeditor_core_ffi`（`dlopen` + `dlsym`），从而：

- Swift 包本身不需要在构建期链接 Rust 产物（避免 SwiftPM/Rust 混合构建的复杂性）。
- 你可以在 host app（AppKit、SwiftUI、CLI、服务进程）里自行决定 Rust dylib 的放置方式。

## 目录结构

- `Sources/EditorCoreFFI/`：核心封装（加载 dylib + `EditorState`/`Workspace` 包装 + viewport blob 解析）。
- `Sources/EditorCoreFFIDemo/`：最小 CLI demo（验证加载与基础编辑）。
- `Tests/EditorCoreFFITests/`：集成测试（会在仓库根目录执行 `cargo build -p editor-core-ffi`，然后加载生成的 dylib 进行验证）。

## 构建 Rust dylib

在仓库根目录：

```bash
cargo build -p editor-core-ffi
```

生成路径（macOS debug 默认）：

```text
target/debug/libeditor_core_ffi.dylib
```

## 运行 demo

```bash
cd swift
swift run EditorCoreFFIDemo
```

可选：通过环境变量指定 dylib：

```bash
EDITOR_CORE_FFI_DYLIB_PATH=../target/debug/libeditor_core_ffi.dylib \
swift run EditorCoreFFIDemo
```

## 运行测试

```bash
cd swift
swift test
```

如果你的环境没有 `cargo`，测试会自动 `skip`（只验证 Swift 侧可编译）。

