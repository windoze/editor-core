# Execution Plan

## Scope

- Follow `TODO.md` as the authoritative task list.
- Identify the first task whose heading is not prefixed with `[DONE]`.
- Complete exactly that task, then stop after committing.

## Steps

1. Read `TODO.md` to identify the first incomplete task and its validation requirements.
2. Check the latest commit only for unfinished work directly relevant to that selected task.
3. Inspect the relevant code and tests for the selected task.
4. Implement the smallest spec-correct change needed for the selected task.
5. Add or update focused tests for the changed behavior.
6. Run formatting first, then clippy with warnings denied, then the required test suite.
7. If any failing test or fixture is observed and is not already explicitly scheduled, fix it or add the minimum prerequisite task before marking the current task complete.
8. Update `TODO.md` by prefixing the completed task heading with `[DONE]` and adding a completion record with validation results.
9. Commit all relevant changes with a descriptive task-scoped commit message.
10. Stop without starting the next task.

## Progress Log

- Initial plan written before task inspection.
- First incomplete task identified: `T21AR Review: 审查 editor-core-app panic 专项`.
- Review scope is the T21A diff and related app panic/error handling paths only.
- Reviewed the T21A source diff in `session.rs` and `settings.rs`; no immediate blocker found.
- Running required validation for the review task: `cargo fmt`, clippy with warnings denied, and `cargo test -p editor-core-app`.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, and `cargo test -p editor-core-app`.
- Updated `TODO.md` to mark `T21AR` as `[DONE]` with review findings and validation results.
