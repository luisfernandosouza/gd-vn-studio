#!/usr/bin/env bash
# Exporta o spike para Web com o template oficial (build/web).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
cd "$HERE/godot"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p ../build/web && "$GODOT" --headless --path . --export-release "Web" ../build/web/index.html >/dev/null 2>&1
ls -la ../build/web/index.wasm
