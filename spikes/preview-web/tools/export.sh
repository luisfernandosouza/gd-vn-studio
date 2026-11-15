#!/usr/bin/env bash
# Exporta o spike para Web com o template oficial (build/web) e, se existir,
# com o template enxuto (build/web-lean, ver tools/build_lean_template.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
cd "$HERE/godot"
rm -rf vn_plugins/fishing && mkdir -p vn_plugins
cp -r ../../../docs/specs/examples/fishing-plugin vn_plugins/fishing
rm -rf vn_plugins/fishing/editor vn_plugins/fishing/tests
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p ../build/web && "$GODOT" --headless --path . --export-release "Web" ../build/web/index.html >/dev/null 2>&1
LEAN="$HERE/build/templates/web_lean_nothreads_release.zip"
if [ -f "$LEAN" ]; then
  cp export_presets.cfg /tmp/export_presets.cfg.bak
  sed -e 's|^name="Web"|name="Web Lean"|' -e "s|^custom_template/release=\"\"|custom_template/release=\"$LEAN\"|" \
      -e 's|^export_path=.*|export_path="../build/web-lean/index.html"|' /tmp/export_presets.cfg.bak > export_presets.cfg
  mkdir -p ../build/web-lean && "$GODOT" --headless --path . --export-release "Web Lean" ../build/web-lean/index.html >/dev/null 2>&1 || true
  cp /tmp/export_presets.cfg.bak export_presets.cfg
fi
ls -la ../build/web*/index.wasm
