#!/bin/bash
# Builds JarvisDashboard.app: a real double-clickable Mac app bundle, hand-
# assembled from a Swift Package Manager build since only the Command Line
# Tools are installed here (no Xcode.app -> no xcodebuild).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Building (release)..."
swift build -c release

APP="$HOME/Applications/Jarvis.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/JarvisDashboard" "$APP/Contents/MacOS/JarvisDashboard"
cp "Info.plist" "$APP/Contents/Info.plist"
cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "Built: $APP"
echo "Launch with: open '$APP'"
