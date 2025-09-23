#!/bin/zsh
set -euo pipefail
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Screen_Actions-*/Build/Products/Debug-iphoneos/Screen\ Actions.app 2>/dev/null | head -1)
[[ -d "$APP" ]] || { echo "No Debug build found. Build to device once, then re-run."; exit 1; }
APPEX="$APP/PlugIns/ScreenActionsWebExtension.appex"
echo "App path: $APP"
echo "Appex:    $APPEX"

test -f "$APPEX/manifest.json" || { echo "✗ Missing manifest.json at appex root"; exit 1; }
echo "✓ manifest.json present at appex root"

for n in background.js popup.js popup.html popup.css; do
  test -f "$APPEX/$n" || { echo "✗ Missing $n at appex root"; exit 1; }
done
echo "✓ core files present at appex root"

for n in 48 64 96 128 256 512; do
  test -f "$APPEX/images/icon-$n-squircle.png" || { echo "✗ Missing images/icon-$n-squircle.png"; exit 1; }
done
echo "✓ icon images present under appex/images"

echo "grep sendNativeMessage:"
grep -n 'sendNativeMessage' "$APPEX/background.js" || true
grep -n 'sendNativeMessage' "$APPEX/popup.js" || true
echo "Rule: NO comma inside sendNativeMessage(..., ...). One-arg Promise only."
