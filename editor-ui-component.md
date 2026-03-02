# editor-ui component（方案与计划）

本文是“走 Option 2（自绘 + 自己处理输入）”的落地计划，但会拆成两层：

1. **Rust 渲染层**：用 **Skia** 在 Rust 里把 editor-core 的 viewport / 样式 / 装饰等渲染成像素（或 GPU surface）。
2. **平台桥接层**：用各平台的原生语言/框架（Win/Mac/Linux）把渲染层接入 OS 组件体系，负责窗口/控件生命周期、事件分发、输入法/剪贴板等平台细节。

> 目标是：让 `editor-core` 仍保持 UI-agnostic，同时提供一个可跨平台复用的高性能 UI 渲染内核。

---

## 0. 设计目标（明确边界）

### Goals

- **单一真值**：文本与选择等编辑状态由 `editor-core` 管理；渲染层只消费快照并绘制。
- **跨平台一致性**：同一份编辑/渲染内核，平台差异只在桥接层。
- **可渐进实现**：先 CPU raster（RGBA buffer）跑通，再做 GPU（Metal/D3D/Vulkan/GL）加速。
- **可测试**：Rust 侧可做 golden image；桥接层可做冒烟测试与手动 demo。
- **ABI 可演进**：延续 `docs/abi-v1-draft.md` 的原则，尽量避免每帧 JSON。

### Non-Goals（第一阶段不做）

- 不追求一次性做完完整 IDE UI（tab、project tree、minimap 等）。
- 不在 v0 就支持“所有字体/复杂排版”；先确保**等宽字体 + 代码编辑器核心体验**。
- 不强行复刻 TextKit；我们走“编辑内核在 Rust，自绘渲染”的路线。

---

## 1. 分层架构（建议）

### 1.1 模块分层图

```
           ┌──────────────────────────────────────────┐
           │         平台桥接层（原生语言/框架）        │
           │  macOS: AppKit/Swift   Windows: WinUI/C#  │
Input/IME  │  Linux: GTK/Qt/C++                          │  Window/View 生命周期
  Events ─▶│  - 事件收集/转换                             │  - 计时器/DisplayLink
           │  - 平台输入法/剪贴板/辅助功能                 │  - Surface 创建与呈现
           └───────────────┬───────────────────────────┘
                           │ C ABI / FFI
                           ▼
           ┌──────────────────────────────────────────┐
           │     Rust 层：Editor + Renderer（核心）      │
           │  - editor-core（状态/命令/布局/viewport）     │
           │  - editor-render-skia（Skia 绘制）           │
           │  - editor-ui-ffi（稳定 ABI：输入/渲染）       │
           └──────────────────────────────────────────┘
```

### 1.2 推荐 crate 划分（Rust）

- `crates/editor-core/`（已有）：编辑状态/命令/布局与 viewport 快照。
- `crates/editor-core-render-skia/`（新增）：把 viewport + overlay（selection/caret/diagnostics）渲染成像素或 GPU surface。
- `crates/editor-core-ui/`（新增，建议）：组合层，持有 `EditorStateManager/Workspace + Renderer`，提供面向 UI 的“一个句柄”。
- `crates/editor-core-ui-ffi/`（新增）：对外 C ABI（给 Swift/C#/C++/…）。

> 为什么建议加 `editor-core-ui`：平台桥接层不应同时管理多个 Rust handle（editor + renderer + processor），否则跨语言生命周期复杂且容易踩坑。

---

## 2. 数据与 API 约定（先定清楚，再写代码）

### 2.1 渲染输入（Render Snapshot）

渲染层不应每次都问 editor-core 取一堆零碎状态；建议一个“快照式输入”：

- **viewport 文本/样式**：优先使用二进制 viewport blob（已有方向：`docs/abi-v1-draft.md` 的 blob 结构）。
- **光标/选择**：需要从 editor-core 暴露（如果现有 FFI 不足，需要补）：
  - 主光标（caret）在视觉坐标/逻辑坐标/char offset 的一种统一表示
  - 多选区（未来）：range 列表 + 方向
- **滚动/可见区域**：起始 visual row、row_count、水平滚动（如果有）。
- **主题（Theme）**：`StyleId -> 具体颜色/字体样式` 的映射
  - v0 先做：前景/背景/selection/caret
  - v1 再加：下划线、波浪线、诊断色、gutter、行高、indent guide 等
- **装饰层（可选）**：diagnostics、decorations、fold regions（未来按需接入）

### 2.2 渲染输出（两个后端路线）

**MVP（强烈建议先做）**：CPU raster → RGBA buffer

- Rust：`render_into_rgba(out_ptr, bytes_per_row, width_px, height_px, scale)`  
- Host：把 buffer 贴到 OS bitmap（mac: `CGImage`；win: `WriteableBitmap`；linux: `QImage`/`cairo_image_surface_t`）

**后续升级**：GPU surface（平台相关）

- macOS：Metal（`CAMetalLayer` / `MTKView`）
- Windows：D3D11/12 或 Vulkan
- Linux：Vulkan/GL

> 计划上：先 CPU 路线保证功能正确与输入完整，再做 GPU，否则调试成本会指数级上升。

### 2.3 输入事件（Event Contract）

建议把“编辑行为映射”（按键 → command）尽量放在 Rust，平台桥接只负责把原始事件传进来：

- 键盘：key code + modifiers + repeat + text（如有）
- 文本输入（commit）：UTF-8 string
- 组合输入（IME / marked text）：marked string + selection range（v1 必须做）
- 鼠标：down/up/move/drag + 坐标 + click count
- 滚轮：deltaX/deltaY + phase

---

## 3. 分阶段计划（Step-by-step）

下面按“可交付里程碑”拆解；每一步都尽量做到**可运行/可验证**。

### 阶段 A：MVP0（CPU 渲染跑通 + 基本输入）

#### A1. Rust：新增渲染与 UI 组合 crate（脚手架）

1. 新增 `crates/editor-core-render-skia/`（依赖 `skia-safe`）：
   - 先锁定支持平台：macOS（优先），Windows/Linux 后续加 feature
   - 选择 Skia build 策略：源码编译（默认）或预编译缓存（CI 需要）
2. 新增 `crates/editor-core-ui/`：
   - 定义 `EditorUi`（或 `EditorView`）结构：持有 `EditorStateManager`（先单 buffer 单 view）
   - 统一对外接口：`set_viewport_size / handle_event / render`
3. 新增 `crates/editor-core-ui-ffi/`：
   - 导出 `extern "C"`：create/free、render、handle_input、last_error
   - 头文件 `include/editor_core_ui_ffi.h`
   - 错误与内存规则沿用 `docs/abi-v1-draft.md`

#### A2. Rust：最小渲染能力（只画得出来）

4. 确定“渲染基线”：
   - 等宽字体（monospace）
   - 固定行高（先用 font metrics 推导，或配置常量）
   - 只画可见 viewport（start_row + row_count）
5. 实现 `render_into_rgba`（CPU Surface）：
   - 清背景
   - 绘制每行文本（按 cell 网格推进 x）
   - 绘制 caret（竖线）
   - 绘制 selection（矩形背景）
6. 定义 Theme（v0）：
   - `bg`, `fg`, `selection_bg`, `caret_fg`
   - `StyleId -> fg/bg` 先允许“不处理”（全部用默认），后面再接样式层

#### A3. Rust：最小输入（只要能编辑）

7. 在 `EditorUi` 内实现事件到命令的最小映射：
   - `insertText(commit)` → `edit/insert_text`
   - backspace/delete/enter/tab
   - arrow keys / home/end / page up/down（先做基础）
   - 复制/剪切/粘贴：v0 可先交给 host 处理剪贴板，再调用 commit/replace
8. 光标/选择状态的暴露：
   - 如果现有 editor-core API/FFI 没有“获取 selection/caret”的接口，需要补：
     - 最小：主光标 char offset + selection range
     - 最终：多 selection + 方向 + 视觉坐标

#### A4. Rust：测试（先能防回归）

9. Golden image（建议最少 3 组）：
   - 纯 ASCII
   - 含 CJK/emoji（验证宽度）
   - 含 selection/caret
10. 行为测试（不依赖 UI）：
   - 给定输入事件序列 → 最终文本 + caret 位置一致

交付物（A 阶段结束时你应该得到）：

- `editor-core-ui-ffi` 能创建实例并渲染出非空 RGBA buffer
- 支持输入/删除/方向键，文本在 UI 中可见且可编辑

---

### 阶段 B：平台桥接 MVP（macOS 优先，其它平台按同套路）

> 桥接层的目标：把 Rust 输出的 RGBA buffer 贴到屏幕上，并把 OS 事件喂回 Rust。

#### B1. macOS（Swift / AppKit）

1. 新增 `swift` 侧 target（建议新建，不与现有 NSTextView 版混在一起）：
   - `EditorCoreSkiaFFI`：加载 `libeditor_core_ui_ffi`（同样用 dlopen/dlsym）
   - `EditorCoreSkiaAppKit`：`NSView` 子类（例如 `EditorCoreSkiaView`）
2. `EditorCoreSkiaView` MVP 渲染：
   - `viewDidMoveToWindow` / `layout()`：把 size/scale 通知 Rust（`set_viewport_size`）
   - 使用 `CADisplayLink` 或简单 `needsDisplay = true` 驱动刷新
   - `draw(_:)`：
     - 向 Rust 请求渲染到复用的 `malloc` buffer
     - 用 `CGImage` 包装 RGBA，绘制到 `CGContext`
3. 输入 MVP：
   - `keyDown`：对普通键（backspace/arrow）直接传 key event
   - 文本输入：实现 `NSTextInputClient`（建议尽早做，否则中文输入会成为大坑）
     - `insertText(_:)` → commit
     - `setMarkedText(...) / unmarkText()` → composition（先最小可用：只显示下划线+替换范围）
4. 鼠标与滚动：
   - `mouseDown/mouseDragged/mouseUp`：点击定位 caret、拖拽 selection
   - `scrollWheel`：滚动（纵向为主）
5. Demo：
   - `EditorCoreSkiaAppKitDemo`：一个窗口 + view + 打印 FPS（可选）

#### B2. Windows（建议 C# / WinUI 3 或 WPF）

6. 选择一个 UI 框架并固定（建议 WinUI 3 优先；WPF 作为备选）
7. MVP 渲染：
   - `WriteableBitmap`（BGRA）承载像素 buffer
   - 每帧从 Rust 拿 buffer，拷贝到 bitmap，再呈现
8. 输入：
   - key events + text input（注意 IME：Win 的输入法接入机制不同，早期可以先保证 commit 文本可用）
9. Demo：最小窗口控件

#### B3. Linux（建议 C++ / GTK4 或 Qt6）

10. 选择一个 UI 框架并固定（GTK4 或 Qt6 二选一）
11. MVP 渲染：
   - GTK：`GtkDrawingArea` + `cairo_image_surface_t`
   - Qt：`QWidget::paintEvent` + `QImage`
12. 输入：key + text commit + mouse + scroll
13. Demo：最小窗口控件

交付物（B 阶段结束）：

- macOS 上有一个可编辑、可选中、可滚动的自绘 Skia 编辑器控件
- Windows/Linux 至少各有一个“能显示 + 能输入”的 demo（即使 IME 还没完全对齐）

---

### 阶段 C：对齐 editor-core 的“编辑器特性”（逐步扩展）

#### C1. 样式层与高亮（Sublime / Tree-sitter / LSP）

1. 把 `StyleId` 体系接入 Theme：
   - Theme JSON（或二进制）从 host 下发：`style_id -> {fg,bg,fontStyle}`  
2. 支持多层 style（editor-core 的 cell 可带多个 style id）：
   - v1：简单合成（后来的覆盖前的，或按层级规则）
3. 接入 processors：
   - Sublime：语法高亮 + 折叠（fold placeholders）
   - Tree-sitter：高亮 + 折叠
   - LSP：diagnostics + semantic tokens
4. Overlay 渲染：
   - diagnostics 波浪线/下划线
   - decorations（如 trailing whitespace、search match）

#### C2. 选择/多光标/矩形选择

5. 完整暴露并渲染多 selection
6. 鼠标拖拽、多击（双击选词、三击选行）
7. Shift + 方向键扩展选区

#### C3. 折叠（Folding）

8. 渲染 fold placeholder（例如 `…`）
9. gutter 上显示折叠标记，点击折叠/展开

---

### 阶段 D：性能与 GPU（可选但推荐）

#### D1. 性能基线（CPU 路线先优化到可用）

1. 避免每帧分配：
   - buffer 由 host 预分配并复用
   - Rust 侧复用 `Surface`/`Canvas`
2. 文本绘制缓存：
   - 每行缓存 `TextBlob`（或 glyph run）  
   - 文本改变时仅重建受影响行
3. 增量重绘：
   - editor-core 暴露 dirty ranges（或 UI 自己比较版本号/行变更）

#### D2. GPU 后端（按平台逐个做）

4. macOS：Metal 后端
   - 由桥接层创建 `CAMetalLayer/MTKView`（更符合 AppKit）
   - Rust 侧用 Skia Metal backend 在 layer surface 上直接 draw
5. Windows：D3D11/12（或 Vulkan）
6. Linux：Vulkan/GL

> GPU 路线的关键在于“跨语言传递 backend context 的句柄与生命周期管理”，这部分建议在 `editor-core-ui-ffi` 明确规则（retain/release / ref-count / thread owner）。

---

## 4. 风险清单（提前规避）

- **Skia 构建与 CI 成本**：编译时间长、平台差异大；需要缓存策略或预编译方案。
- **字体与宽度一致性**：editor-core 的 cell width（1/2）必须和渲染字体度量一致；v0 固定等宽字体可大幅降低风险。
- **IME（输入法）**：必须尽早设计 composition API，否则后期返工会很痛。
- **ABI 稳定性**：渲染与事件是高频路径，避免 JSON；必须有清晰的 out-buffer 规则。
- **线程与重入**：UI 线程与 Rust handle 的所有权要严格；避免并发修改同一个 editor 实例。

---

## 5. 建议的“第一周”落地顺序（最少路径）

1. Rust：先做 `editor-core-ui-ffi` + CPU `render_into_rgba`（能画出文本和 caret）
2. macOS：做 `EditorCoreSkiaView`（draw 到 `CGContext`）+ `insertText` commit（先不做 composition）
3. 再回 Rust：补 selection/caret 的完整对齐与鼠标点击定位
4. 再回 macOS：实现 `NSTextInputClient` 的 marked text（把中文输入做对）
5. 然后开始接样式层（先 Sublime 或 Tree-sitter 二选一）

