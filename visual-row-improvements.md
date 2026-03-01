# Visual Row 改进计划（面向 Minimap / Smooth Scrolling）

状态：仅规划，不含实现代码变更。  
范围：围绕“访问 viewport 外 visual lines”的能力补齐与性能提升。

## 1. 背景与问题

当前内核已经支持按 visual row 区间读取快照（`start_visual_row + count`），可以拿到 viewport 外内容。  
但要把该能力用于“生产级 minimap + 平滑滚动”，还存在以下缺口：

1. 视觉行随机访问性能不足：从文档头线性扫描到目标 visual row，深位置高频读取成本高。
2. `Workspace` 侧缺少视图级视觉坐标查询 API：外层很难做统一的 minimap 点击定位与跳转。
3. 滚动状态是整行粒度：缺少子行偏移模型，不利于平滑滚动。
4. `HeadlessLine` 元数据不足：难做稳定缓存键、精确映射和可复用渲染。
5. 缺少 minimap 专用轻量快照通道：当前逐字符 `Cell` 结果过重。

## 2. 目标与非目标

## 2.1 目标

1. 让“任意 visual row 区间读取”在大文件与深偏移场景可稳定高频调用。
2. 为 `Workspace` 提供完整视图级视觉坐标查询能力。
3. 提供与 UI 无关的平滑滚动数据模型（不绑像素实现）。
4. 补齐快照元数据，支持缓存、映射和调试。
5. 新增 minimap 专用轻量数据路径，降低 CPU/内存开销。

## 2.2 非目标

1. 不在本计划中实现具体 GUI 动画、主题绘制和 minimap UI 控件。
2. 不把核心层绑定到任何前端框架或像素坐标系统。
3. 不修改现有编辑命令语义（仅增强查询与渲染数据通道）。

## 3. 总体策略

1. 先补“查询面”和“元数据面”，保证外部可用性。
2. 再做 visual row 索引，把核心瓶颈从线性降到对数级（或接近）。
3. 引入平滑滚动状态模型，保持与现有整行滚动兼容。
4. 最后新增 minimap 轻量快照路径，并做性能验证。

## 4. 分阶段计划

## Phase 0：基线与验收口径冻结

目标：定义可量化验收指标，避免后续“感觉优化”。

交付：

1. 新增基线基准项（大文件、深位置 start row、高频连续查询）。
2. 统一指标口径：吞吐（ops/s）、单次延迟（p50/p95）、内存峰值。
3. 补充典型场景用例：折叠开启、软换行开启、组合快照开启。

验收标准：

1. 基线可重复运行，结果稳定。
2. 后续每个阶段都可对比 Phase 0 指标。

## Phase 1：`Workspace` 视图级视觉查询 API 补齐（对应缺口 2）

目标：让宿主在 `Workspace` 层直接完成视觉坐标查询，不必下探内部对象。

计划新增能力（命名为草案）：

1. `total_visual_lines_for_view(view_id) -> usize`
2. `visual_to_logical_for_view(view_id, visual_row) -> (logical_line, visual_in_logical)`
3. `logical_to_visual_for_view(view_id, line, column) -> (visual_row, x_cells)`
4. `visual_position_to_logical_for_view(view_id, visual_row, x_cells) -> Position`
5. `viewport_state_for_view(view_id) -> {scroll_top, height, visible_range, total_visual}`

设计要点：

1. 所有查询都应用 `ViewCore`（wrap width / wrap mode / fold state）后再计算。
2. 仅新增 API，不改变现有命令执行路径。
3. 与单视图 `EditorCore` 查询语义严格一致。

验收标准：

1. 单视图与 `Workspace` 查询结果在同一输入下一致。
2. 多 view 同 buffer 时，各自 wrap 配置下结果独立正确。

## Phase 2：快照元数据增强（对应缺口 4）

目标：为 offscreen 渲染、缓存复用和映射回写提供足够元信息。

计划增强字段（草案，择优落地）：

1. `visual_in_logical`
2. `char_offset_start` / `char_offset_end`
3. `is_fold_placeholder_appended`
4. `segment_x_start_cells`（含 wrap indent 后的段内起始 x）

兼容策略：

1. 通过新增字段或新增 `HeadlessLineMeta` 承载，避免破坏旧调用方。
2. 保持 `ComposedLineKind` 与 `HeadlessLine` 可互相映射。

验收标准：

1. 宿主可仅凭快照完成“visual row -> 文本区间”映射。
2. 现有调用方不改动或最小改动即可继续工作。

## Phase 3：Visual Row 索引化与随机访问优化（对应缺口 1）

目标：将深位置查询从“按行线性累计”优化为可扩展索引查询。

核心思路（实现形式待评估）：

1. 维护“每 logical line 可见 visual 行数”的前缀可查询结构。
2. 支持 `visual_row -> logical_line`、`logical_line -> visual_start_row` 的快速映射。
3. 折叠状态变化与局部编辑后，做增量更新，不做全量重算。

候选数据结构：

1. Fenwick Tree（实现简单，前缀和/反查效率高）。
2. Segment Tree（更灵活，代价较高）。
3. 分块前缀索引（工程复杂度低，性能中等）。

关键约束：

1. 与折叠隐藏规则保持一致。
2. 与 `wrap_mode` / `wrap_indent` / `tab_width` 变更联动重算。
3. 大编辑和批量折叠切换下避免退化到频繁全量 rebuild。

验收标准：

1. 深位置查询性能相对 Phase 0 明显提升。
2. 折叠/换行配置变化后映射结果保持正确。
3. 查询与现有逻辑结果一致（通过回归测试对照）。

## Phase 4：平滑滚动数据模型（对应缺口 3）

目标：在核心层提供“子行级滚动状态”，但不绑定像素。

数据模型草案：

1. `top_visual_row: usize`
2. `sub_row_offset: u16`（0..=65535，表示当前行内归一化偏移）
3. `overscan_rows: usize`（供渲染端预取）

接口草案：

1. 查询接口返回“可渲染窗口锚点 + 推荐预取区间”。
2. 保持现有 `scroll_top: usize` 可继续工作（向后兼容）。
3. 新接口为可选增强层，旧宿主可不迁移。

验收标准：

1. 宿主可基于该状态实现连续滚动，不出现坐标跳变。
2. 折叠展开/收起后锚点行为可预测（定义并测试）。

## Phase 5：Minimap 轻量快照通道（对应缺口 5）

目标：提供比 `HeadlessGrid` 更轻的“概览渲染数据”。

输出形态草案：

1. 行级摘要：可见密度、语义颜色桶、折叠标记。
2. 可选列采样：在目标宽度下按桶聚合，而非逐字符 `Cell`。
3. 提供稳定的行锚点信息，支持 minimap 点击反查主视图位置。

设计原则：

1. 不复用逐字符快照结构，避免做完再压缩。
2. 与样式层解耦，仅输出可映射的样式 id/桶信息。
3. 允许宿主按预算选择精度（低/中/高密度模式）。

验收标准：

1. 同等区间下，轻量快照 CPU 与内存占用显著低于 `HeadlessGrid`。
2. 与主视图高亮/折叠状态保持语义一致。

## Phase 6：测试、基准与发布策略

目标：确保正确性、性能和迁移稳定性。

测试计划：

1. 单元测试：visual/logical 双向映射，含软换行、tab、CJK、折叠。
2. 性质测试：映射可逆性与边界稳定性。
3. 集成测试：`Workspace` 多 view 下查询一致性与独立性。
4. 回归测试：旧 API 行为不变。

基准计划：

1. 深位置窗口读取（固定 count，多组 start row）。
2. 高频坐标转换（visual->logical / logical->visual）。
3. minimap 摘要生成吞吐。

发布与迁移：

1. 先发布新增 API（不破坏），再逐步引导宿主迁移。
2. 文档中给出“旧接口 -> 新接口”对照表。
3. 保留旧路径至少一个稳定版本周期。

## 5. 里程碑建议

1. M1：Phase 0 + Phase 1 完成（先可用）。
2. M2：Phase 2 + Phase 3 完成（核心性能与元数据）。
3. M3：Phase 4 + Phase 5 完成（平滑滚动 + minimap 路径）。
4. M4：Phase 6 完成并发布迁移文档。

## 6. 风险与缓解

1. 风险：索引结构增加实现复杂度。  
缓解：先做可替换实现（feature flag 或内部策略切换），保留线性回退路径。

2. 风险：折叠与换行配置联动导致增量更新难度高。  
缓解：定义清晰失效策略，必要时局部分段重建。

3. 风险：新增字段触发调用方编译变更。  
缓解：优先新增可选元数据结构，保持主结构兼容。

4. 风险：轻量 minimap 与主快照语义不一致。  
缓解：建立共享语义测试集，同输入双路径比对。

## 7. 开放问题（实现前需定稿）

1. 平滑滚动子行偏移采用归一化比例还是 cell 偏移。
2. 轻量 minimap 输出是否需要包含“可交互命中信息”。
3. visual row 索引结构是否暴露为独立模块供其他 crate 复用。

