# 执行计划

## 当前状态

- 本文件先记录可公开的执行计划摘要；不包含私有推理链。
- 已读取 `TODO.md`，首个未完成任务是 `T01R Review：审查 LSP 子进程生命周期回收`。
- 当前任务是审查任务，不主动重构；仅在发现明确 bug、测试缺口或质量问题时修复或新增后续任务。

## 步骤

1. 检查 git 工作区状态和最近提交，确认 T01 的实际 diff 以及是否存在直接相关未完成项。
2. 阅读 `crates/editor-core-lsp/src/lsp_client.rs`、`crates/editor-core-lsp/src/editor.rs` 和 `crates/editor-core-lsp/tests/lsp_process_lifecycle.rs`。
3. 按 T01R 审查重点检查：所有退出路径是否 wait、Drop 是否可能 panic/长阻塞、shutdown 超时和同步初始化兼容性、reader/writer channel 关闭是否死锁、测试是否验证真实进程退出。
4. 若发现明确缺陷，做最小修复并补充测试；若发现必须单独排期的问题，更新 `TODO.md` 后停止。
5. 运行建议命令：`cargo test -p editor-core-lsp --test lsp_process_lifecycle` 和 `cargo test -p editor-core-lsp`。
6. 若审查通过，更新 `TODO.md`，将 `T01R` 标题标为 `[DONE]` 并填写审查完成记录。
7. 提交本次任务相关改动，然后停止，不进入 `T02`。

## 进度记录

- 已创建初始执行计划。
- 已识别当前任务：`T01R Review：审查 LSP 子进程生命周期回收`。
- 已检查最近提交：T01 实现提交为 `35c0991 [T01] Reap LSP server processes`，之后 `16542f6` 仅更新执行记录。
- 已确认当前工作区存在两个未跟踪脚本 `notification.sh`、`run_agent.sh`，不属于本任务范围，暂不触碰。
- 正在审查 T01 涉及的 LSP 生命周期代码、测试和伴随 clippy/测试修复 diff。
- 已完成代码审查，未发现需要立即修复或新增前置任务的 T01 生命周期问题。
- 准备运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_process_lifecycle`、`cargo test -p editor-core-lsp`。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_process_lifecycle`、`cargo test -p editor-core-lsp`。
- 准备更新 `TODO.md`，将 `T01R` 标记为 `[DONE]` 并记录审查结论。
- 已更新 `TODO.md`，`T01R` 已标记为 `[DONE]` 并填写完成记录。
- 准备检查 diff/status 后提交本次审查任务改动。
