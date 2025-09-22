#!/bin/zsh
set -euo pipefail

# Edit this if your .mobileprovision files live elsewhere
SRC_DIR="/Users/conor/Developer"
DEST="$HOME/Library/MobileDevice/Provisioning Profiles"
TEAM_ID="92HEPEJ42Z"

# Exact bundle IDs we care about
BUNDLE_IDS=(
  "com.conornolan.Screen-Actions"
  "com.conornolan.Screen-Actions.ScreenActionsWebExtension"
  "com.conornolan.Screen-Actions.ScreenActionsShareExtension"
  "com.conornolan.Screen-Actions.ScreenActionsActionExtension"
)

mkdir -p "$DEST"

scanned=0
installed=0

for f in "$SRC_DIR"/*.mobileprovision(N); do
  (( scanned+=1 ))
  tmp="$(mktemp -t mp)"
  if ! /usr/bin/security cms -D -i "$f" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    continue
  fi

  appid=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$tmp" 2>/dev/null || echo "")
  uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$tmp" 2>/dev/null || echo "")
  name=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$tmp" 2>/dev/null || echo "")
  gtl=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$tmp" 2>/dev/null || echo "false")
  provAll=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$tmp" 2>/dev/null || echo "false")
  /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$tmp" >/dev/null 2>&1
  hasDevices=$?   # 0 if key exists → Ad Hoc; non-zero if not present

  rm -f "$tmp"

  [[ -z "$appid" || -z "$uuid" ]] && continue
  [[ "$appid" == $TEAM_ID.* ]] || continue

  bid="${appid#$TEAM_ID.}"

  wanted=0
  for b in $BUNDLE_IDS; do
    [[ "$bid" == "$b" ]] && wanted=1 && break
  done
  [[ $wanted -eq 1 ]] || continue

  # Keep ONLY App Store (Distribution) profiles:
  #  - get-task-allow == false
  #  - not Enterprise (ProvisionsAllDevices)
  #  - not Ad Hoc (no ProvisionedDevices array)
  [[ "$gtl" == "true" ]] && continue
  [[ "$provAll" == "true" ]] && continue
  [[ $hasDevices -eq 0 ]] && continue

  cp -f "$f" "$DEST/$uuid.mobileprovision"
  (( installed+=1 ))
  echo "Installed: $name → $uuid.mobileprovision  [${bid}]"
done

echo
echo "Scanned: $scanned file(s). Installed App Store profiles: $installed."
echo "Destination: $DEST"
