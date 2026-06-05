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
