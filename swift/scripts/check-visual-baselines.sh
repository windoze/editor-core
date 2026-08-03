#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$SWIFT_DIR/.." && pwd)"

BASELINE_ROOT="${ATTO_VISUAL_BASELINE_DIR:-"$SWIFT_DIR/Tests/AttoEditorTests/Resources"}"
ARTIFACT_DIR="${ATTO_VISUAL_ARTIFACT_DIR:-"$REPO_ROOT/target/atto-visual-artifacts"}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline-root)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --baseline-root\n' >&2
        exit 2
      fi
      BASELINE_ROOT="$2"
      shift 2
      ;;
    --artifact-dir)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --artifact-dir\n' >&2
        exit 2
      fi
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      printf 'Usage: %s [--baseline-root DIR] [--artifact-dir DIR]\n' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$ARTIFACT_DIR"

cd "$REPO_ROOT"

ATTO_VISUAL_BASELINE_DIR="$BASELINE_ROOT" \
ATTO_VISUAL_ARTIFACT_DIR="$ARTIFACT_DIR" \
swift test --package-path swift --filter 'AttoEditorVisualBaselineManifestTests'

printf 'Compared visual baselines under %s\n' "$BASELINE_ROOT"
printf 'Wrote visual review artifacts under %s\n' "$ARTIFACT_DIR"
