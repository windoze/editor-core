# Visual Baseline Policy

`manifest.json` is the source of truth for visual baseline cases. Each case declares a fixture, fixed window size, scale, theme, tolerance, artifact name, and the checked-in PNG path expected by strict baseline verification.

## Review Modes

- Smoke mode: run `swift test --package-path swift --filter 'AttoEditorVisualBaselineManifestTests'` without `ATTO_VISUAL_BASELINE_DIR`. This captures review artifacts and validates that every manifest case is runnable, but it does not require checked-in PNGs.
- Record mode: run `swift/scripts/update-visual-baselines.sh`. This writes PNGs under `swift/Tests/AttoEditorTests/Resources/VisualBaselines/` and review artifacts under `target/atto-visual-artifacts/` by default.
- Strict mode: run `swift/scripts/check-visual-baselines.sh`. This sets `ATTO_VISUAL_BASELINE_DIR` and fails if any checked-in PNG baseline is missing or outside the manifest tolerance.

## Golden PNG Rules

- Only commit PNGs generated from a pinned macOS runner or an explicitly approved baseline machine. Developer-laptop PNGs are review artifacts unless the PR states why that machine is the approved baseline source.
- Keep `scale` fixed at `1.0` unless the manifest case is explicitly testing a different backing scale.
- Keep font choices deterministic. Prefer bundled/system monospace fonts already declared in the manifest case, and update this policy before adding machine-specific fonts.
- When changing UI layout, commit the product/test change and the regenerated PNGs together. The PR must include the command used to regenerate baselines and the strict check command.
- When changing only test harness code, do not regenerate PNGs unless the rendered pixels intentionally change.

## CI Policy

`.github/workflows/visual-baselines.yml` provides the CI entry point:

- Pull requests that touch visual baseline resources or harness files run smoke mode on a pinned macOS runner and upload review artifacts.
- Manual workflow runs support `mode=smoke` for artifact review and `mode=strict` for checked-in PNG comparison.
- Every workflow run records `environment/summary.txt`, `environment/displays.txt`, and `environment/fonts.txt` with the toolchain, display, font, render backend, and scale-factor context used for that artifact set.
- Strict mode is expected to become required after the first approved PNG baseline set is committed.
