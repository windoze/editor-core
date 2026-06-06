# Current Invocation Plan

## Scope

- Follow `TODO.md` as the authoritative task list.
- Complete exactly the first task whose heading is not prefixed with `[DONE]`.
- Stop after implementing, validating, documenting, and committing that one task, or after committing any required prerequisite/blocker bookkeeping if completion is impossible.

## Execution Steps

1. Read `TODO.md` to identify the first incomplete task and its validation requirements.
2. Check recent project context only as needed for that task, including whether the latest commit references a directly relevant unfinished issue.
3. Inspect the files and tests relevant to the selected task.
4. Implement the smallest correct change that satisfies the task without workarounds or spec deviations.
5. Run formatting first, then linting, then the relevant/full tests required by the task policy.
6. If any unscheduled failing test or fixture is observed, fix it or add the minimum prerequisite task in `TODO.md` before marking the current task complete.
7. Update `TODO.md` by prefixing the completed task heading with `[DONE]` and filling its completion record.
8. Update this plan file when key steps complete or if the plan changes.
9. Inspect git status/diff/log, commit all intended changes with a descriptive message, then stop.

## Progress Log

- Initial plan written before repository inspection.
- Read `TODO.md`; selected first incomplete task: `T05R Review：审查 projection 骨架与 unified`.
- Current scope is review-only unless a concrete T05 bug, test gap, or quality issue is found.
- Reviewed T05 projection implementation and unified tests against `TODO.md` / `PLAN.md`; no concrete issue found so far.
- Next validation order: `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, then T05R suggested tests.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test -p editor-core-diff-view --test projection_unified`, and `cargo test -p editor-core-diff-view`.
- Updated `TODO.md` to mark `T05R` as `[DONE]` with completion notes; no `PLAN.md` update needed because phase sequencing did not change.
- Git inspection before commit showed intended changes in `TODO.md` and this plan file, plus unrelated untracked `notification.sh` and `run_agent.sh` left untouched.
