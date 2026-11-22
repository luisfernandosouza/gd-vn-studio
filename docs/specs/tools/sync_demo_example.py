#!/usr/bin/env python3
"""Gera examples/demo-project/ a partir do repositório da demo (spec 09 §1.1, decisão D23).

O repositório gd-vn-studio-demo é a fonte dos dados do jogo. O exemplo das specs é
uma cópia só com os JSON, na versão da demo registrada em
examples/demo-project/SOURCE.json, com um único filtro:

- o campo `credit` dos assets (Data Model §10) sai de assets.json. Os créditos de
  terceiros ficam só na demo; o exemplo das specs não distribui arte nenhuma.

Só entram os arquivos de DATA_PATHS (os JSON da raiz e as pastas de dados do jogo).
A mesma lista é o sparse-checkout da CI (--sparse), para o script e a workflow verem
os mesmos arquivos. Tudo o mais fica de fora: assets/ (arte, música, sons e fontes),
tools/, source/, .vnstudio/, plugins/, migrations/, os .md, LICENSE e .gitignore.

A comparação é byte a byte. O filtro reescreve assets.json no formato padrão dos
projetos (JSON com indentação de 2 espaços, UTF-8 sem escapes e \n no fim), que a
demo também usa.

Uso:
  python3 tools/sync_demo_example.py <pasta-da-demo>                  # reescreve o exemplo
  python3 tools/sync_demo_example.py <pasta-da-demo> --check          # só confere; sai com 1 se divergir
  python3 tools/sync_demo_example.py <pasta-da-demo> --update-source  # reescreve e grava o commit novo em SOURCE.json
  python3 tools/sync_demo_example.py --sparse                         # imprime o sparse-checkout da CI

A pasta da demo tem de ser um clone Git no commit de SOURCE.json; o script confere
(git rev-parse HEAD) e para se não for, a menos que receba --update-source.
"""
import json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXAMPLE = HERE.parent / "examples" / "demo-project"
SOURCE = EXAMPLE / "SOURCE.json"
DATA_DIRS = ("chapters", "characters", "locales", "scenes", "sets", "ui")   # pastas de dados do jogo (Data Model §2)
KEEP_IN_EXAMPLE = {"SOURCE.json"}      # arquivos que só o exemplo tem


def sparse_patterns():
    return ["/*.json"] + [f"/{d}/" for d in DATA_DIRS]


def demo_files(demo):
    for p in sorted(demo.rglob("*.json")):
        rel = p.relative_to(demo)
        if len(rel.parts) == 1 or rel.parts[0] in DATA_DIRS:
            yield rel


def demo_head(demo):
    try:
        return subprocess.run(["git", "-C", str(demo), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


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
    if "--sparse" in argv:
        print("\n".join(sparse_patterns())); return 0
    if not argv or argv[0].startswith("-"):
        print(__doc__); return 2
    demo = Path(argv[0]).resolve()
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    head = demo_head(demo)
    if head is None:
        print(f"{demo} não é um clone Git: não dá para saber em que commit da demo ele está."); return 2
    if head != source["commit"] and "--update-source" not in argv:
        print(f"A demo está em {head[:12]}, mas SOURCE.json pede {source['commit'][:12]}. "
              "Faça o checkout desse commit ou rode com --update-source para trocar a versão de propósito."); return 2
    want = expected(demo)
    if "--check" in argv:
        have = current()
        diffs = sorted(set(want) ^ set(have)) + sorted(k for k in set(want) & set(have) if want[k] != have[k])
        for d in diffs: print("DIVERGE", d)
        print(f"{'O exemplo confere com a demo.' if not diffs else f'{len(diffs)} arquivo(s) divergem da demo: rode tools/sync_demo_example.py sem --check.'}")
        return 1 if diffs else 0
    for rel in current():
        (EXAMPLE / rel).unlink()
    for rel, text in want.items():
        out = EXAMPLE / rel; out.parent.mkdir(parents=True, exist_ok=True); out.write_text(text, encoding="utf-8")
    for d in sorted(EXAMPLE.rglob("*"), reverse=True):
        if d.is_dir() and not any(d.iterdir()): d.rmdir()
    if head != source["commit"]:
        source["commit"] = head
        SOURCE.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"SOURCE.json agora aponta para {head}.")
    print(f"{len(want)} arquivos copiados da demo.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
