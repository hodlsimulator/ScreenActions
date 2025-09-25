#!/bin/zsh
set -euo pipefail

APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Screen_Actions-*/Build/Products/Debug-iphoneos/Screen\ Actions.app 2>/dev/null | head -1)
[[ -d "$APP" ]] || { echo "No Debug build found. Build to a device once, then re-run."; exit 1; }

APPEX="$APP/PlugIns/ScreenActionsWebExtension.appex"
echo "App path: $APP"
echo "Appex: $APPEX"

# Manifest location per Info.plist: WebRes/manifest.json
test -f "$APPEX/WebRes/manifest.json" || { echo "✗ Missing WebRes/manifest.json"; exit 1; }
echo "✓ manifest present under WebRes/"

# Core resources (relative to WebRes/)
for n in background.js popup.js popup.html popup.css content_selection.js; do
  test -f "$APPEX/WebRes/$n" || { echo "✗ Missing WebRes/$n"; exit 1; }
done
echo "✓ core WebRes files present"

# Locales
test -f "$APPEX/WebRes/_locales/en/messages.json" || { echo "✗ Missing WebRes/_locales/en/messages.json"; exit 1; }
echo "✓ locales present"

# Icons
for n in 48 64 96 128 256 512; do
  test -f "$APPEX/WebRes/images/icon-$n-squircle.png" || { echo "✗ Missing WebRes/images/icon-$n-squircle.png"; exit 1; }
done
echo "✓ icons present"

echo "grep sendNativeMessage:"
grep -n 'sendNativeMessage' "$APPEX/WebRes/background.js" || true
grep -n 'sendNativeMessage' "$APPEX/WebRes/popup.js" || true
