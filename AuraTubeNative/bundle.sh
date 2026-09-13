#!/bin/bash
set -e

APP_NAME="AuraTube"
BUNDLE_DIR="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Stopping any running instances..."
pkill -9 -f "${APP_NAME}" || true
sleep 1

echo "==> Preparing bundle directory: ${BUNDLE_DIR}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "==> Copying native binary..."
cp /Users/tungnguyen/Code/Youtube/AuraTubeNative/.build/release/AuraTube "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "==> Copying app icons..."
if [ -f "/Users/tungnguyen/Code/Youtube/assets/icon.icns" ]; then
    cp "/Users/tungnguyen/Code/Youtube/assets/icon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "==> Writing Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
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
    <string>2.0.16</string>
    <key>CFBundleVersion</key>
    <string>17</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Tung Nguyen. All rights reserved.</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
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
