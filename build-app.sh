#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release
app="$(pwd)/Task Board.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/Info.plist"
cp .build/release/TaskBoard "$app/Contents/MacOS/TaskBoard"
cp Assets/TaskBoard.icns "$app/Contents/Resources/TaskBoard.icns"
cp Assets/TaskBoard-logo.png "$app/Contents/Resources/TaskBoard-logo.png"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$app"
touch "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
printf 'Built %s\n' "$app"
