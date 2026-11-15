#!/usr/bin/env python3
"""Gera os bundles do spike: o demo (compilado pelo compilador de referência) e
um bundle grande sintético, com o mesmo formato, para medir a recarga num jogo
do tamanho de uma VN longa.

Uso: python3 tools/make_bundles.py <saída> [cenas] [falas-por-cena]
"""
import json, shutil, subprocess, sys, uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPECS = HERE.parents[2] / "docs" / "specs"
sys.path.insert(0, str(SPECS / "tools"))
try:
    from conformance import jcs  # noqa: E402  (depois do PR das correções da auditoria)
except ImportError:
    from compile_bundle import jcs  # noqa: E402
import base64, hashlib  # noqa: E402

WORDS = ("o mar estava calmo e a luz da tarde batia nas janelas da casa velha enquanto "
         "alguém lá fora chamava pelo nome de um amigo que não respondia").split()


def sri(text):
    return "sha256-" + base64.b64encode(hashlib.sha256(text.encode("utf-8")).digest()).decode()


def write(out, bundle, locales):
    out.mkdir(parents=True, exist_ok=True)
    raw = {k: v for k, v in bundle.items() if k != "content_hash"}
    bundle["content_hash"] = sri(jcs(raw))
    (out / "bundle.json").write_text(jcs(bundle), encoding="utf-8")
    (out / "locales").mkdir(exist_ok=True)
    for lang, strings in locales.items():
        (out / "locales" / f"{lang}.json").write_text(jcs({"locale": lang, "strings": strings}), encoding="utf-8")


def main():
    out = Path(sys.argv[1])
    n_scenes = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    n_lines = int(sys.argv[3]) if len(sys.argv) > 3 else 50
    demo = out / "demo"
    subprocess.run([sys.executable, str(SPECS / "tools" / "compile_bundle.py"), str(SPECS / "examples" / "demo-project"),
                    str(demo), str(SPECS / "examples" / "fishing-plugin")], check=True, stdout=subprocess.DEVNULL)
    bundle = json.loads((demo / "bundle.json").read_text(encoding="utf-8"))
    en = json.loads((demo / "locales" / "en.json").read_text(encoding="utf-8"))["strings"]
    chapter = bundle["project"]["start_chapter"]
    speaker = next(iter(bundle["characters"]))
    k = 0
    for s in range(n_scenes):
        sid = str(uuid.UUID(int=(0x019a7b00 << 96) | (s << 64) | 0x7000_8000_0000_0000))
        nodes = [{"asset": "bg/beach_day", "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{sid}/bg")), "type": "background"}]
        for i in range(n_lines):
            nid = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{sid}/{i}"))
            text = " ".join(WORDS[(k + j) % len(WORDS)] for j in range(14)).capitalize() + "."
            k += 1
            node = {"id": nid, "text": text, "type": "line"}
            if i % 2 == 0:
                node["speaker"] = speaker
            nodes.append(node)
            en[f"{sid}/{nid}"] = "[en] " + text
        nodes.append({"id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{sid}/end")), "type": "end", "then": "selection_point"})
        bundle["scenes"][sid] = {"chapter": chapter, "id": sid, "nodes": nodes, "start": nodes[0]["id"], "title": f"Cena {s}",
                                 "scheduling": {"cooldown": 0, "exclusive_groups": [], "max_plays": 1, "mode": "manual",
                                                "priority": 100, "weight": 1}, "variables": []}
    big = out / "big"
    if big.exists():
        shutil.rmtree(big)
    write(big, bundle, {"en": en})
    shutil.copy(demo / "plugins.json", big / "plugins.json")
    for d in (demo, big):
        print(d.name, f"{(d / 'bundle.json').stat().st_size / 1e6:.2f} MB", f"{len(json.loads((d / 'bundle.json').read_text())['scenes'])} cenas")


if __name__ == "__main__":
    main()
