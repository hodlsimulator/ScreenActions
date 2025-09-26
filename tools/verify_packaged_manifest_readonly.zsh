#!/bin/zsh
# Read-only check; no writes to product or repo; no failures that cause cycles.
set -euo pipefail

SRC="$SRCROOT/ScreenActionsWebExtension/WebRes/manifest.json"
PKG="$TARGET_BUILD_DIR/$WRAPPER_NAME/WebRes/manifest.json"
STAMP="$DERIVED_FILE_DIR/webres_manifest_verified.stamp"

mkdir -p -- "${STAMP:h}"

# First pass during the build graph: files might not exist yet.
if [[ ! -f "$SRC" || ! -f "$PKG" ]]; then
  : > "$STAMP"
  exit 0
fi

# Compare and log diff if different (non-fatal).
if ! /usr/bin/cmp -s "$SRC" "$PKG"; then
  echo "warn: packaged manifest differs from source (non-fatal diff):"
  /usr/bin/diff -u "$SRC" "$PKG" || true
fi

: > "$STAMP"
exit 0
