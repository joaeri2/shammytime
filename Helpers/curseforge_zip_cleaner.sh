cat > ~/clean_shammytime_zip.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

IN_ZIP="${1:-$HOME/Desktop/ShammyTime.zip}"
OUT_ZIP="${2:-$HOME/Desktop/ShammyTime-clean.zip}"

if [[ ! -f "$IN_ZIP" ]]; then
  echo "❌ Input zip not found: $IN_ZIP"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "📦 Unzipping: $IN_ZIP"
unzip -q "$IN_ZIP" -d "$TMP_DIR"

# Remove macOS junk + git stuff
echo "🧹 Removing macOS junk + git folders/files..."
find "$TMP_DIR" -name ".DS_Store" -type f -delete 2>/dev/null || true
find "$TMP_DIR" -name "__MACOSX" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$TMP_DIR" -name "._*" -type f -delete 2>/dev/null || true

# Remove git metadata and common repo-only files
find "$TMP_DIR" -name ".git" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$TMP_DIR" -name ".github" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$TMP_DIR" -name ".gitignore" -type f -delete 2>/dev/null || true
find "$TMP_DIR" -name ".gitattributes" -type f -delete 2>/dev/null || true
find "$TMP_DIR" -name ".gitmodules" -type f -delete 2>/dev/null || true

# Figure out whether the zip contains a single top-level folder (common for addons)
shopt -s nullglob dotglob
ITEMS=("$TMP_DIR"/*)

echo "🗜️ Repacking to: $OUT_ZIP"
rm -f "$OUT_ZIP"

if [[ ${#ITEMS[@]} -eq 1 && -d "${ITEMS[0]}" ]]; then
  # Keep the parent folder (so zip contains ShammyTime/...)
  (cd "$TMP_DIR" && ditto -c -k --sequesterRsrc --keepParent "${ITEMS[0]##*/}" "$OUT_ZIP")
else
  # Zip everything at top level
  (cd "$TMP_DIR" && ditto -c -k --sequesterRsrc . "$OUT_ZIP")
fi

echo "✅ Done."
echo "➡️ Output: $OUT_ZIP"
BASH

chmod +x ~/clean_shammytime_zip.sh
~/clean_shammytime_zip.sh