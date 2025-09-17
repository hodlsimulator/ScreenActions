#!/bin/zsh
set -e
set -u
set -o pipefail

# Ensure unmatched globs expand to nothing (zsh) instead of erroring
setopt null_glob

echo "→ Writing .gitignore files…"

cat > .gitignore <<'EOF'
# Xcode & Swift
DerivedData/
build/
*.xcuserdatad/
*.xcscmblueprint
*.xccheckout
*.xcworkspace/xcuserdata/

# SwiftPM
.swiftpm/
.build/

# CocoaPods / Carthage
Pods/
Carthage/

# Provisioning cruft (local only)
.provtmp/
*.mobileprovision
*.mobileprovision.plist

# macOS cruft
.DS_Store

# Fastlane (if added later)
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots

# Logs
*.log
EOF

mkdir -p "Screen Actions"
cat > "Screen Actions/.gitignore" <<'EOF'
# Xcode & Swift
DerivedData/
build/
*.xcuserdatad/
*.xcscmblueprint
*.xccheckout
*.xcworkspace/xcuserdata/

# SwiftPM
.swiftpm/
.build/

# Provisioning cruft (local only)
.provtmp/
*.mobileprovision
*.mobileprovision.plist

# macOS cruft
.DS_Store

# Fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots

# Logs
*.log
EOF

echo "→ Creating .provtmp/"
mkdir -p .provtmp

echo "→ Moving any provisioning files into .provtmp (zsh-safe)…"
# Collect matches with null_glob so it's fine if nothing matches
typeset -a MOVE_CANDIDATES
MOVE_CANDIDATES=( ./*.mobileprovision* )
if (( ${#MOVE_CANDIDATES} )); then
  mv -- "${MOVE_CANDIDATES[@]}" .provtmp/
else
  echo "  (none found at repo root)"
fi

echo "→ Stopping Git from tracking those files (if any were committed)…"
# Quote globs so zsh doesn't expand; Git will handle the patterns
git rm -r --cached .provtmp 2>/dev/null || true
git rm -r --cached -- '*.mobileprovision' 2>/dev/null || true
git rm -r --cached -- '*.mobileprovision.plist' 2>/dev/null || true

echo "→ Committing ignore rules…"
git add .gitignore "Screen Actions/.gitignore" 2>/dev/null || true
if ! git diff --cached --quiet; then
  git commit -m "gitignore: ignore provisioning artefacts (.provtmp, *.mobileprovision*) and local cruft"
  # Push if this is a branch with an upstream
  (git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 && git push) || true
else
  echo "  (nothing new to commit)"
fi

echo "✔ Done."
