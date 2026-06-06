# Claude Execution Plan

## Scope

- Follow `TODO.md` as the authoritative task list.
- Complete exactly the first task whose title is not prefixed with `[DONE]`, then stop.
- Do not perform broad issue triage before selecting the current task.

## Steps

1. Read `TODO.md` and identify the first incomplete task by title prefix.
2. Check the latest commit message only for directly relevant unfinished work tied to that task.
3. Inspect the files and tests relevant to the selected task.
4. If a concrete prerequisite blocks correct execution, update `TODO.md` with the minimum prerequisite task, commit that bookkeeping, and stop.
5. Otherwise, implement the selected task completely with small focused patches.
6. Run formatting, linting, targeted tests, and required full validation in the requested order unless the task changes only documentation/bookkeeping and a prior green run can be reused.
7. Update `TODO.md` by prefixing the completed task title with `[DONE]` and filling its completion record.
8. Commit all relevant changes with a clear task-scoped message.
9. Stop without starting the next task.

## Progress

- Plan initialized before reading project task files.
- Selected first incomplete task: `T21UF 修复：收口 editor-core-ui LSP processing 错误通道与 poll 回归覆盖`.
- Next: check the latest commit for directly relevant unfinished work, then inspect only the listed UI entry points and tests.
- Latest commit is `[T21UR] Review editor-core-ui panic handling`; its recorded follow-up is exactly T21UF, so no extra prerequisite is needed.
- Implementation plan: add one LSP processing-edit apply helper that records failures through `lsp_fail` and returns `UiError::Processor`; update `poll_lsp_best_effort` and `poll_processing` to propagate that result; add internal tests for LSP apply failure and a constructible Tree-sitter poll error path.
- Implemented the LSP processing-edit helper and updated `poll_lsp_best_effort` / `poll_processing` to propagate apply failures without reporting `applied = true`.
- Added internal UI tests for LSP processing edit apply failure status, LSP session failure poll result, and Tree-sitter worker disconnection poll error.
- Validation passed: `cargo fmt`, `cargo test -p editor-core-ui`, `cargo clippy --all-targets -- -D warnings`, `cargo test --all --all-targets`, and `cargo clippy --all-targets --all-features -- -D warnings`.
- Fixture runner check: `tools/run_fixtures.py` / `tools/**/*fixture*` not found.
- Updated `TODO.md`: marked `T21UF` as `[DONE]` and recorded implementation notes, validation, and the Tree-sitter worker-missing constructability note.
- Next: inspect git status/diff/log, then commit the task changes.
