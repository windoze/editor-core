#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$SWIFT_DIR/.." && pwd)"

BASELINE_ROOT="${ATTO_VISUAL_RECORD_BASELINE_DIR:-"$SWIFT_DIR/Tests/AttoEditorTests/Resources"}"
ARTIFACT_DIR="${ATTO_VISUAL_ARTIFACT_DIR:-"$REPO_ROOT/target/atto-visual-artifacts"}"
CONFIG_FILE="$SWIFT_DIR/.build/atto-visual-baseline-record.json"

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

escape_json_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

mkdir -p "$BASELINE_ROOT" "$ARTIFACT_DIR" "$(dirname "$CONFIG_FILE")"
trap 'rm -f "$CONFIG_FILE"' EXIT

BASELINE_ROOT_JSON="$(escape_json_string "$BASELINE_ROOT")"
ARTIFACT_DIR_JSON="$(escape_json_string "$ARTIFACT_DIR")"
printf '{\n  "recordBaselineRoot": "%s",\n  "artifactRoot": "%s"\n}\n' \
  "$BASELINE_ROOT_JSON" \
  "$ARTIFACT_DIR_JSON" > "$CONFIG_FILE"

cd "$REPO_ROOT"

swift test --package-path swift --filter 'AttoEditorVisualBaselineManifestTests'

printf 'Recorded visual baselines under %s\n' "$BASELINE_ROOT"
printf 'Wrote visual review artifacts under %s\n' "$ARTIFACT_DIR"
