#!/bin/bash
# Rebuild <APP> (app + widget) with ad-hoc signing (NO Apple ID), reinstall to
# /Applications, register, refresh widget daemons, launch to register the widget.
# Replace {{APP}} before use.
set -e
cd "$(dirname "$0")"
APP="{{APP}}"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "▸ Regenerating project…";  xcodegen generate >/dev/null

echo "▸ Building (ad-hoc)…"
xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build \
  2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | grep -vE "CoreSimulator|IDESimulator" || true

echo "▸ Installing to /Applications…"
osascript -e "tell application \"$APP\" to quit" 2>/dev/null || true; sleep 1
rm -rf "/Applications/$APP.app"
cp -R "build/Build/Products/Debug/$APP.app" /Applications/
"$LSREG" -f "/Applications/$APP.app" 2>/dev/null || true

echo "▸ Refreshing widget daemons…"; killall pkd chronod 2>/dev/null || true; sleep 3
echo "▸ Launching (registers the widget)…"; open "/Applications/$APP.app"
echo "✔ Done. Add via: right-click desktop → Edit Widgets → search $APP."
