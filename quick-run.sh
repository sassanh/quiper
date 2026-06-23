#!/bin/bash
set -euo pipefail

xcodebuild -project Quiper.xcodeproj -scheme Quiper -configuration Debug build
if [ "$#" = "1" ]; then
  ~/Library/Developer/Xcode/DerivedData/Quiper-dpgozfjoxglfylgrmictwwzlnnmd/Build/Products/Debug/Quiper.app/Contents/MacOS/Quiper
else
  open ~/Library/Developer/Xcode/DerivedData/Quiper-dpgozfjoxglfylgrmictwwzlnnmd/Build/Products/Debug/Quiper.app
fi
