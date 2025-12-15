#!/bin/bash
# Generate macOS .icns file with White on Black style, preserving padding and transparent squircle corners.
# Requires: ImageMagick (magick) and macOS native iconutil

ICONSET_DIR="/tmp/Quiper.iconset"
OUTPUT_ICNS="Quiper/QuiperIcon.icns"
SOURCE_LOGO="Quiper/logo/logo.png"

# Ensure clean slate
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# List of all required icon sizes and names
# format: "size filename"
sizes=(
    "16 icon_16x16.png"
    "32 icon_16x16@2x.png"
    "32 icon_32x32.png"
    "64 icon_32x32@2x.png"
    "128 icon_128x128.png"
    "256 icon_128x128@2x.png"
    "256 icon_256x256.png"
    "512 icon_256x256@2x.png"
    "512 icon_512x512.png"
    "1024 icon_512x512@2x.png"
)

echo "Generating iconset..."

for info in "${sizes[@]}"; do
    size=$(echo $info | cut -d' ' -f1)
    name=$(echo $info | cut -d' ' -f2)
    
    # Calculate dimensions for squircle mask
    # 22% radius is standard for macOS squircle
    radius=$(python3 -c "print(round($size * 0.22))" | cut -d. -f1)
    maxv=$(($size - 1))

    # 1. Create Base Image (White on Black)
    # - Background: Black (xc:black)
    # - Foreground: Extract alpha from logo.png (the robot shape) and use it directly (white robot)
    # - Resize to target size explicitly
    magick -size ${size}x${size} xc:black \
        \( "$SOURCE_LOGO" -alpha extract -resize ${size}x${size}! \) \
        -gravity center -composite /tmp/base.png

    # 2. Create Squircle Mask
    # - Black background with White rounded rectangle
    magick -size ${size}x${size} xc:black \
        -fill white -draw "roundrectangle 0,0 $maxv,$maxv $radius,$radius" \
        /tmp/mask.png

    # 3. Apply Mask and Save as PNG32
    # - Use copy_opacity to apply the mask to the alpha channel
    # - Save as PNG32 to ensure 32-bit RGBA format (fixes transparency issues in Finder)
    magick /tmp/base.png /tmp/mask.png \
        -alpha off -compose copy_opacity -composite \
        PNG32:"$ICONSET_DIR/$name"
done

echo "Converting iconset to icns..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "Done! Created $OUTPUT_ICNS"
