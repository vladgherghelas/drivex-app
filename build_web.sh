#!/bin/bash
set -e

# ── Find Flutter ─────────────────────────────────────────────────────────────
FLUTTER=""

# Common install locations (FVM, manual, Homebrew, asdf, snap)
CANDIDATES=(
  "$HOME/flutter/bin/flutter"
  "$HOME/development/flutter/bin/flutter"
  "$HOME/fvm/default/bin/flutter"
  "/usr/local/bin/flutter"
  "/opt/homebrew/bin/flutter"
  "/snap/flutter/current/bin/flutter"
)

for candidate in "${CANDIDATES[@]}"; do
  if [ -x "$candidate" ]; then
    FLUTTER="$candidate"
    break
  fi
done

# Try PATH (works if user opened a new terminal since installing Flutter)
if [ -z "$FLUTTER" ]; then
  FLUTTER=$(command -v flutter 2>/dev/null || true)
fi

# Last resort: scan Downloads and home for flutter binary
if [ -z "$FLUTTER" ]; then
  FLUTTER=$(find "$HOME" -maxdepth 6 -name "flutter" -type f -perm +111 2>/dev/null \
    | grep -v ".pub-cache" | grep -v ".dart_tool" | head -1 || true)
fi

if [ -z "$FLUTTER" ]; then
  echo "❌  Flutter not found. Please install it from https://flutter.dev/docs/get-started/install"
  exit 1
fi

echo "✅  Using Flutter at: $FLUTTER"
"$FLUTTER" --version

# ── Build ─────────────────────────────────────────────────────────────────────
echo ""
echo "🔨  Building Flutter web (release)…"
"$FLUTTER" build web --release

echo ""
echo "✅  Build complete! Output is in: build/web/"
echo "   Upload the contents of build/web/ to your hosting provider."
