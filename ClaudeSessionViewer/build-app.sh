#!/bin/bash
set -e

# Build the release version
swift build -c release

# Create app bundle structure
APP_NAME="Claude Session Viewer"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Clean and create directories
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp .build/release/ClaudeSessionViewer "${MACOS_DIR}/"

# Copy Info.plist
cp ClaudeSessionViewer/Resources/Info.plist "${CONTENTS_DIR}/"

# Copy icon
cp ClaudeSessionViewer/Resources/AppIcon.icns "${RESOURCES_DIR}/"

echo "Built ${APP_BUNDLE}"
echo ""
echo "To install, run:"
echo "  cp -r \"${APP_BUNDLE}\" /Applications/"
