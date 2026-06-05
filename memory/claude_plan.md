# Execution Plan

This file records the actionable plan and progress for the current invocation. It intentionally contains a concise, auditable plan rather than private chain-of-thought.

## Current Objective

Complete exactly `T18 实现：多折叠区域 visual/logical 往返修正`, mark it `[DONE]`, validate it, commit the resulting changes, and stop.

## Step-by-Step Plan

1. Read `TODO.md` first and identify the first task whose title is not prefixed with `[DONE]`.
2. Check the latest commit message only for unfinished work that is directly relevant to that selected task.
3. Read the selected task details, dependencies, completion record, and validation requirements.
4. Inspect only the code and documentation needed to implement that task correctly.
5. If the task is blocked by a concrete missing prerequisite or unscheduled failing test/fixture, update `TODO.md` with the minimum prerequisite task, commit that bookkeeping change, and stop.
6. Implement the selected task directly without weakening the intended behavior or introducing workaround-only behavior.
7. Add or update focused tests and fixtures required by the selected task.
8. Run formatting first, then linting with warnings denied, then targeted tests, and finally the required full validation if code changes require it.
9. Fix any observed unscheduled test or fixture failures before marking the task complete, or schedule them explicitly before stopping.
10. Update `TODO.md` by prefixing the selected task title with `[DONE]` and filling in its completion record with files changed and validation performed.
11. Update this file when key steps complete or if the plan changes.
12. Inspect git status, diff, and recent log, then commit all changes relevant to this invocation with a descriptive message.
13. Stop after the commit without starting the next task.

## Progress

- Plan initialized before reading task details.
- Read `TODO.md`; first incomplete task is T18.
- Next checks: latest commit for directly relevant unfinished work, then T18 scoped code/tests only.
- Latest commit is T17R and does not mention unfinished T18 work.
- Current focus: add T18 visual/logical mapping coverage and fix `FoldingManager` folded-line mapping so overlapping/nested collapsed regions are treated as a union of hidden lines instead of double-counted ranges.
- Implemented the mapping fix and added `folding_visual_mapping` regression tests.
- Validation passed: `cargo fmt`, both clippy variants, T18 targeted tests, `cargo test -p editor-core`, and `cargo test --all --all-targets`.
- No fixture runner found under `tools/run_fixtures.py` or `tools/**/*fixture*`.
- Updated `TODO.md` to mark T18 as `[DONE]`; next step is final diff/status review and commit.
