#!/bin/zsh
set -euo pipefail
PLIST="ScreenActionsWebExtension/Info.plist"
[[ -f "$PLIST" ]] || { echo "Missing $PLIST"; exit 1; }

/usr/libexec/PlistBuddy -c 'Set :NSExtension:NSExtensionPointIdentifier com.apple.Safari.web-extension' "$PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c 'Add :NSExtension:NSExtensionPointIdentifier string com.apple.Safari.web-extension' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :NSExtension:NSExtensionPrincipalClass SAWebExtensionHandler' "$PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c 'Add :NSExtension:NSExtensionPrincipalClass string SAWebExtensionHandler' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :NSExtension:NSExtensionAttributes:SFSafariWebExtensionManifestPath WebRes/manifest.json' "$PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c 'Add :NSExtension:NSExtensionAttributes:SFSafariWebExtensionManifestPath string WebRes/manifest.json' "$PLIST"

echo "✓ Info.plist keys set"
