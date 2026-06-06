# Claude Plan

## 当前目标

- 当前第一个未完成任务：`T07 实现：diff-semantic 样式常量与叠加`。
- 只完成 T07；完成代码、测试、文档记录与提交后停止，不进入 T07R。

## 执行计划

1. 查看最近提交信息，判断是否存在与 T07 直接相关的未完成问题；只在其阻塞当前任务时纳入处理或写入 `TODO.md` 前置任务。
2. 定向读取 T07 范围文件和入口：`crates/editor-core/src/intervals.rs`、`crates/editor-core-diff-view/src/style.rs`、`crates/editor-core-diff-view/src/projection.rs`，并定向确认现有 `STYLE_ID` 段位。
3. 在 `editor-core` 中新增未占用的 diff 专用 `StyleId` 常量，使用 `0x0900_xxxx` 段，至少包含 Add 行、Remove 行、Spacer 三类。
4. 在 `editor-core-diff-view/src/style.rs` 中 re-export 或轻量封装这些常量，供 projection/view 使用，不引入渲染或行内 diff 能力。
5. 在 projection 产物中为每个 `RowSlot` 叠加 diff-semantic 样式到 cell：Add 行整行加 add 样式，Remove 行整行加 remove 样式，Spacer 加 spacer 样式，Context 不加 diff 背景；保持语法等既有样式为叠加关系。
6. 新增 `crates/editor-core-diff-view/tests/style.rs`，覆盖 Add/Remove/Spacer/Context 样式行为与新增常量段不冲突。
7. 按要求先运行 `cargo fmt`，再运行 `cargo clippy --all-targets --all-features -- -D warnings`，然后运行 `cargo test -p editor-core-diff-view --test style`、`cargo test -p editor-core`、`cargo test -p editor-core-diff-view`、`cargo test --all --all-targets`。如发现未被 TODO 明确调度的测试失败，修复或把最小前置/后续任务加入 `TODO.md` 后停止。
8. 更新 `TODO.md`：将 T07 标题标记为 `[DONE]`，填写完成记录和验证结果；除非阶段级计划变化，不更新 `PLAN.md`。
9. 检查工作区状态、差异和最近提交，确保不回退用户/其他 agent 改动，只提交本任务需要的文件。
10. 使用清晰提交信息提交本任务，然后停止。

## 进度记录

- 已读取 `TODO.md`，确认第一个未完成任务为 `T07 实现：diff-semantic 样式常量与叠加`。
- 已按要求在执行命令前更新本计划文件；后续关键步骤完成时会继续更新。
- 已查看最近提交，`fb54b71 [T06R] Review side-by-side projection` 未提示与 T07 直接相关的未完成问题。
- 已检查工作区，发现未跟踪脚本 `notification.sh`、`run_agent.sh` 与 T07 无关，后续不纳入提交。
- 已读取 T07 范围入口，现有 `editor-core` 内置 `StyleId` 使用 `0x0300`、`0x0400`、`0x0700`、`0x0800` 段；`0x0900_xxxx` 段可用于 diff 专用样式。
- 已实现 `DIFF_ADD_LINE_STYLE_ID`、`DIFF_REMOVE_LINE_STYLE_ID`、`DIFF_SPACER_STYLE_ID` 并从 `editor-core` 根模块导出。
- 已在 `editor-core-diff-view/src/style.rs` re-export diff 样式常量，并新增行级样式叠加辅助；叠加会保留已有 `Cell.styles`。
- 已让 projection 的 `RowSlot` 携带 cells，并在生成 Add/Remove 行与 Spacer 时附加 diff-semantic 样式；Context 行不附加 diff 背景。
- 已新增 `tests/style.rs`，覆盖 Add/Remove/Spacer/Context 样式、叠加不覆盖已有样式、`0x0900_xxxx` 段不与既有常量冲突。
- 验证进度：`cargo fmt` 已运行；`cargo clippy --all-targets --all-features -- -D warnings` 已通过。
- 验证进度：`cargo test -p editor-core-diff-view --test style` 已通过；首次 `cargo test -p editor-core` 遇到 Rust 增量编译缓存缺失对象文件错误（编译缓存问题，非测试失败），下一步清理受影响 package 缓存后重跑同一测试。
- 已执行 `cargo clean -p editor-core` 清理受影响构建缓存；随后 `cargo test -p editor-core`、`cargo test -p editor-core-diff-view`、`cargo test --all --all-targets` 均通过。
- 已确认仓库内不存在 `tools/run_fixtures.py`，无独立 fixture runner 可运行。
- 已更新 `TODO.md`，将 T07 标记为 `[DONE]` 并填写完成记录；未修改 `PLAN.md`，因为阶段计划未变化。
