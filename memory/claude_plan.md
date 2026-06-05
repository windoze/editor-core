# 执行计划：T02 diagnostics 版本守卫

## 当前任务

- `TODO.md` 中首个未完成任务是 `T02 实现：diagnostics 版本守卫`。
- 本次只完成 T02，完成后停止，不进入 `T02R`。

## 执行边界

- 优先读取任务列出的范围文件，不做全仓开放式历史问题扫描。
- 只在当前任务需要时修改额外文件，并在任务记录中说明原因。
- diagnostics 的旧版本通知不能产生派生状态改动；无版本通知保持兼容应用；普通 notification event 仍需可观察。
- 不改变 semantic tokens 和 folding ranges 既有版本守卫行为。

## 步骤计划

1. 查看最新提交信息，确认是否有与 T02 直接相关的未完成事项。
2. 读取 `crates/editor-core-lsp/src/editor.rs`、`crates/editor-core-lsp/src/lsp_sync.rs` 和现有 diagnostics 测试，定位 `publishDiagnostics` 到 `ProcessingEdit` 的路径。
3. 在 diagnostics 处理路径中读取 params 的 `version`，仅当版本缺失或等于当前 `self.document.version` 时生成 `ReplaceStyleLayer` / `ReplaceDiagnostics`。
4. 保持旧版本 diagnostics 的 notification event 进入正常事件流，避免宿主丢失可观测消息。
5. 补充或更新测试，覆盖旧版本、当前版本、无版本三种情况。
6. 按要求运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test diagnostics_processing_edits`，如新增测试文件则运行对应测试，再运行相关 crate 测试；根据结果修复问题。
7. 更新 `TODO.md`：为 T02 标记 `[DONE]` 并填写完成记录。
8. 复查 diff 和 git 状态，提交本次任务的全部相关改动，然后停止。

## 进度记录

- 已识别首个未完成任务：T02。
- 最新提交为 `adc6305 [T01R] Review LSP process lifecycle`，未显示与 T02 直接相关的未完成事项。
- 已定位 diagnostics active-document 转换路径；另发现 `workspace_sync.rs` 对非 active document diagnostics 会再次生成 processing edits，因此将它作为同一版本守卫缺口纳入 T02 的最小修复范围。
- 已在 `LspSession` 增加 diagnostics 版本匹配判断，并接入 active document 和 workspace non-active document 两条 processing-edit 生成路径。
- 已在 `diagnostics_processing_edits.rs` 增加 session 级回归测试，覆盖旧版本仍可观察但不应用、当前版本应用、无版本兼容应用三种情况。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-lsp --test diagnostics_processing_edits`、`cargo test -p editor-core-lsp`。
- 已运行并通过：`cargo test --all --all-targets`。未找到 `tools/run_fixtures.py`，无可运行的完整 fixture runner。
- 已将 `TODO.md` 中 T02 标记为 `[DONE]` 并填写完成记录；下一步复查 diff、状态和提交。
- 已复查当前 diff、状态和最近提交；未跟踪的 `notification.sh`、`run_agent.sh` 不属于本任务范围，提交时不暂存。
