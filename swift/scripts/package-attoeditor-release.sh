#!/usr/bin/env bash
set -euo pipefail

# 把 AttoEditor 打成可分发的、已签名并公证的 DMG。
#
# 流程（Apple 推荐的 inside-out 顺序）：
#   1. 调用 build-attoeditor-app.sh 构建 .app（版本号由它注入）
#   2. 读回最终版本号，决定 DMG 文件名
#   3. 由内向外签名：resource bundles -> CLI `atto` -> .app 本体
#   4. 公证 .app（通过 zip 提交）并 staple
#   5. 制作 DMG，签名 DMG
#   6. 公证 DMG 并 staple
#   7. 校验（codesign --verify / spctl / stapler validate）
#
# 本地使用（证书在登录 keychain 里）：
#   swift/scripts/package-attoeditor-release.sh --version 0.5.0 --skip-notarize
#
# 签名需要：
#   APPLE_SIGNING_IDENTITY   如 "Developer ID Application: Chen Xu (ABCDE12345)"
#
# 公证需要下面两种认证方式之一（优先用 A）。Team ID 默认从
# APPLE_SIGNING_IDENTITY 的 "(TEAMID)" 部分推导，也可用 APPLE_TEAM_ID 显式覆盖：
#
#   A. Apple ID + app-specific password（推荐：只需自己的 Apple ID，
#      密码可随时在 appleid.apple.com 单独吊销）
#        APPLE_ID                 你的 Apple ID 邮箱
#        APPLE_APP_PASSWORD       app-specific password（xxxx-xxxx-xxxx-xxxx）
#
#   B. App Store Connect API key
#        APPLE_NOTARY_KEY_PATH    私钥 .p8 的路径
#        APPLE_NOTARY_KEY_ID      该 key 的 Key ID
#        APPLE_NOTARY_ISSUER_ID   Issuer ID (UUID)；Individual key 不需要
#
# 可选：
#   APPLE_ENTITLEMENTS_PATH  自定义 entitlements plist（默认使用仓库内的 AttoEditor.entitlements）
#   KEYCHAIN_PATH            指定签名用的 keychain（CI 临时 keychain）

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="AttoEditor"
CLI_NAME="atto"
BUNDLE_ID="codes.unwritten.attoeditor"
OUT_DIR="${ROOT_DIR}/.build/release-dist"
WORK_DIR="${ROOT_DIR}/.build/release-work"
VERSION=""
BUILD_NUMBER=""
SKIP_NOTARIZE=0
SKIP_SIGN=0

usage() {
  cat <<'EOF'
用法：
  scripts/package-attoeditor-release.sh [选项]

选项：
  --version <X.Y.Z>   CFBundleShortVersionString（默认读 Cargo.toml 的 workspace 版本）
  --build <N>         CFBundleVersion（默认沿用 Info.plist 模板里的值）
  --out <dir>         产物输出目录（默认 .build/release-dist）
  --skip-notarize     只签名，不做公证 / stapling（本地验证签名时用）
  --skip-sign         完全不签名（只想看 DMG 打包结果时用）
  -h, --help          显示帮助

产物：
  <out>/AttoEditor-<version>.dmg
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD_NUMBER="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-sign) SKIP_SIGN=1; SKIP_NOTARIZE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" 1>&2; usage 1>&2; exit 2 ;;
  esac
done

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: 缺少环境变量 ${name}" 1>&2
    exit 1
  fi
}

if [[ "${SKIP_SIGN}" -eq 0 ]]; then
  require_env APPLE_SIGNING_IDENTITY
fi

# Team ID 就在签名 identity 的括号里，例如
#   "Developer ID Application: CHEN XU (T872HYBE3E)" -> T872HYBE3E
# 所以默认从 identity 推导，不必额外配一个 secret。
if [[ -z "${APPLE_TEAM_ID:-}" && -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  if [[ "${APPLE_SIGNING_IDENTITY}" =~ \(([A-Z0-9]{10})\)[[:space:]]*$ ]]; then
    APPLE_TEAM_ID="${BASH_REMATCH[1]}"
    echo "Team ID 取自签名 identity：${APPLE_TEAM_ID}"
  fi
fi

# 公证的认证方式：Apple ID + app-specific password 优先，其次 API key。
NOTARY_AUTH=""
if [[ "${SKIP_NOTARIZE}" -eq 0 ]]; then
  if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
    echo "error: 无法确定 Team ID；请设置 APPLE_TEAM_ID，" 1>&2
    echo "  或让 APPLE_SIGNING_IDENTITY 保持 \"... (TEAMID)\" 的完整形式。" 1>&2
    exit 1
  fi
  if [[ -n "${APPLE_ID:-}" || -n "${APPLE_APP_PASSWORD:-}" ]]; then
    require_env APPLE_ID
    require_env APPLE_APP_PASSWORD
    NOTARY_AUTH="apple-id"
  elif [[ -n "${APPLE_NOTARY_KEY_PATH:-}" ]]; then
    require_env APPLE_NOTARY_KEY_ID
    NOTARY_AUTH="api-key"
  else
    echo "error: 公证需要认证信息，请二选一：" 1>&2
    echo "  A. APPLE_ID + APPLE_APP_PASSWORD" 1>&2
    echo "  B. APPLE_NOTARY_KEY_PATH + APPLE_NOTARY_KEY_ID (+ APPLE_NOTARY_ISSUER_ID)" 1>&2
    echo "或加 --skip-notarize 跳过公证。" 1>&2
    exit 1
  fi
fi

# ---------------------------------------------------------------- 1. 构建 .app

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${OUT_DIR}"

STAGE_DIR="${WORK_DIR}/stage"
mkdir -p "${STAGE_DIR}"

echo "==> 构建 ${APP_NAME}.app"
# 版本号注入交给 build 脚本：不传 --version 时它会读 Cargo.toml
# 的 `[workspace.package] version`。
BUILD_ARGS=(--release --out "${STAGE_DIR}")
if [[ -n "${VERSION}" ]]; then
  BUILD_ARGS+=(--version "${VERSION}")
fi
if [[ -n "${BUILD_NUMBER}" ]]; then
  BUILD_ARGS+=(--build "${BUILD_NUMBER}")
fi

"${ROOT_DIR}/scripts/build-attoeditor-app.sh" "${BUILD_ARGS[@]}"

APP_PATH="${STAGE_DIR}/${APP_NAME}.app"
PLIST="${APP_PATH}/Contents/Info.plist"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: 构建产物不存在：${APP_PATH}" 1>&2
  exit 1
fi

# ------------------------------------------------------- 2. 确认最终版本号

EFFECTIVE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")"
if [[ -z "${EFFECTIVE_VERSION}" ]]; then
  echo "error: Info.plist 里没有 CFBundleShortVersionString" 1>&2
  exit 1
fi
echo "==> 发布版本：${EFFECTIVE_VERSION}"
DMG_PATH="${OUT_DIR}/${APP_NAME}-${EFFECTIVE_VERSION}.dmg"

# --------------------------------------------------------------- 3. 签名 .app

# codesign / hdiutil 在 CI 临时 keychain 场景下需要显式 --keychain。
CODESIGN_KEYCHAIN_ARGS=()
if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
  CODESIGN_KEYCHAIN_ARGS=(--keychain "${KEYCHAIN_PATH}")
fi

ENTITLEMENTS="${APPLE_ENTITLEMENTS_PATH:-${ROOT_DIR}/Sources/AttoEditor/AppBundle/AttoEditor.entitlements}"

# keychain 里可能存在同名证书的多份拷贝（例如续期后旧证书没删），此时按名字
# 签名会失败：`... : ambiguous (matches ... and ...)`。
# 解析成唯一的 SHA-1 指纹再传给 codesign 可以规避。
if [[ "${SKIP_SIGN}" -eq 0 && ! "${APPLE_SIGNING_IDENTITY}" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  mapfile -t IDENTITY_HASHES < <(
    security find-identity -v -p codesigning ${KEYCHAIN_PATH:+"${KEYCHAIN_PATH}"} 2>/dev/null \
      | awk -v want="${APPLE_SIGNING_IDENTITY}" 'index($0, want) { print $2 }'
  )
  if [[ "${#IDENTITY_HASHES[@]}" -gt 1 ]]; then
    echo "note: identity \"${APPLE_SIGNING_IDENTITY}\" 在 keychain 里有 ${#IDENTITY_HASHES[@]} 份匹配，"
    echo "      改用指纹 ${IDENTITY_HASHES[0]} 以消除歧义。"
    APPLE_SIGNING_IDENTITY="${IDENTITY_HASHES[0]}"
  elif [[ "${#IDENTITY_HASHES[@]}" -eq 1 ]]; then
    APPLE_SIGNING_IDENTITY="${IDENTITY_HASHES[0]}"
  fi
fi

sign() {
  local target="$1"
  shift
  codesign --force --timestamp --options runtime \
    "${CODESIGN_KEYCHAIN_ARGS[@]}" \
    --sign "${APPLE_SIGNING_IDENTITY}" \
    "$@" \
    "${target}"
}

if [[ "${SKIP_SIGN}" -eq 0 ]]; then
  echo "==> 签名（inside-out）：identity = ${APPLE_SIGNING_IDENTITY}"

  # 3a. 嵌套的 resource bundles（SwiftPM 的 *.bundle）
  #
  # 注意：SwiftPM 对“只有资源、没有代码”的 target 生成的是**扁平** bundle
  # （目录里直接放资源，没有 Info.plist / Contents/），codesign 会拒绝：
  #   "bundle format unrecognized, invalid, or unsuitable"
  # 这类纯数据 bundle 不需要独立签名——签 .app 时它们会被收进
  # Contents/_CodeSignature/CodeResources 的封印里，一样受篡改保护。
  # 只有结构完整的 bundle（带 Info.plist，可能含代码）才需要单独先签。
  while IFS= read -r -d '' nested; do
    rel="${nested#${APP_PATH}/}"
    if [[ -f "${nested}/Contents/Info.plist" || -f "${nested}/Info.plist" ]]; then
      echo "    signing bundle: ${rel}"
      sign "${nested}"
    else
      echo "    skipping flat resource bundle (由 .app 封印覆盖): ${rel}"
    fi
  done < <(find "${APP_PATH}/Contents/Resources" -maxdepth 1 -name '*.bundle' -print0 2>/dev/null || true)

  # 3b. 嵌套的可执行文件（CLI `atto`）——必须在 .app 本体之前签
  echo "    signing nested executable: ${CLI_NAME}"
  sign "${APP_PATH}/Contents/MacOS/${CLI_NAME}" --entitlements "${ENTITLEMENTS}"

  # 3c. .app 本体
  echo "    signing app bundle: ${APP_NAME}.app"
  sign "${APP_PATH}" --entitlements "${ENTITLEMENTS}"

  echo "==> 校验 .app 签名"
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
fi

# ------------------------------------------------------------- 4. 公证 .app

notarize() {
  local target="$1"
  echo "==> 提交公证：$(basename "${target}") (auth: ${NOTARY_AUTH})"

  local auth_args=()
  if [[ "${NOTARY_AUTH}" == "apple-id" ]]; then
    auth_args=(--apple-id "${APPLE_ID}" --password "${APPLE_APP_PASSWORD}")
  else
    auth_args=(--key "${APPLE_NOTARY_KEY_PATH}" --key-id "${APPLE_NOTARY_KEY_ID}")
    # Individual API key 不能带 --issuer；只有 Team key 需要。
    if [[ -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
      auth_args+=(--issuer "${APPLE_NOTARY_ISSUER_ID}")
    fi
  fi

  xcrun notarytool submit "${target}" \
    "${auth_args[@]}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait \
    --timeout 45m
}

if [[ "${SKIP_NOTARIZE}" -eq 0 ]]; then
  # notarytool 不接受裸 .app，必须先打成 zip / dmg / pkg 提交。
  # 这里先用 zip 提交拿到 ticket，再 staple 回 .app —— 这样 DMG 里的 .app
  # 本身也带票，用户拖到 /Applications 后离线也能直接打开。
  APP_ZIP="${WORK_DIR}/${APP_NAME}.zip"
  ditto -c -k --keepParent "${APP_PATH}" "${APP_ZIP}"
  notarize "${APP_ZIP}"

  echo "==> staple .app"
  xcrun stapler staple "${APP_PATH}"
fi

# --------------------------------------------------------------- 5. 制作 DMG

echo "==> 制作 DMG"
DMG_STAGE="${WORK_DIR}/dmg"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_PATH}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${APP_NAME} ${EFFECTIVE_VERSION}" \
  -srcfolder "${DMG_STAGE}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}"

if [[ "${SKIP_SIGN}" -eq 0 ]]; then
  echo "==> 签名 DMG"
  # DMG 是容器，不吃 entitlements / hardened runtime。
  codesign --force --timestamp \
    "${CODESIGN_KEYCHAIN_ARGS[@]}" \
    --sign "${APPLE_SIGNING_IDENTITY}" \
    "${DMG_PATH}"
fi

# -------------------------------------------------------------- 6. 公证 DMG

if [[ "${SKIP_NOTARIZE}" -eq 0 ]]; then
  notarize "${DMG_PATH}"
  echo "==> staple DMG"
  xcrun stapler staple "${DMG_PATH}"
fi

# ------------------------------------------------------------------ 7. 校验

echo "==> 最终校验"
if [[ "${SKIP_SIGN}" -eq 0 ]]; then
  codesign --verify --strict --verbose=2 "${DMG_PATH}"
fi
if [[ "${SKIP_NOTARIZE}" -eq 0 ]]; then
  xcrun stapler validate "${DMG_PATH}"
  # Gatekeeper 视角的最终确认：挂载后检查 .app 是否被接受。
  MOUNT_POINT="$(mktemp -d)"
  hdiutil attach "${DMG_PATH}" -nobrowse -readonly -mountpoint "${MOUNT_POINT}" >/dev/null
  trap 'hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true' EXIT
  spctl --assess --type execute --verbose=4 "${MOUNT_POINT}/${APP_NAME}.app"
  xcrun stapler validate "${MOUNT_POINT}/${APP_NAME}.app"
  hdiutil detach "${MOUNT_POINT}" >/dev/null
  trap - EXIT
fi

echo ""
echo "已生成：${DMG_PATH}"
