# 执行计划

## 约束

- 以 `TODO.md` 为唯一任务排序和完成状态来源。
- 只完成第一个标题未带 `[DONE]` 的任务，然后停止。
- 如遇当前任务的阻塞缺陷，先修复；若无法在本次完成，则在 `TODO.md` 中插入最小必要前置任务并提交后停止。
- 不用绕过、缩小范围或替代表示来规避规格缺口。
- 完成任务后更新 `TODO.md` 的 `[DONE]` 标题和完成记录，必要时才更新 `PLAN.md`。
- 提交前运行格式化、lint 和相关测试；若代码有变更，按要求执行完整验证。

## 步骤

1. 读取 `TODO.md`，定位第一个未完成任务，并检查任务自身的依赖、验证要求和完成记录。
2. 检查最近提交是否明确提到与该任务直接相关的未完成问题；只在其阻塞当前任务时纳入范围。
3. 阅读与当前任务相关的源码、测试、文档和计划上下文，确认最小正确实现范围。
4. 实现当前任务，优先采用小而聚焦的补丁；如发现必须先修复的规格缺口，更新 `TODO.md` 记录前置任务并停止。
5. 为实现补充或调整回归测试，避免夹具或测试绕过真实问题。
6. 运行 `cargo fmt`，再运行 `cargo clippy --all-targets -- -D warnings`，随后运行相关测试；代码变更后按要求运行完整测试套件。
7. 更新 `TODO.md`：在任务标题前加 `[DONE]`，填写本次完成记录、验证命令和结果；只有阶段级计划变化时才改 `PLAN.md`。
8. 检查 `git status`、`git diff` 和最近提交，确认提交范围包含本任务所有未提交变更且不回退他人更改。
9. 使用包含任务编号的清晰提交信息提交变更。
10. 停止，不继续下一个任务。

## 当前进度

- 已读取 `TODO.md`，第一个未完成任务为 `T01 实现：搭建 editor-core-diff-view crate 骨架`。
- 本次只处理 T01：新增 workspace crate、占位模块、最小 smoke test，并完成 T01 要求的构建/测试/lint 验证。
- 已检查最近提交、workspace `Cargo.toml` 与相邻 crate 元数据；最近提交未包含与 T01 直接相关的未完成问题。
- 已新增 `editor-core-diff-view` 最小骨架、四个模块和 smoke test。
- 验证已通过：`cargo fmt`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo build -p editor-core-diff-view`、`cargo test -p editor-core-diff-view`、`cargo clippy -p editor-core-diff-view --all-targets -- -D warnings`、`cargo test --all --all-targets`。
- 仓库内未发现 `tools/run_fixtures.py`，无独立 fixture runner 可运行。
- 已更新 `TODO.md`：T01 标题改为 `[DONE]`，状态和完成记录已填写；`PLAN.md` 无阶段级变化，未修改。
- 下一步检查 diff/status 并提交本任务变更。
