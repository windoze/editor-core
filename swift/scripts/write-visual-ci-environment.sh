#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$SWIFT_DIR/.." && pwd)"

ARTIFACT_DIR="${ATTO_VISUAL_ARTIFACT_DIR:-"$REPO_ROOT/target/atto-visual-artifacts"}"
ENV_DIR="$ARTIFACT_DIR/environment"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --artifact-dir\n' >&2
        exit 2
      fi
      ARTIFACT_DIR="$2"
      ENV_DIR="$ARTIFACT_DIR/environment"
      shift 2
      ;;
    -h|--help)
      printf 'Usage: %s [--artifact-dir DIR]\n' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$ENV_DIR"

{
  printf 'Recorded at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Kernel: '
  uname -a
  printf '\n[macOS]\n'
  sw_vers || true
  printf '\n[Xcode]\n'
  xcodebuild -version || true
  printf '\n[Swift]\n'
  swift --version || true
  printf '\n[Rust]\n'
  rustc --version || true
  cargo --version || true
  printf '\n[Visual Baseline]\n'
  printf 'ATTO_VISUAL_ARTIFACT_DIR=%s\n' "$ARTIFACT_DIR"
  printf 'ATTO_VISUAL_BASELINE_DIR=%s\n' "${ATTO_VISUAL_BASELINE_DIR:-}"
  printf 'ATTO_VISUAL_RENDER_BACKEND=%s\n' "${ATTO_VISUAL_RENDER_BACKEND:-appkit-skia-metal}"
  printf 'ATTO_VISUAL_SCALE_FACTOR=%s\n' "${ATTO_VISUAL_SCALE_FACTOR:-1.0}"
} > "$ENV_DIR/summary.txt"

system_profiler SPDisplaysDataType > "$ENV_DIR/displays.txt" 2>/dev/null || true
system_profiler SPFontsDataType > "$ENV_DIR/fonts.txt" 2>/dev/null || true

printf 'Wrote visual CI environment artifacts under %s\n' "$ENV_DIR"
