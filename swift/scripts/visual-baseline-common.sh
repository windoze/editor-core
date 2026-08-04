#!/usr/bin/env bash

atto_visual_swift_test_args=()

atto_visual_configure_swiftpm_args() {
  atto_visual_swift_test_args=()

  if [[ "${ATTO_VISUAL_SWIFTPM_DISABLE_SANDBOX:-}" == "1" ]]; then
    atto_visual_swift_test_args+=(--disable-sandbox)
  fi

  if [[ -n "${ATTO_VISUAL_SWIFTPM_MANIFEST_CACHE:-}" ]]; then
    atto_visual_swift_test_args+=(--manifest-cache "$ATTO_VISUAL_SWIFTPM_MANIFEST_CACHE")
  fi
  if [[ -n "${ATTO_VISUAL_SWIFTPM_CACHE_PATH:-}" ]]; then
    atto_visual_swift_test_args+=(--cache-path "$ATTO_VISUAL_SWIFTPM_CACHE_PATH")
  fi
  if [[ -n "${ATTO_VISUAL_SWIFTPM_CONFIG_PATH:-}" ]]; then
    atto_visual_swift_test_args+=(--config-path "$ATTO_VISUAL_SWIFTPM_CONFIG_PATH")
  fi
  if [[ -n "${ATTO_VISUAL_SWIFTPM_SECURITY_PATH:-}" ]]; then
    atto_visual_swift_test_args+=(--security-path "$ATTO_VISUAL_SWIFTPM_SECURITY_PATH")
  fi
  if [[ -n "${ATTO_VISUAL_SWIFTPM_SCRATCH_PATH:-}" ]]; then
    atto_visual_swift_test_args+=(--scratch-path "$ATTO_VISUAL_SWIFTPM_SCRATCH_PATH")
  fi
}

atto_visual_run_manifest_tests() {
  if ((${#atto_visual_swift_test_args[@]} > 0)); then
    swift test \
      "${atto_visual_swift_test_args[@]}" \
      --package-path swift \
      --filter 'AttoEditorVisualBaselineManifestTests'
  else
    swift test \
      --package-path swift \
      --filter 'AttoEditorVisualBaselineManifestTests'
  fi
}
