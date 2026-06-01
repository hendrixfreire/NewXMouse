#!/bin/bash
# Build and deploy New X Mouse to /Applications
# Uses xcodebuild install to ensure consistent signing/cdhash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="New X Mouse"
SCHEME="NewXMouse"

echo "Building $APP_NAME..."
xcodebuild install \
    -project "$PROJECT_DIR/NewXMouse.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    DSTROOT=/tmp/nxm_install \
    INSTALL_PATH=/ \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | tail -5

echo "Stopping running instance..."
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

echo "Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "/tmp/nxm_install/$APP_NAME.app" /Applications/

echo "Registering with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f -R -trusted "/Applications/$APP_NAME.app" 2>/dev/null || true

echo "Launching..."
open "/Applications/$APP_NAME.app"

echo "Done! If this is your first run after reset, authorize in System Settings > Privacy & Security > Accessibility"
