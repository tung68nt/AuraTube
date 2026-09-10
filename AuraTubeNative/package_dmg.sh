#!/bin/bash
set -e

APP_NAME="AuraTube"
VERSION="2.0.5"
BUILD="6"
SOURCE_DIR="/Users/tungnguyen/Code/Youtube/AuraTubeNative"
ASSETS_DIR="/Users/tungnguyen/Code/Youtube/assets"
OUTPUT_DIR="/Users/tungnguyen/Code/Youtube"
FINAL_DMG="${OUTPUT_DIR}/${APP_NAME}-v${VERSION}.dmg"
LATEST_DMG="${OUTPUT_DIR}/${APP_NAME}.dmg"
APP_BUNDLE="/Applications/${APP_NAME}.app"

echo "==> 1. Building release bundle for AuraTube v${VERSION}..."
swift build --package-path "${SOURCE_DIR}" -c release && bash "${SOURCE_DIR}/bundle.sh"

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

echo "==> 4. Creating Applications symlink..."
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> 5. Creating temporary read/write disk image..."
rm -f "${TMP_DMG}"
hdiutil create -srcfolder "${STAGING_DIR}" -volname "${APP_NAME}" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 300m "${TMP_DMG}"

echo "==> 6. Mounting temporary disk image for Finder styling..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${TMP_DMG}" | egrep '^/dev/' | sed 1q | awk '{print $1}')
sleep 2

# Apply custom volume icon if available
if [ -f "${ASSETS_DIR}/icon.icns" ]; then
    echo "==> 7. Setting custom Volume Icon..."
    cp "${ASSETS_DIR}/icon.icns" "/Volumes/${APP_NAME}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -c icnC "/Volumes/${APP_NAME}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "/Volumes/${APP_NAME}" 2>/dev/null || true
fi

echo "==> 8. Configuring Finder presentation layout via AppleScript..."
osascript -e "
tell application \"Finder\"
    tell disk \"${APP_NAME}\"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {350, 150, 950, 550}
        
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 110
        set text size of viewOptions to 13
        set arrangement of viewOptions to not arranged
        
        -- Position app on the left, Applications folder on the right
        set position of item \"${APP_NAME}.app\" of container window to {160, 200}
        set position of item \"Applications\" of container window to {440, 200}
        
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
