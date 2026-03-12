#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="AttoEditor"
OUT_DIR="${ROOT_DIR}/.build/app-dist"
CONFIGURATION="release"

usage() {
  cat <<'EOF'
用法：
  scripts/build-attoeditor-app.sh [--debug|--release] [--out <dir>]

说明：
  - 先用 SwiftPM 构建 AttoEditor（会自动触发 Rust build plugin）
  - 再把可执行文件打包为 macOS .app bundle（Info.plist + AppIcon.icns）
  - 默认输出到：.build/app-dist/AttoEditor.app

示例：
  scripts/build-attoeditor-app.sh
  scripts/build-attoeditor-app.sh --out /tmp
  scripts/build-attoeditor-app.sh --debug
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" 1>&2
      usage 1>&2
      exit 2
      ;;
  esac
done

swift build -c "${CONFIGURATION}" --product "${APP_NAME}"

BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: 找不到可执行文件：${BIN_PATH}" 1>&2
  exit 1
fi

TEMPLATE_DIR="Sources/AttoEditor/AppBundle"
PLIST_SRC="${TEMPLATE_DIR}/Info.plist"
ICON_SRC="${TEMPLATE_DIR}/AppIcon.icns"

if [[ ! -f "${PLIST_SRC}" ]]; then
  echo "error: 缺少 Info.plist 模板：${PLIST_SRC}" 1>&2
  exit 1
fi

APP_PATH="${OUT_DIR}/${APP_NAME}.app"
CONTENTS="${APP_PATH}/Contents"

rm -rf "${APP_PATH}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp -f "${BIN_PATH}" "${CONTENTS}/MacOS/${APP_NAME}"
chmod +x "${CONTENTS}/MacOS/${APP_NAME}"

cp -f "${PLIST_SRC}" "${CONTENTS}/Info.plist"

if [[ -f "${ICON_SRC}" ]]; then
  cp -f "${ICON_SRC}" "${CONTENTS}/Resources/AppIcon.icns"
fi

# SwiftPM resources: copy target resource bundles so `Bundle.module` works in the packaged .app.
#
# Notes:
# - SwiftPM emits one `.bundle` per target that has resources.
# - Bundle names are not part of a strict public API, so we copy any bundle that matches `*AttoEditor*.bundle`.
#
# This is required for AttoEditor built-in themes shipped as JSON resources.
mapfile -t RESOURCE_BUNDLES < <(find "${BIN_DIR}" -maxdepth 1 -name "*AttoEditor*.bundle" -print 2>/dev/null || true)
if [[ ${#RESOURCE_BUNDLES[@]} -gt 0 ]]; then
  for b in "${RESOURCE_BUNDLES[@]}"; do
    cp -R "${b}" "${CONTENTS}/Resources/"
  done
else
  echo "warning: 未找到 AttoEditor 资源 bundle（*.bundle）；Bundle.module 资源可能不可用" 1>&2
fi

echo "已生成：${APP_PATH}"
