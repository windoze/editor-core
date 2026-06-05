# 执行计划

## 公开推理摘要

- `TODO.md` 是任务顺序与完成状态的唯一权威来源；本次只处理第一个标题未带 `[DONE]` 的任务。
- 在读取 `TODO.md` 之前，不做开放式缺陷排查，也不假设当前任务内容。
- 如遇到阻塞当前任务的未跟踪问题，先把最小必要前置任务写入 `TODO.md` 并停止；不使用变通方案。
- 完成任务后需要更新 `TODO.md` 的 `[DONE]` 标记与完成记录，按要求运行验证，并提交 Git commit。

## 步骤计划

1. 读取 `TODO.md`，确定第一个未完成任务及其验证要求。
2. 检查最近提交信息是否明确提到与该任务直接相关的未完成问题。
3. 按任务要求阅读最小必要上下文，定位实现与测试位置。
4. 如任务可直接完成，实施最小正确修改并补充或更新回归测试。
5. 先运行 `cargo fmt`，再运行 `cargo clippy --all-targets -- -D warnings`，最后按任务要求运行相关测试；如代码变更需要完整验证，则运行完整测试套件并设置足够超时。
6. 若发现未安排的失败测试或夹具问题，修复它；若它是当前任务的真实前置阻塞，则在 `TODO.md` 中添加最小前置任务并停止。
7. 成功后更新 `TODO.md`，将当前任务标题加 `[DONE]` 并补全完成记录；仅在阶段计划变化时更新 `PLAN.md`。
8. 检查 `git status`、`git diff` 和最近提交，提交本次所有相关变更。
9. 停止，不继续处理下一个任务。

## 进度记录

- 已创建本执行计划文件，下一步读取 `TODO.md` 识别当前任务。
- 已读取 `TODO.md`，第一个未完成任务是 `T03 实现：wait_for_response 保留其它在途响应`。
- T03 范围文件为 `crates/editor-core-lsp/src/lsp_client.rs`、`crates/editor-core-lsp/src/editor.rs`，可新增 `crates/editor-core-lsp/tests/lsp_wait_for_response.rs`。
- 下一步检查最新提交是否有与 T03 直接相关的未完成事项，然后读取 T03 范围内代码与现有测试。
- 最新提交为 `[T02R] Review diagnostics version guard`，未提到与 T03 直接相关的未完成事项。
- 已检查 T03 入口：`LspClient::wait_for_response` 当前会丢弃非目标 response、notification，以及带非 u64 id 的 malformed 消息；`LspSession::poll_*` 只从 `try_recv` 拉取消息。
- 修正计划：在 `LspClient` 中新增 FIFO `deferred_inbound`，`try_recv` 优先返回该缓存；`wait_for_response` 等待目标 response 时缓存所有未消费 inbound，只有成功自动响应的 server request 才不重新投递。
- 已修改 `lsp_client.rs`：新增 deferred inbound FIFO，更新 `try_recv` 和 `wait_for_response` 保留逻辑，并避免 malformed id 在等待期间被吞掉。
- 已修改 `editor.rs` 的 `wait_for_response` 文档说明，使其描述其它 response/notification 会继续排队。
- 已新增 `lsp_wait_for_response.rs`，覆盖乱序 response、等待期间 server request 自动响应、notification 保留、malformed id 保留。
- 下一步运行 `cargo fmt`、clippy 和相关/完整测试。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_wait_for_response`、`cargo test -p editor-core-lsp`。
- 下一步运行完整 Rust 测试套件，并检查是否存在 fixture runner。
- 已运行并通过：`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。
- 已确认不存在 `tools/run_fixtures.py`，无 fixture runner 可执行。
- 已更新 `TODO.md`：T03 标记为 `[DONE]`，状态改为 DONE，并补全完成记录。
- 提交前复查发现 `LspSession::poll_edits_with_line_index_and_handlers` 对 malformed server request 仍会调用 no-op 自动处理后 `continue`，导致缓存后的 malformed id 不能到达 `on_unhandled_message`。
- 已补充修正：poll 路径仅处理可解析为 `LspServerRequest` 的 request；解析失败的 method+id 消息会进入 `on_unhandled_message`。
- 已扩展 `lsp_wait_for_response.rs`，覆盖 malformed server request 经 `wait_for_response` 缓存后仍可被 session poll 上报。
- 重新验证已通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_wait_for_response`、`cargo test -p editor-core-lsp`、`cargo test --all --all-targets`。
- 已更新 `TODO.md` 完成记录，补充 malformed server request 经 session poll 可观察的覆盖。
- 下一步检查最终 diff/status 并提交本次 T03 变更；未跟踪的 `notification.sh`、`run_agent.sh` 不属于本任务，不会纳入提交。

## T03R 进度记录

- 已读取 `TODO.md`，第一个未完成任务是 `T03R Review：审查 wait_for_response 响应缓存`。
- 最新提交为 `[T03] Preserve wait_for_response inbound messages`，与 T03R 审查范围直接相关。
- 已审查 T03 diff 和当前实现，覆盖 `LspClient::wait_for_response`、`LspClient::try_recv`、`LspSession::poll_edits_with_line_index_and_handlers`、server request 自动响应、malformed id 可观察性，以及 `lsp_wait_for_response` 测试。
- 未发现需要立即修复或新增前置任务的问题；缓存按 FIFO 恢复，已处理的 server request 不重复投递，非目标 response/notification/malformed id 保留给后续 poll。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_wait_for_response`、`cargo test -p editor-core-lsp`。
- 已更新 `TODO.md`：T03R 标记为 `[DONE]`，状态改为 DONE，并补全审查完成记录。
- 下一步检查最终 diff/status 并提交本次 T03R 审查记录；未跟踪的 `notification.sh`、`run_agent.sh` 不属于本任务，不会纳入提交。

## T04 进度记录

- 已读取 `TODO.md`，第一个未完成任务是 `T04 实现：折叠派生状态版本化与折叠态保留`。
- T04 范围文件为 `crates/editor-core/src/intervals.rs`、`crates/editor-core/src/processing.rs`、`crates/editor-core/src/state.rs`、`crates/editor-core/src/workspace.rs`、`crates/editor-core-lsp/src/editor.rs`、`crates/editor-core/tests/folding_stability.rs`，可新增 `crates/editor-core-lsp/tests/folding_versioning.rs`。
- 本次执行计划：先检查最新提交是否包含与 T04 直接相关的未完成事项；再只阅读 T04 列出的入口和测试；随后实现 LSP folding 旧版本丢弃、折叠区域刷新时的 collapsed 保留策略，并确认用户 fold 与派生 fold 的折叠态边界；补充针对旧版本 response、行号漂移保留 collapsed、派生刷新不删除用户 fold 的测试；最后按要求运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core-lsp`，必要时运行完整测试；验证通过后更新 `TODO.md` 并提交。
- 最新提交为 `[T03R] Review wait_for_response caching`，未提到与 T04 直接相关的未完成事项。
- 当前工作树已有未跟踪的 `notification.sh`、`run_agent.sh`，不属于 T04；除非后续明确相关，否则不修改、不纳入提交。
- 已阅读 T04 范围内入口：`FoldingManager`、`ProcessingEdit::ReplaceFoldingRegions`、`EditorStateManager::replace_folding_regions`、`Workspace::apply_processing_edits` folding 分支、`LspSession::handle_pending_response` folding 分支，以及现有 `folding_stability.rs`。
- 发现 LSP folding response 已按 `PendingLspRequest::FoldingRanges { version }` 在进入 core 前丢弃旧版本，但缺少专项回归测试；`preserve_collapsed` 仍只按精确 `(start_line, end_line)` 匹配，无法覆盖小范围行号漂移。
- 修正计划更新为：在 `FoldingManager` 增加共享的派生 fold 替换并保留 collapsed 策略，优先精确匹配，其次使用保守的同 placeholder、start 附近、范围重叠且长度接近的匹配；`state` 和 `workspace` 改用该共享方法；新增 core 测试覆盖漂移保留和用户 fold 不被派生刷新删除；新增 LSP 测试覆盖旧版本 folding response 不生成替换 edit。
- 已实现共享保留策略：新增 `FoldingManager::replace_derived_regions_preserving_collapsed`，`EditorStateManager` 和 `Workspace` 的 `ReplaceFoldingRegions { preserve_collapsed: true }` 都改用该路径；`ProcessingEdit` 文档补充异步版本来源要求，LSP folding 分支保留进入 core 前的版本丢弃。
- 已更新 `folding_stability.rs`，新增小范围行号漂移后保留 collapsed、用户 fold collapsed 不复制到派生 fold、多个派生 collapsed fold 在插入/删除后继续平移的覆盖。
- 已新增 `folding_versioning.rs`，使用 fake LSP server 覆盖当前版本 folding response 产生 `ReplaceFoldingRegions`，以及编辑后旧版本 response 不产生替换 edit 且不会覆盖已平移的多个 collapsed region。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core-lsp --test folding_versioning`、`cargo test -p editor-core`、`cargo test -p editor-core-lsp`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`。
- 已确认不存在 `tools/run_fixtures.py`，无可运行的完整 fixture runner。
- 已更新 `TODO.md`：T04 标记为 `[DONE]`，状态改为 DONE，并补全完成记录。下一步复查 diff/status 并提交本次 T04 变更。

## T04R 进度记录

- 已读取 `TODO.md`，第一个未完成任务是 `T04R Review：审查折叠版本化与折叠态保留`。
- 最新提交为 `[T04] Preserve versioned folding state`，与 T04R 审查范围直接相关；当前工作树已有未跟踪的 `notification.sh`、`run_agent.sh`，不属于本任务，不会纳入提交。
- 已审查 T04 diff，覆盖 LSP folding response 版本守卫、`ProcessingEdit::ReplaceFoldingRegions` 文档和 match 点、`FoldingManager` 的 collapsed 保留策略、`EditorStateManager` / `Workspace` 应用路径，以及新增 folding 测试。
- 审查发现 T04 需要后续修复任务：`collapsed_fuzzy_match_score` 对默认 placeholder 的相邻或仅共享边界 derived fold 匹配过宽，可能把无关 region 错误继承为 collapsed；新增测试也没有实际先构建 visual-row cache 再验证 fold 替换/清理后的 cache 重建。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core-lsp`。
- 已更新 `TODO.md`：T04R 标记为 `[DONE]`，状态改为 DONE，并在 T05 前新增 `T04F` 修复任务和 `T04FR` review 任务；本次不继续执行 T04F。
- 下一步检查最终 diff/status 并提交本次 T04R 审查记录。

## T04F 进度记录

- 已读取 `TODO.md`，第一个未完成任务是 `T04F 修复：收紧折叠态保留匹配并补 visual-row cache 回归`。
- 最新提交为 `[T04R] Review folding state preservation`，与 T04F 直接相关；当前工作树已有未跟踪的 `notification.sh`、`run_agent.sh`，不属于本任务，不会纳入提交。
- 已检查 T04F 范围入口：`FoldingManager::collapsed_fuzzy_match_score` / `replace_derived_regions_preserving_collapsed`、`EditorStateManager` 和 `Workspace` 的 folding processing edit 应用路径、`EditorCore::visual_line_count` 的 visual-row cache 构建路径，以及 `folding_stability.rs`。
- 已实现更保守的 derived fold collapsed 保留策略：fuzzy 匹配仍要求相同 placeholder、起始行最多漂移 1 行、长度接近，并新增至少共享两行的要求，从而拒绝仅共享边界的默认 placeholder 匹配。
- 已更新 `folding_stability.rs`，新增默认 placeholder 边界/相邻负向回归、保留既有小范围漂移正向覆盖，并新增 `EditorStateManager` 与 `Workspace::apply_processing_edits` 在先构建 visual-row cache 后执行 `ReplaceFoldingRegions` / `ClearFoldingRegions` 的 cache 重建回归。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core`、`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。
- 已确认不存在 `tools/run_fixtures.py`，无可运行的完整 fixture runner。
- 已更新 `TODO.md`：T04F 标记为 `[DONE]`，状态改为 DONE，并补全完成记录。
- 下一步复查最终 diff/status 并提交本次 T04F 变更。

## T04FR 执行计划与进度记录

- 已读取 `TODO.md`，第一个未完成任务是 `T04FR Review：审查折叠态保留匹配修复`。
- 本次只执行 T04FR，不继续处理 T05。
- 计划步骤：检查最新提交是否直接对应 T04F；复查 T04F diff 与当前实现，重点覆盖 `FoldingManager::collapsed_fuzzy_match_score`、collapsed 保留边界、用户 fold 与派生 fold 隔离、visual-row cache 回归测试是否先构建旧 cache；如发现明确问题，优先最小修复或在 `TODO.md` 中添加必要前置任务；随后运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core`；验证通过后将 T04FR 标记为 `[DONE]` 并补全完成记录；最后检查 `git status` / `git diff` / 最近提交并提交本次 review 结果。
- 最新提交为 `[T04F] Tighten folding state preservation`，与 T04FR 审查范围直接相关；当前工作树已有未跟踪的 `notification.sh`、`run_agent.sh`，不属于本任务，不会纳入提交。
- 已审查 T04F diff 与当前实现，覆盖 fuzzy 匹配收紧、默认 placeholder 边界/相邻负向测试、漂移正向测试、用户 fold 与派生 fold 隔离，以及 state/workspace visual-row cache 回归测试。
- 未发现需要立即修复或新增前置任务的问题。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test folding_stability`、`cargo test -p editor-core`。
- 已更新 `TODO.md`：T04FR 标记为 `[DONE]`，状态改为 DONE，并补全审查完成记录。
- 下一步检查最终 diff/status 并提交本次 T04FR 审查记录。
