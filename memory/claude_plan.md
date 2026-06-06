# Execution Plan

## Scope
- Follow `TODO.md` as the authoritative ordered task list.
- Complete exactly the first task whose heading is not prefixed with `[DONE]`, then stop.
- Do not perform broad historical triage before selecting the current task.

## Steps
1. Read `TODO.md` and identify the first incomplete task exactly as written.
2. Check the latest commit only for an unfinished issue that is directly relevant to that task.
3. Inspect the files and tests needed for that task.
4. Implement the task directly, unless a concrete prerequisite blocker makes correct execution impossible.
5. If blocked, add the minimum prerequisite task to `TODO.md`, update this plan, commit, and stop.
6. Run formatting, linting, targeted tests, and then broader validation as required by the task and repository policy.
7. Mark the task heading in `TODO.md` with `[DONE]` and update its completion record.
8. Commit all intended changes with a clear task-specific message.
9. Stop without starting the next task.

## Progress
- Plan initialized before executing repository commands.
- First incomplete task identified: T05 `DiffProjection` skeleton + `project_unified`.
- Next step: inspect only T05-relevant design/code/tests and the latest commit for directly relevant unfinished work.
- Latest commit `319ba73 [T04R] Record review plan status` has no directly relevant unfinished T05 issue.
- Implemented the initial projection structures, unified build path, SnapshotGenerator-based wrapping, and `projection_unified` regression tests.
- Verification passed: `cargo fmt`, `cargo test -p editor-core-diff-view --test projection_unified`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test -p editor-core-diff-view`, and `cargo test --all --all-targets`.
- `TODO.md` updated to mark T05 `[DONE]` with completion notes. Next step: inspect git diff/status and commit the T05 changes only.
