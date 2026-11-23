#!/usr/bin/env python3
"""Gera o .pck de um plugin como o Studio geraria no Preview (PP §1.3, SDK §10.6).

O Studio mantém uma cópia do plugin em `.vnstudio/preview/plugins/<namespace>/`, que é um
projeto Godot mínimo: `project.godot`, o Runtime SDK em `addons/` (só para o parser resolver
VNRuntimePlugin e companhia; fica fora do pacote) e o plugin em `vn_plugins/<namespace>/`.
A cada salvamento: sincroniza os arquivos alterados e gera o pacote, por um de dois caminhos:

- `--mode export`: `godot --headless --export-pack` (o export do editor; importa o que mudou antes).
- `--mode fast` (padrão): `godot --headless --script tools/pack_plugin.gd`, sem abrir o editor; o import
  headless (`--import`) só roda na primeira vez ou quando um asset do plugin (imagem, som, fonte) muda.

Uso:
  make_pck.py --plugin <pasta do plugin> --namespace fishing --work <pasta> --out fishing.pck
  make_pck.py ... --variant v2          # descomenta as linhas "#v2 " (pacote v2 do plugin de prova)
  make_pck.py ... --bench 10            # 1 geração a frio + 10 a quente (um .gd alterado cada vez)
  make_pck.py ... --mode export         # caminho do export do editor, para comparar
"""

from __future__ import annotations

import argparse
import filecmp
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
SDK = HERE / "host" / "addons" / "vn_runtime_sdk"

PROJECT = """config_version=5

[application]

config/name="vnpreview-plugin-pack"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"""

# Um preset Web basta para o painel e a janela: o pacote só tem scripts, cenas e recursos
# importados; as texturas saem com a compressão de desktop, que os dois aceitam.
PRESETS = """[preset.0]

name="Pack"
platform="Web"
runnable=false
export_filter="all_resources"
include_filter=""
exclude_filter="addons/*"
export_path=""

[preset.0.options]

variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
"""

SKIP_DIRS = {"editor", "tests", ".git"}
TEXT_EXT = {".gd", ".tscn", ".tres", ".json", ".gdshader", ".txt", ".csv", ".cfg", ".md"}
PACK_SCRIPT = HERE / "tools" / "pack_plugin.gd"


def sync_plugin(src: Path, dst: Path, variant: str | None) -> tuple[int, int]:
    """Copia só o que mudou (mantém o cache de import a quente).
    Devolve (arquivos que mudaram, assets que mudaram e precisam de import)."""
    changed = 0
    assets = 0
    wanted: set[Path] = set()
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            s = Path(root) / name
            rel = s.relative_to(src)
            wanted.add(rel)
            d = dst / rel
            data = s.read_bytes()
            if variant == "v2" and s.suffix == ".gd":
                data = data.replace(b"\t#v2 ", b"\t").replace(b"const VERSION := 1", b"const VERSION := 2")
            if d.exists() and d.read_bytes() == data:
                continue
            d.parent.mkdir(parents=True, exist_ok=True)
            d.write_bytes(data)
            changed += 1
            if s.suffix not in TEXT_EXT:
                assets += 1
    if variant == "v2":
        extra = dst / "runtime" / "src" / "probe_extra.gd"
        wanted.add(extra.relative_to(dst))
        text = 'class_name ProbeExtra\nextends RefCounted\n\n\nfunc hello() -> String:\n\treturn "extra"\n'
        if not extra.exists() or extra.read_text() != text:
            extra.write_text(text)
            changed += 1
    for root, _dirs, files in os.walk(dst):
        for name in files:
            p = Path(root) / name
            rel = p.relative_to(dst)
            if rel not in wanted and not name.endswith((".uid", ".import")):
                p.unlink()
                changed += 1
    return changed, assets


def prepare(work: Path) -> None:
    work.mkdir(parents=True, exist_ok=True)
    (work / "project.godot").write_text(PROJECT) if not (work / "project.godot").exists() else None
    (work / "export_presets.cfg").write_text(PRESETS) if not (work / "export_presets.cfg").exists() else None
    sdk_dst = work / "addons" / "vn_runtime_sdk"
    sdk_dst.mkdir(parents=True, exist_ok=True)
    for f in SDK.glob("*.gd"):
        d = sdk_dst / f.name
        if not d.exists() or not filecmp.cmp(f, d, shallow=False):
            shutil.copy2(f, d)


def run(godot: str, args: list[str]) -> tuple[float, str]:
    t0 = time.perf_counter()
    p = subprocess.run([godot, "--headless", *args], capture_output=True, text=True)
    ms = (time.perf_counter() - t0) * 1000
    log = p.stdout + p.stderr
    if p.returncode != 0:
        sys.stderr.write(log)
        raise SystemExit(f"godot {' '.join(args)} saiu com {p.returncode}")
    return ms, log


def build(godot: str, plugin: Path, ns: str, work: Path, out: Path, variant: str | None, mode: str) -> dict:
    t0 = time.perf_counter()
    cold = not (work / ".godot").exists()
    prepare(work)
    changed, assets = sync_plugin(plugin, work / "vn_plugins" / ns, variant)
    sync_ms = (time.perf_counter() - t0) * 1000
    out.parent.mkdir(parents=True, exist_ok=True)
    import_ms, log1 = 0.0, ""
    if mode == "export":
        # O export do editor importa sozinho o que mudou antes de empacotar.
        export_ms, log2 = run(godot, ["--path", str(work), "--export-pack", "Pack", str(out.resolve())])
    else:
        if cold or assets:
            import_ms, log1 = run(godot, ["--path", str(work), "--import"])
        export_ms, log2 = run(godot, ["--path", str(work), "--script", str(PACK_SCRIPT), "--", "--ns", ns, "--out", str(out.resolve())])
    errors = [l for l in (log1 + log2).splitlines() if "ERROR" in l]
    return {
        "mode": mode,
        "changed_files": changed,
        "changed_assets": assets,
        "sync_ms": round(sync_ms, 1),
        "import_ms": round(import_ms, 1),
        "pack_ms": round(export_ms, 1),
        "total_ms": round(sync_ms + import_ms + export_ms, 1),
        "size": out.stat().st_size,
        "errors": errors,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugin", required=True, type=Path)
    ap.add_argument("--namespace", required=True)
    ap.add_argument("--work", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--variant")
    ap.add_argument("--bench", type=int, default=0)
    ap.add_argument("--mode", choices=["fast", "export"], default="fast")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    a = ap.parse_args()

    if not a.bench:
        print(json.dumps(build(a.godot, a.plugin, a.namespace, a.work, a.out, a.variant, a.mode)))
        return

    shutil.rmtree(a.work, ignore_errors=True)
    cold = build(a.godot, a.plugin, a.namespace, a.work, a.out, a.variant, a.mode)
    # "Salvamento": o autor muda um .gd do plugin. Altera a cópia de trabalho do plugin
    # numa pasta temporária, para não mexer no repositório.
    tmp = a.work.parent / (a.work.name + "-src")
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(a.plugin, tmp)
    target = next(p for p in sorted(tmp.rglob("*.gd")) if "/tests/" not in str(p) and "/editor/" not in str(p))
    warm = []
    for i in range(a.bench):
        target.write_text(target.read_text() + f"\n# salvamento {i}\n")
        warm.append(build(a.godot, tmp, a.namespace, a.work, a.out, a.variant, a.mode))
    shutil.rmtree(tmp, ignore_errors=True)
    totals = sorted(w["total_ms"] for w in warm)

    def pct(p: float) -> float:
        return totals[min(len(totals) - 1, int(round(p * (len(totals) - 1))))]

    print(json.dumps({
        "plugin": a.namespace,
        "mode": a.mode,
        "cold": cold,
        "warm_n": len(warm),
        "warm_p50_ms": pct(0.5),
        "warm_p95_ms": pct(0.95),
        "warm_mean_import_ms": round(statistics.mean(w["import_ms"] for w in warm), 1),
        "warm_mean_pack_ms": round(statistics.mean(w["pack_ms"] for w in warm), 1),
        "warm_errors": sorted({e for w in warm for e in w["errors"]}),
    }))


if __name__ == "__main__":
    main()
