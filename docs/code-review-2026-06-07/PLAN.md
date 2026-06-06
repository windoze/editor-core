# CODE-REVIEW 落地方案

来源：`docs/CODE-REVIEW.md`，并结合当前代码抽查结果制定。

## 目标

- 消除高风险正确性问题，优先保证 LSP 进程生命周期、折叠/诊断版本一致性、undo 粒度可控。
- 降低核心热路径的 O(n) / 全文分配，尤其是视觉行映射、行级命令、区间更新。
- 为后续移除 `PieceTable`、收紧 API 暴露、拆分 `commands.rs` 建立可验证的迁移路径。
- 补齐针对多光标、undo、折叠、Unicode/LSP 坐标、FFI ABI 的回归测试。

## 现状校验

- 文本当前确实存在三份：`EditorCore.piece_table`、`EditorCore.line_index` 中的 `ropey::Rope`、`LayoutEngine.line_texts`。
- 主编辑路径 `apply_text_change_to_line_index_and_layout` 已对 `LineIndex` 和 `LayoutEngine` 做增量更新，不是全文重建。
- `EditorCore` 已有 `VisualRowIndex` 缓存，公开的 `EditorCore::visual_line_count`、`visual_to_logical_line`、`get_headless_grid_styled` 会走该缓存；但缓存每次编辑/视图变化整体失效重建，且底层 `LayoutEngine` / `FoldingManager` 的转换 API 仍是线性实现。
- `commands.rs` 的核心实现仍集中在一个 1 万行文件中，拆分和封装需要分阶段做，不能和文本存储大改混在一个 PR。
- FFI 层已有部分 typed API 使用定宽整型，但 `editor-core-ffi` 的若干公开函数仍暴露 `usize`。

## 优先级总览

| 阶段 | 目标 | 主要问题 | 风险 | 验收 |
| --- | --- | --- | --- | --- |
| P0-A | 快速止血正确性 | LSP 子进程、diagnostics 版本、`wait_for_response`、折叠刷新窗口 | 中 | LSP 专项测试通过，无僵尸进程/错位诊断回归 |
| P0-B | 建立文本真相源迁移基础 | 三份文本、破坏性 `LineIndex` API、文档脱节 | 高 | 新 `TextBuffer`/Rope 适配层可跑通现有测试 |
| P1 | 热路径性能 | 视觉行映射、行级命令全文分配、列字节转换、interval 更新 | 中 | 大文件基准有明确下降，现有行为不变 |
| P2 | 可维护性和 ABI | 拆分 `commands.rs`、收紧 `pub`、FFI 定宽、错误处理 | 中 | API 变更有文档，workspace 测试通过 |
| P3 | 测试与文档收口 | 缺测、文档不符、panic 专项 | 低 | `cargo test`、`cargo clippy`、文档一致 |

## P0-A：LSP 与异步派生状态止血

### 1. 回收 LSP 子进程

涉及文件：`crates/editor-core-lsp/src/lsp_client.rs`、`crates/editor-core-lsp/src/editor.rs`。

实施步骤：

1. 将 `LspClient` 字段 `_child: Child` 改为 `child: Child`，实现显式 `shutdown` / `terminate` 方法。
2. `shutdown` 先发送 `shutdown` 请求并等待短超时，再发送 `exit`；若超时或 I/O 断开，调用 `child.kill()`。
3. 无论正常退出还是强杀，都调用 `child.wait()` 回收，避免僵尸进程。
4. 实现 `Drop for LspClient` 作为兜底：尝试 `try_wait`，仍在运行则 `kill` + `wait`。
5. `LspSession::exit` 改为走该生命周期方法，保留当前只发 `exit` 的行为作为优雅路径的一部分。

测试：

- 新增 `crates/editor-core-lsp/tests/lsp_process_lifecycle.rs`，用可控子进程模拟不响应 shutdown 的 server，验证 drop 后进程退出。
- 增加响应 shutdown 的 happy path 测试，验证不会强杀已退出进程。

验收标准：

- `cargo test -p editor-core-lsp` 通过。
- 手动运行一个会忽略 stdin 的 server，销毁 `LspSession` 后无残留子进程。

### 2. diagnostics 增加版本守卫

涉及文件：`crates/editor-core-lsp/src/editor.rs`、`crates/editor-core-lsp/src/lsp_sync.rs`。

实施步骤：

1. 在处理 `textDocument/publishDiagnostics` 时读取 `params.version`。
2. 若 server 提供版本且版本不等于 `self.document.version`，丢弃该 notification，但仍推送普通 `LspEvent::Notification` 供上层观察。
3. 若版本缺失，按 LSP 兼容策略接受，但记录到 `on_unhandled_message` 或新增内部标记，便于宿主排查旧 server 行为。
4. 让 diagnostics 与 semantic tokens / folding ranges 使用一致的版本策略。

测试：

- 扩展 `crates/editor-core-lsp/tests/diagnostics_processing_edits.rs` 或新增 session 级测试：旧版本 diagnostics 不产生 `ReplaceDiagnostics` / `ReplaceStyleLayer`。
- 添加无版本 diagnostics 仍可应用的兼容测试。

验收标准：

- 旧文本 diagnostics 不会用当前 `LineIndex` 转换出错位区间。
- `cargo test -p editor-core-lsp --test diagnostics_processing_edits` 通过。

### 3. 修复 `wait_for_response` 丢弃其它在途响应

涉及文件：`crates/editor-core-lsp/src/lsp_client.rs`、`crates/editor-core-lsp/src/editor.rs`。

实施步骤：

1. 在 `LspClient` 内增加 `deferred_inbound: VecDeque<LspInbound>` 或 `pending_responses: BTreeMap<u64, Value>`。
2. `wait_for_response` 遇到非目标 response 时不能丢弃：若是 response，缓存；若是 notification，缓存到 `deferred_inbound`，供后续 `try_recv` 返回。
3. `try_recv` 优先返回缓存的 inbound，再读 channel。
4. 对 malformed response id（string/null）调用 `on_unhandled_message` 的上层路径，避免静默丢弃。

测试：

- 新增 LSP client 单元/集成测试：先收到 id=2，再收到 id=1；等待 id=1 后，后续 poll 仍能拿到 id=2。
- 覆盖 server->client request 在等待期间仍会被自动响应。

验收标准：

- `pending_client_requests` 不因阻塞等待其它请求而永久泄漏。

### 4. 折叠刷新窗口与折叠态保留

涉及文件：`crates/editor-core/src/intervals.rs`、`crates/editor-core/src/processing.rs`、`crates/editor-core-lsp/src/editor.rs`。

实施步骤：

1. 将 LSP 派生折叠区间标记为“版本化派生状态”：`ProcessingEdit::ReplaceFoldingRegions` 携带 `document_version` 或由调用方在应用前传入版本。
2. 对编辑后到 LSP 刷新完成之间的旧派生 folding regions，采用两步策略：
   - 文本编辑发生时继续用 `apply_line_delta` 平移，减少短窗口错位。
   - 若有 pending folding request 且版本落后于当前文档，则应用结果前丢弃。
3. 折叠态保留不再只按 `(start_line, end_line)` 精确匹配。引入稳定匹配策略：优先匹配同一 start 行附近、相同 kind/placeholder、范围有较高重叠度的 region。
4. 用户手动 fold 与派生 fold 分开保留：用户 fold 继续随编辑平移，派生 fold 按版本刷新。

测试：

- 在 `crates/editor-core/tests/folding_stability.rs` 增加“多个 collapsed region + 编辑插入/删除 + 刷新派生 folds”用例。
- 在 `editor-core-lsp` 增加旧版本 folding response 被丢弃的测试。

验收标准：

- 编辑后旧 folding response 不覆盖新文本。
- 用户已折叠状态在小范围行号漂移后仍能保留。

## P0-B：文本真相源迁移

### 5. 引入单一文本访问抽象

涉及文件：`crates/editor-core/src/line_index.rs`、`crates/editor-core/src/commands.rs`、`crates/editor-core/src/layout.rs`。

实施步骤：

1. 新增内部模块 `text_buffer.rs`，以 `ropey::Rope` 为唯一文本存储，提供当前核心需要的 API：
   - `len_chars`、`len_bytes`、`line_count`
   - `insert/delete/get_text/get_range/get_line_text`
   - `position_to_char_offset/char_offset_to_position`
   - `char_offset_to_byte_offset/byte_offset_to_char_offset`
2. 先让 `TextBuffer` 包装现有 `LineIndex`，不立即删除 `PieceTable`，把调用点从直接访问 `piece_table` / `line_index` 收束到内部方法。
3. 为 `TextBuffer` 建立与现有 `LineIndex` 同语义的测试，覆盖空文档、末尾无换行、末尾有换行、CJK、emoji、CRLF 输入归一化。
4. 将 `EditorCore::get_text`、`char_count`、行文本读取优先改为走 `TextBuffer`，保留 `PieceTable` 作为影子一致性校验。

验收标准：

- 行为不变，`cargo test -p editor-core` 通过。
- 新增 debug-only 一致性断言：每次编辑后 `piece_table.get_text() == text_buffer.get_text()`。

### 6. 移除 `LayoutEngine.line_texts` 文本副本

涉及文件：`crates/editor-core/src/layout.rs`、`crates/editor-core/src/commands.rs`。

实施步骤：

1. 将 `LayoutEngine` 改为只保存每行 `VisualLineInfo` 和换行参数，不保存 `line_texts`。
2. `from_lines/add_line/update_line/insert_line` 保留接收文本以计算布局，但不存储文本。
3. `recalculate_all` 改为由调用方传入行文本迭代器，或提供 `recalculate_all_from_lines`。
4. `set_viewport_width/set_wrap_mode/set_tab_width/set_wrap_indent` 不再内部全量重排，而是标记 `needs_reflow` 或由 `EditorCore` 统一拿 Rope 行文本重排。
5. 在 `EditorCore` 中集中维护“文本变更后更新 layout”的路径，禁止外部直接写 layout。

测试：

- 扩展 `crates/editor-core/tests/incremental_viewport_consistency.rs`，比对编辑后 viewport 与从全文重建的 editor 输出一致。
- 增加 resize/wrap/tab width 变化后的快照一致性测试。

验收标准：

- 删除 `LayoutEngine.line_texts` 后所有快照测试通过。
- 内存占用至少减少一份逐行文本副本。

### 7. 分阶段废弃 `PieceTable`

涉及文件：`crates/editor-core/src/storage.rs`、`crates/editor-core/src/commands.rs`、`crates/editor-core/src/lib.rs`。

实施步骤：

1. 先停止在新代码中直接访问 `EditorCore.piece_table`，所有文本读取/编辑走 `TextBuffer`。
2. 将 `PieceTable` 改为内部兼容组件，隐藏在 `storage` 模块，不再作为 `EditorCore` 公共字段。
3. 在一个过渡期内保留 `pub use storage::PieceTable`，但标记为 deprecated，明确不会作为主存储继续演进。
4. 删除 `apply_text_change_to_line_index_and_layout` 中对三处结构的手动同步，改成：先应用 `TextBuffer`，再根据 edit delta 更新 layout、styles、folding、selection。
5. 所有测试稳定后，删除 `EditorCore.piece_table` 字段；需要全文的路径改为 `TextBuffer::get_text()`。

风险控制：

- 这是最大破坏性改动，必须拆成多个 PR。
- 若外部已直接访问 `EditorCore.piece_table`，需先收紧字段可见性并提供替代 API，再移除。

验收标准：

- `EditorCore` 内只有一份完整文本内容。
- `storage.rs` 不再处于主编辑路径；若保留，只作为历史/实验模块。

## P1：性能优化

### 8. 视觉行映射改为可增量更新索引

涉及文件：`crates/editor-core/src/commands.rs`、`crates/editor-core/src/layout.rs`、`crates/editor-core/src/intervals.rs`。

现状说明：`EditorCore` 已有 `VisualRowIndex`，但每次失效后全量重建；`LayoutEngine::logical_to_visual_line`、`visual_to_logical_line`、`FoldingManager` 相关转换仍是线性。

实施步骤：

1. 将 `VisualRowIndex` 从 `commands.rs` 抽到独立模块 `visual_rows.rs`。
2. 内部结构从 `Vec<VisualRowSpan>` 全量重建改为分块前缀和或 Fenwick tree：每个逻辑行存 `visible`、`visual_line_count`、`prefix_sum`。
3. 编辑时只更新受影响行的 wrap count 和可见性区间；折叠 toggle 时只更新被隐藏/显示区间。
4. `EditorCore::visual_line_count`、`visual_to_logical_line`、`logical_position_to_visual` 统一使用该索引。
5. 废弃或改造 `LayoutEngine` / `FoldingManager` 的线性转换 API，避免测试和外部继续依赖慢路径。

测试与基准：

- 新增大文件基准：10 万行，滚动到尾部反复 `visual_to_logical_line` / `logical_position_to_visual`。
- 增加折叠 + 软换行 + CJK/emoji 的往返测试。

验收标准：

- 首次构建 O(n)，单行编辑/普通光标移动不触发全量重建。
- 大文件尾部坐标转换从 O(n) 降到 O(log n) 或接近 O(1) 分块查询。

### 9. 行级命令避免全文 `get_text()`

涉及文件：`crates/editor-core/src/commands.rs`、`crates/editor-core/src/search.rs`。

实施步骤：

1. 梳理 `DuplicateLines`、`DeleteLines`、`MoveLines`、`JoinLines`、`ToggleComment`、`ApplyTextEdits` 中的全文读取。
2. 对只需要“文档是否以换行结尾”的路径，改为检查最后一个 char 或最后一行状态，不分配全文。
3. 对按行操作的文本片段，用 `TextBuffer::get_range` 或行迭代拼接目标块，不读全文。
4. 搜索类命令若仍需全文匹配，保留全文路径；但需明确其性质是搜索命令，不归入行级编辑热路径。
5. `ApplyTextEdits` 改为先排序/合并 edit ranges，再按范围读取删除文本，不再为每次应用分配全文。

测试：

- 扩展 `crates/editor-core/tests/line_ops.rs`、`comment_toggle.rs`，覆盖末尾无换行、多光标、Unicode 行。
- 增加一个性能回归测试或 benchmark，统计大文件行操作不调用全文构造路径。

验收标准：

- 普通行级编辑只分配受影响文本。
- 现有行操作行为与 VSCode-like 选择映射保持一致。

### 10. 优化列到字节转换

涉及文件：`crates/editor-core/src/commands.rs`。

实施步骤：

1. 将 `byte_offset_for_char_column` 替换为返回同一行多个列位置的批量转换函数。
2. 在 `ToggleComment` 中，计算 indent 时直接在 `char_indices` 迭代中同时得到 `indent_col` 和 `indent_byte`，避免 `chars().take_while().count()` 后再 `nth(column)`。
3. 对同一行多次使用的 char/byte 列，局部缓存。

测试：

- 在 `comment_toggle.rs` 增加包含多字节缩进/emoji 的用例。
- 增加长行多选区 toggle comment benchmark。

验收标准：

- 单行列转换不再形成 O(n²) 外层循环。

### 11. IntervalTree 更新路径降级风险控制

涉及文件：`crates/editor-core/src/intervals.rs`、style layer 应用点。

实施步骤：

1. 短期：批量应用多个编辑时，避免每个 edit 对每个 layer 反复 `update_for_*`；先合并 delta，再对每层一次性更新。
2. 中期：对 `IntervalTree` 引入懒偏移或分块存储，减少插入/删除后重建 `prefix_max_end` 的范围。
3. 对语法高亮/semantic token 这类可刷新派生状态，编辑后可直接标脏并等待 provider 刷新，避免对大量 interval 做精确平移。
4. 保留查询侧 `prefix_max_end` 剪枝，避免优化更新时牺牲 viewport 查询。

测试：

- 添加密集 interval + 多 layer 编辑 benchmark。
- 覆盖插入、删除、跨 interval 删除、完全删除 interval 的正确性测试。

验收标准：

- 多 layer 高频编辑不再随 interval 数量线性乘 layer 数量恶化到不可用。

### 12. 控制 `command_history` 内存

涉及文件：`crates/editor-core/src/commands.rs`。

实施步骤：

1. 全仓确认 `get_command_history` 的真实消费者。
2. 若仅测试/调试使用，默认关闭或改为 ring buffer，容量与 `max_undo` 类似可配置。
3. 避免 clone 大 `InsertText`：历史中只记录 command kind、时间、摘要长度，或直接依赖 undo history。

测试：

- 增加长会话插入大文本后历史容量受限测试。

验收标准：

- `command_history` 不再无界增长。

## P2：可维护性、封装与 ABI

### 13. 拆分 `commands.rs`

建议拆分顺序：

1. `model.rs`：`Position`、`Selection`、选择方向、基础类型。
2. `undo.rs`：`TextEdit`、`UndoStep`、`UndoRedoManager`、snapshot restore。
3. `visual_rows.rs`：`VisualRowIndex` 及映射逻辑。
4. `edit_ops.rs`：插入、删除、replace、ApplyTextEdits、多光标应用。
5. `line_ops.rs`：Duplicate/Delete/Move/Join/ToggleComment。
6. `cursor_ops.rs`：移动、选择、word/grapheme 边界。
7. `render_grid.rs`：viewport、minimap、composed snapshot。
8. `commands.rs` 仅保留 `Command` enum、`CommandExecutor` 分发和公共 re-export。

实施规则：

- 先做纯移动，不改逻辑。
- 每次移动后运行 `cargo test -p editor-core`。
- 拆分完成后再做逻辑优化，避免 review 混乱。

验收标准：

- 单文件不再超过可维护阈值，核心逻辑按职责归档。

### 14. 收紧公开 API 和字段

涉及文件：`crates/editor-core/src/lib.rs`、`crates/editor-core/src/commands.rs`。

实施步骤：

1. 将内部模块分为 public facade 和 private implementation：优先将 `storage`、部分 `line_index`、`layout` 内部方法改为 `pub(crate)`。
2. `EditorCore` 字段改为私有，提供只读 getter 和受控 mutation API。
3. 对确实有外部 crate 依赖的类型，通过 `pub use` 提供稳定 facade。
4. 破坏性变更前先在 changelog/文档中标注迁移方式。

验收标准：

- 外部无法直接破坏文本、layout、folding、style 同步不变量。

### 15. 删除/私有化 `LineIndex` 陷阱 API

涉及文件：`crates/editor-core/src/line_index.rs`。

实施步骤：

1. 删除或改为 `pub(crate)`：`append_line`、`insert_line(LineMetadata)`、`get_line_mut`。
2. 删除 `LineMetadata.pieces` 或改成私有/测试专用，避免暗示 line 和 piece 仍有关联。
3. 标明 `line_to_offset` / `offset_to_line` 为 legacy，并迁移内部测试到 `position_to_char_offset` / `char_offset_to_position`。
4. 修正 CRLF 语义：当前内部已 LF 归一化，文档和测试需明确；若允许直接构造 CRLF `LineIndex`，补测试并正确剥离 `\r\n`。

验收标准：

- 外部无法调用会插入假 `x` 的 API。

### 16. FFI ABI 定宽迁移

涉及文件：`crates/editor-core-ffi/src/lib.rs`、`crates/editor-core-ui-ffi/src/lib.rs`、`docs/abi-v1-draft.md`、`swift/`。

实施步骤：

1. 列出所有 `extern "C"` 签名中的 `usize`，按语义替换：行/列/宽度/数量优先 `u32`，文档字符偏移/长度可用 `u64`。
2. Rust 内部入口立即 `try_from` 到 `usize`，溢出返回 `InvalidArgument`，不要静默截断。
3. 若已有公开函数名不能破坏，新增 `_v2` 或 typed 定宽版本，旧 `usize` 版本标记 deprecated。
4. 同步更新 ABI 文档、Swift/C header 生成、FFI tests。
5. 强化 handle 线程/别名约束：文档中将“建议”改为“调用契约”，说明同一 handle 不允许并发/重入调用。

测试：

- 扩展 `crates/editor-core-ffi/tests/abi_v1.rs`。
- 增加超大 u64/u32 边界值返回 InvalidArgument 的测试。

验收标准：

- 新公共 ABI 不含 `usize`。
- 文档明确数组 `count/out_cap` 与 handle aliasing 契约。

## P3：正确性专项与文档收口

### 17. Undo coalescing 修正

涉及文件：`crates/editor-core/src/commands.rs`，拆分后应在 `undo.rs` / `edit_ops.rs`。

实施步骤：

1. 在 `UndoRedoManager` 记录 open group 的最后编辑位置、时间戳和 edit kind。
2. 只有满足以下条件才合并：纯插入、不含换行、同一主 caret、位置相邻、时间窗口内。
3. 光标移动、选择变化、非插入、超时、不同 selection set 都结束 group。
4. 提供可配置 coalescing timeout，默认可采用 1s 左右。

测试：

- 一段连续输入一次 undo 只撤销最近时间窗口。
- 非相邻位置输入不会合并。
- 多光标输入的 undo group 保持一次用户动作可撤销。

### 18. 多折叠区域 visual/logical 往返验证

涉及文件：`crates/editor-core/src/intervals.rs`、`crates/editor-core/tests/folding_stability.rs`。

实施步骤：

1. 先添加失败用例：多个 collapsed region，视觉行逐个映射回逻辑行，再映射回视觉行。
2. 若确认 `FoldingManager::visual_to_logical` 错位，改为使用累计 hidden lines 时保持同一坐标基准，或直接复用 `VisualRowIndex`。
3. 废弃 `FoldingManager` 自己的线性视觉转换，避免双实现分叉。

验收标准：

- 多个折叠区域下 `logical_to_visual` / `visual_to_logical` 往返稳定。

### 19. LSP UTF-16 边界修正

涉及文件：`crates/editor-core-lsp/src/lsp_sync.rs`。

实施步骤：

1. 修改 `utf16_to_char_offset`：若目标 offset 落在代理对中间，返回该字符起点或按 LSP 容错策略 clamp 到最近合法边界，但必须文档化。
2. 对超大 `character` 做饱和处理，不能因 `u32::MAX` 导致异常区间。
3. `char_offset_for_lsp_position` 对越界 line/character 做明确 clamp。

测试：

- 对 emoji UTF-16 offset 1、2、3 分别测试。
- diagnostics/token range 落在半个代理对时不会扩大到错误字符后方。

### 20. 文档清理

涉及文件：`docs/DESIGN.md`、`docs/abi-v1-draft.md`、`crates/editor-core/src/lib.rs`。

需要修正：

- `DESIGN.md` 中 LineIndex “many edit paths rebuild rope from full text”的表述。
- `DESIGN.md` 中 folding “not automatically shifted”的表述，改成区分用户 fold 平移与派生 fold 刷新。
- `lib.rs` 中 PieceTable O(1) 说法，改为当前实现复杂度更准确的描述。
- `lib.rs` 中 grapheme/word-aware 与 DESIGN non-goal 的冲突：明确当前哪些命令支持 grapheme，哪些坐标/布局仍按 Unicode scalar。
- 拼写/断词：`Subscribe toState changed`、`soft wrappinglayout engine`、`andcode foldingmanagement` 等。

验收标准：

- 文档不再与实现相互矛盾。

### 21. Panic 与错误处理专项

涉及文件：`crates/editor-core/src/storage.rs`、`commands.rs` 拆分后的 undo 模块、`editor-core-ui`、`editor-core-app`。

实施步骤：

1. 核心库中将裸 `unwrap/expect` 分为测试、不可达不变量、可恢复错误三类。
2. `storage.rs` 的 UTF-8 `unwrap` 改为 debug_assert + fallible helper 或返回 `Result`。
3. `UndoRedoManager` 的裸索引改为 checked access，stale node id 返回 `CommandError` 或跳过 tombstone。
4. `editor-core-ui` / `editor-core-app` 单独开专项，不与核心重构混合。

验收标准：

- 核心库生产路径 panic 数量下降，并有说明哪些 panic 是不可恢复 bug。

## 测试矩阵

每个阶段至少运行：

- `cargo fmt`
- `cargo test -p editor-core`
- `cargo test -p editor-core-lsp`
- `cargo test -p editor-core-ffi`

P0/P1 完成后运行：

- `cargo test`
- `cargo clippy --all-targets --all-features`

重点新增测试文件建议：

- `crates/editor-core/tests/text_buffer_single_source.rs`
- `crates/editor-core/tests/visual_row_index.rs`
- `crates/editor-core/tests/undo_coalescing.rs`
- `crates/editor-core/tests/folding_visual_mapping.rs`
- `crates/editor-core-lsp/tests/lsp_process_lifecycle.rs`
- `crates/editor-core-lsp/tests/diagnostics_versioning.rs`
- `crates/editor-core-lsp/tests/utf16_boundaries.rs`
- `crates/editor-core-ffi/tests/abi_fixed_width.rs`

## 推荐 PR 切分

1. PR-1：LSP 子进程回收、`wait_for_response` 缓存、diagnostics 版本守卫。
2. PR-2：折叠派生状态版本化与多折叠映射回归测试。
3. PR-3：`TextBuffer` 抽象与 debug 一致性校验，不移除 `PieceTable`。
4. PR-4：移除 `LayoutEngine.line_texts`，layout 改由 `TextBuffer` 提供文本。
5. PR-5：行级命令与列字节转换性能优化。
6. PR-6：视觉行索引抽模块并改为可增量更新。
7. PR-7：纯移动拆分 `commands.rs`。
8. PR-8：收紧公开字段/API，废弃 `PieceTable` 和损坏的 `LineIndex` API。
9. PR-9：FFI 定宽 ABI 与文档更新。
10. PR-10：文档清理、panic 专项、全量测试和 clippy 收口。

## 关键决策点

- 是否接受破坏性 API：移除 `EditorCore.piece_table` 和收紧 `pub mod` 会影响外部直接依赖内部结构的用户。
- `PieceTable` 是彻底删除还是保留为可选实验模块：建议主路径删除，模块可暂时保留但不再公开承诺。
- diagnostics 无版本时的策略：建议兼容接受，但提供可观测日志/事件。
- FFI 旧 `usize` 函数是否保留：若已有 Swift/外部宿主依赖，建议新增定宽版本并 deprecate 旧版本；若尚未发布，直接替换。

## 完成定义

- 主编辑路径只有一个文本真相源，layout 不保存整行文本副本。
- LSP 子进程可可靠退出，旧版本 diagnostics/folding 不污染当前文档。
- 大文件滚动、视觉行映射、行级编辑无明显 O(n) 热路径退化。
- 核心命令、undo、折叠、Unicode/LSP 坐标有专项回归测试。
- FFI ABI 与文档一致，公开整数使用定宽类型。
- `docs/DESIGN.md`、`lib.rs` 文档与实现一致。
