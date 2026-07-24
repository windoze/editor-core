# editor-core 代码审查报告（Rust 侧）

- 日期：2026-07-24
- 范围：仓库 `editor-core` 全部 Rust crate 的设计与实现（**不含 Swift 侧**）
- 方法：按职责分区，8 个独立 reviewer 并行深读源码 + 交叉验证；关键确认项由主审逐条回读源码复核。
- 基线：`cargo check --workspace --all-targets` 通过，`cargo clippy --workspace --lib` 无警告。低级错误几乎没有，问题集中在**逻辑边界、坐标一致性、长会话资源、跨层契约**。
- 附录：另有一份 `codex-review-2026-07-24.md`（Codex 独立完成），本报告第十节对其 8 项发现逐条复核，其中 3 项（fold toggle 下标 bug、ui tree-sitter 异步超时、save_buffer_as 失败回滚）是本轮遗漏、经实证成立的真实缺陷，已并入优先级。

---

## 已修复（2026-07-24）

以下 5 项已在本轮修复并补回归测试，`cargo test -p editor-core -p editor-core-app` 全绿：

| 项 | 修复位置 | 回归测试 |
|----|----------|----------|
| C-2 fold toggle 折错 region | `intervals.rs` `toggle_region_starting_at_line` 改用绝对下标 | `intervals::tests::test_toggle_region_starting_at_line_targets_correct_region` |
| P0-1/C-3 折叠行统计下溢 | 新增 `FoldingManager::collapsed_hidden_line_count`（并集去重），`state.rs` 改用它 + `saturating_sub` | `test_collapsed_hidden_line_count_dedups_nested_regions`、`folding_state_handles_nested_collapsed_regions` |
| P0-2 delete/replace 溢出 | `edit_ops.rs` 两处改 `checked_add` | `delete_with_overflowing_length_is_rejected`、`replace_with_overflowing_length_is_rejected` |
| C-8 save_buffer_as 失败回滚 | `workspace_io.rs` 改为写盘成功后再改 URI/mark_saved | `save_as_failure_leaves_uri_and_dirty_state_unchanged` |
| C-1 tree-sitter 异步测试超时（CI 阻断） | 见下方根因；QoS 加环境变量逃生开关，测试中禁用 | 原 5 个超时测试 + 全 workspace 测试全绿 |
| P1-7 LSP pending 跨文档串响应 | `PendingLspRequest` 加 `uri` 字段；`handle_pending_response` 校验 uri+version；`maybe_refresh` 的 has_pending 判定按 uri；`set_active_document`/`close_document` 调用新增的 `drop_pending_for_inactive_document` 清理 | `editor.rs` `pending_request_tests`（set_active/close 清理） |
| C-5 LSP workspace edit version 校验 | 新增 `workspace_edit_expected_versions` 解析 `documentChanges[].textDocument.version`；`apply_workspace_edit` 应用前对每个已打开文档校验 session 追踪版本，任一冲突则整体拒绝（all-or-nothing，返回 Err → `applied:false`） | `lsp_text_edits` 单测 + `tests/workspace_edit_versioning.rs`（stale 拒绝 / 匹配应用 / null 无约束） |
| P1-4 find_prev 切片破坏正则 | `search.rs::find_prev` 改为在全文 `find_iter` 上按 `m.start()>=limit_byte` 提前终止、`m.end()>limit_byte` 跳过，保留完整尾部上下文；不再在截断切片上跑 regex | `search::tests`（$ 锚点不误命中 / 全文命中 / 贪婪跨界不截断 / 返回边界前最后一个匹配） |
| P1-6 diff CRLF 归一化不一致 | `SideDoc::from_text` 新增 `normalize_line_endings_to_lf`（CRLF+孤立 CR→LF，与 `SnapshotGenerator` 一致）后再计数/切分/存储，模型行数与内容与投影三者对齐 | `tests/model.rs`（CRLF / 孤立 CR 归一化） |
| P1-5 diff view 宽度解耦 | `DiffProjection` 存 `column_widths`；`DiffColumnView::new` 去掉独立 `viewport_width` 参数、改从 `projection.column_width(column)` 派生，杜绝宽度不一致导致的光标行映射静默错位 | `tests/view.rs`（view 宽度取自 projection、窄宽换行下 side↔unified 行映射自洽） |
| C-4 TextDelta last-only 覆盖丢增量 | 新增 `TextDelta::merge`（顺序拼接 edits，无需坐标重映射——因 delta 契约本就是按序应用）；workspace 两处生产点用 `coalesce_delta_slot` 合并而非覆盖 buffer/view 槽；修掉纯 Style 变更 `= None` 误清未消费文本 delta 的 bug | `delta::tests`（合并重放/删除/多 edit/空/group_id）+ `multiview_workspace`（跨编辑合并、Style 不清 delta） |
| C-6 多 view 从共享 executor scratch 派生 | `BufferEntry` 存 `default_view_core`（open_buffer 时捕获，早于任何命令污染 executor）；`create_view` 从它派生（确定性、与调用顺序无关）；新增 `create_view_from(parent)` 显式克隆父 view 配置；`EditorUi::clone_view` 改用 `create_view_from(current)` | `multiview_workspace`（create_view 配置与最近活动 view 无关、create_view_from 克隆配置） |
| C-7 StateManager 与 Workspace 通知语义不一致 | `change_type_for_command` 对齐 Workspace：除 `ScrollTo`/`GetViewport`（None）外所有 view 命令归为 `ViewportChanged`；`execute` 的变更检测区分 `ViewportWidthOnly`（可 no-op）与其他 config 命令（无条件生效），使 tab-key/indentation/auto-pairs/word-boundary 变更能通知订阅者 | `state_manager_view_config_notify`（4 类 config 命令通知 + GetViewport 查询不通知） |
| P3-18 / P3-20（含 P2-17）char wrap 边界 | 重写 `calculate_wrap_points_char_with_tab_width` 为 lazy wrap：只在「段非空且字符真正溢出」时换行。零宽组合符/ZWJ（width=0）永不触发换行、跟随基字符；超宽首字符（>viewport）占首段而不产生空首段；删除 exact-fit eager 分支，消除重复 wrap point。对普通文本换行位置不变（现有 wrap 测试全过） | `layout::tests`（组合符不拆行 / 超宽首字符无空段 / 精确填满无多余空行） |
| P3-13 find_in_files 逐行重编译正则 | 新增 `CompiledSearch`（正则编译一次，`find_all(text)` 复用）；`find_all` 自由函数委托给它保证语义一致；`find_in_files` 在文件遍历前编译一次、每行复用，消除 O(行数×文件数) 的正则编译 + automaton 构建 | `search::tests` + `find_in_files` 现有测试（语义不变） |
| P3-16 diff 行映射 O(rows) 线扫 | `DiffProjection` 构建时预计算 `SideRowMaps`（每侧 unified↔side 行的双向索引，纯 rows 的函数）；两个映射函数改为 O(1) 查表 | `projection_side_by_side`（与线扫参考实现逐行交叉验证）+ 现有 view 往返测试 |
| P3-23 URI `file://localhost/...` 丢根斜杠 | `file_uri_to_path` 只 strip `localhost` 而非 `localhost/`，保留绝对路径的前导 `/` | `lsp_uri`（localhost authority 解出 `/tmp/x`） |
| P3-24 Windows 盘符冒号被编码为 `C%3A` | `percent_encode_path` 不再编码 `:`（RFC 3986/8089 合法路径字符），产出标准 `file:///C:/...` | `lsp_uri`（盘符冒号不编码、仍可解码） |
| P3-25 LSP transport 无输入上限 | `read_lsp_message` 加 `Content-Length` 上限（256 MiB）与 header 行长度上限（64 KiB），防御攻击者控制的巨额分配 | 现有 transport 测试（正常报文不受影响） |
| P3-26 `did_change_many` 失败后版本错位 | 先算 `next_version`、notify 成功后才提交 `self.document.version`，避免发送失败留下超前版本 | 现有 LSP 测试 |
| P3-27 highlight-simple 区间乱序/重叠 | `highlight` 返回前按 `(start,end,style_id)` 排序 + `dedup`，给消费者稳定有序流 | 现有 highlight-simple 测试 |
| P3-29 部分 void FFI 函数绕过 catch_unwind | 新增 `ffi_void` 辅助（`catch_unwind` + 统一 last-error）；6 个 void 函数（sublime/treesitter/lsp disable、mouse_up、unmark_text、set_smooth_scroll_state）改用它，panic 不再冲出 `extern "C"` | 现有 ui-ffi 测试（51 全过） |

**C-1 根因（已实证定位）**：tree-sitter async worker 线程用 `pthread_set_qos_class_self_np(QOS_CLASS_UTILITY)` 降优先级。在本机上该 QoS 让 worker 里的 WASM grammar 构建/解析被调度得极慢，超过测试 2 秒等待窗口 → worker 迟迟发不出 `Processed` → `poll_processing().pending` 恒 true（`requested=Some(1)`、`applied=None`）→ 超时 panic。与 LSP/rust-analyzer 无关（诊断中 `lsp_is_enabled=false`）；底层同步 `TreeSitterProcessor` 加载同一 grammar 仅 1.68s。逐步排查（关闭 QoS 后 1.36s 收敛）确认是 QoS 调度饥饿。修复：`set_current_thread_qos_for_treesitter_worker` 读环境变量 `EDITOR_CORE_DISABLE_TS_WORKER_QOS`，为空才降 QoS；两个 crate 的 `set_test_treesitter_registry` 测试辅助在 spawn worker 前设置该变量（跨 crate 运行时生效，规避 `cfg(test)` 只对当前 crate 生效的问题）。生产构建仍保留 UTILITY QoS。
> 后续可考虑：给 async 测试的等待窗口更长、或让 worker 在超时/错误路径上主动上报状态（Codex #1 的诊断增强建议仍值得做）。

**至此，两份报告中所有正确性问题、主要性能问题、以及有实际价值的 interop/健壮性问题（P3-23~27、P3-29）均已修复。**

**刻意不改（属已文档化设计或改动风险 > 收益）**：
- **P3-19 续行 Tab 制表位原点用整行绝对列**：reviewer 已确认自洽（wrap 计算与渲染同基准，不崩不错位），纯视觉细节；修它需 wrap 计算 + `render_grid` + `snapshot` 三处联动，回归风险高于收益。
- **P3-20 空引擎 `visual_to_logical_line` 返回 `(0,0)`**：是合理默认值，改需破坏返回类型（API break），调用方本就应自行判空。
- **P3-12 Sublime 每次全量重高亮**：需引入 per-line ParseState 增量缓存（重构状态机），改动大且最易引入高亮正确性回归，收益/风险比不划算；作为已知性能限制。
- **P3-14 `VisualRowIndex` 增删行重建 Fenwick**：`Vec::splice`/`drain` 本身就是 O(n) 数组位移，全量重建 Fenwick 只多一个 log 因子；要做到 O(log n) 需换成 order-statistics tree（大改），收益有限。
- **P3-15 `SnapshotGenerator::get_headless_grid` 全量扫描**：唯一生产调用者（diff-view projection）取 `(0, usize::MAX)` 全量，全扫已是最优；主编辑渲染热路径走 `render_grid` 的索引版本，不经此函数。非热点，不改。
- **P3-28 Sublime 健壮性**（`load_by_reference` 不缓存失败、`escape_onig_literal` 未转义 `(?x)` 元字符、branch 预算触顶整篇失败）：均在复杂的高亮状态机内，改动有正确性回归风险，收益/风险比与 P3-12 同类，作为已知限制保留。
- **P3-30 大量解引用外部裸指针的 FFI 入口未标 `unsafe`**：几百处 `extern "C"` 加 `unsafe` 的机械大扫，纯 soundness 标注卫生、无运行时效果、churn 巨大；不改。

---

## 一、总体评价

代码整体质量高于多数同类项目：

- 坐标转换（char / byte / UTF-16）、区间树位移、tree-sitter 增量三元组、LSP 逆序 TextEdit、FFI 的 null 检查与 `Box`/`CString` 配对等**易错点大多处理正确**，且有 round-trip 测试覆盖。
- FFI 层防御性强，未发现可论证的经典 UB（use-after-free / double-free / 越界）。
- headless 架构边界清晰。

需要修复的缺陷分布如下（按类别）：

| 类别 | 代表问题 |
|------|----------|
| 硬 panic / 整数下溢 | 折叠行统计下溢、delete/replace 范围校验溢出、`side_line_kind` 越界 |
| 静默错误结果 | `find_prev` 切片破坏正则、diff 宽度解耦映射错位、diff CR 归一化丢行、LSP 跨文档串响应 |
| 数据丢失 | Sublime `set_active_syntax_by_reference` 失败清空、LSP 零宽诊断丢弃 |
| 长会话资源 / 复杂度 | undo `nodes` 无界增长 + O(n²) 剪枝、sublime 全量重高亮、visual_rows 全量重建 |
| 跨层隐式契约 | `TextDelta.edits` 降序约定被多处依赖但未强制 |

---

## 二、确认的缺陷（建议优先修复）

### P0-1【硬 panic / 逻辑错误】折叠行统计下溢 + 嵌套区间重复计数
- 位置：`crates/editor-core/src/state.rs:897-903`（`get_folding_state`）
- 现象：`collapsed_line_count` 对每个 collapsed region 独立累加 `end_line - start_line`。**嵌套/重叠的 collapsed 折叠区间**（tree-sitter 派生折叠天然嵌套；用户先折外层再折内层）会导致累加值超过 `line_count`：
  - `visible_logical_lines = editor.line_count() - collapsed_line_count`（903 行）在 debug 下 **panic**，release 下回绕成巨大 usize。
  - 即便不下溢，嵌套区间被重复计数，`visible_logical_lines` 语义也已错误。
- 触发：外层 `0..10`、内层 `2..5` 同时折叠，文档 11 行 → `13 > 11`。此为 `EditorStateManager` 公开 API，前端可随时调用。
- 修复方案：不要用区间长度求和，改为按“隐藏逻辑行的并集”计算。可复用 `intervals.rs` 已有的 `collapsed_hidden_ranges`（已做区间合并）或 `is_logical_line_hidden`：

```rust
let hidden = editor.folding_manager().collapsed_hidden_ranges(); // 已合并、不重叠
let collapsed_line_count: usize = hidden.iter().map(|r| r.len()).sum();
let visible_logical_lines = editor.line_count().saturating_sub(collapsed_line_count);
```

（同时把 903 行的裸减法改为 `saturating_sub` 兜底。）

---

### P0-2【范围校验被整数溢出绕过】Delete / Replace 用裸加法
- 位置：`crates/editor-core/src/edit_ops.rs:2273`（delete）、`:2342`（replace）
- 现象：`if start + length > max_offset`。`start` 已校验 `<= max_offset`，但 `length` 是命令入参、无约束。`length` 取极大值（如 `usize::MAX`）时：
  - debug：加法溢出直接 panic；
  - release：回绕成小值，判定为假，**绕过范围校验**继续执行。
- 触发：`EditCommand::Delete { start: 0, length: usize::MAX }`。
- 佐证：同文件 `apply_text_ops`（2577 行）已正确使用 `start.checked_add(delete_len)`——这两处是遗漏，非风格差异。
- 修复方案：

```rust
let end = start.checked_add(length)
    .ok_or(CommandError::InvalidRange { start, end: usize::MAX })?;
if end > max_offset {
    return Err(CommandError::InvalidRange { start, end });
}
```

---

### P1-3【长会话内存无界 + O(n²)】undo 历史 `nodes` 只增不减
- 位置：`crates/editor-core/src/undo.rs`
  - 新节点始终 `new_id = self.nodes.len()` 追加（`push_step_with_mode` 359、`restore_from_snapshot` 967/995）。
  - 剪枝 `remove_leaf_node`（593-627）/ `prune_root_child`（629-699）**只做墓碑化**（`step=None`、清空 children/parent），从不从 `self.nodes` 移除条目。全文件仅 `restore_from_snapshot`（955）整体重建时替换 `nodes`。
  - `find_prunable_leaf`（581-591）每次 `(1..self.nodes.len()).filter(...).min()` 是 O(nodes.len())。达到 `max_undo` 上限后，**每次 push_step 都全量扫描**（线性历史里 `find_prunable_leaf` 恒返回 `None`，随后走 `prune_root_child`），扫描长度随会话增长。
- 现象：`step_count` 有界，但底层 `Vec` 随总编辑次数单调增长（内存泄漏语义）；第 k 次编辑成本 ≈ O(k)，长会话累计 O(编辑数²)。注意“coalescing”并不减少节点——连续打字每个字符仍占一个节点。
- 修复方案：剪枝时真正回收槽位。用 free-list 复用空闲 id（避免 id 重映射），或 `swap_remove` + 维护 id 映射。核心是让 `nodes.len()` 与 `step_count` 同阶。

---

### P1-4【静默错误结果】`find_prev` 在切片上跑正则，破坏尾部上下文
- 位置：`crates/editor-core/src/search.rs:212-229`
- 现象：`re.find_iter(&text[..limit_byte])` 把文本在 `limit_byte` 处截断再喂给 regex。切片的人为结尾使：
  - `$`（multi_line 开启）、`\z`、`\b`、贪婪量词在**错误位置**命中或被截短；
  - 返回全文中并不存在的伪匹配，或把跨越 limit 的匹配截成错误短匹配。
- 触发：查询 `"o$"`，文本 `"foo\nbar"`，`from_char=2`（切片 `"fo"`）→ 返回全文不存在的匹配 `[1,2)`。
- 对照：`find_next` 用 `re.find_at(text, start_byte)` 保留完整上文，语义正确——只有 `find_prev` 有此问题。
- 修复方案：在**全文**上 `find_iter`，用 `m.end() <= limit_byte` 过滤（保留 last），而非切片：

```rust
for m in re.find_iter(text) {
    if m.end() > limit_byte { break; }
    // ... 原有 candidate/whole_word/empty 处理，记录 last
}
```

---

### P1-5【静默错误结果】DiffColumnView 的 viewport_width 与 projection 列宽解耦
- 位置：`crates/editor-core-diff-view/src/view.rs:26`（参数）、`:44`（用它单独建 `CommandExecutor`）、`:106-128`（`cursor_side_visual_row` / `unified_row_for_side_visual_row` / `cursor_unified_row`）
- 现象：`DiffColumnView` 用**自己的** `viewport_width` 建 `EditorCore`，而 `DiffProjection` 用 `per_column_widths` 换行。二者无一致性约束（无 assert / 无文档强约束）。`cursor_side_visual_row()` 用视图宽度算出侧内可视行号，喂给基于 projection 宽度换行的行轴做映射 → **静默错位**（返回合法 `Some(_)` 但语义错误）。
- 触发（已复现）：projection 用 `[3,3]`（长行拆 4 段），视图用 `80`（同行 1 段）；光标移到第 2 条逻辑行，映射落到“第 0 行续段”而非第 4 行。
- 修复方案：`DiffColumnView::new` 直接从 projection 派生该列宽度，不再让调用方传第二个宽度；或至少 `assert_eq!(viewport_width, projection.column_width(column))`。

---

### P1-6【内容丢失 + 脏数据】diff 模型层与投影层 CR/CRLF 归一化不一致
- 位置：`crates/editor-core-diff-view/src/model.rs:259`（`logical_line_count`）、`:861`（`split_logical_lines`）、`:20-25`（`SideDoc::from_text` 存原始文本）；`crates/editor-core-diff-view/src/projection.rs:431-456`（`wrap_side` 用 `SnapshotGenerator::from_text`）
- 根因：模型层按**原始 `\n`** 计数并保存**原始文本**（含 `\r`）；`wrap_side` 的 `SnapshotGenerator` 会把 CRLF 与**孤立 `\r`** 都归一化为 `\n`。
- 现象：
  - **孤立 CR（已复现）**：`"a\rb\n"` → `side.line_count()==1`，但归一化后 2 行。`visual_segments_by_line` 长度只有 1，`get_mut(1)` 返回 `None` → 第二行 `"b"` **被静默丢弃**，行号/对齐全乱。
  - **CRLF（已复现）**：`SideDoc::logical_line(0)` 返回带尾随 `\r` 的 `"a\r"`，而投影 cells 是干净的 `"a"`——直接读 `logical_lines()` 做 gutter/内容的消费方会拿到脏数据。
  - 附带：`wrap_side:447` 的 `assert!(!segments.is_empty())` 是**失效守卫**——归一化只会增加行数，永不触发它，真正该防的“多出行被丢弃”反而被 438 行的 `if let Some` 静默吞掉。
- 修复方案：`SideDoc`/`align_before_after` 先对文本做与 `SnapshotGenerator` 相同的归一化（`normalize_crlf_to_lf`），再计数与切分，保证模型行数、内容、投影三者一致。

---

### P1-7【静默错误结果】LSP pending 请求只带 version 不带 URI → 跨文档串响应 + 刷新饿死
- 位置：`crates/editor-core-lsp/src/editor.rs:214-218`（`PendingLspRequest` 定义）、`792-806`（`set_active_document`）、`1960-1980`（`handle_pending_response`）、`1999-2005`（`maybe_refresh`）
- 现象：`PendingLspRequest::SemanticTokens { version }` / `FoldingRanges { version }` 只记版本号，不记 URI。版本号是**每文档独立**的 `i32`，多文档常从 `version=0` 起，极易撞号。`set_active_document`/`close_document` 切换 active 时**未清理 `self.pending`**：
  - 串响应：文档 A 的迟到 semanticTokens 响应通过 `version == self.document.version` 校验被当作 B 的结果，用 B 的 `line_index` 解析 A 的 token → 高亮/折叠错乱。
  - 刷新饿死：`maybe_refresh` 里 `has_pending_tokens` 因 A 遗留 pending 误判“已有在途请求”，**永不为 B 发起** semanticTokens/foldingRange，直到 B 版本号变化。
- 修复方案：`PendingLspRequest` 增加 `uri` 字段；`handle_pending_response` 同时校验 uri+version；`set_active_document`/`close_document` 清理旧文档相关 pending。

---

### P2-8【数据丢失】Sublime `set_active_syntax_by_reference` 失败路径清空处理器状态
- 位置：`crates/editor-core-ffi/src/lib.rs:3694-3699`
- 现象：先 `mem::replace`/`mem::take` 把 `scope_mapper` 与 `syntax_set` 从 `processor.inner` 搬出（3695-3696），再 `load_by_reference`（3697）。若加载失败 `?` 提前返回，`processor.inner` 已被留下空 `scope_mapper` 与空 `syntax_set`，旧值随 `?` 丢弃 → 一次**无效 reference 调用就静默清空已加载的语法集**，后续高亮全部失效。
- 修复方案：先 `load_by_reference` 成功、再替换；或用不破坏原状态的临时变量，失败时把旧值放回。

---

### P2-9【信息丢失】LSP 零宽度诊断被整条丢弃
- 位置：`crates/editor-core-lsp/src/editor.rs:2298-2303`（结构化 `ReplaceDiagnostics`）、`2243-2247`（样式）
- 现象：`if start == end { continue; }` 对样式层合理（无法下划线），但**结构化诊断也被跳过**。很多服务器发零宽诊断（“缺少分号”定位到一个点、EOF 处错误）→ 这些诊断完全不出现在面板/hover。
- 修复方案：结构化诊断保留零宽项（渲染层给 1 列展示宽度），只在样式层跳过零宽。

---

### P2-10【硬 panic / API 不一致】`side_line_kind` 越界直接 panic
- 位置：`crates/editor-core-diff-view/src/model.rs:103-105`
- 现象：`self.line_kinds[side][logical_line]` 双重下标无边界检查，而同类 `side()`/`logical_line()` 都返回 `Option`。调用方传错 `side`/`logical_line` 即崩。
- 修复方案：返回 `Option<DiffLineKind>`，或在文档中明确 panic 契约。

---

### P2-11【正确性 / 中途失败污染】tree-sitter 多编辑 delta 部分失败留下脏状态
- 位置：`crates/editor-core-treesitter/src/processor.rs:332-381`
- 现象：`apply_text_delta_incremental` 逐条 apply，每条在循环末尾就 `text.replace_range` + `line_index.delete/insert`（370-373）。若 `edit[1]` 校验失败（348-353）返回 `Err`，`edit[0]` 的改动已落到 `text`/`line_index`/`tree.edit`，但 `last_synced_version` 未更新（565 才设）→ 内部脏。
- 影响：`process()` 主路径能靠全文重跑自愈；但走**后台线程 delta-only API**（`full_text=None`）时进入“脏 + 无法自愈”，后续正确 delta 也会因 `char_count` 校验持续 `DeltaMismatch`。
- 修复方案：先全部校验、再统一 apply，保证失败不留副作用。

---

## 三、性能 / 复杂度（非正确性，但影响大文件与长会话）

- **P3-12 Sublime 每次 `process()` 全量重高亮**：`crates/editor-core-sublime/src/processor.rs:94-96` 无 version 记录，且每次 `Highlighter::new` 重建 `pattern_cache` / `dynamic_regex_cache`（`engine.rs:76-89`）。对比 tree-sitter 有 `last_processed_version` 跳过。几千行文件每次按键 O(文档长度 × patterns) + 动态正则重编译。建议：per-line ParseState 缓存 + 按 version 跳过，或至少把 cache 挪到 `SublimeProcessor`（以 `Arc<SublimeSyntax>` 为失效键）。
- **P3-13 搜索每次调用重编译正则 + 重建全量 `CharIndex`**：`search.rs:154-267`。若上层反复 `find_next` 遍历匹配，退化 O(匹配数 × n)。`is_match_exact` 内部再调 `find_next`，逐键调用即每键全量重建。建议缓存 `Regex` + `CharIndex`（随文本版本失效）。
- **P3-14 `VisualRowIndex` 增删行整棵重建 Fenwick**：`visual_rows.rs:68-69, 82-84` 每次 `FenwickTree::from_values`（O(n log n)）+ `splice`/`drain`（O(n)）。逐行编辑退化近 O(n²)。`set_line_visual_count` 已是 O(log n)。建议增量更新或合并批量增删。
- **P3-15 `SnapshotGenerator::get_headless_grid` 每次全量扫描逻辑行**：`snapshot.rs:413` 从行 0 遍历，O(总行数)。而 `render_grid.rs` 的 styled 版本已用 `VisualRowIndex::span_for_visual_row` 定位起点。建议非 styled 版本同样走 visual row index。
- **P3-16 diff 行映射线性扫描**：`projection.rs:52-88` 两个映射函数全量遍历 `rows`，`view.rs:126-128` 连锁触发。大 diff + 频繁光标移动 O(行数)。可缓存前缀计数。

---

## 四、布局 / 坐标细节（确认，多为中低）

- **P2-17 重复 wrap point：exact-fit + wrap_indent 使续行首字符再溢出**（**建议一并修**）
  - 位置：`crates/editor-core/src/layout.rs:290-315`（`calculate_wrap_points_char_with_tab_width`）
  - 现象：精确填满分支（306-315）在 `char_index+1` 压入 wrap point 并把 `x` 重置为 `wrap_indent_cells`；下一次迭代若 `wrap_indent_cells + ch_width > viewport_width` 溢出分支又在**同一 char_index** 压入 wrap point。结果 `wrap_points` 出现重复项：`visual_line_count` 多算 1（多一条只有缩进的空视觉行），`logical_position_to_visual`（620-627）对同一边界 `wrapped_offset` 累加两次 → 光标视觉行号 off-by-one。
  - 触发：`WrapIndent::SameAsLineIndent` + 行首若干空格 + 窄 viewport + 边界处“窄字符精确填满 + 紧跟 CJK/宽字符”。启用 wrap indent 时较易命中。
  - 修复方案：溢出分支压入前判重（若 `wrap_points.last() == Some(char_index)` 则跳过），或在 exact-fit 分支重置 `x` 后正确带入下一字符宽度判断，避免同一边界两次触发。
- **P3-18 按 char 而非 grapheme 换行**：`layout.rs:286-316`。组合符/ZWJ emoji/旗帜/变体选择符可能在换行点被拆开（零宽组合符尤其在 exact-fit 后被单独换行）。CJK/emoji 场景视觉重影。属 headless 层字形簇边界缺失。
- **P3-19 续行 Tab 制表位原点用整行绝对列、忽略 wrap 缩进**：`layout.rs:287` / `render_grid.rs:89-100` / `snapshot.rs:464-473`。换行与渲染两侧同基准故不崩，但续行 tab 视觉对齐与“视觉行从 0 起算”不一致。
- **P3-20 极窄视口（单字符宽 > viewport）在 char_index 0 产生空首段**：`layout.rs:290-297`；`空引擎 visual_to_logical_line 返回 (0,0)`：`layout.rs:580-587`。边界易误用。

---

- **P3-20b diff `unreachable!()` / `debug_assert` 依赖上游 diff 输出不变式**：`crates/editor-core-diff-view/src/model.rs:199, 241`（`align_before_after` 内两处 `unreachable!()`，依赖 imara-diff 分组严格交替）与 `:247-248, 825`（`debug_assert_eq!(cursor, hunk.end)` 仅 debug 生效）。当前 imara-diff 满足，但上游行为变化或 hunk 合并产生意外顺序会直接 panic；release 下 cursor 与 hunk.end 不符则静默产生错位 alignment（叠加 P1-6 行数口径不一致时更危险）。建议：把不变量在 release 下也做防御性处理（返回 Err 或退化路径），而非 `unreachable!`。
- **P3-20c diff 空/无 hunk patch 静默视作“无变化”**：`crates/editor-core-diff-view/src/model.rs:288-361`（`apply_unified_patch`）。空 patch 返回 after==file 是设计意图（有测试），但“传入了 preamble 却不含任何 `@@` hunk 头”同样静默返回无变化（`seen_hunk` 恒 false），调用方可能期望这是错误。建议对“非空但无 hunk 头”的 patch 返回 Err。

---

## 五、跨层隐式契约（脆弱点，建议加固）

- **P2-21 `TextDelta.edits` 降序约定被多处依赖但未强制**：
  - LSP `text_changes_for_text_delta`（`workspace_sync.rs:452-470`）顺序 `calc.apply_change`，**依赖 edits 按 start 降序**才不互相干扰。
  - workspace `apply_char_offset_delta`（`workspace.rs:297-323`）把其他 view 光标按 delta 位移，同样对 edits 的坐标基准有隐式假设。
  - undo 多 step 组拼接的 delta 是否构成“可顺序整体应用”的统一 delta（`edit_ops.rs:100-125`）也需验证。
  - 当前内核在 `edit_ops.rs` 统一 `sort_by_key(Reverse(start))` 且有测试，但这是**跨 crate 隐式契约**，某条路径改成升序会静默破坏 LSP 增量同步与多 view 光标位移。
  - 建议：在 `TextDelta` 上以文档 + 构造函数不变量（或 debug_assert）显式固化“降序、区间不重叠”，消费方不再各自假设顺序。
- **P3-22 `close_document` 用 `extra_documents.iter().next()` 选下一个 active**：`editor.rs:816-819`，HashMap 迭代顺序不确定；关闭 active 且无其他文档时 `self.document` 仍指向已关闭 URI。建议显式选择或置空态。

---

## 六、interop / 健壮性（低）

- **P3-23 URI：`file://localhost/...` 反解丢根斜杠**：`lsp_uri.rs:79-80`，`strip_prefix("localhost/")` 把前导 `/` 也吃掉，Unix 下变相对路径。应 `strip_prefix("localhost")` 保留其后 `/`。
- **P3-24 URI：Windows 盘符冒号被编码成 `C%3A`**：`lsp_uri.rs:31-42`，本地能 round-trip，但许多 LSP 服务器期望 `file:///C:/...`，可能匹配失败。建议盘符冒号不编码。
- **P3-25 LSP transport 无输入上限**：`lsp_transport.rs:36/50/58`，`Content-Length` 无上限直接 `vec![0u8; len]`，header 行无长度上限。恶意/异常服务器可致大内存分配。建议加合理上限。
- **P3-26 `did_change_many` 先自增 version 再 notify**：`editor.rs:730/750`，notify 失败会造成版本永久错位（连接通常已死，影响有限）。建议发送成功后再提交版本号。
- **P3-27 highlight-simple 区间未排序去重**：`highlight-simple/src/lib.rs:61-104`，多规则结果直接 push，产生重叠/乱序区间，依赖下游 `ReplaceStyleLayer` 消歧。
- **P3-28 Sublime 边界健壮性**：`load_by_reference` 不缓存解析失败（`set.rs:70-99`，反复 I/O + 解析）；`escape_onig_literal` 未转义 `(?x)` 模式下的 `#`/空白（`engine.rs:1272-1285`）；branch/zero-width 循环预算触顶后整篇 `Err` 而非局部降级（`engine.rs:117/139/222-225`）。

---

## 七、FFI soundness 卫生（非运行时缺陷，建议统一）

- **P3-29 部分 `void` 返回的 FFI 函数绕过 `catch_unwind`**：`editor-core-ui-ffi/src/lib.rs` 中 `..._mouse_up`(3490)、`..._unmark_text`(3355)、`..._sublime_disable`(770)、`..._treesitter_disable`(937)、`..._lsp_disable`(1005)、`..._set_smooth_scroll_state`(2019) 直接 `&mut *ui` 调方法，无 `ffi_catch`。若内部 `Mutex` 中毒，`lock().unwrap()` panic 会冲出 `extern "C"`（edition 2024 下是定义良好的 abort，非经典 UB，但仍是可从正常调用触发的进程终止，且与同文件其他函数不一致）。建议统一 `catch_unwind` 包裹。
- **P3-30 大量解引用外部裸指针的入口是 `pub extern "C" fn` 而非 `unsafe extern "C" fn`**：如 `editor-core-ffi` 的 `..._execute_json`(2328)、`..._workspace_open_buffer`(2589)，ui-ffi 的 `..._insert_text`(2060)、`..._mouse_down`(3404) 等，把 unsafe 前提藏在安全签名后（同 crate 另有一批已正确标注 `unsafe extern "C"`）。标注不一致，属 soundness 卫生。建议统一加 `unsafe` + `# Safety` 文档。

---

## 八、明确排查为“正确/无问题”的点（供参考，避免重复排查）

- char/byte/UTF-16 转换、`LineIndex` round-trip（含 `你好/🌍`）、`intervals.rs` 六种相交位移分类 + 降序应用 + `debug_assert_sorted`、folding `logical↔visual` 映射、`visual_rows` Fenwick 对 0 计数隐藏行的处理。
- tree-sitter `InputEdit` 三元组（byte）与 `advance_point`（byte column）一致；旧切片校验先于 `tree.edit`（单条 edit 失败不污染树）；include/extends/变量的环检测齐备。
- anchor bias（Left/Right）位移、snippet 解析深度上限与钳制、多光标 insert 偏移累积（选区经 normalize 后不变负）、line_ops 各减法均在守卫后。
- LSP `utf16↔char` round-trip、`apply_text_edits` 逆序、`wait_for_response` 用 method+id 区分请求/响应、进程 Drop→terminate/reap、semantic tokens delta splice 前的越界校验。
- diff 核心：hunk 分类、对齐单元、side-by-side/unified 投影、`apply_unified_patch` 头解析与 `count==0`/`start==0`/溢出/no-newline 处理，在 LF 文本下正确且测试充分。
- FFI：`build_viewport_blob` 的 `checked_mul/add` + 末尾长度自检、`copy_blob_to_output` 两段式查询、`require_utf8_bytes` 的 len==0 短路、内嵌 NUL 转义、所有 caller `len` 经 `ffi_count_to_usize` 校验。未发现可论证的经典 UB（前提是 Swift 侧遵守指针有效/单次释放/单线程访问同一句柄的契约）。

---

## 九、修复优先级建议

1. **立即修（会 panic 或返回错误结果，且可从公开 API 触发）**：P0-1、P0-2、P1-4、P1-5、P1-6、P1-7、P2-10、P2-17。
2. **尽快修（数据丢失 / 自愈失败 / 长会话退化）**：P1-3、P2-8、P2-9、P2-11。
3. **加固契约与性能**：P2-21、P3-12 ~ P3-16。
4. **健壮性 / 卫生（可批量处理）**：P3-18 ~ P3-30。

> 说明：本轮仅审 Rust 侧。P2-21（TextDelta 顺序契约）、以及 FFI 的跨边界字符串生命周期/单线程访问契约，需要在 Swift 侧一并核对后才能完全闭环。

---

## 十、对 `codex-review-2026-07-24.md` 的复核

Codex 独立提交了一份 Rust 侧 review（8 项）。我对每项逐条回读源码、必要时实测复现。结论如下——**全部 8 项成立**，其中 3 项是本报告此前遗漏、值得重点补上的真实缺陷。

| Codex 项 | 复核结论 | 与本报告关系 |
|----------|----------|--------------|
| #1 ui tree-sitter 异步测试稳定超时 | **实测复现**（见下） | 本报告未覆盖 `editor-core-ui`，**新增缺陷** |
| #2 `toggle_region_starting_at_line` 相对下标写回 | **实测复现的确定性高危 bug** | 本报告 reviewer 未覆盖此函数，**新增高危缺陷** |
| #3 `get_folding_state` 重叠/嵌套统计下溢 | 成立 | 与本报告 **P0-1 完全一致**（互相印证） |
| #4 `TextDelta` last-only 覆盖丢增量 | 读码成立 | 与 P2-21 主题相关、角度不同，**补充** |
| #5 LSP workspace edit 忽略 version | 读码成立 | 本报告 LSP 部分未覆盖，**新增缺陷** |
| #6 多 view 从共享 executor scratch 派生默认配置 | 读码成立 | 本报告未覆盖，**补充** |
| #7 `EditorStateManager` 与 Workspace 通知语义不一致 | 读码成立（与本报告已记录的 `CursorCommand::is_mutating` 语义边界同源） | **补充** |
| #8 `save_buffer_as` 先改 URI 再写盘 | 读码成立 | 本报告未覆盖 `editor-core-app`，**新增缺陷** |

### 需并入“立即修”的三项（本报告此前遗漏）

**C-2【已实证 · 高危 · 确定性】`FoldingManager::toggle_region_starting_at_line` 折错 region**
- 位置：`crates/editor-core/src/intervals.rs:842-855, 859-869`
- 根因：842 行 `regions[idx..].iter().enumerate()` 的 `i` 是**切片相对下标**，854 行 `best_source = Some((is_user, i))` 存的是相对下标，而 859-869 行把它当**绝对下标**做 `user_regions.get_mut(idx)` / `derived_regions.get_mut(idx)`。只要目标 region 不是该 source 数组的首个（`binary_search` 得到的起点 `idx > 0`），就会切换错误的 region。
- 实证：构造 user regions start=`{1,5,10}`，调用 `toggle_region_starting_at_line(10)`，实际折叠的是 start=1 的 region（断言 `collapsed==[10]` 得到 `[1]`，测试失败）。这是**多 fold 文件里 gutter/光标折叠的常见路径**，属确定性用户可见 bug，优先级应等同 P0。
- 修复：保存绝对下标 `let absolute_i = idx + relative_i;`，`best_source` 存 `absolute_i`。

**C-1【已实证 · 工程阻断】`editor-core-ui` tree-sitter 异步测试稳定超时**
- 位置：`crates/editor-core-ui/src/lib.rs:6173-6185`（`wait_for_async_processing`，2s 超时 panic）、`poll_processing`(2725)、worker 状态字段(251-258)
- 实证：`cargo test -p editor-core-ui --lib ui_treesitter_highlight_and_folding_roundtrip` 稳定 FAILED，panic 于 6181 `timeout waiting for async processing`。受影响的还有 `ui_gutter_click_toggles_fold_state` 等共 5 个测试。测试用内置 `set_test_treesitter_registry`（加载 `.wasm` grammar），不依赖网络。
- 影响：`cargo test --workspace --all-targets` 不绿，无法作为合并前门禁，会掩盖后续回归。**这是当前最直接的工程阻断项。**
- 根因方向（与 Codex 判断一致）：worker 失败/完成后 UI 侧 `pending` 不收敛、`applied_version` 未推进，或 `Error`/`NeedFullSync` 路径未传播。建议先按 Codex #1 的建议给超时前打印 `requested_version`/`applied_version`/`last_update_mode`/channel 状态，再定位是 worker 未完成还是 pending 判定不收敛。
- 备注：需进一步确认是否与本机 wasm 运行时相关，但无论如何“worker 失败时 pending 永不收敛 + 硬超时”本身就是应修的收敛/诊断缺陷。

**C-8【读码确认 · 中】`save_buffer_as` 失败留下错误路径状态**
- 位置：`crates/editor-core-app/src/workspace_io.rs:82-92`
- 根因：88 行先 `set_buffer_uri(new_path)`，90 行才 `save_buffer`（内部 `write_utf8_file_atomic` 可能失败）。写盘失败时 URI 已改、文件未写成，dirty 状态挂在错误路径上。
- 修复：all-or-nothing —— 先写盘成功、再更新 URI 与 clean point；或失败时回滚 URI。

### 其余项的处理建议

- **C-3 = 本报告 P0-1**：同一 bug，合并处理即可。
- **C-4（delta last-only）/ C-6（多 view scratch 派生）/ C-7（通知语义不一致）**：均属跨模块契约问题，建议纳入本报告第五节“跨层契约加固”一并处理。C-4 与 P2-21 建议在同一次“重新定义 TextDelta 投递契约”的改动中解决（顺序 + 是否 coalesce/queue 一起定清）。
- **C-5（LSP workspace edit version 校验）**：应纳入 P1 级 LSP 修复，与本报告 P1-7（pending 请求带 URI）同属“LSP 状态正确性”，建议一并处理并补 version-mismatch 拒绝的测试。

### 综合后的“立即修”清单（更新）

在本报告第九节基础上追加：**C-2（fold toggle 折错，高危）、C-1（ui 异步超时，CI 阻断）、C-8（save as 回滚）**。其中 C-2 与 C-1 建议置于最前——前者是确定性用户可见错误，后者阻断全量测试门禁。
