#!/bin/zsh
set -euo pipefail
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Screen_Actions-*/Build/Products/Debug-iphoneos/Screen\ Actions.app 2>/dev/null | head -1)
[[ -d "$APP" ]] || { echo "No Debug build found. Build to device once, then re-run."; exit 1; }
APPEX="$APP/PlugIns/ScreenActionsWebExtension.appex"
BG="$APPEX/WebRes/background.js"
PO="$APPEX/WebRes/popup.js"
echo "background.js -> $BG"; grep -n 'sendNativeMessage' "$BG" || true
echo; echo "popup.js -> $PO";  grep -n 'sendNativeMessage' "$PO" || true
echo; echo "Rule: NO comma inside sendNativeMessage(..., ...). One-arg Promise only."
