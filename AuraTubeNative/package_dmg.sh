#!/bin/bash
set -e

APP_NAME="AuraTube"
SOURCE_DIR="/Users/tungnguyen/Code/Youtube/AuraTubeNative"
ASSETS_DIR="/Users/tungnguyen/Code/Youtube/assets"
OUTPUT_DIR="/Users/tungnguyen/Code/Youtube"

if [ -f "${OUTPUT_DIR}/version.json" ]; then
    VERSION=$(grep '"version":' "${OUTPUT_DIR}/version.json" | head -n1 | sed -E 's/.*"version": "([^"]+)".*/\1/')
    BUILD=$(grep '"build":' "${OUTPUT_DIR}/version.json" | head -n1 | sed -E 's/.*"build": ([0-9]+).*/\1/')
fi
VERSION="${VERSION:-2.0.28}"
BUILD="${BUILD:-29}"

FINAL_DMG="${OUTPUT_DIR}/${APP_NAME}-v${VERSION}.dmg"
LATEST_DMG="${OUTPUT_DIR}/${APP_NAME}.dmg"
APP_BUNDLE="/Applications/${APP_NAME}.app"
TOOL_NAME="Huong Dan Mo Khoa (Doc Khi Bi Bao Loi).txt"

echo "==> 1. Building release bundle for AuraTube v${VERSION} (Build ${BUILD})..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path "${SOURCE_DIR}" -c release && bash "${SOURCE_DIR}/bundle.sh"

# Prepare staging temporary directory
STAGING_DIR="/tmp/auratube_dmg_staging_$$"
TMP_DMG="/tmp/auratube_rw_$$.dmg"
MOUNT_DIR="/Volumes/${APP_NAME}"

cleanup() {
    echo "==> Cleaning up temporary files..."
    if [ -d "${MOUNT_DIR}" ]; then
        hdiutil detach "${MOUNT_DIR}" -force 2>/dev/null || true
    fi
    rm -rf "${STAGING_DIR}" "${TMP_DMG}" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> 2. Preparing staging directory at ${STAGING_DIR}..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

echo "==> 3. Copying ${APP_NAME}.app into staging..."
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"

echo "==> 4. Adding safe Gatekeeper guide into staging..."
cp "${ASSETS_DIR}/Huong Dan Mo Khoa (Doc Khi Bi Bao Loi).txt" "${STAGING_DIR}/${TOOL_NAME}"

echo "==> 5. Creating Applications symlink..."
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> 6. Creating temporary read/write disk image..."
rm -f "${TMP_DMG}"
hdiutil create -srcfolder "${STAGING_DIR}" -volname "${APP_NAME}" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 300m "${TMP_DMG}"

echo "==> 7. Mounting temporary disk image for Finder styling..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${TMP_DMG}" | egrep '^/dev/' | sed 1q | awk '{print $1}')
sleep 2

# Apply custom volume icon if available
if [ -f "${ASSETS_DIR}/icon.icns" ]; then
    echo "==> 8. Setting custom Volume Icon..."
    cp "${ASSETS_DIR}/icon.icns" "/Volumes/${APP_NAME}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -c icnC "/Volumes/${APP_NAME}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "/Volumes/${APP_NAME}" 2>/dev/null || true
fi

echo "==> 9. Configuring Finder presentation layout via AppleScript..."
osascript -e "
tell application \"Finder\"
    tell disk \"${APP_NAME}\"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {260, 150, 960, 540}
        
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 105
        set text size of viewOptions to 12
        set arrangement of viewOptions to not arranged
        
        -- Position app on the left, Applications in the middle, Gatekeeper unlock tool on the right
        set position of item \"${APP_NAME}.app\" of container window to {145, 195}
        set position of item \"Applications\" of container window to {360, 195}
        set position of item \"${TOOL_NAME}\" of container window to {565, 195}
        
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
" || true

# Wait and unmount cleanly
sleep 2
echo "==> 9. Syncing and unmounting disk image..."
sync
hdiutil detach "${DEVICE}" -force

echo "==> 10. Converting to highly compressed final DMG (${FINAL_DMG})..."
rm -f "${FINAL_DMG}" "${LATEST_DMG}"
hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}"

echo "==> 11. Creating latest version link: ${LATEST_DMG}..."
cp -f "${FINAL_DMG}" "${LATEST_DMG}"

echo "==> 12. Generating fast ZIP packages for instant updates..."
FINAL_ZIP="${OUTPUT_DIR}/${APP_NAME}-v${VERSION}.zip"
LATEST_ZIP="${OUTPUT_DIR}/${APP_NAME}.zip"
rm -f "${FINAL_ZIP}" "${LATEST_ZIP}"
(cd /Applications && zip -r -q -y "${FINAL_ZIP}" "${APP_NAME}.app")
cp -f "${FINAL_ZIP}" "${LATEST_ZIP}"

echo "==> 13. Verifying generated DMG..."
hdiutil verify "${FINAL_DMG}"

DMG_SIZE=$(du -h "${FINAL_DMG}" | awk '{print $1}')
ZIP_SIZE=$(du -h "${FINAL_ZIP}" | awk '{print $1}')
echo ""
echo "============================================================"
echo "🎉 Thành công! File DMG và ZIP đã được đóng gói hoàn tất:"
echo "   📍 DMG: ${FINAL_DMG} (${DMG_SIZE})"
echo "   📍 ZIP: ${FINAL_ZIP} (${ZIP_SIZE})"
echo "============================================================"
