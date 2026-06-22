#!/bin/bash
set -euo pipefail

xcodebuild -project Quiper.xcodeproj -scheme Quiper -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Quiper-dpgozfjoxglfylgrmictwwzlnnmd/Build/Products/Debug/Quiper.app
