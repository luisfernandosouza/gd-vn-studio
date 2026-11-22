#!/usr/bin/env python3
"""Vetores de compilação (spec 08 §1, Build System §5.1).

Cada caso parte do projeto congelado em conformance/compile/base/ (demo-project e
fishing-plugin, uma cópia fixa do exemplo das specs que não acompanha a demo), aplica as
trocas de `edits` (JSON Pointer, RFC 6901) e compila com tools/compile_bundle.py.
O resultado tem de bater com `expect`: o content_hash do bundle.json, o hash do
JCS de cada locales/<lang>.json e de plugins.json, e os ponteiros que precisam
existir (`present`) ou faltar (`absent`) no bundle.

O compilador do Studio (TypeScript) DEVE dar os mesmos hashes nos mesmos casos,
compilando o projeto inteiro e também aplicando as entidades compiladas uma a
uma sobre o bundle-base (recarga incremental do Preview, Preview Protocol §3).

Uso: python3 tools/test_compile.py [--print]   (--print mostra os hashes obtidos)
"""
import json, shutil, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compile_bundle as cb  # noqa: E402

SPECS = HERE.parent
CASES = SPECS / "conformance" / "compile" / "cases.json"
BASE = SPECS / "conformance" / "compile" / "base"


def unescape(tok): return tok.replace("~1", "/").replace("~0", "~")


def apply_edit(root, e):
    p = root / e["file"]
    doc = json.loads(p.read_text(encoding="utf-8"))
    toks = [unescape(t) for t in e["pointer"].split("/")[1:]]
    cur = doc
    for t in toks[:-1]:
        cur = cur[int(t)] if isinstance(cur, list) else cur.setdefault(t, {})
    last = toks[-1]
    if "value" in e:
        if isinstance(cur, list): cur.insert(len(cur) if last == "-" else int(last), e["value"])
        else: cur[last] = e["value"]
    else:
        del cur[int(last) if isinstance(cur, list) else last]
    p.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")


def resolve(doc, pointer):
    cur = doc
    for t in [unescape(t) for t in pointer.split("/")[1:]]:
        if isinstance(cur, list): cur = cur[int(t)] if t.isdigit() and int(t) < len(cur) else None
        elif isinstance(cur, dict): cur = cur.get(t)
        else: return None
        if cur is None: return None
    return cur


def run(case):
    tmp = Path(tempfile.mkdtemp())
    try:
        proj = tmp / "demo"; plug = tmp / "fishing"
        shutil.copytree(BASE / case.get("project", "demo-project"), proj)
        shutil.copytree(BASE / "fishing-plugin", plug)
        for e in case.get("edits", []): apply_edit(proj, e)
        bundle, locales, plugins, _ = cb.compile_project(proj, [plug], case.get("edition"))
        got = {"content_hash": bundle["content_hash"],
               "locales": {k: cb.sri(cb.jcs(v).encode("utf-8")) for k, v in sorted(locales.items())},
               "plugins": cb.sri(cb.jcs(plugins).encode("utf-8"))}
        return got, bundle
    finally:
        shutil.rmtree(tmp)


def main(argv):
    data = json.loads(CASES.read_text(encoding="utf-8"))
    fails = 0
    for c in data["cases"]:
        got, bundle = run(c)
        exp = c["expect"]
        bad = [k for k in ("content_hash", "locales", "plugins") if k in exp and exp[k] != got[k]]
        bad += [f"present {p}" for p in exp.get("present", []) if resolve(bundle, p) is None]
        bad += [f"absent {p}" for p in exp.get("absent", []) if resolve(bundle, p) is not None]
        if "--print" in argv: print(c["id"], json.dumps(got))
        print(f"{'ok     ' if not bad else 'FALHOU '} {c['id']}: {c['description']}")
        for b in bad: print("          ", b)
        fails += bool(bad)
    n = len(data["cases"])
    print(f"\n{n - fails}/{n} vetores de compilação conferem.")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
