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

## Current Invocation Plan

1. Read `TODO.md` and identify the first task whose heading is not prefixed with `[DONE]`.
2. Check the latest commit only for unfinished work directly relevant to that selected task.
3. Inspect the selected task body, dependencies, touched files, and validation requirements; update this file with a task-specific plan once the task is known.
4. Implement the selected task completely, or add the minimum prerequisite task if a concrete blocker prevents correct implementation.
5. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, targeted tests, and any required broader validation.
6. Update `TODO.md` completion state and record validation; update `PLAN.md` only if phase-level sequencing changes.
7. Inspect git status, diff, and recent log, commit the intended changes with a task-specific message, then stop.

## T19FF Invocation Plan

1. Selected task: `T19FF 修复：统一 DeltaCalculator 越界 line clamp 语义`.
2. Check the latest commit for unfinished work directly relevant to T19FF.
3. Inspect `crates/editor-core-lsp/src/lsp_sync.rs` and the existing UTF-16 boundary tests.
4. Update `DeltaCalculator::apply_change` so any out-of-bounds LSP line clamps to the calculator document end before character handling, matching the shared LSP coordinate policy.
5. Preserve existing behavior for legal positions and the surrogate-pair middle clamp-to-scalar-start policy.
6. Add focused regressions for out-of-bounds line plus `character = 0`, out-of-bounds line plus huge character, reversed ranges, and half-surrogate behavior.
7. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, and `cargo test -p editor-core-lsp`.
8. Mark T19FF `[DONE]`, record validation, inspect git status/diff/log, commit the intended changes, and stop.

## T19FF Progress Updates

- Read `TODO.md`; the first incomplete task is `T19FF 修复：统一 DeltaCalculator 越界 line clamp 语义`.
- Latest commit is `[T19FR] Review LSP boundary follow-up`; its relevant follow-up is already represented by `T19FF`.
- Implemented the `DeltaCalculator::apply_change` line-position clamp so any LSP line beyond the current calculator document maps to document end before range normalization.
- Added UTF-16 boundary regressions for out-of-bounds line plus zero character, out-of-bounds line plus huge character, reversed ranges, and half-surrogate replacement behavior.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, `cargo test -p editor-core-lsp`, and `cargo test --all --all-targets`.
- No fixture runner was found at `tools/run_fixtures.py` or `tools/**/*fixture*`.
- Marked T19FF as `[DONE]` in `TODO.md` with completion details.
- Committed T19FF changes as `2f04c9e [T19FF] Fix DeltaCalculator line clamp`.

## T19FFR Review Invocation Plan

1. Read `TODO.md` and select the first heading without `[DONE]`.
2. Check the latest commit for unfinished work directly relevant to the selected task.
3. Review the T19FF diff against the T19FFR checklist: out-of-bounds line clamp to document end, legal range / huge character / reversed range behavior, workspace edit synchronization consistency, half-surrogate policy preservation, and regression coverage.
4. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, and `cargo test -p editor-core-lsp`.
5. If findings require follow-up, add the minimum task(s) before the dependent next task in `TODO.md`; otherwise mark T19FFR `[DONE]` directly.
6. Commit the review bookkeeping and stop.

## T19FFR Progress Updates

- Read `TODO.md`; the first incomplete task is `T19FFR Review：审查 DeltaCalculator 越界 line clamp 修复`.
- Latest commits are `[T19FF] Fix DeltaCalculator line clamp` and `[T19FF] Record execution completion`; neither introduced a separate unfinished issue beyond this review task.
- Reviewed the T19FF scoped diff in `crates/editor-core-lsp/src/lsp_sync.rs` and `crates/editor-core-lsp/tests/utf16_boundaries.rs`.
- No blocking review finding was found: `DeltaCalculator::apply_change` maps any line beyond the calculator document to document end before range normalization, legal lines still use `LspCoordinateConverter::lsp_to_char_offset`, half-surrogate offsets still clamp to the scalar start, and workspace edit didChange ranges are regenerated from legal char offsets.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test -p editor-core-lsp --test utf16_boundaries`, and `cargo test -p editor-core-lsp`.
- Marked T19FFR as `[DONE]` in `TODO.md` with completion details.

## T20 Invocation Plan

### Scope

- Work from `TODO.md` as the authoritative task source.
- Complete exactly the first incomplete task, then stop.
- Keep `TODO.md` completion state explicit by adding `[DONE]` to the completed task title only after implementation and required validation pass.
- Update `PLAN.md` only if phase-level sequencing, dependencies, assumptions, or completion criteria change.

### Execution Plan

1. Read `TODO.md` and identify the first task whose title is not prefixed with `[DONE]`.
2. Check the latest commit message only for an explicitly unfinished issue directly relevant to that task.
3. Read the selected task details, dependencies, validation requirements, and any relevant project context.
4. Inspect the minimal code/docs/tests needed for that task.
5. Implement the task fully, or if a concrete blocker makes correct implementation impossible, update `TODO.md` with the minimum prerequisite task and stop after committing.
6. Run formatting first, then linting, then targeted tests, then full tests if code changes require them.
7. Address any failing test or fixture unless it is already explicitly scheduled later.
8. Update `TODO.md` with `[DONE]` and a completion record after validation.
9. Commit all relevant changes with a descriptive task-scoped commit message.
10. Stop without starting the next task.

### Progress Log

- Started: Created this plan before inspecting project task state.
- Selected task: `T20 实现：文档清理和实现一致性修正` is the first incomplete task in `TODO.md`.
- Latest commit check: `b4c653d [T19FFR] Review DeltaCalculator line clamp`; no explicit unfinished issue in the latest commit message that changes T20 scope.
- Next step: inspect only T20 scope files (`docs/DESIGN.md`, `docs/abi-v1-draft.md`, `crates/editor-core/src/lib.rs`) and apply focused documentation corrections.
- Edited docs: updated `DESIGN.md` LineIndex/folding/Unicode limitation text, `lib.rs` feature and Unicode summaries, and `abi-v1-draft.md` handle/threading/output-buffer contracts.
- Validation: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, and `cargo test -p editor-core --doc` all passed.
- Completion record: marked T20 as `[DONE]` in `TODO.md` with a task-scoped completion record.

## T20R Review Invocation Plan

1. Read `TODO.md` and select the first heading without `[DONE]`.
2. Check the latest commit for unfinished work directly relevant to the selected task.
3. Review the T20 diff against the T20R checklist: current-state documentation, complexity claims, grapheme/word/scalar boundary clarity, ABI calling contract clarity, and doc example validity.
4. Inspect only the relevant T20 scope docs and minimal source context needed to confirm the documentation claims.
5. Run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, and `cargo test -p editor-core --doc`.
6. If findings require follow-up, add the minimum task(s) before the dependent next task in `TODO.md`; otherwise mark T20R `[DONE]` directly.
7. Commit the review bookkeeping and stop without starting the next task.

## T20R Progress Updates

- Read `TODO.md`; the first incomplete task is `T20R Review：审查文档一致性修正`.
- Latest commit is `[T20] Fix documentation consistency`, directly relevant to T20R and containing no separate unfinished issue in the commit title.
- Reviewed the T20-scoped diffs in `docs/DESIGN.md`, `docs/abi-v1-draft.md`, `crates/editor-core/src/lib.rs`, and minimal source context in `model.rs`, `cursor_ops.rs`, and `edit_ops.rs`.
- Found follow-up documentation issues: `docs/DESIGN.md` still describes `PieceTable` as the high-level storage/edit path, still says edit commands update the piece table and rebuild the rope, still frames grapheme-aware cursor movement as a non-goal despite dedicated grapheme commands, and still points `UndoRedoManager` to the old `commands.rs` location.
- A directed check found matching stale PieceTable main-path text in `docs/DESIGN.zh.md`; added `T20F` and `T20FR` before `T21` in `TODO.md` to repair the English and Chinese design docs before continuing.
- Marked `T20R` as `[DONE]` and recorded the review findings and validation results in `TODO.md`.
- Validation passed: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, and `cargo test -p editor-core --doc`.
