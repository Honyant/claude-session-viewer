#!/bin/bash
set -e

APP_NAME="Claude Session Viewer"
DMG_NAME="${APP_NAME}.dmg"
STAGING_DIR="dmg-staging"

# Build the app bundle first
echo "Building app..."
./build-app.sh

# Clean previous artifacts
rm -rf "${STAGING_DIR}" "${DMG_NAME}"

# Create staging directory with app and Applications symlink
mkdir -p "${STAGING_DIR}"
cp -r "${APP_NAME}.app" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# Create the DMG
echo "Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_NAME}"

# Clean up
rm -rf "${STAGING_DIR}"

echo ""
echo "Created ${DMG_NAME}"
echo "Users can open the DMG and drag the app to Applications."
