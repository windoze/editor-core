本文件记录本次任务的可审计执行计划、关键决策和进度检查点。不会记录隐藏推理链。

## 当前执行计划

1. 读取 `TODO.md`，只识别第一个标题未带 `[DONE]` 的任务，不做开放式历史问题排查。
2. 读取该任务必要上下文，包括相关 `PLAN.md` 片段、最近提交信息，以及任务涉及的代码和测试。
3. 判断当前任务是否可直接完成；如遇到阻塞当前任务的规格缺口、失败测试或必须先修复的实现边界，按要求在 `TODO.md` 中新增最小前置任务并停止。
4. 若任务可执行，实施最小正确修改，并保持变更聚焦。
5. 运行任务要求的验证；按要求先 `cargo fmt`，再 `cargo clippy --all-targets -- -D warnings`，最后运行相关或完整测试。
6. 更新 `TODO.md`：将完成任务标题加 `[DONE]`，补充完成记录和验证结果。仅当阶段级计划变化时才更新 `PLAN.md`。
7. 提交所有本次相关变更，提交信息包含任务编号和简明说明。
8. 完成一个任务后停止，不进入下一个任务。

## 进度

- 已创建初始计划，下一步读取 `TODO.md` 确认第一个未完成任务。
- 已确认第一个未完成任务为 `T21U 实现：editor-core-ui panic 与错误处理专项`。
- 下一步按任务范围读取最近提交、检查工作区状态，并定向分析 `crates/editor-core-ui/src/lib.rs` 与 `keybindings.rs` 中的 `unwrap` / `expect` / `panic!`，优先修复生产路径中的可恢复错误。
- 定向分类结果：`lib.rs` 中生产路径匹配点为 `EditorUi::new` 的内部不变量 `expect`，以及 `poll_processing` 中 3 个 Tree-sitter worker `expect`；`keybindings.rs` 中 3 个 `unwrap` 属于解析器生产路径。其余 `lib.rs` 匹配点位于 `#[cfg(test)]` 测试模块。
- 当前编辑计划：将 `keybindings.rs` 解析器 `unwrap` 改为显式错误返回；将 `poll_processing` 的 Tree-sitter worker `expect` 改为 `UiError::Processor`；保留 `EditorUi::new` 的不可恢复内部不变量并在完成记录中分类说明。
- 已完成代码修改：`keybindings.rs` 解析器不再使用 `unwrap`；`poll_processing` 在 Tree-sitter worker 状态异常时返回 `UiError::Processor`；新增 keybindings 定向测试覆盖 Unicode 单键与 malformed `when` 输入不 panic。
- 定向复查显示 `editor-core-ui/src` 剩余匹配为 `lib.rs` 244 处：除 `EditorUi::new` 的内部不变量 `expect` 外均位于 `#[cfg(test)]` 测试模块。
- 验证已通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ui`、`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。
- 已检查 fixture runner：未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`。
- 下一步更新 `TODO.md` 将 T21U 标记 `[DONE]` 并记录完成内容，然后提交本次变更。
- 已更新 `TODO.md`：`T21U` 标题已加 `[DONE]`，状态改为 DONE，并记录实现、分类、剩余匹配和验证结果。下一步检查 diff/status 后提交。
