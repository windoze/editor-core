# 当前执行计划

## 约束说明
- 本文件记录可审阅的执行计划、关键决策依据和进度更新；不包含不可见的内部推理链。
- `TODO.md` 是任务顺序和完成状态的权威来源；只处理第一个标题未带 `[DONE]` 的任务。
- 完成当前任务后更新 `TODO.md` 的任务标题与完成记录，运行必要验证，提交 Git，然后停止。

## 初始计划
1. 读取 `TODO.md`，定位第一个未完成任务，并检查任务正文中的依赖、验证要求和完成记录格式。
2. 检查最新提交信息是否明确提到与该任务直接相关的未完成问题；若相关，将其纳入当前任务或作为前置任务记录到 `TODO.md`。
3. 按当前任务要求阅读必要代码和测试，确定最小正确修改范围。
4. 实施任务；若遇到阻塞当前任务的真实缺陷或缺失能力，优先修复，或在 `TODO.md` 中插入最小前置任务并停止。
5. 先运行 `cargo fmt`，再运行 `cargo clippy --all-targets -- -D warnings`，最后运行任务要求的测试和必要的完整测试。
6. 若验证通过，更新 `TODO.md`：给当前任务标题加 `[DONE]`，补充完成记录和验证命令；仅当阶段计划变化时才更新 `PLAN.md`。
7. 检查 `git status`、`git diff` 和最近提交，提交本次所有相关更改，提交后停止，不处理下一项任务。

## 进度记录
- 已创建本计划文件，下一步读取 `TODO.md` 定位首个未完成任务。
- 已读取 `TODO.md`，首个未完成任务为 `T21 实现：核心 panic 与错误处理专项`。
- 最新提交为 `[T20FR] Review design documentation consistency`，未发现与 T21 直接相关的未完成提交说明。
- 已定向审阅 `storage.rs` / `undo.rs`：核心修复点为 PieceTable UTF-8 unwrap / unchecked slice，以及 `UndoRedoManager` 当前节点、redo child 和 parent 链的直接索引。
- 已完成核心修改：PieceTable 新增 fallible `try_*` API 并移除生产路径 UTF-8 unwrap；undo/redo 弹栈和 redo branch 选择改为 checked access，非法/stale 节点返回 `CommandError`。
- 已补测试：storage 内部异常 piece 回归、undo 内部 stale node 回归，以及 `undo_history_robustness` 集成测试的非法 clean index restore 错误路径。
- 首次 `cargo clippy --all-targets -- -D warnings` 失败：`storage.rs` 中两个 `current_offset = 0` 的类型推断不足，需显式标注为 `usize` 后重跑。
- 第二次 `cargo clippy --all-targets -- -D warnings` 失败：`undo.rs` 中一个 `nonminimal_bool` lint，改为 `is_none_or`。
- `cargo test -p editor-core` 首次失败：新增的 invalid-current accessor 测试触发了只读 accessor 内部 `debug_assert`；accessor 目标是“不 panic”，需移除该类 debug assert 并保留 mutating pop/select 路径的显式错误。
- 验证已通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p editor-core --test undo_history_robustness`、`cargo test -p editor-core storage::tests`、`cargo test -p editor-core`、`cargo test --all --all-targets`。
- fixture runner 检查：未找到 `tools/run_fixtures.py` 或 `tools/**/*fixture*`。
- UI/app 统计记录：`editor-core-ui/src` 中 `unwrap/expect/panic!` 匹配 250 处（`lib.rs` 247，`keybindings.rs` 3）；`editor-core-app/src` 中匹配 106 处，已准备在 `TODO.md` 中追加后续专项任务，不混入 T21 核心修复。
- 已读取 `TODO.md`，T21 后的首个未完成任务为 `T21R Review：审查 panic 与错误处理专项`。
- T21R 静态审查完成：`PieceTable` 的 fallible range/UTF-8 helper 与 `UndoRedoManager` 的 checked node access 符合 review 重点，未发现需要新增前置修复任务的问题。
- T21R 验证已通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core`。
- 已将 `T21R` 标记为 `[DONE]` 并写入完成记录；下一步检查 diff 并提交本次 review。

## T21 执行计划
1. 只读取 T21 指定范围和已知入口：`storage.rs`、`commands.rs`/`undo.rs`、相关测试布局；使用定向 grep 查找 `unwrap`、`expect`、`panic!`、`self.nodes[`、`.parent.unwrap_or(0)`。
2. 将核心生产路径风险分类：测试专用、不可达不变量、可恢复错误；本任务优先处理 `storage.rs` UTF-8 unwrap 和 `UndoRedoManager` 直接索引/stale node panic 风险。
3. 对 `storage.rs` 保持 PieceTable 兼容 API 形状，优先用内部 fallible UTF-8 helper + `debug_assert` 表达数据结构不变量，生产路径不直接 unwrap。
4. 对 `UndoRedoManager` 将裸索引改为 checked access；当历史节点缺失、stale 或 tombstone 时返回 `CommandError`/现有错误通道，而不是 panic 或静默吞错。
5. 新增或扩展 `undo_history_robustness` 测试，覆盖非法/stale node restore 返回错误；若能构造 Piece 边界异常，覆盖生产路径不 panic。
6. 运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core`；若代码变化影响更广，再运行必要的额外测试。
7. 更新 `TODO.md` 中 T21 标题为 `[DONE]` 并填写完成记录；检查 diff/status/log 后提交并停止。

## T21R 执行计划
1. 读取 `TODO.md`，确认第一个未完成任务是 T21R review。
2. 查看最新提交，确认 `[T21] Harden core panic handling` 是直接相关提交，未发现额外未完成说明。
3. 审查 T21 diff 触及的 `storage.rs`、`undo.rs`、`edit_ops.rs` 和新增测试，重点检查可恢复错误是否走 `Result`/`CommandError`、是否吞错、undo checked access 是否覆盖直接索引路径、UTF-8 不变量是否保留 debug 检查，以及是否未混入 UI/app 修复。
4. 若发现明确问题，则修复或新增最小前置任务；若未发现问题，运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core`。
5. 更新 `TODO.md` 标记 T21R 为 `[DONE]` 并写入审查与验证记录；提交本次 review 后停止。
