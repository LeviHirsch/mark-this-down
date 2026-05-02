#!/usr/bin/env bash
#
# install.sh — build MarkThisDown Release, install to ~/Applications,
# refresh LaunchServices, and (optionally) add an `mtd` alias to ~/.zshrc.
#
# Usage:
#   ./scripts/install.sh              # build + install + add alias
#   ./scripts/install.sh --no-alias   # skip alias step
#   ./scripts/install.sh --no-build   # skip rebuild (just reinstall)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MarkThisDown"
DEST="$HOME/Applications/${APP_NAME}.app"

ADD_ALIAS=1
DO_BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-alias) ADD_ALIAS=0 ;;
    --no-build) DO_BUILD=0 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

cd "$PROJECT_DIR"

if [[ "$DO_BUILD" == "1" ]]; then
  echo "→ Building Release config…"
  xcodebuild -project markthisdown.xcodeproj \
             -scheme markthisdown \
             -configuration Release \
             -destination 'platform=macOS' \
             clean build > /tmp/markthisdown-build.log 2>&1 \
    || { tail -40 /tmp/markthisdown-build.log; exit 1; }
fi

BUILT_APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
              -name 'markthisdown.app' -path '*Release*' \
              -print -quit 2>/dev/null)"
if [[ -z "$BUILT_APP" ]]; then
  echo "✗ Built app not found. Run without --no-build." >&2
  exit 1
fi

echo "→ Stopping any running instance…"
killall markthisdown MarkThisDown 2>/dev/null || true

echo "→ Installing to $DEST"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
echo "→ Refreshing LaunchServices…"
"$LSREGISTER" -f "$DEST"

if [[ "$ADD_ALIAS" == "1" ]]; then
  ZSHRC="$HOME/.zshrc"
  ALIAS_LINE="alias mtd='open -a MarkThisDown'"
  if grep -Fq "$ALIAS_LINE" "$ZSHRC" 2>/dev/null; then
    echo "→ Alias already present in ~/.zshrc"
  else
    {
      echo ""
      echo "# MarkThisDown — installed by scripts/install.sh"
      echo "$ALIAS_LINE"
    } >> "$ZSHRC"
    echo "→ Added alias to ~/.zshrc — run 'source ~/.zshrc' or open a new terminal."
  fi
fi

echo "✓ Done. Try: open -a MarkThisDown"
