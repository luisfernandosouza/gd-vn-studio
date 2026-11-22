#!/usr/bin/env python3
"""Gera examples/demo-project/ a partir do repositório da demo (spec 09 §1.1, decisão D23).

O repositório gd-vn-studio-demo é a fonte dos dados do jogo. O exemplo das specs é
uma cópia só com os JSON, na versão da demo registrada em
examples/demo-project/SOURCE.json, com um único filtro:

- o campo `credit` dos assets (Data Model §10) sai de assets.json. Os créditos de
  terceiros ficam só na demo; o exemplo das specs não distribui arte nenhuma.

Ficam de fora os arquivos que não são dados do jogo: assets/ (arte, música, sons e
fontes), tools/, source/, os .md, LICENSE e .gitignore.

Uso:
  python3 tools/sync_demo_example.py <pasta-da-demo>            # reescreve o exemplo
  python3 tools/sync_demo_example.py <pasta-da-demo> --check    # só confere; sai com 1 se divergir

A pasta da demo tem de estar no commit de SOURCE.json (a CI faz o checkout dele).
"""
import json, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXAMPLE = HERE.parent / "examples" / "demo-project"
SKIP_DIRS = {"assets", "tools", "source", ".git", ".github"}
KEEP_IN_EXAMPLE = {"SOURCE.json"}      # arquivos que só o exemplo tem


def demo_files(demo):
    for p in sorted(demo.rglob("*.json")):
        rel = p.relative_to(demo)
        if rel.parts[0] in SKIP_DIRS: continue
        yield rel


def filtered(rel, data):
    if rel.as_posix() == "assets.json":
        for a in data.get("assets", {}).values(): a.pop("credit", None)
    return data


def render(data):
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def expected(demo):
    """Texto esperado de cada arquivo: igual ao da demo, byte a byte, salvo quando o filtro muda o conteúdo."""
    out = {}
    for rel in demo_files(demo):
        raw = (demo / rel).read_text(encoding="utf-8")
        data = json.loads(raw)
        new = filtered(rel, json.loads(raw))
        out[rel.as_posix()] = raw if new == data else render(new)
    return out


def current():
    return {p.relative_to(EXAMPLE).as_posix(): p.read_text(encoding="utf-8")
            for p in sorted(EXAMPLE.rglob("*.json")) if p.name not in KEEP_IN_EXAMPLE}


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__); return 2
    demo = Path(argv[0]).resolve()
    want = expected(demo)
    if "--check" in argv:
        have = current()
        diffs = sorted(set(want) ^ set(have)) + sorted(k for k in set(want) & set(have) if json.loads(want[k]) != json.loads(have[k]))
        for d in diffs: print("DIVERGE", d)
        print(f"{'O exemplo confere com a demo.' if not diffs else f'{len(diffs)} arquivo(s) divergem da demo: rode tools/sync_demo_example.py sem --check.'}")
        return 1 if diffs else 0
    for rel in current():
        (EXAMPLE / rel).unlink()
    for rel, text in want.items():
        out = EXAMPLE / rel; out.parent.mkdir(parents=True, exist_ok=True); out.write_text(text, encoding="utf-8")
    for d in sorted(EXAMPLE.rglob("*"), reverse=True):
        if d.is_dir() and not any(d.iterdir()): d.rmdir()
    print(f"{len(want)} arquivos copiados da demo.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
