# Execution Plan

说明：本文件记录可公开、可审计的任务理解、执行步骤和进度；不记录不可公开的内部推理链。

## Current Task

- 首个未完成任务：`T03R Review：审查 DiffModel`。
- 任务性质：专项代码审查任务，不主动重构；只有发现明确 bug、测试缺口或质量问题时才修复或新增后续修复任务。
- 审查范围：T03 的所有 diff，重点是 `crates/editor-core-diff-view/src/model.rs`、T03 相关测试，以及必要的公开 re-export/smoke 测试改动。

## Step-by-Step Plan

1. 查看最新提交，确认是否有与 T03R 直接相关的未完成事项。
2. 检查工作区状态，避免覆盖用户或其他 agent 的无关改动。
3. 读取 T03 涉及的源码与测试，重点核对：model 是否 width/mode 无关、是否无 wrap/spacer 泄漏、缓存是否完整、`side_line_kind` 是否覆盖所有 `AlignUnit` 变体和边界、`SideDoc` 接口是否适合后续 projection 使用、公开接口是否不过度暴露。
4. 如果发现明确问题：做最小修复并补充针对性测试；如果发现当前任务被具体 blocker 阻塞：把最小 prerequisite 写入 `TODO.md` 后停止。
5. 运行 T03R 建议验证：`cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core-diff-view --test model`、`cargo test -p editor-core-diff-view`。若有代码改动或发现未调度失败，再按政策处理。
6. 若审查无问题或问题已修复，更新 `TODO.md`：将 T03R 标题改为 `[DONE]` 并填写完成记录和验证结果。
7. 提交本次 T03R 相关变更，提交信息使用 `[T03R] Review diff model`。
8. 完成一个任务后停止，不进入 T04。

## Progress Log

- 已读取 `TODO.md` 并确认首个未完成任务为 `T03R Review：审查 DiffModel`。
- 已记录当前可公开执行计划；下一步开始查看最新提交、工作区状态和 T03 相关文件。
- 最新提交为 `d00b6d4 [T03] Implement diff-view model`，提交信息未提到未完成事项；与当前 T03R 审查直接相关。
- 工作区当前仅有本计划文件修改，另有既存未跟踪 `notification.sh`、`run_agent.sh`；它们与 T03R 无关，将保持不动。
- 已审查 T03 相关文件：`src/model.rs`、`tests/model.rs`、`tests/smoke.rs` 及公开 re-export；未发现需要修复的明确问题。
- 审查结论：`DiffModel`/`SideDoc` 保持 width/mode 无关，没有 spacer/wrap 泄漏；缓存包含各侧逻辑行、alignment 与每行 change kind；`side_line_kind` 覆盖 T03 生成的所有 `AlignUnit` 变体；公开接口未暴露可变内部状态。
- 下一步进入验证：先 `cargo fmt`，再 clippy，最后运行 T03R 指定测试。
- 验证通过：`cargo fmt`；`cargo clippy --all-targets --all-features -- -D warnings`；`cargo test -p editor-core-diff-view --test model`；`cargo test -p editor-core-diff-view`。
- 当前任务没有代码修复；全量测试沿用 T03 完成记录中的 `cargo test --all --all-targets` 绿色结果，按文档/记录变更规则不重复运行。
- 下一步更新 `TODO.md`，将 T03R 标题标记为 `[DONE]` 并写入完成记录。
- 已更新 `TODO.md`：`T03R Review：审查 DiffModel` 标题已标记 `[DONE]`，状态改为 DONE，并记录审查结论与验证命令。
- 下一步检查 diff/status，然后提交 T03R 相关变更。
- 已检查待提交 diff，只有 `TODO.md` 与 `memory/claude_plan.md` 属于本任务；未跟踪 `notification.sh`、`run_agent.sh` 继续保持不动。
- 提交步骤开始：仅暂存并提交 T03R 相关文档/记录变更。
