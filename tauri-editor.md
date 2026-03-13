# Tauri/HTML 渲染实现计划（Text-Grid / 非富文本）

本文档是一个“从可运行开始、逐步增强”的实现计划：用 **Tauri + WebView（HTML/CSS/JS/TS）** 来渲染 `editor-core` 的文本视图。核心原则是把编辑器当作 **文本网格（text-grid）** 而不是富文本：前端只做高性能显示与输入采集；状态与命令主要在 Rust 侧。

---

## 0. 当前 `editor-core*` 能力核对（基于仓库现状）

这一节用于“对齐现实”：确认 `editor-core` 已经提供哪些 headless 能力，我们的 Tauri/HTML 方案应尽量**复用内核已有语义与数据结构**，避免重复造轮子或引入不一致。

### 0.1 `editor-core`（内核）已具备的关键能力
- **坐标体系与转换齐全**（字符偏移/逻辑行列/可视行列）：
  - API 以 **Unicode scalar（Rust `char`）索引**为主（非 byte offset）。
  - 支持 soft wrap + folding 下的 **logical ⇄ visual** 转换，并用 **cells（列宽）**表达视觉 `x`。
- **headless snapshot（文本栅格）输出**：
  - `HeadlessGrid / HeadlessLine / Cell`：可视行序列，每个 cell 带 `ch + width + styles`，并包含 `char_offset_start/end`、wrap 段信息等（可直接驱动 DOM 行渲染）。
  - `ComposedGrid / ComposedLine / ComposedCell`：装饰感知（可包含 inlay hints / code lens 等虚拟文本），并标注 cell 来源（Document / Virtual）。
- **viewport 状态与虚拟化辅助**：
  - `WorkspaceViewportState` 提供 `visible_lines / total_visual_lines / prefetch_lines / smooth_scroll` 等字段，适合 wrap+fold 的 **文档 visual rows** 虚拟化。
  - 但注意：`ComposedGrid` 可能包含 `AboveLine` 的“虚拟行”（类似 Monaco view zones / code lens），这会让 **composed visual rows** 的 `total_rows/scrollHeight` 不再等于 `WorkspaceViewportState.total_visual_lines`；本计划采用 `ComposedViewportState + ComposedRowIndex` 的方式处理（见 6.4.1、6.4.2）。
- **样式/折叠/派生状态模型完善**：
  - `ProcessingEdit` 支持 `StyleLayerId` 分层替换/清除、折叠 regions、diagnostics、decorations、symbols 等。
  - 内置 `StyleId` 常量包含 `IME_MARKED_TEXT_STYLE_ID`、`INLAY_HINT_STYLE_ID`、`CODE_LENS_STYLE_ID` 等，方便渲染层做一致映射。
- **IME 相关编辑语义已内置**（对 WebView 很重要）：
  - `EditCommand::ReplaceCoalescingUndo{,_WithSelection}` + `EditCommand::EndUndoGroup` 明确支持“composition 更新要合并为一个 undo step”的语义。

### 0.2 `Workspace` 已经提供我们需要的“宿主边界”
`Workspace` 是更贴近真实编辑器（多 buffer / 多 view / split）的集成边界，并且已经直接提供：
- `get_viewport_content_styled(view, start_visual_row, count) -> HeadlessGrid`（按**文档 visual row**）
- `get_viewport_content_composed(view, start_visual_row, count) -> ComposedGrid`（按**composed visual row**，可能包含 `AboveLine` 虚拟行）
- `logical_position_to_visual_for_view(view, line, col) -> (row, x_cells)`（wrap/fold aware）
- `visual_position_to_logical_for_view(view, row, x_cells) -> Option<Position>`

因此：Tauri 后端建议以 `Workspace` 作为核心对象（哪怕 MVP 只有一个 view），避免后期从单文档模型迁移到多文档时大改。

### 0.3 可参考但不作为依赖的 crate（按你的范围说明）
- `editor-core-render-skia` / `editor-core-ui`：Skia 渲染与 Rust UI 组合层，**不纳入本计划的实现范围**；但其中的 IME/撤销分组/marked text 处理逻辑对 WebView 方案非常有参考价值。
- `*-ffi`：Swift/原生桥接相关，当前 Tauri/HTML 计划默认不依赖。
- `editor-core-app`：提供“应用壳”逻辑（保存流程、workspace file index、sessions/recents 等），对“尽早可运行的 App”非常适配；可按需复用。

---

## 1. 目标与硬约束

### 1.1 必须满足的关键点（来自需求）
- **禁止使用 `contenteditable`**：不把 DOM 当成真实文档，不依赖浏览器 selection/undo/composition 行为。
- **行级渲染（line-based）**：每一行对应一个 DOM 节点（`<div class="line">` 或类似），行内样式分组用 `<span>`。
- **从第一版开始支持 soft wrap**：我们不做“超长行横向无限扩展”的 DOM；wrap 宽度由 viewport 决定（`editor-core` 以 cells 表示），避免 viewport 快照/DOM 负载不受控。
- **固定宽度 cells 模型（Monaco 风格）**：UI 坐标以 `(row, x_cells)` 为核心（`row` 处于 **composed visual rows** 空间）；每个 glyph 的占用宽度必须是 **整数 cells**（可为 0/1/2/…，例如 combining=0、ASCII=1、CJK=2、折叠标记/虚拟文本也可 >1）。允许 ligatures（它们只改变绘制形状，不改变“占用的 cells 总数”这一前提）。
- **IME 必须正确**：
  - 需要一个“小型输入覆盖层”捕获 composition；
  - 组合文字必须“像是在底层文本里”，而不是覆盖在文本之上导致错位/遮挡；
  - 组合期间底层文本排版形状要随之变化（至少在视觉上）。
- **DOM 更新需要批量**：JS ↔ Rust 通信可能慢，不能每个字符都同步往返+全量重绘。
- **从一开始就有可运行 App**：先做一个最小可用的编辑器壳，再逐步加能力；结构要干净可扩展。

### 1.2 非目标（第一阶段暂不做）
- 不追求浏览器原生文本选择/复制体验（由我们自己实现 selection/clipboard）。
- 不追求一次到位的“所有复杂脚本+所有平台 IME 完美一致”；先把主流场景跑通并留扩展点。
- 不做 Canvas 渲染（本计划明确用 DOM text-grid）。

---

## 2. 总体架构与职责边界

### 2.1 Rust（Tauri 后端）
- 目标运行时：**Tauri v2**（跨平台窗口 + WebView 容器）。
- 持有 `editor-core` 状态（buffer、布局、光标/选择、语法高亮/装饰等）。
- 接收前端输入事件（键盘/鼠标/滚动/IME commit 等）→ 转换成 editor 命令 → 更新状态。
- 产出“渲染模型（render model）”并生成 **render patch** 推送到前端。
- 提供跨平台能力的后端实现（已确认：剪贴板走 Tauri 后端，而不是 WebView `navigator.clipboard`）。

### 2.2 前端（WebView：HTML/CSS/JS/TS）
- 只渲染 viewport（虚拟化），以 **行** 为单位更新 DOM。
- 维护渲染调度器：合并 patch，`requestAnimationFrame` 内一次性提交 DOM 变更。
- 维护少量 UI-only state（推荐：font metrics 缓存、输入节流队列、IME `textarea` selection/定位信息）。
- 通过调用后端命令完成剪贴板读写、文件读写等“需要稳定跨平台语义”的能力。

### 2.3 推荐数据流（避免同步瓶颈）
1. 前端收集输入事件 → 进入队列（可按帧/按时间片合并）
2. 发送到 Rust（异步，不阻塞 UI）
3. Rust 处理命令并推送 patch（事件/广播，不要求前端发起拉取）
4. 前端合并 patch → raf 批量更新 DOM

> 关键：避免“每个键都 `invoke().await` 然后立即重绘”的同步链路。

### 2.4 参考 Monaco Editor（VS Code）的对照关系（用于设计决策）
当我们在“正确性 / 性能 / 跨平台差异”之间做取舍时，可以把 Monaco Editor 作为一个成熟的参考系（不是照搬 API，而是借鉴其分层与策略）。

粗略对照：
- Monaco **Model**（文档与编辑语义）≈ `editor-core`（`Workspace`/`CommandExecutor`/`EditorCore`）
- Monaco **ViewModel**（wrap、fold、decorations、view zones 组合后的“可渲染视图”）≈ **JS 侧 ViewModel（缓存/差分/测量）** + Rust 侧的 viewport snapshot（本计划从第一版起以 `ComposedGrid` 为主）
- Monaco **View/Renderer**（DOM 行、overlay、小部件）≈ Tauri WebView 前端的 lines layer + overlays + widgets
- Monaco **TextAreaHandler**（输入管线/IME）≈ 我们的 `imeInput` + IME 状态机（见第 5 节）

Monaco 对我们最有价值的经验点：
- DOM 行渲染就是“行容器 + spans”，并且只渲染可视区（virtualization）。
- 输入不依赖 `contenteditable`，而是用隐藏/透明 textarea 捕获键盘与 IME，并把 preedit/selection 反映回渲染层。
- 性能上坚持“批量提交 + 按帧调度 + 最少布局抖动（layout thrash）”，并对浏览器差异留兼容层与记录。

---

## 3. 渲染模型（Render Model）与“行”的定义

### 3.1 “行”优先对齐可视行（visual row）
如果 `editor-core` 支持软换行/折行/折叠，那么前端 DOM 的 `.line` 最终应对应 **可视行（visual row）**，而不是原始逻辑行。否则鼠标命中测试、选择渲染、滚动定位都会变复杂。

结合当前代码实现，`editor-core` 的 snapshot API 本质上是“按行（row）取 viewport 内容”。在我们已经确认“第一版就用 `ComposedGrid`”的前提下，建议：
- **DOM 行与 `ComposedGrid` 对齐**：每个 `.line` = 一个 **composed visual row**（包含必要的 above-line 虚拟行）。
- **从第一版起就启用 soft wrap**（`WrapMode::Char` 或 `WrapMode::Word`，不使用 `None`），并固定 `WrapIndent::SameAsLineIndent`；持续把 WebView 的可视宽度同步为 `editor-core` 的 `viewport_width`（cells）。
  - 原因：`WrapMode::None` 下，一个 visual row 可能包含“整条超长逻辑行”的全部 cells，导致 viewport snapshot 体积与 DOM 更新成本不可控，也不符合我们“text-grid + viewport”的渲染目标。
  - 实践上：wrap 的“宽度边界”就是性能边界——每个 visual row 的内容规模应与 viewport 宽度同阶，而不是与文件中最长龙同阶。

### 3.2 后端输出：从第一版开始以 `ComposedGrid` 为主
已确认：我们需要从第一版开始支持 `ComposedGrid`（否则后续引入虚拟文本/虚拟行会造成架构大改）。因此本计划把 `ComposedGrid` 视为 **唯一/主路径** 的 viewport snapshot：
- `ComposedGrid` 的行序列可能包含：
  - 文档行段（wrap + folding aware）：`ComposedLineKind::Document { logical_line, visual_in_logical }`
  - above-line 虚拟行（例如 code lens / view zones）：`ComposedLineKind::VirtualAboveLine { logical_line }`
- 虚拟文本（inlay hints、折叠占位符、wrap indent 空格等）以 `ComposedCellSource::Virtual { anchor_offset }` 注入，**不会破坏**“固定宽度 cells”坐标体系。

`HeadlessGrid` 仍可用于：
- debug/对照（没有虚拟文本时验证一致性）
- 或在确认“无 decorations 且无 virtual text”时做性能捷径（但前端渲染管线仍按 composed 设计，避免分叉）

#### 3.2.1 两种 row 空间（必须在设计里明确）
为了避免概念混淆，这里约定两种 row 空间：
- **doc visual rows**：仅 wrap+fold 的文档可视行（`HeadlessGrid` 与 `WorkspaceViewportState.total_visual_lines` 使用这个空间）
- **composed visual rows**：doc visual rows + above-line 虚拟行（`ComposedGrid` 的 `start_visual_row/count` 使用这个空间）

本计划建议 **UI 滚动与渲染以 composed visual rows 为准**（更接近 Monaco 的 view lines + view zones），这样 code lens/view zones 才会正确参与滚动高度与虚拟化。

> 关键点（常见坑）：`WorkspaceViewportState` 的统计与定位语义只覆盖 **doc visual rows**。  
> 一旦引入 `ComposedLineKind::VirtualAboveLine`（code lens / view zones），**composed total_rows** 会变大；如果 UI 还用 `WorkspaceViewportState.total_visual_lines` 去算 `scrollHeight/spacerTop/spacerBottom`，滚动条比例与“滚动到某行”都会错。  
> 因此本计划要求：滚动高度与虚拟化的 row 空间必须统一到 **composed visual rows**（详见 6.4.1/6.4.2）。

#### 3.2.2 Rust→JS 传输：压缩为 Web-friendly `ViewportSnapshot`
Rust → JS 不建议把 `ComposedGrid` 原样 serde 成 JSON（对象层级深、重复字段多）；更推荐输出一个 **紧凑快照**（并可进一步二进制化，见 6.5）：
- `ViewportSnapshot { start_row, total_rows, width_cells, tab_width, wrap_indent, lines: LineSnapshot[] }`
  - `start_row/total_rows` 均在 **composed visual rows** 空间
  - `width_cells/tab_width/wrap_indent` 用于前端 viewmodel 的缓存键与 hit test（避免同一帧内“宽度不一致”）

`LineSnapshot`（一个 composed visual row）建议包含：
- `row`：绝对 composed row（用于调试、定位 `data-row`、overlay）
- `kind`：`Document` / `VirtualAboveLine`（至少要区分是否可编辑/可命中到文档）
- `runs`：按连续样式段压缩后的 runs，同时保留来源（Document/Virtual），例如用 tuple 形式减少 JSON 开销：
  - `runs: [styleSetId, sourceKind, sourceOffset, text][]`
    - `styleSetId`：样式集合的 intern id（避免每段都携带 style id 数组）
    - `sourceKind`：0=Document（sourceOffset 为起始 char offset），1=Virtual（sourceOffset 为 anchor_offset）
    - `text`：该段文本

这样前端既能用 runs 渲染 `<span>`，也能在需要时（hit test/选择/IME）基于 `sourceKind/sourceOffset` 做“网格坐标→文档 offset”的映射，而无需每个 cell 都单独传输。

### 3.3 前端渲染单元：runs → `<span>`
我们已经决定在 Rust→JS 的 `LineSnapshot` 中直接输出 runs（而不是 cells），因此前端渲染的最小单位就是“样式段 `<span>`”：
- `runs: [styleSetId, sourceKind, sourceOffset, text][]` → 生成 `<span class="...">text</span>`
- 若相邻 runs 映射到同一个 CSS class，可在前端再做一次合并以减少 DOM 节点数（Monaco 常见优化）

> 宽度一致性说明：内核与前端都以 **cells** 为坐标单位，并且我们已确认“每个 glyph 占用整数个 cells（0/1/2/…）”的约束。
> - 因此 HTML 的实际像素排版应当被约束到“cellWidthPx × N”的离散网格（等宽字体 + 合理的 CSS）。
> - 若出现某个平台字体 fallback 导致“同一字符宽度不是整数 cells”的情况，应视为**兼容性问题**：允许短期记录/绕过，但不能让坐标体系变成连续像素模型（见第 10 节留账）。

### 3.4 光标与选择：推荐做成 overlay（不进文本流）
光标移动非常频繁，把光标/选择做成独立 overlay 层可以减少行内 DOM 重建：
- `cursor`: `{ row, x_cells }`（推荐；`row` 位于 **composed visual rows** 空间）或 `{ x_px, y_px, height_px }`
- `selections`: 推荐用 **文档 char-offset ranges** 表达（Rust 输出），前端基于 viewport `LineSnapshot` 拆成可视矩形渲染；这样能天然处理 wrap、fold、以及 inlay/virtual text 不可选的情况

建议第一版采用：**Rust 输出 `(row, x_cells)`，前端用测量得到的 `cellWidthPx/lineHeightPx` 定位到像素**（固定宽度 cells 模型下最简单、也更接近 Monaco）。

### 3.5 命中测试（hit test）：grid-based + 宽字符
已确认：命中测试可以走 grid-based，但必须处理宽字符/多 cells glyph，避免 caret 落在 glyph 中间。

推荐做法（Monaco 类似思路）：
- **像素 → cells 坐标**：
  - `row = start_row + floor((y_px + lineHeightPx/2) / lineHeightPx)`（半行四舍五入更贴近期望；也可先用 `floor(y/lineHeight)` 再迭代）
  - `x_cells = floor((x_px + cellWidthPx/2) / cellWidthPx)`（半 cell rounding：点击偏右更倾向落在字符后）
- **cells 坐标 → 文档 offset**（基于当前 viewport 的 `LineSnapshot`）：
  - JS ViewModel 为每个可见行维护（懒计算+缓存）一个 `cellBoundaryMap: offset_at_x_cells[]`
  - 计算时遍历 runs 的 `text`，用与内核一致的“cells 宽度”规则累计 `x_cells`（包含 tab 扩展与宽字符），并根据 `sourceKind` 写入：
    - Document run：`offset = sourceOffset + char_index_in_run`
    - Virtual run：`offset = sourceOffset`（anchor_offset；虚拟文本命中可按 anchor 处理或转成 widget 点击）
  - 这样 `offset_at_x_cells[x]` 自然不会落在宽字符“中间”（因为宽字符占多个 cells，边界只在 cells 网格上推进）

> 说明：由于我们允许 ligatures，上述命中测试仍然成立——连字只改变绘制形状，但 caret/选择始终落在 cells 边界上。

---

## 4. DOM 结构：line `<div>` + run `<span>` + overlay + IME 输入层

### 4.1 分层 DOM（建议）
```html
<div id="editorRoot">
  <div id="scrollViewport">
    <div id="spacerTop"></div>
    <div id="linesLayer">
      <!-- composed-row line nodes -->
      <div class="line" data-row="...">
        <span class="tok tok-keyword">fn</span><span class="tok tok-ws"> </span>
        <span class="tok tok-ident">main</span>
      </div>
    </div>
    <div id="spacerBottom"></div>
  </div>

  <div id="overlayLayer">
    <div id="selections"></div>
    <div id="cursor"></div>
  </div>

  <!-- 仅用于输入/IME，不用于显示 -->
  <textarea id="imeInput"></textarea>
</div>
```

### 4.2 CSS/排版要点（影响命中测试与性能）
- `.line { white-space: pre; }` 保留空格/制表符布局（配合 `tab-size`）。
- `tab-size` 需要与 `editor-core` 的 `tab_width`（cells）一致（否则 tab 展开宽度与内核布局会漂移）。
- 统一 `line-height`（虚拟化与滚动定位依赖它）。
- 等宽字体（建议默认）：命中测试与光标定位更简单。
- **支持 ligatures**：不要强制关闭 `font-variant-ligatures`；选择支持连字且仍保持等宽“cells 占用不变”的字体（例如同一段文本即使形成一个连字 glyph，也必须占用整数个 cells）。
- 建议加 `.line { overflow: hidden; }` 作为“防抖”：当某些平台字体 fallback 导致单个 glyph 宽度略超预期时，避免溢出影响布局（差异仍需记录与后续修正）。
- 文本渲染安全：构造 `<span>` 时用 `textContent`；若走 HTML 字符串，必须转义，避免 XSS（文件内容不可视为可信）。

### 4.3 Monaco 借鉴点：图层与小部件
Monaco 的 DOM 结构通常把内容与 overlay 分离（内容行层、选择/光标层、widgets 层、textarea 输入层）。我们建议保持同样的可扩展空间：
- **内容层（lines）**：只承载“字符与样式 runs”，避免把选择/光标/IME 视觉塞进内容层导致频繁重排。
- **overlay 层**：光标、选择矩形、搜索高亮、括号匹配等尽量走 overlay（或用 style layer 统一表达，再由渲染策略决定是否 overlay）。
- **widgets/view zones**（后续）：对应 `ComposedGrid` 的虚拟行/虚拟 cell（inlay/code-lens），以及将来可能的悬浮提示、inline actions。

---

## 5. IME（组合输入）处理方案：透明 textarea + 行内组合渲染

### 5.1 为什么不能用 `contenteditable`
`contenteditable` 会让 WebView 把 DOM 当“真实文档”，浏览器接管 selection/undo/composition；这与 text-grid（多光标、折行、语法高亮、结构化装饰等）模型冲突，并且跨平台行为差异大。

### 5.2 推荐方案概览
用一个“透明/极小”的 `<textarea id="imeInput">` 捕获 IME 与文本输入，但**真正显示仍由 linesLayer 完成**。

关键机制：
- `imeInput` 始终保持 focus（editor 点击/激活时自动 focus）。
- `imeInput` 按 caret 像素位置移动（由 `(row, x_cells)` + `cellWidthPx/lineHeightPx` 计算），让系统候选窗靠近光标出现。
- `imeInput` 视觉透明：`opacity: 0;`，不让用户看到其内容。
- 组合期间，**不直接显示 textarea 的内容**；组合字符串应通过“marked text”进入内核并由 snapshot 渲染（见 5.3），从而视觉上自然嵌入文本流、并真实影响 layout。
  - 若遇到某平台 WebView 事件能力不足（例如无法稳定拿到 replace_range/selection），可临时退化为“前端行内插入 composition span”的 UI-only 方案，但必须记录差异（见 10）。

### 5.3 事件与状态机（推荐：内核一致的“marked text”模型）
`editor-core` 已经内置了 IME 相关的编辑语义与样式 id，因此更推荐把 composition（preedit）作为一种“可替换范围”进入内核模型（并用独立 style layer 渲染下划线/背景），而不是仅在前端做 UI-only。

这样做的好处：
- composition 会真实影响内核布局（wrap/fold/viewport 计算一致），满足“底层文本形状要调整”的要求；
- 撤销/重做能把“一次完整的 IME 组合（多次 update + commit）”当成一个 undo step；
- 样式渲染统一：直接使用 `StyleLayerId::IME_MARKED_TEXT` + `IME_MARKED_TEXT_STYLE_ID`。

建议流程（与现有 `editor-core-ui` 的做法一致）：
- `compositionstart`
  - 记录 composition 的“替换范围”（通常是当前 selection/caret；有些平台 IME 会给出 replace_range）
  - 后端执行：`EditCommand::EndUndoGroup`（避免与普通输入合并 undo）
- `compositionupdate`（高频）
  - 把当前 preedit 字符串作为一次 replace 更新发送给后端：
    - `EditCommand::ReplaceCoalescingUndoWithSelection { start, length, text, selection_start, selection_end }`
  - 后端同时应用/更新一个专用样式层：
    - `ProcessingEdit::ReplaceStyleLayer { layer: StyleLayerId::IME_MARKED_TEXT, intervals: [start..start+len => IME_MARKED_TEXT_STYLE_ID] }`
  - 前端更新候选窗定位：把 `imeInput` 移动到“composition 内部 caret”的像素位置
  - 性能策略：前端对 `compositionupdate` **按帧节流**（例如 16ms 内只发送最后一次），避免跨边界风暴
- `compositionend`（commit）
  - 若 WebView 提供的是最终 commit text：
    - 后端执行一次 `ReplaceCoalescingUndo`（或沿用最后一次 update 的状态，仅清理样式层并 `EndUndoGroup`）
  - 清理样式层：`ProcessingEdit::ClearStyleLayer(IME_MARKED_TEXT)`
  - `EditCommand::EndUndoGroup` 结束 composition undo 分组

取消 composition（例如 Escape / IME 清空 marked text）：
- 约定：当 marked text 变为空串时，视为“取消/清除组合”
- 后端恢复 composition 开始时被替换掉的原始文本（需要保存 original_text/original_len），并恢复原 selection（best-effort）

> 备注：如果某个平台 WebView 无法可靠提供 composition 内 selection（`selectionStart/End` 不稳定），可以退化为“caret 始终在 preedit 末尾”，但要记录差异（见“WebView 差异记录”）。

### 5.4 视觉细节：让组合“看起来在底层文本里”
- marked text 需要“行内呈现”，不能用浮层遮罩覆盖文本：
  - 将 `IME_MARKED_TEXT_STYLE_ID` 映射为 CSS（underline / background / 波浪线等）
  - 前端渲染时，遇到带该 style id 的 run 自动加对应 class
- 由于 marked text 在内核模型中是“真实 replace”，因此不会出现“底层文字仍在、上面再盖一层”的遮挡问题；取消 composition 时再恢复 original_text。

### 5.5 跨平台风险与早期验证
不同平台 WebView 对 IME/textarea 行为不一致（尤其候选窗定位）。里程碑中应尽早做三平台 smoke test：
- macOS：WKWebView
- Windows：WebView2
- Linux：WebKitGTK

### 5.6 Monaco 借鉴点：输入兼容层与“可回退路径”
Monaco 的输入系统本质上是一个“兼容层”：同一个用户动作可能在不同浏览器/平台下走不同事件组合（`keydown`/`beforeinput`/`input`/`composition*`），Monaco 会做多路径归一化。

对 Tauri WebView 来说，我们也建议把输入处理设计成：
- **主路径**：`beforeinput/input + composition*`（与 IME/粘贴更一致）
- **回退路径**：必要时用 `keydown` 兜底（尤其快捷键、导航键、某些平台 beforeinput 不可靠的情况）
- **差异记录与兼容开关**：将 “平台差异 → workaround” 作为显式配置与记录（对应第 10 节）

---

## 6. DOM 更新与性能：Patch、合并、虚拟化

### 6.1 核心原则
- 不做“每次全量重绘整个文件 DOM”
- 不做“每个输入事件都同步往返 Rust”
- 不做“收到 patch 就立即操作 DOM”（统一 raf 合并）

### 6.2 Patch 形态（从简单到高性能）
MVP（先跑通）：
- `set_viewport { start_row, count, lines: LineSnapshot[] }`（每次给完整 viewport；`row` 在 **composed visual rows** 空间）
- `set_overlays { cursor, selections }`

性能版（逐步升级）：
- `replace_rows { start_row, lines: LineSnapshot[] }`（一段连续 composed rows 的替换）
- `splice_rows { start_row, delete_count, insert: LineSnapshot[] }`（插入/删除 composed rows；注意 wrap/fold/above-line 变化可能导致大范围失效）
- `set_overlays` 独立发送（光标移动不需要重建行 DOM）

建议约定一个“强制全量刷新”的场景集合（直接走 `set_viewport`）：
- viewport 宽度（cells）变化导致 reflow（window resize / 字体变更）
- folding/大范围样式层替换导致大量行结构变化
- `DecorationPlacement::AboveLine` 数量变化（code lens/view zones）会改变 composed rows 的总高度与行号映射

### 6.3 前端渲染调度器（批量提交）
前端维护 `pendingPatches`，在 `requestAnimationFrame` 中：
1. 合并 patch（同类字段“后到覆盖先到”）
2. 应用到 **JS ViewModel**（缓存当前 viewport 的 `LineSnapshot[]` + 度量信息），在 ViewModel 内计算“哪些行真的变了”
3. 只对变化的行更新 DOM（推荐：固定数量 `.line` 节点按 index 循环复用，并更新其 `data-row` + runs 内容）
4. 单独更新 overlay（cursor/selection）位置与样式

### 6.4 视口虚拟化（必须尽早）
soft wrap 开启后，一个逻辑行可能拆成多个 **doc visual rows**；同时 `ComposedGrid` 还可能插入 **above-line 虚拟行**，使得 **composed visual rows** 的总行数进一步增加。大文件会让总行数快速膨胀，同时 DOM 节点也会爆炸；因此需要 viewport 虚拟化。

最小版本（等高行）：
- 只渲染 `visibleRows + overscan`（例如上下各 30 行；这里的 rows 指 **composed rows**）
- 用 `#spacerTop/#spacerBottom` 撑开滚动高度
- scroll 时只触发 viewport 可视行集合更新（而不是整页重绘）

#### 6.4.1 `total_rows/scrollHeight`：使用 `ComposedViewportState`（推荐实现）
为了让滚动条高度、`spacerTop/spacerBottom`、以及“滚动到某行”的语义在引入 code lens/view zones（`AboveLine` 虚拟行）后仍然稳定，我们需要一个明确的 viewport state，且它必须工作在 **composed rows 空间**（而不是 `WorkspaceViewportState` 的 doc rows 空间）。

推荐约定：
- UI 侧（JS）把 `ViewportSnapshot.total_rows` 视为**唯一真值**，并用：
  - `scrollHeightPx = total_rows * lineHeightPx`
  - `spacerTopPx = start_row * lineHeightPx`
  - `spacerBottomPx = (total_rows - (start_row + lines.length)) * lineHeightPx`
  - 其中 `start_row` 是这次 `lines[]` 的起始行（通常等于 `prefetch_start`，而不一定等于用户当前“可见区”的第一行；两者差值由 overscan 决定）
- Rust 侧维护并缓存一个 `ComposedViewportState`（或等价结构），并在每次返回 `ViewportSnapshot` 时一并填充：
  - 至少包含：`total_rows`（composed total）与 `start_row`（本次返回 `lines[]` 的起点）
  - `visible_rows/prefetch_rows` 可以由前端根据 viewport_height/overscan 推导；也可以作为调试/一致性字段由后端一并返回（推荐但非必须）

为什么不能直接用 `WorkspaceViewportState.total_visual_lines`：
- 它统计的是 **doc visual rows**（wrap+fold 的文档行段），不包含 `DecorationPlacement::AboveLine` 插入的虚拟行。
- 一旦出现 above-line 行，按 doc rows 计算的 `scrollHeight` 会偏小，滚动条比例与定位都会错。

一个具体例子（直观理解上面的差异）：
- 某文件在 soft wrap 后共有 `doc_total = 100`（`WorkspaceViewportState.total_visual_lines == 100`）。
- 现在给第 10 个 logical line 加一个两行的 code lens（`AboveLine`，会形成 `+2` 行虚拟行）。
- 此时 `composed_total = 102`，但 `WorkspaceViewportState.total_visual_lines` 仍然是 100。
- 如果 UI 用 100 去算 `scrollHeight`，滚动到底部时会“少两行高度”，并且任何基于 `row -> scrollTop` 的定位都会产生偏差/跳动。

#### 6.4.2 `ComposedRowIndex` 缓存（计算与失效策略）
实现 `ComposedViewportState` 的关键是：维护一个能快速回答 “composed 总行数是多少 / 第 N 行是什么 / doc↔composed 如何换算” 的索引。

推荐在后端维护 `ComposedRowIndex`（按 view 维度缓存），其输入来自：
- wrap 布局：每个 logical line 的 `visual_line_count`（受 `viewport_width`、`wrap_mode`、`wrap_indent`、`tab_width` 影响）
- folding：隐藏的 logical lines 需要从统计中跳过
- decorations：`DecorationPlacement::AboveLine` 且 `text` 非空的条目会为对应 logical line 增加虚拟行数（可为多行）

缓存内容建议至少包含：
- `total_rows_composed`
- `above_count_per_logical_line`（可选：只存非零项）
- `prefix_above_before_logical_line`（用于 doc_row → composed_row 的快速换算）

失效（invalidate）触发条件建议明确写死（避免“看起来随机跳动”）：
- **reflow 类**：`viewport_width`（cells）变化、wrap mode 变化、wrap indent 变化、tab width 变化
- **结构类**：folding regions 变化、`AboveLine` decorations 变化（数量/内容变化）
- **文本类**：文档编辑导致 layout/逻辑行结构变化（通常视为全部失效，后续再做增量优化）

实现上可以先做“失效后下一次请求时全量重建索引”（O(逻辑行数)），等到性能压力出现再引入增量更新；但接口与数据结构必须从第一版起就按“可缓存/可失效/可替换编码”设计。

后续增强（可变行高/更复杂布局）：
- 引入测量缓存或分段估算；复杂度高，建议延后。

### 6.5 高效编码与 IPC（从第一版开始）
已确认：需要从第一版就采用**高效的编码设计**，避免先做“好用但很慢的 JSON 全量”再返工。

建议策略（Monaco 思路：ViewModel 缓存 + 最小化跨边界数据）：
- **Rust 侧先压缩**：从 `ComposedGrid` 生成 `LineSnapshot.runs`（连续样式段），并对 `style_ids[]` 做 **style-set interning**（变成 `styleSetId`）。
- **结构尽量扁平**：优先用 tuple 数组（如 `[styleSetId, sourceKind, sourceOffset, text]`）而不是深层对象，减少 JSON 解析开销。
- **可升级为二进制**：如果 JSON 仍成为瓶颈，预留把同一结构编码为 CBOR/MessagePack/自定义二进制的空间（前端用 `Uint8Array` 解码）。关键是“字段语义先稳定”，编码方式可替换。
- **JS ViewModel 做 diff**：即便后端发送一整个 viewport 的 `lines[]`，前端也要在 ViewModel 层做“行级 hash/比较”，只更新变化行的 DOM；这能显著降低 layout/paint 压力。

---

## 7. 里程碑（从可运行开始）

### Milestone 0：Tauri 壳 + 静态渲染（第 1 天）
- 建立最小 Tauri App（窗口 + 前端页面）。
- 前端渲染固定 100 行假数据（验证 line `<div>` + span + 滚动 + CSS）。
- 做一次**字体/行高测量**（前端测 `cellWidthPx/lineHeightPx`），把 viewport 像素尺寸转换为 `editor-core` 需要的 `viewport_width`（cells）与 `viewport_height`（rows），并把这套“测量→同步”的管线固定下来（后续 wrap/命中测试都依赖它）。
- 建立 **JS ViewModel** 骨架：能接收 `ViewportSnapshot`，缓存 viewport lines，并把 runs 渲染为 DOM 行。
- 打通 Rust → JS 的事件推送（先推 `set_viewport` + `lines[]` 即可，但编码按 6.5 的“扁平/可升级”原则设计）。

验收：启动后可看到可滚动文本行。

### Milestone 1：接入 `editor-core` 的只读渲染（第 2–3 天）
- Rust 打开文件 → 从 `editor-core` 产出 viewport **`ComposedGrid`（composed visual rows）**（即使暂时没有 decorations，也保持这条主路径）。
- 明确启用 soft wrap（`WrapMode::Char` 或 `WrapMode::Word`），并固定 `WrapIndent::SameAsLineIndent`；在窗口 resize / 字体变化时，持续同步 `viewport_width`（cells）到内核（否则 wrap 结果与 scroll 高度会立刻失真）。
- 前端实现虚拟化（composed rows + overscan）。
- 定义并跑通最小 render model + patch：Rust 侧把 `ComposedGrid` 压缩成 `ViewportSnapshot/LineSnapshot.runs`，前端 ViewModel 应用并渲染。

验收：能打开真实文件并流畅滚动。

### Milestone 2：光标与基础导航（第 4–5 天）
- 前端捕获 `keydown`（方向键/翻页/Home/End）→ 发送命令给 Rust。
- Rust 更新 caret → 推送 overlay 更新（`(row, x_cells)`；`row` 在 composed rows 空间）。

验收：光标移动正确、滚动跟随正确。

### Milestone 3：文本输入/删除（非 IME）（第 1 周内）
- 用 `imeInput` 的 `beforeinput/input` 捕获普通文本输入（与 IME 同路，避免键盘布局问题）。
- Rust 完成插入/删除命令并推送 viewport patch。

验收：英文输入、Backspace/Delete 正常。

### Milestone 4：IME MVP（建议第 1 周尽早）
- 引入 `compositionstart/update/end` 处理，采用“marked text 进入内核”的模型：
  - `ReplaceCoalescingUndoWithSelection` 做 preedit 更新（按帧节流）
  - `StyleLayerId::IME_MARKED_TEXT + IME_MARKED_TEXT_STYLE_ID` 做下划线/背景渲染
  - `EndUndoGroup` 隔离 composition 的 undo 分组
- 解决候选窗定位（`imeInput` 跟随 caret 像素位置）。
- 把 WebView 平台差异按 10 的格式记录下来（不阻塞 MVP，但要留账）。

验收：中/日/韩输入可用，组合效果“嵌入底层文本”，无错位遮挡。

### Milestone 5：样式分组（语法高亮/装饰）（第 2 周）
- Rust 侧接入一个或多个派生状态来源（可选：`editor-core-highlight-simple` / `editor-core-sublime` / `editor-core-treesitter` / `editor-core-lsp`）产出 `ProcessingEdit::ReplaceStyleLayer`。
- 前端把 viewport snapshot 中的 `StyleId` 映射为 CSS class / CSS variables。

验收：高亮可见且滚动/输入仍流畅。

### Milestone 6：Patch 细化与性能治理（第 2–3 周）
- 从“全量 viewport”升级到“`replace_rows/splice_rows` + overlay 分离”，并让 JS ViewModel 保持稳定缓存命中。
- 引入性能指标（patch 大小、每帧 DOM 更新时间、端到端输入延迟）。

验收：大文件与连续输入下延迟稳定。

---

## 8. 代码组织建议（先规划，后续落地）
为了保持“先跑起来”与“后续可扩展”兼得，建议提前分层抽象（不在本次任务编码）：
- 前端：`ViewModel.applyPatch(patch)`（缓存+diff） / `Renderer.render(viewModel)` / `Renderer.measure()` / `ImeController` / `ClipboardController`（调用后端）
- Rust：`UiBridge.send_patch(patch)` / `InputRouter.handle_event(event)` / `RenderModelBuilder`（从 `ComposedGrid` 生成 `ViewportSnapshot`） / `ClipboardService`（Tauri v2）

---

## 9. 决策记录与待定项（持续更新）

### 9.1 已确认（来自当前讨论的结论）
- **运行时**：目标 **Tauri v2**。
- **坐标与宽度模型**：采用“固定宽度 cells”模型；每个 glyph 占用整数个 cells（可为 0/1/2/…）。**支持 ligatures**（不改变占用 cells 总数）。
- **Wrap 策略**：不使用 `WrapMode::None`；wrap 模式用 `Char` 或 `Word`（按实现便利与体验选择）；wrap indent 固定为 `WrapIndent::SameAsLineIndent`。
- **渲染输入**：从第一版开始以 **`ComposedGrid`** 为主（必须支持虚拟文本/虚拟行；避免后续大改）。
- **剪贴板**：走 **Tauri 后端实现**（跨平台一致性优先），而不是依赖 WebView `navigator.clipboard`。
- **命中测试**：走 **grid-based hit test**（基于 cells），并特别处理宽字符/多 cells glyph（避免把 caret 放进 glyph “中间”）。
- **编码/性能**：从第一版就采用**高效编码设计**（runs 压缩、style-set interning、可升级二进制）。
- **JS ViewModel**：推荐引入（用于缓存与 diff，降低 DOM 更新与 IPC 压力；参考 Monaco 的 viewmodel 思路）。
- **滚动/虚拟化 row 空间**：以 **composed rows** 为准；后端提供 `ViewportSnapshot.total_rows`，并用 `ComposedViewportState + ComposedRowIndex` 做计算与缓存（避免 above-line 虚拟行导致 scrollHeight 错乱）。

### 9.2 仍待细化（不影响方向，但需要落到具体规则）
- **默认 wrap 模式**：首版默认 `Char` 还是 `Word`（建议默认 `Char`，`Word` 作为可切换项）。

首版默认 `Char`。

- **IPC 编码落地方案**：首版直接用“紧凑 JSON tuple”还是直接上 CBOR/MessagePack/自定义二进制；两者的工程成本与收益评估。

首版可以采用JSON，但要确保设计便于后续切换到二进制编码。

- **宽字符点击规则**：grid-based hit test 里，“点击在宽字符右半部分”是否要更倾向于落在字符之后（半 cell rounding 的边界规则需要统一并测试）。

可以采用半 cell rounding 的规则：点击偏右更倾向落在字符后；点击偏左更倾向落在字符前。边界条件无需过于关注，因为用户点击不是一个像素级的精确动作。

- **滚动锚点策略**：当 `AboveLine` decorations 动态增删导致 `total_rows` 变化时，是否要保持视口内容稳定（Monaco 风格 anchor），以及 anchor 选取（doc row / char offset）与实现位置（前端 vs 后端）。

使用Monaco 风格 anchor。

---

## 10. WebView 差异记录（当前可容忍，但要留账）

目标不是“立刻抹平所有平台差异”，而是：
1) 先把主路径跑通；2) 把差异**明确记录**；3) 未来有时间再逐项收敛。

### 10.1 需要重点观察/记录的差异点（待验证清单）
- **IME 事件序列差异**：`composition*` 与 `beforeinput/input` 的触发顺序、频率、data 字段内容。
- **composition 内 selection 的可用性**：`textarea.selectionStart/End` 在 composition 期间是否可靠（不同平台可能返回 0 或滞后）。
- **候选窗定位行为**：移动 `textarea` 是否能稳定改变候选窗位置；是否要求元素可见/有 caret。
- **键盘事件差异**：`KeyboardEvent.key`/`code` 的差异，尤其在非 US 键盘布局、Dead keys、以及 IME 打开时。
- **字体度量差异**：等宽字体下 CJK/emoji 的宽度是否稳定等于 2 “cells”；高 DPI 下是否出现小数像素累积偏移。
- **Tab 渲染差异**：CSS `tab-size` 是否在目标 WebView 版本下按预期工作（以及与内核 `tab_width` 对齐）。
- **滚轮/触控板差异**：wheel delta 模式（pixel/line/page）与惯性滚动行为。
- **剪贴板相关差异**：WebView 的 `navigator.clipboard` 可能受限（user gesture / 权限提示 / 快捷键拦截差异）；我们已决定走 Tauri 后端实现，但仍需记录“各平台 copy/paste 快捷键”与权限/焦点差异。

### 10.2 建议的记录格式（方便后续修）
每发现一个差异，建议补充一条条目，包含：
- 平台/版本（macOS/Windows/Linux + WebView 内核版本、Tauri 版本）
- 复现步骤（最小化）
- 期望行为 vs 实际行为
- 临时 workaround（如果有）
- 是否阻塞 MVP（是/否）

---

## 11. 建议的执行顺序（最短路径）
1. 先做 Milestone 0–2：保证“可运行 + 可滚动 + 光标移动 + 虚拟化”
2. 在做复杂编辑前尽早验证 IME（Milestone 4），避免输入管线重构
3. 再扩展样式、高亮与更细粒度 patch
