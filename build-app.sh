#!/bin/bash
set -euo pipefail

# Define variables
APP_NAME="Quiper"
APP_IDENTIFIER=${APP_IDENTIFIER:-"com.sassanharadji.quiper"}
BUILD_DIR=""
EXECUTABLE_PATH=""
APP_BUNDLE_PATH="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_PATH="Supporting/Info.plist" # Path to your Info.plist
APP_ICON_SOURCE="Supporting/QuiperIcon.icns"

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

# Clean up previous build
rm -rf "$APP_BUNDLE_PATH"

# Build the Swift executable and capture the products directory
swift build -c release
BUILD_DIR=$(swift build --show-bin-path -c release)
EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"

# Check if build was successful
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Error: Swift executable not found at $EXECUTABLE_PATH"
    exit 1
fi

# Create the .app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy the executable
cp "$EXECUTABLE_PATH" "$MACOS_DIR/"

# Copy the Info.plist
cp "$INFO_PLIST_PATH" "$CONTENTS_DIR/"
plutil -replace CFBundleName -string "$APP_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleExecutable -string "$APP_NAME" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleIdentifier -string "$APP_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$APP_BUILD" "$CONTENTS_DIR/Info.plist"

# Copy the app icon if present
if [ -f "$APP_ICON_SOURCE" ]; then
    cp "$APP_ICON_SOURCE" "$RESOURCES_DIR/"
else
    echo "Warning: App icon not found at $APP_ICON_SOURCE"
fi

# Copy static resources that the app expects at runtime.
# Package.swift no longer declares processed resources, so we add them manually.
cp -R "Sources/Quiper/logo" "$RESOURCES_DIR/"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_BUNDLE_PATH"
fi

echo "Successfully created $APP_BUNDLE_PATH"
