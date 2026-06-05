# 当前执行计划

## 范围
- 以 `TODO.md` 作为任务顺序和完成状态的唯一来源。
- 本次只处理第一个标题未标记 `[DONE]` 的任务，然后停止。
- 不做开放式历史问题清扫；仅处理与当前任务直接相关的问题。
- Review 任务只做审查和必要记录；若发现明确缺陷，按 `TODO.md` 规则添加最小后续修复任务。

## 步骤
1. 读取 `TODO.md`，定位第一个未完成任务。
2. 检查最新提交是否与该任务直接相关。
3. 审查当前任务指定范围内的 diff、源码、header 和文档。
4. 运行任务指定验证命令。
5. 若发现未排期失败或阻塞问题，修复或在 `TODO.md` 中添加最小前置任务。
6. 若审查通过，在 `TODO.md` 中将任务标题标记为 `[DONE]` 并补充完成记录。
7. 更新本文件记录关键进度。
8. 检查 git status、diff 和最近提交，确认只提交本次相关文件。
9. 创建清晰的任务提交，然后停止。

## 进度
- 已读取 `TODO.md`，第一个未完成任务是 `T16FR Review：审查 FFI ABI 契约与 UI FFI 转换修复`。
- 已检查最新提交：`[T16F] Tighten FFI ABI conversion checks`，与当前 review 任务直接相关。
- 已审查 T16F diff，重点检查 `editor-core-ui-ffi` fixed-width 入参转换、FFI slice count/null 检查、RGBA 和 selection/range 输出长度溢出处理、ABI 文档/header 一致性，以及是否混入 T19 UTF-16 策略改动。
- 已额外确认 `crates/editor-core-ui-ffi/include/editor_core_ui_ffi.h` 仍保持定宽 C surface。
- 未发现需要立即修复或新增前置任务的问题。
- 已运行并通过：`cargo fmt`、`cargo test -p editor-core-ui-ffi`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo clippy --all-targets -- -D warnings`。
- 已更新 `TODO.md`：`T16FR` 标题加 `[DONE]`，状态改为 DONE，并写入审查与验证完成记录。
- 当前工作树存在未跟踪的 `notification.sh`、`run_agent.sh`，与本任务无关，不修改也不提交。
- 下一步提交 `TODO.md` 和本计划文件的 T16FR review 记录。
