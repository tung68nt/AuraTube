#!/bin/bash
set -e

APP_NAME="AuraTube"
BUNDLE_DIR="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Stopping any running instances..."
pkill -9 -x "${APP_NAME}" || true
sleep 1

echo "==> Preparing bundle directory: ${BUNDLE_DIR}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "==> Copying native binary..."
cp "${APP_BINARY:-${SCRIPT_DIR}/.build/release/AuraTube}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "==> Copying app icons..."
if [ -f "${ROOT_DIR}/assets/icon.icns" ]; then
    cp "${ROOT_DIR}/assets/icon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "==> Bundling standalone yt-dlp (works without Homebrew/Python)..."
mkdir -p "${RESOURCES_DIR}/bin"
YTDLP_CACHE="${SCRIPT_DIR}/.build/yt-dlp_macos"
if curl -fL --retry 3 -o "${YTDLP_CACHE}.tmp" "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"; then
    mv -f "${YTDLP_CACHE}.tmp" "${YTDLP_CACHE}"
fi
if [ ! -f "${YTDLP_CACHE}" ]; then
    echo "ERROR: could not download yt-dlp_macos" >&2
    exit 1
fi
cp "${YTDLP_CACHE}" "${RESOURCES_DIR}/bin/yt-dlp"
chmod +x "${RESOURCES_DIR}/bin/yt-dlp"
xattr -d com.apple.quarantine "${RESOURCES_DIR}/bin/yt-dlp" 2>/dev/null || true

echo "==> Copying custom fonts..."
if [ -d "${SCRIPT_DIR}/Resources/Fonts" ]; then
    mkdir -p "${RESOURCES_DIR}/Fonts"
    cp -R "${SCRIPT_DIR}/Resources/Fonts/"* "${RESOURCES_DIR}/Fonts/"
fi

VERSION="2.1.5"
BUILD="106"
if [ -f "${ROOT_DIR}/version.json" ]; then
    V_PARSED=$(grep '"version":' "${ROOT_DIR}/version.json" | head -n1 | sed -E 's/.*"version": "([^"]+)".*/\1/')
    B_PARSED=$(grep '"build":' "${ROOT_DIR}/version.json" | head -n1 | sed -E 's/.*"build": ([0-9]+).*/\1/')
    if [ -n "$V_PARSED" ]; then VERSION="$V_PARSED"; fi
    if [ -n "$B_PARSED" ]; then BUILD="$B_PARSED"; fi
fi

echo "==> Writing Info.plist for version ${VERSION} (build ${BUILD})..."
cat << EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AuraTube</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.auratube.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AuraTube</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Tung Nguyen. All rights reserved.</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>ATSApplicationFontsPath</key>
    <string>Fonts</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "==> Codesigning (ad-hoc)..."
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "==> Done! Native macOS App created at ${BUNDLE_DIR}"
