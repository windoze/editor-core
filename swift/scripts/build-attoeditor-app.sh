#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="AttoEditor"
CLI_NAME="atto"
OUT_DIR="${ROOT_DIR}/.build/app-dist"
CONFIGURATION="release"
VERSION=""
BUILD_NUMBER=""

usage() {
  cat <<'EOF'
用法：
  scripts/build-attoeditor-app.sh [--debug|--release] [--out <dir>]

说明：
  - 先用 SwiftPM 构建 AttoEditor + atto（会自动触发 Rust build plugin）
  - 再把可执行文件打包为 macOS .app bundle（Info.plist + AppIcon.icns）
  - 额外把 CLI `atto` 放入：AttoEditor.app/Contents/MacOS/atto
  - CFBundleShortVersionString 默认从仓库根 Cargo.toml 的
    `[workspace.package] version` 读取，避免版本号两处手工同步
  - 默认输出到：.build/app-dist/AttoEditor.app

选项：
  --debug | --release   构建配置（默认 release）
  --out <dir>           输出目录
  --version <X.Y.Z>     覆盖 CFBundleShortVersionString
  --build <N>           覆盖 CFBundleVersion

示例：
  scripts/build-attoeditor-app.sh
  scripts/build-attoeditor-app.sh --out /tmp
  scripts/build-attoeditor-app.sh --debug
  scripts/build-attoeditor-app.sh --version 0.5.0 --build 42
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
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
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
swift build -c "${CONFIGURATION}" --product "${CLI_NAME}"

BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: 找不到可执行文件：${BIN_PATH}" 1>&2
  exit 1
fi
CLI_PATH="${BIN_DIR}/${CLI_NAME}"
if [[ ! -x "${CLI_PATH}" ]]; then
  echo "error: 找不到 CLI 可执行文件：${CLI_PATH}" 1>&2
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

cp -f "${CLI_PATH}" "${CONTENTS}/MacOS/${CLI_NAME}"
chmod +x "${CONTENTS}/MacOS/${CLI_NAME}"

cp -f "${PLIST_SRC}" "${CONTENTS}/Info.plist"

# 版本号：单一来源是仓库根 Cargo.toml 的 `[workspace.package] version`。
# Info.plist 模板里的值只作为兜底（读不到 Cargo.toml 时）。
#
# 只取 `[workspace.package]` 段内第一个 `version = "..."`，避免误抓
# `[workspace.dependencies]` 里各依赖的 version。
workspace_version() {
  local cargo_toml="${ROOT_DIR}/../Cargo.toml"
  [[ -f "${cargo_toml}" ]] || return 0
  awk '
    /^\[/ { in_section = ($0 == "[workspace.package]") }
    in_section && /^[[:space:]]*version[[:space:]]*=/ {
      if (match($0, /"[^"]+"/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ' "${cargo_toml}"
}

if [[ -z "${VERSION}" ]]; then
  VERSION="$(workspace_version)"
  if [[ -n "${VERSION}" ]]; then
    echo "版本号取自 Cargo.toml [workspace.package]：${VERSION}"
  else
    echo "warning: 未能从 Cargo.toml 读到 workspace 版本号；沿用 Info.plist 模板值" 1>&2
  fi
fi

if [[ -n "${VERSION}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS}/Info.plist"
fi
if [[ -n "${BUILD_NUMBER}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS}/Info.plist"
fi

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

EFFECTIVE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CONTENTS}/Info.plist")"
EFFECTIVE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${CONTENTS}/Info.plist")"

echo "已生成：${APP_PATH} (版本 ${EFFECTIVE_VERSION}, build ${EFFECTIVE_BUILD})"
