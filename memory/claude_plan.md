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

## T19R Review Invocation Plan

1. Read `TODO.md` and select the first heading without `[DONE]`.
2. Check the latest commit for unfinished work directly relevant to the selected task.
3. Review the T19 diff against the T19R checklist: surrogate-pair policy consistency, unified LSP coordinate conversion, unchecked truncation risks, emoji offset correctness, and diagnostics / semantic token coverage.
4. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, `cargo test -p editor-core-lsp --test diagnostics_processing_edits`, and `cargo test -p editor-core-lsp`.
5. If findings require follow-up, add the minimum task(s) before the dependent next task in `TODO.md`; otherwise mark T19R `[DONE]` directly.
6. Commit the review bookkeeping and stop.

## T19R Progress Updates

- Read `TODO.md`; the first incomplete task is `T19R Review：审查 LSP UTF-16 边界修正`.
- Latest commit is `[T19] Fix LSP UTF-16 boundary handling`, directly relevant to T19R.
- Reviewed `LspCoordinateConverter`, diagnostics conversion, semantic token conversion, LSP range/position parsing helpers, workspace sync, signature help parsing, and `utf16_boundaries` tests.
- Found follow-up issues: `DeltaCalculator::apply_change` can still resize from untrusted LSP line values when syncing server-provided workspace edits back into the incremental calculator, and `lsp_signature_help.rs` still has unchecked `as u32` / `as usize` boundary conversions.
- Added `T19F` and `T19FR` before `T20` in `TODO.md` to schedule those fixes before continuing.
- Marked `T19R` as `[DONE]` and recorded the review findings and validation results in `TODO.md`.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, `cargo test -p editor-core-lsp --test diagnostics_processing_edits`, and `cargo test -p editor-core-lsp`.

## T19F Invocation Plan

1. Read `TODO.md` and select the first heading without `[DONE]`.
2. Check the latest commit for unfinished work directly relevant to T19F.
3. Inspect the listed files and existing tests: `lsp_sync.rs`, `workspace_sync.rs`, `lsp_signature_help.rs`, and `utf16_boundaries.rs`.
4. Fix `DeltaCalculator::apply_change` so untrusted LSP line values cannot trigger large internal resizes; use the same clamp semantics as the current LSP coordinate policy.
5. Ensure workspace edit synchronization feeds the incremental calculator with legal/clamped ranges matching the applied edit semantics.
6. Replace unchecked `as u32` / `as usize` parsing in signature help with saturating or checked handling and safe lookups.
7. Add focused regressions for oversized workspace edit ranges, unchanged legal workspace edit behavior, and oversized signatureHelp offsets/indexes.
8. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, and `cargo test -p editor-core-lsp`.
9. Mark T19F `[DONE]` with completion notes, commit all related changes, then stop.

## T19F Progress Updates

- Read `TODO.md`; the first incomplete task is `T19F 修复：收口 LSP workspace edit 与 signatureHelp 边界解析`.
- Latest commit is `[T19R] Review LSP UTF-16 boundary fix`; its relevant follow-up is already represented by `T19F`.
- Inspected the task files and confirmed current risks: `DeltaCalculator::apply_change` resizes from untrusted LSP lines, workspace edit sync returns original server ranges to the calculator, and `signatureHelp` still truncates large values with `as` casts.
- Implemented the T19F fixes and added regressions in `utf16_boundaries.rs`.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, and `cargo test -p editor-core-lsp`.
- Marked T19F as `[DONE]` in `TODO.md` with completion details. Next step is git inspection and commit.

## T19FR Review Invocation Plan

1. Read `TODO.md` and select the first heading without `[DONE]`.
2. Check the latest commit for unfinished work directly relevant to the selected task.
3. Review the T19F diff against the T19FR checklist: `DeltaCalculator::apply_change`, workspace edit calculator synchronization, signatureHelp checked parsing, T19 half-surrogate policy preservation, and regression coverage.
4. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, and `cargo test -p editor-core-lsp`.
5. If findings require follow-up, add the minimum task(s) before the dependent next task in `TODO.md`; otherwise mark T19FR `[DONE]` directly.
6. Commit the review bookkeeping and stop.

## T19FR Progress Updates

- Read `TODO.md`; the first incomplete task is `T19FR Review：审查 LSP workspace edit 与 signatureHelp 边界修复`.
- Latest commit is `[T19F] Fix LSP workspace edit boundary sync`, directly relevant to T19FR and containing no separate unfinished issue in the commit title.
- Reviewed `DeltaCalculator::apply_change`, `workspace_sync::lsp_changes_for_text_edits`, `lsp_signature_help`, shared LSP range conversion, and the `utf16_boundaries` regression additions.
- Workspace edit synchronization now regenerates didChange ranges from clamped char offsets, and signatureHelp oversized values use saturating parsing with checked active-signature lookup.
- Found a follow-up issue: `DeltaCalculator::apply_change` still clamps an out-of-bounds LSP line to the last line and then honors the original character. With `character = 0`, the edit lands at the start of the last line instead of document end, so it does not match the required unified clamp semantics.
- Added `T19FF` and `T19FFR` before `T20` in `TODO.md` to schedule that fix and review before continuing.
- Marked `T19FR` as `[DONE]` and recorded the review findings and validation results in `TODO.md`.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, and `cargo test -p editor-core-lsp`.
