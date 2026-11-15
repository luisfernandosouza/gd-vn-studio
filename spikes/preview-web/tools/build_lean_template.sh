#!/usr/bin/env bash
# Compila o template Web enxuto (otimização 4): sem 3D e sem módulos que o
# runtime de VN não usa. Precisa do código-fonte do Godot 4.7.2, do emsdk 4.0.11
# (versão da CI do Godot) e do scons. Leva ~13 min em 4 núcleos.
# Uso: tools/build_lean_template.sh <pasta-do-godot-src>
set -euo pipefail
SRC="$1"; HERE="$(cd "$(dirname "$0")/.." && pwd)"
OFF=""
for m in astcenc basis_universal bcdec betsy bmp camera csg cvtt dds enet etcpak fbx glslang gltf \
         godot_physics_3d gridmap hdr jolt_physics ktx lightmapper_rd meshoptimizer mobile_vr mono \
         multiplayer navigation_3d objectdb_profiler openxr raycast tga tinyexr upnp vhacd visual_shader \
         webrtc websocket webxr xatlas_unwrap zip; do OFF="$OFF module_${m}_enabled=no"; done
cd "$SRC"
scons platform=web target=template_release threads=no arch=wasm32 disable_3d=yes optimize=size deprecated=no $OFF -j"$(nproc)"
mkdir -p "$HERE/build/templates"
cp bin/godot.web.template_release.wasm32.nothreads.zip "$HERE/build/templates/web_lean_nothreads_release.zip"
