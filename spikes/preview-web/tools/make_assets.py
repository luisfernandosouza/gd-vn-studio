#!/usr/bin/env python3
"""Gera os assets sintéticos do teste B (D18, PP §1.3): 200 imagens de 1920 × 1080
e 30 músicas, mais as variantes usadas na troca de um asset em uso.

As imagens imitam arte de fundo (gradiente suave, formas e um pouco de ruído),
para que os PNG tenham o tamanho de um fundo real (2 a 3 MB), e não o de uma cor
lisa. Cada imagem tem um bloco 16 × 16 no canto com uma cor-marca, que o runtime
devolve depois de decodificar: assim a bancada confere que leu o arquivo certo.

Formatos: 140 PNG, 40 JPG e 20 WebP; 24 OGG Vorbis e 6 MP3 de 3 min (precisa do
ffmpeg com libvorbis e libmp3lame). Alguns nomes têm acento e espaço, para testar a
codificação dos segmentos do caminho (PP §1.3).

Grava em <saída>/files/ a pasta assets/ do "projeto" e em <saída>/map.json o mapa
{id → res://vn_content/assets/…} como o bundle traz (D24), com as marcas.

Uso: python3 tools/make_assets.py build/assets [imagens] [músicas] [segundos]
"""
import json, subprocess, sys
from pathlib import Path

import numpy as np
from PIL import Image

out = Path(sys.argv[1] if len(sys.argv) > 1 else "build/assets")
N_IMG = int(sys.argv[2]) if len(sys.argv) > 2 else 200
N_MUS = int(sys.argv[3]) if len(sys.argv) > 3 else 30
SECONDS = int(sys.argv[4]) if len(sys.argv) > 4 else 180
W, H = 1920, 1080
PREFIX = "res://vn_content/assets/"
files = out / "files"
rng = np.random.default_rng(20261122)


def marker(i, variant=0):
    # Cores bem separadas, para sobreviver à compressão do JPG e do WebP.
    return [(i * 37) % 200 + 28, (i * 91 + variant * 120) % 200 + 28, 40 + variant * 90]


def picture(i, variant=0):
    small = rng.random((9, 16, 3)) * 255
    img = np.asarray(Image.fromarray(small.astype(np.uint8)).resize((W, H), Image.BICUBIC), dtype=np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    for _ in range(6):
        cx, cy, r = rng.integers(0, W), rng.integers(0, H), rng.integers(80, 400)
        mask = ((xx - cx) ** 2 + (yy - cy) ** 2) < r * r
        img[mask] = img[mask] * 0.5 + rng.random(3) * 127
    img += rng.normal(0, 3.0, img.shape)
    img = np.clip(img, 0, 255).astype(np.uint8)
    img[0:16, 0:16] = marker(i, variant)
    return Image.fromarray(img, "RGB")


def image_path(i):
    fmt = "png" if i < int(N_IMG * 0.7) else ("jpg" if i < int(N_IMG * 0.9) else "webp")
    folder = "cenários" if i % 10 == 3 else "bg"
    name = f"praia à noite {i:03d}" if i % 10 == 7 else f"bg_{i:03d}"
    return f"{folder}/{name}.{fmt}"


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    ext = path.suffix[1:]
    if ext == "png":
        img.save(path, "PNG", compress_level=6)
    elif ext == "jpg":
        img.save(path, "JPEG", quality=90)
    else:
        img.save(path, "WEBP", quality=85)


def music(path, i, seconds):
    path.parent.mkdir(parents=True, exist_ok=True)
    f1, f2 = 110 + i * 7, 220 + i * 11
    src = (f"sine=f={f1}:d={seconds}[a];sine=f={f2}:d={seconds}[b];"
           f"anoisesrc=c=pink:a=0.08:d={seconds}:seed={i}[n];[a][b][n]amix=inputs=3,aformat=channel_layouts=stereo")
    codec = ["-c:a", "libvorbis", "-q:a", "5"] if path.suffix == ".ogg" else ["-c:a", "libmp3lame", "-b:a", "192k"]
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-filter_complex", src, "-ar", "44100", *codec, str(path)], check=True)


assets, kinds, markers, lengths = {}, {}, {}, {}
for i in range(N_IMG):
    rel = image_path(i)
    p = files / rel
    if not p.exists():
        save(picture(i), p)
    aid = f"bg_{i:03d}"
    assets[aid], kinds[aid], markers[aid] = PREFIX + rel, "image", marker(i)

for i in range(N_MUS):
    rel = f"music/{'tema da praia ' if i % 10 == 5 else 'track_'}{i:02d}.{'mp3' if i >= int(N_MUS * 0.8) else 'ogg'}"
    p = files / rel
    if not p.exists():
        music(p, i, SECONDS)
    aid = f"music_{i:02d}"
    assets[aid], kinds[aid], lengths[aid] = PREFIX + rel, "music", SECONDS

# Variantes para a troca de um asset em uso: o Studio copia uma delas por cima do
# arquivo do autor (como se o autor salvasse de novo no editor de imagem).
swap, restore = {}, {}
img_id, mus_id = "bg_010", "music_03"   # um PNG e um OGG
for aid in (img_id, mus_id):
    rel = assets[aid][len(PREFIX):]
    keep = f"_variants/{aid}.v0{Path(rel).suffix}"
    if not (files / keep).exists():
        (files / keep).parent.mkdir(parents=True, exist_ok=True)
        (files / keep).write_bytes((files / rel).read_bytes())
    restore[aid] = keep
for v in (1, 2):
    rel = f"_variants/{img_id}.v{v}{Path(assets[img_id]).suffix}"
    if not (files / rel).exists():
        save(picture(10, v), files / rel)
    swap.setdefault(img_id, []).append({"file": rel, "marker": marker(10, v)})
    rel = f"_variants/{mus_id}.v{v}{Path(assets[mus_id]).suffix}"
    if not (files / rel).exists():
        music(files / rel, 3 + v * 40, SECONDS // 3 * v)
    swap.setdefault(mus_id, []).append({"file": rel, "length": SECONDS // 3 * v})

sizes = {k: sum(f.stat().st_size for f in files.rglob(f"*.{k}") if "_variants" not in f.parts) for k in ("png", "jpg", "webp", "ogg", "mp3")}
(out / "map.json").write_text(json.dumps({
    "prefix": PREFIX, "assets": assets, "kinds": kinds, "markers": markers, "lengths": lengths,
    "swap": swap, "restore": restore,
    "bytes": sizes,
}, ensure_ascii=False, indent=1), encoding="utf-8")
print(json.dumps({k: f"{v / 1e6:.1f} MB" for k, v in sizes.items()}))
