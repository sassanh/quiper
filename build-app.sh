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
    clean build

# Find the built app
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: $APP_NAME.app not found in build directory"
    exit 1
fi

# Copy to root for easy access
cp -R "$APP_PATH" .

echo "✅ Successfully built $APP_NAME.app"
echo "   Location: $(pwd)/$APP_NAME.app"
