# Codex Rust Review - 2026-07-24

## 范围

本次 review 只覆盖 Rust workspace，不覆盖 `swift/` 目录和 SwiftPM 集成代码。

重点阅读范围包括：

- `crates/editor-core/`：核心文本模型、命令执行、状态管理、workspace、多 view、folding、delta。
- `crates/editor-core-ui/`：UI 层状态、Tree-sitter 异步处理、folding/highlight 测试。
- `crates/editor-core-lsp/`：LSP 同步、workspace edit、文本编辑转换。
- `crates/editor-core-app/`：文件保存和 workspace I/O。
- `crates/editor-core-ffi/`、`crates/editor-core-ui-ffi/`：FFI 边界和 ABI 测试做了抽样阅读。
- `docs/DESIGN.md` 和 `AGENTS.md`。

本文件按 code review 口径组织：问题优先，按严重程度排序；设计评价和建议计划放在后面。

## 总体结论

Rust 侧的总体架构方向是清晰的：`TextBuffer` / `LineIndex` 作为文本真相源，PieceTable 逐步退为兼容/调试 shadow；公开 API 倾向使用 char offset，LSP UTF-16 坐标转换被隔离在 LSP 层；layout、folding、style、diagnostics 作为 derived state 分层维护。这些方向是合理的。

当前主要风险集中在三类：

1. Folding 的 correctness 语义不够稳，已经能看到确定性的索引错误和重叠区间统计问题。
2. 增量流和异步处理的契约不清晰，`TextDelta` 的 last-only 存储和若干消费者的“每次编辑都可观察”预期不一致。
3. Workspace 多 view 共享 executor scratch state，部分 view-local 配置会产生调用顺序相关行为。

另外，当前全量 Rust 测试不绿，失败集中在 `editor-core-ui` 的 Tree-sitter 异步测试超时。这个问题应当作为合并前阻断项处理。

## 验证命令

已运行：

```bash
cargo test -p editor-core --all-targets
cargo check --workspace --all-targets --exclude editor-core-render-skia --exclude editor-core-ui --exclude editor-core-ui-ffi
cargo check --workspace --all-targets
cargo test --workspace --all-targets
cargo test -p editor-core-ui --lib ui_treesitter_highlight_and_folding_roundtrip -- --nocapture
RUST_BACKTRACE=1 cargo test -p editor-core-ui --lib ui_treesitter_highlight_and_folding_roundtrip -- --nocapture
```

结果：

- `cargo test -p editor-core --all-targets` 通过。
- `cargo check --workspace --all-targets --exclude editor-core-render-skia --exclude editor-core-ui --exclude editor-core-ui-ffi` 通过。
- `cargo check --workspace --all-targets` 通过。
- `cargo test --workspace --all-targets` 失败，失败点在 `editor-core-ui`。
- 单独复跑 `ui_treesitter_highlight_and_folding_roundtrip` 可稳定复现同类 timeout。

全量测试失败时，`editor-core-ui` 中以下测试超时：

- `tests::ui_gutter_click_toggles_fold_state`
- `tests::ui_nested_fold_unfold_sequence_keeps_inner_toggleable`
- `tests::ui_treesitter_highlight_and_folding_roundtrip`
- `tests::ui_treesitter_runtime_config_can_be_updated_while_running`
- `tests::ui_treesitter_uses_incremental_updates_when_deltas_available`

共同 panic 点：

- `crates/editor-core-ui/src/lib.rs:6181`
- panic 文案：`timeout waiting for async processing`

## Findings

### 1. 高：全量 Rust 测试不绿，Tree-sitter 异步测试稳定超时

相关位置：

- `crates/editor-core-ui/src/lib.rs:6173`：`wait_for_async_processing`
- `crates/editor-core-ui/src/lib.rs:6181`：timeout panic
- `crates/editor-core-ui/src/lib.rs:7722`：`ui_treesitter_highlight_and_folding_roundtrip` 调用等待逻辑
- `crates/editor-core-ui/src/lib.rs:181` 到 `205`：`TreeSitterProcessingConfig` 默认配置
- `crates/editor-core-ui/src/lib.rs:251` 到 `258`：`TreeSitterAsyncWorker` 关键状态字段
- `crates/editor-core-ui/src/lib.rs:2750` 到 `2838`：`poll_processing`

现象：

`cargo test --workspace --all-targets` 在 `editor-core-ui` 停下，5 个 Tree-sitter / folding 相关测试超时。单独复跑 `ui_treesitter_highlight_and_folding_roundtrip` 也会稳定失败，失败点仍是 `wait_for_async_processing`。

影响：

这是当前最直接的工程阻断项。它会导致 workspace 全量测试不可用于合并前验证，也会掩盖后续修改引入的新回归。

可能原因：

- Tree-sitter worker 已经完成处理，但 UI 侧 `pending` 判定没有收敛。
- worker 发送事件失败或事件未被消费，导致 `applied_version` 没有推进。
- `requested_version` / `applied_version` / `last_update_mode` 的状态转换存在 race 或遗漏。
- 测试的等待条件把 LSP pending 或其他异步源误计入 Tree-sitter pending。
- 默认 debounce / cooldown / query budget 与测试等待策略不匹配，但单测稳定超时更像状态收敛 bug，而不只是时间太短。

建议修复方案：

1. 在 `wait_for_async_processing` timeout 前输出关键状态，至少包括：
   - `requested_version`
   - `applied_version`
   - `last_update_mode`
   - worker channel 是否 disconnected
   - 最近一次收到的 worker event 类型
   - `poll_processing` 返回 pending 的具体来源
2. 拆分 `poll_processing` 的 pending 语义，不要只返回一个笼统 bool。建议临时或长期改成类似：

   ```rust
   struct ProcessingPending {
       treesitter: bool,
       lsp: bool,
       worker_connected: bool,
       requested_version: Option<u64>,
       applied_version: Option<u64>,
   }
   ```

3. 对测试 helper 使用 Tree-sitter 专用等待条件，避免 LSP 或其他 derived-state pending 影响 Tree-sitter 测试。
4. 如果确认是 worker 未发送 `Processed`，在 `TreeSitterAsyncWorker` loop 的 `Init`、`Update`、`NeedFullSync`、`Error` 路径补充错误传播和测试断言。
5. 加一个小型单测覆盖“set language 后无编辑，worker 必须推进到当前 buffer version 并清空 pending”。

验收标准：

- `cargo test -p editor-core-ui --lib ui_treesitter_highlight_and_folding_roundtrip -- --nocapture` 稳定通过。
- `cargo test --workspace --all-targets` 不再因为这 5 个测试失败。

### 2. 高：`FoldingManager::toggle_region_starting_at_line` 对切片相对下标写回原数组，目标 fold 会切错

相关位置：

- `crates/editor-core/src/intervals.rs:821` 到 `872`：`toggle_region_starting_at_line`
- `crates/editor-core/src/intervals.rs:842`：`regions[idx..].iter().enumerate()`
- `crates/editor-core/src/intervals.rs:854`：保存 `best_match = Some((i, ...))`
- `crates/editor-core/src/intervals.rs:864`：`regions.get_mut(idx)`
- `crates/editor-core/src/commands.rs:437`：fold toggle 命令入口之一
- `crates/editor-core/src/state.rs:1060`：state manager fold toggle 入口之一

问题：

`toggle_region_starting_at_line` 先找到了同 source 下第一个 `start_line >= line` 的区域位置 `idx`，然后在 `regions[idx..]` 上做 `enumerate()`。这里枚举出来的 `i` 是切片相对下标，不是 `regions` 的绝对下标。但后面保存并使用的是这个相对下标：

```rust
for (i, region) in regions[idx..].iter().enumerate() {
    ...
    best_match = Some((i, region.start_line));
}
...
if let Some(region) = regions.get_mut(idx) {
    region.collapsed = !region.collapsed;
}
```

当目标 fold 不是该 source 的第一个 region 时，会切换错误的 region。多 fold 文件中，通过 gutter 或 cursor 折叠某一行时，用户看到的折叠状态可能作用到前面的另一个区域。

建议修复方案：

保存绝对下标：

```rust
for (relative_i, region) in regions[idx..].iter().enumerate() {
    let absolute_i = idx + relative_i;
    ...
    best_match = Some((absolute_i, region.start_line));
}
```

同时补回归测试：

1. 同一个 `FoldSource` 下至少有 3 个 region。
2. 调用 `toggle_region_starting_at_line` 的 line 命中第 2 或第 3 个 region。
3. 断言只有目标 region 的 `collapsed` 翻转，前面的 region 不变。
4. 最好覆盖 exact start line 和“从 region 内部某行触发，选择最近合法 fold”的分支。

验收标准：

- 新增测试在修复前失败，修复后通过。
- gutter click、cursor fold toggle 在多 fold 文件中目标一致。

### 3. 高：`EditorStateManager::get_folding_state` 对重叠/嵌套 collapsed folds 直接求和，可能 panic 或返回错误统计

相关位置：

- `crates/editor-core/src/state.rs:894` 到 `910`：`get_folding_state`
- `crates/editor-core/src/state.rs:897`：对 collapsed region 的隐藏行数直接 `sum`
- `crates/editor-core/src/state.rs:903`：`line_count - collapsed_line_count`
- `crates/editor-core/tests/folding_visual_mapping.rs:29`：已有视觉映射测试说明系统允许重叠/嵌套 folding 情况

问题：

`get_folding_state` 当前用所有 collapsed region 的 `end_line - start_line` 直接求和，然后用：

```rust
visible_logical_lines: line_count - collapsed_line_count
```

如果 collapsed folds 重叠或嵌套，隐藏行会被重复计数。轻则 `collapsed_line_count` 和 `visible_logical_lines` 错误，重则在 debug build 中发生整数下溢 panic。

影响：

UI 状态、状态查询、外部集成或 FFI 消费者拿到的 folding summary 可能不可信。因为已有视觉映射测试覆盖了重叠情况，说明系统内部并不禁止这类区间。

建议修复方案：

把 collapsed line count 改为按 hidden line union 计算，而不是直接相加。可选实现：

1. 收集 collapsed regions 对应的隐藏行区间：

   ```rust
   // folded region [start_line, end_line] 通常隐藏 start_line + 1..=end_line
   let hidden_start = region.start_line.saturating_add(1);
   let hidden_end_exclusive = region.end_line.saturating_add(1);
   ```

2. 丢弃空区间和越界区间。
3. 按 start 排序并 merge overlap / adjacent ranges。
4. 对 merge 后区间长度求和。
5. `visible_logical_lines` 使用 `line_count.saturating_sub(collapsed_line_count)`，但真正修复应保证 union count 不会超过 line count。

需要补充测试：

- 嵌套 collapsed folds：外层 `0..10`，内层 `2..5`，隐藏行不能重复计算。
- 部分重叠 collapsed folds：`0..5` 和 `3..8`。
- 超界/空文档边界：避免 panic。

验收标准：

- `get_folding_state` 在重叠/嵌套区间下不 panic。
- `collapsed_line_count` 等于实际隐藏行 union 的长度。
- `visible_logical_lines + collapsed_line_count <= line_count`。

### 4. 中高：`TextDelta` 是 last-only 存储，但消费者按 pending queue 语义使用，连续编辑会丢增量

相关位置：

- `crates/editor-core/src/delta.rs:16`：`TextDelta` 文档说明 edits in order
- `crates/editor-core/src/workspace.rs:1154` 到 `1175`：`take_buffer_text_delta` 文档说明每次 buffer edit 应被观察一次
- `crates/editor-core/src/workspace.rs:1322`：覆盖 `last_text_delta`
- `crates/editor-core/src/workspace.rs:2391`：覆盖 `last_text_delta`
- `crates/editor-core-lsp/src/workspace_sync.rs:277`：LSP 同步消费 delta
- `crates/editor-core-app/src/search_results.rs:88`：搜索结果消费 delta

问题：

Workspace 对每个 buffer 只保存一个 `last_text_delta`。如果同一个 buffer 连续发生两次编辑，而某个消费者在两次编辑之间没有调用 `take_buffer_text_delta`，第一次 delta 会被第二次覆盖。

这和 `take_buffer_text_delta` 的文档语义冲突：文档描述更像 pending queue 或“每次编辑都能被观察一次”的事件流。

影响：

- LSP incremental sync 可能漏发某次编辑。
- 搜索结果、derived state 或其他依赖 delta 的消费者可能基于不完整增量更新。
- 如果某个消费者假设 delta 连续，漏 delta 会造成后续坐标映射错误。

建议修复方案：

优先选一个明确语义，并让实现、文档、消费者一致。

推荐方案 A：改成 per-buffer pending queue。

```rust
struct BufferEntry {
    pending_text_deltas: VecDeque<TextDelta>,
}
```

- 每次编辑 push delta。
- `take_buffer_text_delta` pop front，或新增 `drain_buffer_text_deltas` 一次性取走全部。
- 对 LSP 这类需要有序增量的消费者，使用 drain 后按顺序发送。
- 对只需要最终状态的消费者，可以选择 coalesce。

推荐方案 B：保留 last-only，但明确它是 coalesced snapshot delta。

- 文档改为“只保留自上次消费以来的合并 delta”。
- 连续编辑时把旧 delta 和新 delta 合并成一个等价 delta，而不是覆盖。
- 如果不能可靠合并，消费者必须 fallback 到 full sync。

不建议继续保持当前状态：字段名、文档和消费者预期都指向事件流，但实现是 last-write-wins。

需要补充测试：

1. 对同一 buffer 连续执行两次 edit，中间不 take delta。
2. 之后 drain delta。
3. 断言两次编辑都可观察，或者得到一个等价的 coalesced delta。
4. LSP incremental sync 测试应断言不会漏掉第一段变更。

验收标准：

- `take_buffer_text_delta` 的文档和行为一致。
- 连续编辑不会静默丢失 delta。

### 5. 中高：LSP `WorkspaceEdit.documentChanges[].textDocument.version` 被忽略，默认 auto-apply 可能应用 stale edit

相关位置：

- `crates/editor-core-lsp/src/editor.rs:88`：`LspDocument` version
- `crates/editor-core-lsp/src/lsp_text_edits.rs:123` 到 `141`：`TextDocumentEdit` version 字段未进入结构化结果
- `crates/editor-core-lsp/src/lsp_text_edits.rs:165` 到 `183`：workspace edit 解析路径
- `crates/editor-core-lsp/src/workspace_sync.rs:64`：`auto_apply_workspace_edits` 默认 true
- `crates/editor-core-lsp/src/workspace_sync.rs:239` 到 `258`：`workspace/applyEdit` auto apply
- `crates/editor-core-lsp/src/workspace_sync.rs:303` 到 `328`：`apply_workspace_edit`
- `crates/editor-core-lsp/src/workspace_sync.rs:336` 到 `390`：`apply_workspace_edit_to_workspace`

问题：

LSP `WorkspaceEdit` 的 `documentChanges` 可以带 `VersionedTextDocumentIdentifier.version`。这个 version 用来表达服务器生成 edit 时基于的文档版本。当前解析逻辑没有保留/比较该 version，默认 auto-apply 打开时可能把 stale edit 应用到已经改变过的 buffer 上。

影响：

格式化、rename、code action、organize imports 等 LSP 操作可能在用户继续编辑后把旧 edit 应用到新文本，造成错误修改。

建议修复方案：

1. 在 workspace edit 解析结果中保留 optional expected version，例如：

   ```rust
   struct DocumentTextEdit {
       uri: Url,
       expected_version: Option<i32>,
       edits: Vec<TextEdit>,
   }
   ```

2. apply 前查询当前 tracked `LspDocument.version`。
3. 如果 `expected_version` 存在且与当前版本不一致：
   - 不自动应用该 document edit。
   - 返回 skipped/conflict 信息。
   - 对 `workspace/applyEdit` 返回 `applied: false` 或部分失败说明，具体取决于当前 API 能表达的粒度。
4. 对没有 version 的 edit 维持现有行为。
5. 对跨文件 workspace edit，建议采用 all-or-nothing。只要任何文件 version conflict，就拒绝整个 workspace edit，避免产生部分应用状态。

需要补充测试：

- 构造 version 匹配的 workspace edit，应成功应用。
- 构造 version 不匹配的 workspace edit，应拒绝应用且 buffer 不变。
- `auto_apply_workspace_edits = true` 时也必须执行 version 检查。

验收标准：

- stale workspace edit 不会静默应用。
- API 返回结果能让调用方知道 edit 被拒绝或冲突。

### 6. 中：Workspace 多 view 默认状态依赖共享 executor 的最近 scratch 状态

相关位置：

- `crates/editor-core/src/workspace.rs:117` 到 `132`：`ViewCore::from_executor`
- `crates/editor-core/src/workspace.rs:135` 到 `174`：`ViewCore::apply_to_executor`
- `crates/editor-core/src/workspace.rs:703` 到 `725`：`create_view`
- `crates/editor-core/src/workspace.rs:715`：新 view 从 buffer executor 当前状态派生
- `crates/editor-core/src/workspace.rs:1976`、`2029`、`2048`、`2070`、`2121`、`2149`、`2180`：多个只读 view API 也会把 view 状态 apply 到共享 executor
- `crates/editor-core-ui/src/lib.rs:885`：`EditorUi::clone_view` 调用 `create_view`

问题：

Workspace 使用一个 buffer executor，并在 view 操作前把 `ViewCore` apply 到 executor。问题是 `create_view` 会通过 `ViewCore::from_executor(&buffer_entry.executor)` 从 executor 当前 scratch 状态派生新 view。由于很多只读查询也会 apply view-local state，新 view 的初始 view-local 配置取决于最近一次对哪个 view 执行过查询或渲染。

影响：

如果同一 buffer 有 view A 和 view B，它们具有不同 tab width、indent、auto-pairs、word-boundary 等 view-local 配置，那么新建 view C 可能继承 A 或 B，取决于之前谁最后触碰过 executor。这是调用顺序相关行为，不适合作为 workspace API 语义。

建议修复方案：

1. 修改 `create_view` API，使其明确 parent view：

   ```rust
   pub fn create_view_from(&mut self, parent_view_id: ViewId) -> Result<ViewId, WorkspaceError>
   ```

   新 view 复制 parent view 的 `ViewCore`。

2. 保留 `create_view(buffer_id)` 时，不从 executor scratch state 派生，而从 buffer-level default view config 派生。
3. 对 `EditorUi::clone_view` 使用 `create_view_from(current_view_id)`，让“clone”语义明确复制当前 view。
4. 对只读查询是否需要 mutate executor scratch state 做隔离。可以接受内部 apply，但不能让这个 scratch state 成为新 view 默认值来源。

需要补充测试：

- 同 buffer 创建 view A、B，分别设置不同 tab width。
- 对 A 做一次只读查询，再 create C；对 B 做一次只读查询，再 create D。
- 如果使用默认 create，C/D 应相同；如果使用 clone，C 应等于 A，D 应等于 B。

验收标准：

- 新 view 初始化不受最近一次查询/渲染顺序影响。
- clone view 的配置来源可预测。

### 7. 中：单 buffer `EditorStateManager` 与 Workspace 对 view config 命令的通知语义不一致

相关位置：

- `crates/editor-core/src/model.rs:892`：`ViewCommand::is_mutating`
- `crates/editor-core/src/workspace.rs:1235`：Workspace 对 `ViewCommand` 发通知
- `crates/editor-core/src/state.rs:629` 到 `687`：`EditorStateManager::change_type_for_command`
- `crates/editor-core/src/state.rs:678` 到 `687`：若干 view config 命令返回 `None`
- `crates/editor-core/src/commands.rs:1384`：命令执行器实际修改 view config

问题：

某些 view config 命令确实会修改状态，但 `EditorStateManager::change_type_for_command` 返回 `None`，导致单 buffer manager 的订阅者收不到状态变化通知。Workspace 路径对 `ViewCommand::is_mutating` 的处理更接近正确语义。

影响：

使用 `EditorStateManager` 而非 Workspace 的集成方，在 tab behavior、indent、auto-pairs、word-boundary 等配置变化后可能无法刷新 UI 或持久化状态。

建议修复方案：

1. 统一 `EditorStateManager` 和 Workspace 的 mutation 判定来源。
2. 可把 `ViewCommand::is_mutating` 作为单一真相源，`change_type_for_command` 对 mutating view command 返回 `Some(StateChangeType::View)` 或等价类型。
3. 如果某些 config 命令故意不通知，需要在命令定义处明确说明，并补测试锁定语义。

需要补充测试：

- 对单 buffer `EditorStateManager` 订阅变更。
- 执行 tab width / indent / auto-pairs / word-boundary 相关命令。
- 断言订阅者收到通知，且通知类型与 Workspace 路径一致。

验收标准：

- 相同命令在 `EditorStateManager` 和 Workspace 路径的通知行为一致。

### 8. 中：`save_buffer_as` 先改 URI 再写文件，失败会留下错误路径状态

相关位置：

- `crates/editor-core-app/src/workspace_io.rs:70` 到 `79`：`save_buffer`
- `crates/editor-core-app/src/workspace_io.rs:82` 到 `91`：`save_buffer_as`
- `crates/editor-core-app/src/workspace_io.rs:88`：先设置新 URI
- `crates/editor-core-app/src/workspace_io.rs:90`：再调用 `save_buffer`

问题：

`save_buffer_as` 当前先把 buffer URI 改成新路径，然后调用 `save_buffer` 写文件。如果写文件失败，buffer 内部 URI 已经变成目标路径，但文件并没有成功保存。

影响：

- UI 可能显示文件已经位于新路径。
- 后续保存会继续尝试写错误路径。
- dirty / clean point 语义可能与真实磁盘状态不一致。
- 用户可能误以为 Save As 已成功。

建议修复方案：

推荐 all-or-nothing：

1. 先从 buffer snapshot 读取内容。
2. 尝试写入新路径。
3. 写入成功后再更新 buffer URI 和 clean point。
4. 写入失败则保持原 URI 和 dirty 状态不变。

如果当前 API 必须通过 `save_buffer` 复用逻辑，可以在失败时 rollback URI，但更好的方式是拆出一个低层 `write_buffer_contents(path, snapshot)`，避免为了写文件提前修改 editor state。

需要补充测试：

- 使用不可写路径或目录路径触发 Save As 失败。
- 断言失败后 buffer URI 仍是原路径。
- 断言 dirty 状态不被错误清理。
- 成功 Save As 后断言 URI 和 clean point 更新。

验收标准：

- Save As 失败不会改变 buffer 的路径状态。

## 设计评价

### 做得好的部分

- 文本核心和派生状态的边界比较清楚。`TextBuffer` / `LineIndex` 管文本和索引，layout/folding/style/diagnostics 作为派生层维护，方向正确。
- API 对 offset 单位的意识较强。公开层主要使用 char offset，避免把 byte offset 泄漏到核心逻辑。
- LSP UTF-16 坐标转换被限制在 LSP crate 内，这是正确的边界。
- FFI 边界没有看到同等级的明显内存安全问题。抽样阅读中能看到 `catch_unwind`、空指针检查、字符串释放、blob 两阶段输出和固定宽度 ABI 测试。
- Workspace / view 的抽象已经能表达多 buffer、多 view，这是后续 UI、TUI、FFI 集成的好基础。

### 主要薄弱点

- Folding 的区间语义需要统一。视觉映射允许重叠/嵌套，但 summary 统计没有按 union 处理，toggle 路径还有确定性索引错误。
- Delta 的 delivery contract 需要重新定义。当前实现是 last-only，但文档和 LSP/search 等消费者更像需要 ordered stream。
- 多 view 通过共享 executor scratch state 间接传递默认配置，容易产生顺序相关行为。
- 异步 derived state 的 pending 状态缺少可诊断信息，导致测试失败时很难第一时间知道卡在 worker、event channel、version 推进还是等待条件。

## 建议修复优先级

### P0：先恢复全量测试和 folding correctness

1. 修复 `editor-core-ui` Tree-sitter async timeout，至少让失败时输出足够诊断信息。
2. 修复 `FoldingManager::toggle_region_starting_at_line` 的相对下标 bug。
3. 修复 `get_folding_state` 对重叠/嵌套 collapsed fold 的统计。

这三项优先级最高，因为它们分别影响 CI 可用性、用户可见行为和状态查询正确性。

### P1：修正跨模块契约风险

1. 明确并修复 `TextDelta` delivery 语义，推荐改成 per-buffer pending queue 或可靠 coalesced delta。
2. LSP workspace edit apply 前校验 `VersionedTextDocumentIdentifier.version`。
3. 调整 Workspace `create_view` / `clone_view`，避免从共享 executor scratch state 派生默认 view state。

这三项会影响 LSP、搜索、UI 多 view 等较宽的行为面，建议在 P0 后尽快处理。

### P2：补齐一致性和失败回滚

1. 统一 `EditorStateManager` 与 Workspace 的 view config 命令通知语义。
2. 修复 `save_buffer_as` 失败后的 URI rollback / all-or-nothing 行为。
3. 为上述修改补小而集中的回归测试。

## 建议新增测试清单

- `editor-core`：fold toggle 多 region 非首项命中测试。
- `editor-core`：nested / overlapping collapsed folds 的 `get_folding_state` union 统计测试。
- `editor-core` 或 `editor-core-lsp`：同一 buffer 连续两次编辑，中间不消费 delta，之后 drain 不丢变更。
- `editor-core-lsp`：workspace edit version match / mismatch 测试。
- `editor-core`：多 view 不同 view-local config 下，新建 view 不受最近一次只读查询影响。
- `editor-core`：`EditorStateManager` view config 命令通知测试。
- `editor-core-app`：`save_buffer_as` 写失败不改变 URI 和 dirty/clean 状态测试。
- `editor-core-ui`：Tree-sitter set language 后 pending 能收敛到当前 buffer version 的最小测试。

## 建议落地顺序

1. 先加 failing regression tests：fold toggle、folding state union、save as rollback。
2. 修掉两个 folding bug，并跑：

   ```bash
   cargo test -p editor-core --all-targets
   ```

3. 给 `editor-core-ui` 的 async timeout 增加诊断输出，再定位是 worker 未完成还是 pending 判定不收敛。
4. 修复 Tree-sitter async pending 问题，并跑：

   ```bash
   cargo test -p editor-core-ui --lib ui_treesitter_highlight_and_folding_roundtrip -- --nocapture
   cargo test -p editor-core-ui --all-targets
   ```

5. 处理 `TextDelta` 与 LSP version check，这两项建议分开提交，避免把 delta contract 和 LSP apply 语义混在一个 diff 中。
6. 处理 Workspace 多 view 默认状态，给 `create_view` / `clone_view` 明确语义。
7. 最后跑：

   ```bash
   cargo check --workspace --all-targets
   cargo test --workspace --all-targets
   ```

## 备注

- 本次 review 未修改代码。
- 当前工作区在 review 时存在未跟踪文件 `notification.sh` 和 `run_agent.sh`，未处理。
- Swift 部分未阅读，不对 SwiftPM、Swift bridge 或 Apple 平台封装做结论。
