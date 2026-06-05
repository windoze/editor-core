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

### [DONE] T01 实现：LSP 子进程生命周期回收

状态：DONE

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

完成记录：

- 将 `LspClient` 的 `_child` 改为可操作的 `child`，新增 `shutdown` / `exit` / `terminate` 生命周期方法；`shutdown` 会发送 `shutdown` 请求、短超时等待响应、发送 `exit`，超时或 I/O 异常时执行 `kill` + `wait`。
- 为 `LspClient` 实现 `Drop` 兜底回收，确保仍在运行的子进程会被 kill 后 wait。
- 将 `LspSession::exit` 改为使用新的生命周期回收路径；保留低层 `LspSession::shutdown` 请求 API，并记录已请求状态，避免手动 shutdown 后 exit 再次发送 shutdown。
- 新增 `crates/editor-core-lsp/tests/lsp_process_lifecycle.rs`，覆盖 `LspClient` drop 回收、不响应 shutdown 的 session exit 强制回收、响应 shutdown 的 session exit 成功路径。
- 验证过程中 `cargo clippy --all-targets -- -D warnings` 暴露了若干既有 lint 阻塞项，已做等价最小修复；完整测试首次运行暴露了一个 `editor-core-ui-ffi` fold marker 像素测试不稳定/不一致问题，已通过固定 `Block` marker 样式和匹配 gutter 宽度修正。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_process_lifecycle`、`cargo test -p editor-core-lsp`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py`，无可运行的完整 fixture runner。

### [DONE] T01R Review：审查 LSP 子进程生命周期回收

状态：DONE

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

完成记录：

- 已审查 T01 diff，重点检查 `LspClient::shutdown` / `exit` / `terminate` / `Drop`、`LspSession::exit` 生命周期接入，以及 `lsp_process_lifecycle` 测试。
- 未发现需要立即修复或新增前置任务的生命周期缺陷；`kill()` 后和自然退出路径都会进入 `wait()`，`Drop` 忽略错误且不主动 join 后台线程，测试覆盖不响应 shutdown、响应 shutdown 和 drop 回收路径。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_process_lifecycle`、`cargo test -p editor-core-lsp`。

### [DONE] T02 实现：diagnostics 版本守卫

状态：DONE

范围文件：

- `crates/editor-core-lsp/src/editor.rs`
- `crates/editor-core-lsp/src/lsp_sync.rs`
- `crates/editor-core-lsp/tests/diagnostics_processing_edits.rs`
- 可新增 `crates/editor-core-lsp/tests/diagnostics_versioning.rs`

执行备注：`crates/editor-core-lsp/src/workspace_sync.rs` 会对非 active document 的 `publishDiagnostics` 另行生成 processing edits；为避免同一版本守卫缺口残留，T02 需要额外纳入该文件的最小修改。

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

完成记录：

- 在 `LspSession` 中新增 diagnostics 版本匹配判断：`version` 缺失时保持兼容应用；`version` 存在时必须匹配已跟踪文档版本；有版本但 URI 未被 session 跟踪时不应用。
- 将版本守卫接入 active document 的 `publishDiagnostics` processing-edit 生成路径，旧版本 diagnostics 仍会进入 `LspEvent::Notification` 和普通 unhandled notification 观察路径。
- 将同一守卫接入 `workspace_sync.rs` 的非 active document diagnostics 路由，避免 workspace 侧绕过 session 守卫后继续用当前 buffer `LineIndex` 生成派生状态。
- 扩展 `diagnostics_processing_edits.rs`，覆盖旧版本 diagnostics 不生成 `ReplaceStyleLayer` / `ReplaceDiagnostics`、当前版本正常生成派生状态、无版本 diagnostics 兼容应用三种情况。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-lsp --test diagnostics_processing_edits`、`cargo test -p editor-core-lsp`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py`，无可运行的完整 fixture runner。

### [DONE] T02R Review：审查 diagnostics 版本守卫

状态：DONE

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

完成记录：

- 已审查 T02 diff，重点检查 `LspSession::diagnostics_version_matches`、active document `publishDiagnostics` processing-edit 生成路径、`workspace_sync.rs` 非 active buffer diagnostics 路由，以及新增 diagnostics 版本测试。
- 未发现需要立即修复或新增前置任务的问题；旧版本 diagnostics 保留 `LspEvent::Notification` 可观测性但不生成 diagnostics 派生状态，当前版本正常生成 `ReplaceStyleLayer` / `ReplaceDiagnostics`，无版本 diagnostics 继续按兼容策略应用。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test diagnostics_processing_edits`、`cargo test -p editor-core-lsp`。

### [DONE] T03 实现：`wait_for_response` 保留其它在途响应

状态：DONE

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

完成记录：

- 在 `LspClient` 中新增 FIFO `deferred_inbound` 缓存；`try_recv` 优先返回缓存内容，再读取 channel。
- 重写 `wait_for_response` 等待路径：目标 response 返回给调用方；其它 response、notification、malformed id 消息按原始顺序缓存，供后续 poll / `try_recv` 观察。
- 等待期间的 server->client request 仍通过 `handle_server_request` 自动响应；只有已成功处理的 server request 不再重新投递，避免初始化或阻塞等待死锁。
- 更新 `LspSession::wait_for_response` 文档，明确其它 response/notification 会继续排队。
- 新增 `crates/editor-core-lsp/tests/lsp_wait_for_response.rs`，覆盖乱序 response 保留、等待期间 server request 自动响应、notification 保留、malformed response id 保留，以及 malformed server request 经 session poll 可观察。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_wait_for_response`、`cargo test -p editor-core-lsp`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py`，无可运行的完整 fixture runner。

### [DONE] T03R Review：审查 `wait_for_response` 响应缓存

状态：DONE

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

完成记录：

- 已审查 T03 diff，重点检查 `LspClient::wait_for_response` / `try_recv` 的 FIFO 缓存路径、`LspSession` poll 处理、server request 自动响应、malformed id 可观察性，以及 `lsp_wait_for_response` 覆盖。
- 未发现需要立即修复或新增前置任务的问题；非目标 response/notification/malformed id 会按原始顺序留在缓存中，已处理的 server request 不会重复投递，`try_recv` 先排空缓存再读 channel 以保持顺序。
- 缓存增长风险限于阻塞等待期间到达的非目标 inbound 消息；等待有调用方提供的 timeout，且任务场景要求保留这些消息以避免丢失 pending response。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_wait_for_response`、`cargo test -p editor-core-lsp`。

### [DONE] T04 实现：折叠派生状态版本化与折叠态保留

状态：DONE

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

完成记录：

- 将 `preserve_collapsed` 的折叠态保留逻辑下沉到 `FoldingManager::replace_derived_regions_preserving_collapsed`，`EditorStateManager` 和 `Workspace` 的 `ReplaceFoldingRegions` 应用路径共享同一策略。
- 保留策略先按精确 `(start_line, end_line)` 匹配 collapsed 派生 fold；再对同 placeholder、start 附近、范围重叠且长度接近的区域做保守匹配，覆盖小范围行号漂移，且只从派生 fold 继承状态，不把用户 fold collapsed 状态复制到派生 fold。
- 保持 LSP folding response 在进入 core state 前按 `PendingLspRequest::FoldingRanges { version }` 丢弃旧版本，并在 `ProcessingEdit::ReplaceFoldingRegions` 文档中明确异步版本响应需由 producer 先过滤。
- 扩展 `folding_stability.rs`，覆盖行号漂移后 collapsed 保留、用户 fold 与派生 fold 折叠态边界、多个派生 collapsed fold 在插入/删除后继续平移。
- 新增 `crates/editor-core-lsp/tests/folding_versioning.rs`，覆盖当前版本 folding response 产生 `ReplaceFoldingRegions`，以及编辑后旧版本 response 不产生替换 edit 且不会覆盖已平移的多个 collapsed region。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core-lsp --test folding_versioning`、`cargo test -p editor-core`、`cargo test -p editor-core-lsp`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py`，无可运行的完整 fixture runner。

### [DONE] T04R Review：审查折叠版本化与折叠态保留

状态：DONE

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

完成记录：

- 已审查 T04 diff，重点检查 `LspSession::handle_pending_response` 的 folding 版本守卫、`ProcessingEdit::ReplaceFoldingRegions` 文档和 match 点、`FoldingManager::replace_derived_regions_preserving_collapsed`、`EditorStateManager` / `Workspace` 应用路径，以及新增 `folding_stability` / `folding_versioning` 测试。
- 未发现旧版本 LSP folding response 进入 core state 的问题；当前版本检查在生成 `ReplaceFoldingRegions` 前完成，`ProcessingEdit` enum 形状未变，已知构造和 match 点可继续编译覆盖。
- 发现 T04 后续修复项：`collapsed_fuzzy_match_score` 对默认 placeholder 的相邻或仅共享边界 derived fold 匹配过宽，可能把无关 region 错误继承为 collapsed；新增测试也未实际先构建 visual-row cache 再验证 fold 替换/清理后的 cache 重建。
- 已在 T05 前新增 `T04F` / `T04FR`，要求先修复该问题并补充专项 review。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core-lsp`。

### [DONE] T04F 修复：收紧折叠态保留匹配并补 visual-row cache 回归

状态：DONE

依赖：

- T04R 审查发现的折叠态误继承风险和 visual-row cache 测试缺口。

范围文件：

- `crates/editor-core/src/intervals.rs`
- `crates/editor-core/src/state.rs`
- `crates/editor-core/src/workspace.rs`
- `crates/editor-core/tests/folding_stability.rs`

已知入口：

- `FoldingManager::collapsed_fuzzy_match_score`
- `FoldingManager::replace_derived_regions_preserving_collapsed`
- `EditorStateManager::replace_folding_regions`
- `Workspace::apply_processing_edits` 中处理 `ReplaceFoldingRegions` / `ClearFoldingRegions`
- `EditorCore::visual_line_count` / visual-row cache 构建路径

实现要求：

1. 收紧 derived fold collapsed 保留的模糊匹配，避免默认 placeholder 的相邻 region、仅共享边界 region 或明显不相关 region 继承 collapsed 状态。
2. 保留 T04 已覆盖的小范围行号漂移场景；若匹配策略改变，需要用测试固定允许继承的正向条件和禁止继承的负向条件。
3. 补充 visual-row cache 回归：先通过 `visual_line_count` 或 viewport API 构建 cache，再替换或清理 folding regions，验证后续 visual/logical 行数或 viewport 反映最新 fold state。
4. 不改变用户 fold 与派生 fold 的边界；用户 fold collapsed 状态仍不得复制到派生 fold。

测试要求：

1. 默认 placeholder 的相邻或仅边界重叠 derived folds 不会错误继承 collapsed。
2. 小范围行号漂移后同一 derived fold 仍能保留 collapsed。
3. `ReplaceFoldingRegions` 和 `ClearFoldingRegions` 后 visual-row cache 会按最新 fold state 重建。
4. 运行 `cargo test -p editor-core --test folding_stability`。
5. 运行 `cargo test -p editor-core`。

验收标准：

- 折叠态保留不会把无关 derived region 错配成 collapsed。
- fold 替换和清理后的 visual-row cache 行为有明确回归测试。

完成记录：

- 收紧 `FoldingManager::collapsed_fuzzy_match_score`：fuzzy 匹配仍要求同 placeholder、起始行最多漂移 1 行、长度接近，并新增至少共享两行的要求，避免默认 placeholder 的仅边界重叠区域误继承 collapsed。
- 扩展 `folding_stability.rs`，新增默认 placeholder 边界/相邻负向回归，并保留小范围行号漂移后同一 derived fold 继承 collapsed 的正向覆盖。
- 新增 `EditorStateManager` 与 `Workspace::apply_processing_edits` 的 visual-row cache 回归：先通过 visual line 查询构建旧 cache，再执行 `ReplaceFoldingRegions` / `ClearFoldingRegions`，验证后续 visual/logical 映射反映最新 fold state。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core`、`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。
- 未找到 `tools/run_fixtures.py`，无可运行的完整 fixture runner。

### [DONE] T04FR Review：审查折叠态保留匹配修复

状态：DONE

审查范围：T04F 的所有 diff。

审查重点：

1. 模糊匹配是否足够保守，尤其是默认 placeholder、相邻区域和仅共享边界区域。
2. 正向漂移保留是否未被过度收紧破坏。
3. 用户 fold 与派生 fold 的 collapsed 状态是否仍严格隔离。
4. visual-row cache 回归测试是否确实先构建旧 cache，再验证替换/清理后的新结果。
5. 是否引入新的全局特殊 casing 或 fixture-only workaround。

建议命令：

- `cargo test -p editor-core --test folding_stability`
- `cargo test -p editor-core`

完成记录：

- 已审查 T04F diff，重点检查 `FoldingManager::collapsed_fuzzy_match_score` 的保守匹配条件、默认 placeholder 边界/相邻负向覆盖、小范围行号漂移正向覆盖、用户 fold 与派生 fold collapsed 状态隔离，以及 `EditorStateManager` / `Workspace` 的 visual-row cache 回归测试。
- 未发现需要立即修复或新增前置任务的问题；fuzzy 匹配要求同 placeholder、起始行最多漂移 1 行、长度接近且至少共享两行，新增测试会先构建旧 visual-row cache 再验证替换和清理后的映射结果。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core`。

### [DONE] T05 实现：新增 `TextBuffer` 抽象并建立一致性校验

状态：DONE

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

完成记录：

- 新增内部 `TextBuffer` 模块，直接持有 `ropey::Rope` 并提供 `len_chars`、`len_bytes`、`line_count`、`insert`、`delete`、`get_text`、`get_range`、`get_line_text`、position/offset 转换和 char/byte offset 转换能力。
- 将 `LineIndex` 改为委托 `TextBuffer`，保留现有公开 `EditorCore.line_index` 字段和 `PieceTable` 字段，避免引入第四份完整文本副本。
- 将 `EditorCore::get_text` 和 `EditorCore::char_count` 改为优先读取 `TextBuffer`；命令编辑路径继续写入 `PieceTable`，并在 `apply_text_change_to_line_index_and_layout` 中新增 debug-only 全文一致性断言。
- 新增 `crates/editor-core/tests/text_buffer_single_source.rs`，覆盖空文档、末尾无换行、末尾有换行、CJK、emoji、CRLF 入口归一化、range/line 读取、插入删除以及 `PieceTable` 影子一致性。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test text_buffer_single_source`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py`，无可运行的完整 fixture runner。

### [DONE] T05R Review：审查 `TextBuffer` 抽象

状态：DONE

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

完成记录：

- 已审查 T05 diff，重点检查 `TextBuffer` char offset API、`LineIndex` 包装方式、`EditorCore::get_text` / `char_count` 读路径、编辑命令中的 `PieceTable` 影子写入和 debug-only 一致性断言，以及 `text_buffer_single_source` 覆盖。
- 未发现需要立即修复或新增前置任务的问题；`TextBuffer` 边界保持 Unicode scalar / char offset 语义，`LineIndex` 以 `TextBuffer` 替代原有 Rope 字段而非新增额外完整文本副本，CRLF 仍由 `EditorCore` / 编辑命令入口归一化，末尾换行、Unicode、range/line 读取和影子一致性已有测试覆盖。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test text_buffer_single_source`、`cargo test -p editor-core`。
- 本次 review 未修改编译代码；T05 完成记录已有 `cargo test --all --all-targets` 通过结果，因此未重复运行全量测试或 fixture suite。

### [DONE] T06 实现：移除 `LayoutEngine.line_texts` 文本副本

状态：DONE

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

完成记录：

- 删除 `LayoutEngine.line_texts` 字段，布局引擎只保留 wrap 参数和每个逻辑行的 `VisualLineInfo`；`from_lines` / `add_line` / `update_line` / `insert_line` 仍接收文本用于即时计算但不再保存文本。
- 新增 `LayoutEngine::recalculate_all_from_lines`，将 viewport width、wrap mode、wrap indent、tab width 变化后的全量重排改为由调用方显式提供行文本。
- 将 `CommandExecutor` 视图设置路径、workspace 视图状态恢复路径和 `SnapshotGenerator` 改为从 `LineIndex`/自身行列表触发重排，并在 core 重排后失效 visual-row cache。
- 调整 `LayoutEngine::logical_position_to_visual` / `logical_position_to_visual_allow_virtual`，由调用方传入对应行文本，避免布局层为了坐标计算保留文本副本。
- 扩展 `crates/editor-core/tests/incremental_viewport_consistency.rs`，覆盖编辑后 viewport 与参考重建一致，以及 resize、wrap mode、wrap indent、tab width 变化后的快照一致性和 visual-row cache 重建。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test incremental_viewport_consistency`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 已确认 `tools/run_fixtures.py` 不存在，完整 fixture suite 无可运行入口。

### [DONE] T06R Review：审查移除 layout 文本副本

状态：DONE

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

完成记录：

- 已审查 T06 diff，重点检查 `LayoutEngine` 是否彻底移除 `line_texts` 文本副本、全量重排是否由调用方提供行文本、`CommandExecutor` / `Workspace` / `SnapshotGenerator` 的视图参数变更路径，以及 `incremental_viewport_consistency` 的增量与参考重建比对。
- 未发现需要立即修复或新增前置任务的问题；当前 Rust 代码中已无 `line_texts` 引用，主视图参数变更路径会从 `LineIndex` 读取当前文本后重排并失效 visual-row cache，新增测试覆盖编辑、undo/redo、viewport width、wrap mode、wrap indent、tab width 变化后的快照一致性。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test incremental_viewport_consistency`、`cargo test -p editor-core`。

### [DONE] T07 实现：废弃并移出主路径的 `PieceTable`

状态：DONE

范围文件：

- `crates/editor-core/src/storage.rs`
- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/lib.rs`
- `crates/editor-core/tests/text_buffer_single_source.rs`
- `crates/editor-core/tests/undo_redo.rs`
- `crates/editor-core/tests/line_ops.rs`

执行备注：`crates/editor-core/src/workspace.rs` 仍通过公开 `EditorCore.piece_table` 读取 buffer 字符数和 range；`crates/tui-editor/src/main.rs`、`crates/editor-core/examples/state_management.rs`、`crates/editor-core/tests/integration_test.rs` 和 `crates/editor-core/src/state.rs` 文档示例也有直接字段访问。为完成 T07 的 `piece_table` 私有化与主路径迁移，需要纳入这些最小调用点修改。

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

完成记录：

- 将 `EditorCore.piece_table` 从公开字段移除，改为 debug-only 私有 `piece_table_shadow`，仅用于迁移期一致性断言；release 主路径不再持有 PieceTable 影子副本。
- 新增 `EditorCore::text_range`，将 `commands.rs`、`workspace.rs`、TUI 复制逻辑、state 示例和集成测试中的文本读写迁移到 `LineIndex` / `TextBuffer` API。
- 保留 `storage::PieceTable` 兼容模块，并将根 re-export `editor_core::PieceTable` 标记为 deprecated；旧 PieceTable 验证测试改为直接通过 `editor_core::storage::PieceTable` 使用兼容模块，避免 deprecation warning。
- 将 `apply_text_change_to_line_index_and_layout` 的文本变更统一落到 `LineIndex` / `TextBuffer`，并在 debug 构建同步 `piece_table_shadow` 后断言两者一致。
- 更新 `text_buffer_single_source.rs`，覆盖 `EditorCore::text_range` 的 Unicode/range/clamp 读取，以及命令编辑后 `EditorCore` 与 `LineIndex` 文本一致。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test text_buffer_single_source`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core`、`cargo test --all --all-targets`、`cargo test -p editor-core --doc`。
- 未找到 `tools/run_fixtures.py` 或其它 `tools/**/*fixture*` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T07R Review：审查 `PieceTable` 废弃迁移

状态：DONE

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

完成记录：

- 已审查 T07 diff，重点检查 `PieceTable` 是否仍参与主编辑路径、deprecated 兼容 API 标注、undo/redo 的 `deleted_text` / `inserted_text` 记录、`TextDelta` 的 before/after char count，以及完整文本副本是否被保留在 release 主路径。
- 未发现需要立即修复或新增前置任务的问题；当前主路径未发现 `piece_table.insert/delete/get_text/get_range` 调用，剩余 `PieceTable` 使用限于 deprecated 兼容模块、测试、deprecated root re-export 和 debug-only `piece_table_shadow`。
- `EditorCore::get_text` / `char_count` / `text_range` 统一走 `LineIndex` / `TextBuffer`；undo/redo 和文本 delta 计数通过 `EditorCore::char_count` 获取，删除/插入文本记录继续来自 char-offset range API。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core`。

### [DONE] T08 实现：视觉行映射索引增量化

状态：DONE

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

完成记录：

- 新增 `crates/editor-core/src/visual_rows.rs`，将 `VisualRowIndex` / `VisualRowSpan` 从 `commands.rs` 移出，并改为每个 logical line 的 visible visual-count + Fenwick tree 前缀和索引。
- `EditorCore::visual_line_count`、`visual_to_logical_line`、`logical_position_to_visual`、`visual_position_to_logical` 和 viewport/minimap 路径统一走新索引；`LayoutEngine` / `FoldingManager` 的线性转换不再参与这些核心热路径。
- 删除编辑/折叠命令开始时的无条件 visual-row cache 失效；单行文本编辑会按受影响 logical line 更新 wrap count，多行结构变化会同步插入/删除索引项并刷新局部范围，折叠/展开会刷新对应折叠区间。
- 修正 `FoldingManager::apply_line_delta` 后立即重建 merged fold view，保证编辑期间增量 visual-row 索引读取到平移后的折叠状态。
- 新增 `crates/editor-core/tests/visual_row_index.rs`，覆盖缓存已构建后的 fold/unfold 同步、折叠 + soft wrap + CJK/emoji 的 logical/visual 往返，以及 10 万行文档尾部 visual 查询在连续单行编辑后的性能回归。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test visual_row_improvements`、`cargo test -p editor-core --test visual_row_index`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T08R Review：审查视觉行索引增量化

状态：DONE

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

完成记录：

- 已审查 T08 diff，重点检查 `VisualRowIndex` / Fenwick 前缀和、`EditorCore` 视觉行映射入口、文本编辑后的缓存同步、fold/unfold 同步路径，以及新增 `visual_row_index` 测试。
- 发现 T08 后续修复项：`InsertNewline`、`DeleteForward` / `Backspace`、boundary 删除等真实换行编辑路径会调用 `apply_text_change_to_line_index_and_layout` 触发视觉行缓存增量同步，但没有像 `Insert` / `Delete` / `Replace` / `apply_text_ops` 那样先执行 `FoldingManager::apply_line_delta`，已构建缓存可能与平移后的折叠语义错位。
- 同时发现覆盖缺口和残留路径：新增测试未覆盖多个折叠区域、尾部空行/末尾换行、真实换行插入删除命令与 cached visual mapping 的组合；TUI 仍可直接修改 `folding_manager` 而不失效或同步视觉行缓存；带 virtual text 的 composed viewport 仍从文档头部线性扫描。
- 已在 T09 前新增 `T08F` / `T08FR`，要求先修复上述问题并补充专项 review。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test visual_row_improvements`、`cargo test -p editor-core --test visual_row_index`、`cargo test -p editor-core`。

### [DONE] T08F 修复：补齐视觉行索引换行与折叠同步

状态：DONE

依赖：

- T08R 审查发现的视觉行缓存与 folding 同步缺口、测试覆盖缺口和 composed viewport 残留线性路径。

范围文件：

- `crates/editor-core/src/commands.rs`
- `crates/editor-core/src/visual_rows.rs`
- `crates/editor-core/src/intervals.rs`
- `crates/editor-core/src/state.rs`
- `crates/editor-core/src/workspace.rs`
- `crates/tui-editor/src/main.rs`
- `crates/editor-core-ui/src/lib.rs`，仅当 composed viewport 调用路径需要同步调整
- `crates/editor-core/tests/visual_row_index.rs`
- `crates/editor-core/tests/visual_row_improvements.rs`

已知入口：

- `CommandExecutor::apply_text_change_to_line_index_and_layout`
- `CommandExecutor::execute_insert_newline_command`
- `CommandExecutor::execute_delete_like_command`
- `CommandExecutor::execute_delete_by_boundary_command`
- `EditorCore::sync_visual_row_index_after_text_change`
- `EditorCore::sync_visual_row_index_for_logical_range`
- `FoldingManager::apply_line_delta`
- `EditorCore::get_headless_grid_composed`
- TUI `toggle_fold_at_cursor` / `unfold_all`

实现要求：

1. 所有可能改变换行数的文本编辑路径必须在视觉行缓存增量同步前按同一语义更新 `FoldingManager`，覆盖 `InsertNewline`、`DeleteForward` / `Backspace`、boundary 删除、普通 `Insert` / `Delete` / `Replace` 和 `apply_text_ops`。
2. 消除重复或遗漏的 folding line-delta 逻辑；若保留多个调用点，必须用测试覆盖每类真实命令路径。
3. cached `VisualRowIndex` 在折叠状态变化、用户 fold 变化、TUI 直接 fold/unfold 路径和 processing/workspace fold 替换路径后不得过窄更新或保留旧状态。
4. 多行插入/删除更新 `VisualRowIndex` 时不得对每个新增/删除行重复全量重建 Fenwick tree；至少应批量变更后重建一次或使用等价批量更新。
5. 带 virtual text 的 composed viewport 不得继续在尾部 viewport 上从文档头部线性扫描 document visual rows；若需要额外 composed-prefix 索引，应在本任务内实现，不得以 fixture-only 特例绕过。
6. 保持 `LayoutEngine` / `FoldingManager` 旧线性转换 API 的兼容性，但核心 editor/UI viewport 和坐标查询热路径不得继续依赖旧线性实现。

测试要求：

1. 缓存已构建后，`InsertNewline`、`DeleteForward`、`Backspace`、boundary 删除跨换行时，多个 collapsed fold 的 `visual_line_count`、`visual_to_logical_line` 和 `logical_position_to_visual` 保持正确。
2. 覆盖多个折叠区域、嵌套或相邻折叠区域、尾部空行、末尾有换行、末尾无换行与 soft wrap 的组合。
3. 覆盖 TUI 或等价直接 fold/unfold 调用路径不会留下 stale visual-row cache。
4. 覆盖 composed viewport 在存在 above-line / inline virtual text 时的尾部 viewport 映射与性能行为。
5. 运行 `cargo test -p editor-core --test visual_row_index`。
6. 运行 `cargo test -p editor-core --test visual_row_improvements`。
7. 运行 `cargo test -p editor-core`。

验收标准：

- 所有真实换行编辑路径后的 folding state 与 cached visual-row index 一致。
- 多 fold、尾部空行和 virtual text composed viewport 均有明确回归覆盖。
- 大文件尾部 viewport / visual-row 查询不因残留线性路径退化到从文档头部扫描。

完成记录：

- 将 folding line-delta 收敛到 `apply_text_change_to_line_index_and_layout`，确保 `InsertNewline`、`DeleteForward` / `Backspace`、boundary 删除、普通 `Insert` / `Delete` / `Replace`、多光标文本插入和 `apply_text_ops` 都先按同一语义平移 folding，再同步 cached `VisualRowIndex`。
- 将 `VisualRowIndex` 多行结构变更改为批量 `insert_lines` / `remove_lines` 后重建一次 Fenwick tree，避免多行插入/删除逐行重复重建。
- 保持 processing/workspace fold replace/clear 路径的缓存失效，并补齐 TUI 直接 `toggle_fold_at_cursor` / `unfold_all` 后的 visual-row cache 失效。
- 优化 core composed viewport 起点计算：利用 visual-row index 和 above-line virtual text 前缀计数直接定位尾部 composed 起点，不再从文档头逐行扫描；同步将 UI 的 doc-row 到 composed-row 映射改为只遍历 above-line decorations。
- 扩展 `visual_row_index.rs`，覆盖 cached 状态下 `InsertNewline`、`DeleteForward`、`Backspace`、boundary 删除跨换行后的多 collapsed fold 映射，adjacent folds + soft wrap + 尾部空行，直接 fold mutation 失效重建，以及带 above-line / inline virtual text 的 10 万行尾部 composed viewport 映射与性能。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test visual_row_index`、`cargo test -p editor-core --test visual_row_improvements`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T08FR Review：审查视觉行索引同步修复

状态：DONE

审查范围：T08F 的所有 diff。

审查重点：

1. 所有换行编辑命令是否统一更新 folding 后再同步视觉行缓存，且没有重复平移 fold。
2. 多个 collapsed fold、尾部空行和末尾换行的 cached visual mapping 是否正确。
3. TUI / workspace / processing 等 fold 变更路径是否都会同步或失效 visual-row cache。
4. composed viewport 是否不再保留尾部线性扫描热路径。
5. Fenwick 批量插入/删除是否避免 O(k*n) 重建并保持前缀和正确。

建议命令：

- `cargo test -p editor-core --test visual_row_index`
- `cargo test -p editor-core --test visual_row_improvements`
- `cargo test -p editor-core`

完成记录：

- 已审查 T08F diff，重点检查 `apply_text_change_to_line_index_and_layout` 是否统一承担 folding line-delta、各多光标/删除/替换路径是否移除重复平移、`VisualRowIndex::insert_lines` / `remove_lines` 批量更新、TUI 直接 fold/unfold 失效路径、workspace/state processing fold replace/clear 失效路径，以及 composed viewport 起点定位逻辑。
- 未发现需要立即修复或新增前置任务的问题；换行编辑会先平移 folding 再同步 cached visual-row index，fold replace/clear 路径会失效缓存，TUI 直接折叠变更已补失效，composed viewport 使用 visual-row index 与 above-line prefix 定位尾部起点。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test visual_row_index`、`cargo test -p editor-core --test visual_row_improvements`、`cargo test -p editor-core`。
- 本次 review 未修改编译代码；T08F 完成记录已有 `cargo clippy --all-targets --all-features -- -D warnings` 和 `cargo test --all --all-targets` 通过结果，因此未重复运行全量测试或 fixture suite。

### [DONE] T09 实现：行级命令避免全文读取

状态：DONE

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

完成记录：

- 将 `slice_text_for_lines` 改为根据 logical line 计算 char offset 区间，并通过 `EditorCore::text_range` 读取受影响行范围，避免逐行拼接或读取全文。
- 将 `execute_duplicate_lines_command` 的末尾换行判断从 `EditorCore::get_text().ends_with('\n')` 改为读取最后一个 char；T09 行级命令路径不再因该判断分配完整文档 `String`。
- 保留搜索/替换命令的全文读取路径，并通过定向 grep 确认剩余 `EditorCore::get_text()` 调用属于搜索路径、公开 API、debug-only 一致性断言或测试代码。
- 扩展 `line_ops.rs`，覆盖 duplicate/delete/move/join 在末尾无换行、末尾有换行、多光标和 Unicode 行下的行为。
- 扩展 `comment_toggle.rs`，覆盖多行、Unicode 和空行的 line comment toggle；扩展 `workspace_search_apply.rs`，覆盖 Unicode apply-text-edits 的 undo range 准确性。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test workspace_search_apply`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T09R Review：审查行级命令性能优化

状态：DONE

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

完成记录：

- 已审查 T09 diff，重点检查 `slice_text_for_lines` range 读取、`DuplicateLines` 末尾换行判断、Delete/Move/Join/ToggleComment/ApplyTextEdits 的删除文本和 undo range 记录，以及搜索/替换全文读取路径隔离。
- 未发现需要立即修复或新增前置任务的问题；普通行级编辑路径未发现新增 `EditorCore::get_text()` 全文读取，剩余全文读取集中在搜索/替换、公有文本 API、debug-only 一致性断言或测试代码。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test line_ops`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core`。

### [DONE] T10 实现：优化列到字节转换

状态：DONE

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

完成记录：

- 新增 `leading_horizontal_whitespace`，用单次 `char_indices` 扫描同时得到行注释缩进的 char column 和 byte offset，保留现有 char column 语义。
- 将 line comment toggle 改为预先收集每个目标行的文本与缩进扫描结果，comment/uncomment 判断和实际 edit 构建复用该结果，不再对同一缩进 column 调用 `byte_offset_for_char_column` 重复扫描。
- 将 uncomment 删除 token 后空格的检查改为基于已切出的 `rest` 后缀读取，避免再次从行首按 char column 扫描。
- 扩展 `comment_toggle.rs`，覆盖 CJK、emoji、tab、空白缩进，以及长行多选区 toggle comment 的退化回归。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test unicode_segmentation`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T10R Review：审查列字节转换优化

状态：DONE

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

完成记录：

- 已审查 T10 diff，重点检查 `leading_horizontal_whitespace` 单次缩进扫描、`execute_toggle_line_comment` 中 char column / byte offset 边界、token 后空格删除、tab 按字符列处理语义，以及旧 `byte_offset_for_char_column` 是否仍处于 ToggleComment 热路径。
- 未发现需要立即修复或新增前置任务的问题；ToggleComment 已复用每行缩进扫描结果，注释插入/删除继续使用 char offset/char length，`rest.get(token.len()..)` 仅在 `starts_with(token)` 后访问合法 token 字节边界。
- 测试覆盖已包含 CJK、emoji、tab、空白缩进、Unicode 多行和 token 后空格删除，以及长行多选区退化回归。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test comment_toggle`、`cargo test -p editor-core --test unicode_segmentation`。

### [DONE] T11 实现：IntervalTree 更新路径降本

状态：DONE

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

完成记录：

- 新增 `IntervalTextEdit` 与 `IntervalTree::update_for_text_edits`，按 pre-edit start 降序批量应用文本变更；每棵 tree 在一轮批量更新后只重建一次 `prefix_max_end`，并在必要时保持 interval start 排序不变量。
- 将 `CommandExecutor` 的文本编辑更新路径统一收敛到 `update_interval_trees_for_text_edits`：多光标 insert/type/tab/newline/delete、indent/outdent、apply text edits、snippet additional edits、undo/redo 以及单次 insert/delete/replace 都先收集 interval delta，再对 base interval tree 和各 style layer 各批量更新一次。
- `apply_text_ops` 改为先基于 pre-edit 坐标准备删除文本和 interval delta，再执行实际文本变更，避免批量 edit 期间每个 edit 对每个 style layer 反复全量更新。
- 新增 `crates/editor-core/tests/interval_tree_updates.rs`，覆盖插入、删除、跨 interval 删除、完整删除 interval，以及多 style layer 下批量 edit 后 style range 与逐步更新语义一致；扩展 `intervals.rs` 单元测试覆盖批量更新与查询正确性。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test interval_tree_updates`、`cargo test -p editor-core --test diagnostics`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T11R Review：审查 IntervalTree 更新优化

状态：DONE

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

完成记录：

- 已审查 T11 diff，重点检查 `IntervalTree::update_for_text_edits`、`apply_insertion_to_interval` / `apply_deletion_to_interval`、`prefix_max_end` 重建、命令层批量 edit 接入，以及新增 `interval_tree_updates` 测试。
- 未发现需要立即修复或新增前置任务的问题；批量更新按降序 edit 保持与旧逐步更新一致的 `[start, end)` 删除和插入语义，更新后会必要时重排 interval 并重建 `prefix_max_end`，base interval tree 与各 style layer 共享同一批量更新路径。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test interval_tree_updates`、`cargo test -p editor-core --test diagnostics`、`cargo test -p editor-core`。
- 本次 review 未修改编译代码；T11 完成记录已有 `cargo clippy --all-targets --all-features -- -D warnings` 和 `cargo test --all --all-targets` 通过结果，因此未重复运行全量 workspace 测试或 fixture suite。

### [DONE] T12 实现：限制 `command_history` 内存增长

状态：DONE

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

完成记录：

- 定向确认 `get_command_history` 只在 `commands.rs`、测试和示例中使用，未发现生产消费者。
- 将 `CommandExecutor` 的 `command_history` 改为有界调试历史，默认保留最近 1000 条命令，并新增 `command_history_limit` / `set_command_history_limit`，`0` 可关闭历史记录。
- 历史记录在执行前保存命令摘要，继续记录失败命令；大文本字段只保留 UTF-8 边界安全的短预览和原始 byte 长度说明，避免 `InsertText` / replace / snippet / text edits / search 字符串在 history 中额外完整 clone。
- 新增 `crates/editor-core/tests/command_history.rs`，覆盖超过容量只保留最近命令、禁用历史记录、执行大 `InsertText` 仍修改正文但 history 只保存摘要。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test command_executor_commands`、`cargo test -p editor-core --test command_history`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T12R Review：审查 command_history 内存控制

状态：DONE

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

完成记录：

- 已审查 T12 diff，重点检查 `CommandExecutor` 的有界 `command_history`、大文本命令摘要、`get_command_history` API 兼容性、默认容量和禁用历史记录路径。
- 未发现需要立即修复或新增前置任务的问题；history 默认保留最近 1000 条，`0` 可禁用，超过容量会裁剪旧记录，大文本字段会按 UTF-8 边界保存短预览和原始 byte 长度说明，不再把大 `InsertText` 完整克隆到 history。
- 定向确认 `get_command_history` 当前只用于 core 测试和示例；公开返回类型保持 `&[Command]`，但文档已说明大文本 payload 是摘要。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test command_executor_commands`、`cargo test -p editor-core --test command_history`、`cargo test -p editor-core`。

### [DONE] T13 实现：纯移动拆分 `commands.rs`

状态：DONE

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

完成记录：

- 新增 `crates/editor-core/src/model.rs`，移动公开命令/坐标/选择模型并通过 `commands` 模块继续 re-export，保持根 `editor_core::{CommandExecutor, Position, Selection}` 等导出兼容。
- 新增 `crates/editor-core/src/undo.rs`，移动 `TextEdit`、`UndoStep`、`UndoRedoManager`、`UndoNode` 和 undo history snapshot/restore 类型；公开快照类型继续经 `commands` re-export。
- 复用既有 `visual_rows.rs`，未重复创建视觉行索引模块。
- 新增 `edit_ops.rs`、`line_ops.rs`、`cursor_ops.rs`、`render_grid.rs`，分别移动编辑命令、行级命令/注释切换、光标/选择/词边界、viewport/minimap/composed snapshot 相关实现；`commands.rs` 保留 `EditorCore` / `CommandExecutor` 主结构、核心访问器和 view/style dispatch。
- 各移动切片后均运行并通过 `cargo test -p editor-core`；最终验证已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-lsp`、`cargo test -p editor-core-ffi`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T13R Review：审查 `commands.rs` 纯移动拆分

状态：DONE

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

完成记录：

- 已审查 T13 diff，重点检查 `commands.rs` 拆分到 `model.rs`、`undo.rs`、`edit_ops.rs`、`line_ops.rs`、`cursor_ops.rs`、`render_grid.rs` 后是否混入业务逻辑改动，公开 re-export 是否保持兼容，以及新增模块是否过度 public 或形成跨 crate 破坏。
- 未发现需要立即修复或新增前置任务的问题；T13 变更限于纯移动、路径调整和必要的 `pub(super)` 可见性调整，根 `editor_core::{CommandExecutor, Position, Selection, ...}` 与 `editor_core::commands::*` 兼容路径保持可用。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-lsp`、`cargo test -p editor-core-ffi`。

### [DONE] T14 实现：收紧公开 API 和 `EditorCore` 字段

状态：DONE

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

完成记录：

- 将 `EditorCore` 的文本、layout、base/style layers、diagnostics、decorations、document symbols、folding、cursor/selection、viewport 字段改为私有，保留只读 getter（如 `line_index()`、`layout_engine()`、`style_layers()`、`folding_manager()`、`viewport_width()`）供外部检查。
- 新增或收紧受控 mutation 路径：内部通过 `set_view_options`、`set_cursor_state`、style/diagnostics/decorations/symbols/folding 替换 helper 维护同步不变量；对外 TUI 折叠改走 `EditorStateManager::toggle_fold_at_current_line` / `expand_all_folds`，避免直接修改 `FoldingManager` 后遗漏 visual-row cache/状态通知。
- 将 `intervals` / `layout` 模块路径收紧为 crate 内部模块，并通过根级 re-export 暴露必要 facade（`Interval`、`StyleId`、`StyleLayerId`、`LayoutEngine`、wrap/width helper 等）；`line_index` 与 deprecated `storage` 模块路径保留给 T15 与兼容清理继续处理。
- 更新 workspace、state、FFI、TUI、LSP/Sublime/Treesitter/highlight/UI 调用点、示例和测试，改用 getter、root facade re-export 或 StateManager/Workspace 受控 API；在 `lib.rs` 新增 API visibility 迁移说明。
- 已运行并通过：`cargo fmt`、`cargo check -p editor-core-lsp -p editor-core-ffi -p tui-editor`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-ffi`、`cargo test -p tui-editor`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T14R Review：审查公开 API 收紧

状态：DONE

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

完成记录：

- 已审查 T14 diff，重点检查 `EditorCore` 字段私有化、只读 getter、`EditorStateManager` / `Workspace` 派生状态 mutation helper、FFI/TUI/workspace 调用点，以及 `layout` / `intervals` 的 root facade re-export。
- 未发现外部可直接写入文本、layout、folding、style、diagnostics、decorations 或 cursor 字段并破坏同步不变量的 public API；公开 getter 均返回只读引用或切片，派生状态替换路径经 `EditorStateManager` / `Workspace` 受控 API 触发通知和 visual-row cache 处理。
- 发现 T14 后续文档修复项：`EditorStateManager` 文档仍建议通过 `editor_mut()` 直接修改内部状态并手动 `mark_modified()`，且 `lib.rs` module description 仍以私有 `layout` / `intervals` 模块链接描述 facade；已在 T15 前新增 `T14F` / `T14FR`。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core`、`cargo test -p editor-core-ffi`、`cargo check -p tui-editor`。

### [DONE] T14F 修复：同步公开 API 收紧文档

状态：DONE

依赖：

- T14R 审查发现的公开 API 可见性文档不一致问题。

范围文件：

- `crates/editor-core/src/lib.rs`
- `crates/editor-core/src/state.rs`
- `crates/editor-core/src/commands.rs`，仅当 `editor_mut` 文档需要同步修正

已知入口：

- `lib.rs` 的 `API Visibility` 与 `Module Description`
- `EditorStateManager` 顶层文档中关于 `editor_mut()` 直接修改内部状态和手动 `mark_modified()` 的说明
- `CommandExecutor::editor_mut` / `EditorStateManager::editor_mut` 方法文档

实现要求：

1. 文档必须与 T14 后的实际 API 可见性一致：外部 mutation 应优先走 `CommandExecutor`、`EditorStateManager`、`Workspace` 或明确受控的 public 方法。
2. 不再建议外部通过 `editor_mut()` 直接修改内部字段或绕过同步不变量；若保留 `editor_mut()` 文档，只能说明它返回受字段私有化保护的 `EditorCore`，适用于有限高级检查或 public method 调用。
3. 将 `layout` / `intervals` 私有模块的公开文档描述改为 root facade re-export 描述，避免公开 docs 暗示 `editor_core::layout` / `editor_core::intervals` 仍是 public 模块路径。
4. 不修改编译逻辑，不引入新的 API。

测试要求：

1. 运行 `cargo test -p editor-core --doc`。
2. 若只修改文档注释且 doc test 通过，可跳过完整测试套件并在完成记录说明原因。

验收标准：

- 公开文档不再鼓励绕过 T14 建立的受控 mutation API。
- 可见性迁移说明与 root facade re-export 保持一致。

完成记录：

- 更新 `lib.rs` 的 `API Visibility` 与 `Module Description`，说明 `LayoutEngine`、`IntervalTree`、`FoldingManager` 等公开类型通过 crate root facade re-export 暴露，不再暗示私有 `layout` / `intervals` 模块路径仍是 public API。
- 更新 `EditorStateManager` 顶层文档，以及 `EditorStateManager::editor_mut` / `CommandExecutor::editor_mut` 方法文档；不再建议外部直接修改内部字段或绕过同步不变量，改为强调命令、manager/workspace 受控 API 和受字段私有化保护的高级 public method 调用。
- 未修改编译逻辑，未新增 API。
- 已运行并通过：`cargo fmt`、`cargo test -p editor-core --doc`、`cargo clippy --all-targets -- -D warnings`。
- 完整测试套件未运行：本任务仅修改文档注释，且 doc test 已通过，按任务要求跳过。

### [DONE] T14FR Review：审查公开 API 文档同步修复

状态：DONE

审查范围：T14F 的所有 diff。

审查重点：

1. 文档是否准确描述 T14 后的字段私有化和受控 mutation 路径。
2. 是否仍暗示 `editor_core::layout` / `editor_core::intervals` 是 public 模块路径。
3. `editor_mut()` 文档是否避免鼓励外部绕过同步不变量。
4. doc examples 是否仍能编译。
5. 是否只做文档同步，没有混入逻辑改动。

建议命令：

- `cargo test -p editor-core --doc`

完成记录：

- 已审查 T14F diff，重点检查 `lib.rs` 的 API Visibility / Module Description、`EditorStateManager` 架构说明，以及 `CommandExecutor::editor_mut` / `EditorStateManager::editor_mut` 文档。
- 未发现需要修复或新增前置任务的问题；文档准确描述 T14 后的字段私有化与受控 mutation 路径，未继续暗示 `editor_core::layout` / `editor_core::intervals` 是 public 模块路径，`editor_mut()` 文档未鼓励绕过同步不变量。
- T14F diff 仅包含文档注释、TODO 完成记录和进度文件更新，未发现混入编译逻辑或 API 改动。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --doc`。
- 完整测试套件未运行：本 review 未修改编译逻辑，且任务要求的 doc test 与 lint 已通过。

### [DONE] T15 实现：删除或私有化 `LineIndex` 陷阱 API

状态：DONE

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

完成记录：

- 删除 `LineIndex::append_line`、`LineIndex::insert_line(LineMetadata)` 和 `LineIndex::get_line_mut`，移除会根据 `LineMetadata` 构造占位 `x` 的公开陷阱 API。
- 从 `LineMetadata` 中移除僵尸 `pieces` 字段和 `Piece` 依赖，保留当前实际可计算的 ASCII、byte length、char count 元数据。
- 将 `LineIndex::line_to_offset` / `offset_to_line` 标记为 deprecated legacy API，并补充文档说明其 byte offset 不计前序 LF 分隔符；测试调用点迁移到 `position_to_char_offset`、`char_offset_to_byte_offset`、`byte_offset_to_char_offset` 和 `char_offset_to_position`。
- 明确 `LineIndex::from_text` 是低层已归一化文本入口：Editor/Workspace 入口会先将 CRLF/lone CR 归一化为 LF；直接传入 CRLF 时 `LineIndex` 保留 `\r` 作为普通行内容，并在 `line_endings` 中固定该行为。
- 额外更新 `stage6_validation.rs` 的 LineIndex 集成测试，避免在 deprecated legacy offset API 下触发 warning。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test stage2_validation`、`cargo test -p editor-core --test line_endings`、`cargo test -p editor-core`、`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T15R Review：审查 `LineIndex` API 清理

状态：DONE

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

完成记录：

- 已审查 T15 diff 和当前源码，重点检查 `LineIndex` public API、`LineMetadata` 字段、legacy offset 迁移说明、CRLF 行尾语义测试和下游编译影响。
- 未发现需要立即修复或新增前置任务的问题：`LineIndex::append_line`、`LineIndex::insert_line(LineMetadata)`、`LineIndex::get_line_mut` 已不存在；`LineMetadata` 不再暴露 `pieces` 僵尸字段；legacy offset API 已标记 deprecated 并说明推荐迁移路径；直接 CRLF 输入行为和高层入口归一化行为均有测试覆盖。
- 已确认仓内调用点已迁移到 preferred char/byte offset API，deprecated legacy offset API 仅保留在 `line_index.rs` 内部兼容测试中且带 `#[allow(deprecated)]`。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test stage2_validation`、`cargo test -p editor-core --test line_endings`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py`、`tools/**/*fixture*` 或 `tools/` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T16 实现：FFI ABI 定宽迁移

状态：DONE

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

完成记录：

- 按 T16 要求定向检查 `extern "C" fn` 与 `usize`，确认公开 `usize` 签名集中在 `editor-core-ffi/src/lib.rs`；`editor-core-ui-ffi` 公开签名未暴露 `usize`。
- 将 `editor-core-ffi` 公开 C ABI 中的 viewport width、row/count、tab width、logical line 改为 `u32`，将文档/补全文本 char offset 改为 `u64`；内部转换到 `usize` 均通过 `try_from` helper，status-returning typed API 的转换失败映射为 `InvalidArgument`。
- 同步更新 `crates/editor-core-ffi/include/editor_core_ffi.h`，移除 public `size_t` 签名；更新 Swift `EditorCoreFFI` 包装，避免继续通过 `Int(clamping:)` 静默截断宽度/行数参数。
- 更新 `docs/abi-v1-draft.md`，明确 public 函数签名也只能使用定宽整数、`out_cap/out_len` 契约、handle 单线程独占调用契约，以及当前固定宽度 JSON/control-plane ABI 形状。
- 扩展 `crates/editor-core-ffi/tests/abi_v1.rs`，加入函数指针签名断言固定 `u32`/`u64` ABI 形状，覆盖必填输出指针 `InvalidArgument` 错误路径，并验证 LSP `u64` 边界输入不会被截断。首次新增测试触及已排期 T19 的 UTF-16 半代理对策略差异，已收窄为不覆盖 T19 行为。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`、`cargo build -p editor-core-ui-ffi --release`、`swift test`。
- 未找到 `tools/run_fixtures.py`、`tools/**/*fixture*` 或 `tools/` fixture runner，完整 fixture suite 无可运行入口。

### [DONE] T16R Review：审查 FFI ABI 定宽迁移

状态：DONE

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

完成记录：

- 已审查 T16 diff，重点检查 `editor-core-ffi` public `extern "C"` 签名、`editor_core_ffi.h`、Swift 包装、ABI 文档、typed/blob buffer 契约和 `editor-core-ui-ffi` 定宽边界。
- 定向确认 `crates/editor-core-ffi/src/lib.rs` 和 `crates/editor-core-ui-ffi/src/lib.rs` 的 public `extern "C"` 函数签名未继续暴露 `usize`；`crates/editor-core-ffi/include/editor_core_ffi.h` 未继续暴露 `size_t`。
- 发现 T16 后续修复项：ABI 文档对旧 ABI 兼容策略、public boolean 表述和当前 fixed-width public surface 覆盖不完整；`editor-core-ui-ffi` 仍存在 public `u32` / count / offset 到 internal `usize` 的 unchecked `as` 转换，以及 RGBA/range 输出长度可能截断为 `u32` 的风险。
- 已在 T17 前新增 `T16F` / `T16FR`，要求先收口上述 ABI 契约和 UI FFI 转换/长度检查问题。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo test -p editor-core-ui-ffi`。

### [DONE] T16F 修复：收口 FFI ABI 契约与 UI FFI 转换检查

状态：DONE

依赖：

- T16R 审查发现的 ABI 文档/实现不一致、UI FFI unchecked 转换和输出长度截断风险。

范围文件：

- `crates/editor-core-ui-ffi/src/lib.rs`
- `crates/editor-core-ui-ffi/tests` 或同文件内测试模块，按现有测试布局选择
- `crates/editor-core-ffi/include/editor_core_ffi.h`
- `docs/abi-v1-draft.md`

已知入口：

- `editor_core_ui_ffi_editor_ui_new`
- `editor_core_ui_ffi_editor_ui_clone_view`
- `editor_core_ui_ffi_editor_ui_lsp_request_hover`
- `editor_core_ui_ffi_editor_ui_lsp_request_definition`
- `editor_core_ui_ffi_editor_ui_set_tab_width`
- `editor_core_ui_ffi_editor_ui_minimap_json`
- `editor_core_ui_ffi_editor_ui_set_match_highlights`
- `editor_core_ui_ffi_editor_ui_render_rgba`
- `editor_core_ui_ffi_editor_ui_get_selection_ranges`
- `editor_core_ui_ffi_editor_ui_set_selection_ranges`
- `editor_core_ui_ffi_editor_ui_set_marked_text_ex`
- `editor_core_ui_ffi_editor_ui_char_offset_to_logical_position`
- `editor_core_ui_ffi_editor_ui_char_offset_to_view_point`
- `docs/abi-v1-draft.md` 的 ABI Rules、Current Fixed-Width JSON/Control-Plane Surfaces、Migration Plan

实现要求：

1. 为 `editor-core-ui-ffi` 增加统一的 `u32`/count/offset 到 `usize` 转换 helper，替换 public ABI 入参进入内部 API 前的 unchecked `as usize` 热点；失败必须返回 UI FFI 的 invalid-argument 状态并设置 last error。
2. 数组 `range_count`、style/font/decoration count、selection range count 等进入 `slice::from_raw_parts` 前必须显式检查并使用同一转换策略。
3. RGBA buffer required length、selection/range 输出 count、viewport/state 等 `usize` 到 `u32` 输出不得静默截断；无法用 `u32` 表示时返回明确错误或按文档定义的失败状态。
4. ABI 文档必须与当前实现一致：说明本轮是 pre-v1 breaking fixed-width 收口，或补充旧 ABI 兼容策略；public boolean 规则必须与 header/Rust 实现一致；Current Fixed-Width JSON/Control-Plane Surfaces 要么覆盖实际 fixed-width public surface，要么明确 header 是权威定义且该节只是代表性示例。
5. 不改变 T19 已排期的 UTF-16 半代理对策略，不用本任务绕过该行为。

测试要求：

1. 新增或扩展 UI FFI 测试，覆盖 oversized/invalid count、null output pointer、buffer-too-small two-call contract 和输出长度不可表示时的错误路径，按可构造场景选择最小覆盖。
2. 运行 `cargo test -p editor-core-ui-ffi`。
3. 运行 `cargo test -p editor-core-ffi --test abi_v1`。
4. 运行 `cargo test -p editor-core-ffi`。
5. 运行 `cargo clippy --all-targets -- -D warnings`。

验收标准：

- FFI public ABI 不暴露 `usize` / `size_t`，且从 public fixed-width 参数到 internal `usize` 的转换没有 unchecked truncation 风险。
- UI FFI two-call buffer/output count 契约不会因 `usize` -> `u32` 截断而返回错误长度。
- ABI 文档、header 和实际实现对 pre-v1 兼容策略、boolean 表示和 fixed-width surface 的描述一致。

完成记录：

- 在 `editor-core-ui-ffi` 中新增 invalid-argument 标记、统一 `u32`/count 到 `usize` 转换 helper、`usize` 到 `u32` 输出 helper，以及 FFI slice 构造前的 count/null/slice-length 检查。
- 将 UI FFI public 边界中的 viewport width、LSP hover/definition 行列、tab width、semantic token data_len、match highlight ranges、selection ranges、marked text、char offset/view mapping、minimap row/count、RGBA render out buffer 和 viewport/selection 输出等路径改为显式转换，不再直接 `as usize` 或静默 `as u32` 截断。
- `render_rgba` 在 required RGBA 长度无法用 `u32` 表示时返回 `ECU_ERR_INVALID_ARGUMENT` 并设置 last error；two-call buffer-too-small 路径继续写入可表示的 required length。
- 扩展 `editor-core-ui-ffi` 单元测试，覆盖 null `out_len`、RGBA required length 超出 `u32`、非零 `range_count` 搭配 null ranges 的 invalid-argument 路径，并更新 null-argument 期望。
- 更新 `editor_core_ffi.h` 和 `docs/abi-v1-draft.md`，明确当前是 pre-v1 fixed-width 收口、header 是当前 C surface 权威定义、legacy C `bool` 策略，以及 UI FFI fixed-width/control-plane 代表性入口和 array count 契约。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ui-ffi`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T16FR Review：审查 FFI ABI 契约与 UI FFI 转换修复

状态：DONE

审查范围：T16F 的所有 diff。

审查重点：

1. `editor-core-ui-ffi` 是否仍存在 public ABI 入参 unchecked `as usize` 截断风险。
2. 输出长度、range count 和 buffer required length 是否有 `u32` 溢出处理。
3. ABI 文档是否与 header/Rust 实现一致，尤其是 pre-v1 breaking 策略和 public boolean 表示。
4. 新增错误路径测试是否真正触发 conversion/output 边界，而不是只覆盖正常路径。
5. 是否避免混入 T19 UTF-16 半代理对策略或其它无关 ABI 改动。

建议命令：

- `cargo test -p editor-core-ui-ffi`
- `cargo test -p editor-core-ffi --test abi_v1`
- `cargo test -p editor-core-ffi`
- `cargo clippy --all-targets -- -D warnings`

完成记录：

- 已审查 T16F diff，重点检查 `editor-core-ui-ffi` 的 public fixed-width 入参到 internal `usize` 的转换 helper、FFI slice 构造前 count/null 检查、RGBA required length 与 selection/range 输出长度的 `u32` 溢出处理，以及 ABI 文档/header 表述。
- 未发现需要立即修复或新增前置任务的问题；`editor-core-ui-ffi/src/lib.rs` 中未发现 public ABI 入参继续使用 unchecked `as usize`，`slice::from_raw_parts(_mut)` 已收敛到统一 helper，`render_rgba` 和 selection/range 输出路径会在无法表示为 `u32` 时返回 invalid-argument 而非截断。
- 已确认 `crates/editor-core-ffi/include/editor_core_ffi.h` 未暴露 `size_t` public 签名，`crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h` 也保持定宽 C surface；ABI 文档已说明 pre-v1 breaking fixed-width 收口、legacy C `bool` 策略和 C headers 权威性。
- 未发现 T16F 混入 T19 UTF-16 半代理对策略或其它无关 ABI 行为变更。
- 已运行并通过：`cargo fmt`、`cargo test -p editor-core-ui-ffi`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo clippy --all-targets -- -D warnings`。

### [DONE] T17 实现：Undo coalescing 粒度修正

状态：DONE

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

完成记录：

- 在 `UndoRedoManager` 的 open coalescing group 中记录 group id、最后编辑时间戳、edit kind、selection/caret 快照和编辑位置摘要；默认 coalescing timeout 为 1s，并通过 `CommandExecutor::set_undo_coalescing_timeout` 提供可控配置。
- 普通 typing/insert coalescing 仅在纯插入、无换行、selection set 连续、每个插入位置与上一次插入后位置相邻且未超时时复用 group；光标/选择命令、undo/redo、非插入、换行、超时和非相邻插入都会结束或开启新的 undo group。
- 为 `ReplaceCoalescingUndo*` 保留显式 composition coalescing 模式，但与普通 typing group 隔离，且只在下一次替换正好覆盖上一次插入的 composition 范围并保持 selection 连续时合并，修复全量测试暴露的 IME undo grouping 回归。
- 新增 `crates/editor-core/tests/undo_coalescing.rs`，覆盖连续快速输入合并、零 timeout 稳定打断、显式 `EndUndoGroup`、非相邻插入、光标移动、换行、显式 IME-like replacement coalescing，以及多光标连续输入 undo 行为。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test undo_coalescing`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test undo_tree`、`cargo test -p editor-core-ui --test ime_undo_grouping_tests`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T17R Review：审查 Undo coalescing 修正

状态：DONE

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

完成记录：

- 已审查 T17 diff，重点检查 `UndoRedoManager` 的 open coalescing state、普通 insert 合并条件、`ReplaceCoalescingUndo` 显式 IME 合并路径、selection/caret 快照连续性、多光标插入、redo branch/clean state 相关路径，以及新增 `undo_coalescing` 覆盖。
- 未发现需要立即修复或新增前置任务的问题；普通 typing coalescing 仅在纯插入、无换行、selection set 连续、每个插入位置相邻且未超时时复用 group，cursor/undo/redo 和非插入 edit 会结束或关闭 open group，IME 显式合并路径与普通 typing group 隔离。
- 时间窗口测试使用 `Duration::ZERO` 打断合并，不依赖真实 sleep；多光标连续插入、显式 `EndUndoGroup`、非相邻插入、换行、光标移动和 IME-like replacement 均有回归覆盖。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test undo_coalescing`、`cargo test -p editor-core --test undo_redo`、`cargo test -p editor-core --test undo_tree`、`cargo test -p editor-core`、`cargo test -p editor-core-ui --test ime_undo_grouping_tests`。

### [DONE] T18 实现：多折叠区域 visual/logical 往返修正

状态：DONE

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

完成记录：

- 修正 `FoldingManager::logical_to_visual` / `visual_to_logical`：collapsed region 现在先转换为隐藏行区间 union，再做坐标映射，避免多个重叠或嵌套 collapsed region 重复累计 hidden lines；`visual_to_logical` 同时避免 `visual_line < base_visual` 的下溢。
- 保持 `EditorCore` 视觉行映射继续以 `VisualRowIndex` 为权威路径；新增 viewport/headless grid 一致性回归，确认 visual row、logical line、soft wrap segment 与渲染行元数据一致。
- 新增 `crates/editor-core/tests/folding_visual_mapping.rs`，覆盖多个非重叠 collapsed region 的 visual->logical->visual 往返、相邻 collapsed region 边界、重叠 collapsed region hidden-line union、soft wrap 下多折叠往返和 viewport 行一致性。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_visual_mapping`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T18R Review：审查多折叠映射修正

状态：DONE

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

完成记录：

- 已审查 T18 diff，重点检查 `FoldingManager::logical_to_visual` / `visual_to_logical` 的 collapsed hidden-range union、start line 可见语义、base visual row 处理，以及新增 `folding_visual_mapping` 中多个非重叠/相邻/重叠 collapsed region 和 soft wrap viewport 往返覆盖。
- 未发现需要立即修复或新增前置任务的问题；`EditorCore` 坐标与 viewport 热路径继续使用 `VisualRowIndex` 作为权威映射，`FoldingManager` legacy 行级映射已避免多个重叠/嵌套 collapsed region 重复累计 hidden lines。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_visual_mapping`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core`。

### [DONE] T19 实现：LSP UTF-16 代理对边界修正

状态：DONE

范围文件：

- `crates/editor-core-lsp/src/lsp_sync.rs`
- `crates/editor-core-lsp/src/editor.rs`
- `crates/editor-core-lsp/tests/diagnostics_processing_edits.rs`
- 可新增 `crates/editor-core-lsp/tests/utf16_boundaries.rs`

执行备注：定向检查发现 `crates/editor-core-lsp/src/lsp_events.rs`、`crates/editor-core-lsp/src/lsp_text_edits.rs`、`crates/editor-core-lsp/src/lsp_completion.rs`、`crates/editor-core-lsp/src/lsp_hover.rs`、`crates/editor-core-lsp/src/lsp_locations.rs`、`crates/editor-core-lsp/src/lsp_symbols.rs`、`crates/editor-core-lsp/src/lsp_highlights.rs`、`crates/editor-core-lsp/src/lsp_decorations.rs`、`crates/editor-core-lsp/src/lsp_call_hierarchy.rs` 和 `crates/editor-core-lsp/src/lsp_type_hierarchy.rs` 也存在重复的 LSP position 解析或 UTF-16 坐标入口；为保证 T19 的代理对边界策略在所有 LSP 坐标转换入口一致，需要纳入这些最小调用点修改。

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

完成记录：

- 在 `LspCoordinateConverter::utf16_to_char_offset` 中固定半代理对策略：UTF-16 offset 落在 surrogate pair 中间时按畸形 LSP 输入处理并 clamp 到该 Unicode scalar 的起点；超过行尾的 character clamp 到行尾。
- 新增统一的 LSP position/range 饱和解析和 `lsp_position_to_char_offset` 入口，将 diagnostics、semantic tokens、text edits、completion、hover/location、symbols/highlights/decorations、call/type hierarchy 等 LSP 坐标入口改为共享同一 u32/u64 边界策略，避免 raw JSON 超大 line/character 静默截断。
- 将 diagnostics 和 semantic token 区间转换改为使用同一 `lsp_to_char_offset` 策略；半个代理对 range 不再扩展到 surrogate pair 后侧，`u32::MAX` character 会稳定 clamp 到当前行尾。
- 新增 `crates/editor-core-lsp/tests/utf16_boundaries.rs`，覆盖 `a👋b` 的 UTF-16 offset 0/1/2/3/4、半代理对 diagnostics range、超大 character/line clamp，以及 semantic tokens 与 diagnostics 的边界策略一致性。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test utf16_boundaries`、`cargo test -p editor-core-lsp --test diagnostics_processing_edits`、`cargo test -p editor-core-lsp`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，完整 fixture suite 无可运行入口。

### [DONE] T19R Review：审查 LSP UTF-16 边界修正

状态：DONE

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

完成记录：

- 已审查 T19 diff，重点检查 `LspCoordinateConverter::utf16_to_char_offset` 半代理对策略、`LspPosition::from_value` / `LspRange::from_value` 饱和解析、diagnostics / semantic tokens 区间转换，以及各 LSP 坐标解析入口改用统一策略的情况。
- 未发现 diagnostics 和 semantic tokens 半代理对策略不一致的问题；`a👋b` 中 UTF-16 offset 0/1/2/3/4、半代理对 diagnostics range、超大 character clamp 和 semantic token 边界均有 `utf16_boundaries` 覆盖。
- 发现 T19 后续修复项：server-provided workspace edit 的原始 LSP range 会同步到 `DeltaCalculator::apply_change`，超大 line 仍可能导致内部行数组巨量扩容；`lsp_signature_help.rs` 仍有 LSP UTF-16 offset/index 的 unchecked `as u32` / `as usize` 转换风险。
- 已在 T20 前新增 `T19F` / `T19FR`，要求先收口上述 LSP 边界解析和 calculator 同步问题。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test utf16_boundaries`、`cargo test -p editor-core-lsp --test diagnostics_processing_edits`、`cargo test -p editor-core-lsp`。

### [DONE] T19F 修复：收口 LSP workspace edit 与 signatureHelp 边界解析

状态：DONE

依赖：

- T19R 审查发现的 workspace edit calculator 同步边界风险和 `signatureHelp` LSP offset/index unchecked 转换风险。

范围文件：

- `crates/editor-core-lsp/src/lsp_sync.rs`
- `crates/editor-core-lsp/src/workspace_sync.rs`
- `crates/editor-core-lsp/src/lsp_signature_help.rs`
- `crates/editor-core-lsp/tests/utf16_boundaries.rs`，或按现有布局补充 `workspace_sync` / `signature_help` 单元测试

已知入口：

- `DeltaCalculator::apply_change`
- `workspace_sync::apply_workspace_edit`
- `workspace_sync::lsp_changes_for_text_edits`
- `LspTextEdit::from_value`
- `lsp_signature_help::parameter_label_from_value`
- `lsp_signature_help::signature_help_from_value`
- `LspSignatureHelp::to_compact_string`

实现要求：

1. `DeltaCalculator::apply_change` 不得按 untrusted LSP line 直接 `resize(start_line + 1)` / `resize(end_line + 1)`；对越界 line 必须明确 clamp 到当前 calculator 文档末尾，或改为 fallible API 并让调用方丢弃/拒绝非法 change。
2. `workspace_sync` 在把 server-provided `WorkspaceEdit` 同步回 incremental calculator 时，不得继续使用未归一化的原始 LSP range 触发 calculator 扩容；应复用已 clamp 到当前 `LineIndex` 的坐标，或先将已应用的 char range 转回合法 LSP range。
3. 保持 workspace edit 的实际文本应用语义不变：超大 line/character 只能按当前统一策略 clamp，不得引入 fixture-only 特例或跳过合法 edit。
4. `lsp_signature_help.rs` 中 UTF-16 offset 和 active index 解析不得用 unchecked `as u32` / `as usize`；超大值应饱和、丢弃或通过 checked lookup 安全处理，并在测试中固定策略。
5. 不改变 T19 已固定的半代理对策略：UTF-16 offset 落在 surrogate pair 中间时 clamp 到该 Unicode scalar 起点。

测试要求：

1. 覆盖 server-provided workspace edit 含超大 line/character 时，不 panic、不巨量扩容，workspace 文本与 incremental calculator 同步结果保持一致。
2. 覆盖合法 workspace edit 仍生成与原行为一致的 didChange range/text。
3. 覆盖 `signatureHelp` 的超大 parameter label offset、`activeSignature`、`activeParameter` 解析不会 wrap，并且 `to_compact_string` 不会因超大 index 访问错误签名。
4. 运行 `cargo test -p editor-core-lsp --test utf16_boundaries`，若将回归放入该测试文件。
5. 运行 `cargo test -p editor-core-lsp`。
6. 运行 `cargo clippy --all-targets -- -D warnings`。

验收标准：

- LSP 边界值不能通过 workspace edit calculator 同步路径造成 OOM、panic 或状态错位。
- `signatureHelp` 的 LSP offset/index 边界解析没有 unchecked truncation 风险。
- T19 diagnostics / semantic tokens 半代理对策略保持不变。

完成记录：

- 将 `DeltaCalculator::apply_change` 的 LSP range 应用改为先保证至少一行，再将 untrusted start/end line clamp 到当前 calculator 文档末尾，并对反向 range 做 normalize，避免按 server-provided line 直接扩容或 panic。
- 将 `workspace_sync::lsp_changes_for_text_edits` 改为基于 `char_offsets_for_lsp_range` 已 clamp/normalized 的 char range 重新生成合法 `LspRange`，workspace edit 实际应用和 calculator 同步使用同一边界语义，合法 edit 的 didChange range/text 保持不变。
- 将 `lsp_signature_help.rs` 中 parameter label offset、`activeSignature`、`activeParameter` 的解析改为 `u64` 到 `u32` 饱和转换；`to_compact_string` 使用 checked index lookup，超大 active index 不再 wrap 到错误签名。
- 扩展 `utf16_boundaries.rs`，覆盖超大 workspace edit range 不 panic/不巨量扩容且 workspace 文本与 calculator 同步一致、合法 workspace edit 继续产生原 didChange range/text、signatureHelp 超大 offset/index 不 wrap。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test utf16_boundaries`、`cargo test -p editor-core-lsp`。

### [DONE] T19FR Review：审查 LSP workspace edit 与 signatureHelp 边界修复

状态：DONE

审查范围：T19F 的所有 diff。

审查重点：

1. `DeltaCalculator::apply_change` 是否不再按 untrusted line 巨量扩容，且越界策略清晰。
2. `workspace_sync` 是否使用已 clamp/合法化的坐标同步 calculator，实际 workspace edit 应用语义是否保持。
3. `signatureHelp` 的 UTF-16 offset/index 是否不再 unchecked 截断或错误索引。
4. 是否保持 T19 半代理对策略，未引入新的 workaround 或 fixture-only 特例。
5. 回归测试是否覆盖超大 workspace edit range、合法 workspace edit、signatureHelp 超大值三类边界。

建议命令：

- `cargo test -p editor-core-lsp --test utf16_boundaries`，若 T19F 修改该测试文件
- `cargo test -p editor-core-lsp`
- `cargo clippy --all-targets -- -D warnings`

完成记录：

- 已审查 T19F diff，重点检查 `DeltaCalculator::apply_change`、`workspace_sync::lsp_changes_for_text_edits`、`lsp_signature_help` 的饱和解析/checked lookup，以及 `utf16_boundaries` 新增回归覆盖。
- 未发现 workspace edit 同步继续使用原始超大 LSP range 触发 calculator 巨量扩容的问题；`workspace_sync` 会先通过 `char_offsets_for_lsp_range` clamp/normalize 到当前 `LineIndex`，再用合法 char offsets 重新生成 didChange range，合法 workspace edit 的 range/text 回归已有覆盖。
- 未发现 `signatureHelp` 中 active index 或 parameter label offset 继续 unchecked 截断的问题；超大值饱和到 `u32::MAX`，`to_compact_string` 使用 checked lookup，不会 wrap 到错误签名。
- 发现 T19F 后续修复项：`DeltaCalculator::apply_change` 直接处理 untrusted `TextChange` 时只把越界 line clamp 到最后一行，再按原 character 转换；当越界 line 搭配 `character = 0` 时会落到最后一行开头，而不是任务要求的文档末尾，且当前测试只覆盖了超大 line + 超大 character。
- 已在 T20 前新增 `T19FF` / `T19FFR`，要求先修复该 calculator 越界 line clamp 语义并补测试。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test utf16_boundaries`、`cargo test -p editor-core-lsp`。

### [DONE] T19FF 修复：统一 DeltaCalculator 越界 line clamp 语义

状态：DONE

依赖：

- T19FR 审查发现的 `DeltaCalculator::apply_change` 越界 line clamp 语义缺口。

范围文件：

- `crates/editor-core-lsp/src/lsp_sync.rs`
- `crates/editor-core-lsp/tests/utf16_boundaries.rs`，或 `lsp_sync.rs` 单元测试，按最小覆盖选择

已知入口：

- `DeltaCalculator::apply_change`
- `LspCoordinateConverter::lsp_position_to_char_offset`
- `TextChange`

实现要求：

1. `DeltaCalculator::apply_change` 处理 untrusted `TextChange` 时，越界 line 必须按当前统一 LSP 坐标策略 clamp 到当前 calculator 文档末尾，而不是最后一行的任意 character。
2. 超大 line 搭配 `character = 0`、超大 line 搭配超大 character、反向 range 都必须稳定 normalize，不得 panic、巨量扩容或修改错误位置。
3. 保持 T19 已固定的 UTF-16 半代理对策略：落在 surrogate pair 中间的 character clamp 到该 Unicode scalar 起点。
4. 保持 workspace edit 实际应用语义与 calculator 同步语义一致，不引入 fixture-only 特例。

测试要求：

1. 覆盖 `DeltaCalculator::apply_change` 直接接收越界 line + `character = 0` 的 insert/replace，结果应发生在文档末尾。
2. 覆盖越界 line + 超大 character 与反向 range normalize 仍保持文档末尾 clamp 语义。
3. 覆盖半代理对 range 策略不回退。
4. 运行 `cargo test -p editor-core-lsp --test utf16_boundaries`，若回归放入该测试文件。
5. 运行 `cargo test -p editor-core-lsp`。
6. 运行 `cargo clippy --all-targets -- -D warnings`。

验收标准：

- `DeltaCalculator::apply_change` 与 `LineIndex`/workspace edit 的 LSP position clamp 策略一致。
- 任意越界 LSP line 不会落到最后一行开头或中间位置。

完成记录：

- 将 `DeltaCalculator::apply_change` 的 LSP position 解析改为先判断 line 是否超出当前 calculator 文档；任意越界 line 都直接映射到文档末尾，再参与反向 range normalize，避免 `character = 0` 落到最后一行开头。
- 保持合法 line 的 UTF-16 character 解析走 `LspCoordinateConverter::lsp_to_char_offset`，继续保留半代理对中点 clamp 到 Unicode scalar 起点、超大 character clamp 到行尾的策略。
- 在 `utf16_boundaries.rs` 增加直接覆盖 `DeltaCalculator` 的回归：越界 line + `character = 0`、越界 line + 超大 character、越界 line 参与反向 range normalize、半代理对 range 替换。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test utf16_boundaries`、`cargo test -p editor-core-lsp`、`cargo test --all --all-targets`。
- 未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`，无可运行的完整 fixture runner。

### T19FFR Review：审查 DeltaCalculator 越界 line clamp 修复

状态：TODO

审查范围：T19FF 的所有 diff。

审查重点：

1. 越界 line 是否无条件 clamp 到 calculator 文档末尾，而不是最后一行加原 character。
2. 正常合法 range、超大 character、反向 range 和半代理对策略是否未退化。
3. workspace edit 的实际文本应用与 calculator didChange 同步是否仍一致。
4. 测试是否覆盖越界 line + `character = 0` 这个 T19FR 发现的缺口。
5. 是否避免引入 workaround 或 fixture-only 特例。

建议命令：

- `cargo test -p editor-core-lsp --test utf16_boundaries`
- `cargo test -p editor-core-lsp`
- `cargo clippy --all-targets -- -D warnings`

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
