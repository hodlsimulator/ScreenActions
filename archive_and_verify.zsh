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

# Choose a formatter if available (prefer xcbeautify, then xcpretty; else plain)
FMT=""
if command -v xcbeautify >/dev/null 2>&1; then
  FMT="xcbeautify"
elif command -v xcpretty >/dev/null 2>&1; then
  FMT="xcpretty"
fi

set -o pipefail
if [[ -n "${FMT}" ]]; then
  xcodebuild archive \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
  | ${FMT}
  STATUS=${pipestatus[1]}   # exit code of xcodebuild in the pipeline
else
  xcodebuild archive \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates
  STATUS=$?
fi

if [[ ${STATUS} -ne 0 ]]; then
  echo "✗ xcodebuild archive failed (status ${STATUS})"
  exit ${STATUS}
fi

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  echo "✗ Archive failed (no .xcarchive at ${ARCHIVE_PATH})"
  exit 1
fi

echo "→ Verifying entitlements & Info.plist inside archive…"
ruby tools/verify_archive_entitlements.rb "${ARCHIVE_PATH}"

echo "✔ Archive + entitlement verification complete."
