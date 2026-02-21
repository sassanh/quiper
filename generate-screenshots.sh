#!/bin/bash
set -euo pipefail

PROJECT="Quiper.xcodeproj"
SCHEME="Quiper"
SCREENSHOT_DIR="$HOME/Downloads/quiper-screenshots"
ASSETS_DIR=".github/assets"

INTERACTIVE=false
TEST_METHOD="testGenerateScreenshotsNonInteractive"

for arg in "$@"; do
    if [ "$arg" == "--interactive" ]; then
        INTERACTIVE=true
        TEST_METHOD="testGenerateScreenshotsInteractive"
    fi
done

echo "📸 Preparing to generate screenshots..."
rm -rf "$SCREENSHOT_DIR"
mkdir -p "$SCREENSHOT_DIR"

if [ "$INTERACTIVE" = true ]; then
    echo "🎮 Running in INTERACTIVE mode."
else
    echo "🤖 Running in NON-INTERACTIVE mode."
fi

echo "🧪 Running screenshot generation tests ($TEST_METHOD)..."

xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -only-testing:QuiperUITests/ScreenshotGenerator/"$TEST_METHOD"

echo "🔄 Converting screenshots to WebP..."
cd "$SCREENSHOT_DIR"
for png in *.png; do
    if [ -f "$png" ]; then
        filename=$(basename "$png" .png)
        echo "   Converting $filename..."
        cwebp -q 80 "$png" -o "$filename.webp" > /dev/null 2>&1
    fi
done
cd - > /dev/null

echo "📂 Moving screenshots to $ASSETS_DIR..."
mkdir -p "$ASSETS_DIR"
for webp in "$SCREENSHOT_DIR"/*.webp; do
    if [ -f "$webp" ]; then
        cp "$webp" "$ASSETS_DIR/"
    fi
done

echo "✅ Done! Screenshots updated in $ASSETS_DIR"
