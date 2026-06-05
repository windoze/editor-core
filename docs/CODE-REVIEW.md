# editor-core 设计与实现 Review 报告

> 评审范围：`crates/` 下全部 Rust 工作区（约 7.5 万行），重点为核心引擎 `editor-core`（2.7 万行）、FFI 桥（`editor-core-ffi` / `editor-core-ui-ffi`，1.2 万行）、LSP 集成（`editor-core-lsp`，7.6 千行）与状态/工作区层。
> 评审日期：2026-06-05

## 0. 总体评价

整体工程素养较高：分层清晰、坐标模型有明确文档（`docs/DESIGN.md`）、派生状态（高亮/折叠/诊断）以 patch 方式叠加的设计是合理的解耦。FFI 层的 panic 隔离（`catch_unwind`）、null 检查、`Box` 所有权配对都做得扎实。

但存在若干**架构级冗余**、**热路径性能退化**、**文档与实现脱节**，以及**测试覆盖严重不足**的问题。下面按主题展开，每条尽量给出 `文件:行号` 与严重程度。

---

## 1. 架构层面

### 1.1 文本被存储三份（高）

同一份文档文本同时存在于三个独立结构中：

- `PieceTable`（`storage.rs`：`original_buffer` + `add_buffer`）
- `LineIndex` 内部的 `ropey::Rope`（`line_index.rs:56`，完整副本）
- `LayoutEngine.line_texts: Vec<String>`（`layout.rs:398`，逐行完整副本）

每次编辑都要手动把同一变更施加到三处（`commands.rs:9792` `apply_text_change_to_line_index_and_layout` 中 piece_table、line_index、layout_engine 各更新一遍）。后果：

- **约 3× 内存占用**；
- **三者一致性全靠手工维护**，任何一处遗漏即产生静默错位；
- PieceTable 标榜的 "O(1) undo / 高效编辑" 优势并未被利用——undo 实际由 `UndoRedoManager` 的 `TextEdit` 记录实现（`commands.rs`），而 `ropey::Rope` 自身已能 O(log n) 编辑并提供行索引。**PieceTable 在当前架构里是一层可被移除的冗余**。

建议：以 `ropey::Rope` 为唯一文本真相源（rope 已支持高效插删与行/字节/字符互转），让 layout 只缓存"每行宽度/wrap 信息"而非整行文本副本。

### 1.2 `commands.rs` 单文件 10104 行（高）

`EditorCore`、`CommandExecutor`、`Position`/`Selection`、`UndoRedoManager`、`VisualRowIndex`、坐标转换自由函数全部塞在一个文件；`CommandExecutor` 的单个 `impl` 块约 7000 行（约 2914→9966 行）。这远超可维护阈值，定位与改动风险高。建议拆分为 `model.rs` / `undo.rs` / `coords.rs` / `edit_ops.rs` / `line_ops.rs` / `render_grid.rs`。

### 1.3 封装被破坏：内部结构与字段全部 `pub`（中）

- `lib.rs:129-148` 把 `storage` / `line_index` / `layout` / `intervals` 等实现细节全部 `pub mod` 导出。
- `EditorCore` 的 `piece_table` / `line_index` / `layout_engine` / `interval_tree` 等字段几乎全 `pub`（`commands.rs:1688` 起）。

派生结构之间的不变量（如 visual-row 缓存、三份文本同步）没有任何封装保护，外部一旦直接写 `pub` 字段即破坏一致性，也使内部重构（如 1.1）会成为破坏性 API 变更。

### 1.4 文档与实现脱节（中）

评审中发现多处文档/注释与代码不符，容易误导集成方：

- `DESIGN.md:172-175` 称"many edit paths rebuild the rope from full text"；实际主编辑路径是**增量**更新（`commands.rs:9806/9809`）。文档过时（偏保守）。
- `DESIGN.md:254-258` 与 `:474-476` 称"折叠不随编辑移位，需外部刷新"；实际 `FoldingManager::apply_line_delta`（`intervals.rs:765`）已实现移位。文档过时（偏保守）。
- `lib.rs:14` 称 PieceTable "O(1) insertion/deletion"——实际 `insert` 含 `find_piece_at_offset` 线性扫描（`storage.rs:321`）+ `split_piece` 的 O(piece) char→byte 扫描（`storage.rs:344`），并非 O(1)。
- `lib.rs:124` 称 "Grapheme/word-aware cursor"，但 `DESIGN.md:44/471` 明确把 grapheme 列为 non-goal。两处自相矛盾，需澄清当前真实能力。
- `lib.rs` 文档注释有多处拼写/断词错误（"Subscribe toState changed"、"soft wrappinglayout engine"、"andcode foldingmanagement"）。

---

## 2. 性能

### 2.1 坐标转换在热路径上是 O(行数)（高）

视觉↔逻辑行转换是渲染与光标移动每帧都要做的操作，但实现均为线性：

- `LayoutEngine::logical_to_visual_line`（`layout.rs:559`）对前 N 行 `visual_line_count` 求和；
- `LayoutEngine::visual_line_count`（`layout.rs:552`）遍历全部行；
- `LayoutEngine::visual_to_logical_line`（`layout.rs:570`）线性累加；
- `FoldingManager::logical_to_visual` / `visual_to_logical`（`intervals.rs:656/675`）遍历全部折叠区域。

大文件滚动到尾部时，每次转换都是 O(总行数)。缺少前缀和/累积索引缓存。建议为 layout 维护可增量更新的 visual-row 前缀和（B-tree 或分块）。

### 2.2 `IntervalTree` 的更新是 O(n)（中）

- `insert`（`intervals.rs:173`）插入后 `rebuild_prefix_max_end_from` 重算到末尾；
- `update_for_insertion` / `update_for_deletion`（`intervals.rs:309/325`）遍历全部 interval 并重建前缀数组。

每次文本编辑都需对**每个 style layer** 调一次 `update_for_*`，对语法高亮密集的文档，每次按键成本为 O(interval 数 × layer 数)。查询侧（`query_point`/`query_range`）有 `prefix_max_end` 剪枝，做得不错；瓶颈在更新侧。

### 2.3 行级命令退化为全文 O(n) 重建（中）

`DuplicateLines` / `DeleteLines` / `MoveLines` / `JoinLines` / `ToggleComment` / `ApplyTextEdits` 等在入口处 `piece_table.get_text()` 取全文（`commands.rs:5173/7532/7625/8017/8095/8182`），每次行操作都是 O(文档长度) 的 String 分配。单字符 insert/delete 走的是增量路径（良好），但行级命令未享受到。

### 2.4 列→字节转换 O(column)，外层循环造成 O(n²)（中）

`byte_offset_for_char_column`（`commands.rs:874`）用 `char_indices().nth(column)` 每次 O(column)；在 `ToggleComment` 等对每行调用的循环里（`commands.rs:6387/6425`）最坏退化为 O(n²)。

### 2.5 `command_history` 无界增长且整命令 clone（中）

`execute()` 每条命令都 `command_history.push(command.clone())`（`commands.rs:2962`），历史永不清理；对携带大 `String` 的 `InsertText` 命令做整串 clone。长会话内存持续上涨。需确认该历史是否真有消费者，否则应移除或加上限。

### 2.6 视口/换行参数变更触发全量重排（低）

`set_viewport_width` / `set_wrap_mode` / `set_tab_width`（`layout.rs:415/435/465`）均 `recalculate_all()`，对超大文件 resize 时为 O(全文)。可接受，但可懒加载/仅重算可见窗口。

---

## 3. 正确性问题与风险

### 3.1 `LineIndex` 的占位符方法会损坏内容（中 — 当前为死代码）

`append_line` / `insert_line`（`line_index.rs:73/89`）用 `"x".repeat(line.char_count)` 插入**假的 'x' 字符**而非真实文本；`get_line_mut`（`line_index.rs:141`）永远返回 `None`；`LineMetadata.pieces` 字段从未被填充。经全仓搜索，这些方法在生产路径**未被调用**（仅 `insert_line` 内部调 `append_line`）。因此目前危害为"误导性陷阱 API + 僵尸字段"，但作为 `pub` API 一旦被外部误用即损坏文档。建议删除或私有化。

### 3.2 Undo 无限 coalescing，撤销粒度过粗（中）

`push_step`（`commands.rs:1056`）的合并仅判断 `!text.contains('\n')`（`commands.rs:7725`）与 open-group 是否存在，且只有 Cursor 命令才 `end_group`（`commands.rs:2995`）。后果：连续不换行输入会无限并入同一 undo 组——一次性输入数百字符后单次 undo 会全部撤销；且未校验"两次插入位置是否相邻"，非连续位置的插入也可能被合并。多数编辑器按时间/位置窗口分段，此处缺失。

### 3.3 `FoldingManager::visual_to_logical` 多折叠区域可能错位（中 — 待验证）

`intervals.rs:675` 的循环中 `logical` 在迭代里被累加，却用累加后的 `logical` 与后续 region 的**原始** `start_line` 比较（基准不一致）。存在多个 collapsed 区域时，第二个及之后区域的判断基准已被前面的 hidden 行数污染，疑似产生坐标错位。建议补针对"多个折叠区域 + 视觉→逻辑往返"的单元测试验证。

### 3.4 两套偏移语义并存（中）

`LineIndex` 同时提供"含换行"的 `char_offset_to_position`/`position_to_char_offset`（主用）与"不含换行"的 legacy `line_to_offset`/`offset_to_line`（`line_index.rs:148/167`）。两套语义混用是 off-by-one 与坐标错乱的温床。`position_to_char_offset`（`line_index.rs:206`）对行尾换行固定 `-1`，对 `\r\n` 行会少减 1，CRLF 文档下列夹紧可能落在 `\r` 上。

### 3.5 LSP UTF-16 代理对边界（中）

`utf16_to_char_offset`（`lsp_sync.rs:75`）当目标 offset 落在 emoji（2 个 UTF-16 code unit）中间时，循环加完 `len_utf16()=2` 才停止，会把整个字符计入，char offset 多 1。合法 server 不会给半个代理对，但畸形/越界 `character`（含 `u32::MAX` 截断）会污染 diagnostics/token 区间。`char_offset_for_lsp_position`（`editor.rs:2187`）直接信任该结果。

### 3.6 存储层裸 `unwrap`（低）

`storage.rs:253/278/351` 对 `std::str::from_utf8(...).unwrap()` 依赖"切分总在 char 边界"的不变量，目前成立；但属于以 panic 表达不变量，piece 边界一旦因 bug 落在多字节中间即 panic。

---

## 4. LSP / 集成层

### 4.1 子进程从不被回收，泄漏僵尸进程（高）

`lsp_client.rs:33` 以 `_child: Child` 持有子进程，全程无 `kill()`/`wait()`。`Child::drop` 既不杀进程也不收尸，仅关管道。`exit()`（`editor.rs:969`）只发 LSP `exit` 通知；若 server 崩溃/卡死不响应，进程永久残留。缺少超时强杀兜底。

### 4.2 编辑后到折叠刷新完成的窗口内折叠错位（高）

折叠区域行号是绝对坐标，编辑改变行数后到 `maybe_refresh`（`editor.rs:1947`）完成期间，旧 `FoldRegion` 仍按旧行号对新文本生效，渲染折叠错位。`ReplaceFoldingRegions { preserve_collapsed: true }`（`editor.rs:1937`）按 `(start_line,end_line)` 匹配保留折叠态，编辑后行号变化会丢失/错配用户折叠态。（`apply_line_delta` 能缓解纯换行增减，但 server 异步刷新窗口仍存在。）

### 4.3 diagnostics 缺少版本守卫（中）

语义 token 应用前有版本检查（`editor.rs:1922`），但 diagnostics 走 notification 即时应用、**不带版本检查**（`editor.rs:1664` 附近），用当前 `line_index` 转换。若 diagnostics 对应旧文本，下划线区间错位。两层一致性策略不统一。

### 4.4 `wait_for_response` 丢弃其它在途响应（中）

`lsp_client.rs:126` 阻塞等待目标 `request_id` 时，循环把其它 pending 请求的响应直接丢弃，导致 `LspSession::pending_client_requests` 永久泄漏、对应 `LspEvent::Response` 永不投递。阻塞 `wait_for_response` 与轮询 `poll` 混用时尤其危险。

### 4.5 多 view 通知用单一 change_type（中）

`workspace.rs:2293` 一批同时改了 style+folding+diagnostics 的 edits，只取优先级最高的一个 `change_type` 通知 view；只监听 `DiagnosticsChanged` 的订阅者会漏掉本批诊断更新。

### 4.6 `serde_json::Value` 的代价（中，刻意取舍）

高频 token/diagnostics 下每条消息多次哈希查找 + `clone`，分配压力大；字段类型不符（如 `id` 发成 string）被静默当作"非响应"丢弃，难排查。建议至少把无法识别的消息计入 `on_unhandled_message` 而非静默丢弃。

---

## 5. FFI / ABI

### 5.1 公开签名使用 `usize`，违反 ABI 定宽规则（中）

多个 `extern "C"` 函数签名用 `usize`（如 `editor_core_ffi_editor_state_new(... viewport_width: usize)`，`editor-core-ffi/src/lib.rs:2278`；`start_visual_row: usize` 等），与 `docs/abi-v1-draft.md:37/43`"公开整数只用定宽类型"的约定明确不符，32/64 位主机间 ABI 不稳定。建议改 `uint32_t`/`uint64_t`。

### 5.2 `require_mut`/`require_ref` 返回无界生命周期引用（中，需文档强制）

`editor-core-ffi/src/lib.rs:150`、`editor-core-ui-ffi/src/lib.rs:63` 返回的 `&'a mut T` 生命周期与入参无关联。这是常见 FFI 模式，但 handle 类型未实现 `Send/Sync` 而 `extern "C"` 不阻止跨线程/重入调用——并发或重入同一 handle 会形成别名 UB。`abi-v1-draft.md` 仅"建议"单线程独占，未在显著位置强约束。

### 5.3 数组入口信任调用方 `count`/`out_cap`（低，ABI 固有契约）

`editor-core-ui-ffi/src/lib.rs:527/3413/3700` 等 `from_raw_parts(ptr, count as usize)` 仅检查 null，`count` 超过真实分配即越界读写；`out_cap` 容量校验依赖调用方诚实上报。属正常 ABI 约定，应在文档强调。

> FFI 层的正面评价：`unwrap`/`expect`/`panic!` 均位于 `#[cfg(test)]`；生产入口统一 `catch_unwind` 包裹、null 检查与 `Box` 所有权配对完整、UTF-8 校验齐全。整体安全基线良好。

---

## 6. 错误处理与健壮性

- 生产代码 `unwrap`/`expect`/`panic!` 粗略计数：`editor-core` 42、`editor-core-lsp` 27、`editor-core-render-skia` 25、**`editor-core-ui` 250**、`editor-core-app` 106、`tui-editor` 2。`editor-core-ui` / `editor-core-app` 的 panic 密度偏高，值得专项排查（本次未深入这两个 crate）。
- `UndoRedoManager` 内部大量裸索引 `self.nodes[...]` 与 `.parent.unwrap_or(0)`（`commands.rs:1095-1260`），stale node id 会 panic 而非返回 `Err`。
- 多处以 `expect("checked")` 表达不变量（`commands.rs:1062/1826`、`editor.rs:801`），重构脆弱。

---

## 7. 测试与文档

### 7.1 `commands.rs` 仅 9 个单元测试（高）

10104 行的核心文件只有 9 个 `#[test]`。完全缺测的关键复杂逻辑：

- 多光标同时编辑的偏移移位（`commands.rs:3473`）；
- undo/redo 分支树与 coalescing（`push_step`/`pop_undo_group`/prune）；
- 坐标转换在 CJK/emoji + 折叠 + 软换行叠加下的边界；
- 空文档 / 文件末尾无换行 / 换行处删除；
- `restore_from_snapshot` 往返、矩形选择虚拟列编辑。

这些恰是最易出 bug 的部分。`tests/` 目录虽有较多集成测试（stage1~6、unicode、folding_stability 等），但单元级覆盖与文件复杂度严重不匹配。

### 7.2 文档清理

修正第 1.4 节列出的文档/实现脱节与拼写问题；明确 grapheme 支持的真实现状。

---

## 8. 优先级修复建议

**P0（架构/正确性，影响最大）**
1. 评估移除 `PieceTable`，以 `ropey::Rope` 作为唯一文本真相源，消除三份副本与同步负担（§1.1）。
2. LSP 子进程回收 + 超时强杀（§4.1）。
3. 折叠在编辑窗口内的错位与折叠态保留策略（§4.2）。

**P1（性能/正确性）**
4. layout/folding 视觉行转换改增量前缀和，去除热路径 O(n)（§2.1）。
5. undo 按时间/位置窗口分段，修正撤销粒度（§3.2）。
6. diagnostics 增加版本守卫，与语义 token 统一（§4.3）。
7. 验证并修正 `visual_to_logical` 多折叠区域错位（§3.3）。

**P2（可维护性/健壮性）**
8. 拆分 `commands.rs`（§1.2）；收紧 `pub` 暴露面（§1.3）。
9. 删除/私有化 `LineIndex` 损坏的占位符 API 与僵尸字段（§3.1）。
10. 补齐多光标/undo/坐标/折叠的单元测试（§7.1）。
11. FFI 公开签名改定宽整型；强化别名/线程约定文档（§5.1/5.2）。
12. 行级命令与列→字节转换去除全文/O(n²) 退化（§2.3/2.4）。

---

*本报告由对源码的静态评审得出；标注"待验证"的条目建议以针对性单元测试确认。未深入评审的 crate：`editor-core-render-skia`、`editor-core-ui`、`editor-core-app`、`editor-core-treesitter`、`editor-core-sublime`、`editor-core-diff`。*
