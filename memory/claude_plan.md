# 执行计划

## 当前约束

- `TODO.md` 是任务顺序、要求、依赖和完成记录的唯一权威来源。
- 本轮只完成第一个标题未带 `[DONE]` 的任务，完成后提交并停止。
- 若遇到阻塞当前任务的真实缺口或测试/fixture 失败，必须修复，或把最小前置任务写入 `TODO.md` 后提交并停止。
- 不为方便而拆分任务，不绕过规格要求，不修改无关用户改动。
- 我不会记录隐藏推理链路；本文件记录可审计的执行计划、关键决策和进度。

## 初始步骤

1. 读取 `TODO.md`，找到第一个未以 `[DONE]` 开头的任务。
2. 检查该任务的正文、依赖、验证要求和完成记录。
3. 查看最近提交是否明确提到与该任务直接相关的未完成事项；如有，将其纳入当前任务或作为前置任务记录到 `TODO.md`。
4. 根据任务范围读取相关源码、测试和文档，只做与当前任务相关的调查。

## 实施步骤

1. 按任务要求实现最小且完整的代码或文档变更。
2. 如发现当前任务被具体缺口阻塞，更新 `TODO.md` 的依赖/前置任务，并停止后续实现。
3. 对修改点添加或更新聚焦测试；避免 fixture-only hack 或弱化规格。
4. 运行 `cargo fmt`。
5. 运行 `cargo clippy --all-targets -- -D warnings`。
6. 在 lint 通过后运行任务要求的目标测试；如任务或改动需要，运行完整测试套件并设置足够超时。

## 收尾步骤

1. 将当前任务标题在 `TODO.md` 中加上 `[DONE]`，并更新完成记录，写明实现内容和验证结果。
2. 仅当阶段级计划、依赖或完成标准变化时更新 `PLAN.md`。
3. 检查 `git status`、`git diff` 和最近提交，确认只提交预期文件；若本轮是恢复未提交任务，按要求包含当前未提交文件。
4. 使用清晰提交信息提交本轮改动。
5. 停止，不继续下一项任务。

## 进度记录

- 本轮已读取 `TODO.md`，第一个未完成任务是 `T06 实现：移除 LayoutEngine.line_texts 文本副本`。
- T06 范围限定为 `layout.rs`、相关重排调用点、snapshot/state/commands 触发路径以及布局一致性测试；本轮不进入 T06R 或后续任务。
- 执行计划：先检查最新提交和当前工作区状态；再读取 T06 范围源码与现有测试，定位 `LayoutEngine.line_texts` 的字段、方法和调用点；随后删除该文本副本，让布局变更由调用方从 `LineIndex`/`TextBuffer` 提供行文本触发重排，并确保 visual-row cache 失效；最后补充 resize、wrap mode、wrap indent、tab width 与编辑后 viewport 一致性测试。
- 验证计划：按要求先运行 `cargo fmt`，再运行 `cargo clippy --all-targets -- -D warnings`，之后运行 `cargo test -p editor-core --test incremental_viewport_consistency` 和 `cargo test -p editor-core`；如改动影响范围扩大，再运行必要的全量测试。
- 已删除 `LayoutEngine.line_texts` 字段；`set_viewport_width` / `set_wrap_mode` / `set_wrap_indent` / `set_tab_width` 现在只更新布局参数，新增 `recalculate_all_from_lines` 供调用方用真实文本重排。
- 已将 `CommandExecutor` 视图设置路径、workspace 视图状态恢复路径和 `SnapshotGenerator` 改为在布局参数变化后从 `LineIndex` 或自身行列表触发全量重排，并使 visual-row cache 在重排后失效。
- 已扩展 `incremental_viewport_consistency`，覆盖 viewport width、wrap mode、wrap indent、tab width 变化后的参考快照一致性。
- 已确认 `crates/**/*.rs` 中不再存在 `line_texts`，也不再存在旧的内部 `recalculate_all()` 文本副本重排路径。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test incremental_viewport_consistency`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 已检查 `tools/run_fixtures.py` 不存在，因此无可运行的完整 fixture suite。下一步更新 `TODO.md` 的 T06 完成记录并提交。
- 已创建初始执行计划；下一步读取 `TODO.md` 确认第一个未完成任务。
- 已读取 `TODO.md`，第一个未完成任务是 `T05 实现：新增 TextBuffer 抽象并建立一致性校验`。
- 已检查最新提交 `50a3680 [T04FR] Review folding preservation fix`，未发现与 T05 直接相关的未完成事项。
- 下一步只读取 T05 范围文件和相关入口，确认现有 `LineIndex`、`PieceTable`、`EditorCore` 与命令编辑路径后实施。
- 已确认现有文本副本为 `PieceTable`、`LineIndex` 内部 Rope、`LayoutEngine` 行文本；为避免新增第四份完整文本，将新增内部 `TextBuffer` 直接持有 Rope，并让 `LineIndex` 委托 `TextBuffer`，而不是在 `EditorCore` 中另存一份文本。
- `EditorCore::get_text` / `char_count` 将改为通过 `LineIndex` 暴露的 `TextBuffer` 读取；编辑路径继续更新 `PieceTable` 作为影子，并在 `apply_text_change_to_line_index_and_layout` 末尾增加 debug-only 一致性断言。
- 已新增 `crates/editor-core/src/text_buffer.rs`，将 `LineIndex` 改为委托 `TextBuffer`，并让 `EditorCore::get_text` / `char_count` 优先读取该缓冲。
- 已在命令编辑同步路径中加入 debug-only `PieceTable` 与 `TextBuffer` 全文一致性断言。
- 已新增 `crates/editor-core/tests/text_buffer_single_source.rs`，覆盖空文档、末尾换行、Unicode、CRLF 入口归一化、range/line 读取、插入删除和影子一致性。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test text_buffer_single_source`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- 已确认不存在 `tools/run_fixtures.py`，因此无可运行的完整 fixture suite。
- 下一步更新 `TODO.md` 的 T05 标题和完成记录，然后检查 diff 并提交。

## T05R Review 进度记录

- 已定位当前第一个未完成任务：`T05R Review：审查 TextBuffer 抽象`。本次只执行该 review 任务，重点审查 T05 diff 中 TextBuffer char offset 语义、文本副本数量、CRLF 入口归一化、一致性断言覆盖和 Unicode/末尾换行测试。
- 已审查 T05 代码路径：`TextBuffer` 继续以 char offset 为边界，`LineIndex` 包装该 Rope 存储而非新增额外完整副本，`EditorCore::new` 与编辑命令仍在入口归一化 CRLF，命令编辑路径在同步 `PieceTable` 与 `TextBuffer` 后执行 debug-only 一致性断言；暂未发现需立即修复的问题。
- 已完成验证：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core --test text_buffer_single_source`、`cargo test -p editor-core` 均通过。已将 `T05R` 在 `TODO.md` 中标记为 `[DONE]` 并填写完成记录；下一步检查 diff/status/log 后提交本次 review 记录。
