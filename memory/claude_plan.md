# Execution Plan

## Scope

- Follow `TODO.md` as the authoritative task list.
- Identify and complete exactly the first task whose heading is not prefixed with `[DONE]`.
- Stop after committing that task or, if blocked, after recording the minimum required prerequisite task and committing the bookkeeping change.

## Step-by-Step Plan

1. Read `TODO.md` first and identify the first incomplete task.
2. Inspect only the files needed to understand that task and its validation requirements.
3. Check the recent commit message only if it may mention unfinished work directly relevant to the selected task.
4. Implement the task as written, avoiding workarounds or narrowed scope.
5. Add or update focused tests for the behavior changed by the task.
6. Run formatting, linting, and relevant tests in the required order.
7. If any failing test or fixture is observed, either fix it or add the minimum scheduled task before marking the current task done.
8. Update `TODO.md` by prefixing the task heading with `[DONE]` and adding a completion record.
9. Update this plan file with completed key steps and validation results.
10. Inspect git status and diff, then commit all intended changes with a descriptive message.
11. Stop without starting the next task.

## Progress

- Initial execution plan written.
- First incomplete task identified: `T22 实现：阶段性全量收口`.
- T22 scope is validation-only except for fixes required by formatting, tests, clippy, or documentation consistency failures.
- `cargo fmt` completed with no source changes.
- `cargo clippy --all-targets --all-features -- -D warnings` passed.
- `cargo test -p editor-core` passed.
- `cargo test -p editor-core-lsp` passed.
- `cargo test -p editor-core-ffi` passed.
- `cargo test` passed for the full workspace test suite.
- Final `cargo clippy --all-targets --all-features -- -D warnings` passed.
- No fixture runner found at `tools/run_fixtures.py` or `tools/**/*fixture*`.
- `TODO.md` updated to mark T22 as `[DONE]` with validation results.
