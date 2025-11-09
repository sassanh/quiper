#!/bin/bash

# Define variables
APP_NAME="Quiper"
BUILD_DIR=".build/release" # Or .build/debug
EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
APP_BUNDLE_PATH="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_PATH="Supporting/Info.plist" # Path to your Info.plist
APP_ICON_SOURCE="Supporting/QuiperIcon.icns"

# Clean up previous build
rm -rf "$APP_BUNDLE_PATH"

# Build the Swift executable
swift build -c release

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

# Copy the app icon if present
if [ -f "$APP_ICON_SOURCE" ]; then
    cp "$APP_ICON_SOURCE" "$RESOURCES_DIR/"
else
    echo "Warning: App icon not found at $APP_ICON_SOURCE"
fi

# Copy resources (if any, based on Package.swift)
# The Package.swift specifies .process("logo") which means it will be copied to the bundle.
# However, swift build doesn't automatically put it in Resources/.
# We need to manually copy it.
# Assuming 'logo' is a directory or a file in Sources/Quiper/logo
cp -R "Sources/Quiper/logo" "$RESOURCES_DIR/"

echo "Successfully created $APP_BUNDLE_PATH"
