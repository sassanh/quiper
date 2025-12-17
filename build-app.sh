#!/bin/bash
set -euo pipefail

# Define variables
APP_NAME="Quiper"
SCHEME="Quiper"
PROJECT="Quiper.xcodeproj"
CONFIGURATION=${CONFIGURATION:-"Release"}
BUILD_DIR="build"

detect_version() {
    if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" == v* ]]; then
        echo "${GITHUB_REF_NAME#v}"
        return
    fi

    if git describe --tags --abbrev=0 >/dev/null 2>&1; then
        git describe --tags --abbrev=0 | sed 's/^v//'
        return
    fi

    echo "0.0.0"
}

APP_VERSION=${APP_VERSION:-$(detect_version)}
APP_BUILD=${APP_BUILD:-${GITHUB_RUN_NUMBER:-$(date +'%Y%m%d%H%M')}}

echo "🏗️  Building $APP_NAME v$APP_VERSION ($APP_BUILD)..."

# Clean previous builds
rm -rf "$BUILD_DIR"

# Build with xcodebuild
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    MARKETING_VERSION="$APP_VERSION" \
    CURRENT_PROJECT_VERSION="$APP_BUILD" \
    CODE_SIGN_ENTITLEMENTS="Quiper/Quiper.entitlements" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build

# Find the built app
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: $APP_NAME.app not found in build directory"
    exit 1
fi

# Copy to root for easy access
cp -R "$APP_PATH" .

# Re-sign manually to ensure exact entitlements (Option 3: Downloads entitlement without Sandbox)
# This overrides Xcode's automatic injection of app-sandbox
if command -v codesign >/dev/null 2>&1; then
    echo "🔏 Re-signing with explicit entitlements..."
    codesign --force --deep --sign - --entitlements "Quiper/Quiper.entitlements" "$APP_NAME.app"
fi

echo "✅ Successfully built $APP_NAME.app"
echo "   Location: $(pwd)/$APP_NAME.app"
