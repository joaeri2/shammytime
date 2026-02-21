#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# package_curseforge.sh — Create a clean CurseForge-ready zip
# Run from anywhere:  bash Helpers/curseforge_zip_cleaner.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── Resolve addon root (one level up from Helpers/) ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADDON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADDON_NAME="$(basename "$ADDON_DIR")"

# ── Output location ──
OUT_ZIP="${1:-$HOME/Desktop/${ADDON_NAME}.zip}"

echo "📦 Packaging: $ADDON_NAME"
echo "   Source:    $ADDON_DIR"
echo "   Output:    $OUT_ZIP"
echo ""

# Prevent macOS from embedding resource forks in the zip
export COPYFILE_DISABLE=1

# Remove old zip if it exists
rm -f "$OUT_ZIP"

# ── Create the zip ──
# We cd to the parent of the addon folder so the zip contains
# a top-level ShammyTime/ directory (required by WoW addons).
cd "$ADDON_DIR/.."

/usr/bin/zip -rX "$OUT_ZIP" "$ADDON_NAME" \
  -x "${ADDON_NAME}/.git/*" \
  -x "${ADDON_NAME}/.git*" \
  -x "${ADDON_NAME}/.gitignore" \
  -x "${ADDON_NAME}/.gitattributes" \
  -x "${ADDON_NAME}/.gitmodules" \
  -x "${ADDON_NAME}/.github/*" \
  -x "${ADDON_NAME}/Helpers/*" \
  -x "${ADDON_NAME}/Screenshots/*" \
  -x "${ADDON_NAME}/docs/*" \
  -x "${ADDON_NAME}/README.md" \
  -x "${ADDON_NAME}/.cursor/*" \
  -x "*/.DS_Store" \
  -x "*__MACOSX*" \
  -x "*/._*" \
  -x "._*" \
  -x "*.swp" \
  -x "*.swo" \
  -x "*~"

echo ""
echo "✅ Done! Created: $OUT_ZIP"

# ── Verify: list contents and check for junk ──
echo ""
echo "📋 Zip contents:"
unzip -l "$OUT_ZIP" | awk 'NR>3 && /\// {print $NF}'
echo ""

# Final sanity check
if unzip -l "$OUT_ZIP" | grep -qE "__MACOSX|\._|\.git|\.DS_Store|/Helpers/|/Screenshots/|/docs/"; then
  echo "⚠️  Warning: unwanted files may still be present — check the listing above."
else
  echo "✅ Clean — no macOS junk, git files, or dev-only folders found."
fi

# Show zip size
ZIP_SIZE=$(du -h "$OUT_ZIP" | cut -f1)
echo "📏 Zip size: $ZIP_SIZE"
