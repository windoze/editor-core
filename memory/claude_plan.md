执行计划记录

当前目标：根据 `TODO.md` 的权威顺序，只完成第一个未标记 `[DONE]` 的任务，然后提交并停止。

计划步骤：
1. 读取 `TODO.md`，按标题是否带 `[DONE]` 识别第一个未完成任务。
2. 检查最近提交信息是否明确提到与该任务直接相关的未完成问题；只处理会阻塞当前任务的事项。
3. 阅读当前任务涉及的文档、代码和测试，确认实现边界、依赖和验证要求。
4. 如发现当前任务无法按规格完成且存在缺失前置条件，按最小原则更新 `TODO.md`，提交后停止。
5. 如可直接完成，则实施最小正确修改，并为修改添加必要的测试或更新既有测试。
6. 按要求先运行 `cargo fmt`，再运行 `cargo clippy --all-targets -- -D warnings`，再运行相关及完整测试；如仅修改文档且已有可复用绿色结果，则记录跳过原因。
7. 将完成记录写回 `TODO.md`，把任务标题显式加上 `[DONE]`。
8. 检查 `git status` 和差异，提交本次任务相关全部修改，然后停止，不进入下一个任务。

进度：
- 已创建本计划文件，下一步读取 `TODO.md` 确认第一个未完成任务。
- 已读取 `TODO.md`，第一个未完成任务是 `T01 实现：LSP 子进程生命周期回收`。
- 下一步检查最近提交和 T01 范围文件，确认是否存在直接相关的未完成前置问题。
- 最近提交 `68a51de Update plan` 只更新计划/评审文档，没有直接相关的未完成实现问题。
- 已检查 T01 范围入口：`LspClient` 当前持有 `_child` 且无回收逻辑，`LspSession::exit` 仅发送 `exit` notification。
- 计划修改：将 `_child` 改为 `child`，新增客户端关闭流程（shutdown 请求短超时、exit notification、短等待、必要时 kill+wait），并在 Drop 中做兜底回收。
- 已完成核心实现：`LspClient` 现在持有可操作的 `child`，提供 `shutdown` / `exit` / `terminate`，并在 Drop 中强制回收；`LspSession::exit` 已改为走该生命周期路径。
- 已新增 `lsp_process_lifecycle` 专项测试并通过一次 targeted run：3 个测试均通过。
- `cargo clippy --all-targets -- -D warnings` 发现一个阻塞性现有 lint：`commands.rs` 中 `skip_while(...).next()`；已做最小等价替换为 `find(...)`，用于通过质量门禁。
- 后续 clippy 又发现示例和 benchmark 中显式计数器 lint；已将循环改为直接迭代 offset 区间，保持行为等价。
- 第三次 clippy 在 `editor-core-ui` benchmark 中发现同类 lint；已做相同最小等价修正。
- 完整 `cargo test --all --all-targets` 首次运行发现 `editor-core-ui-ffi` 的 gutter fold marker 像素测试失败。
- 已定位为测试未固定 fold marker 样式，默认箭头样式抗锯齿导致精确像素断言不成立；已在该 FFI 测试中设置 `Block` 样式以匹配确定性断言。
- 重跑目标测试后发现 block marker 占用 2 个 gutter cell，而测试仅配置 2 个 cell 却断言第二 cell 是背景；已改为 4 cell gutter，并在 marker 列之后检查背景像素。
- 验证完成：`cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test -p editor-core-lsp --test lsp_process_lifecycle`、`cargo test -p editor-core-lsp`、`cargo test --all --all-targets` 均通过。
- 未找到 `tools/run_fixtures.py`，因此没有可运行的完整 fixture runner。
- 下一步更新 `TODO.md`，将 T01 标记为 `[DONE]` 并记录完成信息。
- 已更新 `TODO.md`：T01 标题已标记 `[DONE]`，状态改为 DONE，并写入完成记录。
- 下一步检查 git diff/status，确认只提交本任务相关修改和要求包含的进度文件。
- 已提交 T01 修改，提交为 `35c0991 [T01] Reap LSP server processes`。
- 提交后工作区仅剩本轮开始前已存在且无关的未跟踪文件 `run_agent.sh`，未纳入提交。
