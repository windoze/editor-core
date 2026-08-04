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

# Rust staticlib 必须先在仓库根目录构建，不能交给 SwiftPM build plugin。
#
# 原因：`editor-core-ui-ffi` 依赖 skia-safe，skia-bindings 的 build.rs 需要联网
# （下载 skia-binaries 预编译包或 skia 源码），而 SwiftPM 的 plugin sandbox 禁止
# 网络访问。所以 plugin 对 CEditorCoreUIFFI 只做“复制已构建好的 .a”，找不到
# 或发现过期就直接报错。
#
# 这里在 sandbox 之外先跑 cargo，plugin 随后复用产物。
#
# 注意：plugin 的新鲜度检查比较 .a 与 .rs 的 mtime，且要求 .a 不旧于源码；
# 它优先取 target/debug，其次 target/release，所以两种配置都构建到对应目录。
CARGO_PROFILE_ARGS=()
CARGO_OUT_SUBDIR="debug"
if [[ "${CONFIGURATION}" == "release" ]]; then
  CARGO_PROFILE_ARGS=(--release)
  CARGO_OUT_SUBDIR="release"
fi

echo "==> 构建 Rust staticlib（在 SwiftPM plugin sandbox 之外，需要联网构建 Skia）"
(
  cd "${ROOT_DIR}/.."
  # macOS 自带 bash 3.2 在 `set -u` 下展开空数组会报 unbound variable
  # （debug 构建时 CARGO_PROFILE_ARGS 为空），故用 ${arr[@]+...} 形式。
  cargo build -p editor-core-ffi -p editor-core-ui-ffi ${CARGO_PROFILE_ARGS[@]+"${CARGO_PROFILE_ARGS[@]}"}
)

RUST_LIB_DIR="${ROOT_DIR}/../target/${CARGO_OUT_SUBDIR}"
RUST_LIB="${RUST_LIB_DIR}/libeditor_core_ui_ffi.a"
if [[ ! -f "${RUST_LIB}" ]]; then
  echo "error: cargo 构建后仍找不到 ${RUST_LIB}" 1>&2
  exit 1
fi

# plugin 的新鲜度检查是「.a 的 mtime 不得早于任何 .rs 的 mtime」。
# cargo 判定无需重建时不会重新链接，.a 会保留旧 mtime；而 git checkout /
# 缓存恢复后 .rs 往往带更新的 mtime —— 两者叠加会让 plugin 误判「已过期」而报错。
#
# 此刻 cargo 刚成功返回，即已确认 .a 与源码一致，因此显式 touch 是准确的。
touch "${RUST_LIB}" "${RUST_LIB_DIR}/libeditor_core_ffi.a" 2>/dev/null || true

# plugin 优先取 target/debug、其次 target/release，两边都存在时会选 debug。
# 构建 release .app 时如果 target/debug 里躺着一个更新的 .a，就会静默链接
# 到 debug 产物。这里把非当前配置的那个挪开，避免拿错。
if [[ "${CARGO_OUT_SUBDIR}" == "release" ]]; then
  OTHER_LIB="${ROOT_DIR}/../target/debug/libeditor_core_ui_ffi.a"
  if [[ -f "${OTHER_LIB}" ]]; then
    echo "note: 为避免 plugin 误选 debug 产物，暂时移开 target/debug/libeditor_core_ui_ffi.a"
    mv -f "${OTHER_LIB}" "${OTHER_LIB}.aside"
    # shellcheck disable=SC2064
    trap "mv -f '${OTHER_LIB}.aside' '${OTHER_LIB}' 2>/dev/null || true" EXIT
  fi
fi

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
#
# 注意：不要用 `mapfile`/`readarray` —— 那是 bash 4+ 的内建命令，而 macOS 自带的
# /bin/bash 仍是 3.2（GitHub runner 上就是它），会直接 `command not found`。
RESOURCE_BUNDLE_COUNT=0
while IFS= read -r bundle; do
  [[ -n "${bundle}" ]] || continue
  cp -R "${bundle}" "${CONTENTS}/Resources/"
  RESOURCE_BUNDLE_COUNT=$((RESOURCE_BUNDLE_COUNT + 1))
done < <(find "${BIN_DIR}" -maxdepth 1 -name "*AttoEditor*.bundle" -print 2>/dev/null || true)

if [[ "${RESOURCE_BUNDLE_COUNT}" -eq 0 ]]; then
  echo "warning: 未找到 AttoEditor 资源 bundle（*.bundle）；Bundle.module 资源可能不可用" 1>&2
fi

EFFECTIVE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CONTENTS}/Info.plist")"
EFFECTIVE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${CONTENTS}/Info.plist")"

echo "已生成：${APP_PATH} (版本 ${EFFECTIVE_VERSION}, build ${EFFECTIVE_BUILD})"
