#!/usr/bin/env bash
# Compila o template Web enxuto do Preview: o oficial sem 3D e sem os módulos que o runtime de VN
# não usa. Mesma lista do spike de 2026-11-15 (spikes/preview-web, no histórico do Git), conferida
# contra o que o runtime precisa: ficam svg, webp, jpg, ogg/vorbis, minimp3, freetype,
# text_server_adv, regex, mbedtls e jsonrpc.
# Precisa do código do Godot 4.7.2, do emsdk 4.0.11 ativo (versão da CI do Godot) e do scons.
# Uso: tools/build_lean_template.sh <pasta-do-godot-src> <saída.zip>
set -euo pipefail
SRC="$1"; OUT="$(realpath -m "$2")"
OFF=""
for m in astcenc basis_universal bcdec betsy bmp camera csg cvtt dds enet etcpak fbx glslang gltf \
         godot_physics_3d gridmap hdr jolt_physics ktx lightmapper_rd meshoptimizer mobile_vr mono \
         multiplayer navigation_3d objectdb_profiler openxr raycast tga tinyexr upnp vhacd visual_shader \
         webrtc websocket webxr xatlas_unwrap zip; do OFF="$OFF module_${m}_enabled=no"; done
cd "$SRC"
# shellcheck disable=SC2086
scons platform=web target=template_release threads=no arch=wasm32 disable_3d=yes optimize=size deprecated=no $OFF -j"$(nproc)"
mkdir -p "$(dirname "$OUT")"
cp bin/godot.web.template_release.wasm32.nothreads.zip "$OUT"
