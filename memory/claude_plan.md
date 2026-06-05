本轮执行计划
========

目标：按照 `TODO.md` 的顺序完成第一个未标记 `[DONE]` 的任务，完成后提交并停止。

约束与判定
----------

- `TODO.md` 是唯一任务排序与完成状态来源。
- 只有标题显式带有 `[DONE]` 的任务才算完成。
- 本轮只完成第一个未完成任务，不继续处理后续任务。
- 如果遇到阻塞当前任务的真实缺陷、缺失特性或测试/fixture 失败，优先修复；若无法在当前任务内正确修复，则把最小必要前置任务插入 `TODO.md`，提交并停止。
- 不通过缩小范围、改 fixture 形状、绕开模型或特殊用例来规避规范问题。
- `PLAN.md` 只在阶段级计划或依赖结构变化时更新。

步骤计划
--------

1. 读取 `TODO.md`，识别第一个标题未带 `[DONE]` 的任务，并记录其要求、依赖和验证项。
2. 查看最近提交，只有当最新提交明确提到与该任务直接相关的未完成问题时，才把它纳入当前任务或作为前置项写入 `TODO.md`。
3. 根据该任务定位相关代码、测试和文档，避免无关历史问题扫描。
4. 实现任务要求；如发现阻塞性规范缺口，按要求更新 `TODO.md` 并停止。
5. 运行格式化、lint 和相关测试；若涉及编译输出变化，按顺序运行 `cargo fmt`、`cargo clippy --all-targets -- -D warnings`，再运行必要的完整测试/fixture 验证。
6. 若所有验证通过，在 `TODO.md` 中给当前任务标题加 `[DONE]`，更新 completion record。
7. 检查 git 状态、diff 和最近提交，确认只提交本轮相关变更；若是恢复未完成任务，则按要求包含当前未提交文件。
8. 使用清晰任务消息提交，提交后停止，不处理下一任务。

历史进度记录：T16
-----------------

- 已写入初始执行计划。
- 已读取 `TODO.md`，确认第一个未完成任务是 `T16 实现：FFI ABI 定宽迁移`。
- T16 的核心要求：定向列出 public `extern "C"` 签名中的 `usize`，将新公共 ABI 迁移为定宽整数，内部转换必须做溢出检查并返回 `InvalidArgument`，同步 ABI 文档和 FFI 测试；完成后只标记 T16，不处理 T16R。
- 已完成定向 `extern "C" fn` + `usize` 检查，发现公开 `usize` 只在 `editor-core-ffi/src/lib.rs`，`editor-core-ui-ffi` 公开签名未暴露 `usize`。
- 已将 `editor-core-ffi` 公开 `usize` 签名改为 `u32`/`u64`，并新增定宽入参到 `usize` 的检查 helper；当前定向复查已无 public `extern "C"` 签名暴露 `usize`。
- 已同步 `crates/editor-core-ffi/include/editor_core_ffi.h`、Swift `EditorCoreFFI` 包装和 `docs/abi-v1-draft.md`；Swift 侧不再用 `Int(clamping:)` 向 ABI 传递会被静默截断的宽度/行数参数。
- 已扩展 `crates/editor-core-ffi/tests/abi_v1.rs`，加入编译期函数指针签名断言，固定公开 ABI 的 `u32`/`u64` 形状，并覆盖必填输出指针的 `InvalidArgument` 错误路径和 LSP `u64` 边界坐标不截断行为。
- 已运行 `cargo fmt`。
- 首次运行 `cargo test -p editor-core-ffi --test abi_v1` 时，新增测试触及已排期 `T19` 的 UTF-16 半代理对策略差异；已将 T16 测试收窄为不覆盖半代理对策略，只验证 u64 边界输入不会被截断。
- `swift test` 首次运行因 SwiftPM 插件缺少/过期 Rust staticlib 失败；已按插件提示运行 `cargo build -p editor-core-ui-ffi --release`。随后 Swift 编译暴露本轮 Swift 多语句函数漏写 `return`，已修复。
- 已通过验证：`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --all --all-targets`、`cargo build -p editor-core-ui-ffi --release`、`swift test`。
- 已确认仓库没有 `tools/run_fixtures.py`、`tools/**/*fixture*` 或 `tools/` fixture runner，完整 fixture suite 无可运行入口。
- 已将 `TODO.md` 中 T16 标记为 `[DONE]` 并补充完成记录；不会继续执行 T16R。

当前进度记录：T16R
------------------

- 已读取 `TODO.md`，第一个未完成任务是 `T16R Review：审查 FFI ABI 定宽迁移`。
- 已检查最近提交：`cc6e542 [T16] Migrate FFI ABI to fixed-width types`，与当前 review 任务直接相关。
- 当前执行范围限定为审查 T16 diff、确认 public C ABI 定宽与溢出检查、运行 T16R 建议验证命令，并在完成后更新 `TODO.md` 与提交。
- 已完成 T16R 审查，确认 `editor-core-ffi` public `extern "C"` 签名未继续暴露 `usize`，header 未继续暴露 `size_t`。
- 审查发现需要排期的 T16 后续修复项：ABI 文档对旧 ABI/布尔类型/当前 public surface 的描述不完全一致，`editor-core-ui-ffi` 仍有 unchecked `as` 转换和部分输出长度截断风险。计划在 `TODO.md` 中新增 `T16F` / `T16FR`，位置放在 `T16R` 之后、`T17` 之前。
- 已运行并通过：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-ffi --test abi_v1`、`cargo test -p editor-core-ffi`、`cargo test -p editor-core-ui-ffi`。
- 已更新 `TODO.md`：`T16R` 标记为 `[DONE]`，并新增 `T16F` / `T16FR` 作为 `T17` 前的后续修复与 review 任务。
