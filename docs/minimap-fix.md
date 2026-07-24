# Minimap 渲染异常（“三角形源码 → 矩形列表”）修复计划

## 1. 现象与复现

### 现象
- 源文件内容是逐行递增字符形成的“大三角形”（每行更长）。
- Minimap 侧却显示为“几乎等宽的横条矩形列表”，无法反映行长度变化。

### 复现方式（建议用最小用例）
1. 打开一个文本文件，内容类似：
   - 第 1 行：`x`
   - 第 2 行：`xx`
   - …
   - 第 N 行：`x` 重复 N 次
2. 打开/显示 minimap。
3. 观察：minimap 中每一行几乎都是同宽矩形，而不是逐渐变宽的三角形轮廓。

> 复现截图：`/Users/chenxu/Desktop/截屏2026-03-12 23.39.42.png`

## 2. 根因定位（已确认）

### 关键结论
问题不在 Rust 侧 `MinimapGrid` 的数据生成，而在 Swift 侧 minimap 的“条形宽度”计算方式。

### 证据链
- Rust 侧 `MinimapLine` 已提供：
  - `total_cells`: 该 visual line 的总渲染宽度（cell 数）
  - `non_whitespace_cells`: 非空白 cell 数
  - 这些信息足以表达“行长”与“空白占比”。
- Swift 侧（`swift/Sources/EditorCoreUI/EditorCoreSkiaMinimapView.swift`）当前逻辑是：
  - 计算 `density = nonWhitespaceCells / totalCells`
  - 将 `density` 映射为“横条宽度”：`w = widthPx * density`

### 为什么会变成“等宽矩形”
- 对于全是 `x` 的行：`nonWhitespaceCells == totalCells`，因此 `density == 1`
- 结果：无论行长是 1 还是 200，都会画出“满宽横条”，视觉上自然是矩形列表而非三角形。

## 3. 目标行为（期望效果）

### 最小目标（修复当前明显错误）
- minimap 的每一行横条宽度应能反映“该行在编辑器坐标系中的水平占用程度”。
- 对“大三角形”用例：minimap 应呈现出从窄到宽的三角形轮廓。

### 保持/兼容的现有行为
- 文档行数很大时（超过 `maxDetailedVisualLines`）仍然走轻量/占位渲染，避免性能问题。
- viewport 指示框与拖拽滚动行为保持不变。

## 4. 修复方案设计

### 方案 A（推荐）：宽度映射到“行长/视口宽度”
将“横条宽度”从 `density` 改为“行长覆盖率”：
- 取参照宽度：`vp.widthCells`（当前视口宽度，单位：cells）
- 取行长：`line.totalCells`（单位：cells）
- 计算覆盖率：`coverage = clamp(line.totalCells / vp.widthCells, 0...1)`
- 条形宽度：`w = widthPx * coverage`（至少 1px，避免不可见）

这样：
- 三角形用例中 `totalCells` 随行数增长，`coverage` 增长 → 条形逐渐变宽
- 对超长行（`totalCells > vp.widthCells`）会自然“满宽”，符合直觉（超过视口宽度的行在 minimap 中不必再更宽）

### “密度”如何处理（可选增强）
密度指标仍然有价值，但更适合映射到 **透明度/亮度** 而不是宽度：
- `ink = nonWhitespaceCells / max(1, totalCells)`
- 用 `ink` 调整 alpha（例如 `baseAlpha * lerp(0.3, 1.0, ink)`）

> 这样对一般代码（大量缩进/空格）也更符合直觉：  
> - 行更长 → 更宽  
> - 行更“实”（非空白更多）→ 更深/更亮

### 方案 B（备选）：以当前 minimap 可见范围的 `max(totalCells)` 归一化
优点：
- 在纯文本且行长变化明显时，能更充分利用 minimap 宽度。
缺点：
- 会受极端长行影响，导致绝大多数行很窄。
- 滚动时可见范围变化会导致横条宽度跳动（不稳定）。

结论：默认优先方案 A；若需要“更像传统 IDE minimap”的视觉，再评估方案 B 或混合策略。

## 5. 实施步骤（不写代码，只列任务）

1. **添加纯函数/小工具函数用于计算条形宽度**
   - 目标：把 `coverage`（基于 `totalCells` 与 `vp.widthCells`）的计算从 `draw(_:)` 中抽离，方便单测。
   - 位置建议：`EditorCoreSkiaMinimapView` 内部 `private` 方法即可。

2. **修改 `draw(_:)` 的 per-line 循环**
   - 将 `w = widthPx * density` 改为 `w = widthPx * coverage`
   - （可选）将 `density/ink` 用于 `fillColor` 的 alpha，而不是用于宽度。
   - 确保对 `vp.widthCells == 0`、`totalCells == 0` 做保护与 clamp。

3. **更新注释与命名**
   - 现有注释写的是 “density bars”，需要改成更准确的描述（例如 “length-based bars + optional ink alpha”）。

4. **新增/调整测试**
   - 文件：`swift/Tests/EditorCoreUITests/EditorCoreSkiaMinimapTests.swift`
   - 单测目标（尽量避免图形截图测试）：
     - 构造两条 `MinimapLineDTO`（或直接使用计算函数的输入）：
       - A：`totalCells = 10, nonWhitespaceCells = 10`
       - B：`totalCells = 40, nonWhitespaceCells = 40`
       - 断言：B 计算出的 width > A
     - 再构造同 `totalCells`、不同 `nonWhitespaceCells` 的用例：
       - 若采用“ink→alpha”，断言 alpha 不同但 width 相同。
   - 若必须做集成验证：调用 `_refreshNowForTesting()` 拿到 grid 后，跑 width 计算函数对多个递增行做“单调递增”断言。

5. **手动验证清单**
   - 用“三角形文件”验证：minimap 轮廓呈三角形。
   - 用普通代码文件验证：
     - 短行比长行更窄（可见差异）
     - 视口缩放/改变编辑器宽度时，minimap 宽度比例变化合理且无明显跳变
   - 大文件验证：超过 `maxDetailedVisualLines` 时仍然不卡顿且 viewport 指示框正常。

## 6. 风险与边界

- **软换行/折叠**：`totalCells` 已包含 wrap indent 与 fold placeholder 的宽度；这会轻微影响条形宽度，但总体仍比“密度映射宽度”更符合直觉。
- **超长行**：宽度会被 clamp 到 1（满宽），避免溢出。
- **性能**：不增加 JSON 请求次数与解码量；仅改变每行 O(1) 的计算与绘制参数。

## 7. 后续可选增强（不属于本次最小修复）

如果希望 minimap 还能体现“缩进起始位置/文本块左右边界”（更像传统 IDE）：
- 扩展 Rust `MinimapLine`：
  - 增加 `leading_whitespace_cells` 或 `first_non_whitespace_x_cells`
  -（或）增加 `segment_x_start_cells`（类似 `HeadlessLine`）
- 同步更新 FFI JSON、Swift DTO、渲染逻辑：用 `x` + `width` 画出“从缩进开始的块”，而不是永远从 `x=0` 画。

