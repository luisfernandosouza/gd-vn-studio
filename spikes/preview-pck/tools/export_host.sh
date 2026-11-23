#!/usr/bin/env bash
# Exporta o "runtime" do spike (host/): Web com o template oficial (build/web/official), Web com o
# template enxuto se LEAN_TEMPLATE apontar para ele (build/web/lean) e o pacote nativo
# (build/native/runtime-preview.pck, aberto com --main-pack, PP §1.2).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
LEAN="${LEAN_TEMPLATE:-}"
cd "$HERE/host"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p ../build/web/official ../build/native
"$GODOT" --headless --path . --export-release "Web" ../build/web/official/index.html
"$GODOT" --headless --path . --export-pack "Linux" ../build/native/runtime-preview.pck
if [ -n "$LEAN" ] && [ -f "$LEAN" ]; then
  cp export_presets.cfg export_presets.cfg.bak
  trap 'mv export_presets.cfg.bak export_presets.cfg' EXIT
  sed -i.tmp -e "s|^custom_template/release=\"\"|custom_template/release=\"$(realpath "$LEAN")\"|" export_presets.cfg
  rm -f export_presets.cfg.tmp
  mkdir -p ../build/web/lean
  "$GODOT" --headless --path . --export-release "Web" ../build/web/lean/index.html
fi
ls -la ../build/web/*/index.wasm ../build/native/
