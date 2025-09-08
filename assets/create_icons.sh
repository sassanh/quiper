#!/bin/bash

SRC_SVG="logo.svg"

for color in "light" "dark"; do
  CHANNEL_ARGS=$([ "$color" = "dark" ] && echo "-channel RGB -negate" || echo "")

  magick \
    -background none \
    "$SRC_SVG" \
    $CHANNEL_ARGS \
    logo_"$color".png

  cp logo_"$color".png ../quiper/logo/
done
