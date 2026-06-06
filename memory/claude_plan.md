# Claude Execution Plan

## Scope
- Follow `TODO.md` as the authoritative task list.
- Identify and complete exactly the first incomplete task, then stop.
- Do not proceed to later tasks in this invocation.

## Execution Plan
1. Read `TODO.md` and identify the first task whose title is not prefixed with `[DONE]`.
2. Check the latest commit only for unfinished work directly relevant to that task.
3. Read the task details and nearby context, then inspect only the relevant code, tests, and documentation.
4. Implement the task as specified, without weakening scope or using workarounds.
5. Run formatting, linting, targeted tests, and required broader validation in the required order.
6. If validation exposes unscheduled failures, either fix them if in scope or add the minimum prerequisite/follow-up task to `TODO.md` before marking completion.
7. Mark the completed task title with `[DONE]` and update its completion record.
8. Commit all intended changes with a descriptive message.
9. Stop after the commit.

## Progress Log
- Initial execution plan recorded before reading project task files.
- Read `TODO.md` and identified the first incomplete task as `T21UFR Review: 审查 editor-core-ui LSP processing 错误通道修复`.
- This invocation will perform only the T21UFR review, run the task-required validation, update `TODO.md` with `[DONE]` and a completion record if review passes, then commit and stop.
- Checked latest commit and confirmed `[T21UF] Fix UI LSP processing error handling` is the direct review target.
- Reviewed the T21UF diff in `crates/editor-core-ui/src/lib.rs`, including LSP processing-edit error propagation, `poll_processing` result reporting, LSP status handling, and new regression tests.
- Review found no blocking defect or missing prerequisite task.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, and `cargo test -p editor-core-ui`.
- Updated `TODO.md` to mark `T21UFR` as `[DONE]` with the review completion record.
- Reviewed final diff/status; only `TODO.md` and this progress file are intended for commit. Existing untracked `notification.sh` and `run_agent.sh` are unrelated and will remain untouched.
