#!/bin/bash
#
# generate-icons.sh
# Converts SVG source icons to PNG for the DUMPSTER PWA.
#
# This script tries multiple strategies:
#   1. Node.js + sharp (best quality, via generate-icons.js)
#   2. rsvg-convert (if installed via brew)
#   3. macOS qlmanage (built-in, decent quality)
#
# Usage:
#   cd dumpster
#   bash scripts/generate-icons.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLIC_DIR="$PROJECT_DIR/public"
SVG_DIR="$SCRIPT_DIR/svg-sources"

echo "DUMPSTER Icon Generator (shell)"
echo "================================"
echo ""
echo "Output: $PUBLIC_DIR"
echo ""

# Map of SVG source -> PNG output
declare -A ICONS
ICONS=(
  ["icon-192.svg"]="icon-192.png"
  ["icon-512.svg"]="icon-512.png"
  ["apple-touch-icon.svg"]="apple-touch-icon.png"
  ["icon-maskable-192.svg"]="icon-maskable-192.png"
  ["icon-maskable-512.svg"]="icon-maskable-512.png"
)

# Corresponding sizes
declare -A SIZES
SIZES=(
  ["icon-192.svg"]=192
  ["icon-512.svg"]=512
  ["apple-touch-icon.svg"]=180
  ["icon-maskable-192.svg"]=192
  ["icon-maskable-512.svg"]=512
)

# Strategy 1: Try node + sharp
if command -v node &>/dev/null; then
  echo "Found node. Trying generate-icons.js..."
  if node "$SCRIPT_DIR/generate-icons.js"; then
    echo ""
    echo "Done (via Node.js + sharp)."
    exit 0
  fi
  echo "Node.js method failed. Trying fallback..."
  echo ""
fi

# Strategy 2: Try rsvg-convert
if command -v rsvg-convert &>/dev/null; then
  echo "Using rsvg-convert..."
  for svg in "${!ICONS[@]}"; do
    png="${ICONS[$svg]}"
    size="${SIZES[$svg]}"
    rsvg-convert -w "$size" -h "$size" "$SVG_DIR/$svg" -o "$PUBLIC_DIR/$png"
    echo "  [OK] $png (${size}x${size})"
  done
  echo ""
  echo "Done (via rsvg-convert)."
  exit 0
fi

# Strategy 3: macOS qlmanage
if command -v qlmanage &>/dev/null; then
  echo "Using macOS qlmanage..."
  TMPDIR_QL=$(mktemp -d)
  for svg in "${!ICONS[@]}"; do
    png="${ICONS[$svg]}"
    size="${SIZES[$svg]}"
    qlmanage -t -s "$size" -o "$TMPDIR_QL" "$SVG_DIR/$svg" &>/dev/null
    # qlmanage outputs as <filename>.svg.png
    ql_output="$TMPDIR_QL/${svg}.png"
    if [ -f "$ql_output" ]; then
      # Resize to exact dimensions using sips
      sips -z "$size" "$size" "$ql_output" --out "$PUBLIC_DIR/$png" &>/dev/null
      echo "  [OK] $png (${size}x${size})"
    else
      echo "  [FAIL] $png - qlmanage did not produce output"
    fi
  done
  rm -rf "$TMPDIR_QL"
  echo ""
  echo "Done (via qlmanage + sips)."
  exit 0
fi

echo "ERROR: No conversion tool found."
echo "Install one of:"
echo "  - npm install sharp (then: node scripts/generate-icons.js)"
echo "  - brew install librsvg (then: bash scripts/generate-icons.sh)"
echo ""
echo "Or use the SVG sources directly from: $SVG_DIR"
exit 1
