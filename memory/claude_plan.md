# Execution Plan

This file records an operational plan and progress updates for the current invocation. It does not include private chain-of-thought.

## Initial Plan

1. Read `TODO.md` and identify the first task whose heading is not prefixed with `[DONE]`.
2. Check the latest commit only for unfinished work that is directly relevant to that selected task.
3. Read the selected task requirements, dependencies, and validation requirements; update this file with the concrete task plan.
4. Implement the selected task completely, unless a concrete prerequisite blocker must be added to `TODO.md` first.
5. Run formatting, linting, targeted tests, and required broader validation according to the task and repository policy.
6. Update `TODO.md` by prefixing the completed task title with `[DONE]` and filling in its completion record; update `PLAN.md` only if phase-level sequencing changes.
7. Inspect git status/diff/log, commit all intended changes with a clear task-specific message, then stop without starting the next task.

## Progress

- Started invocation and created the execution plan record.
- Read `TODO.md`; the first incomplete task is `T19 实现：LSP UTF-16 代理对边界修正`.

## Concrete T19 Plan

1. Check the latest commit message for unfinished work directly relevant to T19.
2. Inspect only the T19 scope files and known conversion entry points in `editor-core-lsp`.
3. Include the additional duplicate LSP coordinate entry files discovered by directed search: `lsp_events.rs`, `lsp_text_edits.rs`, `lsp_completion.rs`, `lsp_hover.rs`, `lsp_locations.rs`, `lsp_symbols.rs`, `lsp_highlights.rs`, `lsp_decorations.rs`, `lsp_call_hierarchy.rs`, and `lsp_type_hierarchy.rs`.
4. Implement a single, documented UTF-16 boundary policy: malformed offsets inside a surrogate pair clamp to the scalar's start boundary; oversized characters clamp to the line end.
5. Ensure diagnostics, semantic tokens, text edits, symbols, highlights, and decorations use the same conversion path, avoiding unchecked narrowing at LSP coordinate boundaries.
6. Add focused regression coverage for `a👋b`, malformed half-surrogate diagnostics ranges, oversized `u32::MAX` characters, and semantic token consistency.
7. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, `cargo test -p editor-core-lsp --test diagnostics_processing_edits`, and `cargo test -p editor-core-lsp`; then run broader validation if code changes warrant it.
8. Mark T19 `[DONE]` with a completion record, inspect git status/diff/log, commit the intended changes, and stop.

## Progress Updates

- Latest commit is `[T18R] Review folding visual mapping fix`; no directly relevant unfinished T19 issue was mentioned.
- Added a T19 execution note in `TODO.md` for the extra duplicate LSP position parsing / coordinate entry files required by the unified conversion policy.
- Implemented the central UTF-16 conversion policy in `LspCoordinateConverter`, added saturating LSP position parsing, and routed diagnostics/semantic token/text edit/symbol/highlight/decoration/hierarchy parsing through the shared helpers.
- Added `utf16_boundaries.rs` coverage for `a👋b`, half-surrogate diagnostics, oversized character/line clamp, and semantic token boundary consistency.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, `cargo test -p editor-core-lsp --test diagnostics_processing_edits`, `cargo test -p editor-core-lsp`, `cargo clippy --all-targets --all-features -- -D warnings`, and `cargo test --all --all-targets`.
- No fixture runner was found at `tools/run_fixtures.py` or `tools/**/*fixture*`.
- Marked T19 as `[DONE]` in `TODO.md` with completion details. Next step is git inspection and commit.
