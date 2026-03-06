# UI 性能计划（editor-core + Skia/AppKit）

本文聚焦“自绘 UI（Skia）+ 原生桥接（AppKit/Swift）”路线下的 **输入延迟** 与 **CPU 占用** 问题，目标是在 **不牺牲正确性** 的前提下，把“打字/IME/撤销”等交互保持在主线程近乎常量时间，并把高开销的派生计算（Tree-sitter/Sublime/LSP 等）移动到后台或做节流。

> 结论先行：**需要把 Tree-sitter（以及其它派生处理）从主线程同步 refresh 中剥离**，改成后台异步处理 + 主线程 non-blocking poll 应用结果。

---

## 0. 目标与非目标

### 目标（必须达成）

- **输入不阻塞**：`insertText` / `setMarkedText` / `doCommand` 不应因为 Tree-sitter/高亮/折叠刷新而卡顿。
- **结果最终一致**：后台处理的高亮/折叠最终会应用到 editor-core 的派生状态（style layers / folding regions）。
- **可观测、可回归**：提供调试开关与测试用例，能稳定复现/定位性能回退。
- **macOS 先行**：先把 Rust + AppKit/Swift 这条链路做稳定，Windows/Linux 留到后续阶段。

### 非目标（后续阶段再做）

- 不在本阶段做“所有语言自动选择 grammar”的完整语言系统（先以 demo 里 Rust 为主）。
- 不在本阶段做“可视区增量高亮缓存”（Tree-sitter query byte-range 优化属于后续）。
- 不在本阶段追求“帧级预算调度器 + 多 worker 并行”；先把主线程从重活里解放出来。

---

## 1. 现状与根因（基线）

### 已知现象

- Metal 渲染耗时很低（`renderMetal` 平均约 0.3–1.5ms），但输入时 `insertText` 可飙到 100ms+。
- 关闭 Tree-sitter 后 `insertText` 立即恢复到 ~0.04ms 级别，说明主要瓶颈在 **Tree-sitter 同步处理**。
- 当文本与语言 grammar 不匹配、或错误恢复路径复杂时，Tree-sitter 可能进入 worst-case，导致 parse/query 变慢；若此时在每次 edit 后同步刷新，会直接卡住主线程。

### 根因（要解决的点）

当前 `crates/editor-core-ui` 在“文本变更路径”里调用 `refresh_processing()`：

- `EditorStateManager::apply_processor(TreeSitterProcessor)` 会同步 parse + query；
- 输入事件来自 Swift 主线程，因此主线程被阻塞 → 卡顿/CPU 飙高。

---

## 2. 总体方案（分层 + 线程模型）

### 2.1 Rust 侧：派生处理异步化

在 `editor-core-ui` 内新增一个“派生处理 worker”：

- worker 线程 **持有 Tree-sitter processor**（以及其内部 parser/tree/text 缓存）。
- 主线程只做：
  - 执行编辑命令（修改文本/光标/选择）
  - 提取 `TextDelta`（若有）并发送到 worker
  - 在合适时机 non-blocking poll worker 结果并 **应用 `ProcessingEdit`** 到 `EditorStateManager`

关键设计点：

- **版本号 gating**：worker 结果携带 `doc_version`，主线程只应用最新版本的结果，丢弃过期结果（避免闪烁/回退）。
- **批处理/合并**：worker drain 队列，把多次输入的 delta 合并成“一次 parse + 一次 query”。
- **fallback**：如发生 delta mismatch（极少见/bug/跨线程丢消息），要求一次 full sync（发送全文）后继续增量。

### 2.2 FFI 侧：显式 poll API

UI 组件是事件驱动绘制（on-demand），因此后台处理完成后需要让 host 有机会“拉取并触发重绘”：

- 在 `editor-core-ui-ffi` 增加 `editor_ui_poll_processing(...)`：
  - non-blocking：不会等待 worker
  - 返回：
    - `applied`：本次是否应用了新结果
    - `pending`：当前是否仍有未完成的后台处理

### 2.3 Swift/AppKit 侧：定时 poll + 触发 redraw

在 `EditorCoreSkiaView` 中：

- 每次“文本变更输入”后（`insertText` / `setMarkedText` commit / undo/redo / paste 等），启动一个短生命周期的 poll timer：
  - 每 8–16ms poll 一次（或 30–60Hz），直到 `pending == false`
  - 若 `applied == true`：
    - `requestRedraw()`
    - `invalidateIMECharacterCoordinates()`（候选窗定位可能依赖 caret）
    - `onViewportStateDidChange?()`（折叠变化可能影响总行数/滚动条）

这样即使用户停止输入，后台高亮/折叠完成后也会自动呈现。

---

## 3. 具体步骤（对应提交粒度）

> 约定：每个步骤完成后 **单独 commit**，并补齐测试。

### Step 1：落地本文档

- 新增 `ui-performance.md`（本文件）。

### Step 2：Rust（editor-core-treesitter）支持“无 EditorStateManager 的增量处理”

目的：让 Tree-sitter 能在 worker 线程运行，而不依赖 `EditorStateManager` 引用。

- 在 `TreeSitterProcessor` 中抽取/新增：
  - `sync_from_text_full(text: &str)`
  - `process_text(version, delta_opt, full_text_opt)`（或等价 API）
- `DocumentProcessor::process(&EditorStateManager)` 改为调用新 API（不改变现有行为）。
- 增加 Rust 单元测试覆盖：
  - 初次 full parse
  - 增量 delta 更新
  - delta mismatch 的错误路径（或 full sync fallback）

### Step 3：Rust（editor-core-ui）引入 Tree-sitter 异步 worker + poll

- 新增 `TreeSitterAsyncWorker`（线程 + channel + drop join）。
- `set_treesitter_*`：
  - 初始化 capture→StyleId 映射（仍在主线程）
  - 启动 worker，并发送 initial full sync（text + version）
- 文本变更路径：
  - 保持 Sublime 同步刷新（先不动）
  - Tree-sitter 改为 `schedule_async_processing_from_last_delta()`，不再同步 parse/query
- `poll_async_processing()`：
  - non-blocking drain receiver
  - 版本号 gating
  - 应用 `ProcessingEdit` 到 `EditorStateManager`
- Rust 测试覆盖：
  - 启用 treesitter 后，poll 直到出现高亮/折叠
  - 连续两次 edit：只应用最新结果
  - update mode（initial/incremental）可观测（用于回归）

### Step 4：FFI（editor-core-ui-ffi）暴露 poll API

- 增加 `editor_core_ui_ffi_editor_ui_poll_processing(EditorUi*, uint8_t* out_applied, uint8_t* out_pending)`。
- 更新 `crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h`。
- Rust FFI 层增加最小覆盖测试（可选）或由 Swift 测试覆盖。

### Step 5：Swift/AppKit 接入异步 poll（并补 Swift 测试）

- `swift/Sources/EditorCoreUIFFI/EditorUI.swift` 增加 `pollProcessing()`。
- `swift/Sources/EditorCoreAppKit/EditorCoreSkiaView.swift`：
  - 编辑输入后启动 poll timer
  - poll 有更新就触发 redraw + IME coordinate invalidate
- Swift 测试：
  - `EditorCoreUIFFITests`：启用 treesitter 后，poll 直到 fold marker 可渲染
  - `EditorCoreAppKitTests`：验证 poll 导致 redraw 请求（可用 hook/计数器方式）

---

## 4. 后续优化方向（不在本阶段强制实现）

- **Debounce**：worker 在收到输入 burst 时，延迟 30–80ms 再 parse，减少重复工作。
- **优先级/QoS**：macOS 上可通过 `pthread_set_qos_class_self_np` 或 GCD 绑定到 `utility`/`background`。
- **可视区 query**：用 Tree-sitter `QueryCursor::set_byte_range` 对 visible/prefetch 范围做增量高亮（需要引入区间缓存策略）。
- **超时/预算**：单次处理超过阈值时跳过本轮或降级（例如仅折叠、仅可视区、或临时禁用）。

