#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"

APP_NAME="${APP_NAME:-Nibbler}"
UPSTREAM_REPO="${UPSTREAM_REPO:-rooklift/nibbler}"
NIBBLER_TAG="${NIBBLER_TAG:-}"
ELECTRON_VERSION="${ELECTRON_VERSION:-40.1.0}"
PACKAGER_VERSION="${PACKAGER_VERSION:-19.0.2}" # @electron/packager
BUNDLE_ID="${BUNDLE_ID:-com.${GITHUB_REPOSITORY_OWNER:-nibbler}.nibbler}"

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required command: $1" >&2
		exit 1
	fi
}

require_cmd curl
require_cmd unzip
require_cmd npx
require_cmd codesign
require_cmd file
require_cmd plutil
require_cmd sips
require_cmd iconutil
require_cmd shasum
require_cmd ditto
require_cmd grep

rm -rf "$DIST_DIR" || true
mkdir -p "$DIST_DIR"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -z "$NIBBLER_TAG" ]]; then
	echo "Resolving latest upstream Nibbler release tag..."
	NIBBLER_TAG="$(curl -fsSL -o /dev/null -w "%{url_effective}" "https://github.com/${UPSTREAM_REPO}/releases/latest" | awk -F/ '{print $NF}')"
fi

if [[ -z "$NIBBLER_TAG" ]]; then
	echo "Failed to resolve Nibbler tag." >&2
	exit 1
fi

echo "Upstream: ${UPSTREAM_REPO}"
echo "Tag:      ${NIBBLER_TAG}"
echo "Electron: ${ELECTRON_VERSION}"

UPSTREAM_ZIP_URL="https://github.com/${UPSTREAM_REPO}/archive/refs/tags/${NIBBLER_TAG}.zip"
UPSTREAM_ZIP_PATH="${WORK_DIR}/nibbler.zip"

echo "Downloading upstream source: ${UPSTREAM_ZIP_URL}"
curl -fsSL -L "$UPSTREAM_ZIP_URL" -o "$UPSTREAM_ZIP_PATH"

echo "Extracting upstream..."
unzip -q "$UPSTREAM_ZIP_PATH" -d "$WORK_DIR"

PACKAGE_JSON_PATH="$(find "$WORK_DIR" -maxdepth 6 -type f -path "*/files/src/package.json" -print -quit)"
if [[ -z "$PACKAGE_JSON_PATH" ]]; then
	echo "Could not locate upstream files/src/package.json in downloaded archive." >&2
	exit 1
fi

APP_SRC_DIR="$(cd "$(dirname "$PACKAGE_JSON_PATH")" && pwd)"
UPSTREAM_ROOT_DIR="$(cd "${APP_SRC_DIR}/../.." && pwd)"
ICON_PNG_PATH="${UPSTREAM_ROOT_DIR}/files/res/nibbler.png"

if [[ ! -f "$ICON_PNG_PATH" ]]; then
	echo "Could not locate upstream icon png at ${ICON_PNG_PATH}" >&2
	exit 1
fi

ICNS_DIR="${WORK_DIR}/icon.iconset"
ICNS_PATH="${WORK_DIR}/Nibbler.icns"

echo "Generating .icns icon..."
mkdir -p "$ICNS_DIR"

make_icon() {
	local size="$1" out="$2"
	sips -s format png -z "$size" "$size" "$ICON_PNG_PATH" --out "${ICNS_DIR}/${out}" >/dev/null
}

make_icon 16 "icon_16x16.png"
make_icon 32 "icon_16x16@2x.png"
make_icon 32 "icon_32x32.png"
make_icon 64 "icon_32x32@2x.png"
make_icon 128 "icon_128x128.png"
make_icon 256 "icon_128x128@2x.png"
make_icon 256 "icon_256x256.png"
make_icon 512 "icon_256x256@2x.png"
make_icon 512 "icon_512x512.png"
make_icon 1024 "icon_512x512@2x.png"

iconutil -c icns "$ICNS_DIR" -o "$ICNS_PATH"

echo "Packaging .app..."
npx --yes "@electron/packager@${PACKAGER_VERSION}" "$APP_SRC_DIR" "$APP_NAME" \
	--platform=darwin \
	--arch=arm64 \
	--electron-version="$ELECTRON_VERSION" \
	--app-bundle-id="$BUNDLE_ID" \
	--out="$DIST_DIR" \
	--overwrite

APP_BUNDLE_PATH="$(find "$DIST_DIR" -maxdepth 3 -type d -name "${APP_NAME}.app" -print -quit)"
if [[ -z "$APP_BUNDLE_PATH" ]]; then
	echo "Packager did not produce ${APP_NAME}.app under ${DIST_DIR}" >&2
	exit 1
fi

echo "Patching Info.plist + icon..."
INFO_PLIST_PATH="${APP_BUNDLE_PATH}/Contents/Info.plist"
plutil -replace LSApplicationCategoryType -string "public.app-category.games" "$INFO_PLIST_PATH"
cp "$ICNS_PATH" "${APP_BUNDLE_PATH}/Contents/Resources/${APP_NAME}.icns"
plutil -replace CFBundleIconFile -string "${APP_NAME}.icns" "$INFO_PLIST_PATH"

echo "Ad-hoc signing (keeps it effectively 'unsigned' but avoids invalid signature errors)..."
codesign --force --deep --sign - "$APP_BUNDLE_PATH"

echo "Verifying codesign..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH"

echo "Verifying architecture..."
BIN_PATH="${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
	echo "Missing app executable: ${BIN_PATH}" >&2
	exit 1
fi

file "$BIN_PATH" | tee "${DIST_DIR}/binary.txt"
if ! file "$BIN_PATH" | grep -q "arm64"; then
	echo "Expected arm64 binary, got:" >&2
	file "$BIN_PATH" >&2
	exit 1
fi

ZIP_NAME="${APP_NAME}-${NIBBLER_TAG}-macOS-arm64.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"

echo "Zipping: ${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE_PATH" "$ZIP_PATH"

echo "${NIBBLER_TAG}" > "${DIST_DIR}/tag.txt"
echo "${ELECTRON_VERSION}" > "${DIST_DIR}/electron_version.txt"
echo "${BUNDLE_ID}" > "${DIST_DIR}/bundle_id.txt"
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "${DIST_DIR}/sha256.txt"

echo "Done:"
echo "  ${ZIP_PATH}"
