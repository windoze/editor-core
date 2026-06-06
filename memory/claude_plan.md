# Current Invocation Plan

## Scope

- Use `TODO.md` as the authoritative task list and complete exactly the first heading not prefixed with `[DONE]`.
- Keep `PLAN.md` unchanged unless phase-level sequencing, dependencies, assumptions, or completion criteria change.
- Stop after the selected task is implemented, validated, documented in `TODO.md`, committed, and no next task is started.

## Execution Steps

1. Read `TODO.md` first to identify the first incomplete task and its explicit requirements.
2. Inspect recent git context only for directly relevant unfinished work tied to that task.
3. Read the task-related code, tests, fixtures, and design notes needed to understand the target behavior.
4. Implement the smallest spec-correct change, or add the minimum prerequisite task in `TODO.md` if a concrete blocker prevents correct implementation.
5. Update this file whenever the selected task is identified, a key implementation step completes, validation status changes, or the plan changes.
6. Run validation in the required order: formatting, linting with warnings denied, then relevant/full tests or fixtures required by the task.
7. Address any observed unscheduled failing tests or fixtures by fixing them or scheduling the minimum prerequisite before completion.
8. Mark the completed task heading in `TODO.md` with `[DONE]` and update its completion record.
9. Inspect git status, diff, and recent log; commit intended changes with a descriptive task-scoped message; then stop.

## Progress Log

- Wrote this invocation plan before selecting the current `TODO.md` task. This file records auditable plan/progress, not private chain-of-thought.
- Read `TODO.md`; selected first incomplete task: `T06 实现：project_side_by_side（spacer + max 对齐）`.
- Current scope is limited to `crates/editor-core-diff-view/src/projection.rs` and new `tests/projection_side_by_side.rs`, unless a directly blocking T06 issue requires TODO bookkeeping.
- Implemented the side-by-side projection path and added T06-focused tests for Add/Remove spacers, different column widths, end-of-unit padding, and Replace spacer semantics.
- Next validation order: `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, targeted T06 tests, crate tests, then full workspace tests.
- First clippy run found `needless_range_loop` in the new projection row materialization; replaced the index loop with direct two-column iteration and will rerun validation from formatting.
- Validation passed after the fix: `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test -p editor-core-diff-view --test projection_side_by_side`, `cargo test -p editor-core-diff-view`, and `cargo test --all --all-targets`.
- Fixture runner check: `tools/run_fixtures.py` is not present in this repository, so no separate fixture suite was run.
- Updated `TODO.md` to mark `T06` as `[DONE]` with implementation and validation notes; no `PLAN.md` change is needed.
