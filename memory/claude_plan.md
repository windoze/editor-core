# Claude Execution Plan

## Guardrails

- Use `TODO.md` as the authoritative task order and completion source.
- Complete exactly the first task whose heading is not prefixed with `[DONE]`, then stop.
- Do not perform broad historical issue triage before identifying the current task.
- Treat blocking test or fixture failures as real work: fix them or schedule explicit prerequisite tasks before marking the current task done.
- Avoid workarounds or weakened fixtures; if spec-correct implementation is blocked, update `TODO.md` with the minimum prerequisite task and stop.
- Update this file whenever the active plan changes or a key step completes.

## Step-by-Step Plan

1. Read `TODO.md` and identify the first incomplete task by heading prefix.
2. Check the latest commit message only for unfinished work directly relevant to that task.
3. Read the task body and the minimal surrounding project context needed to implement it.
4. Inspect current git status so existing user or prior-agent changes are not overwritten.
5. Implement the task with small, focused patches.
6. Add or update focused regression tests for the changed behavior.
7. Run `cargo fmt`, then `cargo clippy --all-targets -- -D warnings`, then the relevant/full test commands required by the task.
8. If validation exposes unscheduled failures, fix them if in scope or add explicit prerequisite/follow-up tasks in `TODO.md` before completion.
9. Mark the task heading in `TODO.md` with `[DONE]` and update its completion record with the implementation and validation performed.
10. Review the final diff, commit all intended changes with a descriptive task-scoped commit message, and stop without starting the next task.

## Progress Log

- Initialized execution plan before reading task details.
- Identified the first incomplete task as `T02R Review: diagnostics version guard review`; the scope is a review of T02 diff only, not implementation of T03.
- Reviewed the T02 changes in `editor.rs`, `workspace_sync.rs`, and `diagnostics_processing_edits.rs`; no direct review finding has been identified before validation.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test diagnostics_processing_edits`, and `cargo test -p editor-core-lsp`.
- Marked `T02R` as `[DONE]` in `TODO.md` with a completion record. Next step is final diff review and commit.
- Final diff review completed; only `TODO.md` and this progress file are intended for the T02R commit. Existing untracked `notification.sh` and `run_agent.sh` are outside this task and will not be staged.
