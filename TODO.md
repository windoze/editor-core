# CODE-REVIEW 执行 TODO

来源：`PLAN.md`。本文件用于把方案拆成可执行任务，并为每个代码改动任务安排紧随其后的专项 review 任务。

## 执行纪律

- 一次只执行一个实现任务。完成该任务的代码、测试和格式化后，必须先执行紧随其后的 `Review` 任务，再进入下一个实现任务。
- 不要把两个实现任务混在一个改动里。尤其不要把纯移动拆分、性能优化、API 破坏性变更和文档修复混在一起。
- 执行每个任务前只需要先读该任务列出的文件和入口函数；不要进行全仓开放式搜索，除非任务中明确写了“需要全仓确认”。
- 不要修改未列入任务范围的文件。若发现必须修改额外文件，先在任务记录里说明原因，再继续。
- 保持 diff 最小。优先修改现有函数和测试，不引入不必要的新抽象。
- 公共 API 坐标默认是 char offset / Unicode scalar index，不要把 byte offset 混入核心逻辑。LSP 层的 UTF-16 转换只允许留在 `editor-core-lsp`。
- FFI 公开 ABI 必须使用定宽整数。若保留旧 ABI，仅可作为 deprecated 兼容入口，内部必须做溢出检查。
- 不要删除或回滚用户/其他 agent 的无关改动。禁止使用 `git reset --hard`、`git checkout --` 等破坏性命令。
- 每个实现任务都必须补充或更新针对性测试。若确实无法测试，需要在任务结果中说明不可测试原因和人工验证方式。
- 每个实现任务完成后至少运行该任务列出的测试命令；P0/P1 任务完成后优先运行相关 crate 的完整测试。
- Review 任务是代码审查任务，不主动重构。只有发现明确 bug、测试缺口或质量问题时，才提出修复建议或创建后续修复任务。

## 通用检查清单

- 格式化：`cargo fmt`。
- 核心测试：`cargo test -p editor-core`。
- LSP 测试：`cargo test -p editor-core-lsp`。
- FFI 测试：`cargo test -p editor-core-ffi`。
- 全量收口：`cargo test` 和 `cargo clippy --all-targets --all-features`。

## 任务列表

### T01 实现：LSP 子进程生命周期回收

状态：TODO

范围文件：

- `crates/editor-core-lsp/src/lsp_client.rs`
- `crates/editor-core-lsp/src/editor.rs`
- `crates/editor-core-lsp/tests/lsp_process_lifecycle.rs`，不存在则新增

已知入口：

- `LspClient` 当前字段：`_child: Child`
- `LspClient::spawn`
- `LspClient::from_child`
- `LspClient::wait_for_response`
- `LspSession::exit`

实现要求：

1. 将 `_child` 改为可操作的 `child` 字段。
2. 新增显式关闭方法，例如 `shutdown` / `terminate`，优雅路径为发送 `shutdown` 请求、短超时等待、发送 `exit`。
3. 若 server 不响应或 I/O 已断开，调用 `child.kill()`，随后必须 `child.wait()`。
4. 实现 `Drop for LspClient` 作为兜底：`try_wait` 未退出时执行 `kill` + `wait`。
5. 修改 `LspSession::exit`，使其使用新的生命周期方法，不再只发 `exit` notification。
6. 保持 reader/writer thread 错误处理行为不退化。

测试要求：

1. 新增不响应 shutdown 的 fake server 测试，drop/session exit 后进程必须退出。
2. 新增响应 shutdown 的 fake server 测试，验证不会误报错误。
3. 运行 `cargo test -p editor-core-lsp --test lsp_process_lifecycle`。
4. 运行 `cargo test -p editor-core-lsp`。

验收标准：

- 销毁 `LspClient` / `LspSession` 后不会遗留子进程。
- 正常和异常 server 都能被回收。

### T01R Review：审查 LSP 子进程生命周期回收

状态：TODO

审查范围：T01 的所有 diff。

审查重点：

1. 是否所有退出路径都调用了 `wait()`，包括 `kill()` 后和进程已自然退出时。
2. `Drop` 是否可能 panic 或长时间阻塞。
3. `shutdown` 请求超时是否合理，是否影响已有同步初始化流程。
4. reader/writer thread 的 channel 关闭是否会造成死锁。
5. 测试是否真的验证进程退出，而不只是验证 API 返回。

建议命令：

- `cargo test -p editor-core-lsp --test lsp_process_lifecycle`
- `cargo test -p editor-core-lsp`

### T02 实现：diagnostics 版本守卫

状态：TODO

范围文件：

- `crates/editor-core-lsp/src/editor.rs`
- `crates/editor-core-lsp/src/lsp_sync.rs`
- `crates/editor-core-lsp/tests/diagnostics_processing_edits.rs`
- 可新增 `crates/editor-core-lsp/tests/diagnostics_versioning.rs`

已知入口：

- `LspSession::poll_edits_with_line_index_and_handlers`
- `LspNotification::PublishDiagnostics`
- `lsp_diagnostics_to_processing_edits`
- `PendingLspRequest::SemanticTokens { version }` 已有版本守卫，可作为一致性参考

实现要求：

1. 处理 `textDocument/publishDiagnostics` 时读取 notification params 的 `version`。
2. 若 `version` 存在且不等于 `self.document.version`，不生成 `ProcessingEdit::ReplaceDiagnostics` 和 diagnostics style layer。
3. 旧版本 diagnostics 仍应进入普通 notification event，避免宿主丢失可观测消息。
4. 若 `version` 缺失，保持兼容：仍应用 diagnostics，但行为要在测试名或注释里明确。
5. 不改变 semantic tokens 和 folding ranges 已有版本守卫行为。

测试要求：

1. 旧版本 diagnostics 不产生任何 diagnostics processing edits。
2. 当前版本 diagnostics 正常产生 `ReplaceStyleLayer` 和 `ReplaceDiagnostics`。
3. 无版本 diagnostics 仍按兼容策略应用。
4. 运行 `cargo test -p editor-core-lsp --test diagnostics_processing_edits`。
5. 若新增文件，运行对应 `cargo test -p editor-core-lsp --test diagnostics_versioning`。

验收标准：

- 旧文本 diagnostics 不会用当前 `LineIndex` 转换坐标。
- diagnostics、semantic tokens、folding ranges 的版本策略一致。

### T02R Review：审查 diagnostics 版本守卫

状态：TODO

审查范围：T02 的所有 diff。

审查重点：

1. 旧版本 notification 是否没有产生派生状态改动。
2. 无版本 diagnostics 的兼容行为是否有测试固定。
3. 是否误吞了非目标 URI 的 diagnostics 或事件。
4. 是否出现重复调用 `on_unhandled_message` 或重复 push event。
5. 测试是否覆盖旧版本、当前版本、无版本三种情况。

建议命令：

- `cargo test -p editor-core-lsp --test diagnostics_processing_edits`
- `cargo test -p editor-core-lsp`

### T03 实现：`wait_for_response` 保留其它在途响应

状态：TODO

范围文件：

- `crates/editor-core-lsp/src/lsp_client.rs`
- `crates/editor-core-lsp/src/editor.rs`
- 可新增 `crates/editor-core-lsp/tests/lsp_wait_for_response.rs`

已知入口：

- `LspClient::wait_for_response`
- `LspClient::try_recv`
- `LspClient::handle_server_request`
- `LspSession::pending_client_requests`
- `LspEvent::Response`

实现要求：

1. 在 `LspClient` 内新增缓存，例如 `deferred_inbound: VecDeque<LspInbound>`。
2. `try_recv` 必须优先返回缓存内容，再从 channel 读取。
3. `wait_for_response` 等待目标 id 时，遇到其它 response 不得丢弃，应缓存为后续 `try_recv` 可见。
4. `wait_for_response` 遇到 notification 时也不得丢弃，除非是已经被 `handle_server_request` 完整处理的 server request。
5. server->client request 在等待期间仍要自动响应，避免初始化死锁。
6. malformed id 不要静默吞掉，应通过缓存路径让上层 `on_unhandled_message` 可观察。

测试要求：

1. 构造先到 id=2、后到 id=1 的响应序列；等待 id=1 后，poll 仍能收到 id=2。
2. 覆盖等待期间的 server request 自动响应。
3. 覆盖 notification 在等待后仍可被 poll 到。
4. 运行 `cargo test -p editor-core-lsp --test lsp_wait_for_response`。
5. 运行 `cargo test -p editor-core-lsp`。

验收标准：

- 阻塞等待某个 request 不会导致其它 pending request 永久泄漏。

### T03R Review：审查 `wait_for_response` 响应缓存

状态：TODO

审查范围：T03 的所有 diff。

审查重点：

1. 缓存顺序是否保持 inbound 原始顺序。
2. `try_recv` 是否会饿死 channel 中的新消息。
3. server request 自动响应后是否被错误重复投递。
4. malformed response 是否可被上层观察。
5. 是否引入无界缓存风险；如果可能无界，是否有合理解释。

建议命令：

- `cargo test -p editor-core-lsp --test lsp_wait_for_response`
- `cargo test -p editor-core-lsp`

### T04 实现：折叠派生状态版本化与折叠态保留

状态：TODO

范围文件：

- `crates/editor-core/src/intervals.rs`
- `crates/editor-core/src/processing.rs`
- `crates/editor-core/src/state.rs`
- `crates/editor-core/src/workspace.rs`
- `crates/editor-core-lsp/src/editor.rs`
- `crates/editor-core/tests/folding_stability.rs`
- 可新增 `crates/editor-core-lsp/tests/folding_versioning.rs`

已知入口：

- `FoldingManager::apply_line_delta`
- `FoldingManager::replace_derived_regions`
- `ProcessingEdit::ReplaceFoldingRegions { regions, preserve_collapsed }`
- `LspSession::handle_pending_response` 的 `PendingLspRequest::FoldingRanges { version }`
- `Workspace::apply_processing_edits` 中处理 `ReplaceFoldingRegions`

实现要求：

1. 为 LSP folding response 引入版本保护，旧版本 response 不能覆盖当前文档 folding state。
2. 对 `ProcessingEdit::ReplaceFoldingRegions` 明确版本来源。若不修改 enum，需要在 LSP 应用前完成丢弃；若修改 enum，必须更新所有构造和 match 点。
3. 编辑期间继续使用 `apply_line_delta` 平移用户 fold 和派生 fold，降低刷新窗口错位。
4. 改进 `preserve_collapsed` 匹配策略，不仅按 `(start_line, end_line)` 精确匹配；优先考虑同 start 附近、范围重叠、placeholder/kind 一致。
5. 用户 fold 与派生 fold 不能互相覆盖折叠态。

测试要求：

1. 多个 collapsed region 下编辑插入/删除后，旧 LSP folding response 被丢弃。
2. 小范围行号漂移后，用户已折叠状态仍保留。
3. 派生 fold 刷新不会删除用户 fold。
4. 运行 `cargo test -p editor-core --test folding_stability`。
5. 运行 `cargo test -p editor-core-lsp`。

验收标准：

- 编辑后旧 folding response 不污染当前文档。
- 折叠态保留策略有明确测试覆盖。

### T04R Review：审查折叠版本化与折叠态保留

状态：TODO

审查范围：T04 的所有 diff。

审查重点：

1. 旧版本 folding response 是否在进入 core state 前就被拦截。
2. `ProcessingEdit` enum 如有变化，是否所有 match 点都已更新。
3. 折叠态模糊匹配是否可能把不相关 region 错配成 collapsed。
4. 用户 fold 和派生 fold 的边界是否清晰。
5. visual-row cache 是否在 fold 变化后正确失效。

建议命令：

- `cargo test -p editor-core --test folding_stability`
- `cargo test -p editor-core-lsp`

### T05 实现：新增 `TextBuffer` 抽象并建立一致性校验

状态：TODO

范围文件：

- `crates/editor-core/src/text_buffer.rs`，不存在则新增
- `crates/editor-core/src/lib.rs`
- `crates/editor-core/src/line_index.rs`
- `crates/editor-core/src/commands.rs`
- `crates/editor-core/tests/text_buffer_single_source.rs`，不存在则新增

已知入口：

- `EditorCore::new`
- `EditorCore::get_text`
- `EditorCore::char_count`
- `CommandExecutor::apply_text_change_to_line_index_and_layout`
- `LineIndex::insert`
- `LineIndex::delete`
- `LineIndex::get_text`
- `LineIndex::get_line_text`

实现要求：

1. 新增内部 `TextBuffer`，先包装 `LineIndex` 或直接包装 `ropey::Rope`，但不要在本任务删除 `PieceTable`。
2. 提供 API：`len_chars`、`len_bytes`、`line_count`、`insert`、`delete`、`get_text`、`get_range`、`get_line_text`、`position_to_char_offset`、`char_offset_to_position`、`char_offset_to_byte_offset`、`byte_offset_to_char_offset`。
3. `EditorCore::get_text` 和 `EditorCore::char_count` 优先走 `TextBuffer`。
4. 编辑路径保留 `PieceTable` 影子写入，但新增 debug-only 一致性断言，确认 `PieceTable` 和 `TextBuffer` 文本一致。
5. 不在本任务改变 public API 可见性。

测试要求：

1. 覆盖空文档、末尾无换行、末尾有换行、CJK、emoji、CRLF 输入归一化。
2. 覆盖插入、删除、range 读取、line 文本读取。
3. 运行 `cargo test -p editor-core --test text_buffer_single_source`。
4. 运行 `cargo test -p editor-core`。

验收标准：

- 新抽象可替代 `LineIndex` 的主要文本访问能力。
- 当前行为不变，`PieceTable` 与 `TextBuffer` 一致。

### T05R Review：审查 `TextBuffer` 抽象

状态：TODO

审查范围：T05 的所有 diff。

审查重点：

1. `TextBuffer` API 是否保持 char offset 语义。
2. 是否引入第四份完整文本副本；如果临时存在，是否只包装现有结构。
3. CRLF 归一化是否仍只在入口处发生。
4. debug 一致性断言是否覆盖所有编辑路径。
5. 测试是否覆盖末尾换行和 Unicode 边界。

建议命令：

- `cargo test -p editor-core --test text_buffer_single_source`
- `cargo test -p editor-core`

### T06 实现：移除 `LayoutEngine.line_texts` 文本副本

状态：TODO

范围文件：

- `crates/editor-core/src/layout.rs`
- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/state.rs`
- `crates/editor-core/src/snapshot.rs`
- `crates/editor-core/tests/incremental_viewport_consistency.rs`
- 可新增 `crates/editor-core/tests/layout_reflow_consistency.rs`

已知入口：

- `LayoutEngine` 字段 `line_texts: Vec<String>`
- `LayoutEngine::from_lines`
- `LayoutEngine::add_line`
- `LayoutEngine::update_line`
- `LayoutEngine::insert_line`
- `LayoutEngine::delete_line`
- `LayoutEngine::recalculate_all`
- `LayoutEngine::set_viewport_width`
- `LayoutEngine::set_wrap_mode`
- `LayoutEngine::set_wrap_indent`
- `LayoutEngine::set_tab_width`
- `CommandExecutor::apply_text_change_to_line_index_and_layout`

实现要求：

1. 删除 `LayoutEngine.line_texts` 字段，layout 只保存 `VisualLineInfo` 和换行参数。
2. 保留 `from_lines/add_line/update_line/insert_line` 接收文本用于计算，但不存储文本。
3. `recalculate_all` 改为由调用方传入行文本，或新增 `recalculate_all_from_lines`。
4. 视口宽度、wrap mode、wrap indent、tab width 改变时，由 `EditorCore` 读取 `TextBuffer`/`LineIndex` 行文本统一触发重排。
5. 确保 visual-row cache 在所有重排行为后失效。

测试要求：

1. 编辑后 viewport 与从全文重建的 editor 输出一致。
2. resize、wrap mode、wrap indent、tab width 改变后 snapshot 一致。
3. 运行 `cargo test -p editor-core --test incremental_viewport_consistency`。
4. 运行 `cargo test -p editor-core`。

验收标准：

- `LayoutEngine` 不再保存整行文本副本。
- 所有快照和布局测试通过。

### T06R Review：审查移除 layout 文本副本

状态：TODO

审查范围：T06 的所有 diff。

审查重点：

1. 是否彻底删除 `line_texts`，没有用其它字段重新保存整行文本。
2. 全量重排时是否从唯一文本源读取。
3. `set_viewport_width` 等 API 行为是否保持一致。
4. visual-row cache 是否正确失效。
5. incremental layout 和从全文重建 layout 是否有测试比对。

建议命令：

- `cargo test -p editor-core --test incremental_viewport_consistency`
- `cargo test -p editor-core`

### T07 实现：废弃并移出主路径的 `PieceTable`

状态：TODO

范围文件：

- `crates/editor-core/src/storage.rs`
- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/lib.rs`
- `crates/editor-core/tests/text_buffer_single_source.rs`
- `crates/editor-core/tests/undo_redo.rs`
- `crates/editor-core/tests/line_ops.rs`

已知入口：

- `EditorCore` 字段 `pub piece_table: PieceTable`
- `EditorCore::get_text`
- `EditorCore::char_count`
- `CommandExecutor::apply_text_change_to_line_index_and_layout`
- 所有 `self.editor.piece_table.get_text()`、`get_range()`、`insert()`、`delete()` 调用点
- `pub use storage::PieceTable` in `crates/editor-core/src/lib.rs`

实现要求：

1. 停止主编辑路径直接依赖 `PieceTable`，文本读写统一走 `TextBuffer`。
2. 若外部 API 仍需要 `PieceTable`，先保留 `pub use storage::PieceTable` 并标记 deprecated，不在本任务强删模块。
3. 将 `EditorCore.piece_table` 从公共字段改为私有影子字段，或在确认无外部依赖后删除。
4. `apply_text_change_to_line_index_and_layout` 改为先应用 `TextBuffer`，再根据 delta 更新 layout、styles、folding、selection。
5. 删除不再需要的一致性影子写入或将其限制到短期 debug 模式。

测试要求：

1. 文本编辑、undo/redo、行操作、快照行为不变。
2. 运行 `cargo test -p editor-core --test undo_redo`。
3. 运行 `cargo test -p editor-core --test line_ops`。
4. 运行 `cargo test -p editor-core`。

验收标准：

- 主编辑路径只有一个完整文本真相源。
- `storage.rs` 不再参与正常编辑同步链路。

### T07R Review：审查 `PieceTable` 废弃迁移

状态：TODO

审查范围：T07 的所有 diff。

审查重点：

1. 是否还有主路径调用 `piece_table.insert/delete/get_text/get_range`。
2. API 破坏性是否被明确标注或保留兼容路径。
3. undo/redo 的 deleted text 和 inserted text 是否仍准确。
4. `TextDelta` 的 before/after char count 是否仍正确。
5. 是否真正减少完整文本副本，而不是换个结构继续保存。

建议命令：

- `cargo test -p editor-core --test undo_redo`
- `cargo test -p editor-core --test line_ops`
- `cargo test -p editor-core`

### T08 实现：视觉行映射索引增量化

状态：TODO

范围文件：

- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/visual_rows.rs`，不存在则新增
- `crates/editor-core/src/layout.rs`
- `crates/editor-core/src/intervals.rs`
- `crates/editor-core/tests/visual_row_improvements.rs`
- 可新增 `crates/editor-core/tests/visual_row_index.rs`

已知入口：

- `VisualRowSpan`
- `VisualRowIndex`
- `EditorCore::with_visual_row_index`
- `EditorCore::build_visual_row_index`
- `EditorCore::visual_line_count`
- `EditorCore::visual_to_logical_line`
- `EditorCore::logical_position_to_visual`
- `EditorCore::visual_start_for_logical_line`
- `LayoutEngine::logical_to_visual_line`
- `LayoutEngine::visual_to_logical_line`
- `FoldingManager::logical_to_visual`
- `FoldingManager::visual_to_logical`

实现要求：

1. 将 `VisualRowIndex` 从 `commands.rs` 抽到 `visual_rows.rs`。
2. 使用分块前缀和、Fenwick tree 或等价结构保存每个逻辑行的 `visible` 和 `visual_line_count`。
3. 单行编辑只更新受影响行的 wrap count；折叠 toggle 只更新对应可见性区间。
4. `EditorCore::visual_line_count`、`visual_to_logical_line`、`logical_position_to_visual` 统一走新索引。
5. 废弃或绕开 `LayoutEngine` / `FoldingManager` 的线性视觉转换，避免双实现不一致。

测试要求：

1. 10 万行尾部 visual->logical 查询有 benchmark 或可重复性能测试。
2. 折叠 + 软换行 + CJK/emoji 的 logical/visual 往返测试。
3. 运行 `cargo test -p editor-core --test visual_row_improvements`。
4. 运行 `cargo test -p editor-core --test visual_row_index`，若新增。
5. 运行 `cargo test -p editor-core`。

验收标准：

- 普通编辑和光标移动不触发全量 visual row 重建。
- 大文件尾部坐标转换不再是 O(total lines)。

### T08R Review：审查视觉行索引增量化

状态：TODO

审查范围：T08 的所有 diff。

审查重点：

1. 新索引是否覆盖 folding 和 soft wrap 的组合语义。
2. cache invalidation 是否过宽或过窄。
3. 多个折叠区域、尾部空行、末尾无换行是否有测试。
4. 是否留下旧线性 API 被核心热路径继续调用。
5. 性能测试是否能证明尾部查询改善。

建议命令：

- `cargo test -p editor-core --test visual_row_improvements`
- `cargo test -p editor-core`

### T09 实现：行级命令避免全文读取

状态：TODO

范围文件：

- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/search.rs`
- `crates/editor-core/tests/line_ops.rs`
- `crates/editor-core/tests/comment_toggle.rs`
- `crates/editor-core/tests/workspace_search_apply.rs`

已知入口：

- `execute_duplicate_lines_command`
- `execute_delete_lines_command`
- `execute_move_lines_command`
- `execute_join_lines_command`
- `execute_toggle_comment_command`
- `execute_apply_text_edits_command`
- `slice_text_for_lines`
- `self.editor.piece_table.get_text()` 全文读取调用点
- `find_next` / `find_all` 搜索路径可保留全文读取，但要和行编辑路径区分

实现要求：

1. Duplicate/Delete/Move/Join/ToggleComment/ApplyTextEdits 不再为普通行编辑读取全文 `String`。
2. 判断文档是否以换行结尾时，改为读取最后一个 char 或最后一行状态。
3. 删除文本读取使用 `TextBuffer::get_range` 或等价范围 API。
4. 搜索命令允许保留全文读取，但不要让行级编辑误走搜索全文路径。
5. 多光标 selection 映射保持现有行为。

测试要求：

1. 行操作覆盖末尾无换行、末尾有换行、多光标、Unicode 行。
2. ToggleComment 覆盖多行、多字节字符、空行。
3. 运行 `cargo test -p editor-core --test line_ops`。
4. 运行 `cargo test -p editor-core --test comment_toggle`。
5. 运行 `cargo test -p editor-core`。

验收标准：

- 普通行级编辑只分配受影响范围的文本。
- 行操作行为不变。

### T09R Review：审查行级命令性能优化

状态：TODO

审查范围：T09 的所有 diff。

审查重点：

1. 是否仍有行级命令调用全文 `get_text()`。
2. 末尾无换行的 duplicate/move/delete 行为是否保持。
3. 多光标 selection 映射是否未退化。
4. 删除文本用于 undo 的范围是否准确。
5. 搜索命令全文读取是否被明确隔离。

建议命令：

- `cargo test -p editor-core --test line_ops`
- `cargo test -p editor-core --test comment_toggle`
- `cargo test -p editor-core`

### T10 实现：优化列到字节转换

状态：TODO

范围文件：

- `crates/editor-core/src/commands.rs`
- `crates/editor-core/tests/comment_toggle.rs`
- `crates/editor-core/tests/unicode_segmentation.rs`

已知入口：

- `byte_offset_for_char_column`
- `char_column_for_byte_offset`
- `execute_toggle_comment_command`
- ToggleComment 中两处 indent 计算：`chars().take_while(...).count()` 后再 `byte_offset_for_char_column`

实现要求：

1. 将 indent 计算改为单次 `char_indices` 迭代，同时得到 `indent_col` 和 `indent_byte`。
2. 若同一行需要多个 char->byte 转换，提供局部批量转换或局部缓存。
3. 保持 `byte_offset_for_char_column` 的旧语义，除非所有调用点同步更新。
4. 不改变 public char column 语义。

测试要求：

1. ToggleComment 覆盖 CJK、emoji、tab、空白缩进。
2. 长行多选区 toggle comment 不出现 O(n²) 明显退化，可用 benchmark 或计时测试固定。
3. 运行 `cargo test -p editor-core --test comment_toggle`。
4. 运行 `cargo test -p editor-core --test unicode_segmentation`。

验收标准：

- ToggleComment 不再对同一 column 做重复 O(column) 扫描。

### T10R Review：审查列字节转换优化

状态：TODO

审查范围：T10 的所有 diff。

审查重点：

1. char column 和 byte offset 是否没有混用。
2. 多字节字符前后的注释插入/删除位置是否正确。
3. tab 缩进是否仍按字符列处理，而不是视觉宽度。
4. 旧 helper 若保留，是否仍有 O(n²) 热路径调用。
5. 测试是否覆盖非 ASCII 缩进和注释 token 后空格删除。

建议命令：

- `cargo test -p editor-core --test comment_toggle`
- `cargo test -p editor-core --test unicode_segmentation`

### T11 实现：IntervalTree 更新路径降本

状态：TODO

范围文件：

- `crates/editor-core/src/intervals.rs`
- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/processing.rs`
- `crates/editor-core/tests/diagnostics.rs`
- 可新增 `crates/editor-core/tests/interval_tree_updates.rs`

已知入口：

- `IntervalTree::insert`
- `IntervalTree::remove`
- `IntervalTree::update_for_insertion`
- `IntervalTree::update_for_deletion`
- `IntervalTree::rebuild_prefix_max_end_from`
- `IntervalTree::rebuild_prefix_max_end`
- style layer 更新点：`self.editor.interval_tree.update_for_*` 和 `self.editor.style_layers.values_mut()` 循环

实现要求：

1. 短期先优化批量编辑：对多个 edit 合并 delta，避免每个 edit 对每个 style layer 反复全量更新。
2. 保持 query 侧 `prefix_max_end` 剪枝语义，不牺牲 `query_point` / `query_range` 正确性。
3. 若引入懒偏移或分块结构，必须保留 interval 排序不变量。
4. 对可刷新派生状态，例如 semantic tokens，可选择标脏等待刷新，但 diagnostics/base style 不得丢失。

测试要求：

1. 插入、删除、跨 interval 删除、完全删除 interval。
2. 多 layer 下批量 edit 后 style range 正确。
3. 运行 `cargo test -p editor-core --test diagnostics`。
4. 运行 `cargo test -p editor-core --test interval_tree_updates`，若新增。
5. 运行 `cargo test -p editor-core`。

验收标准：

- 高频多 layer 编辑不再对每个 edit 都做每层全量更新。
- interval 查询结果保持不变。

### T11R Review：审查 IntervalTree 更新优化

状态：TODO

审查范围：T11 的所有 diff。

审查重点：

1. interval 排序和 `prefix_max_end` 是否始终同步。
2. 删除范围边界 `[start, end)` 是否处理正确。
3. 多 edit 合并是否改变重叠 edit 的语义。
4. 派生状态标脏策略是否会导致旧样式长期残留。
5. 性能优化是否有足够测试证明不破坏查询。

建议命令：

- `cargo test -p editor-core --test diagnostics`
- `cargo test -p editor-core`

### T12 实现：限制 `command_history` 内存增长

状态：TODO

范围文件：

- `crates/editor-core/src/commands.rs`
- `crates/editor-core/tests/command_executor_commands.rs`
- 可新增 `crates/editor-core/tests/command_history.rs`

已知入口：

- `CommandExecutor` 字段 `command_history: Vec<Command>`
- `CommandExecutor::execute` 中 `self.command_history.push(command.clone())`
- `CommandExecutor::get_command_history`
- `EditCommand::InsertText { text }`
- `UndoRedoManager::new(1000)` 可作为容量设计参考

实现要求：

1. 全仓确认 `get_command_history` 是否有生产消费者。此任务允许做一次定向全仓 grep：`get_command_history`。
2. 若仅调试/测试使用，将 history 改为有界 ring buffer。
3. 避免 clone 大文本命令。可记录 command kind、摘要长度、截断文本，或提供配置关闭 history。
4. 保持现有公开 API 能返回合理历史；若改变返回类型，必须明确破坏性并更新调用点。

测试要求：

1. 连续执行超过容量的命令后 history 长度受限。
2. 插入大文本不会在 history 中保存完整副本，或默认 history 关闭。
3. 运行 `cargo test -p editor-core --test command_executor_commands`。
4. 运行新增测试文件，若有。

验收标准：

- `command_history` 不再无界增长。
- 大 `InsertText` 不再因 history 额外完整 clone。

### T12R Review：审查 command_history 内存控制

状态：TODO

审查范围：T12 的所有 diff。

审查重点：

1. 是否真正消除了无界增长。
2. 是否保留了必要调试能力。
3. 大文本是否仍被完整 clone 到 history。
4. `get_command_history` API 兼容性是否清楚。
5. 容量配置是否有合理默认值。

建议命令：

- `cargo test -p editor-core --test command_executor_commands`
- `cargo test -p editor-core`

### T13 实现：纯移动拆分 `commands.rs`

状态：TODO

范围文件：

- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/model.rs`，不存在则新增
- `crates/editor-core/src/undo.rs`，不存在则新增
- `crates/editor-core/src/visual_rows.rs`，若 T08 未创建则新增
- `crates/editor-core/src/edit_ops.rs`，不存在则新增
- `crates/editor-core/src/line_ops.rs`，不存在则新增
- `crates/editor-core/src/cursor_ops.rs`，不存在则新增
- `crates/editor-core/src/render_grid.rs`，不存在则新增
- `crates/editor-core/src/lib.rs`

已知移动对象：

- `Position`、`Selection`、`SelectionDirection` -> `model.rs`
- `TextEdit`、`UndoStep`、`UndoRedoManager`、`UndoNode` -> `undo.rs`
- `VisualRowSpan`、`VisualRowIndex` -> `visual_rows.rs`
- insert/delete/replace/apply edits/multi-cursor helpers -> `edit_ops.rs`
- Duplicate/Delete/Move/Join/ToggleComment helpers -> `line_ops.rs`
- cursor movement/selection/word boundary helpers -> `cursor_ops.rs`
- viewport/minimap/composed snapshot helpers -> `render_grid.rs`

实现要求：

1. 这是纯移动任务，不允许改变业务逻辑。
2. 每移动一个模块后运行 `cargo test -p editor-core`，不要等全部移动完才测试。
3. 保持 public re-export 不变，外部 `use editor_core::{CommandExecutor, Position, Selection}` 不应破坏。
4. 处理模块可见性时优先 `pub(crate)`，不要扩大 public API。
5. 如果 T08 已创建 `visual_rows.rs`，复用而不是重复创建。

测试要求：

1. `cargo test -p editor-core`。
2. `cargo test -p editor-core-lsp`，确认跨 crate 引用未破坏。
3. `cargo test -p editor-core-ffi`，确认 FFI re-export 未破坏。

验收标准：

- `commands.rs` 明显变小，职责清晰。
- 行为测试无变化。

### T13R Review：审查 `commands.rs` 纯移动拆分

状态：TODO

审查范围：T13 的所有 diff。

审查重点：

1. 是否只有移动和路径调整，没有混入逻辑改动。
2. public re-export 是否保持兼容。
3. 模块边界是否合理，没有形成循环依赖或过度 public。
4. `commands.rs` 是否仍承担过多职责。
5. 测试是否覆盖 core、lsp、ffi 依赖。

建议命令：

- `cargo test -p editor-core`
- `cargo test -p editor-core-lsp`
- `cargo test -p editor-core-ffi`

### T14 实现：收紧公开 API 和 `EditorCore` 字段

状态：TODO

范围文件：

- `crates/editor-core/src/lib.rs`
- `crates/editor-core/src/commands.rs` 或拆分后的 `model`/`core` 文件
- `crates/editor-core/src/storage.rs`
- `crates/editor-core/src/line_index.rs`
- `crates/editor-core/src/layout.rs`
- `crates/editor-core/src/workspace.rs`
- `crates/editor-core-ffi/src/lib.rs`
- `crates/tui-editor/src/main.rs`

已知入口：

- `pub mod storage`
- `pub mod line_index`
- `pub mod layout`
- `pub mod intervals`
- `EditorCore` 的公共字段：`piece_table`、`line_index`、`layout_engine`、`interval_tree`、`style_layers`、`diagnostics`、`decorations`、`document_symbols`、`folding_manager`、`cursor_position`、`selection`、`secondary_selections`、`viewport_width`

实现要求：

1. 将内部实现模块逐步改为私有或 `pub(crate)`，但保留必要 facade re-export。
2. `EditorCore` 字段改为私有，提供只读 getter 和受控 mutation API。
3. 先处理最危险字段：文本存储、layout、folding/style 派生状态。
4. 更新 workspace、FFI、TUI 内部调用点，不让它们直接破坏不变量。
5. 若破坏外部 API，必须在文档或 changelog 中记录迁移方式。

测试要求：

1. `cargo test -p editor-core`。
2. `cargo test -p editor-core-ffi`。
3. `cargo test -p tui-editor`，如果该 crate 有测试目标。
4. `cargo check -p tui-editor`，若测试不可用。

验收标准：

- 外部无法直接写破坏文本/layout/folding/style 同步的字段。
- 内部使用受控 API 维护不变量。

### T14R Review：审查公开 API 收紧

状态：TODO

审查范围：T14 的所有 diff。

审查重点：

1. 是否过度破坏 public API，是否有迁移说明。
2. 新 getter/mutator 是否仍允许外部破坏不变量。
3. FFI/TUI/workspace 是否已改用受控 API。
4. 是否保留了必要类型的 public facade。
5. 文档是否与可见性变更一致。

建议命令：

- `cargo test -p editor-core`
- `cargo test -p editor-core-ffi`
- `cargo check -p tui-editor`

### T15 实现：删除或私有化 `LineIndex` 陷阱 API

状态：TODO

范围文件：

- `crates/editor-core/src/line_index.rs`
- `crates/editor-core/src/lib.rs`
- `crates/editor-core/tests/stage2_validation.rs`
- `crates/editor-core/tests/line_endings.rs`

已知入口：

- `LineMetadata.pieces`
- `LineIndex::append_line`
- `LineIndex::insert_line`
- `LineIndex::get_line_mut`
- `LineIndex::line_to_offset`
- `LineIndex::offset_to_line`
- `LineIndex::position_to_char_offset`
- `LineIndex::char_offset_to_position`

实现要求：

1. 删除或改为 `pub(crate)`：`append_line`、`insert_line(LineMetadata)`、`get_line_mut`。
2. 删除 `LineMetadata.pieces` 或改为私有/测试专用，避免继续暗示 LineIndex 持有 Piece。
3. 将 `line_to_offset` / `offset_to_line` 标记为 legacy，内部测试尽量迁移到 preferred API。
4. 明确 CRLF 语义：核心入口归一化 LF；若 `LineIndex::from_text` 直接收到 CRLF，测试应固定当前行为或修正剥离策略。

测试要求：

1. `cargo test -p editor-core --test stage2_validation`。
2. `cargo test -p editor-core --test line_endings`。
3. `cargo test -p editor-core`。

验收标准：

- 外部不能调用会插入假 `x` 的 API。
- offset 语义在文档和测试中清楚。

### T15R Review：审查 `LineIndex` API 清理

状态：TODO

审查范围：T15 的所有 diff。

审查重点：

1. 是否还存在会构造假文本的 public API。
2. `LineMetadata` 是否仍暴露僵尸字段。
3. legacy offset API 是否有迁移说明。
4. CRLF 行尾处理是否清楚且有测试。
5. 下游 crate 是否仍能编译。

建议命令：

- `cargo test -p editor-core --test stage2_validation`
- `cargo test -p editor-core --test line_endings`
- `cargo test -p editor-core`

### T16 实现：FFI ABI 定宽迁移

状态：TODO

范围文件：

- `crates/editor-core-ffi/src/lib.rs`
- `crates/editor-core-ui-ffi/src/lib.rs`
- `crates/editor-core-ffi/tests/abi_v1.rs`
- `docs/abi-v1-draft.md`
- `swift/` 下相关 FFI 包装文件，如有调用签名

已知入口：

- `editor_core_ffi_editor_state_new(initial_text, viewport_width: usize)`
- `editor_core_ffi_editor_state_viewport_styled_json(start_visual_row: usize, count: usize)`
- `editor_core_ffi_editor_state_minimap_json(start_visual_row: usize, count: usize)`
- `editor_core_ffi_editor_state_viewport_composed_json(start_visual_row: usize, count: usize)`
- `editor_core_ffi_workspace_open_buffer(... viewport_width: usize)`
- `editor_core_ffi_workspace_open_buffer_typed(... viewport_width: usize)`
- `editor_core_ffi_workspace_create_view(... viewport_width: usize)`
- `editor_core_ffi_workspace_create_view_typed(... viewport_width: usize)`
- `editor-core-ui-ffi` 中公开 C ABI 大多已用 `u32`，重点检查数组 count/out_cap 文档和转换溢出

实现要求：

1. 列出所有 `extern "C"` 函数签名中的 `usize`，只允许本任务做定向 grep：`extern "C" fn` 与 `usize`。
2. 行、列、宽度、数量优先改为 `u32`；文档字符偏移/长度根据需要用 `u64`。
3. Rust 内部转换到 `usize` 时必须 `try_from` 或显式边界检查，溢出返回 `InvalidArgument`。
4. 若不能破坏旧函数名，新增 `_v2` 或 typed 定宽版本，旧入口 deprecated。
5. 更新 ABI 文档和 FFI tests。

测试要求：

1. `cargo test -p editor-core-ffi --test abi_v1`。
2. 新增超大 u64/u32 边界值返回 InvalidArgument 的测试。
3. `cargo test -p editor-core-ffi`。
4. 若改 UI FFI，运行 `cargo test -p editor-core-ui-ffi`。

验收标准：

- 新公共 ABI 不含 `usize`。
- ABI 文档与实现一致。

### T16R Review：审查 FFI ABI 定宽迁移

状态：TODO

审查范围：T16 的所有 diff。

审查重点：

1. 是否还有 public `extern "C"` 签名暴露 `usize`。
2. 内部转换是否检查溢出，而不是 `as usize` 静默截断。
3. 旧 ABI 兼容策略是否清楚。
4. Swift/header 文档是否同步。
5. 数组 `count/out_cap` 和 handle aliasing 契约是否明确。

建议命令：

- `cargo test -p editor-core-ffi --test abi_v1`
- `cargo test -p editor-core-ffi`
- `cargo test -p editor-core-ui-ffi`

### T17 实现：Undo coalescing 粒度修正

状态：TODO

范围文件：

- `crates/editor-core/src/commands.rs`，或拆分后的 `undo.rs` / `edit_ops.rs`
- `crates/editor-core/tests/undo_redo.rs`
- `crates/editor-core/tests/undo_tree.rs`
- 可新增 `crates/editor-core/tests/undo_coalescing.rs`

已知入口：

- `UndoRedoManager::push_step`
- `UndoRedoManager::end_group`
- `UndoRedoManager::current_group_id`
- `execute_insert_text_command`
- `execute_type_char_command`
- `execute_insert_command`
- `EditCommand::EndUndoGroup`
- 当前 coalescing 判断：纯插入且不含换行

实现要求：

1. 在 undo open group 中记录最后编辑位置、时间戳、edit kind、selection/caret 摘要。
2. 只有纯插入、不含换行、主 caret 相同或 selection set 可证明连续、位置相邻、时间窗口内，才合并。
3. 光标移动、选择变化、非插入、换行、超时、非相邻插入都必须结束 group。
4. 提供默认 coalescing timeout，建议约 1s；测试可注入或通过显式 `EndUndoGroup` 固定。
5. 多光标一次用户动作仍应作为一个 undo step 或合理 group。

测试要求：

1. 连续快速输入可以合并，但超时或显式 group 结束后不会合并。
2. 非相邻位置输入不会合并。
3. 光标移动后输入不会合并。
4. 多光标输入 undo 一次恢复到动作前。
5. 运行 `cargo test -p editor-core --test undo_coalescing`，若新增。
6. 运行 `cargo test -p editor-core --test undo_redo`。
7. 运行 `cargo test -p editor-core --test undo_tree`。

验收标准：

- 单次 undo 不再无限撤销长时间连续输入。
- undo tree 行为不退化。

### T17R Review：审查 Undo coalescing 修正

状态：TODO

审查范围：T17 的所有 diff。

审查重点：

1. 合并条件是否足够严格，尤其是位置相邻和 selection set。
2. 时间窗口测试是否稳定，不依赖真实睡眠导致 flaky。
3. 多光标 undo 粒度是否符合一次用户动作。
4. redo branch 和 clean state 是否未被破坏。
5. IME/snippet 相关编辑是否仍有合理 group 行为。

建议命令：

- `cargo test -p editor-core --test undo_coalescing`
- `cargo test -p editor-core --test undo_redo`
- `cargo test -p editor-core --test undo_tree`

### T18 实现：多折叠区域 visual/logical 往返修正

状态：TODO

范围文件：

- `crates/editor-core/src/intervals.rs`
- `crates/editor-core/src/commands.rs` 或 `visual_rows.rs`
- `crates/editor-core/tests/folding_stability.rs`
- 可新增 `crates/editor-core/tests/folding_visual_mapping.rs`

已知入口：

- `FoldingManager::logical_to_visual`
- `FoldingManager::visual_to_logical`
- `EditorCore::visual_to_logical_line`
- `EditorCore::logical_position_to_visual`
- `VisualRowIndex::span_for_visual_row`
- `VisualRowIndex::span_for_logical_line`

实现要求：

1. 先添加覆盖多个 collapsed region 的往返测试，确认当前行为。
2. 若 `FoldingManager::visual_to_logical` 错位，修正累计 hidden lines 的坐标基准。
3. 优先复用 `VisualRowIndex` 作为权威 visual/logical 映射，避免 core 中保留两套逻辑。
4. 折叠 start line 可见，`start_line + 1..=end_line` 隐藏的语义不变。

测试要求：

1. 多个非重叠 collapsed region 的 visual->logical->visual 往返。
2. 相邻 collapsed region 的边界。
3. 包含 soft wrap 的折叠区域。
4. 运行 `cargo test -p editor-core --test folding_stability`。
5. 运行 `cargo test -p editor-core --test folding_visual_mapping`，若新增。

验收标准：

- 多折叠区域映射稳定且与 `EditorCore` viewport 行一致。

### T18R Review：审查多折叠映射修正

状态：TODO

审查范围：T18 的所有 diff。

审查重点：

1. `visual_to_logical` 是否仍混用被 hidden lines 污染后的 logical 与原始 region start。
2. start line 可见语义是否保持。
3. soft wrap 下 visual_in_logical 是否正确。
4. 是否减少了重复映射实现。
5. 测试是否覆盖多个、相邻、尾部折叠区域。

建议命令：

- `cargo test -p editor-core --test folding_stability`
- `cargo test -p editor-core`

### T19 实现：LSP UTF-16 代理对边界修正

状态：TODO

范围文件：

- `crates/editor-core-lsp/src/lsp_sync.rs`
- `crates/editor-core-lsp/src/editor.rs`
- `crates/editor-core-lsp/tests/diagnostics_processing_edits.rs`
- 可新增 `crates/editor-core-lsp/tests/utf16_boundaries.rs`

已知入口：

- `LspCoordinateConverter::utf8_to_utf16_len`
- `LspCoordinateConverter::char_offset_to_utf16`
- `LspCoordinateConverter::utf16_to_char_offset`
- `LspCoordinateConverter::lsp_to_char_offset`
- `char_offset_for_lsp_position` in `editor.rs`
- `lsp_diagnostics_to_processing_edits`
- `semantic_tokens_to_intervals`

实现要求：

1. `utf16_to_char_offset` 遇到目标 offset 落在代理对中间时，返回该字符起点或最近合法边界；策略必须在注释和测试中固定。
2. 超大 `character` 做饱和 clamp，不允许 `as` 转换导致异常行为。
3. `char_offset_for_lsp_position` 对越界 line/character 做明确 clamp。
4. diagnostics 和 semantic tokens 使用同一转换策略。

测试要求：

1. 对文本 `a👋b` 测试 UTF-16 offset 0、1、2、3、4。
2. 半个代理对 diagnostics range 不应扩展到错误字符之后。
3. `u32::MAX` character 被 clamp 到行尾。
4. 运行 `cargo test -p editor-core-lsp --test utf16_boundaries`，若新增。
5. 运行 `cargo test -p editor-core-lsp --test diagnostics_processing_edits`。

验收标准：

- 畸形 LSP UTF-16 坐标不会污染 diagnostics/token 区间。

### T19R Review：审查 LSP UTF-16 边界修正

状态：TODO

审查范围：T19 的所有 diff。

审查重点：

1. 半代理对策略是否明确且一致。
2. 是否所有 LSP 坐标入口都使用同一转换函数。
3. 是否还有 `as usize` 造成越界/截断风险。
4. emoji 后的普通字符 offset 是否未偏移。
5. diagnostics 和 semantic token 测试是否都覆盖。

建议命令：

- `cargo test -p editor-core-lsp --test utf16_boundaries`
- `cargo test -p editor-core-lsp --test diagnostics_processing_edits`
- `cargo test -p editor-core-lsp`

### T20 实现：文档清理和实现一致性修正

状态：TODO

范围文件：

- `docs/DESIGN.md`
- `docs/abi-v1-draft.md`
- `crates/editor-core/src/lib.rs`

已知修正点：

- `DESIGN.md` 中 LineIndex “many edit paths rebuild rope from full text”的表述。
- `DESIGN.md` 中 folding “not automatically shifted”的表述。
- `lib.rs` 中 PieceTable “O(1) insertion/deletion”的说法。
- `lib.rs` 中 grapheme/word-aware 与 DESIGN non-goal 的冲突。
- `lib.rs` 拼写/断词：`Subscribe toState changed`、`soft wrappinglayout engine`、`andcode foldingmanagement`。
- `docs/abi-v1-draft.md` 中 handle 线程/别名约束和数组 `count/out_cap` 契约。

实现要求：

1. 文档只能描述当前真实能力，不写尚未实现的承诺。
2. grapheme 支持要拆开描述：命令层哪些支持，布局/坐标仍按 Unicode scalar 的地方要说明。
3. PieceTable 复杂度要按当前实现描述，不再写 O(1)。
4. folding 文档要区分用户 fold 平移、派生 fold 刷新和 LSP 异步版本策略。
5. ABI 文档要把 handle 单线程独占从建议改为调用契约。

测试要求：

1. 文档任务通常不需 cargo test。
2. 若修改 doc test 示例，运行 `cargo test -p editor-core --doc`。

验收标准：

- 文档不再与实现明显矛盾。

### T20R Review：审查文档一致性修正

状态：TODO

审查范围：T20 的所有 diff。

审查重点：

1. 文档是否描述现状而非未来计划。
2. 复杂度表述是否准确且不过度承诺。
3. grapheme/word/Unicode scalar 边界是否说清。
4. ABI 调用契约是否足够明确。
5. 示例代码是否仍能编译或至少语义正确。

建议命令：

- `cargo test -p editor-core --doc`，仅当修改 doc test 示例时运行。

### T21 实现：核心 panic 与错误处理专项

状态：TODO

范围文件：

- `crates/editor-core/src/storage.rs`
- `crates/editor-core/src/commands.rs`，或拆分后的 `undo.rs`
- `crates/editor-core-ui/`，仅做统计和单独记录，不混入核心修复
- `crates/editor-core-app/`，仅做统计和单独记录，不混入核心修复
- 可新增 `crates/editor-core/tests/undo_history_robustness.rs`

已知入口：

- `PieceTable::get_text` 中 `std::str::from_utf8(...).unwrap()`
- `PieceTable::get_range` 中 `std::str::from_utf8(...).unwrap()`
- `PieceTable::split_piece` 中 `std::str::from_utf8(...).unwrap()`
- `UndoRedoManager` 中 `self.nodes[...]` 直接索引
- `UndoRedoManager` 中 `.parent.unwrap_or(0)`
- `expect("checked")` 风格不变量表达

实现要求：

1. 将核心库生产路径的 `unwrap/expect/panic` 分为测试、不可达不变量、可恢复错误三类。
2. `storage.rs` UTF-8 unwrap 改为 debug_assert + fallible helper，或在 API 层返回 `Result`。
3. `UndoRedoManager` 裸索引改为 checked access；stale/tombstone node 不应 panic。
4. `editor-core-ui` / `editor-core-app` 只建立后续专项记录，不在本任务大范围修改。
5. 不要用吞错隐藏数据损坏；遇到不变量破坏应返回明确错误或 debug panic。

测试要求：

1. Undo history restore 遇到非法/stale node 时返回错误而非 panic。
2. Piece 边界异常若可构造，验证不会生产路径 panic。
3. 运行 `cargo test -p editor-core`。

验收标准：

- 核心库生产路径 panic 数量下降。
- 剩余 panic 有明确不可恢复不变量说明。

### T21R Review：审查 panic 与错误处理专项

状态：TODO

审查范围：T21 的所有 diff。

审查重点：

1. 是否把可恢复错误改成了明确 `Result` 或 `CommandError`。
2. 是否有吞错导致静默数据损坏。
3. undo node checked access 是否覆盖所有直接索引路径。
4. `storage.rs` UTF-8 不变量是否仍有 debug 检查。
5. 是否避免把 `editor-core-ui` / `editor-core-app` 大范围修改混进核心任务。

建议命令：

- `cargo test -p editor-core`

### T22 实现：阶段性全量收口

状态：TODO

范围文件：

- 仅限修复前面任务遗留的测试、格式化、clippy 和文档一致性问题

执行要求：

1. 运行 `cargo fmt`。
2. 运行 `cargo test -p editor-core`。
3. 运行 `cargo test -p editor-core-lsp`。
4. 运行 `cargo test -p editor-core-ffi`。
5. 运行 `cargo test`。
6. 运行 `cargo clippy --all-targets --all-features`。
7. 只修复上述命令暴露的问题，不引入新功能。

验收标准：

- 全量测试和 clippy 通过，或所有失败都有明确外部原因记录。

### T22R Review：审查阶段性全量收口

状态：TODO

审查范围：T22 的所有 diff 和测试输出。

审查重点：

1. 是否只有测试/格式化/clippy 修复，没有混入新功能。
2. 失败命令是否有清晰记录和后续任务。
3. 是否遗漏了 P0/P1/P2/P3 中任一必须测试的 crate。
4. 文档、ABI、测试矩阵是否最终一致。

建议命令：

- `cargo test`
- `cargo clippy --all-targets --all-features`
