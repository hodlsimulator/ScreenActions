#
//  archive_and_verify.zsh
//  Screen Actions
//
//  Created by . . on 9/17/25.
//

#!/bin/zsh
set -euo pipefail

SCHEME="Screen Actions"
CONFIG="Release"
OUTDIR=".provtmp"
ARCHIVE_PATH="${OUTDIR}/ScreenActions.xcarchive"

echo "→ Cleaning ${OUTDIR}…"
rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}"

echo "→ Archiving (${SCHEME}, ${CONFIG})…"
xcodebuild archive \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  | xcpretty || true

if [ ! -d "${ARCHIVE_PATH}" ]; then
  echo "✗ Archive failed (no .xcarchive at ${ARCHIVE_PATH})"
  exit 1
fi

echo "→ Verifying entitlements & Info.plist inside archive…"
ruby tools/verify_archive_entitlements.rb "${ARCHIVE_PATH}"

echo "✔ Archive + entitlement verification complete."
