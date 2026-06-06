## Execution Plan

Status: T21A completed; awaiting commit.

1. Inspect `TODO.md` and identify the first task whose title is not prefixed with `[DONE]`.
2. Check the latest commit message only for unfinished work directly relevant to that task.
3. Read the selected task details, dependencies, validation requirements, and nearby context in `TODO.md`.
4. Implement the selected task exactly as written, without changing scope or using workarounds.
5. If a concrete blocker prevents correct implementation, update `TODO.md` with the minimum prerequisite task, keep the current task incomplete, commit that bookkeeping, and stop.
6. Run required formatting, linting, targeted tests, and then broader validation as required by the task and repository policy.
7. If unscheduled test or fixture failures appear, fix them or schedule the minimum prerequisite/follow-up task before marking the current task done.
8. Mark the completed task title in `TODO.md` with `[DONE]` and update its completion record with implementation and validation notes.
9. Commit all relevant changes with a descriptive message for the completed task, then stop without starting the next task.

Progress Log:
- Created initial execution plan before reading project files or running commands.
- Identified first incomplete task in `TODO.md`: `T21A 实现：editor-core-app panic 与错误处理专项`.
- Next step: check the latest commit for unfinished work directly relevant to T21A, then inspect only the task-scoped `editor-core-app` files and existing tests.
- Latest commit is `7ff08a5 [T21UFR] Review UI LSP processing error handling`; it does not add a separate unfinished app issue beyond the already scheduled T21A.
- Classified the task-cited `rg --count-matches "unwrap\(|expect\(|panic!" crates/editor-core-app/src` results. The direct matches are all inside `#[cfg(test)]` modules; production code has no direct `unwrap()`, `expect()`, or `panic!` match.
- Implementation focus: remove remaining recoverable production panic risk from session restore direct indexing by using checked access and returning `AppSessionError::InvalidSnapshot`, then add targeted app tests.
- Implemented T21A fixes: `SettingsStore::reload_if_changed` now returns metadata/read errors instead of silently reporting no change; `HotExitSnapshot::restore` uses checked per-view snapshot access and clamps restored primary selection against the actual recovered selection list.
- Added targeted app tests for missing settings file reload, invalid hot-exit `buffer_index`, and empty selection snapshot primary-index clamp.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-app`, `cargo clippy --all-targets --all-features -- -D warnings`, and `cargo test --all --all-targets`.
- Checked for fixture runners with `tools/run_fixtures.py` and `tools/**/*fixture*`; none were present.
- Marked `T21A` as `[DONE]` in `TODO.md` and recorded implementation/validation notes.
