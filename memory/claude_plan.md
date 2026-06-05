# Claude Execution Plan

## Scope

This invocation will complete exactly the first incomplete task in `TODO.md`, then stop. `TODO.md` is the source of truth for task order, requirements, validation, and completion records.

## Step-By-Step Plan

1. Read `TODO.md` and identify the first task whose title is not prefixed with `[DONE]`.
2. Check the latest commit summary only for directly relevant unfinished work related to that selected task.
3. Inspect the code and documentation needed for the selected task, avoiding broad unrelated triage.
4. Implement the selected task completely, or if a concrete blocker prevents correct implementation, add the minimum prerequisite task to `TODO.md` and stop after committing that bookkeeping.
5. Run targeted validation first, then `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, and the required full test/fixture suites unless only documentation changed since a prior green run can be reused.
6. Fix any observed unscheduled test or fixture failures, or schedule them explicitly before the current task if they block completion.
7. Mark the selected task title in `TODO.md` with `[DONE]` and update its completion record with the actual work and validation performed.
8. Update this plan file when key steps complete or if the plan changes.
9. Review `git status`, `git diff`, and recent commits, then commit all relevant changes with a clear task-specific message.
10. Stop without starting the next task.

## Progress

- Plan initialized before project commands.
- Selected first incomplete task: `T08FR Review：审查视觉行索引同步修复`.
- Next step is to inspect only the T08F-related diff/context and perform the review checklist before updating `TODO.md`.
- Reviewed the T08F commit scope: centralized folding line-delta handling, visual-row index batch insertion/removal, composed viewport start lookup, TUI direct fold invalidation, and new visual-row regression tests.
- No blocking finding has been identified so far; validation commands are next.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core --test visual_row_index`, `cargo test -p editor-core --test visual_row_improvements`, and `cargo test -p editor-core`.
- Marked `T08FR` as `[DONE]` in `TODO.md` with the review result and validation record.
