# 当前执行计划

## 约束
- 以 `TODO.md` 为唯一任务顺序和完成状态来源。
- 本次只完成第一个未在标题中标记 `[DONE]` 的任务，然后停止。
- 若遇到阻塞当前任务的真实缺陷或缺失能力，先修复；若不能在本次完成，则在 `TODO.md` 中添加最小前置任务并提交后停止。
- 不用规避、降级夹具、缩小规格或引入临时兼容层来绕开问题。
- 若有代码变更，按要求运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`，再运行相关测试；需要时运行完整测试套件并记录结果。
- 任务完成后必须在 `TODO.md` 标题前加 `[DONE]`，更新完成记录，并提交所有相关更改。

## 步骤
1. 读取 `TODO.md`，按顺序定位第一个标题未带 `[DONE]` 的任务。
2. 查看该任务的依赖、验证要求和完成记录；如最新提交明确提到与该任务直接相关的未完成问题，一并纳入范围或补为前置任务。
3. 检查当前工作树状态，避免覆盖用户或其他代理的无关改动。
4. 阅读与当前任务相关的源码、测试和文档，确定最小正确实现范围。
5. 实施当前任务；若发现阻塞性规格不匹配或缺失能力，按任务规则更新 `TODO.md` 并停止。
6. 添加或更新聚焦测试，必要时补充文档。
7. 运行格式化、lint 和任务要求的测试；处理所有未被明确排期的失败。
8. 更新 `TODO.md` 的 `[DONE]` 标记和完成记录；仅当阶段级计划变化时更新 `PLAN.md`。
9. 查看 diff、状态和最近提交，确认只提交本次相关文件。
10. 使用清晰任务编号提交更改，然后停止，不处理下一个任务。

## 进度
- 已读取 `TODO.md`，第一个未完成任务是 `T16F 修复：收口 FFI ABI 契约与 UI FFI 转换检查`。
- 已检查最近提交：最新提交为 `T16R`，直接对应当前 T16F 前置修复项，无需额外改写任务顺序。
- 已检查工作树：本次新增/修改 `memory/claude_plan.md`；未跟踪的 `notification.sh`、`run_agent.sh` 与当前任务无关，不修改也不提交。
- 已审查 `editor-core-ui-ffi/src/lib.rs`：存在多处 public `u32` 入参直接 `as usize`、slice count 直接进入 `from_raw_parts`、`usize` 输出直接 `as u32`，以及 RGBA required length 可能截断。
- 已审查 ABI 文档/Header：文档的 boolean 规则与当前 header/Rust 实现仍需补充 pre-v1 兼容说明；fixed-width surface 列表需说明 header 是权威定义或改为代表性示例。
- 已在 `editor-core-ui-ffi` 增加 fixed-width 转换、slice count、输出 `u32` 边界 helper，并替换 T16F 指定入口及相关选择/渲染路径的直接截断点。
- 已扩展同文件测试，覆盖 null output pointer、RGBA required length 超出 `u32`、非零 count 搭配 null ranges 的 invalid-argument 路径。
- 已更新 `editor_core_ffi.h` 与 `docs/abi-v1-draft.md`，说明 pre-v1 fixed-width 收口、legacy C `bool` 策略和 Header 权威性。
- 已运行 `cargo fmt`。
- 首次 `cargo clippy --all-targets -- -D warnings` 在 `editor-core-ui-ffi` 编译阶段发现 `ViewportState.sub_row_offset` 是 `u16`，已改为 `u32::from(...)` 无损输出。
- 已重新运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ui-ffi`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo test --all --all-targets`、`cargo clippy --all-targets --all-features -- -D warnings`。
- 已确认 `tools/run_fixtures.py` 与 `tools/**/*fixture*` 均不存在，完整 fixture suite 无可运行入口。
- 已更新 `TODO.md`：T16F 标题加 `[DONE]`、状态改为 DONE，并写入实现与验证完成记录。
- 下一步检查 diff/status，确认只提交 T16F 相关文件和本计划文件，然后创建 Git 提交。
