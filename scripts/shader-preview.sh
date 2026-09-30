#!/bin/zsh
# Renders an image (e.g. a screenshot of a slide) through the dark-mode shader.
#   ./scripts/shader-preview.sh [input.png] [output.png] [scale]
set -euo pipefail
ROOT="${0:A:h:h}"
OUT_DIR="$HOME/Library/Caches/DarkmodeWindow-build/shader-preview"
mkdir -p "$OUT_DIR"
swiftc -O -o "$OUT_DIR/shader-preview" \
    "$ROOT/Sources/DarkmodeWindow/Shaders.swift" \
    "$ROOT/Sources/DarkmodeWindow/DarkFilter.swift" \
    "$ROOT/Tools/ShaderPreview/main.swift" 2>&1 | grep -v "warning" || true
"$OUT_DIR/shader-preview" "$@"
